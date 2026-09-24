import CodometerCore
import Darwin
import Foundation

/// Reads the snapshot the app writes to `~/Library/Application Support/Codometer/Widget/snapshot.json`.
///
/// The extension is sandboxed; its entitlements grant read-only access to exactly that folder of the real home
/// directory. The read refuses symlinks and anything but a regular file, and never reads more than
/// `WidgetSnapshot.maximumFileBytes`.
public struct SnapshotFileReader: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// The reader for the current user's real home directory, which differs from the sandbox container's
    /// `NSHomeDirectory()`: from the account database, else derived from the container path.
    public static func standard() -> SnapshotFileReader? {
        guard let home = realHomeDirectory() ?? homeOutsideContainer(NSHomeDirectory()) else { return nil }
        let url = URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent(WidgetSnapshot.homeRelativeDirectory, isDirectory: true)
            .appendingPathComponent(WidgetSnapshot.fileName, isDirectory: false)
        return SnapshotFileReader(fileURL: url)
    }

    /// The decoded snapshot, or `nil` when the file is missing, not a regular file, too large or unreadable.
    public func load() -> WidgetSnapshot? {
        read().snapshot
    }

    /// The snapshot, or why there is none, for the extension's diagnostics.
    public func read() -> SnapshotReadResult {
        switch readFile() {
        case .success(let data):
            guard let snapshot = WidgetSnapshot.decode(data) else { return .invalid }
            return .loaded(snapshot)
        case .failure(.missing):
            return .missing
        case .failure(.denied):
            return .denied
        case .failure(.invalid):
            return .invalid
        }
    }

    func readBounded() -> Data? {
        try? readFile().get()
    }

    private func readFile() -> Result<Data, FileFailure> {
        let limit = WidgetSnapshot.maximumFileBytes
        let descriptor = open(fileURL.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            switch errno {
            case ENOENT, ENOTDIR: return .failure(.missing)
            case EACCES, EPERM: return .failure(.denied)
            default: return .failure(.invalid)
            }
        }
        defer { close(descriptor) }

        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_size <= off_t(limit) else {
            return .failure(.invalid)
        }
        // One byte past the limit, so a file that grew after `fstat` is still refused.
        var buffer = [UInt8](repeating: 0, count: limit + 1)
        var total = 0
        while total < buffer.count {
            let count = buffer.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return 0 }
                return Darwin.read(descriptor, base.advanced(by: total), raw.count - total)
            }
            if count < 0 {
                if errno == EINTR { continue }
                return .failure(errno == EACCES || errno == EPERM ? .denied : .invalid)
            }
            if count == 0 { break }
            total += count
        }
        guard total > 0, total <= limit else { return .failure(.invalid) }
        return .success(Data(buffer.prefix(total)))
    }

    private enum FileFailure: Error {
        case missing, denied, invalid
    }

    /// A sandboxed process's `NSHomeDirectory()` is `<home>/Library/Containers/<bundle id>/Data`; this recovers `<home>`.
    /// A path outside a container is already the home directory.
    static func homeOutsideContainer(_ path: String) -> String? {
        guard path.hasPrefix("/") else { return nil }
        guard let range = path.range(of: "/Library/Containers/", options: .backwards) else { return path }
        let home = String(path[..<range.lowerBound])
        return home.isEmpty ? nil : home
    }

    static func realHomeDirectory() -> String? {
        var record = passwd()
        var result: UnsafeMutablePointer<passwd>?
        let suggested = sysconf(Int32(_SC_GETPW_R_SIZE_MAX))
        var scratch = [CChar](repeating: 0, count: suggested > 0 ? Int(suggested) : 4_096)
        let status = scratch.withUnsafeMutableBufferPointer { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return ERANGE }
            return getpwuid_r(getuid(), &record, base, buffer.count, &result)
        }
        guard status == 0, result != nil, let directory = record.pw_dir else { return nil }
        let path = String(cString: directory)
        return path.hasPrefix("/") ? path : nil
    }
}

/// The outcome of reading the snapshot file. The failure cases carry no path or content, so they can be logged.
public enum SnapshotReadResult: Sendable {
    case loaded(WidgetSnapshot)
    /// No file yet: the app has not published, or the export is turned off.
    case missing
    /// The sandbox refused the read: the extension's entitlements or signature are wrong.
    case denied
    /// Not a regular file, too large, unreadable or not a valid snapshot.
    case invalid
    /// The real home directory could not be determined.
    case noHome

    public var snapshot: WidgetSnapshot? {
        if case .loaded(let snapshot) = self { return snapshot }
        return nil
    }

    /// A stable one-word name for logs.
    public var name: String {
        switch self {
        case .loaded: "loaded"
        case .missing: "missing"
        case .denied: "denied"
        case .invalid: "invalid"
        case .noHome: "noHome"
        }
    }
}
