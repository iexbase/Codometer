import CodometerCore
import CodometerL10n
import SwiftUI

/// The headline window in large: numeral, what is left, reset, pace and the chart of the current window.
struct HeroWindowCard: View {
    let window: WindowPresentation
    let series: HistorySeries?
    let isStale: Bool
    let resetStyle: ResetTextStyle
    let now: Date
    let metrics: IslandMetrics
    @Environment(\.l10n) private var l10n

    var body: some View {
        let used = window.window.used
        VStack(alignment: .leading, spacing: 8 * metrics.scale) {
            HStack(alignment: .center, spacing: 8 * metrics.scale) {
                Text(window.title)
                    .font(metrics.font(TextSize.footnote, .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 6 * metrics.scale)
                if let reset = UsageFormat.resetText(for: window.window, now: now, style: resetStyle, l10n: l10n) {
                    InfoChip(systemImage: "arrow.counterclockwise", text: reset, metrics: metrics)
                }
            }
            HStack(alignment: .center, spacing: 12 * metrics.scale) {
                Text(UsageFormat.percent(used, l10n: l10n))
                    .font(metrics.digits(TextSize.hero, .bold))
                    .foregroundStyle(isStale ? AnyShapeStyle(.secondary) : AnyShapeStyle(Theme.bandText(for: window.band)))
                    .contentTransition(.numericText(value: used.value))
                    .lineLimit(1)
                    .fixedSize()
                VStack(alignment: .leading, spacing: 4 * metrics.scale) {
                    Text(l10n.deck.percentLeft(l10n.format.percent(Double(DeckLayout.remainingPercent(used)))))
                        .font(metrics.digits(TextSize.callout, .medium))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                    if let pace = window.pace, !used.isExhausted {
                        PacePill(
                            pace: UsageFormat.pace(pace, now: now, l10n: l10n),
                            compactText: DeckLayout.compactPaceText(pace, now: now, l10n: l10n),
                            isStale: isStale,
                            metrics: metrics
                        )
                    }
                }
                Spacer(minLength: 0)
            }
            UsageBar(
                fraction: window.progress.used,
                band: window.band,
                height: 6 * metrics.scale,
                elapsed: window.progress.elapsed,
                isStale: isStale,
                // The hero bar carries the same ghost as the deck's dials: where this pace lands by the reset.
                forecast: RingForecastPolicy.always.arcEnd(used: window.progress.used, forecast: window.forecast),
                forecastBand: window.forecast?.band
            )
            WindowHistoryChart(series: series, window: window.window, now: now, metrics: metrics)
                // Stale data is calm grey everywhere, the chart included: its band colour would claim a current value.
                .compositingGroup()
                .grayscale(isStale ? 1 : 0)
                .opacity(isStale ? 0.75 : 1)
        }
        .padding(metrics.cardPadding)
        .background(RoundedRectangle(cornerRadius: metrics.tileCorner, style: .continuous).fill(Theme.cardFill))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(window.title)
        .accessibilityValue(valueA11y)
    }

    /// Used and left, the reset in words and the pace; the chart's marks are not read.
    private var valueA11y: String {
        let used = window.window.used
        var parts = [
            l10n.deck.usedA11y(l10n.format.percent(used.value)),
            l10n.deck.percentLeft(l10n.format.percent(Double(DeckLayout.remainingPercent(used)))),
        ]
        if let reset = DeckLayout.resetTextA11y(for: window.window, now: now, style: resetStyle, l10n: l10n) {
            parts.append(reset)
        }
        if let forecast = window.forecast, RingForecastPolicy.always.arcEnd(used: window.progress.used, forecast: forecast) != nil, !isStale {
            parts.append(forecast.reachesLimit ? l10n.motion.forecastRunsOutA11y : l10n.motion.forecastA11y(l10n.format.percent(forecast.projectedUsed)))
        }
        if let pace = window.pace, !used.isExhausted {
            parts.append(UsageFormat.pace(pace, now: now, l10n: l10n).text)
        }
        return parts.joined(separator: ", ")
    }
}

/// How usage compares with time: a hot pill when usage runs ahead, a calm one otherwise, grey for stale data.
///
/// One line always: when the full wording is too wide for the space offered, `compactText` takes its place (and is
/// truncated only if even that does not fit), so a long date never changes the card's height.
struct PacePill: View {
    let pace: UsageFormat.PaceText
    /// A shorter wording for a narrow space, or `nil` when `pace.text` is the only one.
    var compactText: String?
    let isStale: Bool
    let metrics: IslandMetrics

    var body: some View {
        ViewThatFits(in: .horizontal) {
            pill(pace.text)
            if let compactText {
                pill(compactText)
            }
        }
    }

    private func pill(_ text: String) -> some View {
        let band: UsageBand = pace.isWarning ? .watch : .ample
        return HStack(spacing: 4 * metrics.scale) {
            Image(systemName: pace.isWarning ? "flame.fill" : "leaf.fill")
                .font(metrics.font(TextSize.badge, .semibold))
            Text(text)
                .font(metrics.font(TextSize.caption, .medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(isStale ? AnyShapeStyle(.secondary) : AnyShapeStyle(Theme.bandText(for: band)))
        .padding(.horizontal, 7 * metrics.scale)
        .padding(.vertical, 2.5 * metrics.scale)
        .background(Capsule().fill(isStale ? Theme.subtleFill : Theme.tint(for: band).opacity(0.13)))
    }
}

/// Tiles for a group of windows, two per row, with a caption for buckets other than the main one.
struct TileSectionView: View {
    let section: DeckLayout.TileSection
    let isStale: Bool
    let resetStyle: ResetTextStyle
    /// Whether each tile also says what is left (the essentials page).
    var showsRemaining = false
    let now: Date
    let metrics: IslandMetrics
    @Environment(\.l10n) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: 6 * metrics.scale) {
            if let title = section.title {
                HStack(spacing: 5 * metrics.scale) {
                    Image(systemName: "cpu")
                        .font(metrics.font(TextSize.badge, .semibold))
                    Text(title)
                        .font(metrics.font(TextSize.footnote, .semibold))
                        .lineLimit(1)
                    if section.isLimitReached {
                        TagChip(text: l10n.deck.limitReachedTag, tint: Theme.bandText(for: .exhausted), metrics: metrics)
                    }
                }
                .foregroundStyle(.secondary)
                .padding(.leading, 4 * metrics.scale)
                .padding(.top, 2 * metrics.scale)
            }
            Grid(horizontalSpacing: metrics.tileSpacing, verticalSpacing: metrics.tileSpacing) {
                ForEach(DeckLayout.rows(section.tiles), id: \.first?.id) { row in
                    GridRow {
                        ForEach(row) { window in
                            WindowTile(window: window, isWide: row.count == 1, isStale: isStale, resetStyle: resetStyle, showsRemaining: showsRemaining, now: now, metrics: metrics)
                                .gridCellColumns(row.count == 1 ? 2 : 1)
                        }
                    }
                }
            }
        }
    }
}

/// One limit window as a tile: title, percentage, bar with the "now" notch, reset.
/// A wide tile (alone in its row) puts the reset next to the percentage instead of under the bar.
struct WindowTile: View {
    let window: WindowPresentation
    let isWide: Bool
    let isStale: Bool
    let resetStyle: ResetTextStyle
    /// Whether "N% left" follows the percentage.
    var showsRemaining = false
    let now: Date
    let metrics: IslandMetrics
    @Environment(\.l10n) private var l10n

    var body: some View {
        let used = window.window.used
        // Always one line, so a window without a reset time keeps the tile's height.
        let reset = Text(UsageFormat.resetText(for: window.window, now: now, style: resetStyle, l10n: l10n) ?? " ")
            .font(metrics.digits(TextSize.caption))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
        VStack(alignment: .leading, spacing: 5 * metrics.scale) {
            Text(window.title)
                .font(metrics.font(TextSize.footnote, .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            HStack(alignment: .firstTextBaseline, spacing: 8 * metrics.scale) {
                Text(UsageFormat.percent(used, l10n: l10n))
                    .font(metrics.digits(TextSize.tileValue, .bold))
                    .foregroundStyle(isStale ? AnyShapeStyle(.secondary) : AnyShapeStyle(Theme.bandText(for: window.band)))
                    .contentTransition(.numericText(value: used.value))
                    .lineLimit(1)
                    .fixedSize()
                if showsRemaining {
                    Text(l10n.deck.percentLeft(l10n.format.percent(Double(DeckLayout.remainingPercent(used)))))
                        .font(metrics.digits(TextSize.caption, .medium))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                }
                if isWide {
                    Spacer(minLength: 8 * metrics.scale)
                    reset
                }
            }
            UsageBar(
                fraction: window.progress.used,
                band: window.band,
                height: 5 * metrics.scale,
                elapsed: window.progress.elapsed,
                isStale: isStale
            )
            .padding(.vertical, 1 * metrics.scale)
            if !isWide {
                reset
            }
        }
        .padding(metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: metrics.tileCorner, style: .continuous).fill(Theme.cardFill))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(window.title)
        .accessibilityValue(valueA11y)
    }

    /// Used (and left, on the essentials page) and the reset in words.
    private var valueA11y: String {
        [
            l10n.deck.usedA11y(l10n.format.percent(window.window.used.value)),
            showsRemaining ? l10n.deck.percentLeft(l10n.format.percent(Double(DeckLayout.remainingPercent(window.window.used)))) : nil,
            DeckLayout.resetTextA11y(for: window.window, now: now, style: resetStyle, l10n: l10n),
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}
