import CodometerCore
import CodometerL10n
import SwiftUI
import WidgetKit

/// The strip layout (`WidgetLayout.strip`) for the medium and large widgets of every kind: a header with the scope's
/// mark and name, the weekly window as a headline of what is *left*, and a compact tile for every other window.
///
/// Medium: the headline beside a two-by-two grid of tiles. Large with one account: the headline beside the account's
/// identity, then up to two rows of three tiles and the freshness line. Large with several accounts: the headline,
/// then one row per account — its name and its own tiles — and "N more accounts" when they do not all fit.
/// `WidgetStripPlan` chooses the headline, groups tiles shared by several accounts and counts the overflow, so the
/// view only places what the plan hands it.
///
/// Every countdown is the system's live text (`Countdown`), which is why a tile gives it a line of its own: the
/// widest one ("6 days, 22 hr") needs the tile's whole width at a size that is still readable.
struct StripLimitsView: View {
    let scope: WidgetScope
    /// Already scoped to `scope`.
    let snapshot: WidgetSnapshot
    let states: [WidgetAccountState]
    let family: WidgetFamily
    let palette: WidgetPalette
    @Environment(\.widgetL10n) private var l10n

    nonisolated static let mediumHeaderHeight: CGFloat = 18
    nonisolated static let largeHeaderHeight: CGFloat = 20
    /// Tiles the medium widget holds: two per row, two rows.
    nonisolated static let mediumChipLimit = 4
    nonisolated static let mediumChipsPerRow = 2
    /// Tiles the large widget holds for one account: three per row, two rows.
    nonisolated static let largeChipLimit = 6
    nonisolated static let largeChipsPerRow = 3
    /// Tiles in one account's row of the large widget with several accounts.
    nonisolated static let largeRowChipLimit = 3
    /// Accounts the large widget lists under the headline; the rest are counted in a footer.
    nonisolated static let largeAccountLimit = 2
    /// The headline column of the medium widget; the tiles take the rest.
    nonisolated static let mediumHeroWidth: CGFloat = 120
    nonisolated static let chipSpacing: CGFloat = 8

    private var isLarge: Bool { family == .systemLarge }

    var body: some View {
        if isLarge {
            large
        } else {
            medium
        }
    }

    // MARK: Medium

    private var medium: some View {
        let plan = WidgetStripPlan(states: states, chipLimit: Self.mediumChipLimit)
        return VStack(alignment: .leading, spacing: 6) {
            StripHeader(scope: scope, snapshot: snapshot, states: states, height: Self.mediumHeaderHeight, palette: palette)
                .frame(height: Self.mediumHeaderHeight)
            HStack(alignment: .center, spacing: 10) {
                StripHero(plan: plan, fallback: WidgetSelection.mostConstrained(states), numberSize: 34, isStacked: true, palette: palette)
                    .frame(width: Self.mediumHeroWidth, alignment: .leading)
                StripChipGrid(chips: plan.chips, overflow: plan.overflow, perRow: Self.mediumChipsPerRow, metrics: .medium, palette: palette)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: Large

    @ViewBuilder
    private var large: some View {
        if states.count == 1, let state = states.first {
            largeSingle(state)
        } else {
            largeList
        }
    }

    private func largeSingle(_ state: WidgetAccountState) -> some View {
        let plan = WidgetStripPlan(states: states, chipLimit: Self.largeChipLimit)
        return VStack(alignment: .leading, spacing: 0) {
            StripHeader(scope: scope, snapshot: snapshot, states: states, height: Self.largeHeaderHeight, palette: palette)
                .frame(height: Self.largeHeaderHeight)
            HStack(alignment: .center, spacing: 14) {
                StripHero(plan: plan, fallback: state, numberSize: 42, isStacked: false, palette: palette)
                    .frame(maxWidth: .infinity, alignment: .leading)
                StripIdentity(state: state, scope: scope, showsLabel: !StripHeader.namesAccount(state, scope: scope, states: states), palette: palette)
                    .frame(maxWidth: 150, alignment: .trailing)
            }
            .padding(.top, 16)
            .padding(.bottom, 20)
            StripChipGrid(chips: plan.chips, overflow: plan.overflow, perRow: Self.largeChipsPerRow, metrics: .large, palette: palette)
            Spacer(minLength: 8)
            StripStatus(snapshot: snapshot, states: states, palette: palette)
                .frame(height: 15)
        }
    }

    private var largeList: some View {
        let plan = WidgetStripPlan(states: states, chipLimit: Self.largeChipLimit)
        let shown = WidgetSelection.featured(states, limit: Self.largeAccountLimit)
        let hidden = states.count - shown.count
        return VStack(alignment: .leading, spacing: 0) {
            StripHeader(scope: scope, snapshot: snapshot, states: states, height: Self.largeHeaderHeight, palette: palette)
                .frame(height: Self.largeHeaderHeight)
            HStack(alignment: .center, spacing: 12) {
                StripHero(plan: plan, fallback: WidgetSelection.mostConstrained(states), numberSize: 34, isStacked: false, palette: palette)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let hero = plan.hero {
                    StripIdentity(state: hero.account, scope: scope, showsLabel: true, palette: palette)
                        .frame(maxWidth: 150, alignment: .trailing)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 12)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(shown) { state in
                    StripAccountRow(state: state, hero: plan.hero, scope: scope, palette: palette)
                }
                if hidden > 0 {
                    Text(verbatim: l10n.widget.moreAccounts(hidden))
                        .font(WidgetFont.text(11.5, .medium))
                        .foregroundStyle(palette.secondary)
                        .frame(height: 14)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Header

/// The scope's mark and name; a single provider account adds its own name and plan; agents waiting or working sit
/// at the trailing end.
private struct StripHeader: View {
    @Environment(\.widgetL10n) private var l10n
    let scope: WidgetScope
    let snapshot: WidgetSnapshot
    let states: [WidgetAccountState]
    let height: CGFloat
    let palette: WidgetPalette

    private var single: WidgetAccountState? { states.count == 1 ? states.first : nil }

    /// Whether the header already names `state`: a provider's only account, whose label (less the provider's name)
    /// is shown after the title — or is nothing but the provider's name.
    nonisolated static func namesAccount(_ state: WidgetAccountState, scope: WidgetScope, states: [WidgetAccountState]) -> Bool {
        scope.provider != nil && states.count == 1
    }

    var body: some View {
        HStack(spacing: 6) {
            mark
            Text(verbatim: title)
                .font(WidgetFont.text(13, .bold))
                .foregroundStyle(palette.primary)
                .lineLimit(1)
            if let provider = scope.provider, let single {
                let label = WidgetText.labelWithinProvider(single.account.label, provider: provider)
                if label != WidgetText.providerName(provider) {
                    Text(verbatim: label)
                        .font(WidgetFont.text(12, .medium))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 6)
            if let single {
                if let plan = single.account.plan {
                    PlanChip(text: plan, palette: palette)
                }
                ActivityBadge(state: single, palette: palette, size: 11)
            } else if snapshot.attentionCount > 0 {
                AttentionBadge(count: snapshot.attentionCount, palette: palette, size: 11, showsLabel: true)
            } else if snapshot.workingCount > 0 {
                WorkingBadge(count: snapshot.workingCount, palette: palette, size: 11)
            }
        }
    }

    private var title: String {
        switch scope {
        case .all: l10n.widget.allName
        case .provider(let provider): WidgetText.providerName(provider)
        }
    }

    @ViewBuilder
    private var mark: some View {
        switch scope {
        case .provider(let provider):
            ProviderBadgeMark(provider: provider, palette: palette, side: height)
        case .all:
            ZStack {
                Circle().fill(palette.chipFill)
                Image(systemName: "gauge.with.needle")
                    .font(.system(size: height * 0.5, weight: .semibold))
                    .foregroundStyle(palette.primary)
            }
            .frame(width: height, height: height)
            .widgetAccentable()
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Hero

/// The headline: the window's title, what is left of it as a big number with "left", a slim meter, and what is used
/// and when it resets — on one line, or stacked where the column is narrow. Without a headline window the account's
/// notice stands in.
private struct StripHero: View {
    @Environment(\.widgetL10n) private var l10n
    let plan: WidgetStripPlan
    /// The account whose notice is shown when no window can be the headline.
    let fallback: WidgetAccountState?
    let numberSize: CGFloat
    /// "36% used" and "Resets in 5 days" always as two lines (the medium widget's narrow column); otherwise one line
    /// where it fits.
    let isStacked: Bool
    let palette: WidgetPalette

    var body: some View {
        if let hero = plan.hero {
            headline(hero)
        } else if let fallback {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: l10n.common.noData)
                    .font(WidgetFont.text(14, .semibold))
                    .foregroundStyle(palette.primary)
                StatusLine(state: fallback, palette: palette, size: 11)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func headline(_ hero: WidgetStripPlan.Hero) -> some View {
        let state = hero.account
        let window = hero.window
        let remaining = WidgetStripPlan.remaining(of: window)
        let color = palette.number(window.band, isStale: state.isStale)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(verbatim: window.source.displayTitle)
                    .font(WidgetFont.text(10.5, .semibold))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if hero.accountCount > 1 {
                    SharingBadge(count: hero.accountCount, palette: palette)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    number(remaining, color: color)
                    unit
                }
                VStack(alignment: .leading, spacing: 0) {
                    number(remaining, color: color)
                    unit
                }
            }
            WidgetMeter(window: window, isStale: state.isStale, height: 3, palette: palette)
                .padding(.top, 2)
                .padding(.bottom, 1)
            if isStacked {
                stackedSubline(hero)
            } else {
                // One line where it fits ("36% used · in 5 days, 16 hr"); the two-line form where the identity column
                // beside it, or a long Russian countdown, leaves too little room.
                ViewThatFits(in: .horizontal) {
                    subline(hero)
                    stackedSubline(hero)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(hero, remaining: remaining))
    }

    private func number(_ remaining: Percentage, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(verbatim: WidgetText.percentNumber(remaining))
                .font(WidgetFont.digits(numberSize, .bold))
            Text(verbatim: "%")
                .font(WidgetFont.text(numberSize * 0.46, .bold))
                .opacity(0.72)
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .widgetAccentable()
    }

    private var unit: some View {
        Text(verbatim: l10n.widget.leftUnit)
            .font(WidgetFont.text(11.5, .medium))
            .foregroundStyle(palette.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    /// What the caption under the number says, before it is set as one line or two.
    private enum Caption {
        /// "🕓 As of 2:32 PM": the reading is stale, the countdown means nothing.
        case stale(Date)
        /// "🔒 Back in …": the window itself is used up.
        case exhausted(reset: Date)
        /// "⟳ 36% used · in …".
        case running(used: String, reset: Date)
        /// "⟳ 36% used": no reset time is known.
        case noReset(used: String)
    }

    private func caption(_ hero: WidgetStripPlan.Hero) -> Caption {
        let state = hero.account
        let window = hero.window
        let used = l10n.format.percent(window.window.used.value)
        if state.isStale, let capturedAt = state.account.capturedAt {
            return .stale(capturedAt)
        }
        if window.isExhausted, !state.isStale, let reset = window.window.resetsAt {
            return .exhausted(reset: reset)
        }
        if let reset = window.window.resetsAt {
            return .running(used: used, reset: reset)
        }
        return .noReset(used: used)
    }

    private func line(symbol: String, _ text: Text, isExhausted: Bool = false) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 8.5, weight: .semibold))
            text
                .font(WidgetFont.digits(10.5, .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(isExhausted ? palette.number(.exhausted, isStale: false) : palette.secondary)
    }

    /// "⟳ 36% used · in 5 days, 16 hr", "🔒 Back in 6 days", "🕓 As of 2:32 PM".
    @ViewBuilder
    private func subline(_ hero: WidgetStripPlan.Hero) -> some View {
        let widget = l10n.widget
        let date = hero.account.date
        switch caption(hero) {
        case .stale(let capturedAt):
            let slot = widget.staleAsOf
            line(symbol: "clock", Text("\(slot.prefix)\(ReadingTime.text(capturedAt, relativeTo: date, calendar: l10n.calendar))\(slot.suffix)"))
        case .exhausted(let reset):
            let slot = widget.backIn
            line(symbol: "lock.fill", Text("\(slot.prefix)\(Countdown.text(until: reset, at: date))\(slot.suffix)"), isExhausted: true)
        case .running(let used, let reset):
            let slot = widget.usedResetsIn(used)
            line(symbol: "arrow.counterclockwise", Text("\(slot.prefix)\(Countdown.text(until: reset, at: date))\(slot.suffix)"))
        case .noReset(let used):
            line(symbol: "arrow.counterclockwise", Text(verbatim: widget.usedNoReset(used)))
        }
    }

    /// The same, with the usage and the reset on two lines: "⟳ 36% used" over "Resets in 5 days, 16 hr".
    @ViewBuilder
    private func stackedSubline(_ hero: WidgetStripPlan.Hero) -> some View {
        let widget = l10n.widget
        let date = hero.account.date
        switch caption(hero) {
        case .running(let used, let reset):
            let slot = widget.resetsInShort
            VStack(alignment: .leading, spacing: 2) {
                line(symbol: "arrow.counterclockwise", Text(verbatim: widget.usedNoReset(used)))
                Text("\(slot.prefix)\(Countdown.text(until: reset, at: date))\(slot.suffix)")
                    .font(WidgetFont.digits(10.5, .medium))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        case .stale, .exhausted, .noReset:
            subline(hero)
        }
    }

    private func spoken(_ hero: WidgetStripPlan.Hero, remaining: Percentage) -> Text {
        let widget = l10n.widget
        let window = hero.window
        let base = widget.percentLeftA11y(
            window.source.displayTitle,
            left: l10n.format.percent(remaining.value),
            used: l10n.format.percent(window.window.used.value)
        )
        let sharing = hero.accountCount > 1 ? ", \(widget.accountsSharing(hero.accountCount))" : ""
        let date = hero.account.date
        switch caption(hero) {
        case .stale(let capturedAt):
            let slot = widget.staleAsOf
            return Text("\(base), \(slot.prefix)\(ReadingTime.text(capturedAt, relativeTo: date, calendar: l10n.calendar))\(slot.suffix)\(sharing)")
        case .exhausted(let reset):
            let slot = widget.backIn
            return Text("\(base), \(slot.prefix)\(Countdown.text(until: reset, at: date))\(slot.suffix)\(sharing)")
        case .running(_, let reset):
            let slot = widget.resetsIn
            return Text("\(base), \(slot.prefix)\(Countdown.text(until: reset, at: date))\(slot.suffix)\(sharing)")
        case .noReset:
            return Text(verbatim: base + sharing)
        }
    }
}

// MARK: - Identity

/// The account beside the large widget's headline: its name and badge, its e-mail, and — only when the headline does
/// not already say so — that it is blocked or stale. The reset countdown is the headline's business.
private struct StripIdentity: View {
    let state: WidgetAccountState
    let scope: WidgetScope
    /// `false` when the header already names the account (a provider's only account).
    let showsLabel: Bool
    let palette: WidgetPalette

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            if showsLabel {
                HStack(spacing: 5) {
                    Text(verbatim: label)
                        .font(WidgetFont.text(13, .semibold))
                        .foregroundStyle(palette.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    badge
                }
            }
            if let email = state.account.email {
                Text(verbatim: email)
                    .font(WidgetFont.text(10.5))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if state.hasReading, state.isBlocked || state.isStale {
                StatusLine(state: state, palette: palette, size: 10.5, blockedCountdownShownElsewhere: false, isCompact: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var badge: some View {
        if let monogram = state.account.monogram {
            WidgetAccountBadge(monogram: monogram, tint: state.account.tint, palette: palette, side: 18)
        } else {
            ProviderBadgeMark(provider: state.account.provider, palette: palette, side: 18)
        }
    }

    private var label: String {
        guard let provider = scope.provider else { return state.account.label }
        return WidgetText.labelWithinProvider(state.account.label, provider: provider)
    }
}

// MARK: - Account rows

/// One account of the large widget's list: its identity on a line, its tiles on the next.
private struct StripAccountRow: View {
    let state: WidgetAccountState
    let hero: WidgetStripPlan.Hero?
    let scope: WidgetScope
    let palette: WidgetPalette

    var body: some View {
        let fitted = WidgetStripPlan.chips(for: state, hero: hero, limit: StripLimitsView.largeRowChipLimit)
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                if let monogram = state.account.monogram {
                    WidgetAccountBadge(monogram: monogram, tint: state.account.tint, palette: palette, side: 16)
                } else {
                    ProviderBadgeMark(provider: state.account.provider, palette: palette, side: 16)
                }
                Text(verbatim: state.account.label)
                    .font(WidgetFont.text(12, .semibold))
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let plan = state.account.plan {
                    PlanChip(text: plan, palette: palette)
                }
                Spacer(minLength: 4)
                if state.hasReading {
                    ActivityBadge(state: state, palette: palette, size: 10.5)
                } else {
                    StatusLine(state: state, palette: palette, size: 10.5)
                }
            }
            .frame(height: 18)
            if state.hasReading {
                StripChipGrid(chips: fitted.chips, overflow: fitted.overflow, perRow: StripLimitsView.largeRowChipLimit, metrics: .row, palette: palette)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Chips

/// The fixed size of a tile and the type inside it, per place in the widget.
struct StripChipMetrics: Hashable, Sendable {
    let height: CGFloat
    let padding: CGFloat
    let titleSize: CGFloat
    let percentSize: CGFloat
    let countdownSize: CGFloat

    /// The medium widget's two-by-two grid.
    static let medium = StripChipMetrics(height: 50, padding: 6, titleSize: 10, percentSize: 12.5, countdownSize: 9)
    /// One account's tiles across the large widget.
    static let large = StripChipMetrics(height: 60, padding: 8, titleSize: 11, percentSize: 15, countdownSize: 10)
    /// An account's row in the large widget's list.
    static let row = StripChipMetrics(height: 48, padding: 5, titleSize: 10, percentSize: 12.5, countdownSize: 9)
}

/// Tiles in rows of `perRow`, the overflow tile last; every tile the same fixed size.
private struct StripChipGrid: View {
    let chips: [WidgetStripPlan.Chip]
    let overflow: Int
    let perRow: Int
    let metrics: StripChipMetrics
    let palette: WidgetPalette

    private enum Cell: Identifiable {
        case chip(WidgetStripPlan.Chip)
        case overflow(Int)

        var id: String {
            switch self {
            case .chip(let chip): chip.id
            case .overflow: "overflow"
            }
        }
    }

    private var rows: [[Cell]] {
        var cells = chips.map(Cell.chip)
        if overflow > 0 {
            cells.append(.overflow(overflow))
        }
        return stride(from: 0, to: cells.count, by: max(1, perRow)).map { Array(cells[$0..<min($0 + perRow, cells.count)]) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StripLimitsView.chipSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: StripLimitsView.chipSpacing) {
                    ForEach(row) { cell in
                        switch cell {
                        case .chip(let chip):
                            StripChip(chip: chip, metrics: metrics, palette: palette)
                        case .overflow(let count):
                            StripOverflowChip(count: count, palette: palette)
                        }
                    }
                    // Fills the places of a short last row, so every tile keeps the width of a full row.
                    ForEach(0..<max(0, perRow - row.count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
                .frame(height: metrics.height)
            }
        }
    }
}

/// One window: its title (and how many accounts share it), its usage in the band colour, and the reset countdown on
/// a line of its own.
private struct StripChip: View {
    @Environment(\.widgetL10n) private var l10n
    let chip: WidgetStripPlan.Chip
    let metrics: StripChipMetrics
    let palette: WidgetPalette

    private var state: WidgetAccountState { chip.account }
    private var window: WidgetWindowState { chip.window }
    private var isExhausted: Bool { window.isExhausted && !state.isStale }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: chip.title)
                .font(WidgetFont.text(metrics.titleSize, .semibold))
                .foregroundStyle(palette.primary.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            // The badge keeps the usage company rather than the title, which needs every point of the tile's width.
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: WidgetText.percent(window.window.used))
                    .font(WidgetFont.digits(metrics.percentSize, .bold))
                    .foregroundStyle(palette.number(window.band, isStale: state.isStale))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                if chip.accountCount > 1 {
                    SharingBadge(count: chip.accountCount, palette: palette)
                }
            }
            Spacer(minLength: 0)
            countdown
        }
        .padding(.horizontal, metrics.padding + 2)
        .padding(.vertical, metrics.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(StripTile(palette: palette))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// "⟳ 1 day, 14 hr", "🔒 2 hr, 13 min" for an exhausted window, "🕓 2:32 PM" for a stale reading.
    @ViewBuilder
    private var countdown: some View {
        if let text = countdownText {
            HStack(spacing: 2.5) {
                Image(systemName: symbol)
                    .font(.system(size: metrics.countdownSize - 1.5, weight: .semibold))
                text
                    .font(WidgetFont.digits(metrics.countdownSize, .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isExhausted ? palette.number(.exhausted, isStale: false) : palette.secondary)
        }
    }

    private var symbol: String {
        if state.isStale { return "clock" }
        return isExhausted ? "lock.fill" : "arrow.counterclockwise"
    }

    private var countdownText: Text? {
        if state.isStale {
            guard let capturedAt = state.account.capturedAt else { return nil }
            return ReadingTime.text(capturedAt, relativeTo: state.date, calendar: l10n.calendar)
        }
        guard let reset = window.window.resetsAt else { return nil }
        return Countdown.text(until: reset, at: state.date)
    }

    private var spoken: Text {
        let widget = l10n.widget
        let base = widget.chipA11y(chip.title, used: l10n.format.percent(window.window.used.value))
        let sharing = chip.accountCount > 1 ? ", \(widget.accountsSharing(chip.accountCount))" : ""
        if state.isStale, let capturedAt = state.account.capturedAt {
            let slot = widget.staleAsOf
            return Text("\(base), \(slot.prefix)\(ReadingTime.text(capturedAt, relativeTo: state.date, calendar: l10n.calendar))\(slot.suffix)\(sharing)")
        }
        guard let reset = window.window.resetsAt else { return Text(verbatim: base + sharing) }
        let slot = window.isExhausted ? widget.backIn : widget.resetsIn
        return Text("\(base), \(slot.prefix)\(Countdown.text(until: reset, at: state.date))\(slot.suffix)\(sharing)")
    }
}

/// "+2": windows that did not get a tile.
private struct StripOverflowChip: View {
    @Environment(\.widgetL10n) private var l10n
    let count: Int
    let palette: WidgetPalette

    var body: some View {
        Text(verbatim: "+\(count)")
            .font(WidgetFont.digits(14, .semibold))
            .foregroundStyle(palette.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(StripTile(palette: palette))
            .accessibilityLabel(l10n.widget.moreWindows(count))
    }
}

/// "⊞ 2": the tile stands for that many accounts.
private struct SharingBadge: View {
    @Environment(\.widgetL10n) private var l10n
    let count: Int
    let palette: WidgetPalette

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 7.5, weight: .semibold))
            Text(verbatim: "\(count)")
                .font(WidgetFont.digits(9, .semibold))
        }
        .foregroundStyle(palette.secondary)
        .padding(.horizontal, 4)
        .padding(.vertical, 1.5)
        .background(Capsule().fill(palette.chipFill))
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(l10n.widget.accountsSharing(count))
    }
}

/// The tile behind a chip: a soft fill, a faint diagonal hatch and a hairline edge. The hatch is drawn in the text
/// colour at a whisper of opacity, so it survives the accented and vibrant rendering modes without meaning anything.
private struct StripTile: View {
    let palette: WidgetPalette

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 11, style: .continuous) }

    var body: some View {
        ZStack {
            shape.fill(palette.chipFill)
            HatchShape(spacing: 5)
                .stroke(palette.primary.opacity(palette.style == .fullColor ? 0.045 : 0.06), lineWidth: 0.7)
                .clipShape(shape)
            shape.strokeBorder(palette.hairline, lineWidth: 0.5)
        }
    }
}

/// Parallel diagonal lines, `spacing` apart, across the whole rect.
private struct HatchShape: Shape {
    let spacing: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step = max(2, spacing)
        var offset = -rect.height
        while offset < rect.width {
            path.move(to: CGPoint(x: rect.minX + offset, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + offset + rect.height, y: rect.minY))
            offset += step
        }
        return path
    }
}

// MARK: - Status

/// When the newest numbers were read, and how many agents are working: the large widget's last line.
private struct StripStatus: View {
    @Environment(\.widgetL10n) private var l10n
    let snapshot: WidgetSnapshot
    let states: [WidgetAccountState]
    let palette: WidgetPalette

    var body: some View {
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
