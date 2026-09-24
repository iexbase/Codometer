@testable import CodometerCodex
import CodometerCore
import Foundation
import Testing

@Suite("Codex rollout events")
struct CodexRolloutEventTests {
    private let time = "2026-09-16T18:55:00.000Z"

    @Test("session_meta: id, working directory, originator and CLI version; instructions are not read")
    func sessionStarted() {
        let parsed = events(Rollout.sessionMeta(at: time, originator: "codex-tui", cliVersion: "0.154.0-alpha.6.2"))
        #expect(parsed == [.sessionStarted(
            sessionID: Rollout.sessionID,
            workingDirectory: Rollout.project,
            originator: "codex-tui",
            cliVersion: "0.154.0-alpha.6.2",
            at: Rollout.date(time)
        )])
    }

    @Test("turn_context: turn, model, effort and approval settings")
    func turnContext() {
        let parsed = events(Rollout.turnContext(at: time, turnID: "0199aa-turn", policy: #""on-request""#, reviewer: "auto_review", effort: "xhigh"))
        #expect(parsed == [.turnContext(
            workingDirectory: Rollout.project,
            turnID: "0199aa-turn",
            model: Rollout.model,
            effort: "xhigh",
            approvalPolicy: "on-request",
            approvalsReviewer: "auto_review",
            at: Rollout.date(time)
        )])
    }

    @Test("turn_context: a structured approval policy may ask; a missing reviewer stays unknown")
    func structuredPolicy() {
        let structured = events(Rollout.turnContext(at: time, policy: #"{"granular":{"sandbox_approval":true}}"#, reviewer: nil))
        guard case let .turnContext(_, _, _, _, policy, reviewer, _) = structured.first else {
            Issue.record("expected turn context")
            return
        }
        #expect(policy == RolloutValue.structuredApprovalPolicy)
        #expect(reviewer == nil)
        guard case let .turnContext(_, _, _, _, nullPolicy, _, _) = events(Rollout.turnContext(at: time, policy: "null")).first else {
            Issue.record("expected turn context")
            return
        }
        #expect(nullPolicy == nil)
    }

    @Test("Turn start, completion and abort carry ids and timings")
    func turns() {
        #expect(events(Rollout.taskStarted(at: time, turnID: "t-1")) == [.turnStarted(turnID: "t-1", at: Rollout.date(time))])
        #expect(events(Rollout.taskComplete(at: time, turnID: "t-1")) == [
            .turnCompleted(turnID: "t-1", durationMs: 252_000, firstTokenMs: 2_800, at: Rollout.date(time)),
        ])
        #expect(events(Rollout.turnAborted(at: time, turnID: "t-2")) == [
            .turnAborted(turnID: "t-2", durationMs: 5_000, reason: "interrupted", at: Rollout.date(time)),
        ])
    }

    @Test("Implausible durations are dropped, not trusted")
    func implausibleDurations() {
        #expect(events(Rollout.taskComplete(at: time, durationMs: "-5", firstTokenMs: "null")) == [
            .turnCompleted(turnID: "turn-1", durationMs: nil, firstTokenMs: nil, at: Rollout.date(time)),
        ])
        #expect(events(Rollout.taskComplete(at: time, durationMs: "86400000", firstTokenMs: "1.5")) == [
            .turnCompleted(turnID: "turn-1", durationMs: nil, firstTokenMs: nil, at: Rollout.date(time)),
        ])
    }

    @Test("token_usage_record: input is uncached; the response id is kept")
    func tokenUsage() throws {
        let parsed = events(Rollout.tokenUsageRecord(at: time, responseID: "resp_0a1b", input: 12_000, cached: 9_500, output: 700, reasoning: 256))
        let expected = try TokenCounts(input: 2_500, cachedInput: 9_500, cacheWrite: 0, output: 700, reasoningOutput: 256)
        #expect(parsed == [.tokenUsage(expected, responseID: "resp_0a1b", at: Rollout.date(time))])
    }

    @Test("Token counts: cache larger than input clamps to zero; negative or absurd counts drop the event")
    func tokenValidation() throws {
        guard case let .tokenUsage(counts, _, _) = events(Rollout.tokenUsageRecord(at: time, responseID: "r1", input: 10, cached: 50)).first else {
            Issue.record("expected token usage")
            return
        }
        #expect(counts.input == 0)
        #expect(counts.cachedInput == 50)
        #expect(events(Rollout.tokenUsageRecord(at: time, responseID: "r2", output: -1)).isEmpty)
        #expect(events(Rollout.tokenUsageRecord(at: time, responseID: "r3", input: 60_000_000, cached: 0)).isEmpty)
        let noUsage = #"{"timestamp":"\#(time)","type":"token_usage_record","payload":{"response_id":"r4"}}"#
        #expect(events(noUsage).isEmpty)
        guard case let .tokenUsage(_, badID, _) = events(Rollout.tokenUsageRecord(at: time, responseID: "not an id")).first else {
            Issue.record("expected token usage")
            return
        }
        #expect(badID == nil)
    }

    @Test("token_count yields rate limits and the last response's tokens")
    func tokenCount() throws {
        let parsed = events(Rollout.tokenCount(at: time, input: 900, cached: 400, output: 80))
        #expect(parsed.count == 2)
        guard case .rateLimits(let snapshot, _) = parsed.first else {
            Issue.record("expected rate limits first")
            return
        }
        #expect(snapshot.primary?.usedPercent == 42)
        let expected = try TokenCounts(input: 500, cachedInput: 400, cacheWrite: 0, output: 80, reasoningOutput: 10)
        #expect(parsed.last == .tokenCountLast(expected, at: Rollout.date(time)))

        let limitsOnly = #"{"timestamp":"\#(time)","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"limit_id":"codex","primary":{"used_percent":1.0,"window_minutes":300,"resets_at":1789600000}}}}"#
        #expect(events(limitsOnly).count == 1)
        let tokensOnly = #"{"timestamp":"\#(time)","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":5,"output_tokens":1}},"rate_limits":null}}"#
        #expect(events(tokensOnly) == [.tokenCountLast(try TokenCounts(input: 5, cachedInput: 0, cacheWrite: 0, output: 1, reasoningOutput: 0), at: Rollout.date(time))])
    }

    @Test("Escalated custom tool calls and function calls")
    func escalatedCalls() {
        #expect(events(Rollout.escalatedExec(at: time, callID: "call_exec1")) == [.escalatedCallStarted(callID: "call_exec1", at: Rollout.date(time))])
        #expect(events(Rollout.escalatedFunctionCall(at: time, callID: "call_fn1")) == [.escalatedCallStarted(callID: "call_fn1", at: Rollout.date(time))])
        #expect(events(Rollout.execMentioningEscalation(at: time, callID: "call_grep")).isEmpty)
    }

    @Test("request_user_input is a question; the async variant does not block")
    func userInput() {
        #expect(events(Rollout.requestUserInput(at: time, callID: "call_q1")) == [.userInputRequested(callID: "call_q1", at: Rollout.date(time))])
        #expect(events(Rollout.requestUserInput(at: time, callID: "call_q2", name: "request_user_input_async")).isEmpty)
    }

    @Test("Call outputs are reported only while the caller scans for them")
    func outputs() {
        let custom = Rollout.customToolCallOutput(at: time, callID: "call_exec1")
        let function = Rollout.functionCallOutput(at: time, callID: "call_fn1")
        #expect(events(custom).isEmpty)
        #expect(events(function).isEmpty)
        #expect(events(custom, scanningCallOutputs: true) == [.callOutput(callID: "call_exec1", at: Rollout.date(time))])
        #expect(events(function, scanningCallOutputs: true) == [.callOutput(callID: "call_fn1", at: Rollout.date(time))])
    }

    @Test("Conversation and compacted lines yield nothing, whatever they mention")
    func content() {
        #expect(events(Rollout.message(at: time), scanningCallOutputs: true).isEmpty)
        #expect(events(Rollout.compacted(at: time), scanningCallOutputs: true).isEmpty)
        let noTimestamp = #"{"type":"response_item","payload":{"type":"custom_tool_call","call_id":"c1","name":"exec","input":"sandbox_permissions: \"require_escalated\""}}"#
        #expect(events(noTimestamp).isEmpty)
        #expect(CodexRolloutParser.timestamp(of: Data(Rollout.message(at: time).utf8)) == Rollout.date(time))
    }

    @Test("Originators map to where the session runs")
    func origins() {
        #expect(CodexSessionState.origin(forOriginator: "codex-tui") == .terminal)
        #expect(CodexSessionState.origin(forOriginator: "codex_exec") == .terminal)
        #expect(CodexSessionState.origin(forOriginator: "codex exec") == .terminal)
        #expect(CodexSessionState.origin(forOriginator: "Codex Desktop") == .desktopApp)
        #expect(CodexSessionState.origin(forOriginator: "vscode") == .unknown)
    }
}
