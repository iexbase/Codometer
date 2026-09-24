import CodometerCore
import CodometerL10n
@testable import CodometerUI
import Foundation
import Testing

/// English output of the shared formatting (Group A), next to the Russian expectations in `PresentationTests`.
@Suite("Text formatting in English")
struct UsageFormatEnglishTests {
    private let en = Localizer.testEnglish
    private let now = UIFixture.now

    @Test("Window titles, percentages and rail countdowns")
    func titles() throws {
        #expect(UsageFormat.windowTitle(try UIFixture.window("session", .session, used: 1, duration: nil), l10n: en) == "Session · 5h")
        #expect(UsageFormat.windowTitle(try UIFixture.window("week", .weekly(model: nil), used: 1, duration: .oneWeek), l10n: en) == "Weekly · All models")
        #expect(UsageFormat.windowTitle(try UIFixture.window("week.sonnet", .weekly(model: "Sonnet only"), used: 1), l10n: en) == "Weekly · Sonnet")
        #expect(UsageFormat.windowTitle(try UIFixture.window("primary", used: 1, duration: nil), l10n: en) == "Main limit")
        #expect(UsageFormat.windowTitle(try UIFixture.window("secondary", used: 1, duration: .oneDay), l10n: en) == "Daily")
        #expect(UsageFormat.percent(try Percentage(validating: 57.5), l10n: en) == "58%")
        #expect(UsageFormat.usedAndLeft(try Percentage(validating: 64), l10n: en) == "64% used · 36% left")
        #expect(UsageFormat.railCountdown(47 * 60, l10n: en) == "47m")
        #expect(UsageFormat.railCountdown(3 * 86_400, l10n: en) == "3d")
        #expect(AnalyticsRange.allCases.map { $0.title(l10n: en) } == ["5h", "24h", "7d"])
    }

    @Test("Resets and pace")
    func resetsAndPace() throws {
        let window = try UIFixture.window("session", .session, used: 40, resetsIn: 2 * 3_600 + 14 * 60)
        #expect(UsageFormat.resetText(for: window, now: now, style: .countdown, l10n: en) == "Resets in 2h 14m")
        #expect(UsageFormat.resetText(for: window, now: now.addingTimeInterval(3 * 3_600), style: .countdown, l10n: en) == "Resetting…")
        let clock = try #require(UsageFormat.resetText(for: window, now: now, style: .clockTime, l10n: en))
        #expect(clock.hasPrefix("Resets "))
        let ahead = try #require(UsagePace(window: try UIFixture.window("s", .session, used: 90, resetsIn: 4 * 3_600), now: now))
        #expect(UsageFormat.pace(ahead, now: now, l10n: en).text.hasPrefix("At this pace, runs out "))
        #expect(UsageFormat.pace(ahead, now: now, l10n: en).isWarning)
    }

    @Test("Sessions: status, turns and health")
    func sessions() throws {
        #expect(UsageFormat.activity(.working, detail: nil, l10n: en) == "Working")
        #expect(UsageFormat.activity(.idle, detail: nil, l10n: en) == "Ready")
        #expect(UsageFormat.activity(.waiting, detail: "permission prompt", l10n: en) == "Needs approval")
        #expect(UsageFormat.activity(.waiting, detail: "input needed", l10n: en) == "Needs input")
        #expect(UsageFormat.activity(.waiting, detail: nil, l10n: en) == "Waiting for you")
        let prompt = try AgentSession(
            id: "p", title: "p", projectPath: nil, activity: .waiting, detail: "permission prompt",
            activitySince: now.addingTimeInterval(-600), processID: nil
        )
        #expect(UsageFormat.activity(of: prompt, provider: .codex, now: now, l10n: en) == "Needs approval or running a command")
        #expect(UsageFormat.turn(try UIFixture.turn(duration: 252, firstToken: 2.8), l10n: en) == "4m 12s turn · first token in 2.8s")
        #expect(UsageFormat.turn(try UIFixture.turn(duration: 38, aborted: true), l10n: en) == "38s turn · interrupted")
        #expect(UsageFormat.health(.quiet(since: now.addingTimeInterval(-480)), now: now, l10n: en) == "No activity for 8 min")
        #expect(UsageFormat.health(.longTurn, now: now, l10n: en) == "Unusually long turn")
        #expect(UsageFormat.health(.waitingLong, now: now, l10n: en) == "Waiting over 10 min")
        #expect(UsageFormat.health(of: try UIFixture.session("s", .waiting, since: 720), now: now, l10n: en) == "Waiting 12 min")
    }

    @Test("Session labels, refresh, attribution and issues")
    func labelsAndIssues() {
        let unnamed = SessionLabelParts(folder: nil, idSuffix: "3f9a1c")
        let named = SessionLabelParts(folder: "Codometer", idSuffix: "3f9a1c")
        #expect(UsageFormat.sessionLabel(unnamed, l10n: en) == "Session 3f9a1c")
        #expect(UsageFormat.sessionLabel(unnamed, l10n: .testRussian) == "сессия 3f9a1c")
        #expect(UsageFormat.sessionLabel(named, l10n: en) == "Codometer · 3f9a1c")
        #expect(UsageFormat.sessionLabel(named, includesID: false, l10n: en) == "Codometer")
        #expect(UsageFormat.nextRefresh(now.addingTimeInterval(180), now: now, l10n: en) == "Next refresh in 3 min")
        #expect(UsageFormat.nextRefresh(now.addingTimeInterval(-1), now: now, l10n: en) == "Refreshing soon")
        #expect(UsageFormat.age(since: now.addingTimeInterval(-120), now: now, l10n: en) == "2 min ago")
        #expect(UsageFormat.age(since: now, now: now, l10n: en) == "just now")
        #expect(UsageFormat.attributionPoints(3.24, l10n: en) == "≈3.2%")
        let offline = TrackerIssue(kind: .offline, detail: "x", occurredAt: now)
        #expect(UsageFormat.issue(offline, provider: .claude, l10n: en) == "No internet connection")
        let signedOut = TrackerIssue(kind: .signedOut, detail: "x", occurredAt: now)
        #expect(UsageFormat.issue(signedOut, provider: .codex, l10n: en) == "You’re not signed in to Codex in this profile")
        #expect(AttributionRows.title(of: .other, l10n: en) == "Other")
        #expect(AttributionRows.title(of: .noProject, l10n: en) == "No project")
        #expect(AttributionRows.title(of: .session(unnamed), l10n: en) == "Session 3f9a1c")
        #expect(AttributionRows.title(of: .project("api"), l10n: en) == "api")
    }

    @Test("Lane titles name sessions without a project in the interface language")
    func laneTitles() {
        let lanes: [(sessionID: String, project: String?)] = [
            ("aaaaaa-111111", "/Users/me/app"), ("bbbbbb-222222", "/Users/me/app"), ("cccccc-333333", nil), ("dddddd-444444", "/Users/me/web"),
        ]
        #expect(TimelineLayout.laneTitles(lanes, l10n: en) == ["app · 111111", "app · 222222", "Session 333333", "web"])
        #expect(TimelineLayout.laneTitles(lanes, l10n: .testRussian) == ["app · 111111", "app · 222222", "сессия 333333", "web"])
    }
}
