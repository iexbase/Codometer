import CodometerCore
import CodometerL10n
@testable import CodometerUI
import Foundation
import SwiftUI
import Testing

private let now = UIFixture.now

@Suite("Window presentations")
struct WindowPresentationTests {
    /// Claude's main bucket in the provider's order plus a second, Codex-style bucket.
    private func claudeStatus(appearance: AppearanceSettings = AppearanceSettings()) throws -> AccountPresentation {
        let main = try UIFixture.bucket("claude", [
            try UIFixture.window("week.fable", .weekly(model: "Fable"), used: 63, duration: .oneWeek, resetsIn: 3 * 86_400),
            try UIFixture.window("limit.extra", used: 12, duration: nil, resetsIn: nil, label: "Extra usage"),
            try UIFixture.window("session", .session, used: 7, resetsIn: 2.5 * 3_600),
            try UIFixture.window("week.sonnet", .weekly(model: "Sonnet only"), used: 70, duration: .oneWeek, resetsIn: 3 * 86_400),
            try UIFixture.window("week", .weekly(model: nil), used: 38, duration: .oneWeek, resetsIn: 3 * 86_400),
        ])
        let spark = try UIFixture.bucket("spark", title: "GPT-5.3-Codex-Spark", [
            try UIFixture.window("primary", used: 12),
            try UIFixture.window("secondary", used: 3, duration: .oneWeek, resetsIn: 5 * 86_400),
        ])
        let status = AccountStatus(profile: try UIFixture.profile("Claude"), reading: try UIFixture.reading([main, spark]))
        return AccountPresentation(status: status, appearance: appearance, now: now, l10n: .testRussian)
    }

    @Test("Every window of every bucket is listed in display order with provider-meaning titles")
    func ordering() throws {
        let presentation = try claudeStatus()
        #expect(presentation.windows.map(\.id) == [
            "claude/session", "claude/week", "claude/week.sonnet", "claude/week.fable", "claude/limit.extra",
            "spark/primary", "spark/secondary",
        ])
        #expect(presentation.windows.map(\.title) == [
            "Сессия · 5\u{00A0}ч", "Неделя · все модели", "Неделя · Sonnet", "Неделя · Fable", "Extra usage", "5\u{00A0}ч", "Неделя",
        ])
        #expect(presentation.windows.map(\.isMainBucket) == [true, true, true, true, true, false, false])
        #expect(presentation.mainWindows.count == 5)
        #expect(presentation.windows.last?.bucketTitle == "GPT-5.3-Codex-Spark")
        #expect(presentation.windows.first?.bucketTitle == nil)
    }

    @Test("Windows carry band, ring progress and pace")
    func windowDetails() throws {
        let presentation = try claudeStatus()
        let session = try #require(presentation.windows.first)
        #expect(session.band == .ample)
        #expect(session.progress.used == 0.07)
        #expect(session.progress.elapsed == 0.5)
        #expect(session.progress.tickCount == 5)
        #expect(session.pace != nil)
        let fable = try #require(presentation.windows.first { $0.window.id == "week.fable" })
        #expect(fable.band == .watch)
        #expect(fable.progress.tickCount == 7)
        #expect(presentation.worstBand == .watch)
        #expect(!presentation.isBlocked)
        #expect(presentation.blockingWindow == nil)

        let withoutPace = try claudeStatus(appearance: AppearanceSettings(showsPace: false))
        #expect(withoutPace.windows.allSatisfy { $0.pace == nil })
    }

    @Test("Blocked accounts name the window that resets last")
    func blocked() throws {
        let bucket = try UIFixture.bucket("claude", [
            try UIFixture.window("session", .session, used: 100, resetsIn: 3_600),
            try UIFixture.window("week", .weekly(model: nil), used: 100, duration: .oneWeek, resetsIn: 3 * 86_400),
            try UIFixture.window("week.fable", .weekly(model: "Fable"), used: 40, duration: .oneWeek, resetsIn: 3 * 86_400),
        ])
        let status = AccountStatus(profile: try UIFixture.profile("Claude"), reading: try UIFixture.reading([bucket]))
        let presentation = AccountPresentation(status: status, appearance: AppearanceSettings(), now: now, l10n: .testRussian)
        #expect(presentation.isBlocked)
        #expect(presentation.blockingWindow?.id == "week")
        #expect(presentation.worstBand == .exhausted)

        let limited = try UIFixture.bucket("codex", [try UIFixture.window("primary", used: 20)], limitReached: true)
        let limitedStatus = AccountStatus(profile: try UIFixture.profile("Codex", provider: .codex), reading: try UIFixture.reading([limited]))
        let limitedPresentation = AccountPresentation(status: limitedStatus, appearance: AppearanceSettings(), now: now, l10n: .testRussian)
        #expect(limitedPresentation.isBlocked)
        #expect(limitedPresentation.blockingWindow == nil)
        #expect(limitedPresentation.worstBand == .exhausted)
    }

    @Test("Without a reading there are no windows and no band")
    func noReading() throws {
        let presentation = AccountPresentation(
            status: AccountStatus(profile: try UIFixture.profile("Claude")),
            appearance: AppearanceSettings(),
            now: now,
            l10n: .testRussian
        )
        #expect(presentation.windows.isEmpty)
        #expect(presentation.worstBand == nil)
        #expect(!presentation.isBlocked)
    }

    @Test("Identity respects e-mail visibility, groups resolve from settings, waiting sessions come longest first")
    func identityGroupAndWaiting() throws {
        let work = try UIFixture.group("Работа")
        let profile = try UIFixture.profile("Claude", group: work)
        let identity = AccountIdentity(email: "example@test.com", organization: "example@test.com's Organization", plan: "Max")
        let status = AccountStatus(
            profile: profile,
            identity: identity,
            sessions: [
                try UIFixture.session("recent", .waiting, since: 30),
                try UIFixture.session("busy", .working, since: 600),
                try UIFixture.session("old", .waiting, since: 900),
            ]
        )
        var settings = try AppSettings(accounts: [profile], groups: [work])

        let byDefault = AccountPresentation(status: status, settings: settings, now: now, l10n: .testRussian)
        #expect(byDefault.displayEmail == nil)
        #expect(byDefault.displayOrganization == nil)

        settings.appearance.emailVisibility = .visible
        let visible = AccountPresentation(status: status, settings: settings, now: now, l10n: .testRussian)
        #expect(visible.displayEmail == "example@test.com")
        #expect(visible.displayOrganization == "example@test.com's Organization")
        #expect(visible.group == work)
        #expect(visible.waitingSessions.map(\.id) == ["old", "recent"])

        settings.appearance.emailVisibility = .masked
        let masked = AccountPresentation(status: status, settings: settings, now: now, l10n: .testRussian)
        #expect(masked.displayEmail == "e••••e@test.com")
        #expect(masked.displayOrganization == "e••••e@test.com's Organization")

        settings.appearance.emailVisibility = .hidden
        let hidden = AccountPresentation(status: status, settings: settings, now: now, l10n: .testRussian)
        #expect(hidden.displayEmail == nil)
        #expect(hidden.displayOrganization == nil)

        let ungrouped = AccountPresentation(status: status, appearance: settings.appearance, now: now, l10n: .testRussian)
        #expect(ungrouped.group == nil)
    }
}

@Suite("Release 2 text formatting")
struct UsageFormatReleaseTwoTests {
    @Test("Window titles follow the provider's meaning")
    func windowTitles() throws {
        #expect(UsageFormat.windowTitle(try UIFixture.window("session", .session, used: 1, duration: nil), l10n: .testRussian) == "Сессия · 5\u{00A0}ч")
        #expect(UsageFormat.windowTitle(try UIFixture.window("week", .weekly(model: nil), used: 1, duration: .oneWeek), l10n: .testRussian) == "Неделя · все модели")
        #expect(UsageFormat.windowTitle(try UIFixture.window("week.sonnet", .weekly(model: "Sonnet only"), used: 1), l10n: .testRussian) == "Неделя · Sonnet")
        #expect(UsageFormat.windowTitle(try UIFixture.window("week.fable", .weekly(model: "Fable"), used: 1), l10n: .testRussian) == "Неделя · Fable")
        #expect(UsageFormat.windowTitle(try UIFixture.window("limit.x", used: 1, duration: nil, label: "Daily Opus"), l10n: .testRussian) == "Daily Opus")
        #expect(UsageFormat.windowTitle(try UIFixture.window("primary", used: 1, duration: nil), l10n: .testRussian) == "Основной лимит")
        #expect(UsageFormat.windowTitle(try UIFixture.window("secondary", used: 1, duration: .oneDay), l10n: .testRussian) == "Сутки")
        #expect(UsageFormat.modelName("only") == "only")
    }

    private static let countdownCases: [(TimeInterval, String)] = [
        (-5, "0м"),
        (0, "0м"),
        (.nan, "0м"),
        (30, "1м"),
        (47 * 60, "47м"),
        (59 * 60 + 1, "1:00"),
        (2 * 3_600 + 13 * 60 + 30, "2:14"),
        (9 * 3_600 + 5 * 60, "9:05"),
        (86_399, "1д"),
        (2.4 * 86_400, "2д"),
        (3 * 86_400, "3д"),
    ]

    @Test("Rail countdowns stay within five characters", arguments: countdownCases)
    func railCountdown(seconds: TimeInterval, expected: String) {
        let text = UsageFormat.railCountdown(seconds, l10n: .testRussian)
        #expect(text == expected)
        #expect(text.count <= UsageFormat.railCountdownTemplate.count)
    }

    @Test("Turn timing reads like a sentence")
    func turn() throws {
        #expect(UsageFormat.turn(try UIFixture.turn(duration: 252, firstToken: 2.8), l10n: .testRussian) == "ход 4\u{00A0}мин 12\u{00A0}с · первый токен 2,8\u{00A0}с")
        #expect(UsageFormat.turn(try UIFixture.turn(duration: 38, aborted: true), l10n: .testRussian) == "ход 38\u{00A0}с · прерван")
        #expect(UsageFormat.turn(try UIFixture.turn(duration: 3_900), l10n: .testRussian) == "ход 1\u{00A0}ч 5\u{00A0}мин")
        #expect(UsageFormat.turn(try UIFixture.turn(duration: 120, firstToken: 12.4), l10n: .testRussian) == "ход 2\u{00A0}мин · первый токен 12\u{00A0}с")
        #expect(UsageFormat.turn(try UIFixture.turn(duration: 0.3, firstToken: 0.01), l10n: .testRussian) == "ход 1\u{00A0}с · первый токен <0,1\u{00A0}с")
    }

    @Test("Session health is hedged and silent while normal")
    func health() throws {
        #expect(UsageFormat.health(.normal, now: now, l10n: .testRussian) == nil)
        #expect(UsageFormat.health(.quiet(since: now.addingTimeInterval(-480)), now: now, l10n: .testRussian) == "нет активности 8\u{00A0}мин")
        #expect(UsageFormat.health(.longTurn, now: now, l10n: .testRussian) == "необычно долгий ход")
        #expect(UsageFormat.health(.waitingLong, now: now, l10n: .testRussian) == "ждёт больше 10\u{00A0}мин")
        #expect(UsageFormat.health(of: try UIFixture.session("s", .waiting, since: 720), now: now, l10n: .testRussian) == "ждёт 12\u{00A0}мин")
        #expect(UsageFormat.health(of: try UIFixture.session("s", .working, since: 60), now: now, l10n: .testRussian) == nil)
    }

    @Test("E-mail visibility: shown, masked or hidden")
    func email() {
        #expect(UsageFormat.email("example@test.com", visibility: .visible) == "example@test.com")
        #expect(UsageFormat.email("example@test.com", visibility: .masked) == "e••••e@test.com")
        #expect(UsageFormat.email("example@test.com", visibility: .hidden) == nil)
        #expect(UsageFormat.email(nil as String?, visibility: .visible) == nil)
        #expect(UsageFormat.email(nil as AccountIdentity?, visibility: .masked) == nil)
        let team = AccountIdentity(email: nil, organization: "Acme Inc", plan: nil)
        #expect(UsageFormat.organization(team, visibility: .hidden) == "Acme Inc")
    }

    @Test("Refresh and attribution texts")
    func refreshAndPoints() {
        #expect(UsageFormat.nextRefresh(now.addingTimeInterval(180), now: now, l10n: .testRussian) == "обновление через 3\u{00A0}мин")
        #expect(UsageFormat.nextRefresh(now.addingTimeInterval(-1), now: now, l10n: .testRussian) == "скоро обновление")
        #expect(UsageFormat.attributionPoints(3.24, l10n: .testRussian) == "≈3,2\u{00A0}%")
        #expect(UsageFormat.attributionPoints(0.05, l10n: .testRussian) == "≈0,1\u{00A0}%")
        #expect(UsageFormat.attributionPoints(0.01, l10n: .testRussian) == "<0,1\u{00A0}%")
        #expect(UsageFormat.attributionPoints(0, l10n: .testRussian) == "0\u{00A0}%")
        #expect(UsageFormat.attributionPoints(9.96, l10n: .testRussian) == "≈10\u{00A0}%")
        #expect(UsageFormat.attributionPoints(12.4, l10n: .testRussian) == "≈12\u{00A0}%")
    }

    @Test("Analytics ranges end now")
    func ranges() {
        #expect(AnalyticsRange.allCases.map { $0.title(l10n: .testRussian) } == ["5\u{00A0}ч", "24\u{00A0}ч", "7\u{00A0}дн"])
        let week = AnalyticsRange.week.interval(endingAt: now)
        #expect(week.end == now)
        #expect(week.duration == 7 * 86_400)
        #expect(AnalyticsRange.fiveHours.interval(endingAt: now).start == now.addingTimeInterval(-5 * 3_600))
    }
}

@Suite("Design tokens")
struct DesignTokenTests {
    private static let textCases: [(CGFloat, CGFloat, CGFloat)] = [
        (10.5, 0.85, 11),
        (10.5, 1, 11),
        (10.5, 1.5, 15.75),
        (9.5, 0.75, 10.5),
        (12, 0.75, 11.4),
        (16, 0.85, 15.2),
        (34, 1, 34),
    ]

    @Test("Text sizes scale with floors", arguments: textCases)
    func textSizes(size: CGFloat, scale: CGFloat, expected: CGFloat) {
        #expect(abs(IslandMetrics.textSize(size, scale: scale) - expected) < 0.001)
        #expect(IslandMetrics(scale: scale).textSize(size) >= IslandMetrics.minimumTextSize)
    }

    @Test("Island margins scale")
    func margins() {
        let metrics = IslandMetrics(scale: 1.5)
        #expect(metrics.windowMargin == 30)
        #expect(metrics.orbitMargin == 6)
    }

    @Test("Glass tint and rim appear only when something needs attention")
    func urgencyColours() {
        #expect(Theme.glassTint(for: nil) == nil)
        #expect(Theme.glassTint(for: .ample) == nil)
        #expect(Theme.glassTint(for: .critical) != nil)
        #expect(Theme.rim(for: nil, waiting: false) == nil)
        #expect(Theme.rim(for: .ample, waiting: false) == nil)
        #expect(Theme.rim(for: .watch, waiting: false) != nil)
        #expect(Theme.rim(for: nil, waiting: true) != nil)
        #expect(Theme.bandText(for: .ample) != Theme.bandText(for: .exhausted))
    }
}

@MainActor
@Suite("Tracker store")
struct TrackerStoreTests {
    private struct Accounts {
        let work: AccountGroup
        let personal: AccountGroup
        let settings: AppSettings
        let state: TrackerState
    }

    /// Work (critical usage), personal (watch, one waiting session), ungrouped without data, and a disabled work
    /// account that waits.
    private func accounts() throws -> Accounts {
        let work = try UIFixture.group("Работа")
        let personal = try UIFixture.group("Личное")
        let office = try UIFixture.profile("Office", group: work)
        let home = try UIFixture.profile("Home", provider: .codex, group: personal)
        let spare = try UIFixture.profile("Spare")
        let old = try UIFixture.profile("Old", isEnabled: false, group: work)
        let settings = try AppSettings(accounts: [office, home, spare, old], groups: [work, personal])
        let state = TrackerState(accounts: [
            AccountStatus(
                profile: office,
                reading: try UIFixture.reading([try UIFixture.bucket("claude", [
                    try UIFixture.window("session", .session, used: 90),
                ])])
            ),
            AccountStatus(
                profile: home,
                reading: try UIFixture.reading([try UIFixture.bucket("codex", [try UIFixture.window("primary", used: 60)])]),
                sessions: [try UIFixture.session("home-1", .waiting)]
            ),
            AccountStatus(profile: spare),
            AccountStatus(profile: old, sessions: [try UIFixture.session("old-1", .waiting, since: 3_600)]),
        ])
        return Accounts(work: work, personal: personal, settings: settings, state: state)
    }

    @Test("The rail shows enabled accounts of the filtered group")
    func visiblePresentations() throws {
        let fixture = try accounts()
        let store = TrackerStore(state: fixture.state, settings: fixture.settings, now: now, actions: UIFixture.actions())
        #expect(store.presentations.map(\.status.profile.label.value) == ["Office", "Home", "Spare"])
        #expect(store.visiblePresentations.map(\.status.profile.label.value) == ["Office", "Home", "Spare"])
        #expect(store.visiblePresentations.first?.group == fixture.work)

        store.updateSettings { (settings: inout AppSettings) throws(ValidationError) in
            settings.appearance.railGroupFilter = fixture.work.id
        }
        #expect(store.visiblePresentations.map(\.status.profile.label.value) == ["Office"])
        #expect(store.presentations.count == 3)
    }

    @Test("Urgency is the worst band of visible accounts")
    func urgency() throws {
        let fixture = try accounts()
        let store = TrackerStore(state: fixture.state, settings: fixture.settings, now: now, actions: UIFixture.actions())
        #expect(store.urgency == .critical)
        store.updateSettings { (settings: inout AppSettings) throws(ValidationError) in
            settings.appearance.railGroupFilter = fixture.personal.id
        }
        #expect(store.urgency == .watch)

        let quiet = TrackerStore(state: .empty, settings: fixture.settings, now: now, actions: UIFixture.actions())
        #expect(quiet.urgency == nil)
    }

    @Test("Waiting sessions of enabled accounts form the attention queue, whatever the filter")
    func attention() throws {
        let fixture = try accounts()
        let store = TrackerStore(state: fixture.state, settings: fixture.settings, now: now, actions: UIFixture.actions())
        #expect(store.hasWaiting)
        #expect(store.attentionQueue.map(\.session.id) == ["home-1"])
        store.updateSettings { (settings: inout AppSettings) throws(ValidationError) in
            settings.appearance.railGroupFilter = fixture.work.id
        }
        #expect(store.attentionQueue.count == 1)

        let idle = TrackerStore(
            state: TrackerState(accounts: [fixture.state.accounts[0]]),
            settings: fixture.settings,
            now: now,
            actions: UIFixture.actions()
        )
        #expect(!idle.hasWaiting)
        #expect(idle.attentionQueue.isEmpty)
    }

    @Test("A changed reading invalidates the account's analytics")
    func receiveInvalidates() async throws {
        let fixture = try accounts()
        let loads = LoadCounter()
        let actions = UIFixture.actions(loadWindowHistory: { account, bucket, window, _ in
            loads.count += 1
            return HistorySeries(accountID: account, bucketID: bucket, windowID: window, points: [], resets: [])
        })
        let store = TrackerStore(state: fixture.state, settings: fixture.settings, now: now, actions: actions)
        let office = fixture.state.accounts[0]
        store.analytics.requestSeries(account: office.id, bucket: "claude", window: "session", since: now)
        await store.analytics.settle()
        #expect(loads.count == 1)
        #expect(store.analytics.series(account: office.id, bucket: "claude", window: "session") != nil)

        // Unchanged: a repeated request does nothing.
        store.analytics.requestSeries(account: office.id, bucket: "claude", window: "session", since: now)
        #expect(!store.analytics.isBusy(series: office.id, bucket: "claude", window: "session"))

        var changed = fixture.state
        changed.accounts[0].reading = try UIFixture.reading(
            [try UIFixture.bucket("claude", [try UIFixture.window("session", .session, used: 91)])],
            capturedAgo: 0
        )
        store.receive(changed)
        store.analytics.requestSeries(account: office.id, bucket: "claude", window: "session", since: now)
        // Throttled: scheduled for later rather than loaded again right away.
        #expect(store.analytics.isBusy(series: office.id, bucket: "claude", window: "session"))
        #expect(loads.count == 1)
    }
}
