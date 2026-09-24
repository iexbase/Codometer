import CodometerCore
import CodometerL10n
@testable import CodometerUI
import Foundation
import Testing

/// What the expanded card says: its hero, its three tiles, its status pill, and which account it follows.
@Suite("Card content")
struct CardContentPlanTests {
    static let now = UIFixture.now
    static let english = Localizer.testEnglish
    static let russian = Localizer.testRussian

    // MARK: - Builders

    static func presentation(
        label: String = "Work",
        provider: ProviderKind = .claude,
        windows: [LimitWindow],
        limitReached: Bool = false,
        sessions: [AgentSession] = [],
        capturedAgo: TimeInterval = 60,
        plan: String? = "max_20x",
        l10n: Localizer = english
    ) throws -> AccountPresentation {
        let status = AccountStatus(
            profile: try UIFixture.profile(label, provider: provider),
            identity: AccountIdentity(email: "work@example.com", organization: nil, plan: plan),
            reading: try UIFixture.reading([try UIFixture.bucket("main", windows, limitReached: limitReached)], capturedAgo: capturedAgo),
            sessions: sessions
        )
        return AccountPresentation(status: status, appearance: AppearanceSettings(), now: now, l10n: l10n)
    }

    static func plan(
        _ presentation: AccountPresentation,
        thirdTile: CardThirdTile = .weeklyReset,
        serviceStatus: ServiceStatusBoard = .empty,
        ceremonies: CeremonyBoard = CeremonyBoard(),
        settings: AppSettings = .empty,
        l10n: Localizer = english
    ) -> CardContentPlan {
        CardContentPlan(
            presentation: presentation,
            settings: settings,
            thirdTile: thirdTile,
            serviceStatus: serviceStatus,
            ceremonies: ceremonies,
            now: now,
            l10n: l10n
        )
    }

    private static func tile(_ plan: CardContentPlan, _ kind: CardContentPlan.Tile.Kind) throws -> CardContentPlan.Tile {
        try #require(plan.tiles.first { $0.kind == kind })
    }

    // MARK: - Hero

    @Test("The hero is the window that limits the account, with the unit word spelled out")
    func heroIsTheBindingWindow() throws {
        let presentation = try Self.presentation(windows: [
            try UIFixture.window("session", .session, used: 42, duration: .fiveHours, resetsIn: 7_200),
            try UIFixture.window("week", .weekly(model: nil), used: 64, duration: .oneWeek, resetsIn: 4 * 86_400),
        ])
        let hero = try #require(Self.plan(presentation).hero)
        #expect(hero.figure == "64%")
        #expect(hero.unit == "used")
        #expect(hero.caption.contains("Weekly"))
        #expect(abs(hero.fraction - 0.64) < 0.001)
        #expect(hero.accessibilityText.contains("64% used"))
    }

    @Test("The hero carries the forecast when there is one to draw")
    func heroForecast() throws {
        // Half the week gone, 60 % used: the projection lands near 100 %.
        let presentation = try Self.presentation(windows: [
            try UIFixture.window("week", .weekly(model: nil), used: 60, duration: .oneWeek, resetsIn: 3.5 * 86_400),
        ])
        let hero = try #require(Self.plan(presentation).hero)
        let forecast = try #require(hero.forecastFraction)
        #expect(forecast > hero.fraction)
        #expect(hero.accessibilityText.contains("forecast"))
    }

    @Test("A plan chip is normalised, and a long or missing one is dropped")
    func planChip() {
        #expect(CardContentPlan.planChip("max_20x") == "MAX 20X")
        #expect(CardContentPlan.planChip("  pro ") == "PRO")
        #expect(CardContentPlan.planChip(nil) == nil)
        #expect(CardContentPlan.planChip("") == nil)
        #expect(CardContentPlan.planChip("an extremely long plan name") == nil)
    }

    // MARK: - Reset tile

    @Test("The reset tile counts down, or shows the clock when the user asked for it")
    func resetTileStyles() throws {
        let presentation = try Self.presentation(windows: [
            try UIFixture.window("week", .weekly(model: nil), used: 64, duration: .oneWeek, resetsIn: 5 * 86_400 + 16 * 3_600),
        ])
        var settings = AppSettings.empty
        let countdown = try Self.tile(Self.plan(presentation, settings: settings), .reset)
        #expect(countdown.value == "5d 16h")
        #expect(countdown.label == "until reset")
        settings.appearance.resetTextStyle = ResetTextStyle.clockTime
        let clock = try Self.tile(Self.plan(presentation, settings: settings), .reset)
        #expect(clock.value != countdown.value)
        #expect(countdown.accessibilityText.contains("5 days"))
    }

    @Test("Without a reset time the tile shows an em dash, not a number")
    func resetTileWithoutATime() throws {
        let presentation = try Self.presentation(windows: [
            try UIFixture.window("week", .weekly(model: nil), used: 64, duration: nil, resetsIn: nil),
        ])
        let tile = try Self.tile(Self.plan(presentation), .reset)
        #expect(tile.value == "—")
        #expect(tile.tone == .secondary)
    }

    @Test("A blocked account says when it is available again, in the exhausted band")
    func resetTileWhenBlocked() throws {
        let presentation = try Self.presentation(
            windows: [
                try UIFixture.window("session", .session, used: 18, duration: .fiveHours, resetsIn: 3_600),
                try UIFixture.window("week", .weekly(model: nil), used: 100, duration: .oneWeek, resetsIn: 30 * 3_600),
            ],
            limitReached: true
        )
        let tile = try Self.tile(Self.plan(presentation), .reset)
        #expect(tile.label == "back at")
        #expect(tile.tone == .band(.exhausted))
        #expect(tile.accessibilityText.contains("Available again"))
    }

    // MARK: - Pace tile

    @Test("Too little of the window gone reads “Too early”, quietly")
    func paceTooEarly() throws {
        let presentation = try Self.presentation(windows: [
            try UIFixture.window("week", .weekly(model: nil), used: 4, duration: .oneWeek, resetsIn: 6.5 * 86_400),
        ])
        let tile = try Self.tile(Self.plan(presentation), .pace)
        #expect(tile.value == "Too early")
        #expect(tile.tone == .secondary)
    }

    @Test("A projection inside the window reads “Runs out …” in a warning colour")
    func paceRunsOut() throws {
        let presentation = try Self.presentation(windows: [
            try UIFixture.window("session", .session, used: 90, duration: .fiveHours, resetsIn: 3_600),
        ])
        let tile = try Self.tile(Self.plan(presentation), .pace)
        #expect(tile.label == "runs out")
        #expect(tile.tone == .band(.critical))
        #expect(tile.accessibilityText.hasPrefix("Runs out"))
    }

    @Test("A projection on another day names the day, so the value reads under its label in both languages")
    func paceRunsOutOnAnotherDay() throws {
        // Two thirds of a week gone with nearly all of it spent: the projection lands days from now.
        for l10n in [Self.english, Self.russian] {
            let presentation = try Self.presentation(
                windows: [try UIFixture.window("week", .weekly(model: nil), used: 92, duration: .oneWeek, resetsIn: 2 * 86_400)],
                l10n: l10n
            )
            let tile = try Self.tile(Self.plan(presentation, l10n: l10n), .pace)
            #expect(tile.label == l10n.card.runsOut)
            // A weekday and a clock, never a countdown: "2 дн 3 ч закончится" is not a sentence.
            #expect(!tile.value.contains(l10n.format.durationCompact(2 * 86_400)))
            let binding = try #require(presentation.headline?.binding)
            let pace = try #require(UsagePace(window: binding, now: Self.now))
            let exhaustion = try #require(pace.projectedExhaustion)
            #expect(tile.value.hasPrefix(l10n.format.weekdayShort(exhaustion)), "\(l10n.language) “\(tile.value)”")
        }
    }

    @Test("Usage that will last reads “On track”")
    func paceOnTrack() throws {
        let presentation = try Self.presentation(windows: [
            try UIFixture.window("week", .weekly(model: nil), used: 20, duration: .oneWeek, resetsIn: 3 * 86_400),
        ])
        let tile = try Self.tile(Self.plan(presentation), .pace)
        #expect(tile.value == "On track")
        #expect(tile.tone == .success)
    }

    @Test("An exhausted window reads “Out”")
    func paceOut() throws {
        let presentation = try Self.presentation(
            windows: [try UIFixture.window("week", .weekly(model: nil), used: 100, duration: .oneWeek, resetsIn: 86_400)],
            limitReached: true
        )
        let tile = try Self.tile(Self.plan(presentation), .pace)
        #expect(tile.value == "Out")
        #expect(tile.tone == .band(.exhausted))
    }

    // MARK: - Third tile

    @Test("The weekly tile shows the all-models week, and falls back to the session window without one")
    func thirdTileWeekly() throws {
        let weekly = try Self.presentation(windows: [
            try UIFixture.window("session", .session, used: 38, duration: .fiveHours, resetsIn: 7_200),
            try UIFixture.window("week", .weekly(model: nil), used: 64, duration: .oneWeek, resetsIn: 3 * 86_400),
        ])
        let tile = try Self.tile(Self.plan(weekly, thirdTile: .weeklyReset), .third)
        #expect(tile.label == "weekly reset")
        // VoiceOver has to tell this tile from the reset tile, which speaks the same kind of phrase.
        let reset = try Self.tile(Self.plan(weekly, thirdTile: .weeklyReset), .reset)
        #expect(tile.accessibilityText.hasSuffix("weekly reset"))
        #expect(tile.accessibilityText != reset.accessibilityText)

        let noWeek = try Self.presentation(windows: [
            try UIFixture.window("session", .session, used: 38, duration: .fiveHours, resetsIn: 7_200),
        ])
        let fallback = try Self.tile(Self.plan(noWeek, thirdTile: .weeklyReset), .third)
        #expect(fallback.label == "session · 5h")
        #expect(fallback.value == "38%")
    }

    @Test("The agents tile counts working and waiting sessions, and says so when there are none")
    func thirdTileAgents() throws {
        let busy = try Self.presentation(
            windows: [try UIFixture.window("week", .weekly(model: nil), used: 40, duration: .oneWeek, resetsIn: 86_400)],
            sessions: [
                try UIFixture.session("a", .working),
                try UIFixture.session("b", .working),
                try UIFixture.session("c", .waiting),
            ]
        )
        let tile = try Self.tile(Self.plan(busy, thirdTile: .agents), .third)
        #expect(tile.value == "2 · 1")
        #expect(tile.label == "working · waiting")
        #expect(tile.tone == .attention)

        let quiet = try Self.presentation(
            windows: [try UIFixture.window("week", .weekly(model: nil), used: 40, duration: .oneWeek, resetsIn: 86_400)]
        )
        let empty = try Self.tile(Self.plan(quiet, thirdTile: .agents), .third)
        #expect(empty.value == "—")
        #expect(empty.label == "no agents")
    }

    // MARK: - Status pill

    @Test("Nothing is shown while everything is fine")
    func pillIsQuietWhenFine() throws {
        let presentation = try Self.presentation(windows: [
            try UIFixture.window("week", .weekly(model: nil), used: 20, duration: .oneWeek, resetsIn: 3 * 86_400),
        ])
        #expect(Self.plan(presentation).pill == nil)
    }

    @Test("Agents waiting beat every other reason, and the tooltip still lists them all")
    func pillPriority() throws {
        let presentation = try Self.presentation(
            windows: [try UIFixture.window("week", .weekly(model: nil), used: 100, duration: .oneWeek, resetsIn: 86_400)],
            limitReached: true,
            sessions: [try UIFixture.session("a", .waiting), try UIFixture.session("b", .waiting)],
            capturedAgo: 3_600
        )
        var board = ServiceStatusBoard.empty
        board.statuses[.claude] = ServiceStatus(provider: .claude, level: .partialOutage, affectedComponents: ["Claude Code"], checkedAt: Self.now)
        let pill = try #require(Self.plan(presentation, serviceStatus: board).pill)
        #expect(pill.kind == .waiting)
        #expect(pill.text == "2 waiting")
        #expect(pill.tone == .attention)
        #expect(pill.statusPageProvider == nil)
        #expect(pill.tooltip.contains("Partial outage"))
        #expect(pill.tooltip.contains("Limit reached"))
        #expect(pill.tooltip.contains("No fresh data since"))
    }

    @Test("Every reason keeps its place in the order")
    func pillOrder() throws {
        let base = try Self.presentation(windows: [
            try UIFixture.window("week", .weekly(model: nil), used: 20, duration: .oneWeek, resetsIn: 3 * 86_400),
        ])
        var outage = ServiceStatusBoard.empty
        outage.statuses[.claude] = ServiceStatus(provider: .claude, level: .majorOutage, affectedComponents: [], checkedAt: Self.now)
        let major = try #require(Self.plan(base, serviceStatus: outage).pill)
        #expect(major.kind == .majorOutage)
        #expect(major.statusPageProvider == .claude)

        let blocked = try Self.presentation(
            windows: [try UIFixture.window("week", .weekly(model: nil), used: 100, duration: .oneWeek, resetsIn: 86_400)],
            limitReached: true
        )
        var degraded = ServiceStatusBoard.empty
        degraded.statuses[.claude] = ServiceStatus(provider: .claude, level: .degraded, affectedComponents: [], checkedAt: Self.now)
        let limit = try #require(Self.plan(blocked, serviceStatus: degraded).pill)
        #expect(limit.kind == .limitReached)

        let stale = try Self.presentation(
            windows: [try UIFixture.window("week", .weekly(model: nil), used: 20, duration: .oneWeek, resetsIn: 3 * 86_400)],
            capturedAgo: 3_600
        )
        let staleOnly = try #require(Self.plan(stale).pill)
        #expect(staleOnly.kind == .stale)
        #expect(staleOnly.tooltip.contains("No fresh data since"))
    }

    @Test("A limit that just reset is celebrated for ten minutes")
    func pillJustReset() throws {
        let presentation = try Self.presentation(windows: [
            try UIFixture.window("week", .weekly(model: nil), used: 3, duration: .oneWeek, resetsIn: 6 * 86_400),
        ])
        var board = CeremonyBoard()
        let event = try WindowResetEvent(
            accountID: presentation.id,
            bucketID: "main",
            windowID: "week",
            previousUsed: try Percentage(validating: 91),
            newUsed: try Percentage(validating: 3),
            detectedAt: Self.now.addingTimeInterval(-90)
        )
        board.insert([event], previousFractions: [:], now: Self.now)
        let pill = try #require(Self.plan(presentation, ceremonies: board).pill)
        #expect(pill.kind == .justReset)
        #expect(pill.text == "Just reset")
    }

    @Test("Russian says the same things in Russian")
    func russianCopy() throws {
        let presentation = try Self.presentation(
            windows: [try UIFixture.window("week", .weekly(model: nil), used: 100, duration: .oneWeek, resetsIn: 30 * 3_600)],
            limitReached: true,
            l10n: Self.russian
        )
        let plan = Self.plan(presentation, l10n: Self.russian)
        let pill = try #require(plan.pill)
        #expect(pill.text == "Лимит исчерпан")
        let reset = try #require(plan.tiles.first { $0.kind == .reset })
        #expect(reset.label == "снова доступно")
        #expect(plan.hero?.unit == "использовано")
    }

    // MARK: - Footer

    @Test("The footer follows the e-mail setting and says when the data arrived")
    func footer() throws {
        let presentation = try Self.presentation(windows: [
            try UIFixture.window("week", .weekly(model: nil), used: 40, duration: .oneWeek, resetsIn: 86_400),
        ])
        let hidden = Self.plan(presentation)
        #expect(hidden.identity == "Work · Claude")
        #expect(hidden.updated.hasPrefix("updated"))

        var settings = AppSettings.empty
        settings.appearance.emailVisibility = EmailVisibility.masked
        let masked = AccountPresentation(status: presentation.status, appearance: settings.appearance, now: Self.now, l10n: Self.english)
        #expect(Self.plan(masked, settings: settings).identity.contains("•"))
    }

    // MARK: - Choosing an account

    private func accounts() throws -> [AccountPresentation] {
        [
            try Self.presentation(label: "Work", windows: [
                try UIFixture.window("week", .weekly(model: nil), used: 40, duration: .oneWeek, resetsIn: 3 * 86_400),
            ]),
            try Self.presentation(label: "Personal", windows: [
                try UIFixture.window("week", .weekly(model: nil), used: 55, duration: .oneWeek, resetsIn: 3 * 86_400),
            ]),
            try Self.presentation(label: "Side", provider: .codex, windows: [
                try UIFixture.window("week", .rolling, used: 12, duration: .oneWeek, resetsIn: 3 * 86_400),
            ]),
        ]
    }

    @Test("Auto-selection picks the account closest to its limit")
    func mostUrgentWins() throws {
        let list = try accounts()
        let selected = CardAccountSelector.select(
            presentations: list,
            current: nil,
            selection: .mostUrgent,
            pointerInside: false,
            manualSwitchAt: nil,
            now: Self.now
        )
        #expect(selected == list[1].id)
    }

    @Test("Waiting agents come before a higher percentage inside the same band")
    func waitingBeatsUsage() throws {
        let calm = try Self.presentation(label: "Calm", windows: [
            try UIFixture.window("week", .weekly(model: nil), used: 44, duration: .oneWeek, resetsIn: 3 * 86_400),
        ])
        let waiting = try Self.presentation(
            label: "Waiting",
            windows: [try UIFixture.window("week", .weekly(model: nil), used: 20, duration: .oneWeek, resetsIn: 3 * 86_400)],
            sessions: [try UIFixture.session("a", .waiting)]
        )
        #expect(CardAccountSelector.mostUrgent([calm, waiting])?.id == waiting.id)
    }

    @Test("Auto-selection never switches under the pointer or within a minute of a manual switch")
    func hysteresis() throws {
        let list = try accounts()
        let current = list[0].id
        #expect(CardAccountSelector.select(
            presentations: list,
            current: current,
            selection: .mostUrgent,
            pointerInside: true,
            manualSwitchAt: nil,
            now: Self.now
        ) == current)
        #expect(CardAccountSelector.select(
            presentations: list,
            current: current,
            selection: .mostUrgent,
            pointerInside: false,
            manualSwitchAt: Self.now.addingTimeInterval(-30),
            now: Self.now
        ) == current)
        // A minute later the hold is over and the most urgent account takes over.
        #expect(CardAccountSelector.select(
            presentations: list,
            current: current,
            selection: .mostUrgent,
            pointerInside: false,
            manualSwitchAt: Self.now.addingTimeInterval(-61),
            now: Self.now
        ) == list[1].id)
    }

    @Test("Inside one band a candidate has to lead by five points to take over")
    func switchMargin() throws {
        let shown = try Self.presentation(label: "Shown", windows: [
            try UIFixture.window("week", .weekly(model: nil), used: 40, duration: .oneWeek, resetsIn: 3 * 86_400),
        ])
        let nearly = try Self.presentation(label: "Nearly", windows: [
            try UIFixture.window("week", .weekly(model: nil), used: 43, duration: .oneWeek, resetsIn: 3 * 86_400),
        ])
        let clearly = try Self.presentation(label: "Clearly", windows: [
            try UIFixture.window("week", .weekly(model: nil), used: 46, duration: .oneWeek, resetsIn: 3 * 86_400),
        ])
        func select(_ candidates: [AccountPresentation]) -> AccountID? {
            CardAccountSelector.select(
                presentations: candidates,
                current: shown.id,
                selection: .mostUrgent,
                pointerInside: false,
                manualSwitchAt: nil,
                now: Self.now
            )
        }
        #expect(select([shown, nearly]) == shown.id)
        #expect(select([shown, clearly]) == clearly.id)
    }

    @Test("A fixed account is kept, and a fixed account that disappeared falls back to the most urgent one")
    func fixedSelection() throws {
        let list = try accounts()
        #expect(CardAccountSelector.select(
            presentations: list,
            current: nil,
            selection: .fixed(list[2].id),
            pointerInside: false,
            manualSwitchAt: nil,
            now: Self.now
        ) == list[2].id)
        let removed = Array(list.prefix(2))
        #expect(CardAccountSelector.select(
            presentations: removed,
            current: nil,
            selection: .fixed(list[2].id),
            pointerInside: false,
            manualSwitchAt: nil,
            now: Self.now
        ) == removed[1].id)
    }
}
