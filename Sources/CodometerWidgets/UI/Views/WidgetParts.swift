import CodometerCore
import CodometerL10n
import SwiftUI

/// A countdown to a reset that the system keeps current without waking the extension, in the locale's words:
/// "2 hr, 13 min" | «2 ч 13 мин», then "47 minutes" within the last hour and "58 seconds" in the last minute, never
/// ticking seconds before that.
enum Countdown {
    static func text(until reset: Date, at date: Date) -> Text {
        switch WidgetCountdown.style(until: reset, at: date) {
        case .hoursAndDays:
            Text(reset, style: .relative)
        case .minutes:
            Text(.currentDate, format: .offset(to: reset, allowedFields: [.minute, .second], maxFieldCount: 1, sign: .never))
        }
    }
}

/// The reset or freshness line under a number: "Resets in 2 hr, 14 min", "As of 2:32 PM", "Limit reached".
///
/// Countdowns are live system text (`Countdown`), so the extension does no work between timeline entries. The symbol
/// is decorative for VoiceOver, except in the compact form, whose spoken label says what the symbol means.
struct StatusLine: View {
    /// What precedes a running countdown unless the line is compact.
    enum ResetWording {
        /// "Resets in 2 hr" | «сброс через 2 ч».
        case full
        /// Under a title that already names the window: "Resets in 2 hr" | «через 2 ч».
        case short
    }

    @Environment(\.widgetL10n) private var l10n
    let state: WidgetAccountState
    let palette: WidgetPalette
    var size: CGFloat = 11.5
    /// Blocked accounts show their countdown as the headline, so the line only says why.
    var blockedCountdownShownElsewhere = true
    /// Drops the words where the symbol already says them: "↻ 4 days, 4 hr", "🔒 2 hr, 13 min". VoiceOver still hears
    /// them.
    var isCompact = false
    var resetWording = ResetWording.full

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: size - 2, weight: .semibold))
                .accessibilityHidden(true)
            text
                .font(WidgetFont.digits(size, .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenText)
    }

    private var symbol: String {
        if !state.hasReading { return state.account.notice == nil ? "hourglass" : "exclamationmark.triangle.fill" }
        if state.isStale { return "clock" }
        if state.isBlocked { return "lock.fill" }
        return "arrow.counterclockwise"
    }

    private var color: Color {
        if state.hasReading, !state.isStale, state.isBlocked { return palette.number(.exhausted, isStale: false) }
        return palette.secondary
    }

    private var text: Text {
        line(isSpoken: false)
    }

    /// The compact countdown spoken with its words.
    private var spokenText: Text {
        line(isSpoken: true)
    }

    private func line(isSpoken: Bool) -> Text {
        let widget = l10n.widget
        if !state.hasReading {
            return Text(verbatim: state.account.notice ?? widget.waitingForData)
        }
        if state.isStale, let capturedAt = state.account.capturedAt {
            let slot = widget.staleAsOf
            return Text("\(slot.prefix)\(ReadingTime.text(capturedAt, relativeTo: state.date, calendar: l10n.calendar))\(slot.suffix)")
        }
        if state.isBlocked {
            guard !blockedCountdownShownElsewhere, let reset = state.headlineReset else { return Text(verbatim: widget.limitReached) }
            let countdown = Countdown.text(until: reset, at: state.date)
            if isCompact, !isSpoken {
                return countdown
            }
            let slot = widget.backIn
            return Text("\(slot.prefix)\(countdown)\(slot.suffix)")
        }
        guard let reset = state.headlineReset else { return Text(verbatim: widget.noResetTime) }
        let countdown = Countdown.text(until: reset, at: state.date)
        if isCompact, !isSpoken {
            return countdown
        }
        let slot = isCompact || resetWording == .full ? widget.resetsIn : widget.resetsInShort
        return Text("\(slot.prefix)\(countdown)\(slot.suffix)")
    }
}

/// "2:32 PM" for a reading from the entry's day, "Sep 15" for an older one, so old numbers never pass for today's.
enum ReadingTime {
    /// `calendar` decides what "the same day" is: the widget localizer's, in the system time zone.
    static func text(_ date: Date, relativeTo reference: Date, calendar: Calendar) -> Text {
        if calendar.isDate(date, inSameDayAs: reference) {
            return Text(date, style: .time)
        }
        return Text(date, format: .dateTime.day().month(.abbreviated))
    }
}

/// A usage number with a smaller percent sign, or "—" without a reading; VoiceOver hears "64% used" or "No data".
///
/// Always drawn at its own size, never squeezed with `minimumScaleFactor`: text that was once scaled to fit poisons
/// SwiftUI's text layout cache, and the same number drawn later at another size — the medium widget after the small
/// one, in the same rendering process — comes out as "…". Where room is tight, `FittingPercentText` picks a size
/// that fits.
///
/// `forecastPolicy` is the one its ring draws with, so what VoiceOver hears and what the ghost arc shows always
/// agree.
struct PercentText: View {
    @Environment(\.widgetL10n) private var l10n
    let window: WidgetWindowState?
    let isStale: Bool
    let size: CGFloat
    var forecastPolicy = WidgetForecastPolicy.never
    let palette: WidgetPalette

    var body: some View {
        if let window {
            HStack(alignment: .firstTextBaseline, spacing: size * 0.02) {
                Text(verbatim: WidgetText.percentNumber(window.window.used))
                    .font(WidgetFont.digits(size, .bold))
                Text(verbatim: "%")
                    .font(WidgetFont.text(size * 0.5, .bold))
                    .opacity(0.72)
            }
            .foregroundStyle(palette.number(window.band, isStale: isStale))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenUsage(window))
        } else {
            Text(verbatim: "—")
                .font(WidgetFont.digits(size * 0.72, .medium))
                .foregroundStyle(palette.secondary.opacity(0.7))
                .accessibilityLabel(l10n.common.noData)
        }
    }

    /// The number, plus where the forecast ghost says usage lands — only when the ring actually draws it, and never
    /// for a stale reading, which has no ghost.
    private func spokenUsage(_ window: WidgetWindowState) -> String {
        let percent = l10n.format.percent(window.window.used.value)
        guard !isStale, let forecast = window.forecast, forecastPolicy.draws(forecast) else {
            return l10n.widget.percentUsedA11y(percent)
        }
        guard !forecast.reachesLimit else { return l10n.widget.percentUsedForecastLimitA11y(percent) }
        return l10n.widget.percentUsedForecastA11y(percent, projected: l10n.format.percent(forecast.projectedUsed))
    }
}

/// The largest of `sizes` at which the number fits the offered width, without scaling any text.
struct FittingPercentText: View {
    let window: WidgetWindowState?
    let isStale: Bool
    /// Largest first.
    let sizes: [CGFloat]
    var forecastPolicy = WidgetForecastPolicy.never
    let palette: WidgetPalette

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(sizes, id: \.self) { size in
                PercentText(window: window, isStale: isStale, size: size, forecastPolicy: forecastPolicy, palette: palette)
            }
        }
    }
}

/// One window as a labelled meter.
struct WindowMeterRow: View {
    enum Layout {
        /// Title, meter and percent on one line.
        case inline(titleWidth: CGFloat)
        /// Title and percent above a full-width meter.
        case stacked
    }

    let window: WidgetWindowState
    let isStale: Bool
    let layout: Layout
    let palette: WidgetPalette

    var body: some View {
        switch layout {
        case .inline(let titleWidth):
            HStack(spacing: 8) {
                title
                    .frame(width: titleWidth, alignment: .leading)
                WidgetMeter(window: window, isStale: isStale, height: 5, palette: palette)
                percent
                    .frame(width: 38, alignment: .trailing)
            }
        case .stacked:
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    title
                    Spacer(minLength: 4)
                    percent
                }
                WidgetMeter(window: window, isStale: isStale, height: 4.5, palette: palette)
            }
        }
    }

    private var title: some View {
        Text(verbatim: window.source.displayTitle)
            .font(WidgetFont.text(11.5, .medium))
            .foregroundStyle(palette.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.9)
    }

    private var percent: some View {
        Text(verbatim: WidgetText.percent(window.window.used))
            .font(WidgetFont.digits(11.5, .semibold))
            .foregroundStyle(palette.number(window.band, isStale: isStale))
            .lineLimit(1)
    }
}
