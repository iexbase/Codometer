import Darwin
import Foundation

/// Where the previous tail read stopped.
public struct TailCursor: Hashable, Sendable {
    public let identity: FileIdentity
    /// Byte offset just past the last complete line that was returned.
    public let offset: UInt64
    /// The bytes at `offset` belong to a line too long to keep; skip to the next newline first.
    public let skipsLeadingFragment: Bool

    public init(identity: FileIdentity, offset: UInt64, skipsLeadingFragment: Bool) {
        self.identity = identity
        self.offset = offset
        self.skipsLeadingFragment = skipsLeadingFragment
    }
}

public struct TailChunk: Sendable {
    /// Complete lines, without their trailing newline.
    public let lines: [Data]
    public let cursor: TailCursor
    /// The file was replaced or truncated since `cursor`, so earlier state derived from it is obsolete.
    public let didRestart: Bool
}

/// Incremental line reader for append-only logs (JSONL session files).
///
/// Only bytes appended since the previous read are touched, so tailing a large file costs
/// proportional to what changed rather than to the file size.
public enum FileTail {
    public static func read(
        at url: URL,
        after cursor: TailCursor?,
        initialTailBytes: UInt64,
        maximumReadBytes: UInt64
    ) throws(FileAccessError) -> TailChunk {
        precondition(maximumReadBytes > 0 && maximumReadBytes <= 64 * 1024 * 1024, "unreasonable read budget")
        let path = url.path
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw .from(errno: errno, path: path) }
        defer { close(descriptor) }

        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw .from(errno: errno, path: path) }
        guard (info.st_mode & S_IFMT) == S_IFREG else { throw .notRegularFile(path: path) }
        let metadata = FileMetadata(info)
        let size = metadata.size

        var start: UInt64
        var skipFirstFragment: Bool
        var didRestart = false
        if let cursor, cursor.identity == metadata.identity, cursor.offset <= size {
            start = cursor.offset
            skipFirstFragment = cursor.skipsLeadingFragment
        } else {
            didRestart = cursor != nil
            start = size > initialTailBytes ? size - initialTailBytes : 0
            skipFirstFragment = start > 0
        }

        if size - start > maximumReadBytes {
            // Too much was appended at once; the newest data matters most.
            start = size - maximumReadBytes
            skipFirstFragment = true
        }

        let length = Int(size - start)
        guard length > 0 else {
            return TailChunk(
                lines: [],
                cursor: TailCursor(identity: metadata.identity, offset: start, skipsLeadingFragment: skipFirstFragment),
                didRestart: didRestart
            )
        }

        var buffer = [UInt8](repeating: 0, count: length)
        var filled = 0
        while filled < length {
            let count = buffer.withUnsafeMutableBytes { raw in
                pread(descriptor, raw.baseAddress!.advanced(by: filled), length - filled, off_t(start) + off_t(filled))
            }
            if count < 0 {
                if errno == EINTR { continue }
                throw .from(errno: errno, path: path)
            }
            if count == 0 { break }
            filled += count
        }

        return split(
            buffer.prefix(filled),
            startingAt: start,
            identity: metadata.identity,
            skipFirstFragment: skipFirstFragment,
            didRestart: didRestart
        )
    }

    static func split(
        _ bytes: ArraySlice<UInt8>,
        startingAt start: UInt64,
        identity: FileIdentity,
        skipFirstFragment: Bool,
        didRestart: Bool
    ) -> TailChunk {
        let newline = UInt8(ascii: "\n")
        var lines: [Data] = []
        var lineStart = bytes.startIndex
        var skipping = skipFirstFragment
        var index = bytes.startIndex

        while index < bytes.endIndex {
            if bytes[index] == newline {
                if skipping {
                    skipping = false
                } else if index > lineStart {
                    lines.append(Data(bytes[lineStart..<index]))
                }
                lineStart = index + 1
            }
            index += 1
        }

        let consumed = UInt64(lineStart - bytes.startIndex)
        if consumed == 0 && !bytes.isEmpty && UInt64(bytes.count) >= 8 * 1024 * 1024 {
            // A single line fills the whole budget: drop it rather than stalling on it forever.
            return TailChunk(
                lines: [],
                cursor: TailCursor(identity: identity, offset: start + UInt64(bytes.count), skipsLeadingFragment: true),
                didRestart: didRestart
            )
        }
        return TailChunk(
            lines: lines,
            cursor: TailCursor(identity: identity, offset: start + consumed, skipsLeadingFragment: skipping),
            didRestart: didRestart
        )
    }
}
