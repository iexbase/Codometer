import CodometerCore
import CodometerL10n
import SwiftUI
import WidgetKit

/// The Claude and Codex widgets: one provider's accounts only.
///
/// Small features the provider's most constrained account; medium shows it in detail, or up to three accounts side
/// by side when the provider has several — or, with the strip layout chosen, the strip. Without an account of that
/// provider the widget says so calmly.
struct ProviderLimitsContent: View {
    let provider: ProviderKind
    /// Already scoped to `provider`.
    let snapshot: WidgetSnapshot
    let states: [WidgetAccountState]
    let family: WidgetFamily
    let palette: WidgetPalette

    var body: some View {
        if let featured = WidgetSelection.mostConstrained(states, provider: provider) {
            switch family {
            case .systemSmall:
                ProviderSmallView(
                    state: featured,
                    showsAccountBadge: ProviderSmallView.showsAccountBadge(for: featured.account, providerAccounts: states.count),
                    palette: palette
                )
            case _ where snapshot.layout == .strip:
                StripLimitsView(scope: .provider(provider), snapshot: snapshot, states: states, family: family, palette: palette)
            default:
                MediumLimitsView(states: WidgetSelection.featured(states, limit: 3), palette: palette, withinProvider: true)
            }
        } else {
            NoProviderAccountView(provider: provider, isCompact: family == .systemSmall, palette: palette)
        }
    }
}

/// systemSmall for one provider: its identity and agents on top, the headline number beside a double ring (the ring
/// window outside, the busiest window of the other length inside), then the window's title and its reset.
struct ProviderSmallView: View {
    let state: WidgetAccountState
    /// Whether the header shows the account's identity badge instead of the provider's mark; see
    /// `showsAccountBadge(for:providerAccounts:)`.
    var showsAccountBadge = false
    let palette: WidgetPalette
    @Environment(\.widgetL10n) private var l10n

    nonisolated static let headerHeight: CGFloat = 20
    nonisolated static let ringSide: CGFloat = 62
    /// Like every small widget: only a forecast that runs into the limit.
    nonisolated static let forecastPolicy = WidgetForecastPolicy.warningsOnly

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .frame(height: Self.headerHeight)

            Spacer(minLength: 4)

            HStack(alignment: .center, spacing: 6) {
                headline
                    .frame(maxWidth: .infinity, alignment: .leading)
                WidgetRing(
                    window: state.binding,
                    companion: state.companion,
                    isStale: state.isStale,
                    lineWidth: 7,
                    isWaiting: state.account.waitingCount > 0,
                    forecastPolicy: Self.forecastPolicy,
                    palette: palette
                ) {
                    ringCenter
                }
                .frame(width: Self.ringSide, height: Self.ringSide)
                .padding(.trailing, state.account.waitingCount > 0 ? 5 : 0)
            }
            .frame(height: Self.ringSide + 6)

            Spacer(minLength: 4)

            Text(verbatim: state.binding?.source.displayTitle ?? l10n.common.noData)
                .font(WidgetFont.text(12.5, .semibold))
                .foregroundStyle(palette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            // A blocked account keeps "100%" as the headline, so its countdown lives here: "🔒 Back in 2 hr, 13 min".
            StatusLine(state: state, palette: palette, size: 11, blockedCountdownShownElsewhere: false, resetWording: .short)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    /// One account of a provider needs no telling apart, so its header keeps the provider's own mark; with several,
    /// the account's badge is what the glance is for. The island's rail draws the same line. A snapshot from an
    /// older build has no monogram and always keeps the provider mark.
    nonisolated static func showsAccountBadge(for account: WidgetAccount, providerAccounts: Int) -> Bool {
        providerAccounts > 1 && account.monogram != nil
    }

    /// The mark in front of the label.
    @ViewBuilder
    private var identityMark: some View {
        if showsAccountBadge, let monogram = state.account.monogram {
            WidgetAccountBadge(monogram: monogram, tint: state.account.tint, palette: palette, side: Self.headerHeight)
        } else {
            ProviderBadgeMark(provider: state.account.provider, palette: palette, side: Self.headerHeight)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            identityMark
            Text(verbatim: WidgetText.labelWithinProvider(state.account.label, provider: state.account.provider))
                .font(WidgetFont.text(12.5, .semibold))
                .foregroundStyle(palette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 2)
            ActivityBadge(state: state, palette: palette, size: 11)
        }
    }

    /// A lock while blocked; otherwise the inner ring's number and window length, so the second ring explains
    /// itself: "38" over "wk".
    @ViewBuilder
    private var ringCenter: some View {
        if state.isBlocked, !state.isStale {
            // The status line below says "Back in …".
            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.number(.exhausted, isStale: false))
                .accessibilityHidden(true)
        } else if let companion = state.companion {
            VStack(spacing: -1) {
                Text(verbatim: WidgetText.percentNumber(companion.window.used))
                    .font(WidgetFont.digits(11, .bold))
                    .foregroundStyle(palette.number(companion.band, isStale: state.isStale))
                if let caption = WidgetText.shortDuration(companion.window, l10n: l10n) {
                    Text(verbatim: caption)
                        .font(WidgetFont.text(8, .semibold))
                        .foregroundStyle(palette.secondary)
                }
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        } else if state.binding == nil {
            ProviderMark(provider: state.account.provider, color: palette.secondary)
                .frame(width: 18, height: 18)
        }
    }

    /// The ring window's usage, as large as the space beside the ring allows.
    private var headline: some View {
        FittingPercentText(
            window: state.binding,
            isStale: state.isStale,
            sizes: [40, 34, 28, 22],
            forecastPolicy: Self.forecastPolicy,
            palette: palette
        )
    }
}

/// Waiting agents first, otherwise working ones; nothing while the account is idle.
struct ActivityBadge: View {
    let state: WidgetAccountState
    let palette: WidgetPalette
    var size: CGFloat = 11.5

    var body: some View {
        if state.account.waitingCount > 0 {
            AttentionBadge(count: state.account.waitingCount, palette: palette, size: size)
        } else if state.isWorkingOnly {
            WorkingBadge(count: state.account.workingCount, palette: palette, size: size)
        }
    }
}

/// "No Codex account": the provider has no enabled account in Codometer.
struct NoProviderAccountView: View {
    @Environment(\.widgetL10n) private var l10n
    let provider: ProviderKind
    let isCompact: Bool
    let palette: WidgetPalette

    var body: some View {
        let name = WidgetText.providerName(provider)
        VStack(spacing: isCompact ? 7 : 8) {
            ZStack {
                Circle()
                    .inset(by: 3)
                    .stroke(palette.track, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, dash: [0.1, 6.5]))
                ProviderMark(provider: provider, color: palette.secondary)
                    .frame(width: 19, height: 19)
            }
            .frame(width: 50, height: 50)
            .accessibilityHidden(true)
            Text(verbatim: l10n.widget.noAccount(name))
                .font(WidgetFont.text(isCompact ? 13 : 14, .semibold))
                .foregroundStyle(palette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(verbatim: isCompact ? l10n.widget.addOne : l10n.widget.addProfile(name))
                .font(WidgetFont.text(11, .medium))
                .foregroundStyle(palette.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
