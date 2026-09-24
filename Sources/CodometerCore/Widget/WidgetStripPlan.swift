import Foundation

/// What the strip layout shows for the accounts in a widget's scope: one headline window and a chip per other window.
///
/// The headline (`hero`) is the most constrained weekly window across the accounts — the number the user plans the
/// week around — falling back to the most constrained account's ring window when nobody has a weekly one. Every
/// other window becomes a chip. Windows of several accounts that share a title ("Weekly · All models" on two Claude
/// accounts) share one chip, which shows the most constrained of them and how many accounts it stands for. Chips keep
/// display order (accounts in settings order, main-bucket windows before the other buckets), so the strip does not
/// shuffle as usage moves; when they do not all fit, the last places make way for a "+N" tile.
public struct WidgetStripPlan: Hashable, Sendable {
    /// The headline window and the account it belongs to.
    public struct Hero: Hashable, Sendable {
        public let account: WidgetAccountState
        public let window: WidgetWindowState
        /// Accounts in scope with a window of the same title, this one included: the badge shows it when above one.
        public let accountCount: Int
    }

    /// One tile: a window, the account it belongs to and how many accounts share its title.
    public struct Chip: Hashable, Sendable, Identifiable {
        public let account: WidgetAccountState
        public let window: WidgetWindowState
        /// Accounts in scope with a window of the same title, this one included; 1 for a chip of one account.
        public let accountCount: Int

        public var id: String { "\(account.id.rawValue.uuidString)/\(window.id)" }
        public var title: String { window.source.displayTitle }
    }

    public let hero: Hero?
    /// At most `chipLimit` tiles, or `chipLimit − 1` when there is overflow.
    public let chips: [Chip]
    /// Windows without a tile of their own, shown as "+N"; 0 when everything fits.
    public let overflow: Int

    /// - Parameters:
    ///   - states: the scope's accounts in settings order.
    ///   - chipLimit: how many tiles the family has room for, the overflow tile included.
    public init(states: [WidgetAccountState], chipLimit: Int) {
        let hero = Self.hero(in: states)
        self.hero = hero
        let groups = Self.groups(in: states)
        let remaining = groups.filter { group in
            guard let hero else { return true }
            return group.title != hero.window.source.displayTitle
        }
        let chips = remaining.map { group in
            Chip(account: group.representative.account, window: group.representative.window, accountCount: group.accountCount)
        }
        (self.chips, overflow) = Self.fit(chips, limit: chipLimit)
    }

    /// One account's windows as tiles, the account's own share of the hero left out, for the per-account rows of the
    /// large widget. Every chip stands for one account.
    public static func chips(for state: WidgetAccountState, hero: Hero?, limit: Int) -> (chips: [Chip], overflow: Int) {
        let chips = state.windows
            .filter { window in !(hero?.account.id == state.id && hero?.window.id == window.id) }
            .map { Chip(account: state, window: $0, accountCount: 1) }
        return fit(chips, limit: limit)
    }

    /// The share of the limit left, clamped to 0…100, so "64% left" and "36% used" always add up.
    public static func remaining(of window: WidgetWindowState) -> Percentage {
        (try? Percentage(validating: window.window.used.remaining)) ?? .zero
    }

    // MARK: Selection

    /// The most constrained weekly main-bucket window, else the most constrained account's ring window.
    static func hero(in states: [WidgetAccountState]) -> Hero? {
        let priority = WidgetSelection.priorityOrder(states)
        var rank: [AccountID: Int] = [:]
        for (position, index) in priority.enumerated() {
            rank[states[index].id] = position
        }
        var best: (account: WidgetAccountState, window: WidgetWindowState)?
        for state in states where state.hasReading {
            for window in state.windows where window.source.isMainBucket && window.isWeekly {
                guard let current = best else {
                    best = (state, window)
                    continue
                }
                let used = window.window.used
                let currentUsed = current.window.window.used
                if used > currentUsed || (used == currentUsed && (rank[state.id] ?? .max) < (rank[current.account.id] ?? .max)) {
                    best = (state, window)
                }
            }
        }
        if best == nil, let featured = WidgetSelection.mostConstrained(states), let binding = featured.binding {
            best = (featured, binding)
        }
        guard let best else { return nil }
        let title = best.window.source.displayTitle
        let sharing = Set(states.filter { state in state.windows.contains { $0.source.displayTitle == title } }.map(\.id))
        return Hero(account: best.account, window: best.window, accountCount: max(1, sharing.count))
    }

    private struct Group {
        let title: String
        var representative: (account: WidgetAccountState, window: WidgetWindowState)
        var accounts: Set<AccountID>

        var accountCount: Int { accounts.count }
    }

    /// Windows grouped by title in first-appearance order; each group's representative is its most constrained window.
    private static func groups(in states: [WidgetAccountState]) -> [Group] {
        var groups: [Group] = []
        var index: [String: Int] = [:]
        for state in states where state.hasReading {
            for window in state.windows {
                let title = window.source.displayTitle
                if let position = index[title] {
                    groups[position].accounts.insert(state.id)
                    if window.window.used > groups[position].representative.window.window.used {
                        groups[position].representative = (state, window)
                    }
                } else {
                    index[title] = groups.count
                    groups.append(Group(title: title, representative: (state, window), accounts: [state.id]))
                }
            }
        }
        return groups
    }

    /// Everything when it fits; otherwise `limit − 1` chips and the rest counted, so the "+N" tile never lies.
    static func fit(_ chips: [Chip], limit: Int) -> (chips: [Chip], overflow: Int) {
        guard limit > 0 else { return ([], chips.count) }
        guard chips.count > limit else { return (chips, 0) }
        let shown = max(0, limit - 1)
        return (Array(chips.prefix(shown)), chips.count - shown)
    }
}

extension WidgetWindowState {
    /// A weekly window: the provider calls it one, or its length is about a week (six to eight days).
    public var isWeekly: Bool {
        if case .weekly = window.scope { return true }
        guard let minutes = window.duration?.minutes else { return false }
        return (6 * 1_440...8 * 1_440).contains(minutes)
    }
}
