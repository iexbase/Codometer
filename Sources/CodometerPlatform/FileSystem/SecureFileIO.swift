import Darwin
import Foundation

public enum FileAccessError: Error, Equatable, Sendable, CustomStringConvertible {
    case notFound(path: String)
    case notRegularFile(path: String)
    case tooLarge(path: String, size: UInt64, limit: UInt64)
    case permissionDenied(path: String)
    case ioFailure(path: String, code: Int32)

    public var description: String {
        switch self {
        case .notFound(let path): "file not found: \(path)"
        case .notRegularFile(let path): "not a regular file (symlinks are refused): \(path)"
        case let .tooLarge(path, size, limit): "file too large (\(size) > \(limit) bytes): \(path)"
        case .permissionDenied(let path): "permission denied: \(path)"
        case let .ioFailure(path, code): "I/O error \(code) (\(String(cString: strerror(code)))): \(path)"
        }
    }

    /// The failure without its path, which names the user's home folder: safe for public log output.
    public var summary: String {
        switch self {
        case .notFound: "file not found"
        case .notRegularFile: "not a regular file (symlinks are refused)"
        case let .tooLarge(_, size, limit): "file too large (\(size) > \(limit) bytes)"
        case .permissionDenied: "permission denied"
        case let .ioFailure(_, code): "I/O error \(code) (\(String(cString: strerror(code))))"
        }
    }

    static func from(errno code: Int32, path: String) -> FileAccessError {
        switch code {
        case ENOENT, ENOTDIR: .notFound(path: path)
        case ELOOP: .notRegularFile(path: path)
        case EACCES, EPERM: .permissionDenied(path: path)
        default: .ioFailure(path: path, code: code)
        }
    }
}

/// File access that refuses symlinks at the final path component and enforces size limits,
/// so a hostile or corrupted file can neither redirect a read nor exhaust memory.
public enum SecureFileIO {
    /// Reads a whole regular file of at most `maximumBytes`.
    public static func readRegularFile(at url: URL, maximumBytes: Int) throws(FileAccessError) -> Data {
        let path = url.path
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw .from(errno: errno, path: path) }
        defer { close(descriptor) }

        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw .from(errno: errno, path: path) }
        guard (info.st_mode & S_IFMT) == S_IFREG else { throw .notRegularFile(path: path) }
        let size = UInt64(max(info.st_size, 0))
        guard size <= UInt64(maximumBytes) else {
            throw .tooLarge(path: path, size: size, limit: UInt64(maximumBytes))
        }

        // Read one byte past the limit so a file that grew after fstat is still rejected.
        var buffer = [UInt8](repeating: 0, count: maximumBytes + 1)
        var total = 0
        while total < buffer.count {
            let count = buffer.withUnsafeMutableBytes { raw in
                read(descriptor, raw.baseAddress!.advanced(by: total), raw.count - total)
            }
            if count < 0 {
                if errno == EINTR { continue }
                throw .from(errno: errno, path: path)
            }
            if count == 0 { break }
            total += count
        }
        guard total <= maximumBytes else {
            throw .tooLarge(path: path, size: UInt64(total), limit: UInt64(maximumBytes))
        }
        return Data(buffer.prefix(total))
    }

    /// Replaces `url` atomically: the data goes to a private temporary file in the same directory,
    /// is flushed, and is renamed over the destination. Readers never observe a partial file.
    public static func writeAtomically(_ data: Data, to url: URL, permissions: mode_t = 0o600) throws(FileAccessError) {
        let directory = url.deletingLastPathComponent().path
        let temporaryPath = directory + "/.\(url.lastPathComponent).\(UUID().uuidString).tmp"
        let descriptor = open(temporaryPath, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, permissions)
        guard descriptor >= 0 else { throw .from(errno: errno, path: temporaryPath) }

        var succeeded = false
        defer {
            if !succeeded { unlink(temporaryPath) }
        }

        let writeFailure: Int32? = data.withUnsafeBytes { raw -> Int32? in
            var offset = 0
            while offset < raw.count {
                let written = write(descriptor, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    return errno
                }
                offset += written
            }
            return fsync(descriptor) == 0 ? nil : errno
        }
        if let writeFailure {
            close(descriptor)
            throw .from(errno: writeFailure, path: temporaryPath)
        }
        guard close(descriptor) == 0 else { throw .from(errno: errno, path: temporaryPath) }
        guard rename(temporaryPath, url.path) == 0 else { throw .from(errno: errno, path: url.path) }
        succeeded = true
    }

    /// Creates the directory (and parents) if needed and restricts it to the current user.
    public static func ensurePrivateDirectory(at url: URL) throws(FileAccessError) {
        let path = url.path
        do {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw .ioFailure(path: path, code: Int32((error as NSError).code))
        }
        var info = stat()
        guard lstat(path, &info) == 0 else { throw .from(errno: errno, path: path) }
        guard (info.st_mode & S_IFMT) == S_IFDIR else { throw .notRegularFile(path: path) }
        guard chmod(path, 0o700) == 0 else { throw .from(errno: errno, path: path) }
    }

    /// Lists the names of regular files in a directory. Missing directories yield an empty list.
    public static func regularFileNames(in directory: URL) throws(FileAccessError) -> [String] {
        let path = directory.path
        guard let handle = opendir(path) else {
            if errno == ENOENT { return [] }
            throw .from(errno: errno, path: path)
        }
        defer { closedir(handle) }
        var names: [String] = []
        while let entry = readdir(handle) {
            guard entry.pointee.d_type == DT_REG else { continue }
            let name = withUnsafePointer(to: entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) {
                    String(cString: $0)
                }
            }
            names.append(name)
        }
        return names
    }

    /// Creates a new private file, failing when anything already exists at `url` (including a symlink).
    ///
    /// Used for the temporary `.partial` file an export is streamed into before it is renamed into place, so an
    /// export can never write through a symlink or overwrite an existing file.
    public static func createExclusive(at url: URL, permissions: mode_t = 0o600) throws(FileAccessError) -> ExclusiveFile {
        let path = url.path
        let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, permissions)
        guard descriptor >= 0 else { throw .from(errno: errno, path: path) }
        return ExclusiveFile(descriptor: descriptor, url: url)
    }

    /// Removes a regular file, refusing to follow a symlink. `false` when there was nothing to remove.
    @discardableResult
    public static func unlinkRegularFile(at url: URL) throws(FileAccessError) -> Bool {
        let path = url.path
        var info = stat()
        guard lstat(path, &info) == 0 else {
            if errno == ENOENT || errno == ENOTDIR { return false }
            throw .from(errno: errno, path: path)
        }
        guard (info.st_mode & S_IFMT) == S_IFREG else { throw .notRegularFile(path: path) }
        guard unlink(path) == 0 else {
            if errno == ENOENT { return false }
            throw .from(errno: errno, path: path)
        }
        return true
    }

    /// Modification time and size without following a final symlink, or `nil` when absent.
    public static func metadata(at url: URL) -> FileMetadata? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        return FileMetadata(info)
    }
}

public struct FileMetadata: Hashable, Sendable {
    public let identity: FileIdentity
    public let size: UInt64
    public let modifiedAt: Date
    public let isRegularFile: Bool
    public let isDirectory: Bool

    init(_ info: stat) {
        identity = FileIdentity(device: UInt64(bitPattern: Int64(info.st_dev)), inode: UInt64(info.st_ino))
        size = UInt64(max(info.st_size, 0))
        modifiedAt = Date(
            timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)
                + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000
        )
        isRegularFile = (info.st_mode & S_IFMT) == S_IFREG
        isDirectory = (info.st_mode & S_IFMT) == S_IFDIR
    }
}

/// Device and inode: stays the same while a file is appended to, changes when it is replaced.
public struct FileIdentity: Hashable, Sendable {
    public let device: UInt64
    public let inode: UInt64

    public init(device: UInt64, inode: UInt64) {
        self.device = device
        self.inode = inode
    }
}


/// A file created by `SecureFileIO.createExclusive`, written in bounded pieces.
///
/// Not `Sendable`: it belongs to the task that created it. Closing flushes to disk; an unclosed file is closed
/// (without an `fsync`) when the object goes away, and the caller removes the leftover.
public final class ExclusiveFile {
    public let url: URL
    private var descriptor: Int32

    init(descriptor: Int32, url: URL) {
        self.descriptor = descriptor
        self.url = url
    }

    deinit {
        if descriptor >= 0 {
            Darwin.close(descriptor)
        }
    }

    public var isClosed: Bool { descriptor < 0 }

    public func write(_ text: String) throws(FileAccessError) {
        try write(Data(text.utf8))
    }

    public func write(_ data: Data) throws(FileAccessError) {
        guard descriptor >= 0 else { throw .ioFailure(path: url.path, code: EBADF) }
        guard !data.isEmpty else { return }
        let descriptor = descriptor
        let failure: Int32? = data.withUnsafeBytes { raw -> Int32? in
            var offset = 0
            while offset < raw.count {
                let written = Darwin.write(descriptor, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    return errno
                }
                offset += written
            }
            return nil
        }
        if let failure {
            throw .from(errno: failure, path: url.path)
        }
    }

    /// Flushes and closes. Calling it twice does nothing the second time.
    public func close() throws(FileAccessError) {
        guard descriptor >= 0 else { return }
        let descriptor = descriptor
        self.descriptor = -1
        guard fsync(descriptor) == 0 else {
            let code = errno
            Darwin.close(descriptor)
            throw .from(errno: code, path: url.path)
        }
        guard Darwin.close(descriptor) == 0 else { throw .from(errno: errno, path: url.path) }
    }
}
