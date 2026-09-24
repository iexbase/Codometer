import CodometerCore
import CodometerL10n
import SwiftUI

/// systemLarge: every account with a meter per window, and the attention count in the header.
struct LargeLimitsView: View {
    let snapshot: WidgetSnapshot
    let states: [WidgetAccountState]
    let palette: WidgetPalette
    @Environment(\.widgetL10n) private var l10n

    nonisolated static let headerHeight: CGFloat = 22
    nonisolated static let headerSpacing: CGFloat = 12
    nonisolated static let accountHeight: CGFloat = 38
    nonisolated static let footerHeight: CGFloat = 15
    nonisolated static let statusHeight: CGFloat = 15
    /// A large widget has room for the forecast ghost on every ring.
    nonisolated static let forecastPolicy = WidgetForecastPolicy.always
    /// The side of an account's identity badge in a list row.
    nonisolated static let badgeSide: CGFloat = 20
    /// The badge beside the hero ring, where the name is drawn at 16 pt.
    nonisolated static let heroBadgeSide: CGFloat = 24
    /// What the hero's identity row leaves for the account's name: the column beside the 128 pt ring, less the badge
    /// and the gap after it. The plan chip sits on the line below precisely so that this stays wide enough for an
    /// ordinary two-word name in both languages (`WidgetCopyFitTests`).
    nonisolated static let heroNameWidth: CGFloat = 344 - 32 - 128 - 18 - heroBadgeSide - 5

    /// Vertical rhythm of the account list. A few accounts get the relaxed rhythm so the widget does not look empty;
    /// many accounts fall back to the compact one, and beyond that rows and then accounts are left out.
    struct Rhythm: Equatable {
        var accountSpacing: CGFloat
        var rowsInset: CGFloat
        var rowHeight: CGFloat
        var rowSpacing: CGFloat

        static let relaxed = Rhythm(accountSpacing: 22, rowsInset: 11, rowHeight: 17, rowSpacing: 10)
        static let compact = Rhythm(accountSpacing: 14, rowsInset: 8, rowHeight: 15, rowSpacing: 6)

        func metrics(availableHeight: CGFloat) -> WidgetLayoutPlan.Metrics {
            WidgetLayoutPlan.Metrics(
                availableHeight: Double(availableHeight),
                accountHeight: Double(LargeLimitsView.accountHeight),
                accountSpacing: Double(accountSpacing),
                rowsInset: Double(rowsInset),
                rowHeight: Double(rowHeight),
                rowSpacing: Double(rowSpacing),
                footerHeight: Double(LargeLimitsView.footerHeight)
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.headerSpacing) {
            header
                .frame(height: Self.headerHeight)
            if states.count == 1, let state = states.first {
                LargeSingleAccountView(state: state, palette: palette)
                status
                    .frame(height: Self.statusHeight)
            } else {
                list
            }
        }
    }

    private var list: some View {
        GeometryReader { proxy in
            let layout = layout(height: proxy.size.height)
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: layout.rhythm.accountSpacing) {
                    ForEach(layout.plan.entries, id: \.index) { entry in
                        LargeAccountBlock(state: states[entry.index], rowCount: entry.rowCount, rhythm: layout.rhythm, palette: palette)
                    }
                    if layout.plan.hiddenCount > 0 {
                        Text(verbatim: l10n.widget.moreAccounts(layout.plan.hiddenCount))
                            .font(WidgetFont.text(11.5, .medium))
                            .foregroundStyle(palette.secondary)
                            .frame(height: Self.footerHeight)
                    }
                }
                Spacer(minLength: 0)
                if layout.showsStatus {
                    status
                        .frame(height: Self.statusHeight)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }

    private struct Layout {
        let plan: WidgetLayoutPlan
        let rhythm: Rhythm
        let showsStatus: Bool
    }

    /// The relaxed rhythm when everything fits, else the compact one; the status line gives way when it would
    /// push an account out.
    private func layout(height: CGFloat) -> Layout {
        let rowCounts = states.map(\.windows.count)
        let priority = WidgetSelection.priorityOrder(states)
        let listHeight = max(0, height - Self.statusHeight - Self.headerSpacing)
        let relaxed = WidgetLayoutPlan(rowCounts: rowCounts, priority: priority, metrics: Rhythm.relaxed.metrics(availableHeight: listHeight))
        if relaxed.showsEverything(rowCounts: rowCounts) {
            return Layout(plan: relaxed, rhythm: .relaxed, showsStatus: true)
        }
        let compact = WidgetLayoutPlan(rowCounts: rowCounts, priority: priority, metrics: Rhythm.compact.metrics(availableHeight: listHeight))
        if compact.hiddenCount > 0 {
            let full = WidgetLayoutPlan(rowCounts: rowCounts, priority: priority, metrics: Rhythm.compact.metrics(availableHeight: height))
            if full.hiddenCount < compact.hiddenCount {
                return Layout(plan: full, rhythm: .compact, showsStatus: false)
            }
        }
        return Layout(plan: compact, rhythm: .compact, showsStatus: true)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(verbatim: l10n.widget.allName)
                .font(WidgetFont.text(15, .bold))
                .foregroundStyle(palette.primary)
            Spacer(minLength: 6)
            if snapshot.attentionCount > 0 {
                AttentionBadge(count: snapshot.attentionCount, palette: palette, size: 12, showsLabel: true)
            }
        }
    }

    /// When the newest numbers were read, and how many agents are working.
    private var status: some View {
        HStack(spacing: 4) {
            if let latest = states.compactMap(\.account.capturedAt).max() {
                let asOf = l10n.widget.latestAsOf
                Image(systemName: "clock")
                    .font(.system(size: 9.5, weight: .semibold))
                    .accessibilityHidden(true)
                Text("\(asOf.prefix)\(ReadingTime.text(latest, relativeTo: states.first?.date ?? latest, calendar: l10n.calendar))\(asOf.suffix)")
                    .font(WidgetFont.digits(11, .medium))
            }
            Spacer(minLength: 6)
            if snapshot.workingCount > 0 {
                Image(systemName: "circle.dotted")
                    .font(.system(size: 9.5, weight: .bold))
                    .accessibilityHidden(true)
                Text(verbatim: l10n.widget.working(snapshot.workingCount))
                    .font(WidgetFont.digits(11, .medium))
                    .accessibilityLabel(l10n.widget.workingA11y(snapshot.workingCount))
            }
        }
        .foregroundStyle(palette.secondary)
        .lineLimit(1)
    }
}

/// One account: a summary row with its ring and headline number, then its windows as meters.
private struct LargeAccountBlock: View {
    @Environment(\.widgetL10n) private var l10n
    let state: WidgetAccountState
    let rowCount: Int
    let rhythm: LargeLimitsView.Rhythm
    let palette: WidgetPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summary
                .frame(height: LargeLimitsView.accountHeight)
            let rows = state.windowsForDisplay(limit: rowCount)
            ForEach(Array(rows.enumerated()), id: \.element.id) { offset, window in
                WindowMeterRow(window: window, isStale: state.isStale, layout: .inline(titleWidth: 122), palette: palette)
                    .frame(height: rhythm.rowHeight)
                    .padding(.top, offset == 0 ? rhythm.rowsInset : rhythm.rowSpacing)
                    .padding(.leading, 48)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var summary: some View {
        HStack(spacing: 10) {
            WidgetRing(
                window: state.binding,
                isStale: state.isStale,
                lineWidth: 4.5,
                showsTicks: false,
                isWaiting: state.account.waitingCount > 0,
                forecastPolicy: LargeLimitsView.forecastPolicy,
                palette: palette
            ) {
                ProviderMark(provider: state.account.provider, color: palette.primary)
                    .frame(width: 13, height: 13)
                    .opacity(state.isBlocked ? 0.55 : 0.92)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    if let monogram = state.account.monogram {
                        WidgetAccountBadge(monogram: monogram, tint: state.account.tint, palette: palette, side: LargeLimitsView.badgeSide)
                    }
                    Text(verbatim: state.account.label)
                        .font(WidgetFont.text(13.5, .semibold))
                        .foregroundStyle(palette.primary)
                        .lineLimit(1)
                    if let plan = state.account.plan {
                        PlanChip(text: plan, palette: palette)
                    }
                    if state.account.waitingCount > 0 {
                        AttentionBadge(count: state.account.waitingCount, palette: palette, size: 10.5)
                    }
                }
                subtitle
                    .font(WidgetFont.text(11, .regular))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 1) {
                if state.isBlocked, !state.isStale, let reset = state.headlineReset {
                    let backIn = l10n.widget.backIn
                    Countdown.text(until: reset, at: state.date)
                        .font(WidgetFont.digits(15, .bold))
                        .foregroundStyle(palette.number(.exhausted, isStale: false))
                        .lineLimit(1)
                        .accessibilityLabel(Text("\(backIn.prefix)\(Countdown.text(until: reset, at: state.date))\(backIn.suffix)"))
                } else {
                    PercentText(
                        window: state.binding,
                        isStale: state.isStale,
                        size: 19,
                        forecastPolicy: LargeLimitsView.forecastPolicy,
                        palette: palette
                    )
                }
                StatusLine(state: state, palette: palette, size: 11, isCompact: true)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    /// The e-mail when shown, otherwise the window the headline number belongs to; the status line carries any problem.
    private var subtitle: Text {
        if let email = state.account.email { return Text(verbatim: email) }
        if let binding = state.binding { return Text(verbatim: binding.source.displayTitle) }
        return Text(verbatim: WidgetText.providerName(state.account.provider))
    }
}

/// One account fills the large widget: a hero ring beside its identity, then every window as a meter.
private struct LargeSingleAccountView: View {
    @Environment(\.widgetL10n) private var l10n
    let state: WidgetAccountState
    let palette: WidgetPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 18) {
                WidgetRing(
                    window: state.binding,
                    isStale: state.isStale,
                    lineWidth: 11,
                    isWaiting: state.account.waitingCount > 0,
                    forecastPolicy: LargeLimitsView.forecastPolicy,
                    palette: palette
                ) {
                    VStack(spacing: 3) {
                        ProviderMark(provider: state.account.provider, color: palette.secondary)
                            .frame(width: 16, height: 16)
                        if state.isBlocked, !state.isStale {
                            // The status line beside the ring says "Back in …".
                            Image(systemName: "lock.fill")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(palette.number(.exhausted, isStale: false))
                                .frame(height: 36)
                                .accessibilityHidden(true)
                        } else {
                            PercentText(
                                window: state.binding,
                                isStale: state.isStale,
                                size: 32,
                                forecastPolicy: LargeLimitsView.forecastPolicy,
                                palette: palette
                            )
                            .frame(height: 36)
                        }
                    }
                }
                .frame(width: 128, height: 128)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        if let monogram = state.account.monogram {
                            WidgetAccountBadge(
                                monogram: monogram,
                                tint: state.account.tint,
                                palette: palette,
                                side: LargeLimitsView.heroBadgeSide
                            )
                        }
                        Text(verbatim: state.account.label)
                            .font(WidgetFont.text(16, .semibold))
                            .foregroundStyle(palette.primary)
                            .lineLimit(1)
                    }
                    // The plan keeps the e-mail company on the line below rather than crowding the name: the identity
                    // badge already costs the column 29 pt, and a cut-off "Claude · Work" reads worse than a chip
                    // one line down. With no e-mail the chip has the line to itself; the column is still shorter
                    // than the 128 pt ring beside it, so nothing moves.
                    if state.account.email != nil || state.account.plan != nil {
                        HStack(spacing: 5) {
                            if let email = state.account.email {
                                Text(verbatim: email)
                                    .font(WidgetFont.text(11.5))
                                    .foregroundStyle(palette.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            if let plan = state.account.plan {
                                PlanChip(text: plan, palette: palette)
                            }
                        }
                    }
                    Text(verbatim: state.binding?.source.displayTitle ?? state.account.notice ?? l10n.common.noData)
                        .font(WidgetFont.text(12.5, .semibold))
                        .foregroundStyle(palette.primary)
                        .lineLimit(1)
                        .padding(.top, 8)
                    StatusLine(state: state, palette: palette, blockedCountdownShownElsewhere: false)
                    if state.account.waitingCount > 0 {
                        AttentionBadge(count: state.account.waitingCount, palette: palette, size: 11.5, showsLabel: true)
                            .padding(.top, 6)
                    }
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(state.windowsForDisplay(limit: 5)) { window in
                    WindowMeterRow(window: window, isStale: state.isStale, layout: .stacked, palette: palette)
                }
            }

            Spacer(minLength: 8)
        }
        .accessibilityElement(children: .combine)
    }
}
