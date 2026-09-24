import CodometerCore
@testable import CodometerEngine
import Foundation
import Testing

private let start = Date(timeIntervalSince1970: 1_789_600_000)
private let account = AccountID()

/// An observation `minutes` after `start` whose window resets `resetMinutes` after `start`.
private func observation(_ minutes: Double, _ used: Double, resetsAt resetMinutes: Double? = nil) -> HistorySeriesBuilder.Observation {
    HistorySeriesBuilder.Observation(
        at: start.addingTimeInterval(minutes * 60),
        used: used,
        resetsAt: resetMinutes.map { start.addingTimeInterval($0 * 60) }
    )
}

private func minutes(_ value: Double) -> Date {
    start.addingTimeInterval(value * 60)
}

@Suite("History series builder")
struct HistorySeriesBuilderTests {
    @Test("Observations become ascending usage points; invalid values are skipped")
    func points() {
        let series = HistorySeriesBuilder.series(
            accountID: account,
            bucketID: "claude",
            windowID: "session",
            observations: [observation(10, 30, resetsAt: 300), observation(0, 10, resetsAt: 300), observation(5, .nan)]
        )
        #expect(series.accountID == account)
        #expect(series.bucketID == "claude")
        #expect(series.windowID == "session")
        #expect(series.points.map(\.used) == [10, 30])
        #expect(series.points.map(\.at) == [minutes(0), minutes(10)])
        #expect(series.resets.isEmpty)
    }

    @Test("A reset time passing between observations is recorded at the reset time")
    func passedReset() {
        let resets = HistorySeriesBuilder.resets(in: [
            observation(0, 80, resetsAt: 30),
            observation(60, 5, resetsAt: 330),
        ])
        #expect(resets == [minutes(30)])
    }

    @Test("A reset time moving far or a large drop marks a reset at the later observation")
    func movedOrDropped() {
        let moved = HistorySeriesBuilder.resets(in: [
            observation(0, 40, resetsAt: 100),
            observation(10, 42, resetsAt: 102),
            observation(20, 45, resetsAt: 400),
        ])
        #expect(moved == [minutes(20)])

        let dropped = HistorySeriesBuilder.resets(in: [
            observation(0, 60),
            observation(10, 50),
            observation(20, 20),
        ])
        #expect(dropped == [minutes(20)])
    }

    @Test("Interval limits both points and resets")
    func interval() {
        let series = HistorySeriesBuilder.series(
            accountID: account,
            bucketID: "codex",
            windowID: "primary",
            observations: [
                observation(0, 90),
                observation(10, 10),
                observation(20, 15),
                observation(30, 0),
                observation(40, 5),
            ],
            interval: DateInterval(start: minutes(5), end: minutes(25))
        )
        #expect(series.points.map(\.used) == [10, 15])
        #expect(series.resets == [minutes(10)])
    }
}
