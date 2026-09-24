import CodometerCore
import Foundation

/// The token usage of one assistant response block in a Claude Code transcript line.
///
/// Claude Code writes one line per content block of a response; every block of one API request repeats the
/// request's usage, with `output_tokens` growing until the last block. Callers deduplicate by `requestID`.
struct ClaudeUsageRecord: Hashable, Sendable {
    /// `requestId`, or `message.id` when the request id is absent.
    let requestID: String
    /// `message.model`, when it looks like a model identifier.
    let model: String?
    let counts: TokenCounts
    let timestamp: Date?
}

/// Extracts usage from transcript lines. Only `requestId`, `timestamp`, `message.id`, `message.model` and the
/// four `message.usage` token counts are decoded; prompts, replies and tool input/output never are.
enum ClaudeTranscriptLine {
    static let maximumIdentifierLength = 128
    static let maximumModelLength = 60

    private static let usageMarker = Data(#""usage""#.utf8)
    private static let assistantMarker = Data(#""assistant""#.utf8)

    /// `nil` for lines without usage, with malformed or negative counts, or without any request identifier.
    static func parse(_ line: Data) -> ClaudeUsageRecord? {
        // Cheap byte scan first: most lines are conversation content and are skipped undecoded.
        guard line.range(of: usageMarker) != nil, line.range(of: assistantMarker) != nil else { return nil }
        guard
            let envelope = try? JSONDecoder().decode(Envelope.self, from: line),
            let usage = envelope.message?.usage,
            usage.hasAnyCount,
            let requestID = identifier(envelope.requestID) ?? identifier(envelope.message?.id),
            let counts = try? TokenCounts(
                input: usage.input ?? 0,
                cachedInput: usage.cacheRead ?? 0,
                cacheWrite: usage.cacheCreation ?? 0,
                output: usage.output ?? 0,
                reasoningOutput: 0
            )
        else { return nil }
        return ClaudeUsageRecord(
            requestID: requestID,
            model: model(envelope.message?.model),
            counts: counts,
            timestamp: timestamp(envelope.timestamp)
        )
    }

    /// Printable ASCII without spaces, 1–128 bytes.
    static func identifier(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty, raw.utf8.count <= maximumIdentifierLength else { return nil }
        guard raw.utf8.allSatisfy({ (0x21...0x7E).contains($0) }) else { return nil }
        return raw
    }

    /// Model ids such as `claude-opus-5`; placeholders like `<synthetic>` and anything unusual become `nil`.
    static func model(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty, raw.utf8.count <= maximumModelLength else { return nil }
        let allowed = raw.utf8.allSatisfy { byte in
            switch byte {
            case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"),
                 UInt8(ascii: "."), UInt8(ascii: "_"), UInt8(ascii: "-"), UInt8(ascii: ":"),
                 UInt8(ascii: "@"), UInt8(ascii: "/"), UInt8(ascii: "+"), UInt8(ascii: "["), UInt8(ascii: "]"):
                true
            default:
                false
            }
        }
        guard allowed, let first = raw.unicodeScalars.first, CharacterSet.alphanumerics.contains(first) else {
            return nil
        }
        return raw
    }

    static func timestamp(_ text: String?) -> Date? {
        guard let text, text.utf8.count <= 40 else { return nil }
        if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
            return date
        }
        return try? Date(text, strategy: Date.ISO8601FormatStyle())
    }

    // MARK: - Whitelisted shape

    /// Each field decodes independently, so a field that changes type drops only itself.
    private struct Envelope: Decodable {
        let requestID: String?
        let timestamp: String?
        let message: Message?

        private enum CodingKeys: String, CodingKey {
            case requestId, timestamp, message
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            requestID = (try? container.decodeIfPresent(String.self, forKey: .requestId)) ?? nil
            timestamp = (try? container.decodeIfPresent(String.self, forKey: .timestamp)) ?? nil
            message = (try? container.decodeIfPresent(Message.self, forKey: .message)) ?? nil
        }
    }

    private struct Message: Decodable {
        let id: String?
        let model: String?
        let usage: Usage?

        private enum CodingKeys: String, CodingKey {
            case id, model, usage
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? nil
            model = (try? container.decodeIfPresent(String.self, forKey: .model)) ?? nil
            usage = (try? container.decodeIfPresent(Usage.self, forKey: .usage)) ?? nil
        }
    }

    private struct Usage: Decodable {
        let input: Int64?
        let output: Int64?
        let cacheCreation: Int64?
        let cacheRead: Int64?

        var hasAnyCount: Bool {
            input != nil || output != nil || cacheCreation != nil || cacheRead != nil
        }

        private enum CodingKeys: String, CodingKey {
            case input = "input_tokens"
            case output = "output_tokens"
            case cacheCreation = "cache_creation_input_tokens"
            case cacheRead = "cache_read_input_tokens"
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            input = (try? container.decodeIfPresent(Int64.self, forKey: .input)) ?? nil
            output = (try? container.decodeIfPresent(Int64.self, forKey: .output)) ?? nil
            cacheCreation = (try? container.decodeIfPresent(Int64.self, forKey: .cacheCreation)) ?? nil
            cacheRead = (try? container.decodeIfPresent(Int64.self, forKey: .cacheRead)) ?? nil
        }
    }
}

/// Remembers the usage already counted for recent requests, so repeated blocks of one response count once.
///
/// A repeated request contributes only what grew since it was last seen (Claude Code's last block of a
/// response carries the final `output_tokens`). Bounded: the oldest requests are forgotten first.
struct RequestLedger: Sendable {
    static let defaultCapacity = 2_000

    let capacity: Int
    private var counted: [String: TokenCounts] = [:]
    private var order: [String] = []
    private var head = 0

    init(capacity: Int = Self.defaultCapacity) {
        self.capacity = max(capacity, 1)
    }

    var count: Int { counted.count }

    /// Records the request's cumulative usage and returns what was not counted before.
    mutating func record(id: String, counts: TokenCounts) -> TokenCounts {
        guard let previous = counted[id] else {
            counted[id] = counts
            order.append(id)
            evictIfNeeded()
            return counts
        }
        var delta = TokenCounts.zero
        delta.input = max(0, counts.input - previous.input)
        delta.cachedInput = max(0, counts.cachedInput - previous.cachedInput)
        delta.cacheWrite = max(0, counts.cacheWrite - previous.cacheWrite)
        delta.output = max(0, counts.output - previous.output)
        delta.reasoningOutput = max(0, counts.reasoningOutput - previous.reasoningOutput)

        var merged = previous
        merged.input = max(previous.input, counts.input)
        merged.cachedInput = max(previous.cachedInput, counts.cachedInput)
        merged.cacheWrite = max(previous.cacheWrite, counts.cacheWrite)
        merged.output = max(previous.output, counts.output)
        merged.reasoningOutput = max(previous.reasoningOutput, counts.reasoningOutput)
        counted[id] = merged
        return delta
    }

    private mutating func evictIfNeeded() {
        while counted.count > capacity, head < order.count {
            counted[order[head]] = nil
            head += 1
        }
        if head >= capacity {
            order.removeFirst(head)
            head = 0
        }
    }
}
