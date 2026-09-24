import CodometerCore
import CodometerL10n
@testable import CodometerWidgetsUI
import AppKit
import Foundation
import Testing

// MARK: - Fixtures

private enum StripFixture {
    static let now = Fixture.now

    static func item(_ window: LimitWindow, bucket: String = "main", main: Bool = true, language: Language = .en) throws -> WidgetWindow {
        try WidgetWindow(bucketID: bucket, isMainBucket: main, window: window, language: language)
    }

    static func account(
        _ label: String,
        provider: ProviderKind = .claude,
        windows: [WidgetWindow],
        capturedAt: Date? = now,
        isLimitReached: Bool = false
    ) throws -> WidgetAccount {
        try WidgetAccount(
            id: AccountID(),
            label: label,
            provider: provider,
            windows: windows,
            capturedAt: capturedAt,
            isLimitReached: isLimitReached
        )
    }

    static func snapshot(_ accounts: [WidgetAccount], layout: WidgetLayout = .strip, language: Language = .en) -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: now,
            accounts: accounts,
            bands: .standard,
            attentionCount: 0,
            workingCount: 0,
            language: language,
            layout: layout
        )
    }

    static func states(_ accounts: [WidgetAccount]) -> [WidgetAccountState] {
        snapshot(accounts).states(at: now)
    }

    /// A Claude account: a session window and two weekly ones.
    static func claude(_ label: String, session: Double, week: Double, fable: Double) throws -> WidgetAccount {
        try account(label, windows: [
            try item(try Fixture.window("session", .session, used: session, minutes: 300, resetsIn: 2 * 3_600), bucket: "claude"),
            try item(try Fixture.window("week", .weekly(model: nil), used: week, minutes: 10_080, resetsIn: 4 * 86_400), bucket: "claude"),
            try item(try Fixture.window("week.fable", .weekly(model: "Fable"), used: fable, minutes: 10_080, resetsIn: 4 * 86_400), bucket: "claude"),
        ])
    }

    /// A Codex account: a 5-hour window, a week-long rolling one, and a Spark bucket window.
    static func codex(_ label: String, primary: Double, secondary: Double) throws -> WidgetAccount {
        try account(label, provider: .codex, windows: [
            try item(try Fixture.window("primary", used: primary, minutes: 300, resetsIn: 3 * 3_600), bucket: "codex"),
            try item(try Fixture.window("secondary", used: secondary, minutes: 10_080, resetsIn: 2 * 86_400), bucket: "codex"),
            try WidgetWindow(
                bucketID: "spark",
                bucketTitle: "GPT-5.3-Codex-Spark",
                isMainBucket: false,
                window: try Fixture.window("primary", used: 12, minutes: 300, resetsIn: 3_600),
                language: .en
            ),
        ])
    }
}

// MARK: - Settings

@Suite("Widget layout setting")
struct WidgetLayoutSettingTests {
    private func general(_ json: String) throws -> GeneralSettings {
        try JSONDecoder().decode(GeneralSettings.self, from: Data(json.utf8))
    }

    @Test("Rings is the default, also for a settings file written before the key existed")
    func missingIsRings() throws {
        #expect(GeneralSettings().widgetLayout == .rings)
        #expect(try general(#"{"launchesAtLogin": true}"#).widgetLayout == .rings)
        let file = try AppSettings.decodeFile(Data(#"{"schemaVersion": 1, "accounts": [], "general": {"exportsWidgetData": true}}"#.utf8))
        #expect(file.settings.general.widgetLayout == .rings)
        #expect(file.repairs.isEmpty)
        #expect(AppSettings.currentSchemaVersion == 1)
    }

    @Test("Unknown, null and mistyped values fall back to rings without failing the file", arguments: [
        #"{"widgetLayout": "bento"}"#, #"{"widgetLayout": null}"#, #"{"widgetLayout": 2}"#, #"{"widgetLayout": ["strip"]}"#, #"{"widgetLayout": "Strip"}"#,
    ])
    func lenient(json: String) throws {
        let decoded = try general(json)
        #expect(decoded.widgetLayout == .rings)
        #expect(decoded.exportsWidgetData == GeneralSettings().exportsWidgetData)
    }

    @Test("An unusable value is noted as a repair; a missing one is not")
    func repairs() throws {
        let broken = try AppSettings.decodeFile(Data(#"{"schemaVersion": 1, "accounts": [], "general": {"widgetLayout": "bento"}}"#.utf8))
        #expect(broken.settings.general.widgetLayout == .rings)
        #expect(broken.repairs == ["general.widgetLayout"])
    }

    @Test("Every choice round-trips and is always written", arguments: WidgetLayout.allCases)
    func roundTrip(layout: WidgetLayout) throws {
        let settings = GeneralSettings(widgetLayout: layout)
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(GeneralSettings.self, from: data) == settings)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["widgetLayout"] as? String == layout.rawValue)
        #expect(try general(#"{"widgetLayout": "\#(layout.rawValue)"}"#).widgetLayout == layout)
    }
}

// MARK: - Snapshot

@Suite("Widget layout in the snapshot")
struct WidgetLayoutSnapshotTests {
    private static func account() throws -> WidgetAccount {
        try StripFixture.claude("Claude", session: 40, week: 30, fable: 20)
    }

    @Test("The layout round-trips; a version-1 file, a missing key and an unknown value read as rings")
    func coding() throws {
        let account = try Self.account()
        for layout in WidgetLayout.allCases {
            let snapshot = StripFixture.snapshot([account], layout: layout)
            let data = try snapshot.encodedData()
            let decoded = try #require(WidgetSnapshot.decode(data))
            #expect(decoded.layout == layout)
            #expect(decoded == snapshot)
            #expect(String(decoding: data, as: UTF8.self).contains("\"layout\":\"\(layout.rawValue)\""))
        }
        #expect(WidgetSnapshot.currentVersion == 2)
        #expect(StripFixture.snapshot([account]).version == 2)
        func decoded(_ fields: String) throws -> WidgetSnapshot {
            try #require(WidgetSnapshot.decode(Data("{\"accounts\": []\(fields)}".utf8)))
        }
        #expect(try decoded(", \"version\": 1").layout == .rings)
        #expect(try decoded("").layout == .rings)
        #expect(try decoded(#", "layout": "bento""#).layout == .rings)
        #expect(try decoded(#", "layout": 7"#).layout == .rings)
        #expect(try decoded(#", "layout": "strip""#).layout == .strip)
        // Whatever the file said, the decoded snapshot reports this build's version.
        #expect(try decoded(", \"version\": 1").version == WidgetSnapshot.currentVersion)
        #expect(try decoded(", \"version\": 9").version == WidgetSnapshot.currentVersion)
    }

    @Test("A layout change alone is new, significant content, published within the significant gap")
    func significance() throws {
        let account = try Self.account()
        let rings = StripFixture.snapshot([account], layout: .rings)
        let strip = StripFixture.snapshot([account], layout: .strip)
        #expect(!rings.hasSameContent(as: strip))
        #expect(rings.significance != strip.significance)
        var policy = WidgetExportPolicy()
        policy.recordPublish(rings, at: StripFixture.now)
        let due = StripFixture.now.addingTimeInterval(WidgetExportPolicy.significantGap)
        #expect(policy.decision(for: strip, now: StripFixture.now.addingTimeInterval(1)) == .wait(until: due))
        #expect(policy.decision(for: strip, now: due) == .publish)
        // Nothing else about the content moved: without the layout change it would only be routine.
        #expect(policy.decision(for: rings, now: due) == .skipIdentical)
    }

    @Test("The builder takes the layout from the general settings", arguments: WidgetLayout.allCases)
    func builder(layout: WidgetLayout) throws {
        let profile = try AccountProfile(
            provider: .claude,
            label: try AccountLabel(validating: "Claude"),
            directory: try ProfileDirectory(validating: "/tmp/.claude-strip")
        )
        let settings = try AppSettings(accounts: [profile], general: GeneralSettings(widgetLayout: layout))
        let state = TrackerState(accounts: [AccountStatus(profile: profile)])
        let snapshot = WidgetSnapshot.make(state: state, settings: settings, now: StripFixture.now, language: .en)
        #expect(snapshot.layout == layout)
    }

    @Test("Scoping to a provider keeps the layout and the forecast setting")
    func scoped() throws {
        let claude = try Self.account()
        let codex = try StripFixture.codex("Codex", primary: 10, secondary: 20)
        let snapshot = WidgetSnapshot(
            generatedAt: StripFixture.now,
            accounts: [claude, codex],
            bands: .standard,
            attentionCount: 0,
            workingCount: 0,
            language: .ru,
            showsForecast: false,
            layout: .strip
        )
        let scoped = snapshot.scoped(to: .provider(.codex))
        #expect(scoped.accounts.map(\.label) == ["Codex"])
        #expect(scoped.layout == .strip)
        #expect(scoped.showsForecast == false)
        #expect(scoped.language == .ru)
    }

    @Test("Sample data and the gallery preview follow the layout the app's snapshot names")
    func sample() throws {
        #expect(WidgetSampleData.snapshot(now: StripFixture.now, language: .en).layout == .rings)
        #expect(WidgetSampleData.snapshot(now: StripFixture.now, language: .en, layout: .strip).layout == .strip)
        // A provider without accounts gets sample numbers in the user's layout.
        let onlyClaude = StripFixture.snapshot([try Self.account()], layout: .strip)
        let preview = LimitsTimelineProvider.previewEntry(for: onlyClaude, scope: .provider(.codex), isPreview: true, now: StripFixture.now)
        #expect(preview.snapshot?.layout == .strip)
        #expect(preview.snapshot?.accounts.map(\.provider) == [.codex])
        #expect(LimitsTimelineProvider.previewEntry(for: nil, scope: .all, isPreview: true, now: StripFixture.now).snapshot?.layout == .rings)
    }
}

// MARK: - Plan

@Suite("Widget strip plan")
struct WidgetStripPlanTests {
    @Test("The headline is the most constrained weekly window across the accounts in scope")
    func hero() throws {
        let claude = try StripFixture.claude("Claude", session: 90, week: 38, fable: 63)
        let codex = try StripFixture.codex("Codex", primary: 18, secondary: 84)
        let plan = WidgetStripPlan(states: StripFixture.states([claude, codex]), chipLimit: 9)
        let hero = try #require(plan.hero)
        // Codex's week-long window is the busiest weekly one, though Claude's session is busier still.
        #expect(hero.account.account.label == "Codex")
        #expect(hero.window.window.id == "secondary")
        #expect(hero.window.isWeekly)
        #expect(hero.accountCount == 1)
        #expect(WidgetStripPlan.remaining(of: hero.window).value == 16)
    }

    @Test("Without a weekly window the ring window of the most constrained account is the headline")
    func heroFallback() throws {
        let short = try StripFixture.account("Codex", provider: .codex, windows: [
            try StripFixture.item(try Fixture.window("primary", used: 30, minutes: 300, resetsIn: 3_600), bucket: "codex"),
            try StripFixture.item(try Fixture.window("hourly", used: 70, minutes: 60, resetsIn: 600), bucket: "codex"),
        ])
        let plan = WidgetStripPlan(states: StripFixture.states([short]), chipLimit: 9)
        #expect(plan.hero?.window.window.id == "hourly")
        #expect(plan.hero?.window.isWeekly == false)
        #expect(plan.chips.map(\.window.window.id) == ["primary"])

        // No readings at all: no headline, and no chips either.
        let empty = try WidgetAccount(id: AccountID(), label: "Codex", provider: .codex, notice: "Not signed in")
        let none = WidgetStripPlan(states: StripFixture.states([empty]), chipLimit: 4)
        #expect(none.hero == nil)
        #expect(none.chips.isEmpty)
        #expect(none.overflow == 0)
        #expect(WidgetStripPlan(states: [], chipLimit: 4).hero == nil)
    }

    @Test("Ties between weekly windows go to the more constrained account, then the earlier one")
    func heroTies() throws {
        let calm = try StripFixture.claude("Calm", session: 10, week: 50, fable: 20)
        let busy = try StripFixture.claude("Busy", session: 95, week: 50, fable: 20)
        let plan = WidgetStripPlan(states: StripFixture.states([calm, busy]), chipLimit: 9)
        #expect(plan.hero?.account.account.label == "Busy")
        #expect(plan.hero?.window.window.id == "week")
        // Both accounts have a "Weekly · All models" window: the headline says so.
        #expect(plan.hero?.accountCount == 2)
        let same = WidgetStripPlan(states: StripFixture.states([calm, try StripFixture.claude("Calm 2", session: 10, week: 50, fable: 20)]), chipLimit: 9)
        #expect(same.hero?.account.account.label == "Calm")
    }

    @Test("Chips: one per window title in display order, the headline's title left out, shared titles counted")
    func chips() throws {
        let work = try StripFixture.claude("Claude · Work", session: 57, week: 38, fable: 63)
        let home = try StripFixture.claude("Claude · Home", session: 20, week: 12, fable: 8)
        let codex = try StripFixture.codex("Codex", primary: 18, secondary: 30)
        let plan = WidgetStripPlan(states: StripFixture.states([work, home, codex]), chipLimit: 9)
        #expect(plan.hero?.window.window.id == "week.fable")
        #expect(plan.hero?.account.account.label == "Claude · Work")
        #expect(plan.hero?.accountCount == 2)
        #expect(plan.chips.map(\.title) == ["Session · 5h", "Weekly · All models", "5h", "Weekly", "Spark · 5h"])
        #expect(plan.chips.map(\.accountCount) == [2, 2, 1, 1, 1])
        // A shared chip shows the most constrained of the windows behind it.
        #expect(plan.chips[0].account.account.label == "Claude · Work")
        #expect(plan.chips[0].window.window.used.value == 57)
        #expect(plan.chips[1].window.window.used.value == 38)
        #expect(plan.overflow == 0)
        #expect(Set(plan.chips.map(\.id)).count == plan.chips.count)
    }

    @Test("Overflow: the last places make way for a +N tile that counts every window left out")
    func overflow() throws {
        let work = try StripFixture.claude("Claude · Work", session: 57, week: 38, fable: 63)
        let codex = try StripFixture.codex("Codex", primary: 18, secondary: 30)
        let states = StripFixture.states([work, codex])
        // Five chips besides the headline.
        #expect(WidgetStripPlan(states: states, chipLimit: 9).chips.count == 5)
        let medium = WidgetStripPlan(states: states, chipLimit: 4)
        #expect(medium.chips.map(\.title) == ["Session · 5h", "Weekly · All models", "5h"])
        #expect(medium.overflow == 2)
        let exact = WidgetStripPlan(states: states, chipLimit: 5)
        #expect(exact.chips.count == 5)
        #expect(exact.overflow == 0)
        let one = WidgetStripPlan(states: states, chipLimit: 1)
        #expect(one.chips.isEmpty)
        #expect(one.overflow == 5)
        let none = WidgetStripPlan(states: states, chipLimit: 0)
        #expect(none.chips.isEmpty)
        #expect(none.overflow == 5)
    }

    @Test("An account's own row leaves out only its share of the headline")
    func perAccount() throws {
        let work = try StripFixture.claude("Claude · Work", session: 57, week: 38, fable: 63)
        let home = try StripFixture.claude("Claude · Home", session: 20, week: 12, fable: 40)
        let states = StripFixture.states([work, home])
        let hero = WidgetStripPlan(states: states, chipLimit: 6).hero
        #expect(hero?.account.account.label == "Claude · Work")
        let workRow = WidgetStripPlan.chips(for: states[0], hero: hero, limit: 3)
        #expect(workRow.chips.map(\.title) == ["Session · 5h", "Weekly · All models"])
        #expect(workRow.overflow == 0)
        // The other account keeps its own "Weekly · Fable": it is not the headline.
        let homeRow = WidgetStripPlan.chips(for: states[1], hero: hero, limit: 3)
        #expect(homeRow.chips.map(\.title) == ["Session · 5h", "Weekly · All models", "Weekly · Fable"])
        #expect(homeRow.chips.allSatisfy { $0.accountCount == 1 })
        let squeezed = WidgetStripPlan.chips(for: states[1], hero: hero, limit: 2)
        #expect(squeezed.chips.map(\.title) == ["Session · 5h"])
        #expect(squeezed.overflow == 2)
    }

    @Test("What is left and what is used add up, clamped at the limit")
    func remaining() throws {
        func remaining(_ used: Double) throws -> Percentage {
            let window = try StripFixture.item(try Fixture.window("w", used: used, minutes: 10_080, resetsIn: 86_400))
            return WidgetStripPlan.remaining(of: WidgetWindowState(source: window, date: StripFixture.now, thresholds: .standard))
        }
        #expect(try remaining(36).value == 64)
        #expect(try remaining(0).value == 100)
        #expect(try remaining(100).value == 0)
        #expect(try remaining(130).value == 0)
        #expect(WidgetText.percentNumber(try remaining(99.5)) == "<1")
        #expect(WidgetText.percentNumber(try remaining(36.4)) == "64")
    }

    @Test("Weekly windows: the provider's weekly scope, or a length of about a week")
    func weekly() throws {
        func state(_ scope: LimitWindowScope, minutes: Int?) throws -> WidgetWindowState {
            let window = try StripFixture.item(try Fixture.window("w", scope, used: 10, minutes: minutes, resetsIn: 3_600))
            return WidgetWindowState(source: window, date: StripFixture.now, thresholds: .standard)
        }
        #expect(try state(.weekly(model: nil), minutes: 10_080).isWeekly)
        #expect(try state(.weekly(model: "Fable"), minutes: nil).isWeekly)
        #expect(try state(.rolling, minutes: 10_080).isWeekly)
        #expect(try state(.rolling, minutes: 6 * 1_440).isWeekly)
        #expect(try !state(.rolling, minutes: 300).isWeekly)
        #expect(try !state(.rolling, minutes: 43_200).isWeekly)
        #expect(try !state(.session, minutes: 300).isWeekly)
        #expect(try !state(.rolling, minutes: nil).isWeekly)
    }
}

// MARK: - Copy

@Suite("Widget strip phrases")
struct WidgetStripPhraseTests {
    @Test("English and Russian phrases of the strip")
    func phrases() {
        let en = Localizer.testEnglish
        #expect(en.widget.leftUnit == "left")
        #expect(en.widget.usedResetsIn(en.format.percent(36)).prefix == "36% used · in ")
        #expect(en.widget.usedResetsIn(en.format.percent(36)).suffix.isEmpty)
        #expect(en.widget.usedNoReset(en.format.percent(36)) == "36% used")
        #expect(en.widget.moreWindows(1) == "1 more window")
        #expect(en.widget.moreWindows(3) == "3 more windows")
        #expect(en.widget.accountsSharing(2) == "2 accounts")
        #expect(en.widget.percentLeftA11y("Weekly", left: en.format.percent(64), used: en.format.percent(36)) == "Weekly: 64% left, 36% used")
        #expect(en.widget.chipA11y("Session · 5h", used: en.format.percent(42)) == "Session · 5h: 42% used")
        #expect(en.general.widgetLayout == "Widget layout")
        #expect(en.general.widgetLayoutRings == "Rings")
        #expect(en.general.widgetLayoutStrip == "Strip")

        let ru = Localizer.testRussian
        #expect(ru.widget.leftUnit == "осталось")
        #expect(ru.widget.usedResetsIn(ru.format.percent(36)).prefix == "расход 36\u{00A0}% · через ")
        #expect(ru.widget.usedNoReset(ru.format.percent(36)) == "расход 36\u{00A0}%")
        #expect(ru.widget.moreWindows(1) == "ещё 1 окно")
        #expect(ru.widget.moreWindows(3) == "ещё 3 окна")
        #expect(ru.widget.moreWindows(11) == "ещё 11 окон")
        #expect(ru.widget.accountsSharing(1) == "1 аккаунт")
        #expect(ru.widget.accountsSharing(2) == "2 аккаунта")
        #expect(ru.widget.accountsSharing(5) == "5 аккаунтов")
        #expect(ru.widget.percentLeftA11y("Неделя", left: ru.format.percent(64), used: ru.format.percent(36)) == "Неделя: осталось 64\u{00A0}%, использовано 36\u{00A0}%")
        #expect(ru.widget.chipA11y("Сессия · 5\u{00A0}ч", used: ru.format.percent(42)) == "Сессия · 5\u{00A0}ч: использовано 42\u{00A0}%")
        #expect(ru.general.widgetLayout == "Вид виджета")
        #expect(ru.general.widgetLayoutRings == "Кольца")
        #expect(ru.general.widgetLayoutStrip == "Полоса")
    }
}

// MARK: - Copy fit

/// The strip's live countdowns and captions measured in the widget's real font against the room the tiles give
/// them, in both languages (the same method as `WidgetCopyFitTests`).
@Suite("Widget strip copy fit")
struct WidgetStripCopyFitTests {
    /// Content width inside the medium and large widgets' 16 pt margins.
    static let contentWidth: CGFloat = 344 - 32
    /// A tile of the medium grid: the headline column and the gaps taken off, two per row.
    static let mediumChipWidth = (contentWidth - StripLimitsView.mediumHeroWidth - 10 - StripLimitsView.chipSpacing) / 2
    /// A tile of a three-per-row grid in the large widget.
    static let largeChipWidth = (contentWidth - 2 * StripLimitsView.chipSpacing) / 3
    /// The countdown line's symbol and the spacing after it.
    static let symbolRoom: CGFloat = 8 + 2.5

    private static func inner(_ width: CGFloat, _ metrics: StripChipMetrics) -> CGFloat {
        width - 2 * (metrics.padding + 2)
    }

    @Test("Every countdown fits the countdown line of every tile at no less than 80 %", arguments: Language.allCases)
    func chipCountdowns(language: Language) {
        let l10n = WidgetCopyFitTests.localizer(language)
        let tiles: [(String, CGFloat, StripChipMetrics)] = [
            ("medium", Self.mediumChipWidth, .medium),
            ("large", Self.largeChipWidth, .large),
            ("row", Self.largeChipWidth, .row),
        ]
        for (name, width, metrics) in tiles {
            let room = Self.inner(width, metrics) - Self.symbolRoom
            let font = WidgetCopyFitTests.font(metrics.countdownSize, .medium, digits: true)
            for countdown in WidgetCopyFitTests.countdowns(l10n) {
                #expect(WidgetCopyFitTests.fits(countdown, font, in: room, scale: 0.8), "\(name): \(countdown) is \(WidgetCopyFitTests.width(countdown, font)) pt of \(room) pt")
            }
            // A stale tile shows the reading's time instead.
            for time in WidgetCopyFitTests.readingTimes(l10n) {
                #expect(WidgetCopyFitTests.fits(time, font, in: room, scale: 0.8), "\(name): \(time)")
            }
            // The widest usage fits its own line outright: it is never scaled.
            let percent = WidgetCopyFitTests.font(metrics.percentSize, .bold, digits: true)
            #expect(WidgetCopyFitTests.fits(WidgetText.percent(.full), percent, in: Self.inner(width, metrics)))
        }
    }

    @Test("The medium headline column holds its number, unit and both caption lines", arguments: Language.allCases)
    func mediumHero(language: Language) {
        let l10n = WidgetCopyFitTests.localizer(language)
        let widget = l10n.widget
        let room = StripLimitsView.mediumHeroWidth
        let caption = WidgetCopyFitTests.font(10.5, .medium, digits: true)
        // "⟳ 100% used" | «⟳ расход 100 %», then "Resets in 6 days, 22 hr" | «через 6 дн 22 ч» on the next line.
        let used = widget.usedNoReset(l10n.format.percent(100))
        #expect(WidgetCopyFitTests.fits(used, caption, in: room - Self.symbolRoom, scale: 0.85), "\(used)")
        for countdown in WidgetCopyFitTests.countdowns(l10n) {
            let resets = widget.resetsInShort.prefix + countdown + widget.resetsInShort.suffix
            #expect(WidgetCopyFitTests.fits(resets, caption, in: room, scale: 0.85), "\(resets): \(WidgetCopyFitTests.width(resets, caption)) pt")
            let back = widget.backIn.prefix + countdown + widget.backIn.suffix
            #expect(WidgetCopyFitTests.fits(back, caption, in: room - Self.symbolRoom, scale: 0.85), "\(back)")
        }
        for time in WidgetCopyFitTests.readingTimes(l10n) {
            let stale = widget.staleAsOf.prefix + time + widget.staleAsOf.suffix
            #expect(WidgetCopyFitTests.fits(stale, caption, in: room - Self.symbolRoom, scale: 0.85), "\(stale)")
        }
        // The number is never scaled; the unit moves under it when the two do not share a line.
        let number = WidgetCopyFitTests.width("100", WidgetCopyFitTests.font(34, .bold, digits: true))
            + 1 + WidgetCopyFitTests.width("%", WidgetCopyFitTests.font(34 * 0.46, .bold))
        #expect(number <= room)
        #expect(WidgetCopyFitTests.fits(widget.leftUnit, WidgetCopyFitTests.font(11.5, .medium), in: room))
        // The widest window title fits the caption above the number beside a sharing badge, at 80 %.
        let title = WidgetCopyFitTests.font(10.5, .semibold)
        #expect(WidgetCopyFitTests.fits(l10n.window.weeklyAllModels, title, in: room - 5 - 24, scale: 0.8))
    }

    @Test("The large headline's caption fits beside the identity column: one line in English, two lines always", arguments: Language.allCases)
    func largeHero(language: Language) {
        let l10n = WidgetCopyFitTests.localizer(language)
        let widget = l10n.widget
        // The identity column takes at most 150 pt plus its 14 pt gap.
        let room = Self.contentWidth - 150 - 14
        let caption = WidgetCopyFitTests.font(10.5, .medium, digits: true)
        for countdown in WidgetCopyFitTests.countdowns(l10n) {
            // `ViewThatFits` falls back to the two-line form, which must always fit.
            let resets = widget.resetsInShort.prefix + countdown + widget.resetsInShort.suffix
            #expect(WidgetCopyFitTests.fits(resets, caption, in: room, scale: 0.85), "\(resets)")
            // English keeps the one-line form for every countdown up to a day; longer ones may stack.
            if language == .en, !countdown.contains("day") {
                let slot = widget.usedResetsIn(l10n.format.percent(100))
                let line = slot.prefix + countdown + slot.suffix
                #expect(WidgetCopyFitTests.fits(line, caption, in: room - Self.symbolRoom, scale: 0.85), "\(line): \(WidgetCopyFitTests.width(line, caption)) pt of \(room) pt")
            }
        }
        #expect(WidgetCopyFitTests.fits(widget.usedNoReset(l10n.format.percent(100)), caption, in: room - Self.symbolRoom, scale: 0.85))
    }

    @Test("The header keeps its title beside the widest badge", arguments: Language.allCases)
    func header(language: Language) {
        let l10n = WidgetCopyFitTests.localizer(language)
        let widget = l10n.widget
        let title = WidgetCopyFitTests.width(widget.allName, WidgetCopyFitTests.font(13, .bold))
        let badge = 2 * 6 + 12 + 3 + WidgetCopyFitTests.width(widget.waiting(12), WidgetCopyFitTests.font(11, .semibold, digits: true))
        #expect(StripLimitsView.largeHeaderHeight + 6 + title + 6 + badge <= Self.contentWidth)
        // The overflow tile and the footer.
        #expect(WidgetCopyFitTests.fits(widget.moreAccounts(14), WidgetCopyFitTests.font(11.5, .medium), in: Self.contentWidth))
        #expect(WidgetCopyFitTests.fits("+12", WidgetCopyFitTests.font(14, .semibold, digits: true), in: Self.inner(Self.mediumChipWidth, .medium)))
    }
}
