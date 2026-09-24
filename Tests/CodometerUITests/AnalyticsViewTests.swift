import CodometerCore
import CodometerL10n
@testable import CodometerUI
import AppKit
import Foundation
import SwiftUI
import Testing

/// Builders for the analytics view tests: a fixed moment (Thursday 17 Sep 2026, 14:32 UTC) and a UTC calendar,
/// so clock texts are the same on every machine.
enum AnalyticsFixture {
    static let now = Date(timeIntervalSince1970: 1_789_655_520)
    /// Derived, never minted, for the same reason as the fixed moment: a render must not change between runs.
    static let account = UIFixture.accountID("analytics")

    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    static func minutes(_ value: Double) -> TimeInterval { value * 60 }
    static func hours(_ value: Double) -> TimeInterval { value * 3_600 }

    static func window(
        used: Double,
        duration: WindowDuration? = .fiveHours,
        resetsIn: TimeInterval? = hours(2),
        scope: LimitWindowScope = .session
    ) throws -> LimitWindow {
        try LimitWindow(
            id: "session",
            scope: scope,
            used: try Percentage(validating: used),
            duration: duration,
            resetsAt: resetsIn.map { now.addingTimeInterval($0) }
        )
    }

    /// Observations `(seconds relative to now, used)`.
    static func series(_ values: [(TimeInterval, Double)], resets: [TimeInterval] = []) throws -> HistorySeries {
        HistorySeries(
            accountID: account,
            bucketID: "claude",
            windowID: "session",
            points: try values.map { try UsagePoint(at: now.addingTimeInterval($0.0), used: $0.1) },
            resets: resets.map { now.addingTimeInterval($0) }
        )
    }

    static func segment(
        _ session: String,
        _ activity: AgentActivity,
        from start: TimeInterval,
        to end: TimeInterval?,
        title: String? = nil
    ) throws -> SessionSegment {
        try SessionSegment(
            accountID: account,
            sessionID: session,
            title: title ?? session,
            project: "/Users/me/\(session)",
            activity: activity,
            start: now.addingTimeInterval(start),
            end: end.map { now.addingTimeInterval($0) }
        )
    }

    /// A project share, or the folded `.other` share for `UsageAttribution.otherShareID`.
    static func share(_ id: String, _ title: String, share: Double, points: Double?) throws -> AttributionShare {
        let subject: AttributionSubject = id == UsageAttribution.otherShareID ? .other : .project(title)
        return try AttributionShare(id: id, subject: subject, weightedTokens: share * 1_000_000, share: share, estimatedPoints: points)
    }

    static func report(_ shares: [AttributionShare], coverageStart: TimeInterval? = nil, duration: TimeInterval = hours(24)) -> AttributionReport {
        AttributionReport(
            interval: DateInterval(start: now.addingTimeInterval(-duration), end: now),
            windowTitleSource: nil,
            usedPoints: shares.contains { $0.estimatedPoints != nil } ? 40 : nil,
            shares: shares,
            totalWeightedTokens: shares.reduce(0) { $0 + $1.weightedTokens },
            coverageStart: coverageStart.map { now.addingTimeInterval($0) }
        )
    }
}

// MARK: - Texts

@Suite("Analytics texts")
struct AnalyticsTextTests {
    private let calendar = AnalyticsFixture.utc
    private let now = AnalyticsFixture.now

    @Test("Clock and moment texts")
    func clock() {
        #expect(AnalyticsText.clock(now, l10n: .testRussian) == "14:32")
        #expect(AnalyticsText.clock(now.addingTimeInterval(-AnalyticsFixture.hours(5.45)), l10n: .testRussian) == "9:05")
        #expect(AnalyticsText.moment(now.addingTimeInterval(-60), now: now, l10n: .testRussian) == "14:31")
        #expect(AnalyticsText.moment(now.addingTimeInterval(-AnalyticsFixture.hours(24)), now: now, l10n: .testRussian) == "ср 14:32")
        #expect(AnalyticsText.moment(now.addingTimeInterval(-AnalyticsFixture.hours(24 * 7)), now: now, l10n: .testRussian) == "10.09 14:32")
    }

    @Test("Agent counts decline like Russian nouns", arguments: [
        (0, "нет агентов"), (1, "1 агент"), (2, "2 агента"), (4, "4 агента"), (5, "5 агентов"),
        (11, "11 агентов"), (12, "12 агентов"), (21, "21 агент"), (22, "22 агента"), (112, "112 агентов"),
    ])
    func agents(count: Int, expected: String) {
        #expect(AnalyticsText.agents(count, l10n: .testRussian) == expected)
    }

    @Test("Percent texts")
    func percent() {
        #expect(AnalyticsText.percent(0, l10n: .testRussian) == "0\u{00A0}%")
        #expect(AnalyticsText.percent(0.4, l10n: .testRussian) == "<1\u{00A0}%")
        #expect(AnalyticsText.percent(41.4, l10n: .testRussian) == "41\u{00A0}%")
        #expect(AnalyticsText.percent(99.6, l10n: .testRussian) == "100\u{00A0}%")
        #expect(AnalyticsText.percent(.nan, l10n: .testRussian) == "0\u{00A0}%")
    }

    @Test("Coverage note only when data starts more than a minute after the interval")
    func coverage() {
        let start = now.addingTimeInterval(-AnalyticsFixture.hours(5))
        #expect(AnalyticsText.coverageNote(coverageStart: nil, intervalStart: start, now: now, l10n: .testRussian) == nil)
        #expect(AnalyticsText.coverageNote(coverageStart: start.addingTimeInterval(30), intervalStart: start, now: now, l10n: .testRussian) == nil)
        #expect(AnalyticsText.coverageNote(coverageStart: start.addingTimeInterval(-600), intervalStart: start, now: now, l10n: .testRussian) == nil)
        #expect(
            AnalyticsText.coverageNote(coverageStart: now.addingTimeInterval(-AnalyticsFixture.hours(2)), intervalStart: start, now: now, l10n: .testRussian)
                == "данные с 12:32"
        )
        // Coverage is clamped into the interval and may equal its end (collection began after the period).
        #expect(AnalyticsText.coverageNote(coverageStart: now, intervalStart: start, now: now, l10n: .testRussian) == "данные с 14:32")
        #expect(AnalyticsText.coverageShortNote(coverageStart: now.addingTimeInterval(-AnalyticsFixture.hours(2)), now: now, l10n: .testRussian) == "с 12:32")
        #expect(AnalyticsText.coverageShortNote(coverageStart: now.addingTimeInterval(-AnalyticsFixture.hours(30)), now: now, l10n: .testRussian) == "с ср 8:32")
    }

    @Test("Style bands follow the configured thresholds")
    func styleBands() throws {
        let strict = try BandThresholds(watch: try Percentage(validating: 20), critical: try Percentage(validating: 40))
        #expect(AnalyticsStyle().band(for: 30) == .ample)
        #expect(AnalyticsStyle(bands: strict).band(for: 30) == .watch)
        #expect(AnalyticsStyle(bands: strict).band(for: 120) == .exhausted)
        #expect(AnalyticsStyle().band(for: -.infinity) == .ample)
    }
}

// MARK: - Window history chart

@Suite("Window history chart model")
struct HistoryChartModelTests {
    private typealias Fixture = AnalyticsFixture
    private let now = AnalyticsFixture.now

    @Test("Domain runs from the window start to its reset")
    func domainFromWindow() throws {
        let window = try Fixture.window(used: 40, resetsIn: Fixture.hours(2))
        let model = HistoryChartModel(series: nil, window: window, now: now)
        #expect(model.domain.lowerBound == now.addingTimeInterval(-Fixture.hours(3)))
        #expect(model.domain.upperBound == now.addingTimeInterval(Fixture.hours(2)))
    }

    @Test("Without a reset time the domain runs from the first observation to now")
    func domainFallback() throws {
        let window = try Fixture.window(used: 40, duration: nil, resetsIn: nil, scope: .rolling)
        let series = try Fixture.series([(-Fixture.hours(1), 10), (-Fixture.minutes(30), 20)])
        let model = HistoryChartModel(series: series, window: window, now: now)
        #expect(model.domain == now.addingTimeInterval(-Fixture.hours(1))...now)
        #expect(model.evenPace == nil)
        #expect(model.now == now)

        let empty = HistoryChartModel.domain(series: nil, window: window, now: now)
        #expect(empty == now.addingTimeInterval(-Fixture.hours(5))...now)
    }

    @Test("A reset in the past never yields an inverted domain")
    func domainNeverInverted() throws {
        let window = try Fixture.window(used: 40, duration: nil, resetsIn: -Fixture.hours(1), scope: .rolling)
        let series = try Fixture.series([(-Fixture.minutes(10), 10), (-Fixture.minutes(5), 12)])
        let domain = HistoryChartModel.domain(series: series, window: window, now: now)
        #expect(domain.upperBound > domain.lowerBound)
    }

    @Test("Placeholder until two observations of the current period exist")
    func placeholder() throws {
        let window = try Fixture.window(used: 40)
        #expect(HistoryChartModel(series: nil, window: window, now: now).isPlaceholder)
        #expect(HistoryChartModel(series: try Fixture.series([]), window: window, now: now).isPlaceholder)
        #expect(HistoryChartModel(series: try Fixture.series([(-600, 30)]), window: window, now: now).isPlaceholder)
        // Observations from before the window started do not count.
        #expect(HistoryChartModel(series: try Fixture.series([(-Fixture.hours(4), 90), (-600, 30)]), window: window, now: now).isPlaceholder)
        #expect(!HistoryChartModel(series: try Fixture.series([(-1_200, 20), (-600, 30)]), window: window, now: now).isPlaceholder)
    }

    @Test("Stored points keep the current period, clamp to 100 and drop duplicates")
    func storedPoints() throws {
        let window = try Fixture.window(used: 40)
        let series = try Fixture.series(
            [(-Fixture.hours(2.5), 70), (-Fixture.hours(2), 80), (-Fixture.hours(1), 5), (-Fixture.minutes(30), 150), (-Fixture.minutes(30), 20), (600, 50)],
            resets: [-Fixture.hours(1.5)]
        )
        let model = HistoryChartModel(series: series, window: window, now: now)
        let stored = HistoryChartModel.storedPoints(series: series, domain: model.domain, now: now)
        #expect(stored.map(\.used) == [5, 20])
        #expect(stored.first?.at == now.addingTimeInterval(-Fixture.hours(1)))
        #expect(HistoryChartModel.clamp(150) == 100)
        #expect(HistoryChartModel.clamp(.infinity) == 0)
    }

    @Test("The curve ends with the live value at now")
    func livePoint() throws {
        let window = try Fixture.window(used: 44)
        let model = HistoryChartModel(series: try Fixture.series([(-1_200, 20), (-600, 30)]), window: window, now: now)
        #expect(model.points.last == HistoryChartModel.Point(at: now, used: 44))
        #expect(model.current == HistoryChartModel.Point(at: now, used: 44))
        #expect(model.points.count == 3)

        let atNow = HistoryChartModel(series: try Fixture.series([(-1_200, 20), (0, 30)]), window: window, now: now)
        #expect(atNow.points.map(\.used) == [20, 44])
    }

    @Test("Long histories are thinned to one point per time slice, keeping the first and the latest")
    func thinning() throws {
        let window = try Fixture.window(used: 60, duration: .oneWeek, resetsIn: Fixture.hours(24), scope: .weekly(model: nil))
        // Six days of observations every five minutes: far more than the strip can show.
        let values = stride(from: -Fixture.hours(144), through: -Fixture.minutes(5), by: 300).map { ($0, 60 * ($0 + Fixture.hours(144)) / Fixture.hours(144)) }
        let series = try Fixture.series(values)
        let model = HistoryChartModel(series: series, window: window, now: now)
        #expect(!model.isPlaceholder)
        // The stored points plus the live value at now.
        #expect(model.points.count <= HistoryChartModel.maximumDrawnPoints + 1)
        #expect(model.points.first?.at == now.addingTimeInterval(-Fixture.hours(144)))
        #expect(zip(model.points, model.points.dropFirst()).allSatisfy { $0.at < $1.at })
        #expect(model.points.last == HistoryChartModel.Point(at: now, used: 60))

        let points = (0..<10).map { HistoryChartModel.Point(at: now.addingTimeInterval(Double($0) * 60), used: Double($0)) }
        let domain = now...now.addingTimeInterval(540)
        #expect(HistoryChartModel.thinned(points, domain: domain, maximum: 20) == points)
        let thin = HistoryChartModel.thinned(points, domain: domain, maximum: 4)
        #expect(thin.count <= 4)
        #expect(thin.first == points.first)
        #expect(thin.last == points.last)
        #expect(HistoryChartModel.thinned(points, domain: now...now, maximum: 3) == Array(points.suffix(3)))
    }

    @Test("Even pace runs from (start, 0) to (reset, 100)")
    func evenPace() throws {
        let window = try Fixture.window(used: 40, resetsIn: Fixture.hours(1))
        let model = HistoryChartModel(series: nil, window: window, now: now)
        #expect(model.evenPace?.from == HistoryChartModel.Point(at: now.addingTimeInterval(-Fixture.hours(4)), used: 0))
        #expect(model.evenPace?.to == HistoryChartModel.Point(at: now.addingTimeInterval(Fixture.hours(1)), used: 100))
    }

    @Test("Projection to exhaustion only when the limit runs out before the reset")
    func projection() throws {
        // 3 h into a 5 h window at 90 %: 30 points an hour reaches 100 % in 20 min, before the reset in 2 h.
        let fast = try Fixture.window(used: 90, resetsIn: Fixture.hours(2))
        let model = HistoryChartModel(series: try Fixture.series([(-600, 85), (-300, 88)]), window: fast, now: now)
        let projection = try #require(model.projection)
        #expect(projection.from == HistoryChartModel.Point(at: now, used: 90))
        #expect(projection.to.used == 100)
        #expect(abs(projection.to.at.timeIntervalSince(now) - Fixture.minutes(20)) < 1)

        let slow = try Fixture.window(used: 30, resetsIn: Fixture.hours(2))
        #expect(HistoryChartModel(series: nil, window: slow, now: now).projection == nil)
    }

    @Test("VoiceOver summary names the value, pace and projection")
    func accessibility() throws {
        let window = try Fixture.window(used: 90, resetsIn: Fixture.hours(2))
        let model = HistoryChartModel(series: try Fixture.series([(-600, 85), (-300, 88)]), window: window, now: now)
        #expect(
            HistoryChartModel.accessibilitySummary(model: model, window: window, now: now, l10n: .testRussian)
                == "История расхода: сейчас 90\u{00A0}%, опережает темп на 30\u{00A0}%, закончится в 14:52"
        )
        #expect(
            HistoryChartModel.accessibilitySummary(model: model, window: window, now: now, l10n: .testEnglish)
                == "Usage history: 90% now, 30% ahead of pace, runs out at 2:52\u{202F}PM"
        )
        let empty = HistoryChartModel(series: nil, window: window, now: now)
        #expect(HistoryChartModel.accessibilitySummary(model: empty, window: window, now: now, l10n: .testRussian) == "История расхода: данные ещё собираются")
        #expect(HistoryChartModel.accessibilitySummary(model: empty, window: window, now: now, l10n: .testEnglish) == "Usage history: still collecting data")

        // Behind pace and on pace; no projection, and never "≈" or " · " in spoken text.
        let calm = try Fixture.window(used: 10, resetsIn: Fixture.hours(2))
        let calmModel = HistoryChartModel(series: try Fixture.series([(-600, 8), (-300, 9)]), window: calm, now: now)
        let spoken = HistoryChartModel.accessibilitySummary(model: calmModel, window: calm, now: now, l10n: .testEnglish)
        #expect(spoken.hasPrefix("Usage history: 10% now, "))
        #expect(spoken.hasSuffix("below pace"))
        #expect(!spoken.contains("≈") && !spoken.contains(" · "))
    }
}

// MARK: - Timeline

@Suite("Session timeline layout")
struct TimelineLayoutTests {
    private typealias Fixture = AnalyticsFixture
    private let now = AnalyticsFixture.now
    private let day = DateInterval(start: AnalyticsFixture.now.addingTimeInterval(-AnalyticsFixture.hours(24)), end: AnalyticsFixture.now)

    @Test("Lanes are the sessions with the most active time, at most five, with the rest counted")
    func laneSelection() throws {
        var segments: [SessionSegment] = []
        for index in 0..<7 {
            // Session s0 is active 10 min, s6 70 min.
            segments.append(try Fixture.segment("s\(index)", .working, from: -Fixture.hours(10), to: -Fixture.hours(10) + Fixture.minutes(Double(10 + index * 10))))
        }
        segments.append(try Fixture.segment("s0", .waiting, from: -Fixture.hours(2), to: -Fixture.hours(2) + Fixture.minutes(65)))
        let selection = TimelineLayout.lanes(segments: segments, interval: day, now: now, l10n: .testRussian)
        #expect(selection.lanes.map(\.sessionID) == ["s0", "s6", "s5", "s4", "s3"])
        #expect(selection.hiddenCount == 2)
        #expect(selection.overflowText(l10n: .testRussian) == "ещё 2")
        #expect(selection.overflowText(l10n: .testEnglish) == "2 more")
        #expect(selection.lanes.first?.segments.count == 2)
        #expect(selection.lanes.first?.activeTime == Fixture.minutes(75))
    }

    @Test("Open segments count to now, outside segments are ignored and edges are clipped")
    func laneTime() throws {
        let segments = [
            try Fixture.segment("open", .waiting, from: -Fixture.minutes(30), to: nil, title: "api"),
            try Fixture.segment("clipped", .working, from: -Fixture.hours(25), to: -Fixture.hours(23)),
            try Fixture.segment("outside", .working, from: -Fixture.hours(30), to: -Fixture.hours(26)),
        ]
        let selection = TimelineLayout.lanes(segments: segments, interval: day, now: now, l10n: .testRussian)
        #expect(selection.lanes.map(\.sessionID) == ["clipped", "open"])
        #expect(selection.hiddenCount == 0)
        #expect(selection.overflowText(l10n: .testRussian) == nil)
        #expect(selection.lanes[0].activeTime == Fixture.hours(1))
        #expect(selection.lanes[0].openActivity == nil)
        #expect(selection.lanes[1].activeTime == Fixture.minutes(30))
        #expect(selection.lanes[1].openActivity == .waiting)
        // Titled by project folder, never by a stored title.
        #expect(selection.lanes[1].title == "open")

        let span = try #require(TimelineLayout.span(of: segments[1], interval: day, now: now))
        #expect(span == day.start...now.addingTimeInterval(-Fixture.hours(23)))
        #expect(TimelineLayout.span(of: segments[2], interval: day, now: now) == nil)
    }

    @Test("Lanes are titled by project folder, with the id's end only where two shown lanes share a folder")
    func laneTitles() throws {
        let titles = TimelineLayout.laneTitles([
            (sessionID: "4ecca291-a70a-4fe9-9306-426595e70d2d", project: "/Users/me/Codometer"),
            (sessionID: "11111111-2222-3333-4444-555555abcdef", project: "/Volumes/work/Codometer"),
            (sessionID: "api-1", project: "/Users/me/exchanger-api"),
            (sessionID: "loose-7", project: nil),
        ], l10n: .testRussian)
        #expect(titles == ["Codometer · e70d2d", "Codometer · abcdef", "exchanger-api", "сессия oose-7"])

        // Only the lanes shown count: a hidden session of the same project does not add the suffix.
        var segments: [SessionSegment] = []
        for (index, minutes) in [60.0, 50, 5].enumerated() {
            segments.append(try SessionSegment(
                accountID: Fixture.account, sessionID: "same-\(index)", title: "Секрет \(index)", project: "/Users/me/app",
                activity: .working, start: now.addingTimeInterval(-Fixture.minutes(minutes)), end: now.addingTimeInterval(-Fixture.minutes(minutes - 4))
            ))
        }
        segments.append(try SessionSegment(
            accountID: Fixture.account, sessionID: "other", title: nil, project: "/Users/me/web",
            activity: .working, start: now.addingTimeInterval(-Fixture.minutes(30)), end: now
        ))
        #expect(TimelineLayout.lanes(segments: segments, interval: day, now: now, maximum: 1, l10n: .testRussian).lanes.map(\.title) == ["web"])
        #expect(TimelineLayout.lanes(segments: segments, interval: day, now: now, maximum: 2, l10n: .testRussian).lanes.map(\.title) == ["web", "app"])
        #expect(TimelineLayout.lanes(segments: segments, interval: day, now: now, maximum: 3, l10n: .testRussian).lanes.map(\.title) == [
            "web", "app · same-2", "app · same-1",
        ])
    }

    @Test("Reset markers keep the newest and drop ones closer than the spacing")
    func resetMarkers() {
        let week = DateInterval(start: now.addingTimeInterval(-Fixture.hours(168)), end: now)
        let plot: ClosedRange<CGFloat> = 0...168
        func resets(_ hoursAgo: [Double]) -> [Date] {
            hoursAgo.map { now.addingTimeInterval(-Fixture.hours($0)) }
        }
        func markers(_ hoursAgo: [Double], spacing: CGFloat) -> [CGFloat] {
            TimelineLayout.resetMarkerXs(resets: resets(hoursAgo), interval: week, plot: plot, minimumSpacing: spacing)
                .map { ($0 * 1_000).rounded() / 1_000 }
        }
        // One point per hour. The newest reset always stays; older ones only once far enough from the last kept one.
        #expect(markers([10, 5, 0.5, 15, 200], spacing: 16) == [167.5])
        #expect(markers([10, 5, 0.5, 15, 200], spacing: 5) == [153, 158, 167.5])
        #expect(markers([10, 5, 0.5, 15], spacing: 4) == [153, 158, 163, 167.5])
        #expect(markers([], spacing: 16).isEmpty)
    }

    @Test("Equal active time orders the most recently active session first")
    func laneTies() throws {
        let segments = [
            try Fixture.segment("early", .working, from: -Fixture.hours(5), to: -Fixture.hours(4)),
            try Fixture.segment("late", .working, from: -Fixture.hours(2), to: -Fixture.hours(1)),
        ]
        #expect(TimelineLayout.lanes(segments: segments, interval: day, now: now, l10n: .testRussian).lanes.map(\.sessionID) == ["late", "early"])
        #expect(TimelineLayout.lanes(segments: segments, interval: day, now: now, maximum: 0, l10n: .testRussian).hiddenCount == 2)
    }

    @Test("Tick step is the finest one that keeps labels apart", arguments: [
        (5.0, 3_600.0), (24.0, 21_600.0), (168.0, 86_400.0),
    ])
    func tickStep(hours: Double, expected: TimeInterval) {
        #expect(TimelineLayout.tickStep(duration: AnalyticsFixture.hours(hours), width: 290, minimumSpacing: 46) == expected)
    }

    @Test("Ticks fall on whole local hours divisible by the step, or on midnights")
    func ticks() {
        let calendar = Fixture.utc
        let five = DateInterval(start: now.addingTimeInterval(-Fixture.hours(5)), end: now)
        let hourly = TimelineLayout.ticks(in: five, step: 3_600, calendar: calendar)
        #expect(hourly.map { AnalyticsText.clock($0, l10n: .testRussian) } == ["10:00", "11:00", "12:00", "13:00", "14:00"])
        let sixHourly = TimelineLayout.ticks(in: day, step: 21_600, calendar: calendar)
        #expect(sixHourly.map { AnalyticsText.clock($0, l10n: .testRussian) } == ["18:00", "0:00", "6:00", "12:00"])
        let week = DateInterval(start: now.addingTimeInterval(-Fixture.hours(168)), end: now)
        let daily = TimelineLayout.ticks(in: week, step: 86_400, calendar: calendar)
        #expect(daily.map { TimelineLayout.tickLabel($0, step: 86_400, l10n: .testRussian) } == ["пт", "сб", "вс", "пн", "вт", "ср", "чт"])
        #expect(TimelineLayout.tickLabel(hourly[0], step: 3_600, l10n: .testRussian) == "10:00")
    }

    @Test("Usage is a step function that forgets values across resets")
    func usageLookup() throws {
        let series = try Fixture.series([(-Fixture.hours(3), 20), (-Fixture.hours(2), 60), (-Fixture.minutes(30), 10)], resets: [-Fixture.hours(1)])
        #expect(TimelineLayout.usage(at: now.addingTimeInterval(-Fixture.hours(4)), in: series) == nil)
        #expect(TimelineLayout.usage(at: now.addingTimeInterval(-Fixture.hours(2.5)), in: series) == 20)
        #expect(TimelineLayout.usage(at: now.addingTimeInterval(-Fixture.hours(1.5)), in: series) == 60)
        #expect(TimelineLayout.usage(at: now.addingTimeInterval(-Fixture.minutes(45)), in: series) == nil)
        #expect(TimelineLayout.usage(at: now, in: series) == 10)
        #expect(TimelineLayout.usage(at: now, in: nil) == nil)
    }

    @Test("Curve: carried-in value, straight runs within a period, a vertical drop at each reset, flat to now")
    func curve() throws {
        let interval = DateInterval(start: now.addingTimeInterval(-Fixture.hours(5)), end: now)
        let series = try Fixture.series(
            [(-Fixture.hours(6), 30), (-Fixture.hours(4), 50), (-Fixture.hours(3), 70), (-Fixture.hours(1), 10), (-Fixture.minutes(30), 120)],
            resets: [-Fixture.hours(2)]
        )
        let vertices = TimelineLayout.curveVertices(series: series, interval: interval, now: now)
        let expected: [(TimeInterval, Double)] = [
            (-Fixture.hours(5), 30), (-Fixture.hours(4), 50), (-Fixture.hours(3), 70),
            (-Fixture.hours(2), 70), (-Fixture.hours(2), 0), (-Fixture.hours(1), 10), (-Fixture.minutes(30), 100), (0, 100),
        ]
        #expect(vertices == expected.map { HistoryChartModel.Point(at: now.addingTimeInterval($0.0), used: $0.1) })

        // A reset between the carried observation and the interval start drops the carried value.
        let reset = try Fixture.series([(-Fixture.hours(6), 30), (-Fixture.hours(4), 50)], resets: [-Fixture.hours(5.5)])
        #expect(TimelineLayout.curveVertices(series: reset, interval: interval, now: now).first?.at == now.addingTimeInterval(-Fixture.hours(4)))
        // A reset at the same moment as an observation drops first.
        let same = try Fixture.series([(-Fixture.hours(3), 60), (-Fixture.hours(2), 5)], resets: [-Fixture.hours(2)])
        #expect(TimelineLayout.curveVertices(series: same, interval: interval, now: now).map(\.used) == [60, 60, 0, 5, 5])
        #expect(TimelineLayout.curveVertices(series: nil, interval: interval, now: now).isEmpty)
    }

    @Test("Tooltip: time, agents at that moment and usage")
    func tooltip() throws {
        let segments = [
            try Fixture.segment("a", .working, from: -Fixture.hours(2), to: nil),
            try Fixture.segment("b", .waiting, from: -Fixture.hours(1), to: -Fixture.minutes(10)),
            try Fixture.segment("b", .working, from: -Fixture.hours(1.5), to: -Fixture.hours(1)),
        ]
        let usage = try Fixture.series([(-Fixture.hours(3), 20), (-Fixture.minutes(40), 41)])
        let snapshot = TimelineSnapshot(
            accountID: Fixture.account,
            interval: DateInterval(start: now.addingTimeInterval(-Fixture.hours(5)), end: now),
            segments: segments,
            usage: usage,
            coverageStart: now.addingTimeInterval(-Fixture.hours(2))
        )
        #expect(TimelineLayout.tooltip(at: now.addingTimeInterval(-Fixture.minutes(30)), snapshot: snapshot, now: now, l10n: .testRussian) == "14:02 · 2 агента · 41\u{00A0}%")
        #expect(TimelineLayout.tooltip(at: now.addingTimeInterval(-Fixture.minutes(5)), snapshot: snapshot, now: now, l10n: .testRussian) == "14:27 · 1 агент · 41\u{00A0}%")
        #expect(TimelineLayout.tooltip(at: now.addingTimeInterval(-Fixture.hours(2.5)), snapshot: snapshot, now: now, l10n: .testRussian) == "12:02 · 20\u{00A0}%")
        #expect(TimelineLayout.tooltip(at: now.addingTimeInterval(-Fixture.hours(4)), snapshot: snapshot, now: now, l10n: .testRussian) == "10:32")
        #expect(TimelineLayout.activeSessions(at: now, segments: segments, now: now) == 1)
        #expect(TimelineLayout.activeSessions(at: now.addingTimeInterval(-Fixture.hours(1)), segments: segments, now: now) == 2)
    }

    @Test("A coverage note that moves to the tick row starts at the boundary and stays inside the row")
    func tickRowNote() {
        let row: ClosedRange<CGFloat> = 100...300
        #expect(TimelineLayout.tickRowNoteSpan(boundaryX: 120, labelWidth: 80, row: row) == 123...203)
        #expect(TimelineLayout.tickRowNoteSpan(boundaryX: 280, labelWidth: 80, row: row) == 220...300)
        #expect(TimelineLayout.tickRowNoteSpan(boundaryX: 90, labelWidth: 250, row: row) == 100...350)
    }

    @Test("Hover positions map to moments inside the plot and back")
    func positions() {
        let plot: ClosedRange<CGFloat> = 100...300
        #expect(TimelineLayout.date(atX: 99, plot: plot, interval: day) == nil)
        #expect(TimelineLayout.date(atX: 200, plot: plot, interval: day) == day.start.addingTimeInterval(Fixture.hours(12)))
        #expect(TimelineLayout.x(of: day.start.addingTimeInterval(Fixture.hours(6)), plot: plot, interval: day) == 150)
        #expect(TimelineLayout.x(of: day.end.addingTimeInterval(Fixture.hours(6)), plot: plot, interval: day) == 300)
        #expect(TimelineLayout.date(atX: 150, plot: 100...100, interval: day) == nil)
    }

    @Test("Placeholder only without a snapshot; summaries decline sessions")
    func placeholderAndSummary() throws {
        let empty = TimelineSnapshot(accountID: Fixture.account, interval: day, segments: [], usage: nil)
        #expect(TimelineLayout.showsPlaceholder(nil))
        #expect(!TimelineLayout.showsPlaceholder(empty))
        #expect(TimelineLayout.accessibilitySummary(snapshot: nil, now: now, l10n: .testRussian) == "Хронология: нет данных")
        #expect(TimelineLayout.accessibilitySummary(snapshot: empty, now: now, l10n: .testRussian) == "Хронология: нет сессий")
        #expect(TimelineLayout.accessibilitySummary(snapshot: nil, now: now, l10n: .testEnglish) == "Timeline: no data")
        #expect(TimelineLayout.accessibilitySummary(snapshot: empty, now: now, l10n: .testEnglish) == "Timeline: no sessions")
        let busy = TimelineSnapshot(
            accountID: Fixture.account,
            interval: day,
            segments: [
                try Fixture.segment("a", .working, from: -Fixture.hours(3), to: -Fixture.hours(1)),
                try Fixture.segment("b", .waiting, from: -Fixture.minutes(12), to: nil),
            ],
            usage: try Fixture.series([(-Fixture.hours(2), 30), (-Fixture.hours(1), 41)])
        )
        // Durations in words for VoiceOver.
        #expect(
            TimelineLayout.accessibilitySummary(snapshot: busy, now: now, l10n: .testRussian)
                == "Хронология: 2 сессии, в работе 2 часа, в ожидании 12 минут, использовано 41\u{00A0}% лимита"
        )
        #expect(
            TimelineLayout.accessibilitySummary(snapshot: busy, now: now, l10n: .testEnglish)
                == "Timeline: 2 sessions, working for 2 hours, waiting for 12 minutes, 41% of the limit used"
        )
        #expect(TimelineLayout.sessions(1, l10n: .testRussian) == "1 сессия")
        #expect(TimelineLayout.sessions(5, l10n: .testRussian) == "5 сессий")
        #expect(TimelineLayout.sessions(22, l10n: .testRussian) == "22 сессии")
        #expect(TimelineLayout.sessions(0, l10n: .testRussian) == "нет сессий")
        #expect(TimelineLayout.sessions(1, l10n: .testEnglish) == "1 session")
        #expect(TimelineLayout.sessions(2, l10n: .testEnglish) == "2 sessions")
        #expect(TimelineLayout.sessions(0, l10n: .testEnglish) == "no sessions")
    }

    @MainActor
    @Test("Frame keeps every lane inside the view at any scale", arguments: [0.85, 1.0, 1.25])
    func frame(scale: Double) {
        let metrics = IslandMetrics(scale: scale)
        let size = CGSize(width: 372 * scale, height: SessionTimelineView.height(for: metrics))
        let frame = TimelineFrame(size: size, metrics: metrics)
        #expect(frame.curve.minY > 0)
        #expect(frame.lanesArea.minY >= frame.curve.maxY)
        #expect(frame.laneMinY(frame.laneCapacity) <= frame.tickRow.minY + 0.001)
        #expect(frame.tickRow.maxY <= size.height)
        #expect(frame.lanePitch >= frame.capsuleHeight)
        #expect(frame.plotX.upperBound <= size.width)
        // Titles never crowd: every lane is at least 1.25 title lines tall.
        #expect(frame.lanePitch >= metrics.textSize(10.5) * TimelineFrame.minimumLaneLines)
        #expect(frame.gutterWidth >= 82)
        #expect(frame.gutterX + frame.gutterWidth < frame.plotX.lowerBound)
    }

    @MainActor
    @Test("A taller timeline grows its curve and fits more lanes, still inside the view", arguments: [0.85, 1.0, 1.25])
    func tallFrame(scale: Double) {
        let metrics = IslandMetrics(scale: scale)
        let ideal = TimelineFrame(size: CGSize(width: 372 * scale, height: SessionTimelineView.height(for: metrics)), metrics: metrics)
        let size = CGSize(width: 372 * scale, height: SessionTimelineView.height(for: metrics) + 100 * scale)
        let tall = TimelineFrame(size: size, metrics: metrics)
        #expect(tall.curve.height > ideal.curve.height)
        #expect(tall.lanesArea.height > ideal.lanesArea.height)
        #expect(tall.laneCapacity > ideal.laneCapacity)
        #expect(tall.laneCapacity <= TimelineFrame.maximumLaneCapacity)
        #expect(tall.laneMinY(tall.laneCapacity) <= tall.tickRow.minY + 0.001)
        #expect(tall.tickRow.maxY <= size.height)
        #expect(tall.lanePitch >= metrics.textSize(10.5) * TimelineFrame.minimumLaneLines)
        let huge = TimelineFrame(size: CGSize(width: 372 * scale, height: 2_000), metrics: metrics)
        #expect(huge.laneCapacity == TimelineFrame.maximumLaneCapacity)
    }

    @MainActor
    @Test("Five lanes fit at full scale; the 0.85 scale keeps four so size-floored titles stay apart", arguments: [
        (0.85, 4), (1.0, 5), (1.25, 5),
    ])
    func laneCapacity(scale: Double, expected: Int) {
        let metrics = IslandMetrics(scale: scale)
        let frame = TimelineFrame(size: CGSize(width: 372 * scale, height: SessionTimelineView.height(for: metrics)), metrics: metrics)
        #expect(frame.laneCapacity == expected)
        let tiny = TimelineFrame(size: CGSize(width: 10, height: 10), metrics: metrics)
        #expect(tiny.laneCapacity == 1)
    }
}

// MARK: - Attribution

@Suite("Timeline page layout")
struct TimelinePageLayoutTests {
    @Test("Extra height goes to the timeline and the list; the header and a short slot keep ideal heights")
    func heights() {
        #expect(TimelinePageLayout.heights(ideal: [30, 150, 120], spacing: 10, available: 320) == [30, 150, 120])
        #expect(TimelinePageLayout.heights(ideal: [30, 150, 120], spacing: 10, available: 200) == [30, 150, 120])
        #expect(TimelinePageLayout.heights(ideal: [30, 150, 120], spacing: 10, available: 420) == [30, 210, 160])
        #expect(TimelinePageLayout.heights(ideal: [30, 150, 120], spacing: 10, available: .infinity) == [30, 150, 120])
        #expect(TimelinePageLayout.heights(ideal: [30], spacing: 10, available: 400) == [30])
        let odd = TimelinePageLayout.heights(ideal: [30, 150, 120], spacing: 10, available: 321)
        #expect(odd.reduce(0, +) + 20 == 321)
    }

    @MainActor
    @Test("The list has four slots at its ideal height at any scale and more when taller", arguments: [0.85, 1.0, 1.25])
    func slots(scale: Double) {
        let metrics = IslandMetrics(scale: scale)
        // The part of the ideal height under the header: the list's height less paddings, header and spacing.
        let header = metrics.textSize(12) * 1.25
        let rowsHeight = AttributionListView.height(for: metrics) - 16 * scale - 7 * scale - header
        #expect(AttributionRows.slotCount(height: rowsHeight, metrics: metrics) == AttributionRows.maximumRows)
        #expect(AttributionRows.slotCount(height: rowsHeight + 1.8 * rowsHeight / 4, metrics: metrics) == 5)
        #expect(AttributionRows.slotCount(height: 10, metrics: metrics) == AttributionRows.maximumRows)
        #expect(AttributionRows.slotCount(height: 5_000, metrics: metrics) == AttributionRows.maximumSlots)
        #expect(AttributionRows.slotCount(height: .infinity, metrics: metrics) == AttributionRows.maximumRows)
    }
}

@Suite("Attribution rows")
struct AttributionRowsTests {
    private typealias Fixture = AnalyticsFixture

    @Test("Up to four shares show as they are")
    func fewShares() throws {
        let report = Fixture.report([
            try Fixture.share("project:a", "Codometer", share: 0.6, points: 24),
            try Fixture.share("project:b", "api", share: 0.4, points: 16),
        ])
        let rows = AttributionRows.rows(from: report, l10n: .testRussian)
        #expect(rows.map(\.title) == ["Codometer", "api"])
        #expect(rows.map(\.valueText) == ["≈24\u{00A0}%", "≈16\u{00A0}%"])
        #expect(!AttributionRows.showsPlaceholder(report))
    }

    @Test("More than four shares fold the rest into “Other”")
    func folding() throws {
        let report = Fixture.report([
            try Fixture.share("project:a", "a", share: 0.4, points: 16),
            try Fixture.share("project:b", "b", share: 0.2, points: 8),
            try Fixture.share("project:c", "c", share: 0.15, points: 6),
            try Fixture.share("project:d", "d", share: 0.1, points: 4),
            try Fixture.share("project:e", "e", share: 0.1, points: 4),
            try Fixture.share(UsageAttribution.otherShareID, "other", share: 0.05, points: 2),
        ])
        let rows = AttributionRows.rows(from: report, l10n: .testRussian)
        #expect(rows.map(\.id) == ["project:a", "project:b", "project:c", UsageAttribution.otherShareID])
        let other = try #require(rows.last)
        #expect(other.isOther)
        #expect(abs(other.share - 0.25) < 1e-9)
        #expect(other.estimatedPoints.map { abs($0 - 10) < 1e-9 } == true)
        #expect(other.valueText == "≈10\u{00A0}%")
    }

    @Test("Folded points are unknown when any folded share lacks them")
    func foldingWithoutPoints() throws {
        let report = Fixture.report([
            try Fixture.share("a", "a", share: 0.5, points: nil),
            try Fixture.share("b", "b", share: 0.2, points: nil),
            try Fixture.share("c", "c", share: 0.1, points: nil),
            try Fixture.share("d", "d", share: 0.1, points: nil),
            try Fixture.share("e", "e", share: 0.1, points: nil),
        ])
        let rows = AttributionRows.rows(from: report, l10n: .testRussian)
        #expect(rows.count == 4)
        #expect(rows.last?.estimatedPoints == nil)
        #expect(rows.last?.valueText == "20\u{00A0}%")
        #expect(AttributionRows.rows(from: report, maximum: 1, l10n: .testRussian).map(\.id) == [UsageAttribution.otherShareID])
    }

    @Test("Values read as points when known, else as the share; VoiceOver says “about” instead of ≈")
    func values() {
        #expect(AttributionRows.valueText(share: 0.41, estimatedPoints: 3.2, l10n: .testEnglish) == "≈3.2%")
        #expect(AttributionRows.valueA11y(share: 0.41, estimatedPoints: 3.2, l10n: .testEnglish) == "about 3.2%")
        #expect(AttributionRows.valueA11y(share: 0.41, estimatedPoints: 12.34, l10n: .testEnglish) == "about 12%")
        #expect(AttributionRows.valueA11y(share: 0.41, estimatedPoints: 0.01, l10n: .testEnglish) == "less than 0.1%")
        #expect(AttributionRows.valueA11y(share: 0.41, estimatedPoints: nil, l10n: .testEnglish) == "41%")
        #expect(AttributionRows.valueA11y(share: 0.41, estimatedPoints: 3.2, l10n: .testRussian) == "около 3,2\u{00A0}%")
        #expect(AttributionRows.valueA11y(share: 0.41, estimatedPoints: 0.01, l10n: .testRussian) == "меньше 0,1\u{00A0}%")
        #expect(AttributionRows.valueText(share: 0.41, estimatedPoints: 3.2, l10n: .testRussian) == "≈3,2\u{00A0}%")
        #expect(AttributionRows.valueText(share: 0.41, estimatedPoints: nil, l10n: .testRussian) == "41\u{00A0}%")
        #expect(AttributionRows.valueText(share: 0.004, estimatedPoints: nil, l10n: .testRussian) == "<1\u{00A0}%")
        #expect(AttributionRows.valueText(share: 0.1, estimatedPoints: 0.01, l10n: .testRussian) == "<0,1\u{00A0}%")
    }

    @Test("Placeholder and header note")
    func noteAndPlaceholder() throws {
        #expect(AttributionRows.showsPlaceholder(nil))
        #expect(AttributionRows.showsPlaceholder(Fixture.report([])))
        #expect(AttributionRows.note(for: nil, l10n: .testRussian) == nil)
        #expect(AttributionRows.note(for: Fixture.report([]), l10n: .testRussian) == nil)
        let shares = [try Fixture.share("a", "a", share: 1, points: 5)]
        #expect(AttributionRows.note(for: Fixture.report(shares), l10n: .testRussian) == "оценка по токенам")
        #expect(AttributionRows.note(for: Fixture.report(shares), l10n: .testEnglish) == "Estimated from tokens")
        #expect(AttributionRows.note(for: Fixture.report(shares, coverageStart: -Fixture.hours(3)), l10n: .testEnglish) == "Data since 11:32\u{202F}AM")
        #expect(AttributionRows.note(for: Fixture.report(shares, coverageStart: -Fixture.hours(3)), l10n: .testRussian) == "данные с 11:32")
    }
}

// MARK: - Sizes

@MainActor
@Suite("Analytics view sizes")
struct AnalyticsViewSizeTests {
    private typealias Fixture = AnalyticsFixture
    private let now = AnalyticsFixture.now

    private func size(of view: some View, width: CGFloat) -> CGSize {
        let controller = NSHostingController(rootView: view.frame(width: width))
        return controller.sizeThatFits(in: CGSize(width: width, height: 2_000))
    }

    /// The size a layout that measures without a height (the deck's page stack) gets.
    private func idealSize(of view: some View, width: CGFloat) -> CGSize {
        let controller = NSHostingController(rootView: view.frame(width: width).fixedSize())
        return controller.sizeThatFits(in: CGSize(width: width, height: 2_000))
    }

    @Test("The history chart keeps one size with no, too little and plenty of history", arguments: [0.85, 1.0, 1.25])
    func chart(scale: Double) throws {
        let metrics = IslandMetrics(scale: scale)
        let window = try Fixture.window(used: 62)
        let full = try Fixture.series(stride(from: -Fixture.hours(3), through: -60, by: 600).map { ($0, 62 + $0 / 300) })
        let sizes = [
            size(of: WindowHistoryChart(series: nil, window: window, now: now, metrics: metrics), width: 372),
            size(of: WindowHistoryChart(series: try Fixture.series([]), window: window, now: now, metrics: metrics), width: 372),
            size(of: WindowHistoryChart(series: full, window: window, now: now, metrics: metrics), width: 372),
        ]
        #expect(Set(sizes.map(\.height)) == [WindowHistoryChart.height(for: metrics)])
        #expect(Set(sizes.map(\.width)) == [372])
    }

    @Test("The timeline keeps one size with no, empty and busy snapshots", arguments: [0.85, 1.0, 1.25])
    func timeline(scale: Double) throws {
        let metrics = IslandMetrics(scale: scale)
        let interval = DateInterval(start: now.addingTimeInterval(-Fixture.hours(5)), end: now)
        let busy = TimelineSnapshot(
            accountID: Fixture.account,
            interval: interval,
            segments: try (0..<8).map { try Fixture.segment("s\($0)", $0 % 3 == 0 ? .waiting : .working, from: -Fixture.hours(4), to: -Fixture.hours(3)) },
            usage: try Fixture.series([(-Fixture.hours(4), 10), (-Fixture.hours(1), 50)]),
            coverageStart: now.addingTimeInterval(-Fixture.hours(4))
        )
        let empty = TimelineSnapshot(accountID: Fixture.account, interval: interval, segments: [], usage: nil)
        // Gaps are drawn inside the plot, so they never change the timeline's height either.
        let gapped = TimelineSnapshot(
            accountID: Fixture.account,
            interval: interval,
            segments: busy.segments,
            usage: busy.usage,
            coverageStart: busy.coverageStart,
            gaps: [
                CollectionGap(
                    interval: DateInterval(start: now.addingTimeInterval(-Fixture.hours(3.5)), end: now.addingTimeInterval(-Fixture.hours(1.5))),
                    reason: .macAsleep
                ),
                CollectionGap(
                    interval: DateInterval(start: now.addingTimeInterval(-Fixture.minutes(20)), end: now),
                    reason: .appNotRunning
                ),
            ]
        )
        let views = [
            SessionTimelineView(snapshot: nil, now: now, metrics: metrics),
            SessionTimelineView(snapshot: empty, now: now, metrics: metrics),
            SessionTimelineView(snapshot: busy, now: now, metrics: metrics),
            SessionTimelineView(snapshot: gapped, now: now, metrics: metrics),
        ]
        let ideal = views.map { idealSize(of: $0, width: 372) }
        #expect(Set(ideal.map(\.height)) == [SessionTimelineView.height(for: metrics)])
        #expect(Set(ideal.map(\.width)) == [372])
        // Offered more (its page is as tall as the tallest page), it fills that height whatever the data; offered
        // less, it keeps its ideal height.
        let taller = SessionTimelineView.height(for: metrics) + 90
        #expect(Set(views.map { size(of: $0.frame(height: taller), width: 372).height }) == [taller])
        let controller = NSHostingController(rootView: views[2].frame(width: 372))
        #expect(controller.sizeThatFits(in: CGSize(width: 372, height: 40)).height == SessionTimelineView.height(for: metrics))
    }

    @Test("The attribution list keeps one size with no, empty and long reports", arguments: [0.85, 1.0, 1.25])
    func attribution(scale: Double) throws {
        let metrics = IslandMetrics(scale: scale)
        let long = Fixture.report(try (0..<9).map {
            try Fixture.share("project:\($0)", "очень-длинное-название-проекта-\($0)", share: 0.1, points: 12.34)
        }, coverageStart: -Fixture.hours(3))
        let views = [
            AttributionListView(report: nil, metrics: metrics),
            AttributionListView(report: Fixture.report([]), metrics: metrics),
            AttributionListView(report: long, metrics: metrics),
        ]
        let ideal = views.map { idealSize(of: $0, width: 372) }
        #expect(Set(ideal.map(\.height)) == [AttributionListView.height(for: metrics)])
        #expect(Set(ideal.map(\.width)) == [372])
        let taller = AttributionListView.height(for: metrics) + 60
        #expect(Set(views.map { size(of: $0.frame(height: taller), width: 372).height }) == [taller])
    }
}

// MARK: - Copy fit

/// Text widths the way the island draws them: SF Rounded, optionally with monospaced digits (`IslandMetrics.digits`).
enum TextFit {
    static func width(_ text: String, size: CGFloat, weight: NSFont.Weight, monospacedDigits: Bool) -> CGFloat {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        var descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
        if monospacedDigits {
            descriptor = descriptor.addingAttributes([
                .featureSettings: [[
                    NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                    NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
                ]],
            ])
        }
        let font = NSFont(descriptor: descriptor, size: size) ?? base
        return (text as NSString).size(withAttributes: [.font: font]).width
    }
}

@Suite("Analytics copy fit")
struct AnalyticsCopyFitTests {
    private typealias Fixture = AnalyticsFixture

    @Test(
        "The attribution value template is at least as wide as every value, in both languages",
        arguments: [0.85, 1.0, 1.5], [Localizer.testEnglish, .testRussian]
    )
    func valueTemplate(scale: Double, l10n: Localizer) {
        let size = IslandMetrics(scale: scale).textSize(11)
        let template = TextFit.width(AttributionRows.valueTemplate(l10n: l10n), size: size, weight: .semibold, monospacedDigits: true)
        var values = stride(from: 0.0, through: 100, by: 0.05).map { AttributionRows.valueText(share: 0.5, estimatedPoints: $0, l10n: l10n) }
        values += stride(from: 0.0, through: 1, by: 0.001).map { AttributionRows.valueText(share: $0, estimatedPoints: nil, l10n: l10n) }
        for value in Set(values) {
            #expect(TextFit.width(value, size: size, weight: .semibold, monospacedDigits: true) <= template + 0.01, "\(l10n.language): \(value)")
        }
    }

    @MainActor
    @Test("Timeline gutter captions fit the lane title column, in both languages", arguments: [0.85, 1.0, 1.25], [Localizer.testEnglish, .testRussian])
    func gutter(scale: Double, l10n: Localizer) {
        let metrics = IslandMetrics(scale: scale)
        let frame = TimelineFrame(size: CGSize(width: 372 * scale, height: SessionTimelineView.height(for: metrics)), metrics: metrics)
        let size = metrics.textSize(10.5)
        #expect(TextFit.width(l10n.analytics.limitCaption, size: size, weight: .medium, monospacedDigits: false) <= frame.gutterWidth)
        let overflow = TimelineLaneSelection(lanes: [], hiddenCount: 99).overflowText(l10n: l10n) ?? ""
        #expect(TextFit.width(overflow, size: size, weight: .medium, monospacedDigits: false) <= frame.gutterWidth, "\(overflow)")
    }

    @MainActor
    @Test("One-line placeholders and the attribution header fit the deck's width, in both languages", arguments: [0.85, 1.0, 1.25], [Localizer.testEnglish, .testRussian])
    func placeholders(scale: Double, l10n: Localizer) throws {
        let metrics = IslandMetrics(scale: scale)
        let inner = metrics.deckWidth - metrics.deckPadding * 2
        let frame = TimelineFrame(size: CGSize(width: inner, height: SessionTimelineView.height(for: metrics)), metrics: metrics)
        let text = l10n.analytics
        for caption in [text.noSessionsInPeriod, text.timelineEmpty] {
            #expect(TextFit.width(caption, size: metrics.textSize(11), weight: .medium, monospacedDigits: false) + 20 * scale <= frame.lanesArea.width, "\(caption)")
        }
        #expect(TextFit.width(text.noLimitHistory, size: metrics.textSize(10.5), weight: .medium, monospacedDigits: false) <= frame.curve.width)
        #expect(TextFit.width(text.collectingHistory, size: metrics.textSize(11), weight: .medium, monospacedDigits: false) + 20 * scale <= inner)
        // Title, the longest coverage note (a date a week back) and the padding.
        let oldest = AnalyticsText.coverageNote(
            coverageStart: Fixture.now.addingTimeInterval(-Fixture.hours(24 * 6 + 20)),
            intervalStart: Fixture.now.addingTimeInterval(-Fixture.hours(24 * 7)),
            now: Fixture.now,
            l10n: l10n
        )
        let note = try #require(oldest)
        let header = TextFit.width(text.whatsEatingLimit, size: metrics.textSize(12), weight: .semibold, monospacedDigits: false)
            + 6 * scale
            + TextFit.width(note, size: metrics.textSize(10.5), weight: .medium, monospacedDigits: false)
        #expect(header <= inner - 24 * scale, "\(text.whatsEatingLimit) \(note)")
        #expect(TextFit.width(text.noTokenData, size: metrics.textSize(11), weight: .medium, monospacedDigits: false) + 20 * scale <= inner - 24 * scale)
    }

    @Test("Analytics phrases in both languages")
    func phrases() {
        let en = Localizer.testEnglish.analytics
        let ru = Localizer.testRussian.analytics
        #expect(en.whatsEatingLimit == "What’s eating your limit")
        #expect(ru.whatsEatingLimit == "Кто съел лимит")
        #expect(en.collectingHistory == "Collecting history…")
        #expect(en.moreLanes(3) == "3 more")
        #expect(ru.moreLanes(3) == "ещё 3")
        #expect(en.chartTime == "Time" && ru.chartTime == "Время")
        for count in [1, 2, 5, 11, 21, 22, 25, 101] {
            #expect(ru.sessions(count).hasPrefix("\(count) "))
        }
        #expect(ru.sessions(21) == "21 сессия")
        #expect(ru.sessions(12) == "12 сессий")
    }
}

// MARK: - Renders

/// Renders the analytics views with realistic data to PNG files for visual review, in English and Russian
/// (`…-en.png`, `…-ru.png`). Runs only when `CODOMETER_ANALYTICS_SNAPSHOT_DIR` or `CODOMETER_SNAPSHOT_DIR` is set; with
/// the latter the files land in its `analytics` folder.
@MainActor
@Suite(
    "Analytics snapshots",
    .enabled(if: ProcessInfo.processInfo.environment["CODOMETER_ANALYTICS_SNAPSHOT_DIR"] != nil
        || ProcessInfo.processInfo.environment["CODOMETER_SNAPSHOT_DIR"] != nil)
)
struct AnalyticsSnapshotTests {
    private typealias Fixture = AnalyticsFixture
    private let directory: URL = {
        let environment = ProcessInfo.processInfo.environment
        if let analytics = environment["CODOMETER_ANALYTICS_SNAPSHOT_DIR"] {
            return URL(fileURLWithPath: analytics, isDirectory: true)
        }
        return URL(fileURLWithPath: environment["CODOMETER_SNAPSHOT_DIR"] ?? "/tmp", isDirectory: true)
            .appendingPathComponent("analytics", isDirectory: true)
    }()
    private let now = AnalyticsFixture.now
    private let claudeStyle = AnalyticsStyle(provider: .claude)
    private let codexStyle = AnalyticsStyle(provider: .codex)

    @Test("Analytics views in light and dark appearance, in both languages", arguments: [Localizer.testEnglish, .testRussian])
    func renderAll(l10n: Localizer) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let language = l10n.language.rawValue
        for scheme in [ColorScheme.light, .dark] {
            let suffix = "\(scheme == .dark ? "dark" : "light")-\(language)"
            try render(charts(), name: "charts-\(suffix)", scheme: scheme, l10n: l10n)
            try render(timelines(), name: "timeline-\(suffix)", scheme: scheme, l10n: l10n)
            try render(attributions(), name: "attribution-\(suffix)", scheme: scheme, l10n: l10n)
        }
        let small = IslandMetrics(scale: 0.85)
        let smallTimelines = try timelines(metrics: small)
        let smallAttributions = try attributions(metrics: small)
        try render(
            VStack(spacing: 18) {
                smallTimelines
                smallAttributions
            },
            name: "scale-085-light-\(language)",
            scheme: .light,
            l10n: l10n,
            metrics: small
        )
        // The widest texts the views can show: long notes, a large overflow and the value template itself.
        try render(extremes(), name: "extremes-light-\(language)", scheme: .light, l10n: l10n)
    }

    private func extremes(metrics: IslandMetrics = IslandMetrics(scale: 1)) throws -> some View {
        let week = DateInterval(start: now.addingTimeInterval(-Fixture.hours(24 * 7)), end: now)
        var segments: [SessionSegment] = []
        for index in 0..<12 {
            let activity: AgentActivity = index % 2 == 0 ? .working : .waiting
            let start: TimeInterval = -Fixture.hours(Double(20 + index))
            let end: TimeInterval = -Fixture.hours(Double(19 + index))
            segments.append(try Fixture.segment("s\(index)", activity, from: start, to: end, title: "project-\(index)"))
        }
        let crowded = TimelineSnapshot(
            accountID: Fixture.account,
            interval: week,
            segments: segments,
            usage: try Fixture.series([(-Fixture.hours(30), 20), (-Fixture.hours(2), 100)]),
            coverageStart: now.addingTimeInterval(-Fixture.hours(24 * 5 + 7))
        )
        let widest = Fixture.report([
            try Fixture.share("project:a", "a-very-long-project-folder-name-that-truncates", share: 1, points: 100),
            try Fixture.share("project:b", "b", share: 0.5, points: 88.8),
            try Fixture.share("project:c", "c", share: 0.004, points: nil),
            try Fixture.share("project:d", "d", share: 0.001, points: 0.01),
        ], coverageStart: -Fixture.hours(24 * 5 + 7), duration: Fixture.hours(24 * 7))
        return VStack(alignment: .leading, spacing: 18) {
            caption("7d, coverage from 5 days ago, 12 sessions, overflow")
            SessionTimelineView(snapshot: crowded, now: now, metrics: metrics)
            caption("≈100% and 88.8, share <1%, <0.1 points, old coverage note")
            AttributionListView(report: widest, metrics: metrics)
        }
        .environment(\.analyticsStyle, claudeStyle)
    }

    private func charts(metrics: IslandMetrics = IslandMetrics(scale: 1)) throws -> some View {
        // A session window 3 h in at 68 %, climbing fast after a quiet start: projection before the reset.
        let hot = try Fixture.window(used: 68, resetsIn: Fixture.hours(2))
        let hotSeries = try Fixture.series(stride(from: -Fixture.hours(3), through: -Fixture.minutes(4), by: 300).map { offset in
            let t = (offset + Fixture.hours(3)) / Fixture.hours(3)
            return (offset, 68 * pow(t, 1.7))
        })
        // A weekly window two days in at 23 %: calm, behind pace.
        let week = try Fixture.window(used: 23, duration: .oneWeek, resetsIn: Fixture.hours(24 * 5), scope: .weekly(model: nil))
        let weekSeries = try Fixture.series(stride(from: -Fixture.hours(48), through: -Fixture.minutes(5), by: 1_800).map { offset in
            let t = (offset + Fixture.hours(48)) / Fixture.hours(48)
            return (offset, 23 * t + 2 * sin(t * 9))
        }.map { ($0.0, max(0, $0.1)) })
        // A window that ran out: 100 %.
        let done = try Fixture.window(used: 100, resetsIn: Fixture.minutes(40))
        let doneSeries = try Fixture.series(stride(from: -Fixture.hours(4.3), through: -Fixture.minutes(2), by: 600).map { offset in
            let t = (offset + Fixture.hours(4.3)) / Fixture.hours(4.3)
            return (offset, min(100, 115 * t))
        })
        let fresh = try Fixture.window(used: 5, resetsIn: Fixture.hours(4.9))
        let freshSeries = try Fixture.series([(-300, 4)])
        return VStack(alignment: .leading, spacing: 18) {
            caption("Session · 5h at 68%, runs out before the reset")
            WindowHistoryChart(series: hotSeries, window: hot, now: now, metrics: metrics)
            caption("Weekly · All models at 23%")
            WindowHistoryChart(series: weekSeries, window: week, now: now, metrics: metrics)
            caption("Limit reached, 100%")
            WindowHistoryChart(series: doneSeries, window: done, now: now, metrics: metrics)
            caption("Too little history")
            WindowHistoryChart(series: freshSeries, window: fresh, now: now, metrics: metrics)
        }
        .environment(\.analyticsStyle, claudeStyle)
    }

    private func timelines(metrics: IslandMetrics = IslandMetrics(scale: 1)) throws -> some View {
        let day = DateInterval(start: now.addingTimeInterval(-Fixture.hours(24)), end: now)
        let segments: [SessionSegment] = try [
            Fixture.segment("codometer-1", .working, from: -Fixture.hours(13), to: -Fixture.hours(11.2), title: "Codometer"),
            Fixture.segment("codometer-1", .waiting, from: -Fixture.hours(11.2), to: -Fixture.hours(10.9), title: "Codometer"),
            Fixture.segment("codometer-1", .working, from: -Fixture.hours(10.9), to: -Fixture.hours(9), title: "Codometer"),
            Fixture.segment("codometer-1", .working, from: -Fixture.hours(3.2), to: -Fixture.hours(1.1), title: "Codometer"),
            Fixture.segment("codometer-1", .working, from: -Fixture.minutes(25), to: nil, title: "Codometer"),
            Fixture.segment("api-2", .working, from: -Fixture.hours(8), to: -Fixture.hours(6.5), title: "exchanger-api"),
            Fixture.segment("api-2", .waiting, from: -Fixture.hours(6.5), to: -Fixture.hours(5.8), title: "exchanger-api"),
            Fixture.segment("api-2", .working, from: -Fixture.hours(2.5), to: -Fixture.minutes(40), title: "exchanger-api"),
            Fixture.segment("api-2", .waiting, from: -Fixture.minutes(12), to: nil, title: "exchanger-api"),
            Fixture.segment("docs-3", .working, from: -Fixture.hours(12), to: -Fixture.hours(10.5), title: "docs"),
            Fixture.segment("web-4", .working, from: -Fixture.hours(7), to: -Fixture.hours(6), title: "landing-web"),
            Fixture.segment("web-4", .waiting, from: -Fixture.hours(6), to: -Fixture.hours(5.9), title: "landing-web"),
            Fixture.segment("scripts-5", .working, from: -Fixture.hours(4.5), to: -Fixture.hours(4), title: "scripts"),
            Fixture.segment("infra-6", .working, from: -Fixture.hours(2), to: -Fixture.hours(1.8), title: "infra"),
            Fixture.segment("misc-7", .working, from: -Fixture.hours(9.5), to: -Fixture.hours(9.45), title: "misc"),
        ]
        // Session usage with a reset every five hours.
        var values: [(TimeInterval, Double)] = []
        let resets: [TimeInterval] = [-Fixture.hours(19), -Fixture.hours(14), -Fixture.hours(9), -Fixture.hours(4)]
        for offset in stride(from: -Fixture.hours(24), through: -Fixture.minutes(3), by: 600) {
            let since = resets.last { $0 <= offset } ?? -Fixture.hours(24)
            let busy = segments.contains { $0.start <= now.addingTimeInterval(offset) && (now.addingTimeInterval(offset) < ($0.end ?? now)) }
            let previous = values.last { $0.0 >= since }?.1 ?? 0
            values.append((offset, min(100, previous + (busy ? 4.2 : 0.2))))
        }
        let usage = try Fixture.series(values, resets: resets)
        let busy = TimelineSnapshot(
            accountID: Fixture.account,
            interval: day,
            segments: segments,
            usage: usage,
            coverageStart: now.addingTimeInterval(-Fixture.hours(13))
        )
        let fiveHours = DateInterval(start: now.addingTimeInterval(-Fixture.hours(5)), end: now)
        let short = TimelineSnapshot(
            accountID: Fixture.account,
            interval: fiveHours,
            segments: segments.filter { $0.start >= fiveHours.start },
            usage: try Fixture.series(values.filter { $0.0 >= -Fixture.hours(5) }, resets: [-Fixture.hours(4)]),
            coverageStart: fiveHours.start
        )
        var hovered = SessionTimelineView(snapshot: busy, now: now, metrics: metrics)
        hovered.previewHoverX = 300
        return VStack(alignment: .leading, spacing: 18) {
            caption("24h, data since 1:32, 7 sessions")
            SessionTimelineView(snapshot: busy, now: now, metrics: metrics)
            caption("Hover")
            hovered
            caption("5h, Codex")
            SessionTimelineView(snapshot: short, now: now, metrics: metrics)
                .environment(\.analyticsStyle, codexStyle)
            caption("Empty period, then no snapshot")
            SessionTimelineView(
                snapshot: TimelineSnapshot(accountID: Fixture.account, interval: fiveHours, segments: [], usage: nil),
                now: now,
                metrics: metrics
            )
            SessionTimelineView(snapshot: nil, now: now, metrics: metrics)
        }
        .environment(\.analyticsStyle, claudeStyle)
    }

    private func attributions(metrics: IslandMetrics = IslandMetrics(scale: 1)) throws -> some View {
        let full = Fixture.report([
            try Fixture.share("project:a", "Codometer", share: 0.46, points: 18.4),
            try Fixture.share("project:b", "exchanger-api", share: 0.27, points: 10.8),
            try Fixture.share("project:c", "landing-web", share: 0.12, points: 4.8),
            try Fixture.share("project:d", "docs", share: 0.08, points: 3.2),
            try Fixture.share("project:e", "scripts", share: 0.05, points: 2.0),
            try Fixture.share("project:f", "без проекта", share: 0.02, points: 0.8),
        ], coverageStart: -Fixture.hours(13))
        let shares = Fixture.report([
            try Fixture.share("session:a", "Codometer · 3f9a1c", share: 0.71, points: nil),
            try Fixture.share("session:b", "exchanger-api-with-a-very-long-name · 77b2e0", share: 0.29, points: nil),
        ])
        return VStack(alignment: .leading, spacing: 18) {
            caption("Projects, ≈ points, partial data")
            AttributionListView(report: full, metrics: metrics)
            caption("Sessions, shares, Codex")
            AttributionListView(report: shares, metrics: metrics)
                .environment(\.analyticsStyle, codexStyle)
            caption("No data")
            AttributionListView(report: nil, metrics: metrics)
        }
        .environment(\.analyticsStyle, claudeStyle)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
    }

    private func render(_ view: some View, name: String, scheme: ColorScheme, l10n: Localizer, metrics: IslandMetrics = IslandMetrics(scale: 1)) throws {
        let content = view
            .frame(width: metrics.deckWidth - 2 * metrics.deckPadding)
            .padding(metrics.deckPadding)
            .background(RoundedRectangle(cornerRadius: metrics.deckCorner, style: .continuous).fill(.regularMaterial))
            .padding(28)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.98, green: 0.55, blue: 0.40), Color(red: 0.55, green: 0.33, blue: 0.86), Color(red: 0.16, green: 0.50, blue: 0.92)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .environment(\.colorScheme, scheme)
            .environment(\.introAnimationsEnabled, false)
            .environment(\.liveEffectsEnabled, false)
            .environment(\.l10n, l10n)
            .environment(\.locale, l10n.locale)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let bitmap = NSBitmapImageRep(cgImage: image)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }
}
