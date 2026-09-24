import CodometerCore
import CodometerL10n
@testable import CodometerUI
import Foundation
import Testing

/// What the Strip card says: which accounts its scope covers, how their windows fold into chips, which window leads
/// as the hero, and how the "left" figure is counted.
@Suite("Card strip plan")
struct CardStripPlanTests {
    static let now = UIFixture.now
    static let english = Localizer.testEnglish
    static let russian = Localizer.testRussian

    // MARK: - Builders

    /// A Claude account with the three windows Claude reports.
    private static func claude(
        _ label: String,
        session: Double = 42,
        weekly: Double = 64,
        opus: Double = 51,
        weeklyResetsIn: TimeInterval = 5 * 86_400 + 16 * 3_600,
        l10n: Localizer = english
    ) throws -> AccountPresentation {
        try CardContentPlanTests.presentation(
            label: label,
            provider: .claude,
            windows: [
                try UIFixture.window("session", .session, used: session, duration: .fiveHours, resetsIn: 7_200),
                try UIFixture.window("week", .weekly(model: nil), used: weekly, duration: .oneWeek, resetsIn: weeklyResetsIn),
                try UIFixture.window("week.opus", .weekly(model: "Opus"), used: opus, duration: .oneWeek, resetsIn: 5 * 86_400),
            ],
            l10n: l10n
        )
    }

    /// A Codex account: a 5-hour and a weekly rolling window, both described by their length only.
    private static func codex(_ label: String, primary: Double = 34, secondary: Double = 57, l10n: Localizer = english) throws -> AccountPresentation {
        try CardContentPlanTests.presentation(
            label: label,
            provider: .codex,
            windows: [
                try UIFixture.window("primary", .rolling, used: primary, duration: .fiveHours, resetsIn: 2 * 3_600 + 5 * 60),
                try UIFixture.window("secondary", .rolling, used: secondary, duration: .oneWeek, resetsIn: 1 * 86_400 + 14 * 3_600),
            ],
            plan: "plus",
            l10n: l10n
        )
    }

    private static func plan(
        _ scope: CardStripScope,
        selected: AccountPresentation?,
        accounts: [AccountPresentation],
        capacity: Int = CardMetrics.stripChipCapacity,
        l10n: Localizer = english
    ) throws -> CardStripPlan {
        try #require(CardStripPlan.make(scope: scope, selected: selected, accounts: accounts, capacity: capacity, now: now, l10n: l10n))
    }

    // MARK: - Hero

    @Test("The hero shows what is left of the binding week, with what is used and the reset on the line below")
    func heroShowsRemaining() throws {
        let work = try Self.claude("Work")
        let plan = try Self.plan(.selectedAccount, selected: work, accounts: [work])
        let hero = try #require(plan.hero)
        #expect(hero.caption == "Weekly")
        #expect(hero.remainingFigure == "36%")
        #expect(hero.unit == "left")
        #expect(hero.usedLine == "64% used · ⟳ 5d 16h")
        #expect(hero.band == .watch)
        #expect(hero.accessibilityText == "Weekly, 36% left, 64% used, Resets in 5 days 16 hours")
    }

    @Test("Remaining is a hundred minus the rounded usage, never below zero")
    func remainingMath() throws {
        #expect(CardStripPlan.remainingPercent(try Percentage(validating: 64.4)) == 36)
        #expect(CardStripPlan.remainingPercent(try Percentage(validating: 64.5)) == 35)
        #expect(CardStripPlan.remainingPercent(try Percentage(validating: 0.3)) == 100)
        #expect(CardStripPlan.remainingPercent(try Percentage(validating: 100)) == 0)
        #expect(CardStripPlan.remainingPercent(try Percentage(validating: 130)) == 0)
        let out = try Self.claude("Work", weekly: 100)
        let hero = try #require(try Self.plan(.selectedAccount, selected: out, accounts: [out]).hero)
        #expect(hero.remainingFigure == "0%")
        #expect(hero.band == .exhausted)
    }

    @Test("The most constrained weekly window leads, whichever account or model it belongs to")
    func heroIsTheMostConstrainedWeek() throws {
        let work = try Self.claude("Work", weekly: 64, opus: 51)
        let personal = try Self.claude("Personal", weekly: 40, opus: 83)
        let plan = try Self.plan(.claude, selected: work, accounts: [work, personal])
        let hero = try #require(plan.hero)
        // Personal's Opus week is the fullest week in scope, and the caption names the account it belongs to.
        #expect(hero.caption == "Weekly · Opus · Personal")
        #expect(hero.remainingFigure == "17%")
        // The session window is fuller on neither account than the weeks, and would not count anyway.
        let busySession = try Self.claude("Busy", session: 95, weekly: 20, opus: 10)
        let sessionPlan = try Self.plan(.selectedAccount, selected: busySession, accounts: [busySession])
        #expect(sessionPlan.hero?.caption == "Weekly")
        #expect(sessionPlan.hero?.remainingFigure == "80%")
    }

    @Test("A Codex week counts as weekly by its length; without any week the binding window leads")
    func heroFallsBackToBinding() throws {
        let codex = try Self.codex("Side", primary: 34, secondary: 57)
        let hero = try #require(try Self.plan(.selectedAccount, selected: codex, accounts: [codex]).hero)
        #expect(hero.caption == "Weekly")
        #expect(hero.remainingFigure == "43%")

        let sessionOnly = try CardContentPlanTests.presentation(windows: [
            try UIFixture.window("session", .session, used: 71, duration: .fiveHours, resetsIn: 3_600),
        ])
        let fallback = try #require(try Self.plan(.selectedAccount, selected: sessionOnly, accounts: [sessionOnly]).hero)
        #expect(fallback.caption == "Session · 5h")
        #expect(fallback.remainingFigure == "29%")
        #expect(fallback.usedLine == "71% used · ⟳ 1h")
    }

    @Test("Equal usage goes to the earlier reset, and a window without a reset says only what is used")
    func heroTies() throws {
        let later = try Self.claude("Later", weekly: 64, weeklyResetsIn: 6 * 86_400)
        let sooner = try Self.claude("Sooner", weekly: 64, weeklyResetsIn: 2 * 86_400)
        let plan = try Self.plan(.allAccounts, selected: later, accounts: [later, sooner])
        #expect(plan.hero?.caption == "Weekly · Sooner")

        let timeless = try CardContentPlanTests.presentation(windows: [
            try UIFixture.window("week", .weekly(model: nil), used: 64, duration: nil, resetsIn: nil),
        ])
        let hero = try #require(try Self.plan(.selectedAccount, selected: timeless, accounts: [timeless]).hero)
        #expect(hero.usedLine == "64% used")
        #expect(!hero.accessibilityText.contains("Resets"))
    }

    // MARK: - Scope

    @Test("Each scope covers exactly the accounts it names, in settings order, and names itself in the header")
    func scopes() throws {
        let work = try Self.claude("Work")
        let side = try Self.codex("Side")
        let personal = try Self.claude("Personal")
        let all = [work, side, personal]

        let selected = try Self.plan(.selectedAccount, selected: side, accounts: all)
        #expect(selected.accountIDs == [side.id])
        #expect(selected.header.isSelectedAccount)
        #expect(selected.header.title == "Side")
        #expect(selected.header.provider == .codex)

        let claude = try Self.plan(.claude, selected: side, accounts: all)
        #expect(claude.accountIDs == [work.id, personal.id])
        #expect(!claude.header.isSelectedAccount)
        #expect(claude.header.title == "Claude")
        #expect(claude.header.provider == .claude)

        let codex = try Self.plan(.codex, selected: work, accounts: all)
        #expect(codex.accountIDs == [side.id])
        #expect(codex.header.title == "Codex")

        let everything = try Self.plan(.allAccounts, selected: work, accounts: all)
        #expect(everything.accountIDs == all.map(\.id))
        #expect(everything.header.title == "All accounts")
        #expect(everything.header.provider == nil)
        #expect(!everything.header.isSelectedAccount)
    }

    @Test("A scope with no matching account falls back to the account the card follows")
    func emptyScopeFallsBack() throws {
        let work = try Self.claude("Work")
        let plan = try Self.plan(.codex, selected: work, accounts: [work])
        #expect(plan.scope == .selectedAccount)
        #expect(plan.header.isSelectedAccount)
        #expect(plan.accountIDs == [work.id])
        // Without any account there is nothing to plan.
        #expect(CardStripPlan.make(scope: .allAccounts, selected: nil, accounts: [], capacity: 3, now: Self.now, l10n: Self.english) == nil)
        // Without a followed account the first one stands in.
        let first = try Self.plan(.selectedAccount, selected: nil, accounts: [work])
        #expect(first.accountIDs == [work.id])
    }

    // MARK: - Chips

    @Test("One account gives one chip per window, main bucket first, in the account's display order")
    func chipsOfOneAccount() throws {
        let work = try Self.claude("Work")
        let plan = try Self.plan(.selectedAccount, selected: work, accounts: [work])
        #expect(plan.chips.map(\.title) == ["Session · 5h", "Weekly", "Weekly · Opus"])
        #expect(plan.chips.map(\.percentText) == ["42%", "64%", "51%"])
        #expect(plan.chips.map(\.resetText) == ["⟳ 2h", "⟳ 5d 16h", "⟳ 5d"])
        #expect(plan.chips.allSatisfy { $0.accountsCount == 1 })
        #expect(plan.more == 0 && plan.moreText == nil)
        #expect(!plan.showsProviders)
        #expect(plan.chips[1].band == .watch)
        #expect(plan.chips[0].accessibilityText == "Claude, Session · 5h, 42% used, Resets in 2 hours")
    }

    @Test("Windows of the same kind on several accounts fold into one chip that shows the fullest and counts them")
    func chipsMerge() throws {
        let work = try Self.claude("Work", session: 42, weekly: 64, opus: 51)
        let personal = try Self.claude("Personal", session: 60, weekly: 40, opus: 83)
        let plan = try Self.plan(.claude, selected: work, accounts: [work, personal], capacity: 5)
        #expect(plan.chips.map(\.title) == ["Session · 5h", "Weekly", "Weekly · Opus"])
        #expect(plan.chips.map(\.percentText) == ["60%", "64%", "83%"])
        #expect(plan.chips.map(\.accountsCount) == [2, 2, 2])
        #expect(plan.chips[2].accessibilityText.hasSuffix("2 accounts"))
        #expect(plan.chips[2].band == .critical)
    }

    @Test("Codex and Claude windows never fold together, and mixed chips carry their provider")
    func chipsKeepProvidersApart() throws {
        let work = try Self.claude("Work")
        let side = try Self.codex("Side")
        let plan = try Self.plan(.allAccounts, selected: work, accounts: [work, side], capacity: 8)
        #expect(plan.chips.map(\.title) == ["Session · 5h", "Weekly", "Weekly · Opus", "5h", "Weekly"])
        #expect(plan.chips.map(\.provider) == [.claude, .claude, .claude, .codex, .codex])
        #expect(plan.showsProviders)
        #expect(Set(plan.chips.map(\.id)).count == plan.chips.count)
        #expect(plan.chips[3].accessibilityText.hasPrefix("Codex, 5h"))
    }

    @Test("Windows of other buckets come after every main-bucket window and carry their bucket's name")
    func otherBucketsLast() throws {
        let status = AccountStatus(
            profile: try UIFixture.profile("Side", provider: .codex),
            identity: nil,
            reading: try UIFixture.reading([
                try UIFixture.bucket("codex", title: "Codex", [
                    try UIFixture.window("primary", .rolling, used: 34, duration: .fiveHours, resetsIn: 3_600),
                    try UIFixture.window("secondary", .rolling, used: 57, duration: .oneWeek, resetsIn: 86_400),
                ]),
                try UIFixture.bucket("gpt5", title: "GPT-5", [
                    try UIFixture.window("primary", .rolling, used: 12, duration: .fiveHours, resetsIn: 3_600),
                ]),
            ]),
            sessions: []
        )
        let side = AccountPresentation(status: status, appearance: AppearanceSettings(), now: Self.now, l10n: Self.english)
        let other = try Self.claude("Work")
        let plan = try Self.plan(.allAccounts, selected: side, accounts: [side, other], capacity: 8)
        #expect(plan.chips.map(\.title) == ["5h", "Weekly", "Session · 5h", "Weekly", "Weekly · Opus", "GPT-5 · 5h"])
        #expect(plan.chips.last?.percentText == "12%")
    }

    @Test("More windows than fit show the first ones and a “+N” chip in the last slot")
    func overflow() throws {
        let work = try Self.claude("Work")
        let side = try Self.codex("Side")
        let plan = try Self.plan(.allAccounts, selected: work, accounts: [work, side], capacity: 3)
        #expect(plan.chips.count == 2)
        #expect(plan.chips.map(\.title) == ["Session · 5h", "Weekly"])
        #expect(plan.more == 3)
        #expect(plan.moreText == "+3")
        #expect(plan.moreAccessibilityText == "3 more windows")
        // Exactly as many as fit needs no "+N" chip.
        let exact = try Self.plan(.selectedAccount, selected: work, accounts: [work], capacity: 3)
        #expect(exact.chips.count == 3 && exact.more == 0)
        // A capacity of one still draws one chip when there is only one window.
        let single = try CardContentPlanTests.presentation(windows: [
            try UIFixture.window("week", .weekly(model: nil), used: 10, duration: .oneWeek, resetsIn: 86_400),
        ])
        let one = try Self.plan(.selectedAccount, selected: single, accounts: [single], capacity: 1)
        #expect(one.chips.count == 1 && one.more == 0)
    }

    @Test("Chip keys tell windows apart by provider, bucket and meaning")
    func chipKeys() throws {
        let appearance = AppearanceSettings()
        func present(_ window: LimitWindow, bucket: String = "main", main: Bool = true) -> WindowPresentation {
            WindowPresentation(bucketID: bucket, bucketTitle: nil, isMainBucket: main, window: window, appearance: appearance, now: Self.now, l10n: Self.english)
        }
        let week = present(try UIFixture.window("week", .weekly(model: nil), used: 1, duration: .oneWeek))
        let opus = present(try UIFixture.window("week.opus", .weekly(model: "Opus"), used: 1, duration: .oneWeek))
        let codexWeek = present(try UIFixture.window("secondary", .rolling, used: 1, duration: .oneWeek))
        let labelled = present(try UIFixture.window("x", .rolling, used: 1, duration: nil, label: "Current week (Opus)"))
        let unknown = present(try UIFixture.window("y", .rolling, used: 1, duration: nil))
        let elsewhere = present(try UIFixture.window("week", .weekly(model: nil), used: 1, duration: .oneWeek), bucket: "b2", main: false)
        let keys = [
            CardStripPlan.chipKey(week, provider: .claude),
            CardStripPlan.chipKey(opus, provider: .claude),
            CardStripPlan.chipKey(codexWeek, provider: .codex),
            CardStripPlan.chipKey(labelled, provider: .codex),
            CardStripPlan.chipKey(unknown, provider: .codex),
            CardStripPlan.chipKey(elsewhere, provider: .claude),
            CardStripPlan.chipKey(week, provider: .codex),
        ]
        #expect(Set(keys).count == keys.count)
        #expect(CardStripPlan.chipKey(week, provider: .claude) == CardStripPlan.chipKey(present(week.window), provider: .claude))
    }

    // MARK: - Words

    @Test("Russian says the same things in Russian")
    func russianCopy() throws {
        let work = try Self.claude("Work", l10n: Self.russian)
        let side = try Self.codex("Side", l10n: Self.russian)
        let plan = try Self.plan(.allAccounts, selected: work, accounts: [work, side], capacity: 8, l10n: Self.russian)
        let hero = try #require(plan.hero)
        #expect(hero.caption == "Неделя · Work")
        #expect(hero.unit == "осталось")
        #expect(hero.usedLine == "64% использовано · ⟳ 5\u{00A0}дн 16\u{00A0}ч")
        #expect(hero.accessibilityText.contains("осталось \(Self.russian.format.percent(36))"))
        #expect(plan.chips.map(\.title) == ["Сессия · 5\u{00A0}ч", "Неделя", "Неделя · Opus", "5\u{00A0}ч", "Неделя"])
        #expect(plan.header.title == "Все аккаунты")
        let merged = try Self.plan(.claude, selected: work, accounts: [work, try Self.claude("Personal", l10n: Self.russian)], l10n: Self.russian)
        #expect(merged.chips[0].accessibilityText.hasSuffix("2 аккаунта"))
        let overflow = try Self.plan(.allAccounts, selected: work, accounts: [work, side], capacity: 3, l10n: Self.russian)
        #expect(overflow.moreText == "+3")
        #expect(overflow.moreAccessibilityText == "ещё 3 окна")
    }

    @Test("The content plan carries the strip only when asked for a scope")
    func contentPlanCarriesTheStrip() throws {
        let work = try Self.claude("Work")
        let side = try Self.codex("Side")
        let plain = CardContentPlanTests.plan(work)
        #expect(plain.strip == nil)
        let strip = CardContentPlan(
            presentation: work,
            settings: .empty,
            thirdTile: .weeklyReset,
            serviceStatus: .empty,
            ceremonies: CeremonyBoard(),
            now: Self.now,
            l10n: Self.english,
            stripScope: .allAccounts,
            scopePresentations: [work, side]
        )
        #expect(strip.strip?.accountIDs == [work.id, side.id])
        // The other parts of the plan are unchanged by the scope: they still describe the followed account.
        #expect(strip.hero == plain.hero)
        #expect(strip.tiles == plain.tiles)
    }

    @Test("A merged strip's status pill and freshness cover its whole scope, and only its scope")
    func mergedScopeStatus() throws {
        let work = try Self.claude("Work")
        let blocked = try CardContentPlanTests.presentation(
            label: "Side",
            provider: .codex,
            windows: [try UIFixture.window("primary", .rolling, used: 100, duration: .fiveHours, resetsIn: 3_600)],
            limitReached: true,
            capturedAgo: 3_600
        )
        func plan(_ scope: CardStripScope) -> CardContentPlan {
            CardContentPlan(
                presentation: blocked,
                settings: .empty,
                thirdTile: .weeklyReset,
                serviceStatus: .empty,
                ceremonies: CeremonyBoard(),
                now: Self.now,
                l10n: Self.english,
                stripScope: scope,
                scopePresentations: [work, blocked]
            )
        }
        // The followed account is blocked and stale, but the Claude scope does not include it.
        #expect(plan(.claude).pill == nil)
        #expect(plan(.claude).updated == Self.english.card.updated(Self.english.format.clock(Self.now.addingTimeInterval(-60))))
        // Every scope that includes it reports it, and says how old its oldest reading is.
        #expect(plan(.allAccounts).pill?.kind == .limitReached)
        #expect(plan(.allAccounts).updated == Self.english.card.updated(Self.english.format.clock(Self.now.addingTimeInterval(-3_600))))
        #expect(plan(.selectedAccount).pill?.kind == .limitReached)
        #expect(plan(.codex).pill?.kind == .limitReached)
    }
}
