import CodometerCore
import Foundation
import Testing

@Suite("Collection gaps")
struct CollectionGapsTests {
    private let origin = Date(timeIntervalSince1970: 1_789_600_000)

    private func at(_ minutes: Double) -> Date { origin.addingTimeInterval(minutes * 60) }

    private func run(_ start: Double, _ end: Double?, lastSeen: Double? = nil, _ reason: CollectionRun.EndReason? = nil) -> CollectionRun {
        CollectionRun(start: at(start), end: end.map(at), lastSeen: lastSeen.map(at), endReason: reason)
    }

    private var day: DateInterval { DateInterval(start: at(0), end: at(24 * 60)) }

    private func gaps(_ runs: [CollectionRun], interval: DateInterval? = nil, coverage: Double? = nil, now: Double = 24 * 60) -> [CollectionGap] {
        CollectionGaps.gaps(runs: runs, interval: interval ?? day, coverageStart: coverage.map(at), now: at(now))
    }

    @Test("Breaks shorter than 10 minutes are not gaps; 10 minutes or more are")
    func thresholds() {
        #expect(gaps([run(0, 60, .quit), run(69, nil)]).isEmpty)
        let found = gaps([run(0, 60, .quit), run(71, nil)])
        #expect(found == [CollectionGap(interval: DateInterval(start: at(60), end: at(71)), reason: .appNotRunning)])
    }

    @Test("Inferred ends need 45 minutes")
    func inferredThresholds() {
        #expect(gaps([run(0, 60, .inferred), run(104, nil)]).isEmpty)
        #expect(gaps([run(0, 60, .inferred), run(106, nil)]).map(\.reason) == [.unknown])
    }

    @Test("Reasons follow how the earlier run ended")
    func reasons() {
        let runs = [
            run(0, 60, .quit), run(120, 180, .sleep), run(240, 300, .disabled), run(360, 420, .crash),
            run(480, 540, lastSeen: 530), run(600, nil),
        ]
        #expect(gaps(runs).map(\.reason) == [.appNotRunning, .macAsleep, .accountOff, .appNotRunning, .unknown])
    }

    @Test("Unsorted and overlapping runs merge before gaps are found")
    func unsortedOverlapping() {
        let runs = [run(200, nil), run(0, 100, .quit), run(50, 120, .sleep), run(60, 70, .quit)]
        #expect(gaps(runs) == [CollectionGap(interval: DateInterval(start: at(120), end: at(200)), reason: .macAsleep)])
    }

    @Test("A dangling run ends at its last heartbeat, or at its start without one")
    func danglingRuns() {
        #expect(gaps([run(0, nil, lastSeen: 50), run(70, nil)]).map(\.interval.start) == [at(50)])
        // No end evidence at all: the start is an early guess, so the inferred threshold applies.
        #expect(gaps([run(0, nil), run(40, nil)]).isEmpty)
        #expect(gaps([run(0, nil), run(50, nil)]).map(\.interval) == [DateInterval(start: at(0), end: at(50))])
    }

    @Test("An open last run leaves no trailing gap; an ended one leaves a gap up to now")
    func trailing() {
        #expect(gaps([run(0, 60, .quit), run(120, nil, lastSeen: 130)], now: 600).count == 1)
        let afterDisable = gaps([run(0, 60, .disabled)], now: 600)
        #expect(afterDisable == [CollectionGap(interval: DateInterval(start: at(60), end: at(600)), reason: .accountOff)])
        #expect(gaps([run(0, 60, .disabled)], now: 65).isEmpty)
        #expect(gaps([run(0, 60, .disabled)], now: 30).isEmpty)
        // An older dangling run does not count as collecting now.
        #expect(gaps([run(0, nil, lastSeen: 10), run(20, 60, .quit)], now: 600).last?.interval == DateInterval(start: at(60), end: at(600)))
    }

    @Test("Gaps are clipped to the interval and never start before coverage")
    func clipping() {
        let window = DateInterval(start: at(100), end: at(200))
        #expect(gaps([run(0, 50, .quit), run(150, 180, .quit), run(300, nil)], interval: window)
            == [
                CollectionGap(interval: DateInterval(start: at(100), end: at(150)), reason: .appNotRunning),
                CollectionGap(interval: DateInterval(start: at(180), end: at(200)), reason: .appNotRunning),
            ])
        #expect(gaps([run(0, 50, .quit), run(150, nil)], interval: window, coverage: 140)
            == [CollectionGap(interval: DateInterval(start: at(140), end: at(150)), reason: .appNotRunning)])
        #expect(gaps([run(0, 50, .quit), run(150, nil)], interval: window, coverage: 160).isEmpty)
        #expect(gaps([run(0, 50, .quit), run(90, nil)], interval: window).isEmpty)
        #expect(gaps([], interval: window).isEmpty)
    }

    @Test("Ends and heartbeats before the start are moved to the start")
    func normalisedRuns() {
        let odd = CollectionRun(start: at(10), end: at(5), lastSeen: at(1), endReason: .quit)
        #expect(odd.end == at(10) && odd.lastSeen == at(10))
    }

    @Test("Timeline snapshots carry gaps in start order, empty by default")
    func timelineSnapshot() {
        let account = AccountID()
        let late = CollectionGap(interval: DateInterval(start: at(300), end: at(400)), reason: .macAsleep)
        let early = CollectionGap(interval: DateInterval(start: at(100), end: at(200)), reason: .appNotRunning)
        #expect(TimelineSnapshot(accountID: account, interval: day, segments: [], usage: nil).gaps.isEmpty)
        #expect(TimelineSnapshot(accountID: account, interval: day, segments: [], usage: nil, gaps: [late, early]).gaps == [early, late])
    }
}
