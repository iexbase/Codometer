import CodometerCore
import CodometerL10n
import SwiftUI

/// The deck's title, freshness line, header buttons and group filter.
struct DeckHeader: View {
    let store: TrackerStore
    let accounts: [AccountPresentation]
    let context: DeckContext
    let metrics: IslandMetrics
    /// Replaces the freshness line, e.g. "Not set up yet" when there is no account to be fresh.
    var subtitle: String?
    /// Whether the group filter may show (`DeckSections.groupFilter`); it shows only when there are groups.
    var showsGroupFilter = true
    @Environment(\.l10n) private var l10n

    var body: some View {
        let options = DeckLayout.filterOptions(groups: store.settings.groups, l10n: l10n)
        VStack(alignment: .leading, spacing: 10 * metrics.scale) {
            VStack(alignment: .leading, spacing: 1 * metrics.scale) {
                HStack(alignment: .center, spacing: 8 * metrics.scale) {
                    Text(l10n.deck.title)
                        .font(metrics.font(TextSize.title, .bold))
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8 * metrics.scale)
                    // Reserved whenever the setting is on, so a status arriving or ageing out moves nothing.
                    if store.settings.general.showsVendorStatus {
                        ServiceStatusChip(status: currentStatus, now: store.now, metrics: metrics) { provider in
                            store.actions.openStatusPage(provider)
                        }
                    }
                    buttons
                }
                Text(subtitle ?? DeckLayout.headerSubtitle(accounts: accounts.map(\.status), now: store.now, l10n: l10n))
                    .font(metrics.font(TextSize.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .contentTransition(.opacity)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(subtitle ?? DeckLayout.headerSubtitleA11y(accounts: accounts.map(\.status), now: store.now, l10n: l10n))
            }
            if showsGroupFilter, !options.isEmpty {
                CapsuleSegmentedControl(
                    options: options.map { (id: $0.id, title: $0.title) },
                    selection: store.settings.appearance.railGroupFilter,
                    metrics: metrics
                ) { groupID in
                    store.updateSettings { $0.appearance.railGroupFilter = groupID }
                }
            }
        }
    }

    /// The vendor trouble worth showing right now, if any.
    private var currentStatus: ServiceStatus? {
        DeckStatus.current(
            board: store.serviceStatus,
            accounts: store.settings.accounts,
            now: store.now
        )
    }

    private var buttons: some View {
        GlassEffectContainer(spacing: 6 * metrics.scale) {
            HStack(spacing: 6 * metrics.scale) {
                GlassIconButton(
                    systemImage: "arrow.clockwise",
                    help: l10n.deck.refreshAllHelp,
                    isBusy: accounts.contains { $0.status.isRefreshing },
                    metrics: metrics
                ) {
                    store.refresh()
                }
                GlassIconButton(systemImage: "gearshape", help: l10n.deck.settingsHelp, metrics: metrics) {
                    store.actions.openSettings()
                }
                if context == .popover {
                    GlassIconButton(systemImage: "power", help: l10n.deck.quitHelp, metrics: metrics) {
                        store.actions.quit()
                    }
                }
            }
        }
    }
}

/// Which vendor's status the header shows.
enum DeckStatus {
    /// The worst recent trouble among the vendors the user actually tracks, Claude first when two are equally bad.
    ///
    /// A vendor without an enabled account is never fetched and never shown, so a Claude-only user never reads about
    /// an OpenAI outage.
    static func current(board: ServiceStatusBoard, accounts: [AccountProfile], now: Date) -> ServiceStatus? {
        let tracked = Set(accounts.filter(\.isEnabled).map(\.provider))
        var worst: ServiceStatus?
        for provider in ProviderKind.allCases where tracked.contains(provider) {
            guard let status = board.visible(for: provider, now: now), let level = status.level else { continue }
            guard let current = worst, let currentLevel = current.level else {
                worst = status
                continue
            }
            if level > currentLevel {
                worst = status
            }
        }
        return worst
    }

    /// The names the chip's tooltip and VoiceOver read out: the affected components, or the vendor itself when the
    /// page named none.
    static func subject(of status: ServiceStatus, l10n: Localizer) -> String {
        status.affectedComponents.isEmpty
            ? UsageFormat.providerName(status.provider)
            : l10n.format.list(status.affectedComponents)
    }
}

/// The vendor status chip: what is wrong, in words, with a click through to the vendor's own status page.
///
/// It keeps the width of the widest wording in the current language whether or not a status is showing, so the
/// header's buttons never move. Colour only doubles the word and the symbol.
private struct ServiceStatusChip: View {
    let status: ServiceStatus?
    let now: Date
    let metrics: IslandMetrics
    let action: (ProviderKind) -> Void

    @Environment(\.l10n) private var l10n

    var body: some View {
        Button {
            guard let status else { return }
            action(status.provider)
        } label: {
            ZStack {
                // The widest wording of this language holds the width; the real row is centred in it.
                row(text: l10n.serviceStatus.chipTemplate, symbol: "exclamationmark.triangle.fill")
                    .hidden()
                    .accessibilityHidden(true)
                row(text: title, symbol: symbol)
            }
            .padding(.horizontal, 8 * metrics.scale)
            .frame(minHeight: 24 * metrics.scale)
            .background(Capsule().fill(Theme.cardFill))
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(status == nil)
        .opacity(status == nil ? 0 : 1)
        .animation(Motion.content, value: status)
        .help(help)
        .accessibilityHidden(status == nil)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(l10n.serviceStatus.opensStatusPage)
    }

    /// One row of the chip: the severity symbol and the wording.
    ///
    /// The symbol sits in a slot of a fixed width, wide enough for the widest of the four (the wrench), so the row
    /// measures the same whichever level shows and the reserved width below is exact.
    private func row(text: String, symbol: String) -> some View {
        HStack(spacing: 4 * metrics.scale) {
            Image(systemName: symbol)
                .font(metrics.font(TextSize.badge, .semibold))
                .foregroundStyle(tint)
                .frame(width: metrics.textSize(TextSize.badge) * 1.4)
            Text(text)
                .font(metrics.font(TextSize.caption, .medium))
                .lineLimit(1)
        }
    }

    private var title: String {
        guard let status, let level = status.level else { return "" }
        return l10n.serviceStatus.chip(vendor: UsageFormat.providerName(status.provider), level: ServiceStatusText.name(level, l10n: l10n))
    }

    private var help: String {
        guard let status, let level = status.level else { return "" }
        return l10n.serviceStatus.tooltip(
            components: DeckStatus.subject(of: status, l10n: l10n),
            level: ServiceStatusText.inSentence(level, l10n: l10n),
            host: VendorStatusFeed.host(for: status.provider),
            ago: l10n.format.ago(status.checkedAt, now: now)
        )
    }

    private var accessibilityLabel: String {
        guard let status, let level = status.level else { return "" }
        return l10n.serviceStatus.chipA11y(
            components: DeckStatus.subject(of: status, l10n: l10n),
            level: ServiceStatusText.inSentence(level, l10n: l10n),
            duration: l10n.format.durationSpoken(max(0, now.timeIntervalSince(status.checkedAt)))
        )
    }

    private var symbol: String {
        switch status?.level {
        case .maintenance: "wrench.and.screwdriver.fill"
        case .degraded: "exclamationmark.circle.fill"
        case .partialOutage: "exclamationmark.triangle.fill"
        case .majorOutage, nil: "exclamationmark.octagon.fill"
        }
    }

    /// The symbol's colour. It repeats what the word already says, so nothing depends on seeing it.
    private var tint: Color {
        switch status?.level {
        case .maintenance: .blue
        case .degraded: Theme.warning
        case .partialOutage: .orange
        case .majorOutage, nil: .red
        }
    }
}

/// The words for a service status level, in both places they are needed.
public enum ServiceStatusText {
    /// On its own, as a chip or a pill: "Partial outage" | «Частичный сбой».
    public static func name(_ level: ServiceStatusLevel, l10n: Localizer) -> String {
        switch level {
        case .maintenance: l10n.serviceStatus.maintenance
        case .degraded: l10n.serviceStatus.degraded
        case .partialOutage: l10n.serviceStatus.partialOutage
        case .majorOutage: l10n.serviceStatus.majorOutage
        }
    }

    /// Inside a sentence, such as the tooltip: "partial outage" | «частичный сбой».
    public static func inSentence(_ level: ServiceStatusLevel, l10n: Localizer) -> String {
        switch level {
        case .maintenance: l10n.serviceStatus.maintenanceInSentence
        case .degraded: l10n.serviceStatus.degradedInSentence
        case .partialOutage: l10n.serviceStatus.partialOutageInSentence
        case .majorOutage: l10n.serviceStatus.majorOutageInSentence
        }
    }
}
