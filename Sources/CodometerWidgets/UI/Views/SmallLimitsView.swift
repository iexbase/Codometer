import CodometerCore
import CodometerL10n
import SwiftUI

/// systemSmall: the most constrained account — its ring, a big number, the window it belongs to and the reset —
/// and how many agents wait across all accounts.
struct SmallLimitsView: View {
    /// A 54 pt ring stays calm: the forecast ghost appears only when it runs into the limit.
    nonisolated static let forecastPolicy = WidgetForecastPolicy.warningsOnly

    @Environment(\.widgetL10n) private var l10n
    let state: WidgetAccountState
    let attentionCount: Int
    let palette: WidgetPalette

    var body: some View {
        let window = state.binding
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 6) {
                WidgetRing(
                    window: window,
                    isStale: state.isStale,
                    lineWidth: 6.5,
                    isWaiting: state.account.waitingCount > 0,
                    forecastPolicy: Self.forecastPolicy,
                    palette: palette
                ) {
                    ProviderMark(provider: state.account.provider, color: palette.primary)
                        .frame(width: 16, height: 16)
                        .opacity(state.isBlocked ? 0.55 : 0.92)
                }
                .frame(width: 54, height: 54)

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 5) {
                    Text(verbatim: state.account.label)
                        .font(WidgetFont.text(12, .semibold))
                        .foregroundStyle(palette.secondary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if attentionCount > 0 {
                        AttentionBadge(count: attentionCount, palette: palette)
                    }
                }
            }

            Spacer(minLength: 2)

            headline
                .frame(height: 40, alignment: .bottomLeading)

            Text(verbatim: window?.source.displayTitle ?? l10n.common.noData)
                .font(WidgetFont.text(12.5, .semibold))
                .foregroundStyle(palette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 1)

            StatusLine(state: state, palette: palette)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var headline: some View {
        if state.isBlocked, !state.isStale, let reset = state.headlineReset {
            let backIn = l10n.widget.backIn
            Countdown.text(until: reset, at: state.date)
                .font(WidgetFont.digits(25, .bold))
                .foregroundStyle(palette.number(.exhausted, isStale: false))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .accessibilityLabel(Text("\(backIn.prefix)\(Countdown.text(until: reset, at: state.date))\(backIn.suffix)"))
        } else {
            PercentText(window: state.binding, isStale: state.isStale, size: 38, forecastPolicy: Self.forecastPolicy, palette: palette)
        }
    }
}
