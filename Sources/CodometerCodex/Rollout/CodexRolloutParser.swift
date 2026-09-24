import CodometerCore
import Foundation

/// Line categories the reader needs before parsing a line.
enum RolloutLineKind: Hashable, Sendable {
    case turnContext
    /// `task_started`, `task_complete` or `turn_aborted`.
    case turnBoundary
    case other
}

/// Turns rollout JSONL lines into `CodexRolloutEvent`s.
///
/// A byte scan (`RolloutLineScanner`) reads the envelope and payload types first; most lines are conversation
/// content and are dropped right there. Session, turn and tool call lines are read by the same byte scan, which
/// copies whitelisted short values and jumps over every other string (`last_agent_message`, instructions, tool
/// input and output) without decoding it. Only the purely numeric token lines go through `JSONDecoder`.
public enum CodexRolloutParser {
    /// Parses one JSONL line. Returns no events for lines the app does not use or cannot read.
    ///
    /// - Parameter scanningCallOutputs: also report tool call outputs. Pass `true` only while a call is pending,
    ///   so output lines — often the largest — are skipped the rest of the time.
    public static func events(in line: Data, scanningCallOutputs: Bool = false) -> [CodexRolloutEvent] {
        line.withUnsafeBytes { bytes -> [CodexRolloutEvent] in
            let head = headFields(bytes)
            switch (head.type?.string, head.payloadType?.string) {
            case (LineType.sessionMeta?, _):
                return sessionMeta(bytes)
            case (LineType.turnContext?, _):
                return turnContext(bytes)
            case (LineType.tokenUsageRecord?, _):
                return tokenUsageRecord(line)
            case (LineType.eventMessage?, PayloadType.tokenCount?):
                return tokenCount(line)
            case (LineType.eventMessage?, PayloadType.taskStarted?):
                return turnStarted(bytes)
            case (LineType.eventMessage?, PayloadType.taskComplete?):
                return turnFinished(bytes, aborted: false)
            case (LineType.eventMessage?, PayloadType.turnAborted?):
                return turnFinished(bytes, aborted: true)
            case (LineType.responseItem?, PayloadType.customToolCall?):
                return callStart(bytes, isFunctionCall: false)
            case (LineType.responseItem?, PayloadType.functionCall?):
                return callStart(bytes, isFunctionCall: true)
            case (LineType.responseItem?, PayloadType.customToolCallOutput?),
                 (LineType.responseItem?, PayloadType.functionCallOutput?):
                return scanningCallOutputs ? callOutput(bytes) : []
            default:
                return []
            }
        }
    }

    /// What kind of line this is, from its envelope alone.
    static func lineKind(of line: Data) -> RolloutLineKind {
        let head = line.withUnsafeBytes { headFields($0) }
        switch (head.type?.string, head.payloadType?.string) {
        case (LineType.turnContext?, _):
            return .turnContext
        case (LineType.eventMessage?, PayloadType.taskStarted?),
             (LineType.eventMessage?, PayloadType.taskComplete?),
             (LineType.eventMessage?, PayloadType.turnAborted?):
            return .turnBoundary
        default:
            return .other
        }
    }

    /// The envelope and payload types, scanned no further than needed.
    private static func headFields(_ bytes: UnsafeRawBufferPointer) -> RolloutLineFields {
        RolloutLineScanner.scan(bytes) { fields in
            guard let type = fields.type else { return false }
            return (type != .string(LineType.responseItem) && type != .string(LineType.eventMessage))
                || fields.payloadType != nil
        }
    }

    /// The first event of a line; convenient where a line is known to carry one event.
    public static func parse(line: Data) -> CodexRolloutEvent? {
        events(in: line).first
    }

    /// The envelope timestamp of any line, conversation lines included, without decoding the line.
    static func timestamp(of line: Data) -> Date? {
        let fields = RolloutLineScanner.scan(line) { $0.timestamp != nil || $0.type != nil }
        return parseTimestamp(fields.timestamp?.string)
    }

    static func parseTimestamp(_ text: String?) -> Date? {
        guard let text, !text.isEmpty, text.utf8.count <= 40 else { return nil }
        if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
            return date
        }
        return try? Date(text, strategy: Date.ISO8601FormatStyle())
    }

    static let userInputToolName = "request_user_input"

    private enum LineType {
        static let sessionMeta = "session_meta"
        static let turnContext = "turn_context"
        static let tokenUsageRecord = "token_usage_record"
        static let eventMessage = "event_msg"
        static let responseItem = "response_item"
    }

    private enum PayloadType {
        static let tokenCount = "token_count"
        static let taskStarted = "task_started"
        static let taskComplete = "task_complete"
        static let turnAborted = "turn_aborted"
        static let customToolCall = "custom_tool_call"
        static let functionCall = "function_call"
        static let customToolCallOutput = "custom_tool_call_output"
        static let functionCallOutput = "function_call_output"
    }

    // MARK: - Session and turn lines (byte scan)

    private static func sessionMeta(_ bytes: UnsafeRawBufferPointer) -> [CodexRolloutEvent] {
        let fields = RolloutLineScanner.scan(bytes) { fields in
            fields.timestamp != nil && fields.sessionID != nil && fields.id != nil && fields.cwd != nil
                && fields.originator != nil && fields.cliVersion != nil
        }
        guard let at = parseTimestamp(fields.timestamp?.string) else { return [] }
        return [.sessionStarted(
            sessionID: RolloutValue.identifier(fields.sessionID?.string) ?? RolloutValue.identifier(fields.id?.string),
            workingDirectory: RolloutValue.absolutePath(fields.cwd?.string),
            originator: RolloutValue.label(fields.originator?.string, maximumLength: RolloutValue.maximumOriginatorLength),
            cliVersion: RolloutValue.keyword(fields.cliVersion?.string),
            at: at
        )]
    }

    private static func turnContext(_ bytes: UnsafeRawBufferPointer) -> [CodexRolloutEvent] {
        let fields = RolloutLineScanner.scan(bytes) { fields in
            fields.timestamp != nil && fields.turnID != nil && fields.cwd != nil && fields.model != nil
                && fields.effort != nil && fields.approvalPolicy != nil && fields.approvalsReviewer != nil
        }
        guard let at = parseTimestamp(fields.timestamp?.string) else { return [] }
        return [.turnContext(
            workingDirectory: RolloutValue.absolutePath(fields.cwd?.string),
            turnID: RolloutValue.identifier(fields.turnID?.string),
            model: RolloutValue.label(fields.model?.string, maximumLength: RolloutValue.maximumModelLength),
            effort: RolloutValue.keyword(fields.effort?.string),
            approvalPolicy: RolloutValue.approvalPolicy(fields.approvalPolicy),
            approvalsReviewer: RolloutValue.keyword(fields.approvalsReviewer?.string),
            at: at
        )]
    }

    private static func turnStarted(_ bytes: UnsafeRawBufferPointer) -> [CodexRolloutEvent] {
        let fields = RolloutLineScanner.scan(bytes) { $0.timestamp != nil && $0.turnID != nil }
        guard let at = parseTimestamp(fields.timestamp?.string) else { return [] }
        return [.turnStarted(turnID: RolloutValue.identifier(fields.turnID?.string), at: at)]
    }

    private static func turnFinished(_ bytes: UnsafeRawBufferPointer, aborted: Bool) -> [CodexRolloutEvent] {
        let fields = RolloutLineScanner.scan(bytes) { fields in
            fields.timestamp != nil && fields.turnID != nil && fields.durationMs != nil
                && (aborted ? fields.reason != nil : fields.firstTokenMs != nil)
        }
        guard let at = parseTimestamp(fields.timestamp?.string) else { return [] }
        let turnID = RolloutValue.identifier(fields.turnID?.string)
        let duration = RolloutValue.milliseconds(fields.durationMs?.int64)
        if aborted {
            return [.turnAborted(turnID: turnID, durationMs: duration, reason: RolloutValue.keyword(fields.reason?.string), at: at)]
        }
        return [.turnCompleted(
            turnID: turnID,
            durationMs: duration,
            firstTokenMs: RolloutValue.milliseconds(fields.firstTokenMs?.int64),
            at: at
        )]
    }

    // MARK: - Tool call lines (byte scan, only behind a byte marker)

    private static func callStart(_ bytes: UnsafeRawBufferPointer, isFunctionCall: Bool) -> [CodexRolloutEvent] {
        let escalated = RolloutLineScanner.requestsEscalation(bytes)
        let mayAskUser = isFunctionCall && RolloutLineScanner.contains(RolloutLineScanner.Marker.userInputName, in: bytes)
        guard escalated || mayAskUser else { return [] }
        let fields = RolloutLineScanner.scan(bytes) { $0.timestamp != nil && $0.callID != nil && $0.name != nil }
        guard
            let at = parseTimestamp(fields.timestamp?.string),
            let callID = RolloutValue.identifier(fields.callID?.string)
        else { return [] }
        if mayAskUser, fields.name?.string == userInputToolName {
            return [.userInputRequested(callID: callID, at: at)]
        }
        return escalated ? [.escalatedCallStarted(callID: callID, at: at)] : []
    }

    private static func callOutput(_ bytes: UnsafeRawBufferPointer) -> [CodexRolloutEvent] {
        let fields = RolloutLineScanner.scan(bytes) { $0.timestamp != nil && $0.callID != nil }
        guard
            let at = parseTimestamp(fields.timestamp?.string),
            let callID = RolloutValue.identifier(fields.callID?.string)
        else { return [] }
        return [.callOutput(callID: callID, at: at)]
    }

    // MARK: - Token lines (numbers only, decoded into whitelisted fields)

    private static func decode<Payload: Decodable>(_ payload: Payload.Type, from line: Data) -> (Payload, Date)? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard
            let decoded = try? decoder.decode(Line<Payload>.self, from: line),
            let at = parseTimestamp(decoded.timestamp)
        else { return nil }
        return (decoded.payload, at)
    }

    private static func tokenUsageRecord(_ line: Data) -> [CodexRolloutEvent] {
        guard
            let (record, at) = decode(TokenUsageRecordPayload.self, from: line),
            let counts = record.usage?.counts
        else { return [] }
        return [.tokenUsage(counts, responseID: RolloutValue.identifier(record.responseId), at: at)]
    }

    private static func tokenCount(_ line: Data) -> [CodexRolloutEvent] {
        guard let (tokenCount, at) = decode(TokenCountPayload.self, from: line) else { return [] }
        var events: [CodexRolloutEvent] = []
        if let limits = tokenCount.rateLimits {
            events.append(.rateLimits(limits.snapshot, at: at))
        }
        if let counts = tokenCount.info?.lastTokenUsage?.counts {
            events.append(.tokenCountLast(counts, at: at))
        }
        return events
    }

    private struct Line<Payload: Decodable>: Decodable {
        let timestamp: String?
        let payload: Payload
    }

    private struct RawTokenUsage: Decodable {
        let counts: TokenCounts?

        private enum CodingKeys: String, CodingKey {
            case inputTokens, cachedInputTokens, cacheWriteInputTokens, outputTokens, reasoningOutputTokens
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            counts = RolloutValue.tokenCounts(
                input: container.lenient(Int64.self, forKey: .inputTokens),
                cachedInput: container.lenient(Int64.self, forKey: .cachedInputTokens),
                cacheWrite: container.lenient(Int64.self, forKey: .cacheWriteInputTokens),
                output: container.lenient(Int64.self, forKey: .outputTokens),
                reasoningOutput: container.lenient(Int64.self, forKey: .reasoningOutputTokens)
            )
        }
    }

    private struct TokenUsageRecordPayload: Decodable {
        let responseId: String?
        let usage: RawTokenUsage?

        private enum CodingKeys: String, CodingKey {
            case responseId, usage
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            responseId = container.lenient(String.self, forKey: .responseId)
            usage = container.lenient(RawTokenUsage.self, forKey: .usage)
        }
    }

    private struct TokenCountPayload: Decodable {
        struct Info: Decodable {
            let lastTokenUsage: RawTokenUsage?

            private enum CodingKeys: String, CodingKey {
                case lastTokenUsage
            }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                lastTokenUsage = container.lenient(RawTokenUsage.self, forKey: .lastTokenUsage)
            }
        }

        let info: Info?
        let rateLimits: RolloutRateLimits?

        private enum CodingKeys: String, CodingKey {
            case info, rateLimits
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            info = container.lenient(Info.self, forKey: .info)
            rateLimits = container.lenient(RolloutRateLimits.self, forKey: .rateLimits)
        }
    }

    private struct RolloutRateLimits: Decodable {
        struct Window: Decodable {
            let usedPercent: Double
            let windowMinutes: Int?
            let resetsAt: Int64?
        }

        struct Credits: Decodable {
            let hasCredits: Bool
            let unlimited: Bool
            let balance: String?
        }

        let limitId: String?
        let limitName: String?
        let primary: Window?
        let secondary: Window?
        let credits: Credits?
        let planType: String?
        let rateLimitReachedType: String?

        var snapshot: CodexLimitSnapshot {
            CodexLimitSnapshot(
                limitID: limitId,
                limitName: limitName,
                primary: primary.map(Self.window),
                secondary: secondary.map(Self.window),
                credits: credits.map {
                    CreditsInfo(hasCredits: $0.hasCredits, isUnlimited: $0.unlimited, balance: $0.balance.flatMap {
                        Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX"))
                    })
                },
                planType: planType,
                isLimitReached: rateLimitReachedType != nil
            )
        }

        private static func window(_ window: Window) -> CodexLimitSnapshot.Window {
            CodexLimitSnapshot.Window(
                usedPercent: window.usedPercent,
                durationMinutes: window.windowMinutes,
                resetsAt: window.resetsAt.flatMap(EpochSeconds.date)
            )
        }
    }
}

extension KeyedDecodingContainer {
    /// The value when present and of the expected type; `nil` otherwise, so one odd field never drops a line.
    fileprivate func lenient<Value: Decodable>(_ type: Value.Type, forKey key: Key) -> Value? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }
}

enum EpochSeconds {
    /// Accepts only plausible timestamps (2020–2100) so a unit mix-up cannot produce absurd dates.
    static func date(_ seconds: Int64) -> Date? {
        guard (1_577_836_800...4_102_444_800).contains(seconds) else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }
}
