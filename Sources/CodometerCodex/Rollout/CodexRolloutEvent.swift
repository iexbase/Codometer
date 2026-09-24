import CodometerCore
import Foundation

/// The events the app extracts from a Codex rollout log. Everything else in the log —
/// prompts, replies, tool input and output — is never decoded.
///
/// Every string carried here was validated by `RolloutValue`; every count is non-negative.
public enum CodexRolloutEvent: Hashable, Sendable {
    /// `session_meta`: the file's header.
    case sessionStarted(sessionID: String?, workingDirectory: String?, originator: String?, cliVersion: String?, at: Date)
    /// `turn_context`: written at the start of every turn.
    case turnContext(
        workingDirectory: String?,
        turnID: String?,
        model: String?,
        effort: String?,
        approvalPolicy: String?,
        approvalsReviewer: String?,
        at: Date
    )
    /// `event_msg/token_count.rate_limits`.
    case rateLimits(CodexLimitSnapshot, at: Date)
    /// `event_msg/task_started`.
    case turnStarted(turnID: String?, at: Date)
    /// `event_msg/task_complete`.
    case turnCompleted(turnID: String?, durationMs: Int64?, firstTokenMs: Int64?, at: Date)
    /// `event_msg/turn_aborted`.
    case turnAborted(turnID: String?, durationMs: Int64?, reason: String?, at: Date)
    /// `token_usage_record.usage`: the tokens of one model response. `input` is already uncached.
    case tokenUsage(TokenCounts, responseID: String?, at: Date)
    /// `event_msg/token_count.info.last_token_usage`: only a fallback for logs without `token_usage_record`.
    case tokenCountLast(TokenCounts, at: Date)
    /// A tool call that asks to run outside the sandbox and may need the user's approval.
    case escalatedCallStarted(callID: String, at: Date)
    /// A `request_user_input` call: the agent asked the user a question.
    case userInputRequested(callID: String, at: Date)
    /// The output of a tool call arrived.
    case callOutput(callID: String, at: Date)
}

/// Validation for the few values read from rollout logs.
enum RolloutValue {
    static let maximumIdentifierLength = 128
    static let maximumModelLength = AgentSession.maximumModelLength
    static let maximumOriginatorLength = 64
    static let maximumKeywordLength = 32
    /// More tokens than this in a single response is corruption or a unit mistake, not usage.
    static let maximumTokensPerResponse: Int64 = 50_000_000
    /// Stands in for an approval policy that is not a plain keyword (a structured policy): it may ask.
    static let structuredApprovalPolicy = "custom"

    /// Ids (`call_id`, `turn_id`, `response_id`, session ids): `[A-Za-z0-9_-]{1,128}`.
    static func identifier(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty, raw.utf8.count <= maximumIdentifierLength else { return nil }
        let valid = raw.utf8.allSatisfy { byte in
            switch byte {
            case UInt8(ascii: "a")...UInt8(ascii: "z"),
                 UInt8(ascii: "A")...UInt8(ascii: "Z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"),
                 UInt8(ascii: "_"), UInt8(ascii: "-"):
                true
            default:
                false
            }
        }
        return valid ? raw : nil
    }

    /// Enumeration-like values (`on-request`, `auto_review`, `0.154.0-alpha.6`): `[A-Za-z0-9._+-]`, bounded.
    static func keyword(_ raw: String?, maximumLength: Int = maximumKeywordLength) -> String? {
        guard let raw, !raw.isEmpty, raw.utf8.count <= maximumLength else { return nil }
        let valid = raw.utf8.allSatisfy { byte in
            switch byte {
            case UInt8(ascii: "a")...UInt8(ascii: "z"),
                 UInt8(ascii: "A")...UInt8(ascii: "Z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"),
                 UInt8(ascii: "_"), UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "+"):
                true
            default:
                false
            }
        }
        return valid ? raw : nil
    }

    /// Short display names (model, originator): trimmed, no control characters, rejected when too long.
    static func label(_ raw: String?, maximumLength: Int) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard
            !trimmed.isEmpty,
            trimmed.count <= maximumLength,
            !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { return nil }
        return trimmed
    }

    /// An absolute path without control characters.
    static func absolutePath(_ raw: String?) -> String? {
        guard
            let raw,
            raw.hasPrefix("/"),
            raw.utf8.count <= ProfileDirectory.maximumLength,
            !raw.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { return nil }
        return raw
    }

    /// `approval_policy`: a keyword such as `never` or `on-request`; any other present shape (a structured
    /// policy, an odd string) becomes `structuredApprovalPolicy`, which may ask the user. Absent or null is `nil`.
    static func approvalPolicy(_ scalar: RolloutScalar?) -> String? {
        guard let scalar, !scalar.isNull else { return nil }
        return keyword(scalar.string) ?? structuredApprovalPolicy
    }

    /// A duration in milliseconds shorter than the longest plausible turn.
    static func milliseconds(_ raw: Int64?) -> Int64? {
        guard let raw, raw >= 0, raw < Int64(TurnTiming.maximumDuration * 1_000) else { return nil }
        return raw
    }

    /// Codex counts: `input_tokens` includes cached tokens, so the uncached part is the difference.
    static func tokenCounts(
        input: Int64?,
        cachedInput: Int64?,
        cacheWrite: Int64?,
        output: Int64?,
        reasoningOutput: Int64?
    ) -> TokenCounts? {
        guard let input, let output else { return nil }
        let cachedInput = cachedInput ?? 0
        let cacheWrite = cacheWrite ?? 0
        let reasoningOutput = reasoningOutput ?? 0
        let all = [input, cachedInput, cacheWrite, output, reasoningOutput]
        guard all.allSatisfy({ (0...maximumTokensPerResponse).contains($0) }) else { return nil }
        return try? TokenCounts(
            input: max(0, input - cachedInput),
            cachedInput: cachedInput,
            cacheWrite: cacheWrite,
            output: output,
            reasoningOutput: reasoningOutput
        )
    }
}
