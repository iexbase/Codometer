import CodometerCore
import CodometerPlatform
import Foundation

public enum SettingsLoadOutcome: Sendable {
    /// The file loaded. When `repairs` is not empty, the original file was first copied to
    /// `settings.backup-repair-<timestamp>.json` and then replaced by the repaired settings.
    case loaded(AppSettings, repairs: [String])
    /// Written by a newer build (`schemaVersion` above the current one): its known keys loaded, and the file is never
    /// saved over (`save` refuses).
    case readOnly(AppSettings, fileSchemaVersion: Int)
    /// No settings file existed yet.
    case missing
    /// The file was not JSON, not an object, too large or unreadable; it was moved aside and defaults are used.
    case recovered(backupPath: String, reason: String)
}

public enum SettingsStoreError: Error, Equatable, Sendable, CustomStringConvertible {
    case encodingFailed(String)
    case writeFailed(FileAccessError)
    /// The file on disk was written by a newer Codometer and is never saved over.
    case newerSchema(version: Int)
    /// Backup tags are `[A-Za-z0-9._-]`, 1–64 characters.
    case invalidBackupTag

    public var description: String {
        switch self {
        case .encodingFailed(let reason): "could not encode settings: \(reason)"
        case .writeFailed(let error): "could not save settings: \(error.description)"
        case .newerSchema(let version): "settings were written by a newer Codometer (schema \(version)); not saved"
        case .invalidBackupTag: "invalid settings backup tag"
        }
    }

    /// The failure without file paths or setting values: safe for public log output.
    public var summary: String {
        switch self {
        case .encodingFailed: "could not encode settings"
        case .writeFailed(let error): "could not save settings: \(error.summary)"
        case .newerSchema, .invalidBackupTag: description
        }
    }
}

/// Loads and saves `settings.json`. Every load fully re-validates the file, so a hand-edited or
/// corrupted file can never put the app into an invalid state.
///
/// Loading is lenient: a value that is unusable falls back to its default and a broken account or group drops only
/// itself; the original file is kept as a repair backup before the repaired settings replace it. Only a file that is
/// not a JSON object at all is moved aside.
public struct SettingsStore: Sendable {
    public static let maximumBytes = 1_024 * 1_024
    /// `settings.invalid-*.json` files (moved-aside files) and `settings.backup-repair-*.json` files kept, each.
    public static let maximumInvalidBackups = 5
    /// Other `settings.backup-<tag>.json` files (pre-upgrade copies such as `settings.backup-0.9.0.json`) kept.
    public static let maximumVersionBackups = 3

    static let invalidPrefix = "settings.invalid-"
    static let backupPrefix = "settings.backup-"
    static let repairTagPrefix = "repair-"

    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    private var directory: URL { fileURL.deletingLastPathComponent() }

    public func load() -> SettingsLoadOutcome {
        let data: Data
        do {
            data = try SecureFileIO.readRegularFile(at: fileURL, maximumBytes: Self.maximumBytes)
        } catch {
            if case .notFound = error { return .missing }
            return moveAside(reason: error.description)
        }
        let file: DecodedSettingsFile
        do {
            file = try AppSettings.decodeFile(data)
        } catch {
            return moveAside(reason: String(describing: error))
        }
        if file.isReadOnly {
            return .readOnly(file.settings, fileSchemaVersion: file.schemaVersion)
        }
        if !file.repairs.isEmpty {
            repair(file.settings, original: data)
        }
        return .loaded(file.settings, repairs: file.repairs)
    }

    /// Refuses to replace a file that a newer build wrote (`newerSchema`).
    public func save(_ settings: AppSettings) throws(SettingsStoreError) {
        if let version = newerSchemaVersionOnDisk() {
            throw .newerSchema(version: version)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(settings)
        } catch {
            throw .encodingFailed(String(describing: error))
        }
        do throws(FileAccessError) {
            try SecureFileIO.writeAtomically(data, to: fileURL)
        } catch {
            throw .writeFailed(error)
        }
    }

    /// Copies the current settings file to `settings.backup-<tag>.json` (0600, replacing an older copy with the same
    /// tag) and prunes old backups: repair backups (`repair-…` tags) to `maximumInvalidBackups`, others to
    /// `maximumVersionBackups`.
    @discardableResult
    public func backup(tag: String) throws(SettingsStoreError) -> URL {
        guard (try? StableIdentifier.validate(tag, field: "settings.backupTag")) != nil else { throw .invalidBackupTag }
        let data: Data
        do throws(FileAccessError) {
            data = try SecureFileIO.readRegularFile(at: fileURL, maximumBytes: Self.maximumBytes)
        } catch {
            throw .writeFailed(error)
        }
        let url = directory.appendingPathComponent("\(Self.backupPrefix)\(tag).json", isDirectory: false)
        do throws(FileAccessError) {
            try SecureFileIO.writeAtomically(data, to: url)
        } catch {
            throw .writeFailed(error)
        }
        let isRepair = tag.hasPrefix(Self.repairTagPrefix)
        prune(
            keeping: isRepair ? Self.maximumInvalidBackups : Self.maximumVersionBackups,
            where: { name in
                guard name.hasPrefix(Self.backupPrefix), name.hasSuffix(".json") else { return false }
                return name.dropFirst(Self.backupPrefix.count).hasPrefix(Self.repairTagPrefix) == isRepair
            },
            protecting: url.lastPathComponent
        )
        return url
    }

    // MARK: - Private

    /// Keeps the original as a repair backup, then writes the repaired settings. When the backup fails the file is
    /// left untouched (it is still repaired in memory, and replaced on the next save).
    private func repair(_ settings: AppSettings, original: Data) {
        if let newest = newestRepairBackup(), (try? SecureFileIO.readRegularFile(at: newest, maximumBytes: Self.maximumBytes)) == original {
            // The same broken file as last time: that backup already holds it.
        } else {
            let stamp = Int(Date().timeIntervalSince1970)
            do throws(SettingsStoreError) {
                try backup(tag: "\(Self.repairTagPrefix)\(stamp)")
            } catch {
                return
            }
        }
        try? save(settings)
    }

    private func newestRepairBackup() -> URL? {
        backups(where: { $0.hasPrefix(Self.backupPrefix + Self.repairTagPrefix) && $0.hasSuffix(".json") }).first
    }

    /// The settings file's declared `schemaVersion` when it is above the current one.
    private func newerSchemaVersionOnDisk() -> Int? {
        guard
            let data = try? SecureFileIO.readRegularFile(at: fileURL, maximumBytes: Self.maximumBytes),
            let probe = try? JSONDecoder().decode(SchemaVersionProbe.self, from: data),
            let version = probe.schemaVersion,
            version > AppSettings.currentSchemaVersion
        else { return nil }
        return version
    }

    private func moveAside(reason: String) -> SettingsLoadOutcome {
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = directory.appendingPathComponent("\(Self.invalidPrefix)\(stamp).json", isDirectory: false)
        do {
            try FileManager.default.moveItem(at: fileURL, to: backup)
        } catch {
            return .recovered(backupPath: "", reason: reason)
        }
        prune(
            keeping: Self.maximumInvalidBackups,
            where: { $0.hasPrefix(Self.invalidPrefix) && $0.hasSuffix(".json") },
            protecting: backup.lastPathComponent
        )
        return .recovered(backupPath: backup.path, reason: reason)
    }

    /// Backup files matching `matches`, newest first (by modification time, then name).
    private func backups(where matches: (String) -> Bool) -> [URL] {
        let names = ((try? SecureFileIO.regularFileNames(in: directory)) ?? []).filter(matches)
        var entries: [BackupEntry] = []
        for name in names {
            let url = directory.appendingPathComponent(name, isDirectory: false)
            entries.append(BackupEntry(url: url, modified: SecureFileIO.metadata(at: url)?.modifiedAt ?? .distantPast))
        }
        entries.sort(by: BackupEntry.isNewer)
        return entries.map(\.url)
    }

    /// Deletes the oldest matching backups beyond `count`; never the one just written.
    private func prune(keeping count: Int, where matches: (String) -> Bool, protecting protected: String) {
        let ordered = backups(where: matches)
        let others = ordered.filter { $0.lastPathComponent != protected }
        for url in others.dropFirst(max(0, count - 1)) {
            unlink(url.path)
        }
    }
}

private struct BackupEntry {
    let url: URL
    let modified: Date

    static func isNewer(_ lhs: BackupEntry, _ rhs: BackupEntry) -> Bool {
        if lhs.modified != rhs.modified { return lhs.modified > rhs.modified }
        return lhs.url.lastPathComponent > rhs.url.lastPathComponent
    }
}

/// Reads only `schemaVersion`, tolerating anything else in the file.
private struct SchemaVersionProbe: Decodable {
    let schemaVersion: Int?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try? container.decodeIfPresent(Int.self, forKey: .schemaVersion)
    }
}
