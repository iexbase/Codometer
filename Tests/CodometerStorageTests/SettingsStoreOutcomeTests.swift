import CodometerCore
import CodometerPlatform
import CodometerStorage
import Darwin
import Foundation
import Testing

@Suite("Settings store outcomes")
struct SettingsStoreOutcomeTests {
    private static let accountID = "8C8E4A0E-3B1A-4C7B-9D5E-000000000001"

    /// One valid account and one with a relative directory; the appearance scale is out of range.
    private static let damaged = """
    {"schemaVersion":1,
     "accounts":[{"id":"\(accountID)","provider":"codex","label":"Codex","directory":"/tmp/.codex"},
                 {"id":"8C8E4A0E-3B1A-4C7B-9D5E-000000000002","provider":"claude","label":"Broken","directory":"relative"}],
     "appearance":{"scale":9}}
    """

    private static let newer = """
    {"schemaVersion":2,"accounts":[{"id":"\(accountID)","provider":"codex","label":"Codex","directory":"/tmp/.codex"}],
     "appearance":{"edge":"left","presentationStyle":"hologram"},"futureKey":true}
    """

    private func write(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url)
    }

    private func names(in directory: TemporaryDirectory) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.url.path).sorted()
    }

    private func mode(of url: URL) -> mode_t {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return 0 }
        return info.st_mode & 0o777
    }

    @Test("A repairable file loads with its repairs, keeps the original as a backup and is rewritten clean")
    func repairedFileIsBackedUpAndRewritten() throws {
        let directory = try TemporaryDirectory()
        let file = directory.file("settings.json")
        try write(Self.damaged, to: file)
        let store = SettingsStore(fileURL: file)

        guard case let .loaded(settings, repairs) = store.load() else {
            Issue.record("expected .loaded")
            return
        }
        #expect(settings.accounts.map(\.label.value) == ["Codex"])
        #expect(settings.appearance.scale == .standard)
        #expect(Set(repairs) == ["accounts[1]", "appearance.scale"])

        let backups = try names(in: directory).filter { $0.hasPrefix("settings.backup-repair-") }
        #expect(backups.count == 1)
        let backup = directory.file(try #require(backups.first))
        #expect(try String(contentsOf: backup, encoding: .utf8) == Self.damaged)
        #expect(mode(of: backup) == 0o600)

        // The rewritten file loads without repairs and writes no further backup.
        guard case let .loaded(again, againRepairs) = store.load() else {
            Issue.record("expected .loaded on the second load")
            return
        }
        #expect(again == settings)
        #expect(againRepairs.isEmpty)
        #expect(try names(in: directory).filter { $0.hasPrefix("settings.backup-") }.count == 1)
    }

    @Test("A newer file loads read-only, is never saved over and gets no backup")
    func newerFileIsReadOnly() throws {
        let directory = try TemporaryDirectory()
        let file = directory.file("settings.json")
        try write(Self.newer, to: file)
        let store = SettingsStore(fileURL: file)

        guard case let .readOnly(settings, version) = store.load() else {
            Issue.record("expected .readOnly")
            return
        }
        #expect(version == 2)
        #expect(settings.accounts.count == 1)
        #expect(settings.appearance.edge == .left)
        #expect(settings.appearance.presentationStyle == .island)

        #expect(throws: SettingsStoreError.newerSchema(version: 2)) { try store.save(settings) }
        #expect(try String(contentsOf: file, encoding: .utf8) == Self.newer)
        #expect(try names(in: directory) == ["settings.json"])
    }

    @Test("Unusable files are moved aside, and at most five moved-aside files are kept")
    func invalidFilesArePruned() throws {
        let directory = try TemporaryDirectory()
        let file = directory.file("settings.json")
        let store = SettingsStore(fileURL: file)
        // Older moved-aside files from earlier launches, oldest first.
        for index in 0..<6 {
            let old = directory.file("settings.invalid-100000000\(index).json")
            try write("old \(index)", to: old)
            let date = Date(timeIntervalSince1970: 1_000_000_000 + Double(index))
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: old.path)
        }
        try write("definitely not json", to: file)

        guard case let .recovered(backupPath, _) = store.load() else {
            Issue.record("expected .recovered")
            return
        }
        let invalid = try names(in: directory).filter { $0.hasPrefix("settings.invalid-") }
        #expect(invalid.count == SettingsStore.maximumInvalidBackups)
        #expect(invalid.contains((backupPath as NSString).lastPathComponent))
        #expect(!invalid.contains("settings.invalid-1000000000.json"))
        #expect(!invalid.contains("settings.invalid-1000000001.json"))
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("Oversized and non-regular settings files are recovered, and a symlink target is never touched")
    func unreadableFiles() throws {
        let directory = try TemporaryDirectory()
        let file = directory.file("settings.json")
        try Data(repeating: 0x20, count: SettingsStore.maximumBytes + 1).write(to: file)
        guard case .recovered = SettingsStore(fileURL: file).load() else {
            Issue.record("expected .recovered for an oversized file")
            return
        }

        let target = directory.file("elsewhere.json")
        try write(#"{"schemaVersion":1}"#, to: target)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
        guard case .recovered = SettingsStore(fileURL: file).load() else {
            Issue.record("expected .recovered for a symlink")
            return
        }
        #expect(try String(contentsOf: target, encoding: .utf8) == #"{"schemaVersion":1}"#)
    }

    @Test("Version backups copy the file with 0600 and keep the newest three; repair backups keep five")
    func backupsArePruned() throws {
        let directory = try TemporaryDirectory()
        let file = directory.file("settings.json")
        let store = SettingsStore(fileURL: file)
        try store.save(try AppSettings(accounts: []))
        let contents = try Data(contentsOf: file)

        var written: [URL] = []
        for (index, tag) in ["0.7.0", "0.8.0", "0.9.0", "0.9.1", "1.0.0"].enumerated() {
            let url = try store.backup(tag: tag)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: 1_000_000_000 + Double(index))],
                ofItemAtPath: url.path
            )
            written.append(url)
        }
        #expect(written.last?.lastPathComponent == "settings.backup-1.0.0.json")
        #expect(try Data(contentsOf: try #require(written.last)) == contents)
        #expect(mode(of: try #require(written.last)) == 0o600)

        for index in 0..<7 {
            let url = try store.backup(tag: "repair-\(1_000_000_000 + index)")
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: 1_000_000_000 + Double(index))],
                ofItemAtPath: url.path
            )
        }
        let all = try names(in: directory)
        let versions = all.filter { $0.hasPrefix("settings.backup-") && !$0.hasPrefix("settings.backup-repair-") }
        #expect(versions == ["settings.backup-0.9.0.json", "settings.backup-0.9.1.json", "settings.backup-1.0.0.json"])
        let repairs = all.filter { $0.hasPrefix("settings.backup-repair-") }
        #expect(repairs.count == SettingsStore.maximumInvalidBackups)
        #expect(!repairs.contains("settings.backup-repair-1000000000.json"))
        #expect(repairs.contains("settings.backup-repair-1000000006.json"))
    }

    @Test("Backup tags are validated and a missing file cannot be backed up")
    func backupErrors() throws {
        let directory = try TemporaryDirectory()
        let store = SettingsStore(fileURL: directory.file("settings.json"))
        #expect(throws: SettingsStoreError.writeFailed(.notFound(path: directory.file("settings.json").path))) {
            try store.backup(tag: "1.0.0")
        }
        try store.save(.empty)
        for tag in ["", "../escape", "a b", String(repeating: "x", count: 65)] {
            #expect(throws: SettingsStoreError.invalidBackupTag) { try store.backup(tag: tag) }
        }
        #expect(try names(in: directory) == ["settings.json"])
    }

    @Test("A repair backup with the same contents is reused instead of writing another")
    func identicalRepairBackupIsReused() throws {
        let directory = try TemporaryDirectory()
        let file = directory.file("settings.json")
        try write(Self.damaged, to: file)
        try write(Self.damaged, to: directory.file("settings.backup-repair-1000000000.json"))
        guard case let .loaded(_, repairs) = SettingsStore(fileURL: file).load() else {
            Issue.record("expected .loaded")
            return
        }
        #expect(!repairs.isEmpty)
        #expect(try names(in: directory) == ["settings.backup-repair-1000000000.json", "settings.json"])
        #expect(try String(contentsOf: file, encoding: .utf8) != Self.damaged)
    }

    @Test("When no backup can be written, the original file is left untouched")
    func failedBackupKeepsOriginal() throws {
        let directory = try TemporaryDirectory()
        let file = directory.file("settings.json")
        try write(Self.damaged, to: file)
        // A read-only folder: the backup fails, so the repaired settings must not replace the file.
        chmod(directory.url.path, 0o500)
        defer { chmod(directory.url.path, 0o700) }
        let store = SettingsStore(fileURL: file)
        for _ in 0..<2 {
            guard case let .loaded(settings, repairs) = store.load() else {
                Issue.record("expected .loaded")
                return
            }
            #expect(!repairs.isEmpty)
            #expect(settings.accounts.count == 1)
        }
        #expect(try String(contentsOf: file, encoding: .utf8) == Self.damaged)
        #expect(try names(in: directory) == ["settings.json"])
    }
}
