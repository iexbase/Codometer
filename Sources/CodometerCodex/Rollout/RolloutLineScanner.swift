import Darwin
import Foundation

/// One value read by `RolloutLineScanner`, kept as raw text.
enum RolloutScalar: Hashable, Sendable {
    /// A string without escapes that fits the field's size limit.
    case string(String)
    /// A JSON number token, not yet converted.
    case number(String)
    /// `true`, `false` or `null`.
    case literal(String)
    /// An object or array.
    case container
    /// Present but unusable: too long, escaped or malformed.
    case unusable

    var string: String? {
        if case .string(let text) = self { text } else { nil }
    }

    var int64: Int64? {
        if case .number(let text) = self { Int64(text) } else { nil }
    }

    var isNull: Bool {
        self == .literal("null")
    }
}

/// The few values the app reads from a rollout line without decoding the line.
struct RolloutLineFields: Equatable, Sendable {
    // Envelope.
    var timestamp: RolloutScalar?
    var type: RolloutScalar?
    // Payload.
    var payloadType: RolloutScalar?
    var callID: RolloutScalar?
    var name: RolloutScalar?
    var turnID: RolloutScalar?
    var durationMs: RolloutScalar?
    var firstTokenMs: RolloutScalar?
    var reason: RolloutScalar?
    var id: RolloutScalar?
    var sessionID: RolloutScalar?
    var cwd: RolloutScalar?
    var originator: RolloutScalar?
    var cliVersion: RolloutScalar?
    var model: RolloutScalar?
    var effort: RolloutScalar?
    var approvalPolicy: RolloutScalar?
    var approvalsReviewer: RolloutScalar?
}

/// Walks the bytes of one JSONL rollout line and copies out a handful of short values.
///
/// Only object keys and the wanted values are ever compared or copied. Every other string — prompts, replies,
/// tool input and output — is skipped by jumping to its closing quote, so its text is never decoded. Values are
/// attributed by position (envelope keys at depth 1, `payload` keys at depth 2), so key-like text inside a string
/// or a nested object can never be mistaken for a field. The first occurrence of a key wins.
enum RolloutLineScanner {
    /// Longest string copied for ids, types and names.
    static let maximumValueBytes = 128
    /// Longest string copied for paths.
    static let maximumPathBytes = 1_024
    static let maximumNumberBytes = 32

    typealias FieldPath = WritableKeyPath<RolloutLineFields, RolloutScalar?>

    /// The envelope `type` and the payload `type` of one line, scanned no further than either of them needs.
    ///
    /// A line that is not an `event_msg` or a `response_item` stops at its envelope type, which is the second key,
    /// so telling the two apart costs a few dozen bytes whatever the line's size.
    static func lineTypes(_ line: Data) -> (type: String?, payloadType: String?) {
        let fields = scan(line) { fields in
            guard let type = fields.type else { return false }
            return (type != .string("event_msg") && type != .string("response_item")) || fields.payloadType != nil
        }
        return (fields.type?.string, fields.payloadType?.string)
    }

    /// Scans `line` until `isComplete` returns true for the fields found so far, or the line ends.
    static func scan(_ line: Data, until isComplete: (RolloutLineFields) -> Bool) -> RolloutLineFields {
        line.withUnsafeBytes { scan($0, until: isComplete) }
    }

    static func scan(_ bytes: UnsafeRawBufferPointer, until isComplete: (RolloutLineFields) -> Bool) -> RolloutLineFields {
        var fields = RolloutLineFields()
        var depth = 0
        var valueBelongsToPayload = false
        var insidePayload = false
        var index = 0
        while index < bytes.count {
            switch bytes[index] {
            case Byte.quote:
                guard let close = closingQuote(in: bytes, openingAt: index) else { return fields }
                let keyRange = (index + 1)..<close
                let afterString = skipWhitespace(in: bytes, from: close + 1)
                guard afterString < bytes.count, bytes[afterString] == Byte.colon else {
                    // A string value nobody asked for.
                    index = close + 1
                    continue
                }
                index = afterString + 1
                if depth == 1 {
                    valueBelongsToPayload = matches(bytes, keyRange, Key.payload)
                }
                guard let (field, limit) = field(for: bytes, keyRange: keyRange, depth: depth, insidePayload: insidePayload),
                      fields[keyPath: field] == nil
                else { continue }
                let valueStart = skipWhitespace(in: bytes, from: index)
                guard valueStart < bytes.count else { return fields }
                let (value, valueEnd) = readValue(in: bytes, at: valueStart, maximumStringBytes: limit)
                fields[keyPath: field] = value
                index = valueEnd
                if isComplete(fields) { return fields }
            case Byte.openBrace, Byte.openBracket:
                depth += 1
                if depth == 2 {
                    insidePayload = bytes[index] == Byte.openBrace && valueBelongsToPayload
                }
                index += 1
            case Byte.closeBrace, Byte.closeBracket:
                depth -= 1
                if depth < 2 {
                    insidePayload = false
                }
                index += 1
            default:
                index += 1
            }
        }
        return fields
    }

    /// Whether `needle` occurs anywhere in `bytes`.
    static func contains(_ needle: [UInt8], in bytes: UnsafeRawBufferPointer) -> Bool {
        firstIndex(of: needle, in: bytes, from: 0) != nil
    }

    /// True when the line asks to run a command outside the sandbox.
    ///
    /// Codex marks such calls with `sandbox_permissions` set to `require_escalated` — as JSON inside
    /// `function_call.arguments` (`\"sandbox_permissions\":\"require_escalated\"`) or as a property inside
    /// `custom_tool_call.input` (`sandbox_permissions: \"require_escalated\"`). Requiring the key right before the
    /// value keeps commands that merely mention the word (a `grep`, a patch) from looking like approval prompts.
    static func requestsEscalation(_ bytes: UnsafeRawBufferPointer) -> Bool {
        var searchFrom = 0
        while let valueStart = firstIndex(of: Marker.escalatedValue, in: bytes, from: searchFrom) {
            var keyEnd = valueStart
            while keyEnd > 0, valueStart - keyEnd < Marker.maximumSeparatorBytes, Byte.isSeparator(bytes[keyEnd - 1]) {
                keyEnd -= 1
            }
            let keyStart = keyEnd - Marker.sandboxKey.count
            if keyEnd < valueStart, keyStart >= 0, matches(bytes, keyStart..<keyEnd, Marker.sandboxKey) {
                return true
            }
            searchFrom = valueStart + Marker.escalatedValue.count
        }
        return false
    }

    enum Marker {
        static let escalatedValue = Array("require_escalated".utf8)
        static let sandboxKey = Array("sandbox_permissions".utf8)
        /// Quotes, escapes, a colon or equals sign and spaces between the key and the value.
        static let maximumSeparatorBytes = 8
        /// The exact tool name, quotes included, so `request_user_input_async` does not match.
        static let userInputName = Array("\"request_user_input\"".utf8)
    }

    // MARK: - Fields

    private enum Key {
        static let payload = Array("payload".utf8)
        static let timestamp = Array("timestamp".utf8)
        static let type = Array("type".utf8)
        static let callID = Array("call_id".utf8)
        static let name = Array("name".utf8)
        static let turnID = Array("turn_id".utf8)
        static let durationMs = Array("duration_ms".utf8)
        static let firstTokenMs = Array("time_to_first_token_ms".utf8)
        static let reason = Array("reason".utf8)
        static let id = Array("id".utf8)
        static let sessionID = Array("session_id".utf8)
        static let cwd = Array("cwd".utf8)
        static let originator = Array("originator".utf8)
        static let cliVersion = Array("cli_version".utf8)
        static let model = Array("model".utf8)
        static let effort = Array("effort".utf8)
        static let approvalPolicy = Array("approval_policy".utf8)
        static let approvalsReviewer = Array("approvals_reviewer".utf8)
    }

    /// The field a key at `depth` fills, with the longest string it accepts. Dispatches on the key length first,
    /// so most keys are rejected without comparing bytes and nothing is allocated.
    private static func field(
        for bytes: UnsafeRawBufferPointer,
        keyRange: Range<Int>,
        depth: Int,
        insidePayload: Bool
    ) -> (FieldPath, Int)? {
        func key(_ expected: [UInt8]) -> Bool {
            matches(bytes, keyRange, expected)
        }
        if depth == 1 {
            if key(Key.timestamp) { return (\.timestamp, 40) }
            if key(Key.type) { return (\.type, maximumValueBytes) }
            return nil
        }
        guard depth == 2, insidePayload else { return nil }
        let path: FieldPath? = switch keyRange.count {
        case 2: key(Key.id) ? \.id : nil
        case 3: key(Key.cwd) ? \.cwd : nil
        case 4: key(Key.type) ? \.payloadType : key(Key.name) ? \.name : nil
        case 5: key(Key.model) ? \.model : nil
        case 6: key(Key.reason) ? \.reason : key(Key.effort) ? \.effort : nil
        case 7: key(Key.callID) ? \.callID : key(Key.turnID) ? \.turnID : nil
        case 10: key(Key.sessionID) ? \.sessionID : key(Key.originator) ? \.originator : nil
        case 11: key(Key.durationMs) ? \.durationMs : key(Key.cliVersion) ? \.cliVersion : nil
        case 15: key(Key.approvalPolicy) ? \.approvalPolicy : nil
        case 18: key(Key.approvalsReviewer) ? \.approvalsReviewer : nil
        case 22: key(Key.firstTokenMs) ? \.firstTokenMs : nil
        default: nil
        }
        guard let path else { return nil }
        return (path, path == \RolloutLineFields.cwd ? maximumPathBytes : maximumValueBytes)
    }

    /// Reads the value starting at `start`. Returns the value and the index to continue walking from:
    /// past a scalar, or at the opening bracket of a container so the walk descends into it.
    private static func readValue(
        in bytes: UnsafeRawBufferPointer,
        at start: Int,
        maximumStringBytes: Int
    ) -> (RolloutScalar, Int) {
        switch bytes[start] {
        case Byte.quote:
            guard let close = closingQuote(in: bytes, openingAt: start) else { return (.unusable, bytes.count) }
            let range = (start + 1)..<close
            guard range.count <= maximumStringBytes, !bytes[range].contains(Byte.backslash) else {
                return (.unusable, close + 1)
            }
            return (.string(String(decoding: UnsafeRawBufferPointer(rebasing: bytes[range]), as: UTF8.self)), close + 1)
        case Byte.openBrace, Byte.openBracket:
            return (.container, start)
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"):
            let end = tokenEnd(in: bytes, from: start, allowed: Byte.isNumberByte)
            let token = start..<end
            guard token.count <= maximumNumberBytes else { return (.unusable, end) }
            return (.number(String(decoding: UnsafeRawBufferPointer(rebasing: bytes[token]), as: UTF8.self)), end)
        case UInt8(ascii: "t"), UInt8(ascii: "f"), UInt8(ascii: "n"):
            let end = tokenEnd(in: bytes, from: start) { $0 >= UInt8(ascii: "a") && $0 <= UInt8(ascii: "z") }
            let text = String(decoding: UnsafeRawBufferPointer(rebasing: bytes[start..<end]), as: UTF8.self)
            return (["true", "false", "null"].contains(text) ? .literal(text) : .unusable, end)
        default:
            return (.unusable, start)
        }
    }

    // MARK: - Byte helpers

    private enum Byte {
        static let quote = UInt8(ascii: "\"")
        static let backslash = UInt8(ascii: "\\")
        static let colon = UInt8(ascii: ":")
        static let openBrace = UInt8(ascii: "{")
        static let closeBrace = UInt8(ascii: "}")
        static let openBracket = UInt8(ascii: "[")
        static let closeBracket = UInt8(ascii: "]")

        static func isWhitespace(_ byte: UInt8) -> Bool {
            byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
        }

        static func isNumberByte(_ byte: UInt8) -> Bool {
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "-"), UInt8(ascii: "+"), UInt8(ascii: "."),
                 UInt8(ascii: "e"), UInt8(ascii: "E"):
                true
            default:
                false
            }
        }

        static func isSeparator(_ byte: UInt8) -> Bool {
            switch byte {
            case quote, backslash, colon, UInt8(ascii: "'"), UInt8(ascii: "="), UInt8(ascii: " "), openBracket: true
            default: false
            }
        }
    }

    private static func matches(_ bytes: UnsafeRawBufferPointer, _ range: Range<Int>, _ expected: [UInt8]) -> Bool {
        range.count == expected.count && bytes[range].elementsEqual(expected)
    }

    private static func skipWhitespace(in bytes: UnsafeRawBufferPointer, from start: Int) -> Int {
        tokenEnd(in: bytes, from: start, allowed: Byte.isWhitespace)
    }

    private static func tokenEnd(in bytes: UnsafeRawBufferPointer, from start: Int, allowed: (UInt8) -> Bool) -> Int {
        var index = start
        while index < bytes.count, allowed(bytes[index]) {
            index += 1
        }
        return index
    }

    /// Index of the quote that closes the string opened at `start`, or `nil` when the line ends first.
    /// Jumps between quotes with `memchr`; a quote preceded by an odd run of backslashes is part of the text.
    private static func closingQuote(in bytes: UnsafeRawBufferPointer, openingAt start: Int) -> Int? {
        guard let base = bytes.baseAddress else { return nil }
        var searchFrom = start + 1
        while searchFrom < bytes.count {
            guard let found = memchr(base.advanced(by: searchFrom), Int32(Byte.quote), bytes.count - searchFrom) else {
                return nil
            }
            let index = base.distance(to: UnsafeRawPointer(found))
            var backslashes = 0
            while index - backslashes - 1 > start, bytes[index - backslashes - 1] == Byte.backslash {
                backslashes += 1
            }
            if backslashes % 2 == 0 {
                return index
            }
            searchFrom = index + 1
        }
        return nil
    }

    private static func firstIndex(of needle: [UInt8], in bytes: UnsafeRawBufferPointer, from start: Int) -> Int? {
        guard let base = bytes.baseAddress, !needle.isEmpty, start < bytes.count else { return nil }
        return needle.withUnsafeBytes { pattern -> Int? in
            guard
                let patternBase = pattern.baseAddress,
                let found = memmem(base.advanced(by: start), bytes.count - start, patternBase, pattern.count)
            else { return nil }
            return base.distance(to: UnsafeRawPointer(found))
        }
    }
}
