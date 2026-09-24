import CodometerCore
import CodometerL10n
import Foundation

/// The floating card's context menu as data: which items exist in which state, their order, their check marks and
/// their titles in the current language.
///
/// The harness cannot capture an `NSMenu`, so the menu is built here and only turned into `NSMenuItem`s by the
/// controller. That is what makes its copy testable in both languages.
public struct CardMenuPlan: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case minimize
        case expand
        /// `nil` returns to following the most urgent account.
        case selectAccount(AccountID?)
        /// Keeps the account that is shown now, for good.
        case stayOnAccount
        case size(CardSize)
        /// Which accounts the Strip size covers.
        case stripScope(CardStripScope)
        case theme(CardTheme)
        case toggleKeepAbove
        case toggleSnapping
        case move(CardAnchor)
        case moveToDisplay(DisplayID)
        case refresh
        case switchToIsland
        case openSettings
    }

    public struct Item: Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String
        public let systemImage: String?
        public let action: Action?
        public let isChecked: Bool
        public let children: [Item]
        public let isSeparator: Bool

        init(
            id: String,
            title: String,
            systemImage: String? = nil,
            action: Action? = nil,
            isChecked: Bool = false,
            children: [Item] = []
        ) {
            self.id = id
            self.title = title
            self.systemImage = systemImage
            self.action = action
            self.isChecked = isChecked
            self.children = children
            isSeparator = false
        }

        private init(separatorID: String) {
            id = separatorID
            title = ""
            systemImage = nil
            action = nil
            isChecked = false
            children = []
            isSeparator = true
        }

        static func separator(_ id: String) -> Item { Item(separatorID: id) }
    }

    /// One account as the menu lists it (its own name, never translated).
    public struct AccountEntry: Equatable, Sendable {
        public let id: AccountID
        public let label: String
        public let provider: ProviderKind
        /// "64%", or `nil` without a reading.
        public let usage: String?

        public init(id: AccountID, label: String, provider: ProviderKind, usage: String?) {
            self.id = id
            self.label = label
            self.provider = provider
            self.usage = usage
        }
    }

    /// One connected display as the menu lists it.
    public struct DisplayEntry: Equatable, Sendable {
        public let id: DisplayID
        public let name: String

        public init(id: DisplayID, name: String) {
            self.id = id
            self.name = name
        }
    }

    public let items: [Item]

    /// Builds the menu for the card's current state.
    ///
    /// - Parameters:
    ///   - otherDisplays: Connected displays other than the one the card is on; empty on a single-display Mac, where
    ///     "Move To" lists only the places.
    public static func make(
        isExpanded: Bool,
        settings: FloatingCardSettings,
        snapsWhileDragging: Bool,
        accounts: [AccountEntry],
        otherDisplays: [DisplayEntry],
        l10n: Localizer
    ) -> CardMenuPlan {
        let card = l10n.card
        var items: [Item] = [
            isExpanded
                ? Item(id: "minimize", title: card.minimize, systemImage: "minus.circle", action: .minimize)
                : Item(id: "expand", title: card.expand, systemImage: "plus.circle", action: .expand),
            .separator("s1"),
        ]
        if !accounts.isEmpty {
            items.append(Item(
                id: "account",
                title: card.accountMenu,
                systemImage: "person.crop.circle",
                children: accountItems(settings: settings, accounts: accounts, l10n: l10n)
            ))
        }
        items.append(Item(id: "size", title: card.sizeMenu, systemImage: "rectangle.resize", children: sizeItems(settings: settings, l10n: l10n)))
        if settings.size == .strip {
            // The scope only means something to the strip, so the other sizes keep the menu short.
            items.append(Item(id: "scope", title: card.scopeMenu, systemImage: "person.2.crop.square.stack", children: scopeItems(settings: settings, l10n: l10n)))
        }
        items.append(Item(id: "theme", title: card.themeMenu, systemImage: "paintpalette", children: themeItems(settings: settings, l10n: l10n)))
        items.append(Item(id: "moveTo", title: card.moveTo, systemImage: "arrow.up.left.and.arrow.down.right", children: moveItems(otherDisplays: otherDisplays, l10n: l10n)))
        items.append(.separator("s2"))
        items.append(Item(
            id: "keepAbove",
            title: card.keepAbove,
            systemImage: "square.3.layers.3d.top.filled",
            action: .toggleKeepAbove,
            isChecked: settings.keepsAboveWindows
        ))
        items.append(Item(
            id: "snap",
            title: card.snapWhileDragging,
            systemImage: "dot.magnifyingglass",
            action: .toggleSnapping,
            isChecked: snapsWhileDragging
        ))
        items.append(.separator("s3"))
        items.append(Item(id: "refresh", title: l10n.menu.refreshAll, systemImage: "arrow.clockwise", action: .refresh))
        items.append(Item(id: "island", title: card.switchToIsland, systemImage: "capsule", action: .switchToIsland))
        items.append(Item(id: "settings", title: l10n.menu.settings, systemImage: "gearshape", action: .openSettings))
        return CardMenuPlan(items: items)
    }

    private static func accountItems(
        settings: FloatingCardSettings,
        accounts: [AccountEntry],
        l10n: Localizer
    ) -> [Item] {
        let isAuto = settings.accountSelection == .mostUrgent
        var items: [Item] = [
            Item(id: "account.auto", title: l10n.card.accountAuto, action: .selectAccount(nil), isChecked: isAuto),
            .separator("account.s1"),
        ]
        for account in accounts {
            let title = account.usage.map { "\(account.label) · \($0)" } ?? account.label
            items.append(Item(
                id: "account.\(account.id.rawValue.uuidString)",
                title: title,
                action: .selectAccount(account.id),
                isChecked: settings.accountSelection == .fixed(account.id)
            ))
        }
        if isAuto {
            items.append(.separator("account.s2"))
            items.append(Item(id: "account.stay", title: l10n.card.accountStay, action: .stayOnAccount))
        }
        return items
    }

    private static func sizeItems(settings: FloatingCardSettings, l10n: Localizer) -> [Item] {
        CardSize.allCases.map { size in
            Item(id: "size.\(size.rawValue)", title: title(size, l10n: l10n), action: .size(size), isChecked: settings.size == size)
        }
    }

    private static func scopeItems(settings: FloatingCardSettings, l10n: Localizer) -> [Item] {
        CardStripScope.allCases.map { scope in
            Item(id: "scope.\(scope.rawValue)", title: title(scope, l10n: l10n), action: .stripScope(scope), isChecked: settings.stripScope == scope)
        }
    }

    private static func themeItems(settings: FloatingCardSettings, l10n: Localizer) -> [Item] {
        CardTheme.allCases.map { theme in
            Item(id: "theme.\(theme.rawValue)", title: title(theme, l10n: l10n), action: .theme(theme), isChecked: settings.theme == theme)
        }
    }

    private static func moveItems(otherDisplays: [DisplayEntry], l10n: Localizer) -> [Item] {
        let card = l10n.card
        let places: [(CardAnchor, String)] = [
            (.topLeading, card.topLeft),
            (.topTrailing, card.topRight),
            (.bottomLeading, card.bottomLeft),
            (.bottomTrailing, card.bottomRight),
            (.center, card.center),
        ]
        var items = places.map { anchor, title in
            Item(id: "move.\(anchor.rawValue)", title: title, action: .move(anchor))
        }
        guard !otherDisplays.isEmpty else { return items }
        items.append(.separator("move.s1"))
        for display in otherDisplays {
            items.append(Item(
                id: "move.display.\(display.id.rawValue)",
                title: card.moveToDisplay(display.name),
                action: .moveToDisplay(display.id)
            ))
        }
        return items
    }

    public static func title(_ size: CardSize, l10n: Localizer) -> String {
        switch size {
        case .compact: l10n.card.sizeCompact
        case .regular: l10n.card.sizeRegular
        case .strip: l10n.card.sizeStrip
        }
    }

    public static func title(_ scope: CardStripScope, l10n: Localizer) -> String {
        switch scope {
        case .selectedAccount: l10n.card.scopeSelected
        case .claude: l10n.card.scopeClaude
        case .codex: l10n.card.scopeCodex
        case .allAccounts: l10n.card.scopeAll
        }
    }

    public static func title(_ theme: CardTheme, l10n: Localizer) -> String {
        switch theme {
        case .graphite: l10n.card.themeGraphite
        case .liquidGlass: l10n.card.themeLiquidGlass
        case .midnight: l10n.card.themeMidnight
        case .light: l10n.card.themeLight
        }
    }

    public static func title(_ tile: CardThirdTile, l10n: Localizer) -> String {
        switch tile {
        case .weeklyReset: l10n.card.thirdTileWeekly
        case .sessionWindow: l10n.card.thirdTileSession
        case .agents: l10n.card.thirdTileAgents
        }
    }

    /// Every title the plan produces, submenus included, for the copy tests.
    public var allTitles: [String] {
        func walk(_ items: [Item]) -> [String] {
            items.flatMap { item in item.isSeparator ? [] : [item.title] + walk(item.children) }
        }
        return walk(items)
    }
}
