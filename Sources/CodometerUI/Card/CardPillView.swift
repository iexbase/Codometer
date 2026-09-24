import CodometerCore
import CodometerL10n
import SwiftUI

/// The minimized card: a ring, the percentage and the countdown for one account, or up to three mini rings and a "+N"
/// badge for several.
///
/// Its width comes from `CardMetrics.pillSize(accounts:templates:)`, which measures the hidden templates only, so the
/// pill is the same width in one language whatever the numbers say, and one click restores the card.
struct CardPillView: View {
    let store: TrackerStore
    let model: FloatingCardModel
    let accounts: [AccountPresentation]

    @Environment(\.l10n) private var l10n
    @Environment(\.cardTheme) private var theme
    @Environment(\.cardMetrics) private var metrics

    private var selected: AccountPresentation? {
        accounts.first { $0.id == model.selectedAccountID } ?? accounts.first
    }

    /// The accounts a crowded pill shows, most urgent first.
    private var ordered: [AccountPresentation] {
        accounts.sorted { lhs, rhs in
            let a = CardAccountSelector.rank(lhs)
            let b = CardAccountSelector.rank(rhs)
            if a.band != b.band { return a.band > b.band }
            if a.waiting != b.waiting { return a.waiting > b.waiting }
            return a.used > b.used
        }
    }

    var body: some View {
        content
            .frame(width: model.pillFrame.width, height: model.pillFrame.height)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(l10n.card.pillA11y(summary))
            .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var content: some View {
        if accounts.count <= 1 {
            single
        } else {
            several
        }
    }

    @ViewBuilder
    private var single: some View {
        HStack(spacing: 6 * metrics.scale) {
            if let selected {
                RingGauge(
                    presentation: selected,
                    diameter: metrics.pillRing,
                    showsSecondary: false,
                    forecastPolicy: .always,
                    ceremonySurface: .card
                )
                .accessibilityHidden(true)
                Text(percentText(selected))
                    .font(metrics.font(.pill))
                    .foregroundStyle(theme.primaryTextColor)
                    .contentTransition(.numericText())
                Text(countdownText(selected))
                    .font(metrics.font(.pill))
                    .foregroundStyle(theme.secondaryTextColor)
                    .contentTransition(.numericText())
            } else {
                Text(l10n.common.noData)
                    .font(metrics.font(.pill))
                    .foregroundStyle(theme.secondaryTextColor)
            }
        }
        .padding(.horizontal, metrics.pillPadding)
        .lineLimit(1)
    }

    private var several: some View {
        let shown = Array(ordered.prefix(3))
        let rest = accounts.count - shown.count
        return HStack(spacing: 3 * metrics.scale) {
            ForEach(shown) { account in
                RingGauge(
                    presentation: account,
                    diameter: metrics.pillRing,
                    showsSecondary: false,
                    forecastPolicy: .always,
                    ceremonySurface: .card
                )
                .accessibilityHidden(true)
            }
            if rest > 0 {
                Text(verbatim: "+\(rest)")
                    .font(metrics.font(.pill))
                    .foregroundStyle(theme.secondaryTextColor)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, metrics.pillPadding)
    }

    private func percentText(_ presentation: AccountPresentation) -> String {
        guard let headline = presentation.headline else { return l10n.card.noValue }
        return l10n.format.percentCompact(headline.binding.used.value)
    }

    private func countdownText(_ presentation: AccountPresentation) -> String {
        guard let resetsAt = presentation.headline?.binding.resetsAt else { return l10n.card.noValue }
        return l10n.format.durationCompact(max(0, resetsAt.timeIntervalSince(store.now)))
    }

    /// What VoiceOver reads after "Codometer, minimized.".
    private var summary: String {
        CardContentPlan.pillSummary(showing: selected, accounts: accounts, now: store.now, l10n: l10n)
    }
}
