import Darwin
import Foundation

/// Bounded reads of the parts of a rollout file the tail read does not cover.
///
/// The initial tail is the last megabyte, but Codex logs grow to hundreds of megabytes: the `session_meta` header
/// is far behind it, and so is the `turn_context` of a long turn still in progress. Both reads refuse symlinks and
/// non-regular files, read at most a fixed budget, and pass lines through `CodexRolloutParser` like any other line.
enum RolloutFileHistory {
    /// The header line is ~20 KB (it embeds the base instructions); anything longer is not read.
    static let maximumHeaderBytes = 256 * 1_024
    static let windowBytes = 1_024 * 1_024
    /// How far before the tail the latest turn boundary is looked for. Real turns log up to a few megabytes.
    static let maximumSearchBytes: UInt64 = 16 * 1_024 * 1_024
    /// The search starts this far inside the tail so a line cut by the tail's start is still seen whole.
    static let tailOverlapBytes: UInt64 = 64 * 1_024

    /// The first line of the file, when it ends within `maximumBytes`.
    static func firstLine(of url: URL, maximumBytes: Int = maximumHeaderBytes) -> Data? {
        withRegularFile(at: url) { descriptor, size in
            let bytes = read(descriptor, offset: 0, count: Int(min(UInt64(maximumBytes), size)))
            guard let bytes, let newline = bytes.firstIndex(of: UInt8(ascii: "\n")) else { return nil }
            return bytes.prefix(upTo: newline)
        } ?? nil
    }

    /// The latest `turn_context` and the latest turn start or end written before `offset`, oldest first.
    ///
    /// Walks backwards in windows until the wanted lines are found or `maximumSearchBytes` were read. Only the
    /// envelope of each line is scanned; lines that are not turn events are never parsed further.
    static func latestTurnEvents(
        of url: URL,
        before offset: UInt64,
        needsContext: Bool = true,
        needsBoundary: Bool = true
    ) -> [CodexRolloutEvent] {
        guard needsContext || needsBoundary else { return [] }
        return withRegularFile(at: url) { descriptor, size -> [CodexRolloutEvent] in
            var found: [(position: UInt64, event: CodexRolloutEvent)] = []
            var foundContext = !needsContext
            var foundBoundary = !needsBoundary
            var end = min(offset.addingReportingOverflow(tailOverlapBytes).partialValue, size)
            let floor = end > maximumSearchBytes ? end - maximumSearchBytes : 0
            while end > floor, !(foundContext && foundBoundary) {
                let start = max(floor, end > UInt64(windowBytes) ? end - UInt64(windowBytes) : 0)
                guard let bytes = read(descriptor, offset: start, count: Int(end - start)) else { break }
                for line in completeLines(in: bytes, startsFileOrLine: start == 0).reversed()
                where !(foundContext && foundBoundary) {
                    let data = bytes[line]
                    switch CodexRolloutParser.lineKind(of: data) {
                    case .turnContext where !foundContext:
                        foundContext = true
                        found += CodexRolloutParser.events(in: data).map { (start + UInt64(line.lowerBound), $0) }
                    case .turnBoundary where !foundBoundary:
                        foundBoundary = true
                        found += CodexRolloutParser.events(in: data).map { (start + UInt64(line.lowerBound), $0) }
                    default:
                        break
                    }
                }
                guard start > floor else { break }
                end = nextWindowEnd(in: bytes, start: start, end: end)
            }
            return found.sorted { $0.position < $1.position }.map(\.event)
        } ?? []
    }

    /// Where the next (earlier) window ends: just past this window's first newline, so the line cut by this window's
    /// start lies whole in the next window. A window whose only newline is its last byte, or that has none, is the
    /// middle of a line longer than a window — never a turn line — and is skipped whole.
    static func nextWindowEnd(in bytes: Data, start: UInt64, end: UInt64) -> UInt64 {
        guard let newline = bytes.firstIndex(of: UInt8(ascii: "\n")) else { return start }
        let afterNewline = start + UInt64(newline - bytes.startIndex) + 1
        return afterNewline < end ? afterNewline : start
    }

    /// Ranges of the lines in `bytes` that are known to be whole: each ends with a newline and starts after one
    /// (or at the start of the file). Returned ranges exclude the newline.
    static func completeLines(in bytes: Data, startsFileOrLine: Bool) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var lineStart: Int? = startsFileOrLine ? bytes.startIndex : nil
        var index = bytes.startIndex
        while let newline = bytes[index...].firstIndex(of: UInt8(ascii: "\n")) {
            if let start = lineStart, newline > start {
                ranges.append((start - bytes.startIndex)..<(newline - bytes.startIndex))
            }
            lineStart = newline + 1
            index = newline + 1
            if index >= bytes.endIndex { break }
        }
        return ranges
    }

    // MARK: - File access

    private static func withRegularFile<Result>(at url: URL, _ body: (Int32, UInt64) -> Result) -> Result? {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        return body(descriptor, UInt64(max(info.st_size, 0)))
    }

    private static func read(_ descriptor: Int32, offset: UInt64, count: Int) -> Data? {
        guard count > 0, count <= windowBytes * 2 else { return count == 0 ? Data() : nil }
        var buffer = [UInt8](repeating: 0, count: count)
        var filled = 0
        while filled < count {
            let result = buffer.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return pread(descriptor, base.advanced(by: filled), count - filled, off_t(offset) + off_t(filled))
            }
            if result < 0 {
                if errno == EINTR { continue }
                return nil
            }
            if result == 0 { break }
            filled += result
        }
        return Data(buffer.prefix(filled))
    }
}
