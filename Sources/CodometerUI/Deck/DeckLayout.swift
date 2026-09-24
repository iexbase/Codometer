import CodometerCore
import CodometerL10n
import CoreGraphics
import Foundation

/// Switches for deck features.
public enum DeckFeatures {
    /// The Timeline page (session lanes and attribution), fed by the live-recorded history.
    public static let showsTimelinePage = true
}

/// The deck's pages.
enum DeckPage: String, CaseIterable, Identifiable, Hashable {
    case overview
    case timeline

    var id: String { rawValue }

    func title(l10n: Localizer) -> String {
        switch self {
        case .overview: l10n.deck.overview
        case .timeline: l10n.deck.timeline
        }
    }

    /// The pages the deck offers with the current feature switches.
    static func available(showsTimeline: Bool) -> [DeckPage] {
        showsTimeline ? [.overview, .timeline] : [.overview]
    }
}

/// One entry of the deck's group filter: "All" (`id == nil`) or a group.
struct GroupFilterOption: Hashable, Identifiable {
    let id: AccountGroupID?
    let title: String
}

/// Pure decisions behind the deck's layout, kept out of the views so they can be tested.
enum DeckLayout {
    static let maximumSessions = 4
    static let maximumAttentionCards = 3
    /// Width reserved for elapsed times such as "12h 40m" | «12 ч 40 мин» in this language, so a ticking clock never
    /// moves its neighbours.
    static func elapsedTemplate(l10n: Localizer) -> String {
        l10n.deck.elapsedTemplate
    }

    /// History for windows without a known start is requested from a time rounded down to this step,
    /// so the request does not change with every clock tick.
    static let historyRoundingStep: TimeInterval = 15 * 60

    /// The pages the deck offers with the current feature switches.
    static var availablePages: [DeckPage] {
        DeckPage.available(showsTimeline: DeckFeatures.showsTimelinePage)
    }

    /// The pages for a detail level: the essentials keep the overview only.
    static func availablePages(detail: DeckDetail) -> [DeckPage] {
        detail == .full ? availablePages : [.overview]
    }

    // MARK: Windows

    /// A group of tiles: the main bucket's other windows (no title) or another bucket's windows.
    struct TileSection: Equatable, Identifiable {
        let id: String
        /// `nil` for the main bucket.
        let title: String?
        let isLimitReached: Bool
        let tiles: [WindowPresentation]
    }

    struct WindowSections: Equatable {
        /// The headline primary window, shown large.
        let hero: WindowPresentation?
        let sections: [TileSection]
    }

    /// Splits an account's windows into the hero (the headline primary window) and tile sections:
    /// the main bucket's remaining windows first, then one section per other bucket in provider order.
    /// Only windows the provider reported appear.
    static func windowSections(
        windows: [WindowPresentation],
        primaryWindowID: String?,
        limitReachedBuckets: Set<String> = []
    ) -> WindowSections {
        let main = windows.filter(\.isMainBucket)
        let hero = main.first { $0.window.id == primaryWindowID } ?? main.first
        var sections: [TileSection] = []
        let mainTiles = main.filter { $0.id != hero?.id }
        if !mainTiles.isEmpty {
            sections.append(TileSection(id: mainTiles[0].bucketID, title: nil, isLimitReached: false, tiles: mainTiles))
        }
        var order: [String] = []
        var grouped: [String: [WindowPresentation]] = [:]
        for window in windows where !window.isMainBucket {
            if grouped[window.bucketID] == nil { order.append(window.bucketID) }
            grouped[window.bucketID, default: []].append(window)
        }
        for bucketID in order {
            guard let tiles = grouped[bucketID], let first = tiles.first else { continue }
            sections.append(TileSection(
                id: bucketID,
                title: first.bucketTitle ?? bucketID,
                isLimitReached: limitReachedBuckets.contains(bucketID),
                tiles: tiles
            ))
        }
        return WindowSections(hero: hero, sections: sections)
    }

    /// The essentials page: every window as a tile, the headline primary window first and alone on its row, then the
    /// main bucket's other windows, then one section per other bucket. Nothing is shown large.
    static func essentialSections(
        windows: [WindowPresentation],
        primaryWindowID: String?,
        limitReachedBuckets: Set<String> = []
    ) -> [TileSection] {
        let full = windowSections(windows: windows, primaryWindowID: primaryWindowID, limitReachedBuckets: limitReachedBuckets)
        guard let hero = full.hero else { return full.sections }
        return [TileSection(id: "primary." + hero.id, title: nil, isLimitReached: false, tiles: [hero])] + full.sections
    }

    /// Tiles in rows of two; an odd last tile gets a row to itself (and spans both columns).
    static func rows<T>(_ items: [T], columns: Int = 2) -> [[T]] {
        let columns = max(1, columns)
        return stride(from: 0, to: items.count, by: columns).map { start in
            Array(items[start..<min(start + columns, items.count)])
        }
    }

    /// The share of a window still left, in whole percent.
    static func remainingPercent(_ used: Percentage) -> Int {
        max(0, 100 - Int(used.value.rounded()))
    }

    /// What a dial shows under its ring: the headline percentage, or, while the account is blocked, the time
    /// until the window keeping it blocked resets ("2:14"), even when that is not the primary window.
    static func dialCaption(primary: LimitWindow?, blocking: LimitWindow?, now: Date, l10n: Localizer) -> (text: String, isCountdown: Bool) {
        guard let primary else { return ("—", false) }
        if let blocking, let remaining = blocking.timeUntilReset(from: now), remaining > 0 {
            return (UsageFormat.railCountdown(remaining, l10n: l10n), true)
        }
        return (UsageFormat.percent(primary.used, l10n: l10n), false)
    }

    /// When the history for a window's chart should start: the window's start when known, otherwise one
    /// window length back, rounded down so it stays put between clock ticks; `nil` without a duration.
    static func historySince(window: LimitWindow, now: Date) -> Date? {
        if let start = window.windowStart { return start }
        guard let duration = window.duration?.timeInterval else { return nil }
        let raw = now.addingTimeInterval(-duration).timeIntervalSinceReferenceDate
        let rounded = (raw / historyRoundingStep).rounded(.down) * historyRoundingStep
        return Date(timeIntervalSinceReferenceDate: rounded)
    }

    // MARK: Accounts and groups

    /// "All" and then every group in settings order; empty when there are no groups (the filter is hidden). Group names
    /// are the user's own and never translated.
    static func filterOptions(groups: [AccountGroup], l10n: Localizer) -> [GroupFilterOption] {
        guard !groups.isEmpty else { return [] }
        return [GroupFilterOption(id: nil, title: l10n.deck.allGroups)] + groups.map { GroupFilterOption(id: $0.id, title: $0.name.value) }
    }

    /// The accounts the dial row shows for a group filter. A filter naming a missing group shows everything.
    static func filtered(_ accounts: [AccountPresentation], filter: AccountGroupID?, groups: [AccountGroup]) -> [AccountPresentation] {
        guard let filter, groups.contains(where: { $0.id == filter }) else { return accounts }
        return accounts.filter { $0.status.profile.groupID == filter }
    }

    /// The selected account: the preferred one when shown, else the first shown, else the first at all.
    static func selection(preferred: AccountID?, shown: [AccountID], all: [AccountID]) -> AccountID? {
        if let preferred, shown.contains(preferred) { return preferred }
        return shown.first ?? all.first
    }

    /// Whether a row of dials fits the deck without scrolling.
    static func dialsFit(count: Int, itemWidth: CGFloat, spacing: CGFloat, available: CGFloat) -> Bool {
        guard count > 0 else { return true }
        return CGFloat(count) * itemWidth + CGFloat(count - 1) * spacing <= available + 0.5
    }

    // MARK: Text

    /// "Updated 2 min ago": the freshest reading over the given accounts.
    ///
    /// Only the past: when the next refresh comes differs per account, so it is the selected account's footer that
    /// says "Next refresh in 3 min" (a header with the earliest time across accounts would contradict it), and the
    /// refresh button shows that a refresh is running.
    static func headerSubtitle(accounts: [AccountStatus], now: Date, l10n: Localizer) -> String {
        guard let newest = accounts.compactMap(\.reading?.capturedAt).max() else {
            return accounts.contains(where: \.isRefreshing) ? l10n.deck.loadingLimitsCaption : l10n.deck.waitingForData
        }
        return l10n.deck.updated(ago: UsageFormat.age(since: newest, now: now, l10n: l10n))
    }

    /// `headerSubtitle` for VoiceOver, with the time in words: "Updated 2 minutes ago".
    static func headerSubtitleA11y(accounts: [AccountStatus], now: Date, l10n: Localizer) -> String {
        guard let newest = accounts.compactMap(\.reading?.capturedAt).max() else {
            return headerSubtitle(accounts: accounts, now: now, l10n: l10n)
        }
        return ageA11y(since: newest, now: now, l10n: l10n)
    }

    /// "Updated 2 minutes ago", or "just now" under a minute: `format.ago` in words, for VoiceOver.
    static func ageA11y(since date: Date, now: Date, l10n: Localizer) -> String {
        let seconds = now.timeIntervalSince(date)
        guard seconds.isFinite, seconds >= 60 else { return UsageFormat.age(since: date, now: now, l10n: l10n) }
        return l10n.deck.updatedA11y(l10n.format.durationSpoken(seconds))
    }

    /// The account's own refresh state for its footer: "Next refresh in 3 min" or "Refreshing…".
    static func refreshText(status: AccountStatus, now: Date, l10n: Localizer) -> String? {
        if status.isRefreshing { return l10n.deck.refreshing }
        return status.nextRefreshAt.map { UsageFormat.nextRefresh($0, now: now, l10n: l10n) }
    }

    /// `refreshText` for VoiceOver, with the time in words: "Next refresh in 3 minutes".
    static func refreshTextA11y(status: AccountStatus, now: Date, l10n: Localizer) -> String? {
        guard !status.isRefreshing, let next = status.nextRefreshAt else { return refreshText(status: status, now: now, l10n: l10n) }
        let remaining = next.timeIntervalSince(now)
        guard remaining > 0 else { return UsageFormat.nextRefresh(next, now: now, l10n: l10n) }
        return l10n.usage.nextRefresh(in: l10n.format.durationSpoken(remaining))
    }

    /// "me@example.com · 2 min ago"; "me@example.com · Updated 20 min ago" once stale.
    static func identityLine(
        email: String?,
        freshness: ReadingFreshness,
        capturedAt: Date?,
        provider: ProviderKind,
        now: Date,
        l10n: Localizer
    ) -> String {
        var parts: [String] = []
        if let email { parts.append(email) }
        switch freshness {
        case .stale(let since):
            parts.append(l10n.deck.staleData(ago: UsageFormat.age(since: since, now: now, l10n: l10n)))
        case .fresh:
            if let capturedAt { parts.append(UsageFormat.age(since: capturedAt, now: now, l10n: l10n)) }
        case .missing:
            break
        }
        return parts.isEmpty ? UsageFormat.providerName(provider) : parts.joined(separator: " · ")
    }

    /// `identityLine` for VoiceOver: times in words, ", " between the parts, and a note when the data is out of date.
    static func identityLineA11y(
        email: String?,
        freshness: ReadingFreshness,
        capturedAt: Date?,
        provider: ProviderKind,
        now: Date,
        l10n: Localizer
    ) -> String {
        var parts: [String] = []
        if let email { parts.append(email) }
        switch freshness {
        case .stale(let since):
            parts.append(ageA11y(since: since, now: now, l10n: l10n))
            parts.append(l10n.deck.staleDataA11y)
        case .fresh:
            if let capturedAt { parts.append(ageA11y(since: capturedAt, now: now, l10n: l10n)) }
        case .missing:
            break
        }
        return parts.isEmpty ? UsageFormat.providerName(provider) : parts.joined(separator: ", ")
    }

    /// A window's reset for VoiceOver: a countdown in words ("Resets in 2 hours 14 minutes"), or the reset text
    /// itself when it names a clock time or is on its way; `nil` without a reset time.
    static func resetTextA11y(for window: LimitWindow, now: Date, style: ResetTextStyle, l10n: Localizer) -> String? {
        guard style == .countdown, let remaining = window.timeUntilReset(from: now), remaining > 0 else {
            return UsageFormat.resetText(for: window, now: now, style: style, l10n: l10n)
        }
        return l10n.usage.resetsIn(l10n.format.durationSpoken(remaining))
    }

    // MARK: Sessions

    /// Sessions in the order the deck lists them: waiting (longest wait first), then working, then idle,
    /// each keeping the provider's order; at most `limit`, with the count left out.
    static func sessions(_ sessions: [AgentSession], limit: Int = maximumSessions) -> (shown: [AgentSession], hidden: Int) {
        let waiting = AccountPresentation.waitingSessions(in: sessions)
        let working = sessions.filter { $0.activity == .working }
        let idle = sessions.filter { $0.activity == .idle }
        let ordered = waiting + working + idle
        let shown = Array(ordered.prefix(max(0, limit)))
        return (shown, ordered.count - shown.count)
    }

    /// What a session is doing, hedged when it looks unusual: "Working", "No activity for 8 min", "Needs approval",
    /// "Needs approval or running a command" (a long Codex prompt).
    static func sessionStatus(_ session: AgentSession, provider: ProviderKind, now: Date, l10n: Localizer) -> String {
        switch session.activity {
        case .waiting, .idle:
            return UsageFormat.activity(of: session, provider: provider, now: now, l10n: l10n)
        case .working:
            return UsageFormat.health(of: session, now: now, l10n: l10n) ?? UsageFormat.activity(.working, detail: nil, l10n: l10n)
        }
    }

    /// A shorter wording of a session status for a line too narrow for it: "Waiting or running a command" for the
    /// Codex hedge; `nil` when the status is already short.
    static func compactStatus(_ status: String, l10n: Localizer) -> String? {
        status == l10n.usage.approvalOrRunning ? l10n.session.approvalOrRunningCompact : nil
    }

    /// The pace pill's shorter wording when the full one does not fit beside the numeral: "Runs out tomorrow at
    /// 2:10 PM" for "At this pace, runs out tomorrow at 2:10 PM"; `nil` for the other paces, which are short.
    static func compactPaceText(_ pace: UsagePace, now: Date, l10n: Localizer) -> String? {
        guard case .ahead = pace.verdict, let exhaustion = pace.projectedExhaustion else { return nil }
        return l10n.deck.runsOutCompact(at: UsageFormat.clockText(exhaustion, now: now, l10n: l10n))
    }

    /// The first attention items, with the count left out.
    static func attention(_ items: [AttentionItem], limit: Int = maximumAttentionCards) -> (shown: [AttentionItem], hidden: Int) {
        let shown = Array(items.prefix(max(0, limit)))
        return (shown, items.count - shown.count)
    }
}
