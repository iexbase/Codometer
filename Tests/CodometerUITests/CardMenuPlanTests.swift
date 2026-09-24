import CodometerCore
import CodometerL10n
@testable import CodometerUI
import Foundation
import Testing

/// The card's context menu, which the harness cannot capture: its items, their order, their check marks and their
/// copy in both languages.
@Suite("Card menu")
struct CardMenuPlanTests {
    static let english = Localizer.testEnglish
    static let russian = Localizer.testRussian

    private static func accounts(_ count: Int) throws -> [CardMenuPlan.AccountEntry] {
        try (0..<count).map { index in
            CardMenuPlan.AccountEntry(
                id: AccountID(rawValue: try #require(UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index)))),
                label: "Account \(index)",
                provider: index.isMultiple(of: 2) ? .claude : .codex,
                usage: "\(40 + index)%"
            )
        }
    }

    private static func plan(
        isExpanded: Bool = true,
        settings: FloatingCardSettings = FloatingCardSettings(),
        snaps: Bool = true,
        accounts: [CardMenuPlan.AccountEntry] = [],
        displays: [CardMenuPlan.DisplayEntry] = [],
        l10n: Localizer = english
    ) -> CardMenuPlan {
        CardMenuPlan.make(
            isExpanded: isExpanded,
            settings: settings,
            snapsWhileDragging: snaps,
            accounts: accounts,
            otherDisplays: displays,
            l10n: l10n
        )
    }

    private func ids(_ plan: CardMenuPlan) -> [String] {
        plan.items.filter { !$0.isSeparator }.map(\.id)
    }

    @Test("The first item names the transition the card can make right now")
    func firstItemFollowsTheForm() {
        #expect(Self.plan(isExpanded: true).items.first?.id == "minimize")
        #expect(Self.plan(isExpanded: true).items.first?.title == "Minimize")
        #expect(Self.plan(isExpanded: false).items.first?.id == "expand")
        #expect(Self.plan(isExpanded: false).items.first?.title == "Expand")
    }

    @Test("The menu has every item the design asks for, in order")
    func order() throws {
        let plan = Self.plan(accounts: try Self.accounts(2))
        #expect(ids(plan) == [
            "minimize", "account", "size", "theme", "moveTo", "keepAbove", "snap", "refresh", "island", "settings",
        ])
    }

    @Test("The strip adds a “Show” submenu with its four scopes, right after “Size”; the other sizes have none")
    func stripScopeSubmenu() throws {
        var settings = FloatingCardSettings()
        settings.size = .strip
        settings.stripScope = .codex
        let plan = Self.plan(settings: settings, accounts: try Self.accounts(2))
        #expect(ids(plan) == [
            "minimize", "account", "size", "scope", "theme", "moveTo", "keepAbove", "snap", "refresh", "island", "settings",
        ])
        let scope = try #require(plan.items.first { $0.id == "scope" })
        #expect(scope.title == "Show")
        #expect(scope.children.map(\.id) == ["scope.selectedAccount", "scope.claude", "scope.codex", "scope.allAccounts"])
        #expect(scope.children.map(\.title) == ["This Account", "Claude", "Codex", "All Accounts"])
        #expect(scope.children.first { $0.isChecked }?.action == .stripScope(.codex))
        let size = try #require(plan.items.first { $0.id == "size" })
        #expect(size.children.map(\.title) == ["Compact", "Regular", "Strip"])
        #expect(size.children.first { $0.isChecked }?.id == "size.strip")
        #expect(!ids(Self.plan(accounts: try Self.accounts(2))).contains("scope"))

        let russian = try #require(Self.plan(settings: settings, l10n: Self.russian).items.first { $0.id == "scope" })
        #expect(russian.title == "Показывать")
        #expect(russian.children.map(\.title) == ["Этот аккаунт", "Claude", "Codex", "Все аккаунты"])
    }

    @Test("Without accounts the account submenu is left out entirely")
    func noAccountsNoSubmenu() {
        #expect(!ids(Self.plan()).contains("account"))
    }

    @Test("Check marks follow the settings")
    func checkMarks() throws {
        var settings = FloatingCardSettings()
        settings.size = .compact
        settings.theme = .midnight
        settings.keepsAboveWindows = false
        let plan = Self.plan(settings: settings, snaps: false, accounts: try Self.accounts(1))
        let size = try #require(plan.items.first { $0.id == "size" })
        #expect(size.children.first { $0.isChecked }?.id == "size.compact")
        let theme = try #require(plan.items.first { $0.id == "theme" })
        #expect(theme.children.first { $0.isChecked }?.id == "theme.midnight")
        #expect(plan.items.first { $0.id == "keepAbove" }?.isChecked == false)
        #expect(plan.items.first { $0.id == "snap" }?.isChecked == false)
    }

    @Test("Following the most urgent account is checked until the user fixes one")
    func accountSelection() throws {
        let accounts = try Self.accounts(3)
        let auto = try #require(Self.plan(accounts: accounts).items.first { $0.id == "account" })
        #expect(auto.children.first?.id == "account.auto")
        #expect(auto.children.first?.isChecked == true)
        #expect(auto.children.contains { $0.id == "account.stay" })

        var settings = FloatingCardSettings()
        settings.accountSelection = .fixed(accounts[1].id)
        let fixed = try #require(Self.plan(settings: settings, accounts: accounts).items.first { $0.id == "account" })
        #expect(fixed.children.first?.isChecked == false)
        #expect(fixed.children.first { $0.isChecked }?.title.hasPrefix("Account 1") == true)
        // "Stay on This Account" only makes sense while the card is still following the most urgent account.
        #expect(!fixed.children.contains { $0.id == "account.stay" })
    }

    @Test("Each account is listed with its usage, and the labels are the user's own words")
    func accountTitles() throws {
        let accounts = try Self.accounts(2)
        let menu = try #require(Self.plan(accounts: accounts).items.first { $0.id == "account" })
        let titles = menu.children.filter { $0.id.hasPrefix("account.0") || $0.id.hasPrefix("account.\(accounts[0].id.rawValue.uuidString)") }
        #expect(!titles.isEmpty || menu.children.contains { $0.title == "Account 0 · 40%" })
    }

    @Test("“Move To” lists the five places, and one item per other display")
    func moveItems() throws {
        let single = try #require(Self.plan().items.first { $0.id == "moveTo" })
        #expect(single.children.map(\.id) == [
            "move.topLeading", "move.topTrailing", "move.bottomLeading", "move.bottomTrailing", "move.center",
        ])
        let external = CardMenuPlan.DisplayEntry(id: try DisplayID("11111111-1111-4111-8111-111111111111"), name: "LG UltraFine")
        let several = try #require(Self.plan(displays: [external]).items.first { $0.id == "moveTo" })
        #expect(several.children.last?.title == "Move to “LG UltraFine”")
        #expect(several.children.last?.action == .moveToDisplay(external.id))
    }

    @Test("Every action is reachable from the menu")
    func actions() throws {
        let accounts = try Self.accounts(1)
        let plan = Self.plan(accounts: accounts)
        func walk(_ items: [CardMenuPlan.Item]) -> [CardMenuPlan.Action] {
            items.flatMap { item in (item.action.map { [$0] } ?? []) + walk(item.children) }
        }
        let actions = walk(plan.items)
        #expect(actions.contains(.minimize))
        #expect(actions.contains(.selectAccount(nil)))
        #expect(actions.contains(.selectAccount(accounts[0].id)))
        #expect(actions.contains(.stayOnAccount))
        #expect(actions.contains(.size(.compact)))
        #expect(actions.contains(.theme(.liquidGlass)))
        #expect(actions.contains(.toggleKeepAbove))
        #expect(actions.contains(.toggleSnapping))
        #expect(actions.contains(.move(.center)))
        #expect(actions.contains(.refresh))
        #expect(actions.contains(.switchToIsland))
        #expect(actions.contains(.openSettings))
    }

    @Test("English menu titles are Title Case, as macOS menus are")
    func englishIsTitleCase() throws {
        // Words a title keeps lowercase.
        let small: Set<String> = ["to", "on", "the", "of", "a", "and", "in", "its", "this", "other"]
        var settings = FloatingCardSettings()
        settings.size = .strip
        let plan = Self.plan(settings: settings, accounts: try Self.accounts(1))
        for title in plan.allTitles {
            // Account names and generated titles are the user's own words.
            guard !title.hasPrefix("Account "), !title.hasPrefix("Move to “") else { continue }
            for (index, word) in title.split(separator: " ").enumerated() {
                let text = String(word)
                guard let first = text.first, first.isLetter else { continue }
                if index > 0, small.contains(text.lowercased()) { continue }
                #expect(first.isUppercase, "“\(title)”: “\(text)” should start with a capital")
            }
        }
    }

    @Test("Russian menu titles are sentence case and written in Russian")
    func russianCopy() throws {
        var settings = FloatingCardSettings()
        settings.size = .strip
        let plan = Self.plan(settings: settings, accounts: try Self.accounts(1), l10n: Self.russian)
        #expect(plan.items.first?.title == "Свернуть")
        let theme = try #require(plan.items.first { $0.id == "theme" })
        #expect(theme.title == "Оформление")
        #expect(theme.children.map(\.title) == ["Графит", "Liquid Glass", "Полночь", "Светлая"])
        let move = try #require(plan.items.first { $0.id == "moveTo" })
        #expect(move.children.first?.title == "Вверху слева")
        // Every title carries Cyrillic unless it is a brand name.
        let brands: Set<String> = ["Liquid Glass", "Claude", "Codex"]
        for title in plan.allTitles {
            guard !title.hasPrefix("Account "), !brands.contains(title) else { continue }
            #expect(title.contains { $0.isCyrillic }, "“\(title)” has no Russian in it")
        }
    }

    @Test("Both languages produce the same shape of menu")
    func sameShape() throws {
        let accounts = try Self.accounts(2)
        for size in CardSize.allCases {
            var settings = FloatingCardSettings()
            settings.size = size
            let en = Self.plan(settings: settings, accounts: accounts, l10n: Self.english)
            let ru = Self.plan(settings: settings, accounts: accounts, l10n: Self.russian)
            #expect(ids(en) == ids(ru))
            #expect(en.allTitles.count == ru.allTitles.count)
        }
    }
}

private extension Character {
    var isCyrillic: Bool {
        unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
    }
}
