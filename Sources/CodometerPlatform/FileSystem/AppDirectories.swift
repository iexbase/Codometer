import CodometerCore
import Darwin
import Foundation
import os

/// The app's private storage under `~/Library/Application Support/Codometer`, or an isolated root named by
/// `CODOMETER_DATA_ROOT` for development and verification runs.
public struct AppDirectories: Sendable {
    public let root: URL
    /// Whether `root` came from an accepted `CODOMETER_DATA_ROOT`. An isolated instance exports no widget snapshot,
    /// posts no notifications, never changes the login item and registers no global shortcut on its own.
    public let isIsolated: Bool
    public init(root: URL, isIsolated: Bool = false) {
        self.root = root
        self.isIsolated = isIsolated
    }

    public var settingsFile: URL { root.appendingPathComponent("settings.json", isDirectory: false) }
    public var historyDatabase: URL { root.appendingPathComponent("history.sqlite", isDirectory: false) }
    /// A fixed, empty working directory for CLI probes, so they never create per-run project state.
    public var probeWorkingDirectory: URL { root.appendingPathComponent("probe", isDirectory: true) }
    /// Locally kept crash and hang diagnostics (MetricKit payloads) that Diagnostics lists. Created by their writer.
    public var diagnosticsDirectory: URL { root.appendingPathComponent("Diagnostics", isDirectory: true) }
    /// The single-instance lock file, taken after `prepare()`.
    public var instanceLockFile: URL { root.appendingPathComponent(".lock", isDirectory: false) }

    /// Creates all directories with owner-only permissions.
    public func prepare() throws(FileAccessError) {
        try SecureFileIO.ensurePrivateDirectory(at: root)
        try SecureFileIO.ensurePrivateDirectory(at: probeWorkingDirectory)
    }
}

extension AppDirectories {
    /// The data folder's name under Application Support.
    public static let folderName = "Codometer"
    /// Names an isolated data root (development and verification runs only).
    public static let dataRootVariable = "CODOMETER_DATA_ROOT"

    /// The data root for this process.
    ///
    /// `CODOMETER_DATA_ROOT`: absolute, standardized, no symlink components, strictly under `~/Library/Caches/` or
    /// `NSTemporaryDirectory()`. A value that breaks these rules is logged and refused with an error rather than
    /// ignored, so a mistyped override never falls back to the real data.
    public static func standard(environment: [String: String]) throws(FileAccessError) -> AppDirectories {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw .notFound(path: "~/Library/Application Support")
        }
        let prefixes = overridePrefixes(homeDirectory: NSHomeDirectory(), temporaryDirectory: NSTemporaryDirectory())

        if let value = environment[dataRootVariable] {
            let root: URL
            switch validatedOverride(value, allowedPrefixes: prefixes) {
            case .success(let accepted):
                root = accepted
            case .failure(let refusal):
                AppLog.storage.error("\(dataRootVariable, privacy: .public) refused: \(refusal.reason, privacy: .public) (\(value, privacy: .private))")
                throw .permissionDenied(path: value)
            }
            AppLog.storage.notice("isolated data root (\(root.path, privacy: .private))")
            return AppDirectories(root: root, isIsolated: true)
        }

        return AppDirectories(root: support.appendingPathComponent(folderName, isDirectory: true), isIsolated: false)
    }

    // MARK: - Helpers

    private static func entryName(_ entry: UnsafeMutablePointer<dirent>) -> String {
        withUnsafePointer(to: entry.pointee.d_name) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) {
                String(cString: $0)
            }
        }
    }
}

// MARK: - Data root override validation

/// Why a data root override was refused; the text is safe for public log output (it never contains the path).
struct DataRootRefusal: Error, Equatable {
    let reason: String
}

extension AppDirectories {
    /// The folders an override may live in, without trailing slashes: `~/Library/Caches` and the temporary
    /// directory, the latter also in its symlink-resolved form (`/var/folders/…` is `/private/var/folders/…`).
    static func overridePrefixes(homeDirectory: String, temporaryDirectory: String) -> [String] {
        var prefixes: [String] = []
        if let home = standardizedAbsolutePath(homeDirectory) {
            prefixes.append(home == "/" ? "/Library/Caches" : home + "/Library/Caches")
        }
        if let temporary = standardizedAbsolutePath(temporaryDirectory) {
            prefixes.append(temporary)
            if let resolved = resolvedPath(temporary), resolved != temporary {
                prefixes.append(resolved)
            }
        }
        return prefixes.filter { $0 != "/" }
    }

    /// Accepts an absolute path that, once standardized, lies strictly below one of `allowedPrefixes` and has no
    /// symbolic link among its existing components.
    static func validatedOverride(_ value: String, allowedPrefixes: [String]) -> Result<URL, DataRootRefusal> {
        guard let path = standardizedAbsolutePath(value) else {
            return .failure(DataRootRefusal(reason: "not an absolute path"))
        }
        guard allowedPrefixes.contains(where: { path.hasPrefix($0 + "/") }) else {
            return .failure(DataRootRefusal(reason: "not under ~/Library/Caches or the temporary directory"))
        }
        var current = ""
        var info = stat()
        for component in path.split(separator: "/") {
            current += "/" + component
            guard lstat(current, &info) == 0 else {
                if errno == ENOENT || errno == ENOTDIR { break }
                return .failure(DataRootRefusal(reason: "a path component cannot be inspected (errno \(errno))"))
            }
            if (info.st_mode & S_IFMT) == S_IFLNK {
                return .failure(DataRootRefusal(reason: "a path component is a symbolic link"))
            }
        }
        return .success(URL(fileURLWithPath: path, isDirectory: true))
    }

    /// Lexical standardization: removes empty and `.` components and applies `..` (never above `/`); `nil` for a
    /// relative or empty path, or one containing a NUL character.
    static func standardizedAbsolutePath(_ value: String) -> String? {
        guard value.hasPrefix("/"), !value.contains("\0") else { return nil }
        var components: [Substring] = []
        for component in value.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".": continue
            case "..": if !components.isEmpty { components.removeLast() }
            default: components.append(component)
            }
        }
        return "/" + components.joined(separator: "/")
    }

    private static func resolvedPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}

// MARK: - Erase all data

extension AppDirectories {
    /// Folders inside the data root the app creates and may remove, one level deep only.
    static let erasableDirectoryNames = ["Widget", "probe", "Diagnostics"]
    /// Files inside the data root the app creates, by exact name.
    static let erasableFileNames = [
        "settings.json",
        "history.sqlite", "history.sqlite-wal", "history.sqlite-shm", "history.sqlite-journal",
        ".lock",
    ]
    /// Files inside the data root the app creates with a timestamp or tag in the name.
    static let erasableFilePrefixes = ["settings.invalid-", "settings.backup-", "history.corrupt-"]
    /// Leftovers of an interrupted export inside the data root.
    static let erasableFileSuffixes = [".partial", ".tmp"]
    /// Where macOS keeps a window's saved state, relative to the home folder.
    static let savedStateFolder = "Library/Saved Application State"

    /// Removes every file the app created inside the data root, then the root itself, plus the app's saved window
    /// state when `bundleIdentifier` names it.
    ///
    /// Only names the app writes are removed, one level deep in `Widget/`, `probe/` and `Diagnostics/`; anything
    /// else is left alone and counted, which also keeps the root in place. Symbolic links are never followed or
    /// removed, and a symlinked root is refused outright. The database must be closed first
    /// (`TrackerEngine.prepareForErase`).
    public func eraseAll(bundleIdentifier: String?) throws(FileAccessError) -> EraseSummary {
        try eraseAll(
            bundleIdentifier: bundleIdentifier,
            savedStateParent: URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent(Self.savedStateFolder, isDirectory: true)
        )
    }

    /// `eraseAll(bundleIdentifier:)` with the saved-state folder injected, so tests never touch the real one.
    func eraseAll(bundleIdentifier: String?, savedStateParent: URL?) throws(FileAccessError) -> EraseSummary {
        var tally = EraseTally()
        switch Self.entryKind(at: root.path) {
        case .missing:
            break
        case .symbolicLink:
            throw .notRegularFile(path: root.path)
        case .directory:
            try eraseRoot(into: &tally)
        case .regularFile, .other:
            throw .notRegularFile(path: root.path)
        }
        if let savedStateParent, let name = Self.savedStateName(for: bundleIdentifier) {
            eraseDirectory(at: savedStateParent.appendingPathComponent(name, isDirectory: true), into: &tally)
        }
        return tally.summary
    }

    // MARK: - Private

    /// Counts while erasing; unknown entries are reported as failures, because the erase was not complete.
    struct EraseTally {
        var removed = 0
        var refusedSymlinks = 0
        var failures = 0
        var unknown = 0

        var isClean: Bool { refusedSymlinks == 0 && failures == 0 && unknown == 0 }

        var summary: EraseSummary {
            EraseSummary(removedItems: removed, refusedSymlinks: refusedSymlinks, failures: failures + unknown)
        }
    }

    private enum EntryKind {
        case missing, symbolicLink, directory, regularFile, other
    }

    private func eraseRoot(into tally: inout EraseTally) throws(FileAccessError) {
        guard let handle = opendir(root.path) else { throw .from(errno: errno, path: root.path) }
        var names: [String] = []
        while let entry = readdir(handle) {
            let name = Self.entryName(entry)
            guard name != ".", name != ".." else { continue }
            names.append(name)
        }
        closedir(handle)

        for name in names.sorted() {
            let path = root.path + "/" + name
            switch Self.entryKind(at: path) {
            case .missing:
                continue
            case .symbolicLink:
                tally.refusedSymlinks += 1
            case .regularFile:
                if Self.isErasableFile(name) {
                    Self.unlink(path, into: &tally)
                } else {
                    tally.unknown += 1
                }
            case .directory:
                if Self.erasableDirectoryNames.contains(name) {
                    eraseDirectory(at: root.appendingPathComponent(name, isDirectory: true), into: &tally)
                } else {
                    tally.unknown += 1
                }
            case .other:
                tally.unknown += 1
            }
        }
        guard tally.isClean else { return }
        if rmdir(root.path) == 0 {
            tally.removed += 1
        } else if errno != ENOENT {
            tally.failures += 1
        }
    }

    /// Removes the regular files directly inside `directory` and then the directory, one level only.
    private func eraseDirectory(at directory: URL, into tally: inout EraseTally) {
        switch Self.entryKind(at: directory.path) {
        case .directory: break
        case .symbolicLink:
            tally.refusedSymlinks += 1
            return
        case .missing, .regularFile, .other:
            return
        }
        guard let handle = opendir(directory.path) else {
            tally.failures += 1
            return
        }
        var names: [String] = []
        while let entry = readdir(handle) {
            let name = Self.entryName(entry)
            guard name != ".", name != ".." else { continue }
            names.append(name)
        }
        closedir(handle)

        var leftovers = false
        for name in names.sorted() {
            let path = directory.path + "/" + name
            switch Self.entryKind(at: path) {
            case .missing:
                continue
            case .symbolicLink:
                tally.refusedSymlinks += 1
                leftovers = true
            case .regularFile:
                if !Self.unlink(path, into: &tally) {
                    leftovers = true
                }
            case .directory, .other:
                // Never recurse into something the app did not create.
                tally.unknown += 1
                leftovers = true
            }
        }
        guard !leftovers else { return }
        if rmdir(directory.path) == 0 {
            tally.removed += 1
        } else if errno != ENOENT {
            tally.failures += 1
        }
    }

    @discardableResult
    private static func unlink(_ path: String, into tally: inout EraseTally) -> Bool {
        if Darwin.unlink(path) == 0 {
            tally.removed += 1
            return true
        }
        if errno == ENOENT { return true }
        tally.failures += 1
        return false
    }

    private static func entryKind(at path: String) -> EntryKind {
        var info = stat()
        guard lstat(path, &info) == 0 else { return .missing }
        return switch info.st_mode & S_IFMT {
        case S_IFLNK: .symbolicLink
        case S_IFDIR: .directory
        case S_IFREG: .regularFile
        default: .other
        }
    }

    static func isErasableFile(_ name: String) -> Bool {
        if erasableFileNames.contains(name) { return true }
        if erasableFilePrefixes.contains(where: { name.hasPrefix($0) && name.count > $0.count }) { return true }
        return erasableFileSuffixes.contains { name.hasSuffix($0) && name.count > $0.count }
    }

    /// `<bundle id>.savedState`, or `nil` when the identifier could name something outside that folder.
    static func savedStateName(for bundleIdentifier: String?) -> String? {
        guard
            let identifier = bundleIdentifier,
            !identifier.isEmpty,
            identifier.count <= 255,
            !identifier.contains("/"),
            !identifier.contains("\0"),
            identifier != ".",
            identifier != ".."
        else { return nil }
        return identifier + ".savedState"
    }
}
