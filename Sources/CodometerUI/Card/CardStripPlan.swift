import CodometerCore
import CodometerL10n
import Foundation

/// Everything the Strip card draws, worked out once per render from the accounts in its scope.
///
/// The strip is the one size that can cover several accounts (`CardStripScope`), so it cannot be planned from one
/// presentation the way the other sizes are. Windows of the same kind on several accounts fold into one chip that
/// shows the most constrained of them and says how many accounts it stands for; the hero is the most constrained
/// weekly window of the scope. Pure and `Equatable`, so every rule here is tested without a renderer.
public struct CardStripPlan: Equatable, Sendable {
    /// What the header names: the account itself, or the scope.
    public struct Header: Equatable, Sendable {
        /// The account's own label, or the scope's name ("Claude", "All accounts").
        public let title: String
        /// The provider every account in scope shares; `nil` when the scope mixes providers.
        public let provider: ProviderKind?
        /// Draws the account chip (badge, label, plan, menu) instead of the scope's name.
        public let isSelectedAccount: Bool
    }

    /// The big figure on the left: what is *left* of the window that binds the scope.
    public struct Hero: Equatable, Sendable {
        /// "Weekly", or "Weekly · Work" when the scope covers several accounts.
        public let caption: String
        /// "64%".
        public let remainingFigure: String
        /// "left".
        public let unit: String
        /// "36% used · ⟳ 5d 16h".
        public let usedLine: String
        public let band: UsageBand
        public let accessibilityText: String
    }

    /// One limit window, or several accounts' windows of the same kind folded together.
    public struct Chip: Equatable, Sendable, Identifiable {
        public let id: String
        public let provider: ProviderKind
        /// "Weekly · Opus", "Session · 5h", "5h", the provider's own label.
        public let title: String
        /// "51%" used.
        public let percentText: String
        /// "⟳ 1d 14h"; `nil` without a reset time.
        public let resetText: String?
        public let band: UsageBand
        /// How many accounts share this window; the badge shows it when it is more than one.
        public let accountsCount: Int
        public let accessibilityText: String
    }

    /// The scope actually drawn: the requested one, or `.selectedAccount` when no enabled account matched it.
    public let scope: CardStripScope
    public let header: Header
    public let hero: Hero?
    /// At most `capacity` chips, or `capacity - 1` when a "+N" chip follows them.
    public let chips: [Chip]
    /// How many windows the "+N" chip stands for; 0 draws no such chip.
    public let more: Int
    /// "+3"; `nil` when every window has its chip.
    public let moreText: String?
    public let moreAccessibilityText: String?
    /// Chips carry their provider's glyph when the ones drawn belong to more than one provider.
    public let showsProviders: Bool
    /// The accounts the strip covers, in the order given.
    public let accountIDs: [AccountID]

    /// Plans the strip for `scope`.
    ///
    /// - Parameters:
    ///   - selected: The account the card follows; the one shown for `.selectedAccount`, and the fallback when the
    ///     scope matches no account.
    ///   - accounts: Every account the card may show, in settings order.
    ///   - capacity: How many chips fit (`CardMetrics.stripChipCapacity`).
    /// - Returns: `nil` when there is no account to show at all.
    public static func make(
        scope: CardStripScope,
        selected: AccountPresentation?,
        accounts: [AccountPresentation],
        capacity: Int,
        now: Date,
        l10n: Localizer
    ) -> CardStripPlan? {
        let shown = selected ?? accounts.first
        let matching: [AccountPresentation] = switch scope {
        case .selectedAccount: shown.map { [$0] } ?? []
        case .claude: accounts.filter { $0.provider == .claude }
        case .codex: accounts.filter { $0.provider == .codex }
        case .allAccounts: accounts
        }
        let effectiveScope: CardStripScope = matching.isEmpty ? .selectedAccount : scope
        let inScope = matching.isEmpty ? (shown.map { [$0] } ?? []) : matching
        guard let first = inScope.first else { return nil }

        let header = makeHeader(scope: effectiveScope, first: first, accounts: inScope, l10n: l10n)
        let hero = makeHero(accounts: inScope, now: now, l10n: l10n)
        let merged = mergedChips(accounts: inScope, now: now, l10n: l10n)
        let cut = max(1, capacity)
        let overflow = merged.count > cut ? merged.count - (cut - 1) : 0
        let chips = overflow > 0 ? Array(merged.prefix(cut - 1)) : merged
        return CardStripPlan(
            scope: effectiveScope,
            header: header,
            hero: hero,
            chips: chips,
            more: overflow,
            moreText: overflow > 0 ? l10n.card.stripMore(overflow) : nil,
            moreAccessibilityText: overflow > 0 ? l10n.card.moreWindowsA11y(overflow) : nil,
            showsProviders: Set(chips.map(\.provider)).count > 1,
            accountIDs: inScope.map(\.id)
        )
    }

    // MARK: - Header

    private static func makeHeader(
        scope: CardStripScope,
        first: AccountPresentation,
        accounts: [AccountPresentation],
        l10n: Localizer
    ) -> Header {
        let providers = Set(accounts.map(\.provider))
        let provider = providers.count == 1 ? providers.first : nil
        switch scope {
        case .selectedAccount:
            return Header(title: first.status.profile.label.value, provider: first.provider, isSelectedAccount: true)
        case .claude:
            return Header(title: l10n.card.scopeClaude, provider: .claude, isSelectedAccount: false)
        case .codex:
            return Header(title: l10n.card.scopeCodex, provider: .codex, isSelectedAccount: false)
        case .allAccounts:
            return Header(title: l10n.card.allAccountsTitle, provider: provider, isSelectedAccount: false)
        }
    }

    // MARK: - Hero

    /// The most constrained weekly window over the scope's main buckets; without one, the most constrained binding
    /// window. Ties go to the earlier reset, then to the earlier account.
    static func heroWindow(accounts: [AccountPresentation]) -> (account: AccountPresentation, window: WindowPresentation)? {
        var weekly: [(AccountPresentation, WindowPresentation)] = []
        var binding: [(AccountPresentation, WindowPresentation)] = []
        for account in accounts {
            for window in account.mainWindows where isWeekly(window.window) {
                weekly.append((account, window))
            }
            if let id = account.headline?.binding.id, let window = account.mainWindows.first(where: { $0.window.id == id }) {
                binding.append((account, window))
            }
        }
        let candidates = weekly.isEmpty ? binding : weekly
        return mostConstrained(candidates).map { (account: $0.0, window: $0.1) }
    }

    /// A weekly window by meaning, or by length for providers that only give a duration.
    static func isWeekly(_ window: LimitWindow) -> Bool {
        if case .weekly = window.scope { return true }
        return window.duration?.minutes == WindowDuration.oneWeek.minutes
    }

    /// The highest usage wins; equal usage goes to the earlier reset (an unknown reset counts as the latest), then to
    /// the earlier element.
    private static func mostConstrained<Account>(
        _ candidates: [(Account, WindowPresentation)]
    ) -> (Account, WindowPresentation)? {
        var best: (Account, WindowPresentation)?
        for candidate in candidates {
            guard let current = best else {
                best = candidate
                continue
            }
            if beats(candidate.1.window, current.1.window) {
                best = candidate
            }
        }
        return best
    }

    private static func beats(_ challenger: LimitWindow, _ holder: LimitWindow) -> Bool {
        if challenger.used != holder.used { return challenger.used > holder.used }
        switch (challenger.resetsAt, holder.resetsAt) {
        case let (left?, right?): return left < right
        case (.some, nil): return true
        case (nil, _): return false
        }
    }

    private static func makeHero(accounts: [AccountPresentation], now: Date, l10n: Localizer) -> Hero? {
        guard let (account, presentation) = heroWindow(accounts: accounts) else { return nil }
        let window = presentation.window
        let title = chipTitle(presentation, l10n: l10n)
        let caption = accounts.count > 1 ? "\(title) · \(account.status.profile.label.value)" : title
        let remaining = Double(remainingPercent(window.used))
        let used = l10n.format.percentCompact(window.used.value)
        let countdown = window.resetsAt.map { max(0, $0.timeIntervalSince(now)) }
        let usedLine = countdown.map { l10n.card.stripUsedLine(used: used, reset: l10n.format.durationCompact($0)) }
            ?? l10n.card.stripUsed(used)
        var speech = [
            caption,
            l10n.card.leftA11y(l10n.format.percent(remaining)),
            l10n.card.usedA11y(l10n.format.percent(window.used.value)),
        ]
        if let countdown {
            speech.append(l10n.card.resetsInA11y(l10n.format.durationSpoken(countdown)))
        }
        return Hero(
            caption: caption,
            remainingFigure: l10n.format.percentCompact(remaining),
            unit: l10n.card.left,
            usedLine: usedLine,
            band: presentation.band,
            accessibilityText: speech.joined(separator: ", ")
        )
    }

    /// The share of a window still left, in whole percent, the way the deck counts it.
    static func remainingPercent(_ used: Percentage) -> Int {
        max(0, 100 - Int(used.value.rounded()))
    }

    // MARK: - Chips

    /// One chip per kind of window over the scope, main buckets first: windows of the same kind on several accounts
    /// fold into the most constrained one, with a count of the accounts folded.
    static func mergedChips(accounts: [AccountPresentation], now: Date, l10n: Localizer) -> [Chip] {
        struct Entry {
            var provider: ProviderKind
            var shown: WindowPresentation
            var accounts: Set<AccountID>
            var isMainBucket: Bool
        }
        var order: [String] = []
        var entries: [String: Entry] = [:]
        for account in accounts {
            for window in account.windows {
                let key = chipKey(window, provider: account.provider)
                if var entry = entries[key] {
                    entry.accounts.insert(account.id)
                    if beats(window.window, entry.shown.window) {
                        entry.shown = window
                    }
                    entries[key] = entry
                } else {
                    order.append(key)
                    entries[key] = Entry(provider: account.provider, shown: window, accounts: [account.id], isMainBucket: window.isMainBucket)
                }
            }
        }
        let ordered = order.compactMap { key in entries[key].map { (key, $0) } }
        let main = ordered.filter { $0.1.isMainBucket }
        let others = ordered.filter { !$0.1.isMainBucket }
        return (main + others).map { key, entry in
            chip(id: key, provider: entry.provider, window: entry.shown, accountsCount: entry.accounts.count, now: now, l10n: l10n)
        }
    }

    /// What makes two windows on different accounts "the same window": the provider, the bucket (the main one by
    /// role, others by id) and the window's meaning.
    static func chipKey(_ window: WindowPresentation, provider: ProviderKind) -> String {
        let bucket = window.isMainBucket ? "main" : "bucket:\(window.bucketID)"
        let kind: String = switch window.window.scope {
        case .session: "session"
        case .weekly(nil): "weekly"
        case .weekly(let model?): "weekly:\(model)"
        case .rolling:
            if let label = window.window.label {
                "label:\(label)"
            } else if let minutes = window.window.duration?.minutes {
                "rolling:\(minutes)"
            } else {
                "window:\(window.window.id)"
            }
        }
        return "\(provider.rawValue)/\(bucket)/\(kind)"
    }

    /// A chip's title: the window's own title, except that the all-models week is just "Weekly" — the model weeks
    /// beside it already say which model they are — and a window of another bucket carries that bucket's name.
    static func chipTitle(_ window: WindowPresentation, l10n: Localizer) -> String {
        let own = window.window.scope == .weekly(model: nil) ? l10n.window.weekly : window.title
        guard !window.isMainBucket else { return own }
        return "\(window.bucketTitle ?? window.bucketID) · \(own)"
    }

    private static func chip(
        id: String,
        provider: ProviderKind,
        window presentation: WindowPresentation,
        accountsCount: Int,
        now: Date,
        l10n: Localizer
    ) -> Chip {
        let window = presentation.window
        let title = chipTitle(presentation, l10n: l10n)
        let countdown = window.resetsAt.map { max(0, $0.timeIntervalSince(now)) }
        var speech = [UsageFormat.providerName(provider), title, l10n.card.usedA11y(l10n.format.percent(window.used.value))]
        if let countdown {
            speech.append(l10n.card.resetsInA11y(l10n.format.durationSpoken(countdown)))
        }
        if accountsCount > 1 {
            speech.append(l10n.card.accountsSharingA11y(accountsCount))
        }
        return Chip(
            id: id,
            provider: provider,
            title: title,
            percentText: l10n.format.percentCompact(window.used.value),
            resetText: countdown.map { l10n.card.stripReset(l10n.format.durationCompact($0)) },
            band: presentation.band,
            accountsCount: accountsCount,
            accessibilityText: speech.joined(separator: ", ")
        )
    }
}
