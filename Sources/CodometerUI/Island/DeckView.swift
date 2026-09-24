import CodometerCore
import CodometerL10n
import SwiftUI

enum DeckContext {
    case island
    case popover
}

/// Expanded content: header, "Waiting for you", a dial per account and the selected account's page.
///
/// The layout never depends on interaction: every account's page (and every page kind) is laid out in one
/// stack and only the selected one is shown, time-dependent texts reserve their size, and the group filter
/// only changes which dials are listed. A group without accounts keeps that room invisible under an empty state
/// (`DeckSections`). So switching accounts, pages or filters never resizes the island.
struct DeckContent: View {
    let store: TrackerStore
    let model: IslandModel
    let accounts: [AccountPresentation]
    let context: DeckContext
    /// The tallest the deck may be, e.g. the screen's visible height. When the content is taller, the part
    /// below the header scrolls. `.infinity` never scrolls.
    let maxHeight: CGFloat

    @State private var hoveredAccountID: AccountID?
    /// Hover follows the pointer only once it has moved since the deck appeared: a deck that opens under a still
    /// pointer must not switch accounts (or light a dial) by itself right after it has settled.
    @State private var hoverTracking = DialHoverTracking()
    @State private var page: DeckPage = .overview
    /// Whether the capped body is actually taller than its room. Until it is, the scroller stays hidden, so a deck
    /// that fits (e.g. the popover, which always passes a finite cap) never flashes a scroll bar as it appears.
    @State private var bodyOverflows = false
    @Environment(\.liveEffectsEnabled) private var liveEffectsEnabled
    @Environment(\.l10n) private var l10n

    init(
        store: TrackerStore,
        model: IslandModel,
        accounts: [AccountPresentation],
        context: DeckContext,
        maxHeight: CGFloat = .infinity
    ) {
        self.store = store
        self.model = model
        self.accounts = accounts
        self.context = context
        self.maxHeight = maxHeight
    }

    private var metrics: IslandMetrics { model.layout.metrics }

    /// The pages this deck offers under the current detail setting.
    private var availablePages: [DeckPage] { DeckLayout.availablePages(detail: store.settings.appearance.deckDetail) }

    /// The selected page, falling back to the overview when the detail setting has taken the selected one away.
    private var shownPage: DeckPage { availablePages.contains(page) ? page : .overview }

    var body: some View {
        let insets = context == .island ? model.layout.deckInsets : EdgeInsets()
        let chrome = metrics.deckVerticalPadding * 2 + insets.top + insets.bottom
        let shown = DeckLayout.filtered(accounts, filter: store.settings.appearance.railGroupFilter, groups: store.settings.groups)
        let queue = store.attentionQueue
        let sections = sections(shown: shown, attentionCount: queue.count)
        DeckStackLayout(spacing: metrics.sectionSpacing, maxHeight: max(0, maxHeight - chrome)) {
            DeckHeader(
                store: store,
                accounts: accounts,
                context: context,
                metrics: metrics,
                subtitle: sections.emptyState?.headerSubtitle(l10n: l10n),
                showsGroupFilter: sections.groupFilter.isShown
            )
            if maxHeight.isFinite {
                ScrollView(.vertical) {
                    deckBody(shown: shown, queue: queue, sections: sections)
                }
                .scrollBounceBehavior(.basedOnSize)
                // An empty state has nothing to scroll to: no scroller beside it, even when the kept room overflows.
                .scrollIndicators(bodyOverflows && sections.emptyState == nil ? .automatic : .never)
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentSize.height > geometry.containerSize.height + 0.5
                } action: { _, overflows in
                    if bodyOverflows != overflows {
                        bodyOverflows = overflows
                    }
                }
            } else {
                deckBody(shown: shown, queue: queue, sections: sections)
            }
        }
        .padding(.horizontal, metrics.deckPadding)
        .padding(.vertical, metrics.deckVerticalPadding)
        .frame(width: metrics.deckWidth, alignment: .leading)
        .padding(insets)
        // Only a deck the user is actually looking at celebrates; measurement copies, a prewarmed deck and static
        // renders get no stage at all. The menu bar popover reuses this view, so it celebrates through the same line.
        .environment(\.ceremonyStage, ceremonyStage)
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: DebugDeckCommands.showPage)) { notification in
            guard let name = DebugDeckCommands.value(of: notification), let requested = DeckPage(rawValue: name),
                  availablePages.contains(requested) else { return }
            page = requested
        }
        #endif
    }

    // MARK: Reset ceremonies

    /// The stage this deck's dials celebrate resets on, or `nil` when they must not.
    private var ceremonyStage: CeremonyStage? {
        Self.ceremonyStage(
            store: store,
            context: context,
            isExpanded: model.isExpanded,
            liveEffects: liveEffectsEnabled
        )
    }

    /// Whether a deck celebrates, and on which board.
    ///
    /// A ceremony runs once per surface and then expires, so it must never be spent where nobody can see it. That
    /// rules out three decks: the hidden copies the island measures and the still settings renders (both without live
    /// effects), and the island's *prewarmed* deck, which is built invisible while the pointer's open intent runs and
    /// is thrown away again when the user moves on — hence `isExpanded`. A popover's deck exists only while the
    /// popover is on screen, so it celebrates as soon as it is built.
    ///
    /// The surface is `.deck` for both hosts: the island's deck and the menu bar popover show the same dials, and
    /// `DeckDial` reports `.deck` to the ring gauge.
    static func ceremonyStage(
        store: TrackerStore,
        context: DeckContext,
        isExpanded: Bool,
        liveEffects: Bool
    ) -> CeremonyStage? {
        guard liveEffects, store.settings.appearance.celebratesResets else { return nil }
        guard context == .popover || isExpanded else { return nil }
        return CeremonyStage(surface: .deck, board: store.ceremonies, now: store.now) { [store] id, surface in
            store.markCeremonyPlayed(id, on: surface)
        }
    }

    private func sections(shown: [AccountPresentation], attentionCount: Int) -> DeckSections {
        DeckSections.make(
            accountCount: accounts.count,
            shownCount: shown.count,
            settings: store.settings,
            attentionCount: attentionCount,
            pageCount: availablePages.count
        )
    }

    private func deckBody(shown: [AccountPresentation], queue: [AttentionItem], sections: DeckSections) -> some View {
        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            if sections.attention.isShown {
                AttentionSection(items: queue, labels: accountLabels, providers: accountProviders, now: store.now, metrics: metrics) { id in
                    focus(on: id, shown: shown)
                }
                .transition(.opacity)
            }
            if sections.dials.isLaidOut {
                accountSections(shown: shown, sections: sections)
                    // An empty group keeps the accounts' room (so the deck never resizes) and says so in it.
                    .overlay {
                        if let empty = sections.emptyState {
                            emptyState(empty, fillsRoom: true)
                                .transition(.opacity)
                        }
                    }
            } else if let empty = sections.emptyState {
                emptyState(empty, fillsRoom: false)
            }
        }
        .animation(Motion.content, value: queue.isEmpty)
    }

    /// The dial row, the page switcher and the pages, each shown or only reserving its room.
    private func accountSections(shown: [AccountPresentation], sections: DeckSections) -> some View {
        let selectedID = DeckLayout.selection(preferred: model.selectedAccountID, shown: shown.map(\.id), all: accounts.map(\.id))
        return VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            dialRow(shown: shown, selectedID: selectedID)
                .deckSection(sections.dials)
            if sections.pageSwitcher.isLaidOut {
                CapsuleSegmentedControl(
                    options: availablePages.map { (id: $0, title: $0.title(l10n: l10n)) },
                    selection: shownPage,
                    metrics: metrics
                ) { page = $0 }
                .frame(maxWidth: .infinity)
                .deckSection(sections.pageSwitcher)
            }
            // No page is selected while reserved, so none of them loads history or runs an orbit.
            ZStack(alignment: .top) {
                // Where groups exist, a group can be empty: the pages keep at least the room its empty state
                // needs, so a short essentials page never clips the message that replaces it.
                if !store.settings.groups.isEmpty {
                    emptyState(.group(name: nil), fillsRoom: false)
                        .hidden()
                        .accessibilityHidden(true)
                }
                pages(selectedID: sections.pages.isShown ? selectedID : nil)
                    .deckSection(sections.pages)
            }
        }
    }

    private var accountLabels: [AccountID: String] {
        Dictionary(store.state.accounts.map { ($0.id, $0.profile.label.value) }, uniquingKeysWith: { first, _ in first })
    }

    private var accountProviders: [AccountID: ProviderKind] {
        Dictionary(store.state.accounts.map { ($0.id, $0.profile.provider) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: Dials

    @ViewBuilder
    private func dialRow(shown: [AccountPresentation], selectedID: AccountID?) -> some View {
        let spacing = 6 * metrics.scale
        let available = metrics.deckWidth - metrics.deckPadding * 2
        let fits = DeckLayout.dialsFit(count: shown.count, itemWidth: DeckDial.itemWidth(metrics), spacing: spacing, available: available)
        ZStack {
            // A hidden dial keeps the row's height when a group has no accounts.
            if let template = accounts.first {
                dial(template, selectedID: nil)
                    .environment(\.liveEffectsEnabled, false)
                    .hidden()
                    .accessibilityHidden(true)
            }
            if fits {
                dials(shown, selectedID: selectedID, spacing: spacing)
            } else {
                ScrollView(.horizontal) {
                    dials(shown, selectedID: selectedID, spacing: spacing)
                }
                .scrollIndicators(.never)
            }
        }
        .frame(maxWidth: .infinity)
        // Clear air under the dials: the selected account's page starts as its own block, not as the dials' tail.
        .padding(.bottom, 8 * metrics.scale)
        // The rings fly only between dials that are actually in view.
        .modifier(DeckViewportReporter())
    }

    private func dials(_ shown: [AccountPresentation], selectedID: AccountID?, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(shown) { account in
                dial(account, selectedID: selectedID)
                    .onContinuousHover(coordinateSpace: .global) { phase in
                        switch phase {
                        case .active(let location):
                            guard hoverTracking.pointerMoved(to: location) else { return }
                            if hoveredAccountID != account.id {
                                hoveredAccountID = account.id
                            }
                            select(account.id)
                        case .ended:
                            if hoveredAccountID == account.id {
                                hoveredAccountID = nil
                            }
                        }
                    }
                    .onTapGesture { select(account.id) }
                    .accessibilityAction { select(account.id) }
            }
        }
    }

    private func dial(_ account: AccountPresentation, selectedID: AccountID?) -> some View {
        DeckDial(
            presentation: account,
            isSelected: account.id == selectedID,
            isHovered: hoveredAccountID == account.id,
            isHighlighted: model.highlightedAccountID == account.id,
            showsInnerRings: store.settings.appearance.showsSecondaryRing,
            now: store.now,
            metrics: metrics
        )
    }

    // MARK: Pages

    private func pages(selectedID: AccountID?) -> some View {
        PageStackLayout {
            ForEach(accounts) { account in
                ForEach(availablePages) { kind in
                    let isSelected = account.id == selectedID
                    let isShown = isSelected && kind == shownPage
                    pageView(kind, account: account, isSelected: isShown)
                        // Hidden pages draw their orbits still, so no animation runs where nobody sees it.
                        .environment(\.liveEffectsEnabled, isShown && liveEffectsEnabled)
                        .opacity(isShown ? 1 : 0)
                        .allowsHitTesting(isShown)
                        .accessibilityHidden(!isShown)
                }
            }
        }
        .animation(Motion.content, value: selectedID)
        .animation(Motion.content, value: shownPage)
    }

    @ViewBuilder
    private func pageView(_ kind: DeckPage, account: AccountPresentation, isSelected: Bool) -> some View {
        switch kind {
        case .overview:
            AccountDetailView(presentation: account, store: store, isSelected: isSelected, metrics: metrics)
        case .timeline:
            DeckTimelinePage(presentation: account, store: store, isSelected: isSelected, metrics: metrics)
        }
    }

    private func select(_ id: AccountID) {
        guard model.selectedAccountID != id else { return }
        model.selectedAccountID = id
    }

    /// Shows an account from the attention queue, clearing a group filter that hides it.
    private func focus(on id: AccountID, shown: [AccountPresentation]) {
        if !shown.contains(where: { $0.id == id }) {
            store.updateSettings { $0.appearance.railGroupFilter = nil }
        }
        page = .overview
        select(id)
    }

    private func emptyState(_ state: DeckSections.EmptyState, fillsRoom: Bool) -> some View {
        DeckEmptyStateView(
            state: state,
            metrics: metrics,
            fillsRoom: fillsRoom,
            onShowAll: {
                withAnimation(Motion.geometry) {
                    _ = store.updateSettings { $0.appearance.railGroupFilter = nil }
                }
            },
            onOpenSettings: { store.actions.openSettings() }
        )
    }
}

private extension View {
    /// Shows a deck section, or keeps only its room: invisible, without hits and hidden from accessibility.
    func deckSection(_ visibility: DeckSections.Visibility) -> some View {
        opacity(visibility.isShown ? 1 : 0)
            .allowsHitTesting(visibility.isShown)
            .accessibilityHidden(!visibility.isShown)
    }
}

/// Remembers where the pointer first hovered a dial, so hover selection starts only after a real movement.
/// A reference type on purpose: recording pointer locations must not invalidate the deck on every move.
@MainActor
final class DialHoverTracking {
    /// Movements smaller than this (points) are jitter, not intent.
    static let threshold: CGFloat = 2

    private var origin: CGPoint?
    private(set) var hasMoved = false

    /// Records a hover location and returns whether the pointer has moved since the first one.
    func pointerMoved(to location: CGPoint) -> Bool {
        guard !hasMoved else { return true }
        guard let origin else {
            origin = location
            return false
        }
        hasMoved = hypot(location.x - origin.x, location.y - origin.y) >= Self.threshold
        return hasMoved
    }
}

/// Lays pages on top of each other, all as tall as the tallest, so the deck's height never depends on which
/// page is shown and every page can pin its footer to the bottom.
struct PageStackLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)) }
        return CGSize(
            width: proposal.width ?? sizes.map(\.width).max() ?? 0,
            height: sizes.map(\.height).max() ?? 0
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
        }
    }
}

/// Stacks the header and the deck body vertically. The body gets its ideal height, capped so the whole
/// stack stays within `maxHeight` (the body is then expected to scroll).
struct DeckStackLayout: Layout {
    let spacing: CGFloat
    let maxHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let heights = Self.heights(ideal: subviews.map { $0.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)).height }, spacing: spacing, maxHeight: maxHeight)
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        return CGSize(width: width, height: heights.reduce(0, +) + spacing * CGFloat(max(0, subviews.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let heights = Self.heights(ideal: subviews.map { $0.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height }, spacing: spacing, maxHeight: maxHeight)
        var y = bounds.minY
        for (subview, height) in zip(subviews, heights) {
            subview.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: height))
            y += height + spacing
        }
    }

    /// Ideal heights with the last one capped so the total (with spacing) stays within `maxHeight`.
    static func heights(ideal: [CGFloat], spacing: CGFloat, maxHeight: CGFloat) -> [CGFloat] {
        guard let last = ideal.last, maxHeight.isFinite else { return ideal }
        let fixed = ideal.dropLast().reduce(0, +) + spacing * CGFloat(max(0, ideal.count - 1))
        return ideal.dropLast() + [max(0, min(last, maxHeight - fixed))]
    }
}
