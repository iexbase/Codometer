import CodometerCore
import CodometerL10n
@testable import CodometerUI
import AppKit
import Foundation
import SwiftUI
import Testing

/// Stretches the app did not record: which of them the timeline draws, how they split the curve and the lane
/// tracks, and what they say in English and Russian.
@Suite("Timeline gaps layout")
struct TimelineGapsLayoutTests {
    private typealias Fixture = AnalyticsFixture
    private let now = AnalyticsFixture.now
    /// A day-long timeline, 240 pt wide: ten points per hour.
    private let day = DateInterval(start: AnalyticsFixture.now.addingTimeInterval(-AnalyticsFixture.hours(24)), end: AnalyticsFixture.now)
    private let plot: ClosedRange<CGFloat> = 100...340

    /// A gap between two moments given in hours before `now`.
    private func gap(_ from: Double, _ to: Double, _ reason: CollectionGap.Reason = .appNotRunning) -> CollectionGap {
        CollectionGap(
            interval: DateInterval(start: now.addingTimeInterval(Fixture.hours(from)), end: now.addingTimeInterval(Fixture.hours(to))),
            reason: reason
        )
    }

    private func at(_ hours: Double) -> Date { now.addingTimeInterval(Fixture.hours(hours)) }

    // MARK: - Spans

    @Test("Only gaps wider than three points are drawn, clipped to the interval and ordered by position")
    func spans() {
        let spans = TimelineLayout.gapSpans(
            [
                gap(-10, -8, .macAsleep),
                gap(-26, -23),
                gap(-4, -3.8),
                gap(-30, -28),
                gap(-2, 3, .accountOff),
            ],
            interval: day,
            plot: plot
        )
        #expect(spans.map(\.x) == [100...110, 240...260, 320...340])
        #expect(spans.map(\.reason) == [.appNotRunning, .macAsleep, .accountOff])
        // Clipped to the interval on both ends, so nothing is drawn outside the plot.
        #expect(spans.first?.interval == DateInterval(start: day.start, end: at(-23)))
        #expect(spans.last?.interval == DateInterval(start: at(-2), end: day.end))
        // A twelve-minute gap is two points wide at this width: hatching it would only look like an artefact.
        #expect(spans.allSatisfy { $0.width > TimelineLayout.minimumGapWidth })
        #expect(TimelineLayout.gapSpans([], interval: day, plot: plot).isEmpty)
        // A degenerate plot never produces a span.
        #expect(TimelineLayout.gapSpans([gap(-10, -8)], interval: day, plot: 100...100).isEmpty)
    }

    // MARK: - Curve

    @Test("The curve splits into runs at the gaps, dropping vertices inside them")
    func curveRuns() {
        let vertices = [-24.0, -20, -15, -10, -5, 0].map { HistoryChartModel.Point(at: at($0), used: 40) }
        let runs = TimelineLayout.curveRuns(vertices: vertices, gaps: [gap(-18, -12).interval])
        #expect(runs.map { $0.map(\.at) } == [[at(-24), at(-20)], [at(-10), at(-5), at(0)]])

        // Two gaps make three runs; a vertex exactly on a gap's edge belongs to the run beside it.
        let three = TimelineLayout.curveRuns(vertices: vertices, gaps: [gap(-22, -19).interval, gap(-8, -6).interval])
        #expect(three.map { $0.map(\.at) } == [[at(-24)], [at(-15), at(-10)], [at(-5), at(0)]])

        #expect(TimelineLayout.curveRuns(vertices: vertices, gaps: []).count == 1)
        #expect(TimelineLayout.curveRuns(vertices: [], gaps: [gap(-18, -12).interval]).isEmpty)
        // Everything inside one gap: nothing is drawn rather than a line across unknown time.
        #expect(TimelineLayout.curveRuns(vertices: vertices, gaps: [gap(-25, 1).interval]).isEmpty)
    }

    @Test("A gap between two neighbouring vertices splits them even with nothing recorded inside it")
    func curveRunsWithoutInnerVertices() {
        let vertices = [-24.0, -1].map { HistoryChartModel.Point(at: at($0), used: 62) }
        #expect(TimelineLayout.curveRuns(vertices: vertices, gaps: [gap(-20, -2).interval]).count == 2)
        // A gap that lies entirely outside the pair leaves them in one run.
        #expect(TimelineLayout.curveRuns(vertices: vertices, gaps: [gap(-40, -30).interval]).count == 1)
        // Two vertices at the same moment (the vertical drop at a reset) never split.
        let drop = [HistoryChartModel.Point(at: at(-5), used: 90), HistoryChartModel.Point(at: at(-5), used: 0)]
        #expect(TimelineLayout.curveRuns(vertices: drop, gaps: [gap(-6, -4).interval]).isEmpty)
    }

    // MARK: - Lanes and messages

    @Test("Lane tracks and capsules are drawn only outside the gaps")
    func visibleRanges() {
        let spans = TimelineLayout.gapSpans([gap(-20, -18), gap(-10, -8)], interval: day, plot: plot)
        #expect(TimelineLayout.visibleRanges(plot, without: spans) == [100...140, 160...240, 260...340])
        // A capsule that runs into a gap keeps only its recorded part.
        #expect(TimelineLayout.visibleRanges(130...170, without: spans) == [130...140, 160...170])
        #expect(TimelineLayout.visibleRanges(145...155, without: spans).isEmpty)
        #expect(TimelineLayout.visibleRanges(plot, without: []) == [plot])
        // Overlapping spans merge into one hole.
        let overlapping = TimelineLayout.gapSpans([gap(-20, -16), gap(-18, -14)], interval: day, plot: plot)
        #expect(TimelineLayout.visibleRanges(plot, without: overlapping) == [100...140, 200...340])
    }

    @Test("“No sessions in this period” takes the widest stretch that is not a gap")
    func messageCenter() {
        let spans = TimelineLayout.gapSpans([gap(-22, -14)], interval: day, plot: plot)
        // The free stretches are 100…120 and 200…340; the message goes into the wider one.
        #expect(TimelineLayout.messageCenter(in: plot, avoiding: spans, width: 80) == 270)
        #expect(TimelineLayout.messageCenter(in: plot, avoiding: spans, width: 200) == nil)
        // Without gaps it stays in the middle, exactly as before.
        #expect(TimelineLayout.messageCenter(in: plot, avoiding: [], width: 80) == 220)
        #expect(TimelineLayout.messageCenter(in: plot, avoiding: [], width: 400) == nil)
    }

    // MARK: - Labels

    @Test("A gap shows its full phrase, then the short one, then nothing")
    func labelTiers() {
        // A measure of one point per character, so the tiers are readable in the numbers.
        let measure: (String) -> CGFloat = { CGFloat($0.count) }
        let en = Localizer.testEnglish
        #expect(TimelineLayout.gapLabel(.macAsleep, width: 30, inset: 2, l10n: en, measure: measure) == "Mac was asleep")
        #expect(TimelineLayout.gapLabel(.macAsleep, width: 14, inset: 2, l10n: en, measure: measure) == "Asleep")
        #expect(TimelineLayout.gapLabel(.macAsleep, width: 8, inset: 2, l10n: en, measure: measure) == nil)
        #expect(TimelineLayout.gapLabel(.macAsleep, width: 0, inset: 2, l10n: en, measure: measure) == nil)
        // An unknown gap has no shorter form; "No data" is already the short one.
        #expect(TimelineLayout.gapLabel(.unknown, width: 12, inset: 2, l10n: en, measure: measure) == "No data")
        #expect(TimelineLayout.gapLabel(.unknown, width: 8, inset: 2, l10n: en, measure: measure) == nil)
    }

    @MainActor
    @Test(
        "Gap labels fit the gaps they promise to name, in both languages",
        arguments: [0.85, 1.0, 1.25], [Localizer.testEnglish, .testRussian]
    )
    func labelFit(scale: Double, l10n: Localizer) {
        let metrics = IslandMetrics(scale: scale)
        let frame = TimelineFrame(
            size: CGSize(width: metrics.deckWidth - 2 * metrics.deckPadding, height: SessionTimelineView.height(for: metrics)),
            metrics: metrics
        )
        let width = frame.plotX.upperBound - frame.plotX.lowerBound
        let size = metrics.textSize(10.5)
        let measure: (String) -> CGFloat = { TextFit.width($0, size: size, weight: .medium, monospacedDigits: false) }
        for reason in CollectionGap.Reason.allCases {
            let full = AnalyticsText.gapLabel(reason, l10n: l10n)
            // Four fifths of the period: the full phrase fits, whatever the language.
            #expect(TimelineLayout.gapLabel(reason, width: width * 0.8, l10n: l10n, measure: measure) == full, "\(full)")
            // Two fifths: at least the short form is named.
            let short = TimelineLayout.gapLabel(reason, width: width * 0.4, l10n: l10n, measure: measure)
            #expect(short != nil, "\(AnalyticsText.gapShortLabel(reason, l10n: l10n))")
            // The narrowest drawn gap stays unlabelled; the tooltip and the summary say what it is.
            #expect(TimelineLayout.gapLabel(reason, width: TimelineLayout.minimumGapWidth, l10n: l10n, measure: measure) == nil)
        }
    }

    // MARK: - Phrases

    @Test("Gap phrases in both languages")
    func phrases() {
        let en = Localizer.testEnglish
        let ru = Localizer.testRussian
        #expect(AnalyticsText.gapLabel(.appNotRunning, l10n: en) == "Codometer wasn\u{2019}t running")
        #expect(AnalyticsText.gapLabel(.macAsleep, l10n: en) == "Mac was asleep")
        #expect(AnalyticsText.gapLabel(.accountOff, l10n: en) == "Account was off")
        #expect(AnalyticsText.gapLabel(.unknown, l10n: en) == "No data")
        #expect(AnalyticsText.gapLabel(.appNotRunning, l10n: ru) == "Codometer не был запущен")
        #expect(AnalyticsText.gapLabel(.macAsleep, l10n: ru) == "Mac спал")
        #expect(AnalyticsText.gapLabel(.accountOff, l10n: ru) == "аккаунт был выключен")
        #expect(AnalyticsText.gapLabel(.unknown, l10n: ru) == "нет данных")
        #expect(AnalyticsText.gapShortLabel(.appNotRunning, l10n: en) == "Not running")
        #expect(AnalyticsText.gapShortLabel(.macAsleep, l10n: ru) == "спал")
        // Every short form is shorter than its full phrase in both languages.
        for reason in CollectionGap.Reason.allCases where reason != .unknown {
            for l10n in [en, ru] {
                #expect(AnalyticsText.gapShortLabel(reason, l10n: l10n).count < AnalyticsText.gapLabel(reason, l10n: l10n).count)
            }
        }
    }

    // MARK: - Tooltip and VoiceOver

    @Test("The tooltip inside a gap says that nothing was recorded, and why")
    func tooltip() throws {
        let snapshot = TimelineSnapshot(
            accountID: Fixture.account,
            interval: day,
            segments: [try Fixture.segment("a", .working, from: Fixture.hours(-3), to: Fixture.hours(-1))],
            usage: try Fixture.series([(Fixture.hours(-20), 12), (Fixture.hours(-2), 62)]),
            coverageStart: day.start,
            gaps: [gap(-10, -8, .macAsleep), gap(-18, -16), gap(-6, -5, .accountOff), gap(-4, -3.5, .unknown)]
        )
        #expect(TimelineLayout.tooltip(at: at(-9), snapshot: snapshot, now: now, l10n: .testEnglish) == "5:32\u{202F}AM · no data (Mac was asleep)")
        #expect(TimelineLayout.tooltip(at: at(-9), snapshot: snapshot, now: now, l10n: .testRussian) == "5:32 · нет данных (Mac спал)")
        #expect(TimelineLayout.tooltip(at: at(-17), snapshot: snapshot, now: now, l10n: .testEnglish) == "Wed 9:32\u{202F}PM · no data (Codometer wasn\u{2019}t running)")
        #expect(TimelineLayout.tooltip(at: at(-5.5), snapshot: snapshot, now: now, l10n: .testRussian) == "9:02 · нет данных (аккаунт был выключен)")
        // An unknown gap only says that nothing was recorded; naming the reason would repeat the phrase.
        #expect(TimelineLayout.tooltip(at: at(-3.7), snapshot: snapshot, now: now, l10n: .testEnglish) == "10:50\u{202F}AM · no data")
        #expect(TimelineLayout.tooltip(at: at(-3.7), snapshot: snapshot, now: now, l10n: .testRussian) == "10:50 · нет данных")
        // Outside the gaps the tooltip is unchanged.
        #expect(TimelineLayout.tooltip(at: at(-2), snapshot: snapshot, now: now, l10n: .testEnglish) == "12:32\u{202F}PM · 1 agent · 62%")
        #expect(TimelineLayout.gap(at: at(-9), in: snapshot.gaps)?.reason == .macAsleep)
        #expect(TimelineLayout.gap(at: at(-12), in: snapshot.gaps) == nil)
    }

    @Test("The VoiceOver summary counts the gaps, declined in Russian")
    func summary() throws {
        func snapshot(gaps: Int) -> TimelineSnapshot {
            TimelineSnapshot(
                accountID: Fixture.account,
                interval: day,
                segments: [],
                usage: nil,
                coverageStart: day.start,
                gaps: (0..<gaps).map { index -> CollectionGap in
                    let start = -20.0 + Double(index) * 2
                    return gap(start, start + 1, .macAsleep)
                }
            )
        }
        #expect(
            TimelineLayout.accessibilitySummary(snapshot: snapshot(gaps: 1), now: now, l10n: .testEnglish)
                == "Timeline: no sessions, 1 gap in the data"
        )
        #expect(
            TimelineLayout.accessibilitySummary(snapshot: snapshot(gaps: 2), now: now, l10n: .testEnglish)
                == "Timeline: no sessions, 2 gaps in the data"
        )
        #expect(
            TimelineLayout.accessibilitySummary(snapshot: snapshot(gaps: 1), now: now, l10n: .testRussian)
                == "Хронология: нет сессий, 1 пропуск в данных"
        )
        #expect(
            TimelineLayout.accessibilitySummary(snapshot: snapshot(gaps: 2), now: now, l10n: .testRussian)
                == "Хронология: нет сессий, 2 пропуска в данных"
        )
        #expect(
            TimelineLayout.accessibilitySummary(snapshot: snapshot(gaps: 5), now: now, l10n: .testRussian)
                == "Хронология: нет сессий, 5 пропусков в данных"
        )
        // Without gaps the summary is exactly what it was.
        #expect(
            TimelineLayout.accessibilitySummary(snapshot: snapshot(gaps: 0), now: now, l10n: .testEnglish)
                == "Timeline: no sessions"
        )
        for count in [1, 3, 11, 21, 22, 101] {
            #expect(Localizer.testRussian.analytics.gapsA11y(count).hasPrefix("\(count) "))
        }
        #expect(Localizer.testRussian.analytics.gapsA11y(21) == "21 пропуск в данных")
        #expect(Localizer.testRussian.analytics.gapsA11y(14) == "14 пропусков в данных")
    }

}

// MARK: - Renders

/// The timeline with gaps, rendered for visual review in English and Russian (`…-en.png`, `…-ru.png`). Runs only
/// when `CODOMETER_ANALYTICS_SNAPSHOT_DIR` or `CODOMETER_SNAPSHOT_DIR` is set; with the latter the files land in
/// its `analytics` folder.
@MainActor
@Suite(
    "Timeline gap snapshots",
    .enabled(if: ProcessInfo.processInfo.environment["CODOMETER_ANALYTICS_SNAPSHOT_DIR"] != nil
        || ProcessInfo.processInfo.environment["CODOMETER_SNAPSHOT_DIR"] != nil)
)
struct TimelineGapSnapshotTests {
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

    @Test("Timelines with gaps in light and dark appearance, in both languages", arguments: [Localizer.testEnglish, .testRussian])
    func renderGaps(l10n: Localizer) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for scheme in [ColorScheme.light, .dark] {
            try render(
                try timelines(),
                name: "timeline-gaps-\(scheme == .dark ? "dark" : "light")-\(l10n.language.rawValue)",
                scheme: scheme,
                l10n: l10n
            )
        }
        try render(
            try timelines(metrics: IslandMetrics(scale: 0.85)),
            name: "timeline-gaps-scale-085-light-\(l10n.language.rawValue)",
            scheme: .light,
            l10n: l10n,
            metrics: IslandMetrics(scale: 0.85)
        )
    }

    /// The acceptance cases: a day with a two-hour sleep gap and a quit gap, a hover inside the sleep gap, a
    /// five-hour period whose gap is wide enough for the full phrase, and a period that is almost all gap.
    private func timelines(metrics: IslandMetrics = IslandMetrics(scale: 1)) throws -> some View {
        let day = DateInterval(start: now.addingTimeInterval(-Fixture.hours(24)), end: now)
        let segments: [SessionSegment] = try [
            Fixture.segment("codometer-1", .working, from: -Fixture.hours(22), to: -Fixture.hours(20.5), title: "codometer"),
            Fixture.segment("codometer-1", .working, from: -Fixture.hours(13), to: -Fixture.hours(11.4), title: "codometer"),
            Fixture.segment("codometer-1", .waiting, from: -Fixture.hours(11.4), to: -Fixture.hours(11), title: "codometer"),
            Fixture.segment("api-2", .working, from: -Fixture.hours(12.5), to: -Fixture.hours(10.2), title: "exchanger-api"),
            Fixture.segment("api-2", .working, from: -Fixture.hours(3.4), to: -Fixture.hours(1.2), title: "exchanger-api"),
            Fixture.segment("docs-3", .working, from: -Fixture.hours(2.4), to: -Fixture.minutes(20), title: "docs"),
            Fixture.segment("web-4", .waiting, from: -Fixture.minutes(18), to: nil, title: "landing-web"),
        ]
        // The app was quit from 19 h to 14 h before now, and the Mac slept from 9 h to 7 h.
        let quit = CollectionGap(
            interval: DateInterval(start: now.addingTimeInterval(-Fixture.hours(19)), end: now.addingTimeInterval(-Fixture.hours(14))),
            reason: .appNotRunning
        )
        let asleep = CollectionGap(
            interval: DateInterval(start: now.addingTimeInterval(-Fixture.hours(9)), end: now.addingTimeInterval(-Fixture.hours(7))),
            reason: .macAsleep
        )
        var values: [(TimeInterval, Double)] = []
        let resets: [TimeInterval] = [-Fixture.hours(20), -Fixture.hours(10), -Fixture.hours(5)]
        for offset in stride(from: -Fixture.hours(24), through: -Fixture.minutes(3), by: 600) {
            let moment = now.addingTimeInterval(offset)
            if quit.interval.contains(moment) || asleep.interval.contains(moment) { continue }
            let since = resets.last { $0 <= offset } ?? -Fixture.hours(24)
            let busy = segments.contains { $0.start <= moment && moment < ($0.end ?? now) }
            let previous = values.last { $0.0 >= since }?.1 ?? 0
            values.append((offset, min(100, previous + (busy ? 4.4 : 0.2))))
        }
        let dayShot = TimelineSnapshot(
            accountID: Fixture.account,
            interval: day,
            segments: segments,
            usage: try Fixture.series(values, resets: resets),
            coverageStart: day.start,
            gaps: [quit, asleep]
        )
        var hovered = SessionTimelineView(snapshot: dayShot, now: now, metrics: metrics)
        // The middle of the sleep gap at this width, so the tooltip reads "… · no data (Mac was asleep)".
        let frame = TimelineFrame(
            size: CGSize(width: metrics.deckWidth - 2 * metrics.deckPadding, height: SessionTimelineView.height(for: metrics)),
            metrics: metrics
        )
        hovered.previewHoverX = TimelineLayout.x(of: now.addingTimeInterval(-Fixture.hours(8)), plot: frame.plotX, interval: day)

        let fiveHours = DateInterval(start: now.addingTimeInterval(-Fixture.hours(5)), end: now)
        let evening = TimelineSnapshot(
            accountID: Fixture.account,
            interval: fiveHours,
            segments: segments.filter { $0.start >= fiveHours.start },
            usage: try Fixture.series(values.filter { $0.0 >= -Fixture.hours(5) }, resets: [-Fixture.hours(5)]),
            coverageStart: fiveHours.start,
            gaps: [CollectionGap(
                interval: DateInterval(start: now.addingTimeInterval(-Fixture.hours(4.6)), end: now.addingTimeInterval(-Fixture.hours(1.2))),
                reason: .appNotRunning
            )]
        )
        let off = TimelineSnapshot(
            accountID: Fixture.account,
            interval: fiveHours,
            segments: [],
            usage: nil,
            coverageStart: fiveHours.start,
            gaps: [CollectionGap(
                interval: DateInterval(start: fiveHours.start, end: now.addingTimeInterval(-Fixture.minutes(24))),
                reason: .accountOff
            )]
        )
        // Over a week the same two-hour sleep is about four points wide: a plain band, not a hatched one.
        let week = DateInterval(start: now.addingTimeInterval(-Fixture.hours(24 * 7)), end: now)
        let weekShot = TimelineSnapshot(
            accountID: Fixture.account,
            interval: week,
            segments: segments,
            usage: try Fixture.series(values, resets: resets),
            coverageStart: week.start,
            gaps: [quit, asleep]
        )

        return VStack(alignment: .leading, spacing: 18) {
            caption("24h · quit 19:32–00:32, asleep 05:32–07:32")
            SessionTimelineView(snapshot: dayShot, now: now, metrics: metrics)
            caption("Hover inside the sleep gap")
            hovered
            caption("7d · the same two gaps, a few points wide")
            SessionTimelineView(snapshot: weekShot, now: now, metrics: metrics)
            caption("5h · not running for 3h 24m")
            SessionTimelineView(snapshot: evening, now: now, metrics: metrics)
            caption("5h · account off almost all period, no sessions")
            SessionTimelineView(snapshot: off, now: now, metrics: metrics)
        }
        .environment(\.analyticsStyle, AnalyticsStyle(provider: .claude))
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
        let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }
}
