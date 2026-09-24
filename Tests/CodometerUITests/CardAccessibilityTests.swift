import CodometerCore
import CodometerL10n
@testable import CodometerUI
import Foundation
import Testing

/// What VoiceOver reads on the card and on the pill: words instead of compact units, and never a colour on its own.
@Suite("Card accessibility")
struct CardAccessibilityTests {
    static let now = UIFixture.now
    static let english = Localizer.testEnglish
    static let russian = Localizer.testRussian

    private func windows() throws -> [LimitWindow] {
        [
            try UIFixture.window("session", .session, used: 42, duration: .fiveHours, resetsIn: 7_200),
            try UIFixture.window("week", .weekly(model: nil), used: 64, duration: .oneWeek, resetsIn: 5 * 86_400 + 16 * 3_600),
        ]
    }

    @Test("Durations are spoken in words, never as “5d 16h”")
    func spokenDurations() throws {
        let presentation = try CardContentPlanTests.presentation(windows: try windows())
        let plan = CardContentPlanTests.plan(presentation)
        let reset = try #require(plan.tiles.first { $0.kind == .reset })
        #expect(reset.value == "5d 16h")
        #expect(reset.accessibilityText == "Resets in 5 days 16 hours")
        #expect(!reset.accessibilityText.contains("5d"))
    }

    @Test("The hero says the window, the percentage in words and the forecast")
    func heroSpeech() throws {
        let presentation = try CardContentPlanTests.presentation(windows: [
            try UIFixture.window("week", .weekly(model: nil), used: 60, duration: .oneWeek, resetsIn: 3.5 * 86_400),
        ])
        let hero = try #require(CardContentPlanTests.plan(presentation).hero)
        #expect(hero.accessibilityText.contains("Weekly"))
        #expect(hero.accessibilityText.contains("60% used"))
        #expect(hero.accessibilityText.contains("forecast"))
        #expect(hero.accessibilityText.contains("at reset"))
    }

    @Test("The pill says the account, its usage, when it resets and which of several it is")
    func pillSummary() throws {
        let first = try CardContentPlanTests.presentation(label: "Work", windows: try windows())
        let second = try CardContentPlanTests.presentation(label: "Personal", windows: try windows())
        let third = try CardContentPlanTests.presentation(label: "Side", provider: .codex, windows: try windows())
        let accounts = [first, second, third]
        let summary = CardContentPlan.pillSummary(showing: first, accounts: accounts, now: Self.now, l10n: Self.english)
        #expect(summary.hasPrefix("Work"))
        #expect(summary.contains("64% used"))
        #expect(summary.contains("5 days 16 hours"))
        #expect(summary.contains("Account 1 of 3"))
        #expect(Self.english.card.pillA11y(summary).hasPrefix("Codometer, minimized. "))
    }

    @Test("A single account's pill never counts itself")
    func singleAccountPill() throws {
        let only = try CardContentPlanTests.presentation(windows: try windows())
        let summary = CardContentPlan.pillSummary(showing: only, accounts: [only], now: Self.now, l10n: Self.english)
        #expect(!summary.contains("Account 1 of"))
    }

    @Test("An account without a reading still says something")
    func noReading() {
        #expect(CardContentPlan.pillSummary(showing: nil, accounts: [], now: Self.now, l10n: Self.english) == "No data")
    }

    @Test("Russian speaks Russian, with its own plural forms")
    func russianSpeech() throws {
        let presentation = try CardContentPlanTests.presentation(windows: try windows(), l10n: Self.russian)
        let plan = CardContentPlanTests.plan(presentation, l10n: Self.russian)
        let reset = try #require(plan.tiles.first { $0.kind == .reset })
        #expect(reset.accessibilityText.hasPrefix("Сброс через"))
        #expect(reset.accessibilityText.contains("дн"))
        let summary = CardContentPlan.pillSummary(showing: presentation, accounts: [presentation], now: Self.now, l10n: Self.russian)
        #expect(summary.contains("использовано"))
        #expect(Self.russian.card.pillA11y(summary).hasPrefix("Codometer, свёрнуто. "))
    }

    @Test("Every tile carries words, so colour is never the only signal")
    func everyTileHasWords() throws {
        let blocked = try CardContentPlanTests.presentation(
            windows: [try UIFixture.window("week", .weekly(model: nil), used: 100, duration: .oneWeek, resetsIn: 30 * 3_600)],
            limitReached: true
        )
        for thirdTile in CardThirdTile.allCases {
            let plan = CardContentPlanTests.plan(blocked, thirdTile: thirdTile)
            #expect(plan.tiles.count == 3)
            for tile in plan.tiles {
                #expect(!tile.label.isEmpty, "\(tile.kind)")
                #expect(!tile.value.isEmpty, "\(tile.kind)")
                #expect(!tile.accessibilityText.isEmpty, "\(tile.kind)")
            }
            let pill = try #require(plan.pill)
            #expect(!pill.text.isEmpty)
        }
    }

    @Test("The status pill's tooltip names every current item, not only the winner")
    func tooltipListsEverything() throws {
        let presentation = try CardContentPlanTests.presentation(
            windows: [try UIFixture.window("week", .weekly(model: nil), used: 100, duration: .oneWeek, resetsIn: 30 * 3_600)],
            limitReached: true,
            sessions: [try UIFixture.session("a", .waiting)]
        )
        let pill = try #require(CardContentPlanTests.plan(presentation).pill)
        #expect(pill.tooltip.contains("1 waiting"))
        #expect(pill.tooltip.contains("Limit reached"))
    }

    @Test("The strip's hero and every chip carry words: the window, the figures spoken with their units, the reset")
    func stripSpeech() throws {
        let work = try CardContentPlanTests.presentation(label: "Work", windows: try windows())
        let personal = try CardContentPlanTests.presentation(label: "Personal", windows: try windows())
        let plan = try #require(CardStripPlan.make(scope: .claude, selected: work, accounts: [work, personal], capacity: 3, now: Self.now, l10n: Self.english))
        let hero = try #require(plan.hero)
        #expect(hero.accessibilityText.contains("36% left"))
        #expect(hero.accessibilityText.contains("64% used"))
        #expect(hero.accessibilityText.contains("5 days 16 hours"))
        #expect(!hero.accessibilityText.contains("5d"))
        for chip in plan.chips {
            #expect(chip.accessibilityText.hasPrefix("Claude, "))
            #expect(chip.accessibilityText.contains("% used"))
            #expect(chip.accessibilityText.hasSuffix("2 accounts"))
            #expect(!chip.title.isEmpty && !chip.percentText.isEmpty)
        }
        let russian = try #require(CardStripPlan.make(scope: .selectedAccount, selected: work, accounts: [work], capacity: 3, now: Self.now, l10n: Self.russian))
        #expect(russian.hero?.accessibilityText.contains("осталось \(Self.russian.format.percent(36))") == true)
        #expect(russian.chips.first?.accessibilityText.contains("Сброс через") == true)
    }

    @Test("Every hit target the card draws is at least 24 points across")
    func hitTargets() {
        for scale in [0.75, 1.0, 1.5] {
            let metrics = CardMetrics(scale: scale)
            #expect(metrics.minimizeButton >= 24, "minimize at \(scale)")
            // Page dots and the status pill draw small but take a 24 pt target (see `CardPageDots`,
            // `CardStatusPill`); the pill form itself is a single button of the pill's own height.
            #expect(metrics.pillHeight >= 24, "pill at \(scale)")
        }
    }
}
