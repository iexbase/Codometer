@testable import CodometerClaude
import CodometerCore
import Foundation
import Testing

private let origin = Date(timeIntervalSince1970: 1_789_600_000)

private func at(_ seconds: TimeInterval) -> Date {
    origin.addingTimeInterval(seconds)
}

private func session(
    _ activity: AgentActivity,
    since seconds: TimeInterval,
    id: String = "s1",
    lastEventAt: Date? = nil
) throws -> AgentSession {
    try AgentSession(
        id: id,
        title: "Task",
        projectPath: "/Users/me/project",
        activity: activity,
        detail: activity == .waiting ? "permission prompt" : nil,
        activitySince: at(seconds),
        processID: 42,
        origin: .terminal,
        lastEventAt: lastEventAt
    )
}

@Suite("Claude turn tracker")
struct TurnTrackerTests {
    @Test("working → idle produces a turn from the working record's start to the idle record's time")
    func completedTurn() throws {
        var tracker = TurnTracker()
        #expect(tracker.apply(to: [try session(.idle, since: 0)], now: at(1)).first?.lastTurn == nil)
        #expect(tracker.apply(to: [try session(.working, since: 10)], now: at(11)).first?.lastTurn == nil)
        #expect(tracker.hasOpenTurn(sessionID: "s1"))
        _ = tracker.apply(to: [try session(.working, since: 10)], now: at(100))

        let ended = tracker.apply(to: [try session(.idle, since: 262)], now: at(263))
        let turn = try #require(ended.first?.lastTurn)
        #expect(turn.startedAt == at(10))
        #expect(turn.endedAt == at(262))
        #expect(turn.duration == 252)
        #expect(turn.firstTokenLatency == nil)
        #expect(!turn.wasAborted)
        #expect(!tracker.hasOpenTurn(sessionID: "s1"))
        // Everything else about the session is preserved by the rebuild.
        #expect(ended.first?.origin == .terminal)
        #expect(ended.first?.detail == nil)
        #expect(ended.first?.processID == 42)
    }

    @Test("The last turn stays on later scans until the next turn ends")
    func keepsLastTurn() throws {
        var tracker = TurnTracker()
        _ = tracker.apply(to: [try session(.working, since: 0)], now: at(1))
        _ = tracker.apply(to: [try session(.idle, since: 30)], now: at(31))
        #expect(tracker.apply(to: [try session(.idle, since: 30)], now: at(500)).first?.lastTurn?.duration == 30)
        // A new turn is running: the previous one is still the last finished turn.
        #expect(tracker.apply(to: [try session(.working, since: 600)], now: at(601)).first?.lastTurn?.duration == 30)
        let next = tracker.apply(to: [try session(.idle, since: 700)], now: at(701))
        #expect(next.first?.lastTurn?.startedAt == at(600))
        #expect(next.first?.lastTurn?.duration == 100)
    }

    @Test("A permission prompt in the middle belongs to the same turn")
    func waitingInsideTurn() throws {
        var tracker = TurnTracker()
        _ = tracker.apply(to: [try session(.working, since: 0)], now: at(1))
        _ = tracker.apply(to: [try session(.waiting, since: 40)], now: at(41))
        _ = tracker.apply(to: [try session(.working, since: 90)], now: at(91))
        let turn = try #require(tracker.apply(to: [try session(.idle, since: 120)], now: at(121)).first?.lastTurn)
        #expect(turn.startedAt == at(0))
        #expect(turn.duration == 120)
    }

    @Test("An idle record without a newer status time ends the turn now")
    func fallbackToNow() throws {
        var tracker = TurnTracker()
        _ = tracker.apply(to: [try session(.working, since: 50)], now: at(51))
        let turn = try #require(tracker.apply(to: [try session(.idle, since: 5)], now: at(80)).first?.lastTurn)
        #expect(turn.endedAt == at(80))
        #expect(turn.duration == 30)
    }

    @Test("Sessions first seen waiting or idle have no turn; zero-length turns are dropped")
    func noTurn() throws {
        var tracker = TurnTracker()
        _ = tracker.apply(to: [try session(.waiting, since: 0)], now: at(1))
        #expect(tracker.apply(to: [try session(.idle, since: 20)], now: at(21)).first?.lastTurn == nil)

        _ = tracker.apply(to: [try session(.working, since: 50)], now: at(50))
        #expect(tracker.apply(to: [try session(.idle, since: 50)], now: at(50)).first?.lastTurn == nil)
    }

    @Test("Ended sessions are forgotten")
    func forgetsEndedSessions() throws {
        var tracker = TurnTracker()
        _ = tracker.apply(to: [try session(.working, since: 0, id: "a"), try session(.working, since: 0, id: "b")], now: at(1))
        _ = tracker.apply(to: [try session(.idle, since: 10, id: "a"), try session(.working, since: 0, id: "b")], now: at(11))
        #expect(tracker.lastTurn(sessionID: "a") != nil)

        _ = tracker.apply(to: [], now: at(20))
        #expect(tracker.lastTurn(sessionID: "a") == nil)
        #expect(!tracker.hasOpenTurn(sessionID: "b"))
        #expect(tracker.apply(to: [try session(.idle, since: 30, id: "b")], now: at(31)).first?.lastTurn == nil)
    }

    @Test("Turns are tracked per session")
    func independentSessions() throws {
        var tracker = TurnTracker()
        _ = tracker.apply(to: [try session(.working, since: 0, id: "a"), try session(.idle, since: 0, id: "b")], now: at(1))
        _ = tracker.apply(to: [try session(.working, since: 0, id: "a"), try session(.working, since: 5, id: "b")], now: at(6))
        let result = tracker.apply(
            to: [try session(.working, since: 0, id: "a"), try session(.idle, since: 25, id: "b")],
            now: at(26)
        )
        #expect(result.map(\.id) == ["a", "b"])
        #expect(result[0].lastTurn == nil)
        #expect(result[1].lastTurn?.duration == 20)
    }
}

@Suite("Claude session activity folding")
struct SessionActivityFoldingTests {
    @Test("Transcript activity newer than the record becomes lastEventAt")
    func foldsTranscriptActivity() throws {
        let sessions = [try session(.working, since: 0, lastEventAt: at(10))]
        let folded = SessionActivityFolding.fold(sessions, activity: ["s1": at(100)], previous: [], now: at(120))
        #expect(folded.first?.lastEventAt == at(100))
        #expect(folded.first?.lastTurn == nil)
        #expect(folded.first?.activity == .working)
    }

    @Test("Small moves keep the published value so the session compares equal")
    func granularity() throws {
        let published = SessionActivityFolding.fold(
            [try session(.working, since: 0)],
            activity: ["s1": at(100)],
            previous: [],
            now: at(100)
        )
        let slightlyLater = SessionActivityFolding.fold(
            [try session(.working, since: 0)],
            activity: ["s1": at(110)],
            previous: published,
            now: at(110)
        )
        #expect(slightlyLater == published)
        let muchLater = SessionActivityFolding.fold(
            [try session(.working, since: 0)],
            activity: ["s1": at(100 + SessionActivityFolding.granularity)],
            previous: published,
            now: at(200)
        )
        #expect(muchLater.first?.lastEventAt == at(130))
    }

    @Test("Values never move backwards or into the future")
    func monotonicAndClamped() throws {
        let previous = [try session(.working, since: 0, lastEventAt: at(500))]
        let older = SessionActivityFolding.fold(
            [try session(.working, since: 0, lastEventAt: at(100))],
            activity: [:],
            previous: previous,
            now: at(600)
        )
        #expect(older.first?.lastEventAt == at(500))
        let future = SessionActivityFolding.fold(
            [try session(.working, since: 0)],
            activity: ["s1": at(10_000)],
            previous: [],
            now: at(700)
        )
        #expect(future.first?.lastEventAt == at(700))
        #expect(SessionActivityFolding.fold([try session(.idle, since: 0)], activity: [:], previous: [], now: at(1))
            .first?.lastEventAt == nil)
    }
}
