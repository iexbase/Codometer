import CodometerCore
import CodometerL10n
import SwiftUI

/// systemMedium: one account in detail, or up to three accounts side by side.
struct MediumLimitsView: View {
    /// A medium widget has room for the forecast ghost on every ring.
    nonisolated static let forecastPolicy = WidgetForecastPolicy.always

    let states: [WidgetAccountState]
    let palette: WidgetPalette
    /// In a provider's own widget labels drop the provider's name: "Work" rather than "Codex · Work".
    var withinProvider = false

    var body: some View {
        if states.count == 1, let state = states.first {
            MediumSingleAccountView(state: state, palette: palette, withinProvider: withinProvider)
        } else {
            HStack(spacing: 0) {
                ForEach(Array(states.enumerated()), id: \.element.id) { offset, state in
                    if offset > 0 {
                        Rectangle()
                            .fill(palette.hairline)
                            .frame(width: 1)
                            .padding(.vertical, 14)
                    }
                    MediumAccountColumn(state: state, isNarrow: states.count > 2, palette: palette, withinProvider: withinProvider)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

/// A ring with the number inside and the account, window and reset below it. A waiting account shows the attention
/// halo around its ring rather than a corner badge, which would cover part of the arc.
private struct MediumAccountColumn: View {
    @Environment(\.widgetL10n) private var l10n
    let state: WidgetAccountState
    /// Three columns leave no room for "Resets in" or "Back in", so the line reads "↻ 2 hr, 13 min" or "🔒 2 hr, 13 min".
    let isNarrow: Bool
    let palette: WidgetPalette
    let withinProvider: Bool

    var body: some View {
        VStack(spacing: 8) {
            WidgetRing(
                window: state.binding,
                isStale: state.isStale,
                lineWidth: 7,
                isWaiting: state.account.waitingCount > 0,
                forecastPolicy: MediumLimitsView.forecastPolicy,
                palette: palette
            ) {
                VStack(spacing: 1) {
                    ProviderMark(provider: state.account.provider, color: palette.secondary)
                        .frame(width: 11, height: 11)
                    if state.isBlocked, !state.isStale {
                        // The status line below says "Back in …".
                        Image(systemName: "lock.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(palette.number(.exhausted, isStale: false))
                            .frame(height: 20)
                            .accessibilityHidden(true)
                    } else {
                        PercentText(
                            window: state.binding,
                            isStale: state.isStale,
                            size: 17,
                            forecastPolicy: MediumLimitsView.forecastPolicy,
                            palette: palette
                        )
                        .frame(height: 20)
                    }
                }
                .padding(.top, 2)
            }
            .frame(width: 72, height: 72)

            VStack(spacing: 1.5) {
                Text(verbatim: label(state, withinProvider: withinProvider))
                    .font(WidgetFont.text(12.5, .semibold))
                    .foregroundStyle(palette.primary)
                    .minimumScaleFactor(0.85)
                Text(verbatim: state.binding?.source.displayTitle ?? l10n.common.noData)
                    .font(WidgetFont.text(11, .medium))
                    .foregroundStyle(palette.secondary)
                    .minimumScaleFactor(0.8)
                StatusLine(state: state, palette: palette, size: 11, blockedCountdownShownElsewhere: false, isCompact: isNarrow)
            }
            .lineLimit(1)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 4)
        }
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// A large ring beside every window of the account as meters.
private struct MediumSingleAccountView: View {
    @Environment(\.widgetL10n) private var l10n
    let state: WidgetAccountState
    let palette: WidgetPalette
    let withinProvider: Bool

    var body: some View {
        HStack(spacing: 16) {
            WidgetRing(
                window: state.binding,
                isStale: state.isStale,
                lineWidth: 9,
                isWaiting: state.account.waitingCount > 0,
                forecastPolicy: MediumLimitsView.forecastPolicy,
                palette: palette
            ) {
                VStack(spacing: 2) {
                    ProviderMark(provider: state.account.provider, color: palette.secondary)
                        .frame(width: 14, height: 14)
                    if state.isBlocked, !state.isStale, let reset = state.headlineReset {
                        let backIn = l10n.widget.backIn
                        Countdown.text(until: reset, at: state.date)
                            .font(WidgetFont.digits(14, .bold))
                            .foregroundStyle(palette.number(.exhausted, isStale: false))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(width: 70, height: 30)
                            .accessibilityLabel(Text("\(backIn.prefix)\(Countdown.text(until: reset, at: state.date))\(backIn.suffix)"))
                    } else {
                        PercentText(
                            window: state.binding,
                            isStale: state.isStale,
                            size: 28,
                            forecastPolicy: MediumLimitsView.forecastPolicy,
                            palette: palette
                        )
                        .frame(height: 30)
                    }
                }
            }
            .frame(width: 112, height: 112)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Text(verbatim: label(state, withinProvider: withinProvider))
                        .font(WidgetFont.text(14, .semibold))
                        .foregroundStyle(palette.primary)
                        .lineLimit(1)
                    if let plan = state.account.plan {
                        PlanChip(text: plan, palette: palette)
                    }
                    Spacer(minLength: 4)
                    ActivityBadge(state: state, palette: palette, size: 11)
                }
                .frame(height: 20)

                Spacer(minLength: 4)

                VStack(alignment: .leading, spacing: 7) {
                    ForEach(state.windowsForDisplay(limit: 3)) { window in
                        WindowMeterRow(window: window, isStale: state.isStale, layout: .stacked, palette: palette)
                    }
                }

                Spacer(minLength: 4)

                StatusLine(state: state, palette: palette, blockedCountdownShownElsewhere: true)
            }
            .frame(maxHeight: .infinity)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The account's label, without the provider's name inside that provider's own widget.
private func label(_ state: WidgetAccountState, withinProvider: Bool) -> String {
    withinProvider ? WidgetText.labelWithinProvider(state.account.label, provider: state.account.provider) : state.account.label
}
