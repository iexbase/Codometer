import CodometerCore
import CodometerL10n
import Foundation

/// What `WindowHistoryChart` draws for one window, computed without SwiftUI so it can be tested.
struct HistoryChartModel: Hashable, Sendable {
    /// One usage observation on the chart's 0…100 scale.
    struct Point: Hashable, Sendable, Identifiable {
        let at: Date
        let used: Double

        var id: Date { at }
    }

    /// A dashed straight segment: the even pace or the projection to exhaustion.
    struct Segment: Hashable, Sendable {
        let from: Point
        let to: Point
    }

    /// Stored observations needed before a curve means anything; fewer show "Collecting history…".
    static let minimumStoredPoints = 2
    /// Most stored observations drawn. A strip about 370 pt wide cannot show more, and fewer marks keep
    /// Swift Charts cheap for long weekly histories.
    static let maximumDrawnPoints = 180

    /// The x domain: the window's start (else the first observation) to its reset (else `now`).
    let domain: ClosedRange<Date>
    /// Observations of the current window period inside the domain, ending with the live value at `now`.
    let points: [Point]
    /// Whether too little history exists to draw a curve.
    let isPlaceholder: Bool
    /// From (start, 0) to (reset, 100); `nil` unless both the window start and reset are known.
    let evenPace: Segment?
    /// `now` when it falls inside the domain.
    let now: Date?
    /// The live value at `now`, drawn as a dot at the end of the curve.
    let current: Point?
    /// From the live value to (projected exhaustion, 100) when the limit runs out before the reset.
    let projection: Segment?

    init(series: HistorySeries?, window: LimitWindow, now: Date) {
        let domain = Self.domain(series: series, window: window, now: now)
        let stored = Self.storedPoints(series: series, domain: domain, now: now)
        self.domain = domain
        isPlaceholder = stored.count < Self.minimumStoredPoints

        let nowInside = domain.contains(now) ? now : nil
        self.now = nowInside
        let live = nowInside.map { Point(at: $0, used: Self.clamp(window.used.value)) }
        current = live

        var points = Self.thinned(stored, domain: domain, maximum: Self.maximumDrawnPoints)
        if let live {
            if let last = points.last, last.at >= live.at {
                points[points.count - 1] = Point(at: last.at, used: live.used)
            } else {
                points.append(live)
            }
        }
        self.points = points

        if let start = window.windowStart, let reset = window.resetsAt, start < reset {
            evenPace = Segment(from: Point(at: start, used: 0), to: Point(at: reset, used: 100))
        } else {
            evenPace = nil
        }

        if let live, let exhaustion = UsagePace(window: window, now: now)?.projectedExhaustion, exhaustion > live.at {
            projection = Segment(from: live, to: Point(at: min(exhaustion, domain.upperBound), used: 100))
        } else {
            projection = nil
        }
    }

    /// The window's start (fallback: the first observation) to its reset (fallback: `now`).
    ///
    /// Without either bound the domain ends at `now` and starts one window length earlier (five hours when the
    /// duration is unknown). An empty or inverted domain grows to one minute, so a scale is always valid.
    static func domain(series: HistorySeries?, window: LimitWindow, now: Date) -> ClosedRange<Date> {
        let upper = window.resetsAt ?? now
        let fallbackLength = window.duration?.timeInterval ?? WindowDuration.fiveHours.timeInterval
        let lower = window.windowStart ?? series?.points.first?.at ?? upper.addingTimeInterval(-fallbackLength)
        guard upper > lower else { return lower...lower.addingTimeInterval(60) }
        return lower...upper
    }

    /// Observations inside the domain and not after `now`, starting after the latest reset inside that range,
    /// clamped to 0…100, one per timestamp (the later one wins).
    static func storedPoints(series: HistorySeries?, domain: ClosedRange<Date>, now: Date) -> [Point] {
        guard let series else { return [] }
        let end = min(domain.upperBound, now)
        let periodStart = series.resets.last { $0 > domain.lowerBound && $0 <= end } ?? domain.lowerBound
        var points: [Point] = []
        for point in series.points where point.at >= periodStart && point.at <= end {
            let clamped = Point(at: point.at, used: clamp(point.used))
            if let last = points.last, last.at == point.at {
                points[points.count - 1] = clamped
            } else {
                points.append(clamped)
            }
        }
        return points
    }

    /// At most `maximum` points: the first one, then the latest point of each of `maximum − 1` equal time slices
    /// of the domain. Ascending input expected; shorter input is returned as is.
    static func thinned(_ points: [Point], domain: ClosedRange<Date>, maximum: Int) -> [Point] {
        guard maximum >= 2, points.count > maximum, let first = points.first else { return points }
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        guard span > 0 else { return Array(points.suffix(maximum)) }
        let slices = maximum - 1
        var result = [first]
        var lastSlice: Int?
        for point in points.dropFirst() {
            let fraction = min(max(point.at.timeIntervalSince(domain.lowerBound) / span, 0), 1)
            let slice = min(Int(fraction * Double(slices)), slices - 1)
            if slice == lastSlice {
                result[result.count - 1] = point
            } else {
                result.append(point)
                lastSlice = slice
            }
        }
        return result
    }

    static func clamp(_ used: Double) -> Double {
        used.isFinite ? min(max(used, 0), 100) : 0
    }

    /// The VoiceOver summary: "Usage history: 57% now, 12% ahead of pace, runs out at 4:40 PM".
    static func accessibilitySummary(
        model: HistoryChartModel,
        window: LimitWindow,
        now: Date,
        l10n: Localizer
    ) -> String {
        let text = l10n.analytics
        guard !model.isPlaceholder else { return text.historyCollectingA11y }
        var parts = [text.nowA11y(AnalyticsText.percent(window.used.value, l10n: l10n))]
        if let pace = UsagePace(window: window, now: now) {
            switch pace.verdict {
            case .ahead(let points): parts.append(text.aheadOfPaceA11y(AnalyticsText.percent(points, l10n: l10n)))
            case .behind(let points): parts.append(text.spareA11y(AnalyticsText.percent(points, l10n: l10n)))
            case .onTrack: parts.append(text.onPaceA11y)
            }
        }
        if let projection = model.projection {
            parts.append(text.runsOutA11y(l10n.format.moment(projection.to.at, now: now)))
        }
        return text.historyA11y(parts.joined(separator: ", "))
    }
}
