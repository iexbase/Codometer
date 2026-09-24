import CodometerCore
import CodometerL10n
import SwiftUI

/// The Timeline page: session lanes under the usage curve and who used the limit, over a chosen range.
///
/// Its height never depends on the data (the timeline and the list have fixed ideal heights), and the deck lays it
/// out with every other page, so switching to it never resizes the deck. The deck makes every page as tall as the
/// tallest one (Overview), and `TimelinePageLayout` shares that extra height between the timeline and the list
/// instead of leaving it empty. It loads only while it is the page shown in a deck the user sees (`isDeckVisible`);
/// hidden measurement copies never load.
struct DeckTimelinePage: View {
    let presentation: AccountPresentation
    let store: TrackerStore
    let isSelected: Bool
    let metrics: IslandMetrics

    @Environment(\.isDeckVisible) private var isDeckVisible
    @Environment(\.l10n) private var l10n
    @State private var range: AnalyticsRange = .fiveHours

    var body: some View {
        let timeline = store.analytics.timeline(account: presentation.id, range: range)
        let attribution = store.analytics.attribution(account: presentation.id, range: range, grouping: .project)
        TimelinePageLayout(spacing: 10 * metrics.scale) {
            HStack(spacing: 8 * metrics.scale) {
                Text(presentation.status.profile.label.value)
                    .font(metrics.font(TextSize.headline, .semibold))
                    .lineLimit(1)
                Spacer(minLength: 6 * metrics.scale)
                CapsuleSegmentedControl(
                    options: AnalyticsRange.allCases.map { (id: $0, title: $0.title(l10n: l10n)) },
                    selection: range,
                    metrics: metrics
                ) { range = $0 }
            }
            SessionTimelineView(snapshot: timeline, now: store.now, metrics: metrics)
            // The list draws its own "What’s eating your limit" header with the coverage note.
            AttributionListView(report: attribution, metrics: metrics)
        }
        .environment(\.analyticsStyle, AnalyticsStyle(provider: presentation.provider, bands: store.settings.appearance.bands))
        .onAppear(perform: request)
        .onChange(of: RequestKey(visible: isDeckVisible, selected: isSelected, range: range, capturedAt: presentation.status.reading?.capturedAt)) { _, _ in
            request()
        }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: DebugDeckCommands.showRange)) { notification in
            guard let name = DebugDeckCommands.value(of: notification), let requested = AnalyticsRange(rawValue: name) else { return }
            range = requested
        }
        #endif
    }

    private struct RequestKey: Equatable {
        let visible: Bool
        let selected: Bool
        let range: AnalyticsRange
        let capturedAt: Date?
    }

    private func request() {
        guard isDeckVisible, isSelected else { return }
        store.analytics.requestTimeline(account: presentation.id, range: range)
        store.analytics.requestAttribution(account: presentation.id, range: range, grouping: .project)
    }
}

/// Stacks the page's header, timeline and attribution list.
///
/// Measured without a height — how the deck's page stack sizes pages — it is exactly as tall as their ideal heights
/// together. Placed taller, it keeps the header's ideal height and shares the extra between the timeline
/// (`timelineShare`) and the list, so the page fills its slot the same way whatever the data.
struct TimelinePageLayout: Layout {
    let spacing: CGFloat

    /// Part of the extra height the timeline gets; the list gets the rest.
    static let timelineShare: CGFloat = 0.6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ideal = subviews.map { $0.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)).height }
        let idealHeight = ideal.reduce(0, +) + spacing * CGFloat(max(0, subviews.count - 1))
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        guard let proposed = proposal.height, proposed.isFinite else {
            return CGSize(width: width, height: idealHeight)
        }
        return CGSize(width: width, height: max(idealHeight, proposed))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let ideal = subviews.map { $0.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height }
        var y = bounds.minY
        for (subview, height) in zip(subviews, Self.heights(ideal: ideal, spacing: spacing, available: bounds.height)) {
            subview.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: height))
            y += height + spacing
        }
    }

    /// Ideal heights, with any height beyond them split between the second-to-last view (the timeline,
    /// `timelineShare`) and the last one (the list). Fewer than two views keep their ideal heights.
    static func heights(ideal: [CGFloat], spacing: CGFloat, available: CGFloat) -> [CGFloat] {
        guard ideal.count >= 2, available.isFinite else { return ideal }
        let total = ideal.reduce(0, +) + spacing * CGFloat(ideal.count - 1)
        let extra = max(0, available - total)
        var heights = ideal
        let timelineExtra = (extra * timelineShare).rounded(.down)
        heights[heights.count - 2] += timelineExtra
        heights[heights.count - 1] += extra - timelineExtra
        return heights
    }
}
