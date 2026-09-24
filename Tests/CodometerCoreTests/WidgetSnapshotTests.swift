import CodometerCore
import CodometerL10n
@testable import CodometerWidgetsUI
import AppKit
import Foundation
import SwiftUI
import Testing
import WidgetKit

// MARK: - Fixtures

private enum WidgetFixture {
    static let now = Fixture.now

    static func settings(
        _ accounts: [AccountProfile],
        groups: [AccountGroup] = [],
        email: EmailVisibility = .visible,
        filter: AccountGroupID? = nil,
        exports: Bool = true,
        showsForecast: Bool = true
    ) throws -> AppSettings {
        var appearance = AppearanceSettings(emailVisibility: email)
        appearance.railGroupFilter = filter
        appearance.showsForecast = showsForecast
        return try AppSettings(
            accounts: accounts,
            groups: groups,
            appearance: appearance,
            general: GeneralSettings(exportsWidgetData: exports)
        )
    }

    static func item(_ window: LimitWindow, bucket: String = "main", main: Bool = true) throws -> WidgetWindow {
        try WidgetWindow(bucketID: bucket, isMainBucket: main, window: window, language: .ru)
    }

    static func account(
        _ label: String = "Claude",
        provider: ProviderKind = .claude,
        windows: [LimitWindow],
        capturedAt: Date = now,
        isStale: Bool = false,
        isLimitReached: Bool = false,
        waiting: Int = 0,
        working: Int = 0
    ) throws -> WidgetAccount {
        try WidgetAccount(
            id: AccountID(),
            label: label,
            provider: provider,
            windows: try windows.map { try item($0) },
            capturedAt: capturedAt,
            isStale: isStale,
            isLimitReached: isLimitReached,
            waitingCount: waiting,
            workingCount: working
        )
    }

    static func snapshot(
        _ accounts: [WidgetAccount],
        attention: Int? = nil,
        at date: Date = now,
        language: Language = .ru,
        showsForecast: Bool = true,
        layout: WidgetLayout = .rings
    ) -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: date,
            accounts: accounts,
            bands: .standard,
            attentionCount: attention ?? accounts.reduce(0) { $0 + $1.waitingCount },
            workingCount: accounts.reduce(0) { $0 + $1.workingCount },
            language: language,
            showsForecast: showsForecast,
            layout: layout
        )
    }

    /// The same content with the strip layout chosen.
    static func strip(_ snapshot: WidgetSnapshot) -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: snapshot.generatedAt,
            accounts: snapshot.accounts,
            bands: snapshot.bands,
            attentionCount: snapshot.attentionCount,
            workingCount: snapshot.workingCount,
            language: snapshot.language,
            showsForecast: snapshot.showsForecast,
            layout: .strip
        )
    }

    static func session(_ activity: AgentActivity, id: String) throws -> AgentSession {
        try Fixture.session(activity, id: id)
    }
}

// MARK: - Titles

@Suite("Widget texts")
struct WidgetTextTests {
    @Test("Window titles follow the provider's meaning like the island's")
    func titles() throws {
        #expect(WidgetText.windowTitle(try Fixture.window("session", .session, used: 10), l10n: .testRussian) == "Сессия · 5\u{00A0}ч")
        #expect(WidgetText.windowTitle(try Fixture.window("week", .weekly(model: nil), used: 10, minutes: 10_080), l10n: .testRussian) == "Неделя · все модели")
        #expect(WidgetText.windowTitle(try Fixture.window("week.fable", .weekly(model: "Fable"), used: 10, minutes: 10_080), l10n: .testRussian) == "Неделя · Fable")
        #expect(WidgetText.windowTitle(try Fixture.window("week.sonnet", .weekly(model: "Sonnet only"), used: 10), l10n: .testRussian) == "Неделя · Sonnet")
        #expect(WidgetText.windowTitle(try Fixture.window("limit.x", .rolling, used: 10, label: "Current month (Opus)"), l10n: .testRussian) == "Current month (Opus)")
        #expect(WidgetText.windowTitle(try Fixture.window("primary", used: 10, minutes: 300), l10n: .testRussian) == "5\u{00A0}ч")
        #expect(WidgetText.windowTitle(try Fixture.window("secondary", used: 10, minutes: 10_080), l10n: .testRussian) == "Неделя")
        #expect(WidgetText.windowTitle(try Fixture.window("secondary", used: 10, minutes: 90), l10n: .testRussian) == "1\u{00A0}ч 30\u{00A0}мин")
        #expect(WidgetText.windowTitle(try Fixture.window("primary", used: 10, minutes: nil), l10n: .testRussian) == "Основной лимит")
        #expect(WidgetText.windowTitle(try Fixture.window("other", used: 10, minutes: nil), l10n: .testRussian) == "Доп. лимит")
    }

    @Test("Percent, e-mail and notice texts")
    func texts() throws {
        #expect(WidgetText.percent(try Percentage(validating: 62.6)) == "63%")
        #expect(WidgetText.percentNumber(try Percentage(validating: 0.3)) == "<1")
        #expect(WidgetText.percentNumber(.zero) == "0")
        #expect(WidgetText.email("example@test.com", visibility: .visible) == "example@test.com")
        #expect(WidgetText.email("example@test.com", visibility: .masked) == "e••••e@test.com")
        #expect(WidgetText.email("example@test.com", visibility: .hidden) == nil)
        #expect(WidgetText.email("", visibility: .visible) == nil)
        #expect(WidgetText.notice(for: .signedOut, l10n: .testRussian) == "вы не вошли")
    }

    @Test("English titles, notices and ring captions")
    func english() throws {
        #expect(WidgetText.windowTitle(try Fixture.window("session", .session, used: 10), l10n: .testEnglish) == "Session · 5h")
        #expect(WidgetText.windowTitle(try Fixture.window("week", .weekly(model: nil), used: 10, minutes: 10_080), l10n: .testEnglish) == "Weekly · All models")
        #expect(WidgetText.windowTitle(try Fixture.window("week.sonnet", .weekly(model: "Sonnet only"), used: 10), l10n: .testEnglish) == "Weekly · Sonnet")
        #expect(WidgetText.windowTitle(try Fixture.window("secondary", used: 10, minutes: 1_440), l10n: .testEnglish) == "Daily")
        #expect(WidgetText.windowTitle(try Fixture.window("secondary", used: 10, minutes: 90), l10n: .testEnglish) == "1h 30m")
        #expect(WidgetText.windowTitle(try Fixture.window("primary", used: 10, minutes: nil), l10n: .testEnglish) == "Main limit")
        #expect(WidgetText.windowTitle(try Fixture.window("other", used: 10, minutes: nil), l10n: .testEnglish) == "Extra limit")
        #expect(WidgetText.notice(for: .signedOut, l10n: .testEnglish) == "Not signed in")
        #expect(WidgetText.notice(for: .offline, l10n: .testEnglish) == "Offline")
        #expect(WidgetText.shortDuration(try Fixture.window("w", .weekly(model: nil), used: 1, minutes: 10_080), l10n: .testEnglish) == "wk")
        #expect(WidgetText.shortDuration(try Fixture.window("h", used: 1, minutes: 90), l10n: .testEnglish) == "2h")
    }

    @Test("Short window lengths for the caption inside a small ring")
    func shortDurations() throws {
        #expect(WidgetText.shortDuration(try Fixture.window("s", .session, used: 1, minutes: 300), l10n: .testRussian) == "5\u{00A0}ч")
        #expect(WidgetText.shortDuration(try Fixture.window("w", .weekly(model: nil), used: 1, minutes: 10_080), l10n: .testRussian) == "нед")
        #expect(WidgetText.shortDuration(try Fixture.window("d", used: 1, minutes: 1_440), l10n: .testRussian) == "сут")
        #expect(WidgetText.shortDuration(try Fixture.window("m", used: 1, minutes: 43_200), l10n: .testRussian) == "мес")
        #expect(WidgetText.shortDuration(try Fixture.window("q", used: 1, minutes: 45), l10n: .testRussian) == "45\u{00A0}мин")
        #expect(WidgetText.shortDuration(try Fixture.window("h", used: 1, minutes: 90), l10n: .testRussian) == "2\u{00A0}ч")
        #expect(WidgetText.shortDuration(try Fixture.window("t", used: 1, minutes: 4_320), l10n: .testRussian) == "3\u{00A0}дн")
        #expect(WidgetText.shortDuration(try Fixture.window("n", used: 1, minutes: nil), l10n: .testRussian) == nil)
    }

    @Test("Inside a provider's widget labels drop the provider's name")
    func labelsWithinProvider() {
        #expect(WidgetText.labelWithinProvider("Codex · Работа", provider: .codex) == "Работа")
        #expect(WidgetText.labelWithinProvider("codex - личное", provider: .codex) == "личное")
        #expect(WidgetText.labelWithinProvider("Claude: Team", provider: .claude) == "Team")
        #expect(WidgetText.labelWithinProvider("Claude Max", provider: .claude) == "Max")
        #expect(WidgetText.labelWithinProvider("Claude", provider: .claude) == "Claude")
        #expect(WidgetText.labelWithinProvider("Claude · ", provider: .claude) == "Claude · ")
        #expect(WidgetText.labelWithinProvider("Claudette", provider: .claude) == "Claudette")
        #expect(WidgetText.labelWithinProvider("Работа", provider: .codex) == "Работа")
        #expect(WidgetText.labelWithinProvider("Codex · Работа", provider: .claude) == "Codex · Работа")
    }

    @Test("Other buckets are named compactly next to the window title")
    func bucketTitles() throws {
        #expect(WidgetText.shortBucketTitle("GPT-5.3-Codex-Spark") == "Spark")
        #expect(WidgetText.shortBucketTitle("gpt-5") == "gpt-5")
        #expect(WidgetText.shortBucketTitle("Opus") == "Opus")
        #expect(WidgetText.shortBucketTitle("model-x") == "model-x")
        let window = try Fixture.window("primary", used: 10, minutes: 300)
        #expect(try WidgetWindow(bucketID: "spark", bucketTitle: "GPT-5.3-Codex-Spark", isMainBucket: false, window: window, language: .ru).displayTitle == "Spark · 5\u{00A0}ч")
        #expect(try WidgetWindow(bucketID: "spark", isMainBucket: false, window: window, language: .ru).displayTitle == "5\u{00A0}ч")
        #expect(try WidgetWindow(bucketID: "codex", bucketTitle: "Codex", isMainBucket: true, window: window, language: .ru).displayTitle == "5\u{00A0}ч")
    }
}

// MARK: - Builder

@Suite("Widget snapshot builder")
struct WidgetSnapshotBuilderTests {
    @Test("Enabled accounts in settings order, whatever group the island is filtered to")
    func enabledAccounts() throws {
        let work = try Fixture.group("Работа")
        let first = try Fixture.profile(.claude, path: "/tmp/.claude", label: "Claude", groupID: work.id)
        let second = try Fixture.profile(.codex, path: "/tmp/.codex", label: "Codex")
        let disabled = try Fixture.profile(.codex, path: "/tmp/.codex-off", label: "Off", isEnabled: false)
        let settings = try WidgetFixture.settings([first, second, disabled], groups: [work], filter: work.id)
        #expect(settings.appearance.railGroupFilter == work.id)
        // State order differs from settings order and lacks the second account entirely.
        let state = TrackerState(accounts: [
            AccountStatus(profile: disabled, reading: try Fixture.reading([try Fixture.window("primary", used: 5)])),
            AccountStatus(profile: first, reading: try Fixture.reading([try Fixture.window("session", .session, used: 40)])),
        ])

        let snapshot = WidgetSnapshot.make(state: state, settings: settings, now: WidgetFixture.now, language: .ru)
        #expect(snapshot.version == WidgetSnapshot.currentVersion)
        #expect(snapshot.generatedAt == WidgetFixture.now)
        #expect(snapshot.accounts.map(\.label) == ["Claude", "Codex"])
        #expect(snapshot.accounts[0].hasReading)
        #expect(!snapshot.accounts[1].hasReading)
        #expect(snapshot.accounts[1].capturedAt == nil)
        #expect(snapshot.bands == settings.appearance.bands)
    }

    @Test("E-mail follows the visibility setting; organisation never enters the snapshot")
    func emailVisibility() throws {
        let profile = try Fixture.profile(.claude, path: "/tmp/.claude", label: "Claude")
        let identity = AccountIdentity(email: "example@test.com", organization: "example@test.com's Organization", plan: "Max")
        let state = TrackerState(accounts: [AccountStatus(profile: profile, identity: identity)])
        for (visibility, expected) in [(EmailVisibility.visible, "example@test.com"), (.masked, "e••••e@test.com"), (.hidden, nil)] {
            let snapshot = WidgetSnapshot.make(state: state, settings: try WidgetFixture.settings([profile], email: visibility), now: WidgetFixture.now, language: .ru)
            #expect(snapshot.accounts[0].email == expected)
            #expect(snapshot.accounts[0].plan == "Max")
            let json = String(decoding: try snapshot.encodedData(), as: UTF8.self)
            #expect(!json.contains("Organization"))
            if visibility != .visible {
                #expect(!json.contains("example@"))
            }
        }
    }

    @Test("Windows: main bucket in display order with headline ids, then other buckets with unique ids")
    func windows() throws {
        let profile = try Fixture.profile(.claude, path: "/tmp/.claude", label: "Claude")
        let main = try Fixture.bucket("claude", [
            try Fixture.window("week.fable", .weekly(model: "Fable"), used: 63, minutes: 10_080),
            try Fixture.window("week", .weekly(model: nil), used: 38, minutes: 10_080),
            try Fixture.window("session", .session, used: 20),
            try Fixture.window("week.sonnet", .weekly(model: "Sonnet only"), used: 70, minutes: 10_080),
        ])
        let spark = try LimitBucket(id: "spark", title: "GPT-5.3-Codex-Spark", windows: [try Fixture.window("session", .session, used: 12)], isLimitReached: false)
        let reading = try Fixture.reading([main, spark])
        let state = TrackerState(accounts: [AccountStatus(profile: profile, reading: reading)])

        let account = try #require(WidgetSnapshot.make(state: state, settings: try WidgetFixture.settings([profile]), now: WidgetFixture.now, language: .ru).accounts.first)
        #expect(account.windows.map(\.id) == ["claude/session", "claude/week", "claude/week.sonnet", "claude/week.fable", "spark/session"])
        #expect(account.windows.map(\.title) == ["Сессия · 5\u{00A0}ч", "Неделя · все модели", "Неделя · Sonnet", "Неделя · Fable", "Сессия · 5\u{00A0}ч"])
        #expect(account.windows.map(\.isMainBucket) == [true, true, true, true, false])
        #expect(account.windows[4].bucketTitle == "GPT-5.3-Codex-Spark")
        #expect(account.primaryWindowID == "claude/session")
        #expect(account.secondaryWindowID == "claude/week")
        #expect(account.modelWeeklyWindowID == "claude/week.sonnet")
        #expect(account.capturedAt == reading.capturedAt)
    }

    @Test("At most eight windows per account")
    func windowCap() throws {
        let profile = try Fixture.profile()
        let buckets = try (0..<3).map { index in
            try Fixture.bucket("b\(index)", try (0..<4).map { try Fixture.window("w\($0)", used: Double($0)) })
        }
        let state = TrackerState(accounts: [AccountStatus(profile: profile, reading: try Fixture.reading(buckets))])
        let account = try #require(WidgetSnapshot.make(state: state, settings: try WidgetFixture.settings([profile]), now: WidgetFixture.now, language: .ru).accounts.first)
        #expect(account.windows.count == WidgetAccount.maximumWindows)
        #expect(Set(account.windows.map(\.id)).count == WidgetAccount.maximumWindows)
    }

    @Test("Counts, staleness, provider limit and issues")
    func statusFields() throws {
        let claude = try Fixture.profile(.claude, path: "/tmp/.claude", label: "Claude")
        let codex = try Fixture.profile(.codex, path: "/tmp/.codex", label: "Codex")
        let old = WidgetFixture.now.addingTimeInterval(-AccountStatus.defaultStaleAfter - 60)
        let limited = try Fixture.reading([try Fixture.bucket("codex", [try Fixture.window("primary", used: 40)], limitReached: true)], at: old)
        let state = TrackerState(accounts: [
            AccountStatus(
                profile: claude,
                issue: TrackerIssue(kind: .signedOut, detail: "x", occurredAt: WidgetFixture.now),
                sessions: [
                    try WidgetFixture.session(.waiting, id: "a"),
                    try WidgetFixture.session(.waiting, id: "b"),
                    try WidgetFixture.session(.working, id: "c"),
                    try WidgetFixture.session(.idle, id: "d"),
                ]
            ),
            AccountStatus(profile: codex, reading: limited, sessions: [try WidgetFixture.session(.working, id: "e")]),
        ])
        let snapshot = WidgetSnapshot.make(state: state, settings: try WidgetFixture.settings([claude, codex]), now: WidgetFixture.now, language: .ru)
        #expect(snapshot.accounts[0].waitingCount == 2)
        #expect(snapshot.accounts[0].workingCount == 1)
        #expect(snapshot.accounts[0].notice == "вы не вошли")
        #expect(!snapshot.accounts[0].isStale)
        #expect(snapshot.accounts[1].isStale)
        #expect(snapshot.accounts[1].isLimitReached)
        #expect(snapshot.attentionCount == 2)
        #expect(snapshot.workingCount == 2)
    }
}

// MARK: - Coding

@Suite("Widget snapshot coding")
struct WidgetSnapshotCodingTests {
    @Test("Round trip keeps every value and is deterministic")
    func roundTrip() throws {
        let account = try WidgetAccount(
            id: AccountID(),
            label: "Claude",
            provider: .claude,
            plan: "Max",
            email: "e••••e@test.com",
            windows: [
                try WidgetFixture.item(try Fixture.window("session", .session, used: 57)),
                try WidgetFixture.item(try Fixture.window("week.fable", .weekly(model: "Fable"), used: 63, minutes: 10_080, resetsIn: nil)),
                try WidgetFixture.item(try Fixture.window("session", .session, used: 12), bucket: "spark", main: false),
            ],
            primaryWindowID: "main/session",
            modelWeeklyWindowID: "main/week.fable",
            capturedAt: WidgetFixture.now,
            isStale: true,
            isLimitReached: true,
            waitingCount: 2,
            workingCount: 1
        )
        let snapshot = WidgetFixture.snapshot([account], attention: 2)
        let data = try snapshot.encodedData()
        let decoded = try #require(WidgetSnapshot.decode(data))
        #expect(decoded == snapshot)
        #expect(try decoded.encodedData() == data)
    }

    @Test("Missing keys take defaults; invalid accounts and windows are dropped, not fatal")
    func tolerant() throws {
        let json = #"""
        {
          "accounts": [
            {"id": "8C8E4A0E-3B1A-4C7B-9D5E-0000000000A1", "label": "  Claude\u0007 ", "provider": "claude",
             "waitingCount": 5000, "primaryWindowID": "main/missing",
             "windows": [
               {"bucketID": "main", "window": {"id": "session", "scope": {"session": {}}, "used": 40}},
               {"bucketID": "bad id", "window": {"id": "week", "scope": {"session": {}}, "used": 10}},
               {"bucketID": "main", "window": {"id": "week", "scope": {"session": {}}, "used": -3}},
               {"bucketID": "main"}
             ]},
            {"id": "8C8E4A0E-3B1A-4C7B-9D5E-0000000000A2", "label": "Gemini", "provider": "gemini"},
            {"id": "not-a-uuid", "label": "X", "provider": "codex"},
            {"id": "8C8E4A0E-3B1A-4C7B-9D5E-0000000000A3", "label": "   ", "provider": "codex"},
            "garbage"
          ],
          "bands": {"watch": 90, "critical": 10},
          "futureKey": true
        }
        """#
        let snapshot = try #require(WidgetSnapshot.decode(Data(json.utf8)))
        #expect(snapshot.version == WidgetSnapshot.currentVersion)
        #expect(snapshot.generatedAt == .distantPast)
        #expect(snapshot.bands == .standard)
        #expect(snapshot.accounts.count == 1)
        let account = snapshot.accounts[0]
        #expect(account.label == "Claude")
        #expect(account.waitingCount == WidgetSnapshot.maximumCount)
        #expect(account.windows.map(\.id) == ["main/session"])
        // A window without a title gets an English one; a snapshot without a language is English.
        #expect(account.windows[0].title == "Session · 5h")
        #expect(snapshot.language == .en)
        #expect(account.primaryWindowID == nil)
        #expect(snapshot.attentionCount == WidgetSnapshot.maximumCount)
    }

    @Test("Garbage, empty and oversized data decode to nil")
    func refused() throws {
        #expect(WidgetSnapshot.decode(Data()) == nil)
        #expect(WidgetSnapshot.decode(Data("not json".utf8)) == nil)
        #expect(WidgetSnapshot.decode(Data("[]".utf8)) == nil)
        var huge = Data("{\"accounts\":[],\"pad\":\"".utf8)
        huge.append(Data(repeating: UInt8(ascii: "a"), count: WidgetSnapshot.maximumFileBytes))
        huge.append(Data("\"}".utf8))
        #expect(WidgetSnapshot.decode(huge) == nil)
    }

    @Test("Bounds: 16 accounts, distinct ids, 8 windows, capped strings and counts")
    func bounds() throws {
        let accounts = try (0..<20).map { index in
            try WidgetFixture.account("Account \(index)", windows: [try Fixture.window("w", used: 10)])
        }
        let duplicate = accounts[0]
        let snapshot = WidgetFixture.snapshot([duplicate] + accounts, attention: -4)
        #expect(snapshot.accounts.count == WidgetSnapshot.maximumAccounts)
        #expect(Set(snapshot.accounts.map(\.id)).count == WidgetSnapshot.maximumAccounts)
        #expect(snapshot.attentionCount == 0)

        let windows = try (0..<12).map { try WidgetFixture.item(try Fixture.window("w\($0)", used: 1)) }
        let account = try WidgetAccount(
            id: AccountID(),
            label: String(repeating: "x", count: 100),
            provider: .codex,
            plan: String(repeating: "p", count: 100),
            windows: windows + windows
        )
        #expect(account.windows.count == WidgetAccount.maximumWindows)
        #expect(account.label.count == AccountLabel.maximumLength)
        #expect((account.plan?.count ?? 0) == WidgetAccount.maximumPlanLength)
        #expect(throws: ValidationError.self) {
            try WidgetAccount(id: AccountID(), label: " \n ", provider: .codex)
        }
        #expect(throws: ValidationError.self) {
            try WidgetWindow(bucketID: "../etc", isMainBucket: true, window: try Fixture.window("w", used: 1), language: .ru)
        }
        let farReset = try LimitWindow(id: "w", scope: .rolling, used: .zero, duration: nil, resetsAt: Date(timeIntervalSince1970: 1e15))
        #expect(throws: ValidationError.self) {
            try WidgetWindow(bucketID: "main", isMainBucket: true, window: farReset, language: .ru)
        }
        let ancient = try WidgetAccount(
            id: AccountID(),
            label: "Codex",
            provider: .codex,
            windows: [try WidgetFixture.item(try Fixture.window("w", used: 1))],
            capturedAt: Date(timeIntervalSince1970: -1e12)
        )
        #expect(ancient.capturedAt == nil)
    }
}

// MARK: - Language

@Suite("Widget snapshot language")
struct WidgetSnapshotLanguageTests {
    @Test("The language round-trips, and a snapshot without one (or with an unknown one) is English")
    func coding() throws {
        let account = try WidgetFixture.account(windows: [try Fixture.window("session", .session, used: 40)])
        for language in Language.allCases {
            let snapshot = WidgetSnapshot(
                generatedAt: WidgetFixture.now, accounts: [account], bands: .standard, attentionCount: 0, workingCount: 0, language: language
            )
            let decoded = try #require(WidgetSnapshot.decode(try snapshot.encodedData()))
            #expect(decoded.language == language)
            #expect(decoded == snapshot)
        }
        #expect(WidgetSnapshot.decode(Data(#"{"accounts": []}"#.utf8))?.language == .en)
        #expect(WidgetSnapshot.decode(Data(#"{"accounts": [], "language": "de"}"#.utf8))?.language == .en)
        #expect(WidgetSnapshot.decode(Data(#"{"accounts": [], "language": 7}"#.utf8))?.language == .en)
        #expect(WidgetSnapshot.decode(Data(#"{"accounts": [], "language": "ru"}"#.utf8))?.language == .ru)
    }

    @Test("A language change alone is new, significant content")
    func content() throws {
        let account = try WidgetFixture.account(windows: [try Fixture.window("session", .session, used: 40)])
        let russian = WidgetFixture.snapshot([account])
        let english = WidgetSnapshot(
            generatedAt: WidgetFixture.now, accounts: [account], bands: .standard, attentionCount: 0, workingCount: 0, language: .en
        )
        #expect(!english.hasSameContent(as: russian))
        #expect(english.significance != russian.significance)
        var policy = WidgetExportPolicy()
        policy.recordPublish(russian, at: WidgetFixture.now)
        #expect(policy.decision(for: english, now: WidgetFixture.now.addingTimeInterval(WidgetExportPolicy.significantGap)) == .publish)
    }

    @Test("The builder writes titles and notices in the snapshot's language, and scoping keeps it")
    func builder() throws {
        let profile = try Fixture.profile(.claude, path: "/tmp/.claude", label: "Claude")
        let state = TrackerState(accounts: [
            AccountStatus(
                profile: profile,
                reading: try Fixture.reading([try Fixture.window("session", .session, used: 40)]),
                issue: TrackerIssue(kind: .signedOut, detail: "x", occurredAt: WidgetFixture.now)
            ),
        ])
        let settings = try WidgetFixture.settings([profile])
        let english = WidgetSnapshot.make(state: state, settings: settings, now: WidgetFixture.now, language: .en)
        #expect(english.language == .en)
        #expect(english.accounts[0].windows.map(\.title) == ["Session · 5h"])
        #expect(english.accounts[0].notice == "Not signed in")
        let russian = WidgetSnapshot.make(state: state, settings: settings, now: WidgetFixture.now, language: .ru)
        #expect(russian.accounts[0].windows.map(\.title) == ["Сессия · 5\u{00A0}ч"])
        #expect(russian.accounts[0].notice == "вы не вошли")
        #expect(russian.scoped(to: .provider(.claude)).language == .ru)
        #expect(english.scoped(to: .provider(.codex)).language == .en)
    }

    @Test("Entries read the snapshot's language; sample data follows the language asked for")
    func entries() throws {
        let snapshot = WidgetFixture.snapshot([try WidgetFixture.account(windows: [try Fixture.window("w", used: 10)])])
        #expect(LimitsEntry(date: WidgetFixture.now, snapshot: snapshot).localizer.language == .ru)
        #expect(LimitsTimelineProvider.entries(for: snapshot, now: WidgetFixture.now).allSatisfy { $0.localizer.language == .ru })
        let sample = WidgetSampleData.snapshot(now: WidgetFixture.now, language: .en)
        #expect(sample.language == .en)
        #expect(sample.accounts[0].windows[0].title == "Session · 5h")
        let preview = LimitsTimelineProvider.previewEntry(
            for: snapshot.scoped(to: .provider(.codex)), scope: .provider(.codex), isPreview: true, now: WidgetFixture.now
        )
        #expect(preview.snapshot?.language == .ru)
    }
}

// MARK: - Projection

@Suite("Widget timeline projection")
struct WidgetTimelineTests {
    @Test("A passed reset restarts usage at zero and moves the reset on by whole windows")
    func projection() throws {
        let window = try Fixture.window("session", .session, used: 80, minutes: 300, resetsIn: 3_600)
        let source = try WidgetFixture.item(window)
        let before = WidgetWindowState(source: source, date: WidgetFixture.now, thresholds: .standard)
        #expect(before.window == window)
        #expect(!before.hasResetSinceCapture)
        #expect(before.band == .critical)

        let later = WidgetFixture.now.addingTimeInterval(7 * 3_600)
        let after = WidgetWindowState(source: source, date: later, thresholds: .standard)
        #expect(after.hasResetSinceCapture)
        #expect(after.window.used == .zero)
        #expect(after.band == .ample)
        #expect(after.window.resetsAt == WidgetFixture.now.addingTimeInterval(3_600 + 2 * 18_000))
        #expect(after.progress.elapsed.map { abs($0 - 0.2) < 0.000_1 } == true)

        let unknownLength = try WidgetFixture.item(try Fixture.window("x", used: 50, minutes: nil, resetsIn: 60))
        let projected = WidgetWindowState(source: unknownLength, date: later, thresholds: .standard)
        #expect(projected.window.resetsAt == nil)
        #expect(projected.window.used == .zero)
    }

    @Test("The ring shows the highest main-bucket window; ties go to the shorter one")
    func binding() throws {
        let account = try WidgetAccount(
            id: AccountID(),
            label: "Claude",
            provider: .claude,
            windows: [
                try WidgetFixture.item(try Fixture.window("session", .session, used: 38, minutes: 300)),
                try WidgetFixture.item(try Fixture.window("week", .weekly(model: nil), used: 38, minutes: 10_080)),
                try WidgetFixture.item(try Fixture.window("week.fable", .weekly(model: "Fable"), used: 30, minutes: 10_080)),
                try WidgetFixture.item(try Fixture.window("session", used: 99), bucket: "spark", main: false),
            ],
            capturedAt: WidgetFixture.now
        )
        let state = WidgetAccountState(account: account, date: WidgetFixture.now, thresholds: .standard)
        #expect(state.binding?.id == "main/session")
        #expect(!state.isBlocked)
        #expect(state.worstBand == .ample)

        let fable = try WidgetAccount(
            id: AccountID(),
            label: "Claude",
            provider: .claude,
            windows: [
                try WidgetFixture.item(try Fixture.window("week", .weekly(model: nil), used: 38, minutes: 10_080)),
                try WidgetFixture.item(try Fixture.window("week.fable", .weekly(model: "Fable"), used: 63, minutes: 10_080)),
            ],
            capturedAt: WidgetFixture.now
        )
        let fableState = WidgetAccountState(account: fable, date: WidgetFixture.now, thresholds: .standard)
        #expect(fableState.binding?.title == "Неделя · Fable")
        #expect(fableState.worstBand == .watch)
    }

    @Test("Blocked by the exhausted window that resets last, or by the provider's flag until a reset")
    func blocked() throws {
        let account = try WidgetFixture.account(windows: [
            try Fixture.window("session", .session, used: 100, minutes: 300, resetsIn: 3_600),
            try Fixture.window("week", .weekly(model: nil), used: 100, minutes: 10_080, resetsIn: 86_400),
            try Fixture.window("week.fable", .weekly(model: "Fable"), used: 40, minutes: 10_080, resetsIn: 90_000),
        ])
        let state = WidgetAccountState(account: account, date: WidgetFixture.now, thresholds: .standard)
        #expect(state.isBlocked)
        #expect(state.blocking?.id == "main/week")
        #expect(state.headlineReset == WidgetFixture.now.addingTimeInterval(86_400))
        #expect(state.worstBand == .exhausted)

        let unknown = try WidgetFixture.account(windows: [
            try Fixture.window("a", used: 100, resetsIn: 60),
            try Fixture.window("b", used: 100, resetsIn: nil),
        ])
        #expect(WidgetAccountState(account: unknown, date: WidgetFixture.now, thresholds: .standard).blocking?.id == "main/b")

        let flagged = try WidgetFixture.account(windows: [try Fixture.window("primary", used: 40, resetsIn: 3_600)], isLimitReached: true)
        #expect(WidgetAccountState(account: flagged, date: WidgetFixture.now, thresholds: .standard).isBlocked)
        let afterReset = WidgetAccountState(account: flagged, date: WidgetFixture.now.addingTimeInterval(7_200), thresholds: .standard)
        #expect(!afterReset.isBlocked)
        #expect(afterReset.isStale)
    }

    @Test("Stale when the snapshot said so, when the reading ages past 30 minutes, or after a reset")
    func staleness() throws {
        #expect(WidgetAccountState.staleAfter > WidgetExportPolicy.routineGap + TimeInterval(ProviderKind.claude.defaultPollInterval.seconds))
        let fresh = try WidgetFixture.account(windows: [try Fixture.window("w", used: 10, resetsIn: 3_600)])
        #expect(!WidgetAccountState(account: fresh, date: WidgetFixture.now.addingTimeInterval(29 * 60), thresholds: .standard).isStale)
        #expect(WidgetAccountState(account: fresh, date: WidgetFixture.now.addingTimeInterval(31 * 60), thresholds: .standard).isStale)
        let flagged = try WidgetFixture.account(windows: [try Fixture.window("w", used: 10)], isStale: true)
        #expect(WidgetAccountState(account: flagged, date: WidgetFixture.now, thresholds: .standard).isStale)
        let empty = try WidgetAccount(id: AccountID(), label: "Codex", provider: .codex)
        let emptyState = WidgetAccountState(account: empty, date: WidgetFixture.now, thresholds: .standard)
        #expect(!emptyState.isStale)
        #expect(!emptyState.hasReading)
        #expect(emptyState.worstBand == nil)
        #expect(emptyState.binding == nil)
    }

    @Test("Display windows keep order and always include the ring's window")
    func displayWindows() throws {
        let account = try WidgetFixture.account(windows: [
            try Fixture.window("session", .session, used: 10),
            try Fixture.window("week", .weekly(model: nil), used: 20, minutes: 10_080),
            try Fixture.window("week.a", .weekly(model: "A"), used: 30, minutes: 10_080),
            try Fixture.window("week.b", .weekly(model: "B"), used: 90, minutes: 10_080),
        ])
        let state = WidgetAccountState(account: account, date: WidgetFixture.now, thresholds: .standard)
        #expect(state.windowsForDisplay(limit: 0).isEmpty)
        #expect(state.windowsForDisplay(limit: 2).map(\.id) == ["main/session", "main/week.b"])
        #expect(state.windowsForDisplay(limit: 3).map(\.id) == ["main/session", "main/week", "main/week.b"])
        #expect(state.windowsForDisplay(limit: 9).count == 4)
    }

    @Test("Countdowns switch to minutes within the last hour")
    func countdownStyle() {
        let now = WidgetFixture.now
        #expect(WidgetCountdown.style(until: now.addingTimeInterval(3 * 86_400), at: now) == .hoursAndDays)
        #expect(WidgetCountdown.style(until: now.addingTimeInterval(3_601), at: now) == .hoursAndDays)
        #expect(WidgetCountdown.style(until: now.addingTimeInterval(3_600), at: now) == .minutes)
        #expect(WidgetCountdown.style(until: now.addingTimeInterval(59), at: now) == .minutes)
        #expect(WidgetCountdown.style(until: now.addingTimeInterval(-5), at: now) == .minutes)
    }

    @Test("Entry dates: now, resets and the hour before them within 12 h (repeating windows included) and the stale moment, sorted and bounded")
    func entryDates() throws {
        let now = WidgetFixture.now
        let account = try WidgetFixture.account(
            windows: [
                try Fixture.window("session", .session, used: 10, minutes: 300, resetsIn: 3_600),
                try Fixture.window("week", .weekly(model: nil), used: 10, minutes: 10_080, resetsIn: 3 * 86_400),
                try Fixture.window("hourly", used: 10, minutes: nil, resetsIn: 7_200),
                try Fixture.window("never", used: 10, minutes: 300, resetsIn: nil),
            ],
            capturedAt: now.addingTimeInterval(-60)
        )
        let snapshot = WidgetFixture.snapshot([account])
        let dates = snapshot.timelineDates(from: now)
        #expect(dates == [
            now,
            now.addingTimeInterval(-60 + WidgetAccountState.staleAfter + 1),
            now.addingTimeInterval(3_600),
            now.addingTimeInterval(7_200),
            now.addingTimeInterval(18_000),
            now.addingTimeInterval(3_600 + 18_000),
            now.addingTimeInterval(36_000),
            now.addingTimeInterval(3_600 + 36_000),
        ])

        // A reset that already passed is projected forward, not listed in the past.
        let later = now.addingTimeInterval(2 * 3_600)
        let laterDates = snapshot.timelineDates(from: later)
        #expect(laterDates.first == later)
        #expect(laterDates.dropFirst().allSatisfy { $0 > later && $0 <= later.addingTimeInterval(WidgetSnapshot.timelineHorizon) })
        #expect(laterDates.contains(now.addingTimeInterval(3_600 + 18_000)))

        let many = try (0..<40).map { index in
            try WidgetFixture.account("A\(index)", windows: [try Fixture.window("w", used: 1, minutes: nil, resetsIn: Double(index + 1) * 600)])
        }
        let bounded = WidgetFixture.snapshot(Array(many.prefix(16))).timelineDates(from: now)
        #expect(bounded.count <= WidgetSnapshot.maximumTimelineEntries)
        #expect(bounded == bounded.sorted())
        #expect(WidgetFixture.snapshot([]).timelineDates(from: now) == [now])
    }

    @Test("The small widget features the most constrained account; medium keeps settings order")
    func selection() throws {
        let calm = try WidgetFixture.account("Calm", windows: [try Fixture.window("w", used: 20)])
        let busy = try WidgetFixture.account("Busy", windows: [try Fixture.window("w", used: 85)])
        let blocked = try WidgetFixture.account("Blocked", windows: [try Fixture.window("w", used: 100)])
        let empty = try WidgetAccount(id: AccountID(), label: "Empty", provider: .codex)
        let states = WidgetFixture.snapshot([empty, calm, busy, blocked]).states(at: WidgetFixture.now)

        #expect(WidgetSelection.mostConstrained(states)?.account.label == "Blocked")
        #expect(WidgetSelection.priorityOrder(states) == [3, 2, 1, 0])
        #expect(WidgetSelection.featured(states, limit: 2).map(\.account.label) == ["Busy", "Blocked"])
        #expect(WidgetSelection.featured(states, limit: 3).map(\.account.label) == ["Calm", "Busy", "Blocked"])
        #expect(WidgetSelection.featured(states, limit: 9).count == 4)
        #expect(WidgetSelection.featured(states, limit: 0).isEmpty)
        #expect(WidgetSelection.mostConstrained([]) == nil)

        let tie = WidgetFixture.snapshot([calm, try WidgetFixture.account("Calm 2", windows: [try Fixture.window("w", used: 20)])])
        #expect(WidgetSelection.mostConstrained(tie.states(at: WidgetFixture.now))?.account.label == "Calm")
    }
}

// MARK: - Layout plan

@Suite("Widget large layout plan")
struct WidgetLayoutPlanTests {
    private func metrics(_ height: Double) -> WidgetLayoutPlan.Metrics {
        WidgetLayoutPlan.Metrics(
            availableHeight: height,
            accountHeight: 38,
            accountSpacing: 14,
            rowsInset: 8,
            rowHeight: 15,
            rowSpacing: 6,
            footerHeight: 15
        )
    }

    @Test("Everything fits when there is room")
    func fits() {
        let plan = WidgetLayoutPlan(rowCounts: [3, 2], priority: [1, 0], metrics: metrics(400))
        #expect(plan.entries == [.init(index: 0, rowCount: 3), .init(index: 1, rowCount: 2)])
        #expect(plan.hiddenCount == 0)
        #expect(plan.showsEverything(rowCounts: [3, 2]))
    }

    @Test("Rows are shared round by round and never overflow")
    func sharesRows() {
        // 3 accounts: 3×38 + 2×14 = 142; each round adds 23 then 21 per account.
        let plan = WidgetLayoutPlan(rowCounts: [4, 4, 4], priority: [0, 1, 2], metrics: metrics(318))
        #expect(plan.entries.map(\.rowCount) == [3, 3, 2])
        #expect(plan.hiddenCount == 0)
        #expect(!plan.showsEverything(rowCounts: [4, 4, 4]))
    }

    @Test("Accounts that do not fit are hidden, least constrained first, and counted in the footer")
    func hides() {
        let plan = WidgetLayoutPlan(rowCounts: [2, 2, 2, 2, 2, 2, 2], priority: [6, 2, 4, 0, 1, 3, 5], metrics: metrics(320))
        // n accounts plus footer: 38n + 14(n−1) + 14 + 15 ≤ 320 → n = 5.
        #expect(plan.entries.map(\.index) == [0, 1, 2, 4, 6])
        #expect(plan.hiddenCount == 2)
        #expect(plan.entries.allSatisfy { $0.rowCount <= 2 })
        #expect(!plan.showsEverything(rowCounts: [0, 0, 0, 0, 0, 0, 0]))
    }

    @Test("Degenerate inputs")
    func degenerate() {
        #expect(WidgetLayoutPlan(rowCounts: [], priority: [], metrics: metrics(300)).entries.isEmpty)
        let tiny = WidgetLayoutPlan(rowCounts: [3, 3], priority: [0, 1], metrics: metrics(10))
        #expect(tiny.entries.isEmpty)
        #expect(tiny.hiddenCount == 2)
        // Unknown and repeated priority indices are ignored; missing ones are appended in order.
        let messy = WidgetLayoutPlan(rowCounts: [0, 1], priority: [7, 1, 1, -3], metrics: metrics(300))
        #expect(messy.entries == [.init(index: 0, rowCount: 0), .init(index: 1, rowCount: 1)])
    }
}

// MARK: - Export policy

@Suite("Widget export policy")
struct WidgetExportPolicyTests {
    private static let accountID = AccountID(rawValue: UUID(uuid: (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16)))

    private func snapshot(
        used: Double,
        waiting: Int = 0,
        working: Int = 0,
        windowID: String = "w",
        capturedAt: Date = WidgetFixture.now,
        isStale: Bool = false,
        at date: Date = WidgetFixture.now
    ) throws -> WidgetSnapshot {
        let account = try WidgetAccount(
            id: Self.accountID,
            label: "Claude",
            provider: .claude,
            windows: [try WidgetFixture.item(try Fixture.window(windowID, used: used, resetsIn: 86_400))],
            capturedAt: capturedAt,
            isStale: isStale,
            waitingCount: waiting,
            workingCount: working
        )
        return WidgetFixture.snapshot([account], at: date)
    }

    private func at(_ seconds: TimeInterval) -> Date {
        WidgetFixture.now.addingTimeInterval(seconds)
    }

    @Test("First snapshot is published, identical content skipped even with a new timestamp")
    func identical() throws {
        var policy = WidgetExportPolicy()
        let first = try snapshot(used: 10)
        #expect(policy.decision(for: first, now: WidgetFixture.now) == .publish)
        policy.recordPublish(first, at: WidgetFixture.now)
        #expect(policy.decision(for: try snapshot(used: 10, at: at(600)), now: at(600)) == .skipIdentical)
    }

    @Test("Routine changes — percentages within a band, counts, capture times — wait for the routine gap")
    func routine() throws {
        var policy = WidgetExportPolicy()
        policy.recordPublish(try snapshot(used: 10), at: WidgetFixture.now)
        let due = at(WidgetExportPolicy.routineGap)
        #expect(policy.decision(for: try snapshot(used: 14, at: at(60)), now: at(60)) == .wait(until: due))
        #expect(policy.decision(for: try snapshot(used: 10, working: 2, at: at(60)), now: at(60)) == .wait(until: due))
        #expect(policy.decision(for: try snapshot(used: 10, capturedAt: at(300), at: at(300)), now: at(300)) == .wait(until: due))
        #expect(policy.decision(for: try snapshot(used: 14, at: due), now: due) == .publish)
        // A clock that moved backwards never holds publishing back.
        #expect(policy.decision(for: try snapshot(used: 14, at: at(-5)), now: at(-5)) == .publish)
    }

    @Test("Significant changes are published within a minute: band, blocked, attention, stale, window set, big moves")
    func significant() throws {
        var policy = WidgetExportPolicy()
        #expect(WidgetExportPolicy.significantGap < WidgetExportPolicy.routineGap)
        policy.recordPublish(try snapshot(used: 42), at: WidgetFixture.now)
        let soon = at(5)
        let due = at(WidgetExportPolicy.significantGap)
        #expect(policy.decision(for: try snapshot(used: 55, at: soon), now: soon) == .wait(until: due))
        #expect(policy.decision(for: try snapshot(used: 100, at: soon), now: soon) == .wait(until: due))
        #expect(policy.decision(for: try snapshot(used: 42, waiting: 1, at: soon), now: soon) == .wait(until: due))
        #expect(policy.decision(for: try snapshot(used: 42, isStale: true, at: soon), now: soon) == .wait(until: due))
        #expect(policy.decision(for: try snapshot(used: 42, windowID: "other", at: soon), now: soon) == .wait(until: due))
        #expect(policy.decision(for: WidgetFixture.snapshot([], at: soon), now: soon) == .wait(until: due))
        #expect(policy.decision(for: try snapshot(used: 4, at: soon), now: soon) == .wait(until: due))
        let hidden = WidgetFixture.snapshot([try WidgetAccount(
            id: Self.accountID,
            label: "Claude",
            provider: .claude,
            email: "e••••e@test.com",
            windows: [try WidgetFixture.item(try Fixture.window("w", used: 42, resetsIn: 86_400))],
            capturedAt: WidgetFixture.now
        )], at: soon)
        #expect(policy.decision(for: hidden, now: soon) == .wait(until: due))
        #expect(policy.decision(for: try snapshot(used: 55, at: due), now: due) == .publish)

        policy.reset()
        #expect(policy.lastPublished == nil)
        #expect(policy.recentPublishes.isEmpty)
        #expect(policy.decision(for: try snapshot(used: 45, at: soon), now: soon) == .publish)
    }

    @Test("Never more than the hourly maximum, however significant")
    func hourlyCap() throws {
        var policy = WidgetExportPolicy()
        let maximum = WidgetExportPolicy.maximumPublishesPerHour
        for index in 0..<maximum {
            policy.recordPublish(try snapshot(used: 10, waiting: index), at: at(Double(index) * 120))
        }
        #expect(policy.recentPublishes.count == maximum)
        let now = at(Double(maximum) * 120)
        #expect(policy.decision(for: try snapshot(used: 10, waiting: 99, at: now), now: now) == .wait(until: at(3_600)))
        #expect(policy.decision(for: try snapshot(used: 10, waiting: 99, at: at(3_600)), now: at(3_600)) == .publish)
        policy.recordPublish(try snapshot(used: 10, waiting: 99), at: at(3_600))
        #expect(policy.recentPublishes.count == maximum)
        #expect(policy.recentPublishes.first == at(120))
    }

    @Test("Usage moves are measured per account window")
    func usageMoves() throws {
        let before = try snapshot(used: 30)
        #expect(try snapshot(used: 40).usageMoved(from: before, byAtLeast: 10))
        #expect(!(try snapshot(used: 39).usageMoved(from: before, byAtLeast: 10)))
        #expect(!(try snapshot(used: 90, windowID: "other").usageMoved(from: before, byAtLeast: 10)))
    }

    @Test("A snapshot waits until the state covers every enabled account")
    func stateReady() throws {
        let claude = try Fixture.profile(.claude, path: "/tmp/.claude", label: "Claude")
        let codex = try Fixture.profile(.codex, path: "/tmp/.codex", label: "Codex")
        let off = try Fixture.profile(.codex, path: "/tmp/.codex-off", label: "Off", isEnabled: false)
        let settings = try WidgetFixture.settings([claude, codex, off])
        #expect(!WidgetSnapshot.isStateReady(.empty, for: settings))
        #expect(!WidgetSnapshot.isStateReady(TrackerState(accounts: [AccountStatus(profile: claude)]), for: settings))
        #expect(WidgetSnapshot.isStateReady(TrackerState(accounts: [AccountStatus(profile: codex), AccountStatus(profile: claude)]), for: settings))
        #expect(WidgetSnapshot.isStateReady(.empty, for: try WidgetFixture.settings([off])))
    }
}

// MARK: - Widget extension helpers

@Suite("Widget extension")
struct WidgetExtensionTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("codometer-widget-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("The reader loads a regular file and refuses symlinks, oversized and missing files")
    func reader() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent(WidgetSnapshot.fileName)
        let snapshot = WidgetFixture.snapshot([try WidgetFixture.account(windows: [try Fixture.window("w", used: 42)])])
        try snapshot.encodedData().write(to: file)
        #expect(SnapshotFileReader(fileURL: file).load() == snapshot)

        let link = directory.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        #expect(SnapshotFileReader(fileURL: link).load() == nil)

        let big = directory.appendingPathComponent("big.json")
        try Data(repeating: 0x20, count: WidgetSnapshot.maximumFileBytes + 1).write(to: big)
        #expect(SnapshotFileReader(fileURL: big).readBounded() == nil)

        #expect(SnapshotFileReader(fileURL: directory.appendingPathComponent("missing.json")).load() == nil)
        #expect(SnapshotFileReader(fileURL: directory).load() == nil)

        // The diagnostics tell a missing file from a refused or damaged one.
        #expect(SnapshotFileReader(fileURL: file).read().name == "loaded")
        #expect(SnapshotFileReader(fileURL: directory.appendingPathComponent("missing.json")).read().name == "missing")
        #expect(SnapshotFileReader(fileURL: link).read().name == "invalid")
        #expect(SnapshotFileReader(fileURL: big).read().name == "invalid")
        #expect(SnapshotFileReader(fileURL: directory).read().name == "invalid")
        let garbage = directory.appendingPathComponent("garbage.json")
        try Data("not json".utf8).write(to: garbage)
        #expect(SnapshotFileReader(fileURL: garbage).read().name == "invalid")
        let locked = directory.appendingPathComponent("locked.json")
        try snapshot.encodedData().write(to: locked)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        #expect(SnapshotFileReader(fileURL: locked).read().name == "denied")
        #expect(SnapshotReadResult.noHome.snapshot == nil)
    }

    @Test("The standard reader points into the real home, as the sandbox exception names it")
    func standardPath() throws {
        let reader = try #require(SnapshotFileReader.standard())
        #expect(reader.fileURL.path.hasSuffix("/Library/Application Support/Codometer/Widget/snapshot.json"))
        #expect(reader.fileURL.path.hasPrefix(NSHomeDirectory()))
        #expect(SnapshotFileReader.homeOutsideContainer("/Users/me/Library/Containers/com.codometer.Codometer.Widgets/Data") == "/Users/me")
        #expect(SnapshotFileReader.homeOutsideContainer("/Users/me") == "/Users/me")
        #expect(SnapshotFileReader.homeOutsideContainer("relative/Library/Containers/x") == nil)
        #expect(SnapshotFileReader.homeOutsideContainer("/Library/Containers/x/Data") == nil)
    }

    @Test("Timeline entries share the snapshot; no snapshot gives one empty entry")
    func entries() throws {
        let now = WidgetFixture.now
        #expect(LimitsTimelineProvider.entries(for: nil, now: now).map(\.date) == [now])
        let snapshot = WidgetFixture.snapshot([
            try WidgetFixture.account(windows: [try Fixture.window("w", used: 85, minutes: nil, resetsIn: 600)], waiting: 1),
        ])
        let entries = LimitsTimelineProvider.entries(for: snapshot, now: now)
        #expect(entries.map(\.date) == snapshot.timelineDates(from: now))
        #expect(entries.allSatisfy { $0.snapshot == snapshot })
        #expect(entries[0].urgency == .critical)
        #expect(entries[0].hasAttention)
        #expect(Localizer.testRussian.widget.moreAccounts(1) == "ещё 1 аккаунт")
        #expect(Localizer.testRussian.widget.moreAccounts(3) == "ещё 3 аккаунта")
        #expect(Localizer.testRussian.widget.moreAccounts(11) == "ещё 11 аккаунтов")
        #expect(Localizer.testRussian.widget.moreAccounts(22) == "ещё 22 аккаунта")
        #expect(Localizer.testEnglish.widget.moreAccounts(1) == "1 more account")
        #expect(Localizer.testEnglish.widget.moreAccounts(3) == "3 more accounts")
    }

    @Test("Sample data is valid and never empty")
    func sample() {
        let sample = WidgetSampleData.snapshot(now: WidgetFixture.now, language: .ru)
        #expect(sample.accounts.count == 2)
        #expect(sample.accounts.allSatisfy { $0.hasReading })
        #expect(WidgetSnapshot.decode((try? sample.encodedData()) ?? Data()) == sample)
    }
}

// MARK: - Scopes

@Suite("Widget scopes")
struct WidgetScopeTests {
    @Test("Kinds are stable, distinct and round-trip")
    func kinds() {
        #expect(WidgetScope.all.kind == "CodometerLimits")
        #expect(WidgetScope.provider(.claude).kind == "CodometerClaude")
        #expect(WidgetScope.provider(.codex).kind == "CodometerCodex")
        #expect(WidgetSnapshot.widgetKind == "CodometerLimits")
        #expect(WidgetSnapshot.widgetKinds == [
            "CodometerLimits", "CodometerClaude", "CodometerCodex",
            "CodometerStrip", "CodometerClaudeStrip", "CodometerCodexStrip",
        ])
        #expect(Set(WidgetScope.allCases.map(\.kind)).count == WidgetScope.allCases.count)
        for scope in WidgetScope.allCases {
            #expect(WidgetScope(kind: scope.kind) == scope)
        }
        #expect(WidgetScope(kind: "CodometerOther") == nil)
        #expect(WidgetScope.all.provider == nil)
        #expect(WidgetScope.provider(.codex).provider == .codex)
    }

    @Test("A provider scope keeps that provider's accounts in order with their own counts")
    func scoped() throws {
        let claudeWork = try WidgetFixture.account("Claude · Работа", windows: [try Fixture.window("w", used: 20)], waiting: 2, working: 1)
        let codex = try WidgetFixture.account("Codex", provider: .codex, windows: [try Fixture.window("w", used: 50)], working: 3)
        let claudeHome = try WidgetFixture.account("Claude · Дом", windows: [try Fixture.window("w", used: 70)], working: 1)
        let snapshot = WidgetFixture.snapshot([claudeWork, codex, claudeHome])

        #expect(snapshot.scoped(to: .all) == snapshot)
        let claude = snapshot.scoped(to: .provider(.claude))
        #expect(claude.accounts.map(\.label) == ["Claude · Работа", "Claude · Дом"])
        #expect(claude.attentionCount == 2)
        #expect(claude.workingCount == 2)
        #expect(claude.generatedAt == snapshot.generatedAt)
        #expect(claude.bands == snapshot.bands)
        let codexOnly = snapshot.scoped(to: .provider(.codex))
        #expect(codexOnly.accounts.map(\.label) == ["Codex"])
        #expect(codexOnly.attentionCount == 0)
        #expect(codexOnly.workingCount == 3)
        #expect(WidgetFixture.snapshot([codex]).scoped(to: .provider(.claude)).accounts.isEmpty)
    }

    @Test("The most constrained account per provider; nil without one")
    func perProvider() throws {
        let calmClaude = try WidgetFixture.account("Claude A", windows: [try Fixture.window("w", used: 30)])
        let busyClaude = try WidgetFixture.account("Claude B", windows: [try Fixture.window("w", used: 90)])
        let blockedCodex = try WidgetFixture.account("Codex", provider: .codex, windows: [try Fixture.window("w", used: 100)])
        let states = WidgetFixture.snapshot([calmClaude, blockedCodex, busyClaude]).states(at: WidgetFixture.now)

        #expect(WidgetSelection.mostConstrained(states)?.account.label == "Codex")
        #expect(WidgetSelection.mostConstrained(states, provider: .claude)?.account.label == "Claude B")
        #expect(WidgetSelection.mostConstrained(states, provider: .codex)?.account.label == "Codex")
        let claudeOnly = WidgetFixture.snapshot([calmClaude]).states(at: WidgetFixture.now)
        #expect(WidgetSelection.mostConstrained(claudeOnly, provider: .codex) == nil)

        // An account without numbers still stands for its provider, after any account with numbers.
        let empty = try WidgetAccount(id: AccountID(), label: "Codex · Новый", provider: .codex, notice: "вы не вошли")
        let withEmpty = WidgetFixture.snapshot([empty, calmClaude]).states(at: WidgetFixture.now)
        #expect(WidgetSelection.mostConstrained(withEmpty, provider: .codex)?.account.label == "Codex · Новый")
    }

    @Test("The companion ring pairs the ring window with the busiest window of another length")
    func companion() throws {
        let session = try Fixture.window("session", .session, used: 57, minutes: 300)
        let week = try Fixture.window("week", .weekly(model: nil), used: 38, minutes: 10_080)
        let fable = try Fixture.window("week.fable", .weekly(model: "Fable"), used: 63, minutes: 10_080)

        func state(_ windows: [LimitWindow], other: [WidgetWindow] = []) throws -> WidgetAccountState {
            let items = try windows.map { try WidgetFixture.item($0, bucket: "claude") } + other
            let account = try WidgetAccount(id: AccountID(), label: "Claude", provider: .claude, windows: items, capturedAt: WidgetFixture.now)
            return WidgetAccountState(account: account, date: WidgetFixture.now, thresholds: .standard)
        }

        // Fable binds the ring; the session is the only window of another length.
        let claude = try state([session, week, fable])
        #expect(claude.binding?.window.id == "week.fable")
        #expect(claude.companion?.window.id == "session")

        // The session binds; the busier weekly window keeps it company.
        let sessionHeavy = try state([try Fixture.window("session", .session, used: 91, minutes: 300), week, fable])
        #expect(sessionHeavy.companion?.window.id == "week.fable")

        // Only windows of the same length: the busiest other one.
        let sameLength = try state([try Fixture.window("a", used: 10, minutes: 300), try Fixture.window("b", used: 40, minutes: 300), try Fixture.window("c", used: 30, minutes: 300)])
        #expect(sameLength.binding?.window.id == "b")
        #expect(sameLength.companion?.window.id == "c")

        // Other buckets never become the companion; a lone window has none.
        let spark = try WidgetFixture.item(try Fixture.window("primary", used: 99, minutes: 10_080), bucket: "spark", main: false)
        let lone = try state([session], other: [spark])
        #expect(lone.binding?.window.id == "session")
        #expect(lone.companion == nil)
        #expect(try state([]).companion == nil)
    }

    @Test("Working badge only while nobody waits")
    func workingOnly() throws {
        let window = try Fixture.window("w", used: 10)
        func state(waiting: Int, working: Int) throws -> WidgetAccountState {
            let account = try WidgetFixture.account(windows: [window], waiting: waiting, working: working)
            return WidgetAccountState(account: account, date: WidgetFixture.now, thresholds: .standard)
        }
        #expect(try state(waiting: 0, working: 2).isWorkingOnly)
        #expect(try !state(waiting: 1, working: 2).isWorkingOnly)
        #expect(try !state(waiting: 0, working: 0).isWorkingOnly)
    }

    @Test("Provider timelines are scoped; the gallery falls back to sample numbers only without accounts")
    func providerEntries() throws {
        let now = WidgetFixture.now
        let codex = try WidgetFixture.account("Codex", provider: .codex, windows: [try Fixture.window("w", used: 40, minutes: nil, resetsIn: 7_200)])
        let claude = try WidgetFixture.account("Claude", windows: [try Fixture.window("w", used: 60, minutes: nil, resetsIn: 600)], waiting: 1)
        let snapshot = WidgetFixture.snapshot([claude, codex])

        let codexEntries = LimitsTimelineProvider.entries(for: snapshot, scope: .provider(.codex), now: now)
        #expect(codexEntries.allSatisfy { $0.scope == .provider(.codex) && $0.snapshot?.accounts.map(\.label) == ["Codex"] })
        #expect(codexEntries.map(\.date) == snapshot.scoped(to: .provider(.codex)).timelineDates(from: now))
        #expect(!codexEntries[0].hasAttention)
        #expect(LimitsTimelineProvider.entries(for: snapshot, scope: .provider(.claude), now: now)[0].hasAttention)
        #expect(LimitsTimelineProvider.entries(for: nil, scope: .provider(.claude), now: now).map(\.snapshot) == [nil])

        let onlyClaude = WidgetFixture.snapshot([claude])
        let noCodex = LimitsTimelineProvider.entries(for: onlyClaude, scope: .provider(.codex), now: now)
        #expect(noCodex.count == 1)
        #expect(noCodex[0].snapshot?.accounts.isEmpty == true)

        let preview = LimitsTimelineProvider.previewEntry(for: onlyClaude, scope: .provider(.codex), isPreview: true, now: now)
        #expect(preview.snapshot?.accounts.map(\.provider) == [.codex])
        let live = LimitsTimelineProvider.previewEntry(for: onlyClaude, scope: .provider(.codex), isPreview: false, now: now)
        #expect(live.snapshot?.accounts.isEmpty == true)
        let real = LimitsTimelineProvider.previewEntry(for: snapshot, scope: .provider(.claude), isPreview: true, now: now)
        #expect(real.snapshot?.accounts.map(\.label) == ["Claude"])
        #expect(LimitsTimelineProvider.previewEntry(for: nil, scope: .all, isPreview: true, now: now).snapshot?.accounts.count == 2)
        #expect(LimitsTimelineProvider.previewEntry(for: nil, scope: .all, isPreview: false, now: now).snapshot == nil)
    }

    @Test("Diagnostics count accounts without carrying their content")
    func diagnostics() throws {
        let now = WidgetFixture.now
        let fresh = try WidgetFixture.account("Claude", windows: [try Fixture.window("w", used: 60)])
        let stale = try WidgetFixture.account("Claude · Старый", windows: [try Fixture.window("w", used: 60)], capturedAt: now.addingTimeInterval(-3_600))
        let codex = try WidgetAccount(id: AccountID(), label: "Codex", provider: .codex)
        let snapshot = WidgetFixture.snapshot([fresh, stale, codex], at: now.addingTimeInterval(-125))

        let claude = WidgetDiagnostics.Summary(result: .loaded(snapshot), scope: .provider(.claude), now: now)
        #expect(claude.file == "loaded")
        #expect(claude.totalAccounts == 3)
        #expect(claude.scopedAccounts == 2)
        #expect(claude.withReading == 2)
        #expect(claude.stale == 1)
        #expect(claude.ageSeconds == 125)

        let all = WidgetDiagnostics.Summary(result: .loaded(snapshot), scope: .all, now: now)
        #expect(all.scopedAccounts == 3)
        #expect(all.withReading == 2)

        let missing = WidgetDiagnostics.Summary(result: .missing, scope: .all, now: now)
        #expect(missing.file == "missing")
        #expect(missing.totalAccounts == 0)
        #expect(missing.ageSeconds == nil)
    }
}

// MARK: - Copy

@Suite("Widget phrases")
struct WidgetPhraseTests {
    @Test("Gallery names and descriptions in both languages")
    func gallery() {
        let english = WidgetGallery.text(for: .all, l10n: .testEnglish)
        #expect(english.name == "AI Limits")
        #expect(english.description == "Claude and Codex limits at a glance: usage rings, reset times, and agents waiting for you.")
        let russian = WidgetGallery.text(for: .all, l10n: .testRussian)
        #expect(russian.name == "Лимиты AI")
        #expect(russian.description == "Лимиты Claude и Codex: кольца расхода, время сброса и агенты, которые ждут вас.")

        let codex = WidgetGallery.text(for: .provider(.codex), l10n: .testEnglish)
        #expect(codex.name == "Codex")
        #expect(codex.description == "Your busiest Codex account: usage rings, reset times, and agent activity.")
        let claude = WidgetGallery.text(for: .provider(.claude), l10n: .testRussian)
        #expect(claude.name == "Claude")
        #expect(claude.description == "Самый загруженный аккаунт Claude: кольца расхода, время сброса и работа агентов.")
    }

    @Test("Empty states")
    func emptyStates() {
        let en = Localizer.testEnglish.widget
        #expect(en.openApp == "Open Codometer")
        #expect(en.openAppToSeeLimits == "Open Codometer to see your limits")
        #expect(en.noAccount("Codex") == "No Codex account")
        #expect(en.addOne == "Add one in Codometer")
        #expect(en.addProfile("Claude") == "Add a Claude profile in Codometer\u{00A0}→\u{00A0}Settings\u{00A0}→\u{00A0}Accounts")
        let ru = Localizer.testRussian.widget
        #expect(ru.openApp == "Откройте Codometer")
        #expect(ru.openAppToSeeLimits == "Откройте Codometer, чтобы увидеть лимиты")
        #expect(ru.noAccount("Codex") == "Нет аккаунта Codex")
        #expect(ru.addOne == "Добавьте его в Codometer")
        #expect(ru.addProfile("Claude") == "Добавьте профиль Claude в Codometer\u{00A0}→\u{00A0}Настройки\u{00A0}→\u{00A0}Аккаунты")
    }

    @Test("Status lines: sentence case in English, lowercase captions in Russian; slots around live text")
    func statusLines() {
        let en = Localizer.testEnglish.widget
        #expect(en.waitingForData == "Waiting for data")
        #expect(en.limitReached == "Limit reached")
        #expect(en.noResetTime == "No reset time")
        #expect(en.resetsIn.prefix == "Resets in " && en.resetsIn.suffix.isEmpty)
        #expect(en.resetsInShort.prefix == "Resets in ")
        #expect(en.backIn.prefix == "Back in ")
        #expect(en.staleAsOf.prefix == "As of " && en.latestAsOf.prefix == "As of ")
        let ru = Localizer.testRussian.widget
        #expect(ru.waitingForData == "ожидание данных")
        #expect(ru.limitReached == "лимит исчерпан")
        #expect(ru.noResetTime == "без времени сброса")
        #expect(ru.resetsIn.prefix == "сброс через " && ru.resetsIn.suffix.isEmpty)
        #expect(ru.resetsInShort.prefix == "через ")
        #expect(ru.backIn.prefix == "через ")
        #expect(ru.staleAsOf.prefix == "данные от ")
        #expect(ru.latestAsOf.prefix == "данные на ")
    }

    @Test("Counts and badges")
    func counts() {
        let en = Localizer.testEnglish.widget
        #expect(en.working(3) == "3 working")
        #expect(en.waiting(1) == "1 waiting")
        #expect(en.waiting(2) == "2 waiting")
        #expect(en.moreAccounts(21) == "21 more accounts")
        let ru = Localizer.testRussian.widget
        #expect(ru.working(3) == "в работе: 3")
        #expect(ru.waiting(1) == "ждёт вас: 1")
        #expect(ru.waiting(2) == "ждут вас: 2")
        #expect(ru.waiting(11) == "ждут вас: 11")
        #expect(ru.waiting(21) == "ждёт вас: 21")
        #expect(ru.moreAccounts(21) == "ещё 21 аккаунт")
        #expect(ru.moreAccounts(5) == "ещё 5 аккаунтов")
    }

    @Test("VoiceOver agrees number and verb")
    func voiceOver() {
        let en = Localizer.testEnglish.widget
        #expect(en.waitingA11y(1) == "1 agent is waiting for you")
        #expect(en.waitingA11y(2) == "2 agents are waiting for you")
        #expect(en.workingA11y(1) == "1 agent is working")
        #expect(en.workingA11y(12) == "12 agents are working")
        #expect(en.percentUsedA11y(Localizer.testEnglish.format.percent(64)) == "64% used")
        let ru = Localizer.testRussian.widget
        #expect(ru.waitingA11y(1) == "Вас ждёт 1 агент")
        #expect(ru.waitingA11y(3) == "Вас ждут 3 агента")
        #expect(ru.waitingA11y(11) == "Вас ждут 11 агентов")
        #expect(ru.waitingA11y(21) == "Вас ждёт 21 агент")
        #expect(ru.workingA11y(1) == "Работает 1 агент")
        #expect(ru.workingA11y(4) == "Работают 4 агента")
        #expect(ru.workingA11y(25) == "Работают 25 агентов")
        #expect(ru.percentUsedA11y(Localizer.testRussian.format.percent(64)) == "использовано 64\u{00A0}%")
    }
}

/// Widget text measured in the widget's real font (SF Rounded) against the room its view gives it.
///
/// A line with `minimumScaleFactor` fits when its natural width, scaled down to that factor, fits. Countdowns are the
/// system's live text, so they are measured with the formatter that produces the same words ("23 hr, 59 min",
/// "59 minutes" | «23 ч 59 мин», «59 минут»).
@Suite("Widget copy fit")
struct WidgetCopyFitTests {
    /// Content width inside the 16 pt margins.
    static let smallWidth: CGFloat = 164 - 32
    static let mediumWidth: CGFloat = 344 - 32
    /// A status line's symbol and the spacing after it.
    static let symbolRoom: CGFloat = 12 + 3
    /// Status lines may shrink to this factor.
    static let statusScale: CGFloat = 0.8

    static func localizer(_ language: Language) -> Localizer {
        language == .en ? .testEnglish : .testRussian
    }

    static func font(_ size: CGFloat, _ weight: NSFont.Weight, digits: Bool = false) -> NSFont {
        let base = digits ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded), let rounded = NSFont(descriptor: descriptor, size: size) else {
            return base
        }
        return rounded
    }

    static func width(_ text: String, _ font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    /// The widest countdowns `Countdown` draws: hours and days up to a monthly window, then minutes, then seconds.
    static func countdowns(_ l10n: Localizer) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = l10n.locale
        let long = DateComponentsFormatter()
        long.calendar = calendar
        long.unitsStyle = .short
        long.maximumUnitCount = 2
        long.allowedUnits = [.day, .hour, .minute]
        let short = DateComponentsFormatter()
        short.calendar = calendar
        short.unitsStyle = .full
        short.maximumUnitCount = 1
        short.allowedUnits = [.minute, .second]
        let hoursAndDays: [TimeInterval] = [4 * 3_600 + 59 * 60, 23 * 3_600 + 59 * 60, 6 * 86_400 + 22 * 3_600, 29 * 86_400 + 22 * 3_600]
        let minutes: [TimeInterval] = [59 * 60, 59]
        return hoursAndDays.compactMap(long.string(from:)) + minutes.compactMap(short.string(from:))
    }

    /// Clock and day texts of a stale reading.
    static func readingTimes(_ l10n: Localizer) -> [String] {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let noon = l10n.calendar.date(bySettingHour: 12, minute: 59, second: 0, of: date) ?? date
        let evening = l10n.calendar.date(bySettingHour: 23, minute: 59, second: 0, of: date) ?? date
        return [
            noon.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: l10n.locale, calendar: l10n.calendar, timeZone: l10n.calendar.timeZone)),
            evening.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: l10n.locale, calendar: l10n.calendar, timeZone: l10n.calendar.timeZone)),
            date.formatted(Date.FormatStyle(locale: l10n.locale, calendar: l10n.calendar, timeZone: l10n.calendar.timeZone).day().month(.abbreviated)),
        ]
    }

    static func fits(_ text: String, _ font: NSFont, in room: CGFloat, scale: CGFloat = 1) -> Bool {
        width(text, font) * scale <= room
    }

    @Test("The countdown formatter speaks the widget's words", arguments: Language.allCases)
    func countdownWords(language: Language) {
        let words = Self.countdowns(Self.localizer(language))
        #expect(words.count == 6)
        switch language {
        case .en: #expect(words.contains("23 hr, 59 min") && words.contains("59 minutes"))
        case .ru: #expect(words.contains { $0.contains("мин") } && words.contains { $0.contains("минут") })
        }
    }

    @Test("Reset and freshness lines fit the small widgets", arguments: Language.allCases)
    func smallStatusLines(language: Language) {
        let l10n = Self.localizer(language)
        let widget = l10n.widget
        let room = Self.smallWidth - Self.symbolRoom
        for (size, resetSlot) in [(CGFloat(11.5), widget.resetsIn), (11, widget.resetsInShort)] {
            let font = Self.font(size, .medium, digits: true)
            var lines = Self.countdowns(l10n).flatMap { countdown in
                [resetSlot.prefix + countdown + resetSlot.suffix, widget.backIn.prefix + countdown + widget.backIn.suffix]
            }
            lines += Self.readingTimes(l10n).map { widget.staleAsOf.prefix + $0 + widget.staleAsOf.suffix }
            lines += [widget.waitingForData, widget.limitReached, widget.noResetTime]
            for line in lines {
                #expect(Self.fits(line, font, in: room, scale: Self.statusScale), "\(line) at \(size) pt: \(Self.width(line, font)) pt")
            }
        }
    }

    @Test("Reset lines fit two and three medium columns", arguments: Language.allCases)
    func mediumColumns(language: Language) {
        let l10n = Self.localizer(language)
        let widget = l10n.widget
        let font = Self.font(11, .medium, digits: true)
        let twoColumns = (Self.mediumWidth - 1) / 2 - 8 - Self.symbolRoom
        let threeColumns = (Self.mediumWidth - 2) / 3 - 8 - Self.symbolRoom
        for countdown in Self.countdowns(l10n) {
            for line in [widget.resetsIn.prefix + countdown, widget.backIn.prefix + countdown] {
                #expect(Self.fits(line, font, in: twoColumns, scale: Self.statusScale), "\(line): \(Self.width(line, font)) pt")
            }
            // Three columns drop the words.
            #expect(Self.fits(countdown, font, in: threeColumns, scale: Self.statusScale), "\(countdown): \(Self.width(countdown, font)) pt")
        }
    }

    @Test("A blocked account's countdown fits where it is the headline", arguments: Language.allCases)
    func headlineCountdowns(language: Language) {
        let l10n = Self.localizer(language)
        for countdown in Self.countdowns(l10n) {
            // Small widget: 25 pt, may shrink to 55 %.
            #expect(Self.fits(countdown, Self.font(25, .bold, digits: true), in: Self.smallWidth, scale: 0.55), "\(countdown)")
            // Medium, one account: inside the ring in a 70 pt frame, may shrink to 60 %.
            #expect(Self.fits(countdown, Self.font(14, .bold, digits: true), in: 70, scale: 0.6), "\(countdown)")
            // Large list: 15 pt at full size beside the account, which keeps at least 100 pt for its label.
            #expect(Self.mediumWidth - 38 - 16 - Self.width(countdown, Self.font(15, .bold, digits: true)) >= 100, "\(countdown)")
        }
    }

    @Test("Empty states fit on their lines", arguments: Language.allCases)
    func emptyStates(language: Language) {
        let l10n = Self.localizer(language)
        let widget = l10n.widget
        let caption = Self.font(11.5, .medium)
        // Two lines each.
        #expect(Self.fits(widget.openApp, caption, in: 2 * Self.smallWidth))
        #expect(Self.fits(widget.openAppToSeeLimits, caption, in: 2 * Self.mediumWidth))
        #expect(Self.fits(l10n.common.noData, Self.font(14, .semibold), in: Self.smallWidth))
        for provider in ["Claude", "Codex"] {
            // One line, allowed to shrink to 80 %.
            #expect(Self.fits(widget.noAccount(provider), Self.font(13, .semibold), in: Self.smallWidth, scale: 0.8))
            #expect(Self.fits(widget.noAccount(provider), Self.font(14, .semibold), in: Self.mediumWidth))
            #expect(Self.fits(widget.addOne, Self.font(11, .medium), in: 2 * Self.smallWidth))
            #expect(Self.fits(widget.addProfile(provider), Self.font(11, .medium), in: 2 * Self.mediumWidth))
            // The menu path is kept on one line, so it must fit one.
            let path = widget.addProfile(provider).split(separator: " ").last.map(String.init) ?? ""
            #expect(path.contains("→") && Self.fits(path, Self.font(11, .medium), in: Self.mediumWidth), "\(path)")
        }
    }

    @Test("The large widget's header, footer and status line leave room", arguments: Language.allCases)
    func largeWidget(language: Language) {
        let l10n = Self.localizer(language)
        let widget = l10n.widget
        let header = Self.width(widget.allName, Self.font(15, .bold)) + 8 + 18 + Self.width(widget.waiting(12), Self.font(12, .semibold, digits: true))
        #expect(header <= Self.mediumWidth)
        #expect(Self.fits(widget.moreAccounts(14), Self.font(11.5, .medium), in: Self.mediumWidth))
        let digits = Self.font(11, .medium, digits: true)
        for time in Self.readingTimes(l10n) {
            let status = 2 * 13 + Self.width(widget.latestAsOf.prefix + time, digits) + 6 + Self.width(widget.working(16), digits)
            #expect(status <= Self.mediumWidth, "\(time): \(status) pt")
        }
        // A compact countdown beside an account leaves the label at least 120 pt (ring 38, spacings 16).
        for countdown in Self.countdowns(l10n) {
            let trailing = Self.symbolRoom + Self.width(countdown, digits)
            #expect(Self.mediumWidth - 38 - 16 - trailing >= 120, "\(countdown): \(trailing) pt")
        }
    }

    @Test("Window titles fit the large widget's title column and the small widget", arguments: Language.allCases)
    func windowTitles(language: Language) throws {
        let l10n = Self.localizer(language)
        let titles = [
            WidgetText.windowTitle(try Fixture.window("week", .weekly(model: nil), used: 10, minutes: 10_080), l10n: l10n),
            WidgetText.windowTitle(try Fixture.window("session", .session, used: 10), l10n: l10n),
            WidgetText.windowTitle(try Fixture.window("week.sonnet", .weekly(model: "Sonnet only"), used: 10, minutes: 10_080), l10n: l10n),
            "Spark · " + WidgetText.windowTitle(try Fixture.window("session", .session, used: 10), l10n: l10n),
        ]
        for title in titles {
            #expect(Self.fits(title, Self.font(11.5, .medium), in: 122, scale: 0.9), "\(title)")
            #expect(Self.fits(title, Self.font(12.5, .semibold), in: Self.smallWidth, scale: 0.8), "\(title)")
        }
    }
}

// MARK: - Account identity

@Suite("Widget account identity")
struct WidgetAccountIdentityTests {
    private static func mark(_ tint: AccountTint, _ monogram: String) throws -> (AccountTint, AccountMonogram) {
        (tint, try AccountMonogram(validating: monogram))
    }

    @Test("Tint and monogram round-trip through the snapshot file")
    func roundTrip() throws {
        let (tint, monogram) = try Self.mark(.indigo, "wa")
        let account = try WidgetAccount(
            id: AccountID(),
            label: "Claude · Work",
            provider: .claude,
            tint: tint,
            monogram: monogram,
            windows: [try WidgetFixture.item(try Fixture.window("session", .session, used: 40))]
        )
        #expect(account.monogram?.value == "WA")
        let decoded = try #require(WidgetSnapshot.decode(try WidgetFixture.snapshot([account]).encodedData()))
        #expect(decoded.accounts[0].tint == .indigo)
        #expect(decoded.accounts[0].monogram?.value == "WA")
        #expect(decoded.accounts[0] == account)
    }

    @Test("An emoji monogram survives the round trip")
    func emoji() throws {
        let account = try WidgetAccount(
            id: AccountID(),
            label: "Codex",
            provider: .codex,
            tint: .sand,
            monogram: try AccountMonogram(validating: "🚀")
        )
        let decoded = try #require(WidgetSnapshot.decode(try WidgetFixture.snapshot([account]).encodedData()))
        #expect(decoded.accounts[0].monogram?.value == "🚀")
    }

    @Test("A snapshot from an older build decodes, with no identity mark, and reads as the current version")
    func olderFile() throws {
        let json = #"""
        {
          "version": 1, "generatedAt": 1789600000, "attentionCount": 0, "workingCount": 0,
          "bands": {"watch": 60, "critical": 85},
          "accounts": [
            {"id": "8C8E4A0E-3B1A-4C7B-9D5E-0000000000B1", "label": "Claude", "provider": "claude",
             "windows": [{"bucketID": "main", "isMainBucket": true, "title": "Session · 5h",
                          "window": {"id": "session", "scope": {"session": {}}, "used": 40}}]}
          ]
        }
        """#
        let snapshot = try #require(WidgetSnapshot.decode(Data(json.utf8)))
        #expect(snapshot.version == WidgetSnapshot.currentVersion)
        #expect(snapshot.layout == .rings)
        #expect(snapshot.accounts.count == 1)
        #expect(snapshot.accounts[0].tint == nil)
        #expect(snapshot.accounts[0].monogram == nil)
        #expect(snapshot.accounts[0].windows.count == 1)
    }

    @Test("An unknown tint, `automatic`, and a monogram that no longer validates are dropped, not fatal")
    func tolerant() throws {
        func account(_ fields: String) throws -> WidgetAccount {
            let json = """
            {"accounts": [{"id": "8C8E4A0E-3B1A-4C7B-9D5E-0000000000B2", "label": "Claude", "provider": "claude", \(fields)}]}
            """
            let snapshot = try #require(WidgetSnapshot.decode(Data(json.utf8)))
            return try #require(snapshot.accounts.first)
        }
        #expect(try account(#""tint": "chartreuse""#).tint == nil)
        #expect(try account(#""tint": 7"#).tint == nil)
        #expect(try account(#""tint": "automatic""#).tint == nil)
        #expect(try account(#""tint": "slate""#).tint == .slate)
        #expect(try account(#""monogram": "ABC""#).monogram == nil)
        #expect(try account(#""monogram": " ""#).monogram == nil)
        #expect(try account(#""monogram": 3"#).monogram == nil)
        #expect(try account(#""monogram": "wa""#).monogram?.value == "WA")
        // `.automatic` never leaves the resolver, and never enters a snapshot through the initialiser either.
        let direct = try WidgetAccount(id: AccountID(), label: "Claude", provider: .claude, tint: .automatic)
        #expect(direct.tint == nil)
    }

    private static func profile(
        _ provider: ProviderKind,
        path: String,
        label: String,
        isEnabled: Bool = true,
        tint: AccountTint = .automatic
    ) throws -> AccountProfile {
        try AccountProfile(
            provider: provider,
            label: try AccountLabel(validating: label),
            directory: try ProfileDirectory(validating: path),
            isEnabled: isEnabled,
            tint: tint
        )
    }

    @Test("The builder resolves marks over the whole account list, disabled accounts included")
    func builder() throws {
        let work = try Self.profile(.claude, path: "/tmp/.claude-work", label: "Claude · Work", tint: .pink)
        let off = try Self.profile(.claude, path: "/tmp/.claude-off", label: "Claude · Archive", isEnabled: false)
        let personal = try Self.profile(.claude, path: "/tmp/.claude-home", label: "Claude · Personal")
        let bare = try Self.profile(.codex, path: "/tmp/.codex", label: "Codex")
        let settings = try WidgetFixture.settings([work, off, personal, bare])
        let state = TrackerState(accounts: [work, personal, bare].map { AccountStatus(profile: $0) })
        let snapshot = WidgetSnapshot.make(state: state, settings: settings, now: WidgetFixture.now, language: .en)

        #expect(snapshot.accounts.map(\.id) == [work.id, personal.id, bare.id])
        #expect(snapshot.accounts[0].tint == .pink)
        // Ordinals run per provider, and a label that is only the provider's name falls back to one: "Codex" → "1".
        #expect(snapshot.accounts.map { $0.monogram?.value } == ["W", "P", "1"])
        let styles = AccountStyleResolver.styles(for: settings.accounts)
        #expect(snapshot.accounts.allSatisfy { $0.tint == styles[$0.id]?.tint && $0.monogram == styles[$0.id]?.monogram })
        #expect(snapshot.accounts.allSatisfy { $0.tint != .automatic })
    }

    @Test("A new monogram or tint reaches the widget as a significant change")
    func significance() throws {
        let windows = [try WidgetFixture.item(try Fixture.window("session", .session, used: 40))]
        func account(_ tint: AccountTint, _ monogram: String) throws -> WidgetAccount {
            try WidgetAccount(
                id: AccountID(rawValue: UUID(uuidString: "8C8E4A0E-3B1A-4C7B-9D5E-0000000000B3") ?? UUID()),
                label: "Claude",
                provider: .claude,
                tint: tint,
                monogram: try AccountMonogram(validating: monogram),
                windows: windows
            )
        }
        let first = WidgetFixture.snapshot([try account(.teal, "W")])
        let renamedMark = WidgetFixture.snapshot([try account(.teal, "P")])
        let recoloured = WidgetFixture.snapshot([try account(.lime, "W")])
        #expect(!first.hasSameContent(as: renamedMark))
        #expect(first.significance != renamedMark.significance)
        #expect(first.significance != recoloured.significance)
        var policy = WidgetExportPolicy()
        policy.recordPublish(first, at: WidgetFixture.now)
        let due = WidgetFixture.now.addingTimeInterval(WidgetExportPolicy.significantGap)
        #expect(policy.decision(for: recoloured, now: due) == .publish)
        #expect(policy.decision(for: recoloured, now: WidgetFixture.now.addingTimeInterval(1)) == .wait(until: due))
    }

    @Test("A full snapshot with identity marks still fits the file the widget will read")
    func fileSize() throws {
        let windows = try (0..<WidgetAccount.maximumWindows).map {
            try WidgetFixture.item(try Fixture.window("w\($0)", .weekly(model: "Model \($0)"), used: 40, minutes: 10_080))
        }
        let accounts = try (0..<WidgetSnapshot.maximumAccounts).map { index in
            try WidgetAccount(
                id: AccountID(),
                label: String(repeating: "Ж", count: AccountLabel.maximumLength),
                provider: index.isMultiple(of: 2) ? .claude : .codex,
                tint: AccountTint.palette[index % AccountTint.palette.count],
                monogram: try AccountMonogram(validating: "ЖШ"),
                plan: String(repeating: "p", count: WidgetAccount.maximumPlanLength),
                email: String(repeating: "e", count: 40),
                windows: windows,
                capturedAt: WidgetFixture.now
            )
        }
        let data = try WidgetFixture.snapshot(accounts).encodedData()
        #expect(data.count <= WidgetSnapshot.maximumFileBytes, "\(data.count) bytes")
        #expect(WidgetSnapshot.decode(data)?.accounts.count == WidgetSnapshot.maximumAccounts)
    }

    @Test("Sample data carries identity marks, so the gallery preview looks like the real widget")
    func sampleData() {
        let sample = WidgetSampleData.snapshot(now: WidgetFixture.now, language: .en)
        #expect(sample.accounts.allSatisfy { $0.monogram != nil && $0.tint != nil })
    }
}

// MARK: - Account tints

@Suite("Widget account tints")
struct WidgetAccountTintTests {
    /// The sRGB components of a colour the widget draws, as `NSColor` resolves it.
    static func rgb(_ color: Color) -> (red: Double, green: Double, blue: Double, alpha: Double) {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? .black
        return (resolved.redComponent, resolved.greenComponent, resolved.blueComponent, resolved.alphaComponent)
    }

    /// Hue in degrees, and chroma as the plain max − min of the components.
    static func hueAndChroma(_ color: Color) -> (hue: Double, chroma: Double) {
        let c = rgb(color)
        let maximum = max(c.red, c.green, c.blue)
        let minimum = min(c.red, c.green, c.blue)
        let chroma = maximum - minimum
        guard chroma > 0 else { return (0, 0) }
        let hue: Double
        if maximum == c.red {
            hue = 60 * (((c.green - c.blue) / chroma).truncatingRemainder(dividingBy: 6) + 6)
        } else if maximum == c.green {
            hue = 60 * (2 + (c.blue - c.red) / chroma)
        } else {
            hue = 60 * (4 + (c.red - c.green) / chroma)
        }
        return (hue.truncatingRemainder(dividingBy: 360), chroma)
    }

    static func hueDistance(_ lhs: Double, _ rhs: Double) -> Double {
        let difference = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
    }

    static func luminance(_ color: Color) -> Double {
        let c = rgb(color)
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(c.red) + 0.7152 * linear(c.green) + 0.0722 * linear(c.blue)
    }

    static func contrast(_ lhs: Color, _ rhs: Color) -> Double {
        let left = luminance(lhs)
        let right = luminance(rhs)
        return (max(left, right) + 0.05) / (min(left, right) + 0.05)
    }

    /// `top` at its own alpha over an opaque `bottom`.
    static func composite(_ top: Color, over bottom: Color) -> Color {
        let over = rgb(top)
        let under = rgb(bottom)
        return Color(
            red: over.red * over.alpha + under.red * (1 - over.alpha),
            green: over.green * over.alpha + under.green * (1 - over.alpha),
            blue: over.blue * over.alpha + under.blue * (1 - over.alpha)
        )
    }

    /// Colours that already mean something: both ends of every band gradient, and the waiting violet.
    static func meaningfulColors(_ palette: WidgetPalette) -> [Color] {
        UsageBand.allCases.flatMap { WidgetPalette.bandGradient($0) } + [palette.attention]
    }

    @Test("A tint with real colour keeps 25° of hue from every band colour and from the waiting violet", arguments: [false, true])
    func hueDistance(isDark: Bool) {
        let palette = WidgetPalette(style: .fullColor, scheme: isDark ? .dark : .light)
        let taken = Self.meaningfulColors(palette).map { Self.hueAndChroma($0).hue }
        for tint in AccountTint.palette {
            let mark = Self.hueAndChroma(palette.accountTint(tint))
            guard mark.chroma >= 0.2 else { continue }
            for hue in taken {
                #expect(Self.hueDistance(mark.hue, hue) >= 25, "\(tint) at \(mark.hue)° is \(Self.hueDistance(mark.hue, hue))° from \(hue)°")
            }
        }
    }

    @Test("The quiet tints really are quiet, and every tint is its own colour", arguments: [false, true])
    func chroma(isDark: Bool) {
        let palette = WidgetPalette(style: .fullColor, scheme: isDark ? .dark : .light)
        for tint in [AccountTint.sand, .slate, .graphite] {
            #expect(Self.hueAndChroma(palette.accountTint(tint)).chroma < 0.2, "\(tint)")
        }
        let marks = AccountTint.palette.map { Self.rgb(palette.accountTint($0)) }
        for (index, mark) in marks.enumerated() {
            for other in marks[(index + 1)...] {
                let distance = abs(mark.red - other.red) + abs(mark.green - other.green) + abs(mark.blue - other.blue)
                #expect(distance > 0.12, "two tints are \(distance) apart")
            }
        }
    }

    @Test("A monogram reads at 4.5 : 1 on its own badge, over either end of the background", arguments: [false, true])
    func contrast(isDark: Bool) {
        let palette = WidgetPalette(style: .fullColor, scheme: isDark ? .dark : .light)
        for stop in WidgetBackground.gradientStops(isDark: isDark) {
            for tint in AccountTint.palette {
                let badge = Self.composite(palette.accountTintFill(tint), over: stop)
                let ratio = Self.contrast(palette.accountTint(tint), badge)
                #expect(ratio >= 4.5, "\(tint) on \(isDark ? "dark" : "light"): \(ratio)")
            }
        }
    }

    @Test("Accented and vibrant rendering give up the tint, so the system's own colours decide")
    func systemRendering() {
        // Only the monogram is accentable, so only it follows the accent colour; the square keeps the plain fill.
        let accented = WidgetPalette(style: .accented, scheme: .dark, accentPreview: Color(red: 0.45, green: 0.72, blue: 1))
        let vibrant = WidgetPalette(style: .vibrant, scheme: .dark)
        for tint in AccountTint.palette {
            #expect(accented.accountTint(tint) == accented.accent, "\(tint)")
            #expect(accented.accountTintFill(tint) == Color.primary.opacity(0.14), "\(tint)")
            #expect(vibrant.accountTint(tint) == Color.primary, "\(tint)")
            #expect(vibrant.accountTintFill(tint) == Color.primary.opacity(0.14), "\(tint)")
        }
        // The ghost arc is accentable too, so it follows the same rule.
        #expect(accented.forecast(.critical) == accented.accent.opacity(0.42))
        #expect(vibrant.forecast(.critical) == Color.primary.opacity(0.42))
    }

    @Test("A provider widget keeps its provider mark until that provider has more than one account")
    func providerHeader() throws {
        let marked = try WidgetAccount(
            id: AccountID(), label: "Claude · Work", provider: .claude, tint: .teal,
            monogram: try AccountMonogram(validating: "W")
        )
        let legacy = try WidgetAccount(id: AccountID(), label: "Claude", provider: .claude)
        #expect(!ProviderSmallView.showsAccountBadge(for: marked, providerAccounts: 1))
        #expect(ProviderSmallView.showsAccountBadge(for: marked, providerAccounts: 2))
        #expect(!ProviderSmallView.showsAccountBadge(for: legacy, providerAccounts: 3))
    }

    @Test("The badge's monogram shrinks for two characters, keeps a readable floor, and never scales to fit")
    func badgeFont() {
        #expect(WidgetAccountBadge.fontSize(side: 20, characters: 1) == 10)
        #expect(WidgetAccountBadge.fontSize(side: 20, characters: 2) == 8.4)
        #expect(WidgetAccountBadge.fontSize(side: 20, characters: 2) < WidgetAccountBadge.fontSize(side: 20, characters: 1))
        // 0.42 × 16 would be 6.7 pt, which is below the floor.
        #expect(WidgetAccountBadge.fontSize(side: 16, characters: 2) == WidgetAccountBadge.minimumTextSize)
        // A badge smaller than the floor keeps its text inside itself rather than honouring the floor.
        #expect(WidgetAccountBadge.fontSize(side: 10, characters: 2) == 6)
    }

    /// Realistic account names: the provider's own name and one ordinary word, as the app's own automatic labels and
    /// the onboarding wizard produce them.
    static func heroNames(_ language: Language) -> [String] {
        language == .en
            ? ["Claude · Work", "Codex · Personal", "Claude · Steady", "Codex · Review"]
            : ["Claude · Работа", "Codex · Личное", "Claude · Ревью", "Codex · Спринт"]
    }

    @Test("An ordinary account name still fits beside its badge on the large widget's hero", arguments: Language.allCases)
    func heroNameFit(language: Language) {
        let font = WidgetCopyFitTests.font(16, .semibold)
        for name in Self.heroNames(language) {
            #expect(
                WidgetCopyFitTests.fits(name, font, in: LargeLimitsView.heroNameWidth),
                "\(name): \(WidgetCopyFitTests.width(name, font)) pt of \(LargeLimitsView.heroNameWidth) pt"
            )
        }
        // The badge is what costs the room, so the budget has to be checked against the real column.
        #expect(LargeLimitsView.heroNameWidth == 344 - 32 - 128 - 18 - LargeLimitsView.heroBadgeSide - 5)
    }

    @Test("The widest two-character monogram fits the badges the widget draws")
    func badgeFit() {
        // The widest pairs the validator allows in each language, plus a wide Latin pair.
        let widest = ["WM", "ЖШ", "МЖ", "00"]
        for side in [LargeLimitsView.badgeSide, LargeLimitsView.badgeSide + 4, ProviderSmallView.headerHeight] {
            let font = WidgetCopyFitTests.font(WidgetAccountBadge.fontSize(side: side, characters: 2), .semibold)
            for text in widest {
                #expect(WidgetCopyFitTests.fits(text, font, in: side - 1), "\(text) at \(side) pt: \(WidgetCopyFitTests.width(text, font)) pt")
            }
        }
    }
}

// MARK: - Forecast

@Suite("Widget forecast")
struct WidgetForecastTests {
    /// A window `elapsed` of its length into a `minutes`-long window, with `used` spent.
    private func state(used: Double, minutes: Int, elapsed: Double, at date: Date = WidgetFixture.now) throws -> WidgetWindowState {
        let length = Double(minutes) * 60
        let window = try Fixture.window("session", .session, used: used, minutes: minutes, resetsIn: length * (1 - elapsed))
        return WidgetWindowState(source: try WidgetFixture.item(window), date: date, thresholds: .standard)
    }

    @Test("A window state works its forecast out at the entry's date")
    func computed() throws {
        let halfway = try state(used: 40, minutes: 300, elapsed: 0.5)
        let forecast = try #require(halfway.forecast)
        #expect(abs(forecast.projectedUsed - 80) < 0.001)
        #expect(!forecast.reachesLimit)
        #expect(forecast.band == .critical)

        let fast = try state(used: 60, minutes: 300, elapsed: 0.4)
        #expect(try #require(fast.forecast).reachesLimit)
        // Too early to tell, nothing used, and already exhausted: nothing to draw.
        #expect(try state(used: 40, minutes: 300, elapsed: 0.14).forecast == nil)
        #expect(try state(used: 0, minutes: 300, elapsed: 0.5).forecast == nil)
        #expect(try state(used: 100, minutes: 300, elapsed: 0.5).forecast == nil)
        // A gain of less than two points is not worth a ghost.
        #expect(try state(used: 98, minutes: 300, elapsed: 0.99).forecast == nil)
    }

    @Test("A window that reset since the app last read it has no forecast, because its usage is back at zero")
    func afterReset() throws {
        let window = try Fixture.window("session", .session, used: 80, minutes: 300, resetsIn: 60)
        let later = WidgetFixture.now.addingTimeInterval(2 * 3_600)
        let state = WidgetWindowState(source: try WidgetFixture.item(window), date: later, thresholds: .standard)
        #expect(state.hasResetSinceCapture)
        #expect(state.forecast == nil)
    }

    @Test("Policies: never draws nothing, warnings only a forecast that reaches the limit, always every one")
    func policies() throws {
        let calm = try state(used: 40, minutes: 300, elapsed: 0.5)
        let racing = try state(used: 60, minutes: 300, elapsed: 0.4)
        let none = try state(used: 0, minutes: 300, elapsed: 0.5)
        #expect(!WidgetForecastPolicy.never.draws(calm.forecast))
        #expect(!WidgetForecastPolicy.never.draws(racing.forecast))
        #expect(!WidgetForecastPolicy.warningsOnly.draws(calm.forecast))
        #expect(WidgetForecastPolicy.warningsOnly.draws(racing.forecast))
        #expect(WidgetForecastPolicy.always.draws(calm.forecast))
        #expect(WidgetForecastPolicy.always.draws(racing.forecast))
        #expect(WidgetForecastPolicy.always.draws(none.forecast) == false)
    }

    @Test("The ghost starts past the used arc and never closes the circle")
    func arcEnd() throws {
        let calm = try state(used: 40, minutes: 300, elapsed: 0.5)
        let end = try #require(WidgetForecastPolicy.always.arcEnd(for: calm))
        #expect(abs(end - 0.8) < 0.001)
        #expect(end > calm.progress.used)
        #expect(WidgetForecastPolicy.never.arcEnd(for: calm) == nil)
        #expect(WidgetForecastPolicy.warningsOnly.arcEnd(for: calm) == nil)

        let racing = try state(used: 60, minutes: 300, elapsed: 0.4)
        let capped = try #require(WidgetForecastPolicy.always.arcEnd(for: racing))
        #expect(capped == WidgetForecastPolicy.maximumArcEnd)
        #expect(capped < 1)
    }

    @Test("Small widgets warn only; medium and large draw every forecast")
    func viewPolicies() {
        #expect(SmallLimitsView.forecastPolicy == .warningsOnly)
        #expect(ProviderSmallView.forecastPolicy == .warningsOnly)
        #expect(MediumLimitsView.forecastPolicy == .always)
        #expect(LargeLimitsView.forecastPolicy == .always)
    }

    @Test("The snapshot carries the user's forecast setting, leniently")
    func settingCoding() throws {
        let account = try WidgetFixture.account(windows: [try Fixture.window("session", .session, used: 40)])
        for wanted in [true, false] {
            let data = try WidgetFixture.snapshot([account], showsForecast: wanted).encodedData()
            #expect(try #require(WidgetSnapshot.decode(data)).showsForecast == wanted)
        }
        // A file from before the key existed, and a file whose value is not a boolean, keep the setting's default.
        func decoded(_ fields: String) throws -> WidgetSnapshot {
            try #require(WidgetSnapshot.decode(Data("{\"accounts\": []\(fields)}".utf8)))
        }
        #expect(try decoded("").showsForecast)
        #expect(try decoded(#", "showsForecast": "no""#).showsForecast)
        #expect(try decoded(#", "showsForecast": false"#).showsForecast == false)
    }

    @Test("Turning the forecast off reaches the widget as a significant change")
    func settingSignificance() throws {
        let account = try WidgetFixture.account(windows: [try Fixture.window("session", .session, used: 40)])
        let on = WidgetFixture.snapshot([account])
        let off = WidgetFixture.snapshot([account], showsForecast: false)
        #expect(!on.hasSameContent(as: off))
        #expect(on.significance != off.significance)
        var policy = WidgetExportPolicy()
        policy.recordPublish(on, at: WidgetFixture.now)
        let due = WidgetFixture.now.addingTimeInterval(WidgetExportPolicy.significantGap)
        #expect(policy.decision(for: off, now: due) == .publish)
        #expect(policy.decision(for: off, now: WidgetFixture.now.addingTimeInterval(1)) == .wait(until: due))
    }

    @Test("With the setting off no ring has a ghost, whatever its family's policy would draw")
    func settingHidesEveryGhost() throws {
        // Both windows would forecast: one calmly, one into the limit.
        let windows = [
            try Fixture.window("session", .session, used: 40, minutes: 300, resetsIn: 150 * 60),
            try Fixture.window("week", .weekly(model: nil), used: 60, minutes: 300, resetsIn: 180 * 60),
        ]
        let account = try WidgetFixture.account(windows: windows)
        let on = WidgetFixture.snapshot([account]).states(at: WidgetFixture.now)
        #expect(on[0].windows.allSatisfy { $0.forecast != nil })
        #expect(on[0].windows.contains { WidgetForecastPolicy.warningsOnly.arcEnd(for: $0) != nil })

        let off = WidgetFixture.snapshot([account], showsForecast: false).states(at: WidgetFixture.now)
        #expect(off[0].windows.allSatisfy { $0.forecast == nil })
        for window in off[0].windows {
            for policy in WidgetForecastPolicy.allCases {
                #expect(policy.arcEnd(for: window) == nil, "\(policy)")
                #expect(!policy.draws(window.forecast), "\(policy)")
            }
        }
        // Bands, percentages and countdowns are untouched: only the ghost goes.
        #expect(off[0].windows.map(\.band) == on[0].windows.map(\.band))
        #expect(off[0].windows.map(\.progress.used) == on[0].windows.map(\.progress.used))
    }

    @Test("The builder takes the setting from the user's appearance settings", arguments: [true, false])
    func settingFromBuilder(wanted: Bool) throws {
        let profile = try AccountProfile(
            provider: .claude,
            label: try AccountLabel(validating: "Claude"),
            directory: try ProfileDirectory(validating: "/tmp/.claude-forecast")
        )
        let settings = try WidgetFixture.settings([profile], showsForecast: wanted)
        let state = TrackerState(accounts: [AccountStatus(profile: profile)])
        let snapshot = WidgetSnapshot.make(state: state, settings: settings, now: WidgetFixture.now, language: .en)
        #expect(snapshot.showsForecast == wanted)
    }

    @Test("VoiceOver says what the ghost shows, and stays quiet when nothing is drawn", arguments: Language.allCases)
    func spoken(language: Language) {
        let l10n = language == .en ? Localizer.testEnglish : .testRussian
        let widget = l10n.widget
        let used = l10n.format.percent(40)
        switch language {
        case .en:
            #expect(widget.percentUsedA11y(used) == "40% used")
            #expect(widget.percentUsedForecastA11y(used, projected: l10n.format.percent(80)) == "40% used, at this pace about 80% by reset")
            #expect(widget.percentUsedForecastLimitA11y(used) == "40% used, at this pace it runs out before the reset")
        case .ru:
            #expect(widget.percentUsedA11y(used) == "использовано 40\u{00A0}%")
            #expect(
                widget.percentUsedForecastA11y(used, projected: l10n.format.percent(80))
                    == "использовано 40\u{00A0}%, при таком темпе к сбросу около 80\u{00A0}%"
            )
            #expect(widget.percentUsedForecastLimitA11y(used) == "использовано 40\u{00A0}%, при таком темпе лимит кончится до сброса")
        }
    }
}

// MARK: - Notices

@Suite("Widget notice fit")
struct WidgetNoticeFitTests {
    /// Usage numbers are drawn at their own size, never squeezed (`PercentText`), so the widest one has to fit the
    /// room its view gives it outright.
    @Test("The widest percentage fits every size the widget draws it at")
    func percentages() {
        let widest = WidgetText.percent(.full)
        #expect(widest == "100%")
        func width(_ size: CGFloat) -> CGFloat {
            // The number in monospaced digits, then the sign at half the size.
            WidgetCopyFitTests.width("100", WidgetCopyFitTests.font(size, .bold, digits: true))
                + WidgetCopyFitTests.width("%", WidgetCopyFitTests.font(size * 0.5, .bold))
        }
        // Small: the headline beside nothing else.
        #expect(width(38) <= WidgetCopyFitTests.smallWidth)
        // Provider small: beside a 62 pt ring with 6 pt of spacing. `FittingPercentText` steps down through
        // 40/34/28/22, so its smallest step must fit — otherwise `ViewThatFits` has nothing to choose.
        #expect(width(22) <= WidgetCopyFitTests.smallWidth - ProviderSmallView.ringSide - 6)
        // Medium, one account: inside a 112 pt ring.
        #expect(width(28) <= 112 - 2 * 9)
        // Medium column: inside a 72 pt ring.
        #expect(width(17) <= 72 - 2 * 7)
        // Large, one account: inside a 128 pt ring.
        #expect(width(32) <= 128 - 2 * 11)
        // Large list row: beside a 38 pt ring, leaving at least 120 pt for the label column.
        #expect(WidgetCopyFitTests.mediumWidth - 38 - 16 - width(19) >= 120)
    }

    @Test("Every notice fits the small widget's status line in both languages", arguments: Language.allCases)
    func notices(language: Language) {
        let l10n = language == .en ? Localizer.testEnglish : .testRussian
        let room = WidgetCopyFitTests.smallWidth - WidgetCopyFitTests.symbolRoom
        let font = WidgetCopyFitTests.font(11.5, .medium, digits: true)
        for kind in TrackerIssue.Kind.allCases {
            let notice = WidgetText.notice(for: kind, l10n: l10n)
            #expect(
                WidgetCopyFitTests.fits(notice, font, in: room, scale: WidgetCopyFitTests.statusScale),
                "\(notice): \(WidgetCopyFitTests.width(notice, font)) pt"
            )
        }
    }
}

// MARK: - Rendering

/// Renders all three widget families to PNG for visual review, in English and Russian (`…-en.png`, `…-ru.png`).
/// Runs only when `CODOMETER_SNAPSHOT_DIR` is set, e.g.
/// `CODOMETER_SNAPSHOT_DIR=/tmp/shots Scripts/test.sh --filter WidgetRender`.
@MainActor
@Suite("WidgetRender", .enabled(if: ProcessInfo.processInfo.environment["CODOMETER_SNAPSHOT_DIR"] != nil))
struct WidgetRenderTests {
    private let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODOMETER_SNAPSHOT_DIR"] ?? "/tmp", isDirectory: true)

    private enum Look: String, CaseIterable {
        case light, dark, accented, vibrant

        var scheme: ColorScheme { self == .light ? .light : .dark }
        var style: WidgetStyle {
            switch self {
            case .light, .dark: .fullColor
            case .accented: .accented
            case .vibrant: .vibrant
            }
        }
    }

    /// Fixed language, region, clock and time zone, so the images do not depend on this Mac's settings.
    private static func localizer(_ language: Language) -> Localizer {
        language == .en ? .testEnglish : .testRussian
    }

    @Test("Small, medium and large in light, dark, accented and vibrant rendering", arguments: Language.allCases)
    func renderFamilies(language: Language) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let now = Date()
        let scenarios: [(String, WidgetSnapshot?)] = [
            ("two", try twoAccounts(now: now, language: language)),
            ("blocked", try blocked(now: now, language: language)),
            ("soon", try soon(now: now, language: language)),
            ("many", try manyAccounts(now: now, language: language)),
            ("stale", try stale(now: now, age: 47 * 60, language: language)),
            ("old", try stale(now: now, age: 3 * 86_400, language: language)),
            ("single", try single(now: now, language: language)),
            ("working", try working(now: now, language: language)),
            ("empty", nil),
        ]
        for (scenario, snapshot) in scenarios {
            let entry = LimitsEntry(date: now, snapshot: snapshot)
            for (family, familyName, size) in Self.families {
                let looks: [Look] = scenario == "two" ? Look.allCases : [.light, .dark]
                for look in looks {
                    try render(entry: entry, language: language, family: family, size: size, look: look, name: "widget-\(scenario)-\(familyName)-\(look.rawValue)")
                }
            }
        }
    }

    /// The sizes chronod asks for on this Mac's desktop (logged as `164.00/164.00/27.88`).
    private static let families: [(WidgetFamily, String, CGSize)] = [
        (.systemSmall, "small", CGSize(width: 164, height: 164)),
        (.systemMedium, "medium", CGSize(width: 344, height: 164)),
        (.systemLarge, "large", CGSize(width: 344, height: 344)),
    ]

    @Test("Claude and Codex widgets, small and medium, in every rendering", arguments: Language.allCases)
    func renderProviders(language: Language) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let now = Date()
        let many = try manyAccounts(now: now, language: language)
        let scenarios: [(String, WidgetScope, WidgetSnapshot?, [Look])] = [
            ("claude", .provider(.claude), try twoAccounts(now: now, language: language), Look.allCases),
            ("codex", .provider(.codex), try twoAccounts(now: now, language: language), Look.allCases),
            ("claude-blocked", .provider(.claude), try blocked(now: now, language: language), [.light, .dark]),
            ("claude-soon", .provider(.claude), try soon(now: now, language: language), [.light, .dark]),
            ("claude-stale", .provider(.claude), try stale(now: now, age: 47 * 60, language: language), [.light, .dark]),
            ("claude-many", .provider(.claude), many, [.light, .dark]),
            ("codex-many", .provider(.codex), many, [.light, .dark]),
            ("codex-blocked-many", .provider(.codex), try blockedCodexColumns(now: now, language: language), [.light, .dark]),
            ("codex-signedout", .provider(.codex), try signedOutCodex(now: now, language: language), [.light, .dark]),
            ("codex-none", .provider(.codex), try single(now: now, language: language), [.light, .dark, .accented]),
            ("claude-nodata", .provider(.claude), nil, [.light, .dark]),
        ]
        for (scenario, scope, snapshot, looks) in scenarios {
            let entry = LimitsProviderEntryFixture.entry(snapshot: snapshot, scope: scope, now: now)
            for (family, familyName, size) in Self.families where family != .systemLarge {
                for look in looks {
                    try render(entry: entry, language: language, family: family, size: size, look: look, name: "provider-\(scenario)-\(familyName)-\(look.rawValue)")
                }
            }
        }
    }

    /// The strip layout: medium and large of all three kinds. The small widget keeps its ring whatever the layout.
    @Test("The strip layout, medium and large, for AI Limits, Claude and Codex", arguments: Language.allCases)
    func renderStrip(language: Language) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let now = Date()
        let many = WidgetFixture.strip(try manyAccounts(now: now, language: language))
        let two = WidgetFixture.strip(try twoAccounts(now: now, language: language))
        let scenarios: [(String, WidgetScope, WidgetSnapshot, [Look])] = [
            ("two", .all, two, Look.allCases),
            ("single", .all, WidgetFixture.strip(try single(now: now, language: language)), [.light, .dark]),
            ("many", .all, many, [.light, .dark]),
            ("blocked", .all, WidgetFixture.strip(try blocked(now: now, language: language)), [.light, .dark]),
            ("soon", .all, WidgetFixture.strip(try soon(now: now, language: language)), [.light, .dark]),
            ("stale", .all, WidgetFixture.strip(try stale(now: now, age: 47 * 60, language: language)), [.light, .dark]),
            ("working", .all, WidgetFixture.strip(try working(now: now, language: language)), [.light, .dark]),
            ("claude", .provider(.claude), two, Look.allCases),
            ("codex", .provider(.codex), two, Look.allCases),
            ("claude-many", .provider(.claude), many, [.light, .dark]),
            ("codex-many", .provider(.codex), many, [.light, .dark]),
            ("codex-blocked-many", .provider(.codex), WidgetFixture.strip(try blockedCodexColumns(now: now, language: language)), [.light, .dark]),
            ("codex-signedout", .provider(.codex), WidgetFixture.strip(try signedOutCodex(now: now, language: language)), [.light, .dark]),
            ("small-keeps-ring", .all, two, [.dark]),
        ]
        for (scenario, scope, snapshot, looks) in scenarios {
            let entry = LimitsProviderEntryFixture.entry(snapshot: snapshot, scope: scope, now: now)
            for (family, familyName, size) in Self.families where (family != .systemSmall) == (scenario != "small-keeps-ring") {
                for look in looks {
                    try render(entry: entry, language: language, family: family, size: size, look: look, name: "strip-\(scenario)-\(familyName)-\(look.rawValue)")
                }
            }
        }
    }

    private func render(entry: LimitsEntry, language: Language, family: WidgetFamily, size: CGSize, look: Look, name: String) throws {
        let l10n = Self.localizer(language)
        let palette = WidgetPalette(
            style: look.style,
            scheme: look.scheme,
            accentPreview: look == .accented ? Color(red: 0.45, green: 0.72, blue: 1.0) : nil
        )
        let content = LimitsWidgetContent(entry: entry, family: family, palette: palette)
            .padding(16)
            .frame(width: size.width, height: size.height)
            .background { background(for: look, entry: entry) }
            .clipShape(RoundedRectangle(cornerRadius: 27.88, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 27.88, style: .continuous)
                    .strokeBorder(Color.white.opacity(look == .light ? 0.5 : 0.12), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
            .padding(28)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.36, green: 0.42, blue: 0.62), Color(red: 0.62, green: 0.45, blue: 0.58), Color(red: 0.93, green: 0.66, blue: 0.52)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .environment(\.colorScheme, look.scheme)
            .environment(\.widgetL10n, l10n)
            .environment(\.locale, l10n.locale)
            .environment(\.timeZone, l10n.calendar.timeZone)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("\(name)-\(language.rawValue).png"))
    }

    @ViewBuilder
    private func background(for look: Look, entry: LimitsEntry) -> some View {
        switch look {
        case .light, .dark:
            WidgetBackground(urgency: entry.urgency, hasAttention: entry.hasAttention, scheme: look.scheme)
        case .accented:
            LinearGradient(colors: [Color(red: 0.10, green: 0.16, blue: 0.30), Color(red: 0.06, green: 0.09, blue: 0.18)], startPoint: .top, endPoint: .bottom)
        case .vibrant:
            Color(white: 0.26).opacity(0.92)
        }
    }

    // MARK: Scenarios

    private func limit(_ id: String, _ scope: LimitWindowScope, _ used: Double, minutes: Int?, resetsIn: TimeInterval?, now: Date, label: String? = nil) throws -> LimitWindow {
        try LimitWindow(
            id: id,
            scope: scope,
            used: try Percentage(validating: used),
            duration: try minutes.map { try WindowDuration(minutes: $0) },
            resetsAt: resetsIn.map { now.addingTimeInterval($0) },
            label: label
        )
    }

    private func claude(
        now: Date,
        language: Language,
        session: Double,
        week: Double,
        fable: Double,
        sessionResetsIn: TimeInterval = 2 * 3_600 + 14 * 60,
        weekResetsIn: TimeInterval = 4 * 86_400 + 5 * 3_600,
        waiting: Int = 0,
        capturedAt: Date? = nil,
        label: String = "Claude",
        email: String? = "e••••e@test.com"
    ) throws -> WidgetAccount {
        let windows = [
            try WidgetWindow(bucketID: "claude", isMainBucket: true, window: try limit("session", .session, session, minutes: 300, resetsIn: sessionResetsIn, now: now), language: language),
            try WidgetWindow(bucketID: "claude", isMainBucket: true, window: try limit("week", .weekly(model: nil), week, minutes: 10_080, resetsIn: weekResetsIn, now: now), language: language),
            try WidgetWindow(bucketID: "claude", isMainBucket: true, window: try limit("week.fable", .weekly(model: "Fable"), fable, minutes: 10_080, resetsIn: weekResetsIn, now: now), language: language),
        ]
        return try WidgetAccount(
            id: AccountID(),
            label: label,
            provider: .claude,
            plan: "Max",
            email: email,
            windows: windows,
            capturedAt: capturedAt ?? now.addingTimeInterval(-90),
            waitingCount: waiting
        )
    }

    private func codex(
        now: Date,
        language: Language,
        primary: Double,
        secondary: Double,
        primaryResetsIn: TimeInterval = 3 * 3_600 + 40 * 60,
        label: String = "Codex",
        working: Int = 0
    ) throws -> WidgetAccount {
        let windows = [
            try WidgetWindow(bucketID: "codex", isMainBucket: true, window: try limit("primary", .rolling, primary, minutes: 300, resetsIn: primaryResetsIn, now: now), language: language),
            try WidgetWindow(bucketID: "codex", isMainBucket: true, window: try limit("secondary", .rolling, secondary, minutes: 10_080, resetsIn: 2 * 86_400, now: now), language: language),
            try WidgetWindow(bucketID: "codex_spark", bucketTitle: "GPT-5.3-Codex-Spark", isMainBucket: false, window: try limit("primary", .rolling, 12, minutes: 300, resetsIn: 3 * 3_600, now: now), language: language),
        ]
        return try WidgetAccount(id: AccountID(), label: label, provider: .codex, plan: "Pro", windows: windows, capturedAt: now.addingTimeInterval(-40), workingCount: working)
    }

    private func signedOut(_ label: String, language: Language) throws -> WidgetAccount {
        try WidgetAccount(id: AccountID(), label: label, provider: .codex, notice: WidgetText.notice(for: .signedOut, l10n: Self.localizer(language)))
    }

    private func twoAccounts(now: Date, language: Language) throws -> WidgetSnapshot {
        WidgetFixture.snapshot([
            try claude(now: now, language: language, session: 57, week: 38, fable: 63, waiting: 1),
            try codex(now: now, language: language, primary: 18, secondary: 84, working: 1),
        ], at: now, language: language)
    }

    /// The weekly limit reached for almost a week: the widest countdown in both languages.
    private func blocked(now: Date, language: Language) throws -> WidgetSnapshot {
        WidgetFixture.snapshot([
            try claude(now: now, language: language, session: 71, week: 100, fable: 92, weekResetsIn: 6 * 86_400 + 22 * 3_600 + 50 * 60),
            try codex(now: now, language: language, primary: 22, secondary: 35),
        ], at: now, language: language)
    }

    /// A blocked session that resets within the hour, and a waiting account.
    private func soon(now: Date, language: Language) throws -> WidgetSnapshot {
        WidgetFixture.snapshot([
            try claude(now: now, language: language, session: 100, week: 64, fable: 30, sessionResetsIn: 47 * 60 + 20, waiting: 1),
            try codex(now: now, language: language, primary: 22, secondary: 35),
        ], at: now, language: language)
    }

    private func manyAccounts(now: Date, language: Language) throws -> WidgetSnapshot {
        let work = language == .en ? "Work" : "Работа"
        let personal = language == .en ? "Personal" : "Личное"
        return WidgetFixture.snapshot([
            try claude(now: now, language: language, session: 34, week: 21, fable: 40, label: "Claude · \(work)"),
            try claude(now: now, language: language, session: 81, week: 55, fable: 12, sessionResetsIn: 4 * 3_600 + 58 * 60, waiting: 2, label: "Claude · \(personal)", email: nil),
            try codex(now: now, language: language, primary: 9, secondary: 47, label: "Codex · \(work)"),
            try codex(now: now, language: language, primary: 66, secondary: 72, label: "Codex · \(personal)"),
            try signedOut(language == .en ? "Codex · Test" : "Codex · Тест", language: language),
            try codex(now: now, language: language, primary: 3, secondary: 5, label: language == .en ? "Codex · Spare" : "Codex · Ещё"),
        ], at: now, language: language)
    }

    /// Three Codex columns, two of them blocked for most of a day: the narrowest "Back in" lines.
    private func blockedCodexColumns(now: Date, language: Language) throws -> WidgetSnapshot {
        let work = language == .en ? "Work" : "Работа"
        let personal = language == .en ? "Personal" : "Личное"
        return WidgetFixture.snapshot([
            try codex(now: now, language: language, primary: 100, secondary: 47, primaryResetsIn: 4 * 3_600 + 58 * 60, label: "Codex · \(work)"),
            try codex(now: now, language: language, primary: 100, secondary: 72, primaryResetsIn: 4 * 3_600 + 59 * 60, label: "Codex · \(personal)"),
            try codex(now: now, language: language, primary: 12, secondary: 100, label: "Codex"),
        ], at: now, language: language)
    }

    private func stale(now: Date, age: TimeInterval, language: Language) throws -> WidgetSnapshot {
        WidgetFixture.snapshot([
            try claude(now: now, language: language, session: 64, week: 31, fable: 20, capturedAt: now.addingTimeInterval(-age)),
            try codex(now: now, language: language, primary: 40, secondary: 12),
        ], at: now, language: language)
    }

    private func single(now: Date, language: Language) throws -> WidgetSnapshot {
        WidgetFixture.snapshot([try claude(now: now, language: language, session: 42, week: 38, fable: 63)], at: now, language: language)
    }

    /// More accounts than the large widget holds, with agents working: the footer and the working count.
    private func working(now: Date, language: Language) throws -> WidgetSnapshot {
        let many = try manyAccounts(now: now, language: language)
        let extra = try (1...4).map { index in
            try codex(now: now, language: language, primary: Double(10 * index), secondary: 20, label: "Codex \(index)", working: index)
        }
        return WidgetFixture.snapshot(many.accounts + extra, at: now, language: language)
    }

    private func signedOutCodex(now: Date, language: Language) throws -> WidgetSnapshot {
        WidgetFixture.snapshot([
            try claude(now: now, language: language, session: 42, week: 38, fable: 63),
            try signedOut("Codex", language: language),
        ], at: now, language: language)
    }
}

/// Scopes a render scenario the way the timeline provider does.
private enum LimitsProviderEntryFixture {
    static func entry(snapshot: WidgetSnapshot?, scope: WidgetScope, now: Date) -> LimitsEntry {
        LimitsEntry(date: now, snapshot: snapshot?.scoped(to: scope), scope: scope)
    }
}
