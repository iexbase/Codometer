@testable import CodometerCodex
import CodometerCore
import Foundation
import Testing

@Suite("Codex waiting detection and turn timing")
struct CodexWaitingTests {
    private func header(policy: String = #""on-request""#, reviewer: String? = "user") -> [String] {
        [
            Rollout.sessionMeta(at: "2026-09-16T18:54:41.845Z"),
            Rollout.turnContext(at: "2026-09-16T18:55:00.000Z", policy: policy, reviewer: reviewer),
            Rollout.taskStarted(at: "2026-09-16T18:55:00.100Z"),
        ]
    }

    private let callTime = "2026-09-16T18:55:10.000Z"

    @Test("approval_policy never: an escalated call never waits")
    func policyNever() async throws {
        let profile = try RolloutProfile()
        try profile.write(header(policy: #""never""#) + [Rollout.escalatedExec(at: callTime, callID: "call_1")])
        let snapshot = await profile.reader().bootstrap(now: Rollout.date("2026-09-16T18:56:00Z"))
        #expect(snapshot.sessions.first?.activity == .working)
        #expect(snapshot.needsRecheckAt == nil)
    }

    @Test("on-request reviewed by the user: waiting after 2 s, cleared by the call output")
    func onRequestWaits() async throws {
        let profile = try RolloutProfile()
        try profile.write(header() + [Rollout.escalatedExec(at: callTime, callID: "call_1")])
        let reader = profile.reader()

        let early = await reader.bootstrap(now: Rollout.date("2026-09-16T18:55:11Z"))
        #expect(early.sessions.first?.activity == .working)
        #expect(early.needsRecheckAt == Rollout.date("2026-09-16T18:55:12Z"))

        let prompted = await reader.snapshot(now: Rollout.date("2026-09-16T18:55:12Z"))
        let waiting = try #require(prompted.sessions.first)
        #expect(waiting.activity == .waiting)
        #expect(waiting.detail == "permission prompt")
        #expect(waiting.activitySince == Rollout.date(callTime))
        #expect(prompted.needsRecheckAt == nil)

        try profile.append([Rollout.customToolCallOutput(at: "2026-09-16T18:55:40.000Z", callID: "call_1")])
        let resolved = await reader.process(changedPaths: [profile.file.path], now: Rollout.date("2026-09-16T18:55:41Z"))
        #expect(resolved.sessions.first?.activity == .working)
        #expect(resolved.sessions.first?.detail == nil)
        #expect(resolved.sessions.first?.activitySince == Rollout.date("2026-09-16T18:55:00.100Z"))
    }

    @Test("A function call output for another call does not clear the wait")
    func otherOutput() async throws {
        let profile = try RolloutProfile()
        try profile.write(header() + [
            Rollout.escalatedFunctionCall(at: callTime, callID: "call_1"),
            Rollout.functionCallOutput(at: "2026-09-16T18:55:11.000Z", callID: "call_other"),
        ])
        let snapshot = await profile.reader().bootstrap(now: Rollout.date("2026-09-16T18:55:30Z"))
        #expect(snapshot.sessions.first?.activity == .waiting)
    }

    @Test("Automatic review never waits for the user")
    func autoReview() async throws {
        let profile = try RolloutProfile()
        try profile.write(header(reviewer: "auto_review") + [Rollout.escalatedExec(at: callTime, callID: "call_1")])
        let snapshot = await profile.reader().bootstrap(now: Rollout.date("2026-09-16T18:57:00Z"))
        #expect(snapshot.sessions.first?.activity == .working)
        #expect(snapshot.needsRecheckAt == nil)
    }

    @Test("A structured policy or a log without a reviewer may still ask the user")
    func structuredPolicyWaits() async throws {
        let profile = try RolloutProfile()
        try profile.write(header(policy: #"{"granular":{"sandbox_approval":true}}"#, reviewer: nil)
            + [Rollout.escalatedExec(at: callTime, callID: "call_1")])
        let snapshot = await profile.reader().bootstrap(now: Rollout.date("2026-09-16T18:55:30Z"))
        #expect(snapshot.sessions.first?.activity == .waiting)
    }

    @Test("The end of the turn clears every pending call")
    func turnEndClears() async throws {
        let profile = try RolloutProfile()
        try profile.write(header() + [
            Rollout.escalatedExec(at: callTime, callID: "call_1"),
            Rollout.requestUserInput(at: "2026-09-16T18:55:11.000Z", callID: "call_2"),
        ])
        let reader = profile.reader()
        #expect(await reader.bootstrap(now: Rollout.date("2026-09-16T18:55:30Z")).sessions.first?.activity == .waiting)

        try profile.append([Rollout.turnAborted(at: "2026-09-16T18:56:00.000Z")])
        let aborted = await reader.process(changedPaths: [profile.file.path], now: Rollout.date("2026-09-16T18:56:01Z"))
        #expect(aborted.sessions.first?.activity == .idle)

        // A new turn starts clean: nothing pending from the aborted one.
        try profile.append([Rollout.taskStarted(at: "2026-09-16T18:57:00.000Z", turnID: "turn-2")])
        let next = await reader.process(changedPaths: [profile.file.path], now: Rollout.date("2026-09-16T18:58:00Z"))
        #expect(next.sessions.first?.activity == .working)
        #expect(next.needsRecheckAt == nil)
    }

    @Test("request_user_input waits for input right away; its output clears it")
    func userInput() async throws {
        let profile = try RolloutProfile()
        try profile.write(header(policy: #""never""#) + [Rollout.requestUserInput(at: callTime, callID: "call_q")])
        let reader = profile.reader()
        let asked = await reader.bootstrap(now: Rollout.date("2026-09-16T18:55:10.500Z"))
        let session = try #require(asked.sessions.first)
        #expect(session.activity == .waiting)
        #expect(session.detail == "input needed")

        try profile.append([Rollout.functionCallOutput(at: "2026-09-16T18:56:10.000Z", callID: "call_q")])
        let answered = await reader.process(changedPaths: [profile.file.path], now: Rollout.date("2026-09-16T18:56:11Z"))
        #expect(answered.sessions.first?.activity == .working)
    }

    @Test("request_user_input_async does not block the turn")
    func asyncInput() async throws {
        let profile = try RolloutProfile()
        try profile.write(header() + [Rollout.requestUserInput(at: callTime, callID: "call_q", name: "request_user_input_async")])
        let snapshot = await profile.reader().bootstrap(now: Rollout.date("2026-09-16T18:56:00Z"))
        #expect(snapshot.sessions.first?.activity == .working)
    }

    @Test("A prompt left for hours in a silent log is treated as abandoned")
    func staleWait() async throws {
        let profile = try RolloutProfile()
        try profile.write(header() + [Rollout.escalatedExec(at: callTime, callID: "call_1")])
        let reader = profile.reader()
        let later = await reader.bootstrap(now: Rollout.date("2026-09-16T20:00:00Z"))
        #expect(later.sessions.first?.activity == .waiting)
        let muchLater = await reader.snapshot(now: Rollout.date("2026-09-16T21:00:00Z"))
        #expect(!muchLater.sessions.contains { $0.activity == .waiting })
    }

    @Test("Turn timing: duration, first token, start derived from the end; origin and model")
    func timing() async throws {
        let profile = try RolloutProfile()
        try profile.write(header() + [
            Rollout.message(at: "2026-09-16T18:55:05.000Z"),
            Rollout.taskComplete(at: "2026-09-16T18:59:12.100Z"),
        ])
        let reader = profile.reader()
        let snapshot = await reader.bootstrap(now: Rollout.date("2026-09-16T19:00:00Z"))
        let session = try #require(snapshot.sessions.first)
        #expect(session.activity == .idle)
        #expect(session.origin == .terminal)
        #expect(session.model == Rollout.model)
        #expect(session.title == "weather-app")
        let turn = try #require(session.lastTurn)
        #expect(turn.duration == 252)
        #expect(turn.firstTokenLatency == 2.8)
        #expect(turn.endedAt == Rollout.date("2026-09-16T18:59:12.100Z"))
        #expect(abs(turn.startedAt.timeIntervalSince(Rollout.date("2026-09-16T18:55:00.100Z"))) < 0.001)
        #expect(!turn.wasAborted)
        // Published in whole minutes so busy logs do not republish sessions on every line.
        #expect(session.lastEventAt == Rollout.date("2026-09-16T18:59:00Z"))

        try profile.append([
            Rollout.taskStarted(at: "2026-09-16T19:01:00.000Z", turnID: "turn-2"),
            Rollout.turnAborted(at: "2026-09-16T19:01:05.000Z", turnID: "turn-2", durationMs: "5000"),
        ])
        let aborted = try #require(await reader.process(changedPaths: [profile.file.path], now: Rollout.date("2026-09-16T19:02:00Z")).sessions.first?.lastTurn)
        #expect(aborted.wasAborted)
        #expect(aborted.duration == 5)
        #expect(aborted.firstTokenLatency == nil)
    }

    @Test("Without duration_ms the turn is measured from its start event")
    func timingFallback() async throws {
        let profile = try RolloutProfile()
        try profile.write(header() + [Rollout.taskComplete(at: "2026-09-16T18:56:00.100Z", durationMs: "null", firstTokenMs: "999999")])
        let snapshot = await profile.reader().bootstrap(now: Rollout.date("2026-09-16T18:57:00Z"))
        let turn = try #require(snapshot.sessions.first?.lastTurn)
        #expect(abs(turn.duration - 60) < 0.001)
        #expect(turn.firstTokenLatency == nil)
    }

    @Test("A subagent file of the same session does not hide the parent's prompt")
    func subagentFile() async throws {
        let profile = try RolloutProfile()
        try profile.write(header() + [Rollout.escalatedExec(at: callTime, callID: "call_1")])
        let subagentID = "0199bbbb-0000-4000-8000-000000000001"
        try profile.write([
            Rollout.sessionMeta(at: "2026-09-16T18:55:20.000Z", threadID: subagentID),
            Rollout.taskStarted(at: "2026-09-16T18:55:21.000Z", turnID: "sub-turn"),
            Rollout.message(at: "2026-09-16T18:55:40.000Z"),
        ], to: profile.sibling(named: "rollout-2026-09-16T22-55-20-\(subagentID).jsonl"))
        let reader = profile.reader()
        let snapshot = await reader.bootstrap(now: Rollout.date("2026-09-16T18:55:45Z"))
        #expect(snapshot.sessions.count == 1)
        #expect(snapshot.sessions.first?.activity == .waiting)

        try profile.append([Rollout.customToolCallOutput(at: "2026-09-16T18:55:50.000Z", callID: "call_1")])
        let resolved = await reader.process(changedPaths: [profile.file.path], now: Rollout.date("2026-09-16T18:55:51Z"))
        #expect(resolved.sessions.map(\.activity) == [.working])
    }

    @Test("A subagent that finishes its turn while the parent still works keeps the session working")
    func subagentFinishesFirst() async throws {
        let profile = try RolloutProfile()
        try profile.write(header() + [Rollout.message(at: "2026-09-16T18:55:05.000Z")])
        let subagentID = "0199bbbb-0000-4000-8000-000000000002"
        let subagent = profile.sibling(named: "rollout-2026-09-16T22-55-06-\(subagentID).jsonl")
        try profile.write([
            Rollout.sessionMeta(at: "2026-09-16T18:55:06.000Z", threadID: subagentID),
            Rollout.taskStarted(at: "2026-09-16T18:55:07.000Z", turnID: "sub-turn"),
        ], to: subagent)
        let reader = profile.reader()
        let bothWorking = await reader.bootstrap(now: Rollout.date("2026-09-16T18:56:00Z"))
        #expect(bothWorking.sessions.map(\.activity) == [.working])
        #expect(bothWorking.sessions.first?.activitySince == Rollout.date("2026-09-16T18:55:00.100Z"))

        // The subagent's file is now the newest, and idle; the parent's turn is still open.
        try profile.append([Rollout.taskComplete(at: "2026-09-16T18:57:30.000Z", turnID: "sub-turn", durationMs: "143000")], to: subagent)
        let subagentDone = await reader.process(changedPaths: [subagent.path], now: Rollout.date("2026-09-16T18:57:31Z"))
        let session = try #require(subagentDone.sessions.first)
        #expect(subagentDone.sessions.count == 1)
        #expect(session.activity == .working)
        #expect(session.activitySince == Rollout.date("2026-09-16T18:55:00.100Z"))
        // The subagent's activity counts, so the parent's silence while it waits does not look stuck.
        #expect(session.lastEventAt == Rollout.date("2026-09-16T18:57:00Z"))

        try profile.append([Rollout.taskComplete(at: "2026-09-16T18:58:00.000Z", durationMs: "179900")])
        let parentDone = await reader.process(changedPaths: [profile.file.path], now: Rollout.date("2026-09-16T18:58:01Z"))
        #expect(parentDone.sessions.map(\.activity) == [.idle])
        #expect(parentDone.sessions.first?.lastTurn?.duration == 179.9)
    }

    @Test("A subagent left open by an interrupted parent turn neither works nor waits")
    func subagentStoppedWithParent() async throws {
        let profile = try RolloutProfile()
        try profile.write(header() + [Rollout.message(at: "2026-09-16T18:55:05.000Z")])
        let subagentID = "0199bbbb-0000-4000-8000-000000000003"
        let subagent = profile.sibling(named: "rollout-2026-09-16T22-55-06-\(subagentID).jsonl")
        try profile.write([
            Rollout.sessionMeta(at: "2026-09-16T18:55:06.000Z", threadID: subagentID),
            Rollout.turnContext(at: "2026-09-16T18:55:07.000Z", turnID: "sub-turn"),
            Rollout.taskStarted(at: "2026-09-16T18:55:07.100Z", turnID: "sub-turn"),
            Rollout.escalatedExec(at: "2026-09-16T18:55:08.000Z", callID: "call_sub"),
        ], to: subagent)
        let reader = profile.reader()
        let asking = await reader.bootstrap(now: Rollout.date("2026-09-16T18:55:30Z"))
        #expect(asking.sessions.map(\.activity) == [.waiting])

        // The user interrupts the parent; the subagent's file is never closed.
        try profile.append([Rollout.turnAborted(at: "2026-09-16T18:56:00.000Z", durationMs: "59900")])
        let interrupted = await reader.process(changedPaths: [profile.file.path], now: Rollout.date("2026-09-16T18:56:01Z"))
        #expect(interrupted.sessions.map(\.activity) == [.idle])
        #expect(interrupted.sessions.first?.lastTurn?.wasAborted == true)

        // A subagent still writing after the parent's turn ended keeps counting.
        try profile.append([Rollout.message(at: "2026-09-16T18:56:10.000Z")], to: subagent)
        let stillActive = await reader.process(changedPaths: [subagent.path], now: Rollout.date("2026-09-16T18:56:11Z"))
        #expect(stillActive.sessions.map(\.activity) == [.waiting])
    }

    @Test("A turn that ends without a measurable duration does not keep the previous turn's timing")
    func unmeasurableTurn() async throws {
        let profile = try RolloutProfile()
        try profile.write(header() + [Rollout.taskComplete(at: "2026-09-16T18:56:00.000Z", durationMs: "59900")])
        let reader = profile.reader()
        #expect(await reader.bootstrap(now: Rollout.date("2026-09-16T18:56:10Z")).sessions.first?.lastTurn?.duration == 59.9)

        try profile.append([Rollout.taskComplete(at: "2026-09-16T18:57:00.000Z", turnID: "turn-2", durationMs: "null")])
        let snapshot = await reader.process(changedPaths: [profile.file.path], now: Rollout.date("2026-09-16T18:57:10Z"))
        #expect(snapshot.sessions.first?.activity == .idle)
        #expect(snapshot.sessions.first?.lastTurn == nil)
    }

    @Test("Snapshots are numbered in the order they were taken")
    func generations() async throws {
        let profile = try RolloutProfile()
        try profile.write(header())
        let reader = profile.reader()
        let first = await reader.bootstrap(now: Rollout.date("2026-09-16T18:56:00Z"))
        let second = await reader.snapshot(now: Rollout.date("2026-09-16T18:56:01Z"))
        let third = await reader.process(changedPaths: [profile.file.path], now: Rollout.date("2026-09-16T18:56:02Z"))
        #expect(first.generation < second.generation)
        #expect(second.generation < third.generation)
    }

    @Test("A log without turn events is idle since its last activity, not since launch")
    func oldIdleLog() async throws {
        let profile = try RolloutProfile()
        try profile.write([
            Rollout.tokenUsageRecord(at: "2026-09-16T12:00:00.000Z", responseID: "resp_old"),
            Rollout.tokenCount(at: "2026-09-16T12:00:00.100Z"),
        ])
        let reader = profile.reader()
        #expect(await reader.bootstrap(now: Rollout.date("2026-09-16T18:00:00Z")).sessions.isEmpty)
        #expect(await reader.snapshot(now: Rollout.date("2026-09-16T12:10:00Z")).sessions.map(\.activity) == [.idle])
    }

    @Test("Desktop sessions are marked as the desktop app")
    func desktopOrigin() async throws {
        let profile = try RolloutProfile()
        try profile.write([Rollout.sessionMeta(at: "2026-09-16T18:54:41.845Z", originator: "Codex Desktop"), Rollout.taskStarted(at: "2026-09-16T18:55:00.000Z")])
        let snapshot = await profile.reader().bootstrap(now: Rollout.date("2026-09-16T18:55:30Z"))
        #expect(snapshot.sessions.first?.origin == .desktopApp)
    }
}
