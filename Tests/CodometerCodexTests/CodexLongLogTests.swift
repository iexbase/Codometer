@testable import CodometerCodex
import CodometerCore
import Foundation
import Testing

@Suite("Codex logs longer than the initial tail")
struct CodexLongLogTests {
    /// `megabytes` of filler stamped between 18:55:01 and 18:55:09.
    private func filler(megabytes: Double) -> [String] {
        let lineBytes = 16 * 1_024
        let count = Int(megabytes * 1_048_576) / lineBytes + 1
        return (0..<count).map { index in
            Rollout.filler(at: "2026-09-16T18:55:0\(1 + index * 8 / count).000Z", bytes: lineBytes)
        }
    }

    @Test("Header and turn context far before the tail are recovered, so a prompt is still detected")
    func recoversTurn() async throws {
        let profile = try RolloutProfile()
        try profile.write([
            Rollout.sessionMeta(at: "2026-09-16T18:54:41.845Z", originator: "Codex Desktop"),
            Rollout.turnContext(at: "2026-09-16T18:55:00.000Z"),
            Rollout.taskStarted(at: "2026-09-16T18:55:00.100Z"),
        ] + filler(megabytes: 2.6) + [Rollout.escalatedExec(at: "2026-09-16T18:55:10.000Z", callID: "call_1")])

        let snapshot = await profile.reader().bootstrap(now: Rollout.date("2026-09-16T18:55:20Z"))
        let session = try #require(snapshot.sessions.first)
        #expect(session.activity == .waiting)
        #expect(session.detail == "permission prompt")
        #expect(session.origin == .desktopApp)
        #expect(session.model == Rollout.model)
        #expect(session.projectPath == Rollout.project)
    }

    @Test("A long turn whose start is before the tail is recovered even when a later turn context is in the tail")
    func recoversStartBehindLaterContext() async throws {
        let profile = try RolloutProfile()
        try profile.write([
            Rollout.sessionMeta(at: "2026-09-16T18:54:41.845Z"),
            Rollout.turnContext(at: "2026-09-16T18:55:00.000Z"),
            Rollout.taskStarted(at: "2026-09-16T18:55:00.100Z"),
        ] + filler(megabytes: 2.6) + [
            // Written again after a compaction, inside the tail.
            Rollout.turnContext(at: "2026-09-16T18:55:09.500Z"),
            Rollout.escalatedExec(at: "2026-09-16T18:55:10.000Z", callID: "call_1"),
        ])

        let snapshot = await profile.reader().bootstrap(now: Rollout.date("2026-09-16T18:55:20Z"))
        let session = try #require(snapshot.sessions.first)
        #expect(session.activity == .waiting)
        #expect(session.activitySince == Rollout.date("2026-09-16T18:55:10.000Z"))
    }

    @Test("Only the missing kind of turn line is searched for")
    func searchesOnlyMissing() throws {
        let profile = try RolloutProfile()
        try profile.write([
            Rollout.turnContext(at: "2026-09-16T18:52:00.000Z", turnID: "new"),
            Rollout.taskStarted(at: "2026-09-16T18:52:00.100Z", turnID: "new"),
        ] + filler(megabytes: 1.2))
        let size = try #require(try FileManager.default.attributesOfItem(atPath: profile.file.path)[.size] as? UInt64)
        let offset = size - 64 * 1_024
        let boundaryOnly = RolloutFileHistory.latestTurnEvents(of: profile.file, before: offset, needsContext: false)
        #expect(boundaryOnly == [.turnStarted(turnID: "new", at: Rollout.date("2026-09-16T18:52:00.100Z"))])
        let contextOnly = RolloutFileHistory.latestTurnEvents(of: profile.file, before: offset, needsBoundary: false)
        #expect(contextOnly.count == 1)
        #expect(RolloutFileHistory.latestTurnEvents(of: profile.file, before: offset, needsContext: false, needsBoundary: false).isEmpty)
    }

    @Test("A turn line cut by a window start is read whole from the next window")
    func lineAcrossWindows() throws {
        let profile = try RolloutProfile()
        let context = Rollout.turnContext(at: "2026-09-16T18:52:00.000Z", turnID: "t")
        let started = Rollout.taskStarted(at: "2026-09-16T18:52:00.100Z", turnID: "t")
        // One content line longer than a window follows the turn start.
        let long = Rollout.filler(at: "2026-09-16T18:52:01.000Z", bytes: RolloutFileHistory.windowBytes * 3 / 2)
        try profile.write([context, started, long])
        // The first window starts 100 bytes into the task_started line and holds no complete line.
        let startedOffset = UInt64(context.utf8.count + 1)
        let firstWindowEnd = startedOffset + 100 + UInt64(RolloutFileHistory.windowBytes)
        let events = RolloutFileHistory.latestTurnEvents(of: profile.file, before: firstWindowEnd - RolloutFileHistory.tailOverlapBytes)
        #expect(events.count == 2)
        #expect(events.last == .turnStarted(turnID: "t", at: Rollout.date("2026-09-16T18:52:00.100Z")))
    }

    @Test("Window continuation: past the first newline, or skip a window that is one long line")
    func nextWindowEnd() {
        #expect(RolloutFileHistory.nextWindowEnd(in: Data("tail\nhead".utf8), start: 100, end: 109) == 105)
        #expect(RolloutFileHistory.nextWindowEnd(in: Data("no newline".utf8), start: 100, end: 110) == 100)
        #expect(RolloutFileHistory.nextWindowEnd(in: Data("ends here\n".utf8), start: 100, end: 110) == 100)
    }

    @Test("A turn that ended before the tail stays ended")
    func recoversFinishedTurn() async throws {
        let profile = try RolloutProfile()
        try profile.write([
            Rollout.sessionMeta(at: "2026-09-16T18:54:41.845Z"),
            Rollout.turnContext(at: "2026-09-16T18:54:50.000Z"),
            Rollout.taskStarted(at: "2026-09-16T18:54:50.100Z"),
            Rollout.taskComplete(at: "2026-09-16T18:55:00.000Z", durationMs: "9900", firstTokenMs: "700"),
        ] + filler(megabytes: 1.5))

        let snapshot = await profile.reader().bootstrap(now: Rollout.date("2026-09-16T18:56:00Z"))
        let session = try #require(snapshot.sessions.first)
        #expect(session.activity == .idle)
        #expect(session.lastTurn?.firstTokenLatency == 0.7)
        #expect(session.model == Rollout.model)
    }

    @Test("The latest boundary wins and events come back oldest first")
    func latestBoundary() throws {
        let profile = try RolloutProfile()
        let lines = [
            Rollout.turnContext(at: "2026-09-16T18:50:00.000Z", turnID: "old", model: "old-model"),
            Rollout.taskComplete(at: "2026-09-16T18:51:00.000Z", turnID: "old"),
            Rollout.turnContext(at: "2026-09-16T18:52:00.000Z", turnID: "new"),
            Rollout.taskStarted(at: "2026-09-16T18:52:00.100Z", turnID: "new"),
        ] + filler(megabytes: 1.2)
        try profile.write(lines)
        let size = try #require(try FileManager.default.attributesOfItem(atPath: profile.file.path)[.size] as? UInt64)
        let events = RolloutFileHistory.latestTurnEvents(of: profile.file, before: size - 64 * 1_024)
        #expect(events.count == 2)
        guard case .turnContext(_, "new"?, _, _, _, _, _) = events.first, case .turnStarted("new"?, _) = events.last else {
            Issue.record("expected the newest turn context then its start")
            return
        }
    }

    @Test("First line reads are bounded and refuse symlinks")
    func firstLine() throws {
        let profile = try RolloutProfile()
        try profile.write([Rollout.sessionMeta(at: "2026-09-16T18:54:41.845Z"), Rollout.message(at: "2026-09-16T18:55:00.000Z")])
        let header = try #require(RolloutFileHistory.firstLine(of: profile.file))
        #expect(CodexRolloutParser.events(in: header).count == 1)
        #expect(RolloutFileHistory.firstLine(of: profile.file, maximumBytes: 64) == nil)

        let link = profile.sibling(named: "rollout-link.jsonl")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: profile.file)
        #expect(RolloutFileHistory.firstLine(of: link) == nil)
        #expect(RolloutFileHistory.latestTurnEvents(of: link, before: 1_000).isEmpty)
        #expect(RolloutFileHistory.firstLine(of: profile.sibling(named: "missing.jsonl")) == nil)
    }

    @Test("Only whole lines count inside a window")
    func completeLines() {
        let bytes = Data("tail\nfirst\n\nsecond\npartial".utf8)
        let inside = RolloutFileHistory.completeLines(in: bytes, startsFileOrLine: false)
        #expect(inside.map { String(decoding: bytes[$0], as: UTF8.self) } == ["first", "second"])
        let atStart = RolloutFileHistory.completeLines(in: bytes, startsFileOrLine: true)
        #expect(atStart.map { String(decoding: bytes[$0], as: UTF8.self) } == ["tail", "first", "second"])
        #expect(RolloutFileHistory.completeLines(in: Data("no newline".utf8), startsFileOrLine: true).isEmpty)
        #expect(RolloutFileHistory.completeLines(in: Data(), startsFileOrLine: true).isEmpty)
    }
}
