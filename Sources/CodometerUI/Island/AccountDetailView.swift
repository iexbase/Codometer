import CodometerCore
import CodometerL10n
import SwiftUI

/// The selected account's overview page: identity, banners, the headline window as a hero with its chart,
/// tiles for every other window the provider reports, live sessions and a footer.
struct AccountDetailView: View {
    let presentation: AccountPresentation
    let store: TrackerStore
    /// Whether this page is the one shown; only then does it load history.
    let isSelected: Bool
    let metrics: IslandMetrics

    @Environment(\.isDeckVisible) private var isDeckVisible
    @Environment(\.l10n) private var l10n

    private var appearance: AppearanceSettings { store.settings.appearance }
    private var status: AccountStatus { presentation.status }

    var body: some View {
        let limitReached = Set(status.reading?.buckets.filter(\.isLimitReached).map(\.id) ?? [])
        let sections = DeckLayout.windowSections(
            windows: presentation.windows,
            primaryWindowID: presentation.headline?.primary.id,
            limitReachedBuckets: limitReached
        )
        let essentials = appearance.deckDetail == .essentials
        VStack(alignment: .leading, spacing: 10 * metrics.scale) {
            identityRow
            if let issue = status.issue {
                IssueBanner(issue: issue, provider: presentation.provider, isRefreshing: status.isRefreshing, metrics: metrics) {
                    store.refresh(presentation.id)
                }
                .transition(.opacity)
            }
            if presentation.isBlocked {
                BlockedBanner(window: presentation.blockingWindow, now: store.now, metrics: metrics)
            }
            if essentials {
                // The essentials: every window as a tile, nothing large, no history, sessions or footer.
                let tiles = DeckLayout.essentialSections(
                    windows: presentation.windows,
                    primaryWindowID: presentation.headline?.primary.id,
                    limitReachedBuckets: limitReached
                )
                if tiles.isEmpty, status.issue == nil {
                    loadingRow
                }
                ForEach(tiles) { section in
                    TileSectionView(
                        section: section,
                        isStale: presentation.isStale,
                        resetStyle: appearance.resetTextStyle,
                        showsRemaining: true,
                        now: store.now,
                        metrics: metrics
                    )
                }
            } else if let hero = sections.hero {
                HeroWindowCard(
                    window: hero,
                    series: store.analytics.series(account: presentation.id, bucket: hero.bucketID, window: hero.window.id),
                    isStale: presentation.isStale,
                    resetStyle: appearance.resetTextStyle,
                    now: store.now,
                    metrics: metrics
                )
                .onAppear { requestHistory(for: hero) }
                .onChange(of: HistoryRequest(hero: hero, page: self)) { _, _ in requestHistory(for: hero) }
            } else if status.issue == nil {
                loadingRow
            }
            if !essentials {
                ForEach(sections.sections) { section in
                    TileSectionView(
                        section: section,
                        isStale: presentation.isStale,
                        resetStyle: appearance.resetTextStyle,
                        now: store.now,
                        metrics: metrics
                    )
                }
                if !status.sessions.isEmpty {
                    SessionList(sessions: status.sessions, provider: presentation.provider, now: store.now, metrics: metrics)
                        .padding(.top, 2 * metrics.scale)
                }
                // Pages share the tallest page's height; the footer sits at the bottom of each.
                Spacer(minLength: 0)
                footer
            }
        }
        .animation(Motion.content, value: status.issue)
        .animation(Motion.content, value: status.sessions)
        // The chart colours usage with the user's band thresholds, like the rings and tiles.
        .environment(\.analyticsStyle, AnalyticsStyle(provider: presentation.provider, bands: appearance.bands))
    }

    // MARK: Identity

    private var identityRow: some View {
        HStack(spacing: 10 * metrics.scale) {
            // The account's own mark, with the provider still readable in its corner.
            AccountBadge(style: presentation.style, provider: presentation.provider, size: 30 * metrics.scale)
            VStack(alignment: .leading, spacing: 1 * metrics.scale) {
                HStack(spacing: 6 * metrics.scale) {
                    Text(status.profile.label.value)
                        .font(metrics.font(TextSize.headline, .semibold))
                        .lineLimit(1)
                    if let plan = status.identity?.plan {
                        TagChip(text: plan, tint: Theme.accent(for: presentation.provider), metrics: metrics)
                    }
                }
                HStack(spacing: 4 * metrics.scale) {
                    if presentation.isStale {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(metrics.font(TextSize.badge, .semibold))
                    }
                    Text(DeckLayout.identityLine(
                        email: presentation.displayEmail ?? presentation.displayOrganization,
                        freshness: presentation.freshness,
                        capturedAt: status.reading?.capturedAt,
                        provider: presentation.provider,
                        now: store.now,
                        l10n: l10n
                    ))
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
                .font(metrics.font(TextSize.caption))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(status.profile.label.value)
        .accessibilityValue(identityA11y)
    }

    /// The plan, the e-mail and the update time in words, for VoiceOver.
    private var identityA11y: String {
        let line = DeckLayout.identityLineA11y(
            email: presentation.displayEmail ?? presentation.displayOrganization,
            freshness: presentation.freshness,
            capturedAt: status.reading?.capturedAt,
            provider: presentation.provider,
            now: store.now,
            l10n: l10n
        )
        return [status.identity?.plan, line].compactMap { $0 }.joined(separator: ", ")
    }

    private var loadingRow: some View {
        HStack(spacing: 8 * metrics.scale) {
            ProgressView().controlSize(.small)
            Text(l10n.deck.loadingLimits)
                .font(metrics.font(TextSize.body))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6 * metrics.scale)
    }

    // MARK: Footer

    private var footer: some View {
        let credits = status.reading?.credits.flatMap { UsageFormat.credits($0, l10n: l10n) }
        return VStack(spacing: 8 * metrics.scale) {
            Hairline()
            HStack(spacing: 8 * metrics.scale) {
                if let group = presentation.group {
                    Label(group.name.value, systemImage: "square.stack.fill")
                        .labelStyle(CompactLabelStyle(spacing: 4 * metrics.scale))
                        .lineLimit(1)
                }
                if let credits {
                    Label(credits, systemImage: "creditcard")
                        .labelStyle(CompactLabelStyle(spacing: 4 * metrics.scale))
                        .lineLimit(1)
                }
                Spacer(minLength: 6 * metrics.scale)
                // Always present, so the footer keeps one height whatever the refresh state.
                Text(DeckLayout.refreshText(status: status, now: store.now, l10n: l10n) ?? " ")
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .accessibilityLabel(DeckLayout.refreshTextA11y(status: status, now: store.now, l10n: l10n) ?? "")
                    .accessibilityHidden(status.nextRefreshAt == nil && !status.isRefreshing)
            }
            .font(metrics.font(TextSize.caption))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4 * metrics.scale)
        }
    }

    // MARK: History

    /// Everything that should re-request the hero's history when it changes.
    private struct HistoryRequest: Equatable {
        let visible: Bool
        let selected: Bool
        let bucketID: String
        let windowID: String
        let since: Date?
        let capturedAt: Date?

        @MainActor
        init(hero: WindowPresentation, page: AccountDetailView) {
            visible = page.isDeckVisible
            selected = page.isSelected
            bucketID = hero.bucketID
            windowID = hero.window.id
            since = DeckLayout.historySince(window: hero.window, now: page.store.now)
            capturedAt = page.status.reading?.capturedAt
        }
    }

    /// Only a deck the user actually sees loads history; hidden measurement copies never do.
    private func requestHistory(for hero: WindowPresentation) {
        guard isDeckVisible, isSelected,
              let since = DeckLayout.historySince(window: hero.window, now: store.now)
        else { return }
        store.analytics.requestSeries(account: presentation.id, bucket: hero.bucketID, window: hero.window.id, since: since)
    }
}
