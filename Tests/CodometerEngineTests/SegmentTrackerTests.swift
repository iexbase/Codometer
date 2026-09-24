import CodometerCore
@testable import CodometerEngine
import Foundation
import Testing

private let base = Date(timeIntervalSince1970: 1_789_599_900)
private let account = AccountID()

private func at(_ seconds: TimeInterval) -> Date {
    base.addingTimeInterval(seconds)
}

private func session(
    _ id: String,
    _ activity: AgentActivity,
    since seconds: TimeInterval,
    title: String? = "Задача",
    project: String? = "/Users/me/app"
) throws -> AgentSession {
    try AgentSession(
        id: id, title: title, projectPath: project, activity: activity, detail: nil,
        activitySince: at(seconds), processID: nil
    )
}

/// The segments opened and closed by a list of writes, as (session, activity, start, end?) for readable checks.
private struct Change: Equatable, CustomStringConvertible {
    let kind: String
    let session: String
    let activity: AgentActivity
    let start: TimeInterval
    let time: TimeInterval

    var description: String { "\(kind) \(session) \(activity) \(start) @\(time)" }
}

private func changes(_ writes: [HistoryWrite]) -> [Change] {
    writes.compactMap { write in
        switch write {
        case let .openSegment(segment, lastSeen):
            Change(kind: "open", session: segment.sessionID, activity: segment.activity,
                   start: segment.start.timeIntervalSince(base), time: lastSeen.timeIntervalSince(base))
        case let .closeSegment(segment, end):
            Change(kind: "close", session: segment.sessionID, activity: segment.activity,
                   start: segment.start.timeIntervalSince(base), time: end.timeIntervalSince(base))
        default:
            nil
        }
    }
}

private func open(_ session: String, _ activity: AgentActivity, start: TimeInterval, now: TimeInterval) -> Change {
    Change(kind: "open", session: session, activity: activity, start: start, time: now)
}

private func close(_ session: String, _ activity: AgentActivity, start: TimeInterval, end: TimeInterval) -> Change {
    Change(kind: "close", session: session, activity: activity, start: start, time: end)
}

@Suite("Segment tracker")
struct SegmentTrackerTests {
    @Test("Working and waiting open segments; leaving the activity closes them at the new activity's start")
    func transitions() throws {
        var tracker = SegmentTracker()
        var writes = tracker.update(accountID: account, sessions: [try session("s1", .working, since: 10)], now: at(12), floor: at(0))
        #expect(changes(writes) == [open("s1", .working, start: 10, now: 12)])

        writes = tracker.update(accountID: account, sessions: [try session("s1", .working, since: 10)], now: at(20), floor: at(0))
        #expect(writes.isEmpty)

        writes = tracker.update(accountID: account, sessions: [try session("s1", .waiting, since: 40)], now: at(41), floor: at(0))
        #expect(changes(writes) == [close("s1", .working, start: 10, end: 40), open("s1", .waiting, start: 40, now: 41)])

        writes = tracker.update(accountID: account, sessions: [try session("s1", .idle, since: 90)], now: at(95), floor: at(0))
        #expect(changes(writes) == [close("s1", .waiting, start: 40, end: 90)])
        #expect(tracker.openSegments.isEmpty)

        writes = tracker.update(accountID: account, sessions: [try session("s1", .idle, since: 90)], now: at(99), floor: at(0))
        #expect(writes.isEmpty)
    }

    @Test("A disappearing session closes now; starts are clamped between the floor and now")
    func clamping() throws {
        var tracker = SegmentTracker()
        var writes = tracker.update(
            accountID: account,
            sessions: [try session("old", .working, since: -3_600), try session("future", .waiting, since: 500)],
            now: at(30),
            floor: at(20)
        )
        #expect(changes(writes) == [open("old", .working, start: 20, now: 30), open("future", .waiting, start: 30, now: 30)])

        writes = tracker.update(accountID: account, sessions: [], now: at(70), floor: at(20))
        #expect(changes(writes) == [close("future", .waiting, start: 30, end: 70), close("old", .working, start: 20, end: 70)])
    }

    @Test("The same activity resuming within 3 s extends the previous segment; a longer gap starts a new one")
    func shortGapMerge() throws {
        var tracker = SegmentTracker()
        _ = tracker.update(accountID: account, sessions: [try session("s1", .working, since: 0)], now: at(1), floor: at(0))
        _ = tracker.update(accountID: account, sessions: [try session("s1", .idle, since: 50)], now: at(50), floor: at(0))

        var writes = tracker.update(accountID: account, sessions: [try session("s1", .working, since: 52.5)], now: at(53), floor: at(0))
        #expect(changes(writes) == [open("s1", .working, start: 0, now: 53)])
        #expect(tracker.openSegments.map(\.start) == [at(0)])

        _ = tracker.update(accountID: account, sessions: [try session("s1", .idle, since: 60)], now: at(60), floor: at(0))
        writes = tracker.update(accountID: account, sessions: [try session("s1", .working, since: 64)], now: at(64), floor: at(0))
        #expect(changes(writes) == [open("s1", .working, start: 64, now: 64)])
    }

    @Test("A different activity never merges, and a session's segments never overlap")
    func noOverlap() throws {
        var tracker = SegmentTracker()
        _ = tracker.update(accountID: account, sessions: [try session("s1", .working, since: 0)], now: at(0), floor: at(0))
        _ = tracker.update(accountID: account, sessions: [try session("s1", .waiting, since: 10)], now: at(10), floor: at(0))
        // A stale snapshot claims work started before the waiting segment did.
        let writes = tracker.update(accountID: account, sessions: [try session("s1", .working, since: 5)], now: at(12), floor: at(0))
        #expect(changes(writes) == [close("s1", .waiting, start: 10, end: 10), open("s1", .working, start: 10, now: 12)])
    }

    @Test("A project change relabels the open segment without moving its start; a title change writes nothing")
    func rename() throws {
        var tracker = SegmentTracker()
        let first = tracker.update(accountID: account, sessions: [try session("s1", .working, since: 0, title: nil)], now: at(0), floor: at(0))
        guard case let .openSegment(opened, _)? = first.first else {
            Issue.record("expected an open write, got \(first)")
            return
        }
        #expect(opened.title == "app · s1")
        #expect(opened.project == "app")

        // The session's own title can carry conversation content: it never reaches a segment.
        let retitled = tracker.update(accountID: account, sessions: [try session("s1", .working, since: 0, title: "Рефакторинг")], now: at(5), floor: at(0))
        #expect(retitled.isEmpty)

        let writes = tracker.update(
            accountID: account,
            sessions: [try session("s1", .working, since: 0, title: "Рефакторинг", project: "/Users/me/other")],
            now: at(9),
            floor: at(0)
        )
        guard case let .openSegment(segment, lastSeen)? = writes.first, writes.count == 1 else {
            Issue.record("expected one open write, got \(writes)")
            return
        }
        #expect(segment.title == "other · s1")
        #expect(segment.project == "other")
        #expect(segment.start == at(0))
        #expect(lastSeen == at(9))
    }

    @Test("Other accounts are untouched; closing all can target one account")
    func accounts() throws {
        let other = AccountID()
        var tracker = SegmentTracker()
        _ = tracker.update(accountID: account, sessions: [try session("a", .working, since: 0)], now: at(0), floor: at(0))
        _ = tracker.update(accountID: other, sessions: [try session("b", .working, since: 0)], now: at(0), floor: at(0))
        #expect(tracker.update(accountID: account, sessions: [], now: at(5), floor: at(0)).count == 1)
        #expect(tracker.openSegments.map(\.sessionID) == ["b"])

        _ = tracker.update(accountID: account, sessions: [try session("a2", .waiting, since: 6)], now: at(6), floor: at(0))
        #expect(changes(tracker.closeAll(accountID: other, at: at(8))) == [close("b", .working, start: 0, end: 8)])
        tracker.forget(accountID: account)
        #expect(tracker.openSegments.isEmpty)
    }

    @Test("Open segments are touched at most once a minute")
    func touches() throws {
        var tracker = SegmentTracker()
        #expect(tracker.touchIfDue(now: at(0)) == nil)
        _ = tracker.update(accountID: account, sessions: [try session("s1", .working, since: 0)], now: at(0), floor: at(0))
        #expect(tracker.touchIfDue(now: at(30)) == nil)
        #expect(tracker.touchIfDue(now: at(60)) == .touchOpenSegments(at: at(60)))
        #expect(tracker.touchIfDue(now: at(100)) == nil)
        #expect(tracker.touchIfDue(now: at(121)) == .touchOpenSegments(at: at(121)))
    }

    @Test("Stored times are whole milliseconds")
    func milliseconds() throws {
        var tracker = SegmentTracker()
        let writes = tracker.update(accountID: account, sessions: [try session("s1", .working, since: 1.23456)], now: at(2), floor: at(0))
        guard case let .openSegment(segment, _)? = writes.first else {
            Issue.record("expected an open write")
            return
        }
        #expect(segment.start == SegmentTracker.milliseconds(segment.start))
        #expect(abs(segment.start.timeIntervalSince(at(1.235))) < 0.000_5)
    }
}
