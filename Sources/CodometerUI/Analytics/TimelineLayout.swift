import CodometerCore
import CodometerL10n
import Foundation

/// One session's row in the timeline.
struct TimelineLane: Hashable, Sendable, Identifiable {
    let sessionID: String
    /// The project folder of the session's latest segment, or "Codometer · 3f9a1c" when another shown lane has the
    /// same folder; "Session 3f9a1c" without a project. Never the session's own title.
    let title: String
    /// The session's segments that touch the interval, by start time.
    let segments: [SessionSegment]
    /// Working and waiting time inside the interval.
    let activeTime: TimeInterval
    /// What the session is doing now, when its latest segment is still open.
    let openActivity: AgentActivity?

    var id: String { sessionID }
}

/// The lanes a timeline shows and how many sessions did not fit.
struct TimelineLaneSelection: Hashable, Sendable {
    let lanes: [TimelineLane]
    let hiddenCount: Int

    /// "3 more" when sessions were left out, else `nil`.
    func overflowText(l10n: Localizer) -> String? {
        hiddenCount > 0 ? l10n.analytics.moreLanes(hiddenCount) : nil
    }
}

/// A gap in the collected data as the timeline draws it: where it sits on the time axis and what it says.
struct TimelineGapSpan: Hashable, Sendable {
    /// The gap's extent along the plot.
    let x: ClosedRange<CGFloat>
    /// The gap clipped to the shown interval.
    let interval: DateInterval
    let reason: CollectionGap.Reason

    var width: CGFloat { x.upperBound - x.lowerBound }
}

/// Pure layout decisions for `SessionTimelineView`: lanes, ticks, usage lookups, gaps and the hover tooltip.
enum TimelineLayout {
    static let maximumLanes = 5

    // MARK: - Lanes

    /// Sessions ordered by active time inside the interval (longest first, then most recently active,
    /// then by id), at most `maximum` of them, titled by `laneTitles`. Open segments count up to `now`.
    static func lanes(
        segments: [SessionSegment],
        interval: DateInterval,
        now: Date,
        maximum: Int = maximumLanes,
        l10n: Localizer
    ) -> TimelineLaneSelection {
        var bySession: [String: [SessionSegment]] = [:]
        for segment in segments where touches(segment, interval: interval, now: now) {
            bySession[segment.sessionID, default: []].append(segment)
        }
        let candidates = bySession.map { sessionID, segments -> (lane: TimelineLane, project: String?, lastActive: Date) in
            let ordered = segments.sorted { lhs, rhs in lhs.start == rhs.start ? lhs.id < rhs.id : lhs.start < rhs.start }
            let active = ordered.reduce(0) { $0 + overlap(of: $1, interval: interval, now: now) }
            let latest = ordered.last
            let lastActive = ordered.map { $0.end ?? now }.max() ?? interval.start
            let lane = TimelineLane(
                sessionID: sessionID,
                title: latest?.title ?? "—",
                segments: ordered,
                activeTime: active,
                openActivity: latest.flatMap { $0.isOpen ? $0.activity : nil }
            )
            return (lane, latest?.project, lastActive)
        }
        .sorted { lhs, rhs in
            if lhs.lane.activeTime != rhs.lane.activeTime { return lhs.lane.activeTime > rhs.lane.activeTime }
            if lhs.lastActive != rhs.lastActive { return lhs.lastActive > rhs.lastActive }
            return lhs.lane.sessionID < rhs.lane.sessionID
        }

        let limit = max(0, maximum)
        let shown = Array(candidates.prefix(limit))
        let titles = laneTitles(shown.map { (sessionID: $0.lane.sessionID, project: $0.project) }, l10n: l10n)
        let lanes = zip(shown, titles).map { candidate, title in
            TimelineLane(
                sessionID: candidate.lane.sessionID,
                title: title,
                segments: candidate.lane.segments,
                activeTime: candidate.lane.activeTime,
                openActivity: candidate.lane.openActivity
            )
        }
        return TimelineLaneSelection(lanes: lanes, hiddenCount: max(0, candidates.count - limit))
    }

    /// Short lane titles for a narrow column: the project folder alone when no other lane shows the same one,
    /// otherwise the folder with the end of the session id ("Codometer · 3f9a1c"); "Session 3f9a1c" without a project.
    static func laneTitles(_ lanes: [(sessionID: String, project: String?)], l10n: Localizer) -> [String] {
        let folders = lanes.map { SessionLabel.folder(of: $0.project) }
        var counts: [String: Int] = [:]
        for folder in folders.compactMap(\.self) {
            counts[folder, default: 0] += 1
        }
        return zip(lanes, folders).map { lane, folder in
            guard let folder, counts[folder] == 1 else {
                return UsageFormat.sessionLabel(SessionLabel.parts(sessionID: lane.sessionID, projectFolder: lane.project), l10n: l10n)
            }
            return folder
        }
    }

    /// Whether any part of the segment (open ones up to `now`) lies inside the interval.
    static func touches(_ segment: SessionSegment, interval: DateInterval, now: Date) -> Bool {
        segment.start <= interval.end && max(segment.start, segment.end ?? now) >= interval.start
    }

    /// Seconds of the segment inside the interval; open segments run to `now`.
    static func overlap(of segment: SessionSegment, interval: DateInterval, now: Date) -> TimeInterval {
        let start = max(segment.start, interval.start)
        let end = min(segment.end ?? max(now, segment.start), interval.end)
        return max(0, end.timeIntervalSince(start))
    }

    /// The segment's visible span inside the interval, or `nil` when it lies outside.
    static func span(of segment: SessionSegment, interval: DateInterval, now: Date) -> ClosedRange<Date>? {
        guard touches(segment, interval: interval, now: now) else { return nil }
        let start = max(segment.start, interval.start)
        let end = min(max(segment.end ?? now, segment.start), interval.end)
        return start...max(start, end)
    }

    // MARK: - Ticks

    /// Tick spacings in seconds, finest first.
    static let tickSteps: [TimeInterval] = [3_600, 2 * 3_600, 3 * 3_600, 6 * 3_600, 12 * 3_600, 86_400]

    /// The finest step whose ticks stay at least `minimumSpacing` points apart across `width`.
    static func tickStep(duration: TimeInterval, width: CGFloat, minimumSpacing: CGFloat) -> TimeInterval {
        guard duration > 0, width > 0 else { return tickSteps[tickSteps.count - 1] }
        for step in tickSteps where CGFloat(step / duration) * width >= minimumSpacing {
            return step
        }
        return tickSteps[tickSteps.count - 1]
    }

    /// Ticks inside the interval on local whole hours divisible by the step (hour steps) or local midnights (day
    /// steps), ascending. Bounded, so a malformed interval never loops long.
    static func ticks(in interval: DateInterval, step: TimeInterval, calendar: Calendar = .autoupdatingCurrent) -> [Date] {
        let maximumTicks = 64
        var ticks: [Date] = []
        if step >= 86_400 {
            var day = calendar.startOfDay(for: interval.start)
            var guardCount = 0
            while day <= interval.end, ticks.count < maximumTicks, guardCount < 400 {
                if day >= interval.start { ticks.append(day) }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
                day = next
                guardCount += 1
            }
            return ticks
        }
        let stepHours = max(1, Int((step / 3_600).rounded()))
        guard var hour = calendar.dateInterval(of: .hour, for: interval.start)?.start else { return [] }
        var guardCount = 0
        while hour <= interval.end, ticks.count < maximumTicks, guardCount < 400 {
            if hour >= interval.start, calendar.component(.hour, from: hour) % stepHours == 0 {
                ticks.append(hour)
            }
            guard let next = calendar.date(byAdding: .hour, value: 1, to: hour), next > hour else { break }
            hour = next
            guardCount += 1
        }
        return ticks
    }

    /// The x positions of the reset markers to draw, ascending: resets inside the interval, keeping the newest and
    /// then each older one at least `minimumSpacing` from the last one kept, so frequent resets over a long range
    /// never pile up into one blot.
    static func resetMarkerXs(
        resets: [Date],
        interval: DateInterval,
        plot: ClosedRange<CGFloat>,
        minimumSpacing: CGFloat
    ) -> [CGFloat] {
        var kept: [CGFloat] = []
        for reset in resets.filter({ interval.contains($0) }).sorted(by: >) {
            let x = TimelineLayout.x(of: reset, plot: plot, interval: interval)
            if let last = kept.last, last - x < minimumSpacing { continue }
            kept.append(x)
        }
        return kept.reversed()
    }

    /// Where "Data since 2:20 PM" goes in the tick row when the dimmed part is too narrow for it: starting just after
    /// the coverage boundary, pulled left so it ends inside the row, never starting before the row.
    static func tickRowNoteSpan(boundaryX: CGFloat, labelWidth: CGFloat, row: ClosedRange<CGFloat>) -> ClosedRange<CGFloat> {
        let width = max(0, labelWidth)
        let start = max(row.lowerBound, min(boundaryX + 3, row.upperBound - width))
        return start...(start + width)
    }

    /// "2:00 PM" | «14:00» for hour ticks, "Mon" | «пн» for day ticks.
    static func tickLabel(_ date: Date, step: TimeInterval, l10n: Localizer) -> String {
        step >= 86_400 ? AnalyticsText.weekday(date, l10n: l10n) : AnalyticsText.clock(date, l10n: l10n)
    }

    // MARK: - Usage

    /// The usage curve's vertices over the interval, in data space: the value carried in from before the
    /// interval, straight lines between observations of one window period, and at each reset a flat run to the
    /// reset followed by a vertical drop to zero, ending flat at `now` (or the interval's end).
    static func curveVertices(series: HistorySeries?, interval: DateInterval, now: Date) -> [HistoryChartModel.Point] {
        guard let series else { return [] }
        enum Event {
            case observation(Double)
            case reset
        }
        var events: [(at: Date, order: Int, event: Event)] = []
        for (offset, point) in series.points.enumerated() where interval.contains(point.at) {
            events.append((point.at, offset, .observation(HistoryChartModel.clamp(point.used))))
        }
        // A reset sorts before any observation at the same moment.
        for reset in series.resets where interval.contains(reset) {
            events.append((reset, -1, .reset))
        }
        events.sort { lhs, rhs in lhs.at == rhs.at ? lhs.order < rhs.order : lhs.at < rhs.at }

        var vertices: [HistoryChartModel.Point] = []
        if let carried = series.points.last(where: { $0.at < interval.start }),
           !series.resets.contains(where: { $0 > carried.at && $0 <= interval.start }) {
            vertices.append(HistoryChartModel.Point(at: interval.start, used: HistoryChartModel.clamp(carried.used)))
        }
        for entry in events {
            switch entry.event {
            case .observation(let used):
                vertices.append(HistoryChartModel.Point(at: entry.at, used: used))
            case .reset:
                if let previous = vertices.last {
                    vertices.append(HistoryChartModel.Point(at: entry.at, used: previous.used))
                }
                vertices.append(HistoryChartModel.Point(at: entry.at, used: 0))
            }
        }
        let end = min(now, interval.end)
        if let last = vertices.last, end > last.at {
            vertices.append(HistoryChartModel.Point(at: end, used: last.used))
        }
        return vertices
    }

    /// The usage at `date` as a step function: the latest observation at or before it, unless a reset lies
    /// between that observation and `date`; `nil` when unknown.
    static func usage(at date: Date, in series: HistorySeries?) -> Double? {
        guard let series, let point = series.points.last(where: { $0.at <= date }) else { return nil }
        if series.resets.contains(where: { $0 > point.at && $0 <= date }) { return nil }
        return point.used
    }

    /// Sessions working or waiting at `date`; open segments run to `now`.
    static func activeSessions(at date: Date, segments: [SessionSegment], now: Date) -> Int {
        var sessions = Set<String>()
        for segment in segments where segment.start <= date {
            let end = segment.end ?? now
            if date < end || (segment.isOpen && date <= end) {
                sessions.insert(segment.sessionID)
            }
        }
        return sessions.count
    }

    /// "2:32 PM · 2 agents · 41%". The agent count is left out before the recorded coverage (unknown there),
    /// the usage when no observation covers the moment. Inside a gap nothing was collected, so the whole line
    /// reads "2:32 PM · no data (Mac was asleep)".
    static func tooltip(
        at date: Date,
        snapshot: TimelineSnapshot,
        now: Date,
        l10n: Localizer
    ) -> String {
        var parts = [AnalyticsText.moment(date, now: now, l10n: l10n)]
        if let gap = gap(at: date, in: snapshot.gaps) {
            parts.append(AnalyticsText.gapTooltip(gap.reason, l10n: l10n))
            return parts.joined(separator: " · ")
        }
        if let coverage = snapshot.coverageStart, date >= coverage {
            parts.append(AnalyticsText.agents(activeSessions(at: date, segments: snapshot.segments, now: now), l10n: l10n))
        }
        if let used = usage(at: date, in: snapshot.usage) {
            parts.append(AnalyticsText.percent(used, l10n: l10n))
        }
        return parts.joined(separator: " · ")
    }

    /// The moment under a hover location, clamped into the interval; `nil` outside the plot's x range.
    static func date(atX x: CGFloat, plot: ClosedRange<CGFloat>, interval: DateInterval) -> Date? {
        guard plot.upperBound > plot.lowerBound, plot.contains(x) else { return nil }
        let fraction = Double((x - plot.lowerBound) / (plot.upperBound - plot.lowerBound))
        return interval.start.addingTimeInterval(interval.duration * min(max(fraction, 0), 1))
    }

    /// The x of a moment inside the plot, clamped to its ends.
    static func x(of date: Date, plot: ClosedRange<CGFloat>, interval: DateInterval) -> CGFloat {
        guard interval.duration > 0 else { return plot.lowerBound }
        let fraction = date.timeIntervalSince(interval.start) / interval.duration
        return plot.lowerBound + (plot.upperBound - plot.lowerBound) * CGFloat(min(max(fraction, 0), 1))
    }

    // MARK: - Gaps

    /// Gaps thinner than this are not drawn: a hatched sliver reads as an artefact, and its label would never fit.
    static let minimumGapWidth: CGFloat = 3
    /// Below this width (before scaling) a gap is a plain band: diagonal stripes cannot show inside a few points,
    /// and two dashed edges that close together read as a drawing artefact rather than as missing time.
    static let hatchedGapWidth: CGFloat = 9
    /// Space kept between a gap's label and the gap's edges.
    static let gapLabelInset: CGFloat = 5

    /// The gaps the canvas draws, clipped to the interval and the plot and ordered by position; gaps at most
    /// `minimumWidth` wide are left out.
    static func gapSpans(
        _ gaps: [CollectionGap],
        interval: DateInterval,
        plot: ClosedRange<CGFloat>,
        minimumWidth: CGFloat = minimumGapWidth
    ) -> [TimelineGapSpan] {
        gaps.compactMap { gap -> TimelineGapSpan? in
            let start = max(gap.interval.start, interval.start)
            let end = min(gap.interval.end, interval.end)
            guard end > start else { return nil }
            let minX = x(of: start, plot: plot, interval: interval)
            let maxX = x(of: end, plot: plot, interval: interval)
            guard maxX - minX > minimumWidth else { return nil }
            return TimelineGapSpan(x: minX...maxX, interval: DateInterval(start: start, end: end), reason: gap.reason)
        }
        .sorted { $0.x.lowerBound < $1.x.lowerBound }
    }

    /// The usage curve split into the runs that were recorded: vertices inside a gap are dropped, and a new run
    /// starts wherever a gap lies between two of them. The value before and after a gap is real; what happened
    /// between them is unknown, which is why the runs are drawn apart.
    static func curveRuns(vertices: [HistoryChartModel.Point], gaps: [DateInterval]) -> [[HistoryChartModel.Point]] {
        guard !gaps.isEmpty else { return vertices.isEmpty ? [] : [vertices] }
        var runs: [[HistoryChartModel.Point]] = []
        var current: [HistoryChartModel.Point] = []
        for vertex in vertices {
            guard !gaps.contains(where: { $0.start < vertex.at && vertex.at < $0.end }) else { continue }
            if let last = current.last, gaps.contains(where: { $0.start < vertex.at && $0.end > last.at }) {
                runs.append(current)
                current = []
            }
            current.append(vertex)
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }

    /// `range` without the gap spans: the parts of a lane track or capsule that are drawn. Empty when the gaps
    /// cover all of it.
    static func visibleRanges(_ range: ClosedRange<CGFloat>, without gaps: [TimelineGapSpan]) -> [ClosedRange<CGFloat>] {
        var result: [ClosedRange<CGFloat>] = []
        var start = range.lowerBound
        for gap in gaps.sorted(by: { $0.x.lowerBound < $1.x.lowerBound }) {
            let gapStart = max(gap.x.lowerBound, range.lowerBound)
            let gapEnd = min(gap.x.upperBound, range.upperBound)
            guard gapEnd > gapStart else { continue }
            if gapStart > start { result.append(start...gapStart) }
            start = max(start, gapEnd)
        }
        if start < range.upperBound { result.append(start...range.upperBound) }
        return result
    }

    /// Where a centred message fits without touching a gap: the middle of the widest free stretch that holds
    /// `width`; `nil` when no stretch does.
    static func messageCenter(in area: ClosedRange<CGFloat>, avoiding gaps: [TimelineGapSpan], width: CGFloat) -> CGFloat? {
        let widest = visibleRanges(area, without: gaps)
            .max { ($0.upperBound - $0.lowerBound) < ($1.upperBound - $1.lowerBound) }
        guard let widest, widest.upperBound - widest.lowerBound >= width else { return nil }
        return (widest.lowerBound + widest.upperBound) / 2
    }

    /// The label a gap `width` points wide shows: the full phrase when it fits with `inset` on both sides, else
    /// the short form, else nothing. `measure` returns a phrase's drawn width.
    static func gapLabel(
        _ reason: CollectionGap.Reason,
        width: CGFloat,
        inset: CGFloat = gapLabelInset,
        l10n: Localizer,
        measure: (String) -> CGFloat
    ) -> String? {
        let available = width - 2 * inset
        guard available > 0 else { return nil }
        let full = AnalyticsText.gapLabel(reason, l10n: l10n)
        if measure(full) <= available { return full }
        let short = AnalyticsText.gapShortLabel(reason, l10n: l10n)
        return measure(short) <= available ? short : nil
    }

    /// The gap a moment falls into, if any.
    static func gap(at date: Date, in gaps: [CollectionGap]) -> CollectionGap? {
        gaps.first { $0.interval.contains(date) }
    }

    // MARK: - Summary

    /// Whether the view shows its placeholder instead of the timeline.
    static func showsPlaceholder(_ snapshot: TimelineSnapshot?) -> Bool {
        snapshot == nil
    }

    /// The VoiceOver summary: "Timeline: 3 sessions, working for 2 hours 10 minutes, waiting for 12 minutes, 41% of the
    /// limit used, 2 gaps in the data". The gap count comes last, and only when the period has gaps.
    static func accessibilitySummary(snapshot: TimelineSnapshot?, now: Date, l10n: Localizer) -> String {
        let text = l10n.analytics
        guard let snapshot else { return text.timelineNoDataA11y }
        let selection = lanes(segments: snapshot.segments, interval: snapshot.interval, now: now, maximum: .max, l10n: l10n)
        var working: TimeInterval = 0
        var waiting: TimeInterval = 0
        for segment in snapshot.segments {
            let seconds = overlap(of: segment, interval: snapshot.interval, now: now)
            if segment.activity == .waiting { waiting += seconds } else { working += seconds }
        }
        var parts = [sessions(selection.lanes.count, l10n: l10n)]
        if working > 0 { parts.append(text.workingA11y(l10n.format.durationSpoken(working))) }
        if waiting > 0 { parts.append(text.waitingA11y(l10n.format.durationSpoken(waiting))) }
        if let used = snapshot.usage?.points.last?.used {
            parts.append(text.limitUsedA11y(AnalyticsText.percent(used, l10n: l10n)))
        }
        if !snapshot.gaps.isEmpty {
            parts.append(text.gapsA11y(snapshot.gaps.count))
        }
        return text.timelineA11y(parts.joined(separator: ", "))
    }

    /// "no sessions", "1 session", "3 sessions" | «нет сессий», «1 сессия», «3 сессии», «5 сессий».
    static func sessions(_ count: Int, l10n: Localizer) -> String {
        l10n.analytics.sessions(count)
    }
}
