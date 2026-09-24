import CodometerCore
@testable import CodometerEngine
import CodometerPlatform
import CodometerStorage
import Foundation
import Synchronization
import Testing

/// A multiple of five minutes, so token buckets line up with the minutes used below.
private let base = Date(timeIntervalSince1970: 1_789_599_900)

private func at(_ minutes: Double) -> Date {
    base.addingTimeInterval(minutes * 60)
}

/// A clock tests move by hand.
private final class TestClock: Sendable {
    private let current = Mutex(base)

    var now: Date { current.withLock { $0 } }

    func set(_ minutes: Double) {
        current.withLock { $0 = at(minutes) }
    }
}

/// A monitor that reports nothing by itself; tests feed the engine events directly.
private actor SilentMonitor: AccountMonitor {
    let profile: AccountProfile

    init(profile: AccountProfile) {
        self.profile = profile
    }

    func start() async {}
    func stop() {}
    func refreshNow() {}
    func setPaused(_ paused: Bool) {}
    func diagnostics() -> AccountDiagnostics { .empty(accountID: profile.id, provider: profile.provider) }
    func setEnergyFactor(_ factor: EnergyFactor) {}
}

/// An engine over a real temporary database, with silent monitors and a hand-moved clock.
private struct Harness {
    let directory: TemporaryDirectory
    let store: UsageHistoryStore
    let clock = TestClock()
    let engine: TrackerEngine
    let account: AccountProfile

    init(provider: ProviderKind = .claude, directory: TemporaryDirectory? = nil, account: AccountProfile? = nil) throws {
        let directory = try directory ?? TemporaryDirectory()
        self.directory = directory
        store = try UsageHistoryStore(databaseURL: directory.url.appendingPathComponent("history.sqlite"))
        self.account = try account ?? AccountProfile(
            provider: provider,
            label: try AccountLabel(validating: "Тест"),
            directory: try ProfileDirectory(validating: directory.url.appendingPathComponent(".profile").path)
        )
        let live = EngineDependencies.live(
            homeDirectory: directory.url,
            directories: AppDirectories(root: directory.url),
            history: store
        )
        let clock = clock
        let dependencies = EngineDependencies(
            homeDirectory: directory.url,
            history: store,
            network: live.network,
            ownProcesses: live.ownProcesses,
            claudeProbe: live.claudeProbe,
            codexProbe: live.codexProbe,
            now: { clock.now }
        )
        engine = TrackerEngine(dependencies: dependencies, historyCoalescing: .zero, monitorFactory: { profile, _ in SilentMonitor(profile: profile) })
    }

    var accountID: AccountID { account.id }

    func start(accounts: [AccountProfile]? = nil) async throws {
        await engine.start(settings: try AppSettings(accounts: accounts ?? [account]))
    }

    func sessions(_ sessions: [AgentSession], at minutes: Double) async {
        clock.set(minutes)
        await engine.handle(.sessions(accountID, sessions))
    }

    func segments(_ from: Double = -600, _ to: Double = 600) async throws -> [SessionSegment] {
        await engine.flushHistory()
        return try await store.segments(accountID: accountID, interval: DateInterval(start: at(from), end: at(to)))
    }
}

private func session(_ id: String, _ activity: AgentActivity, since minutes: Double, project: String = "/Users/me/app") throws -> AgentSession {
    try AgentSession(
        id: id, title: "Сессия \(id)", projectPath: project, activity: activity, detail: nil,
        activitySince: at(minutes), processID: nil
    )
}

private func claudeReading(used: Double, at minutes: Double, resetsAt resetMinutes: Double = 300) throws -> UsageReading {
    let session = try LimitWindow(
        id: "session",
        scope: .session,
        used: try Percentage(validating: used),
        duration: .fiveHours,
        resetsAt: at(resetMinutes)
    )
    let week = try LimitWindow(
        id: "week",
        scope: .weekly(model: nil),
        used: try Percentage(validating: 12),
        duration: .oneWeek,
        resetsAt: at(5_000)
    )
    return try UsageReading(
        capturedAt: at(minutes),
        source: .claudeUsageCommand,
        buckets: [try LimitBucket(id: "claude", title: nil, windows: [session, week], isLimitReached: false)],
        credits: nil
    )
}

private func tokens(_ sessionID: String, account: AccountID, project: String?, at minutes: Double, input: Int64, output: Int64 = 0) throws -> TokenSample {
    try TokenSample(
        accountID: account,
        sessionID: sessionID,
        project: project,
        model: "claude-fable-5",
        at: at(minutes),
        delta: try TokenCounts(input: input, cachedInput: 0, cacheWrite: 0, output: output, reasoningOutput: 0)
    )
}

@Suite("Engine history recording")
struct EngineHistoryTests {
    @Test("Session transitions become stored segments and the timeline returns them")
    func segmentsThroughEngine() async throws {
        let harness = try Harness()
        harness.clock.set(0)
        try await harness.start()

        await harness.sessions([try session("s1", .working, since: -30), try session("s2", .idle, since: -5)], at: 1)
        await harness.sessions([try session("s1", .waiting, since: 4), try session("s2", .working, since: 5)], at: 5)
        await harness.sessions([try session("s1", .working, since: 9), try session("s2", .working, since: 5)], at: 9)
        await harness.sessions([try session("s2", .idle, since: 20)], at: 21)

        let stored = try await harness.segments()
        #expect(stored.map { "\($0.sessionID):\($0.activity.rawValue)" } == ["s1:working", "s1:waiting", "s2:working", "s1:working"])
        // Collection is live: s1's work that began before the monitor started counts from the monitor's start.
        #expect(stored.map(\.start) == [at(0), at(4), at(5), at(9)])
        #expect(stored.map(\.end) == [at(4), at(9), at(20), at(21)])
        // Labelled by project folder and id, never by the session's own title.
        #expect(stored.first?.title == "app · s1")
        #expect(stored.first?.project == "app")

        let timeline = await harness.engine.timeline(accountID: harness.accountID, interval: DateInterval(start: at(-60), end: at(30)))
        #expect(timeline.segments.map(\.id) == stored.map(\.id))
        #expect(timeline.coverageStart == at(0))
        #expect(timeline.usage == nil)

        let later = await harness.engine.timeline(accountID: harness.accountID, interval: DateInterval(start: at(6), end: at(30)))
        #expect(later.segments.map(\.sessionID) == ["s1", "s2", "s1"])
        #expect(later.coverageStart == at(6))
        await harness.engine.stop()
    }

    @Test("Status flapping within 3 s extends the segment instead of fragmenting it")
    func shortGapThroughEngine() async throws {
        let harness = try Harness()
        try await harness.start()
        await harness.sessions([try session("s1", .working, since: 1)], at: 1)
        await harness.sessions([try session("s1", .idle, since: 2)], at: 2)
        await harness.sessions([try session("s1", .working, since: 2 + 2.0 / 60)], at: 2 + 2.0 / 60)
        await harness.sessions([try session("s1", .idle, since: 3)], at: 3)

        let stored = try await harness.segments()
        #expect(stored.count == 1)
        #expect(stored.first?.start == at(1))
        #expect(stored.first?.end == at(3))
        await harness.engine.stop()
    }

    @Test("Pausing closes open segments now, resuming reopens active sessions from the wake time, stopping closes all")
    func pauseAndStop() async throws {
        let harness = try Harness()
        try await harness.start()
        await harness.sessions([try session("s1", .working, since: 1)], at: 1)

        harness.clock.set(10)
        await harness.engine.setPaused(true)
        // Changes while paused update the state but record nothing.
        await harness.sessions([try session("s1", .waiting, since: 20)], at: 20)
        #expect(try await harness.segments().map(\.end) == [at(10)])

        harness.clock.set(30)
        await harness.engine.setPaused(false)
        var stored = try await harness.segments()
        #expect(stored.map(\.activity) == [.working, .waiting])
        #expect(stored.last?.start == at(30))
        #expect(stored.last?.isOpen == true)

        harness.clock.set(45)
        await harness.engine.stop()
        stored = try await harness.store.segments(accountID: harness.accountID, interval: DateInterval(start: at(0), end: at(60)))
        #expect(stored.map(\.end) == [at(10), at(45)])
    }

    @Test("Segments a previous run left open are closed at their last seen time on start")
    func danglingOnStart() async throws {
        let directory = try TemporaryDirectory()
        let account: AccountProfile
        do {
            // The previous run crashed while a segment was open, last seen 12 minutes before this run starts.
            let previous = try Harness(directory: directory)
            account = previous.account
            let segment = try SessionSegment(
                accountID: account.id, sessionID: "crashed", title: nil, project: nil,
                activity: .waiting, start: at(-30), end: nil
            )
            try await previous.store.openSegment(segment, lastSeen: at(-30))
            try await previous.store.touchOpenSegments(at: at(-12))
        }
        let harness = try Harness(directory: directory, account: account)
        harness.clock.set(0)
        try await harness.start()
        let stored = try await harness.segments()
        #expect(stored.map(\.sessionID) == ["crashed"])
        #expect(stored.map(\.end) == [at(-12)])
        await harness.engine.stop()
        // Stopping does not move a segment that was already closed.
        #expect(try await harness.segments().map(\.end) == [at(-12)])
    }

    @Test("A running account's open segment is touched at most once a minute through events")
    func touchThroughEvents() async throws {
        let harness = try Harness()
        try await harness.start()
        await harness.sessions([try session("s1", .working, since: 0)], at: 0)
        harness.clock.set(0.5)
        await harness.engine.handle(.refreshStarted(harness.accountID))
        harness.clock.set(2)
        await harness.engine.handle(.refreshFinished(harness.accountID, nextRefreshAt: at(5)))
        await harness.engine.flushHistory()

        // A crash now would close the segment where it was last touched.
        #expect(try await harness.store.closeDanglingSegments() == 1)
        let stored = try await harness.store.segments(accountID: harness.accountID, interval: DateInterval(start: at(0), end: at(10)))
        #expect(stored.map(\.end) == [at(2)])
        await harness.engine.stop()
    }

    @Test("Removing an account from settings deletes its segments and token usage")
    func removal() async throws {
        let harness = try Harness()
        let other = try AccountProfile(
            provider: .codex,
            label: try AccountLabel(validating: "Другой"),
            directory: try ProfileDirectory(validating: harness.directory.url.appendingPathComponent(".codex").path)
        )
        try await harness.start(accounts: [harness.account, other])
        await harness.sessions([try session("s1", .working, since: 0)], at: 0)
        await harness.engine.handle(.tokenUsage(harness.accountID, [
            try tokens("s1", account: harness.accountID, project: "/Users/me/app", at: 0, input: 10),
        ]))
        await harness.engine.flushHistory()
        // Both accounts have a collection start; only the first one has segments and tokens.
        #expect(try await harness.store.accountIDs() == [harness.accountID, other.id])
        let range = DateInterval(start: at(-10), end: at(10))
        #expect(try await harness.store.segments(accountID: harness.accountID, interval: range).count == 1)

        await harness.engine.apply(settings: try AppSettings(accounts: [other]))
        await harness.engine.flushHistory()
        #expect(try await harness.store.accountIDs() == [other.id])
        #expect(try await harness.store.segments(accountID: harness.accountID, interval: range).isEmpty)
        #expect(try await harness.store.tokenSamples(accountID: harness.accountID, interval: range).isEmpty)
        await harness.engine.stop()
    }

    @Test("A pause shorter than the resume gap does not split an ongoing segment")
    func briefPause() async throws {
        let harness = try Harness()
        harness.clock.set(0)
        try await harness.start()
        await harness.sessions([try session("s1", .working, since: 1)], at: 1)
        harness.clock.set(5)
        await harness.engine.setPaused(true)
        harness.clock.set(5 + 2.0 / 60)
        await harness.engine.setPaused(false)
        let stored = try await harness.segments()
        #expect(stored.count == 1)
        #expect(stored.first?.start == at(1))
        #expect(stored.first?.isOpen == true)
        await harness.engine.stop()
    }

    @Test("On start, stored data of accounts no longer in settings is deleted")
    func removalOnStart() async throws {
        let harness = try Harness()
        let stale = AccountID()
        let old = try SessionSegment(
            accountID: stale, sessionID: "old", title: nil, project: nil, activity: .working, start: at(-50), end: nil
        )
        try await harness.store.closeSegment(old, at: at(-40))
        try await harness.store.addTokenSamples([try tokens("old", account: stale, project: nil, at: -45, input: 3)])
        try await harness.store.beginCollection(accountID: stale, at: at(-60))
        #expect(try await harness.store.accountIDs() == [stale])

        try await harness.start()
        await harness.engine.flushHistory()
        #expect(try await harness.store.accountIDs() == [harness.accountID])
        await harness.engine.stop()
    }

    @Test("Coverage counts from the first collection start and survives restarts, so quiet stretches are not «no data»")
    func coverageAcrossRestarts() async throws {
        let directory = try TemporaryDirectory()
        let account: AccountProfile
        do {
            let first = try Harness(directory: directory)
            account = first.account
            first.clock.set(0)
            try await first.start()
            await first.engine.stop()
        }
        let harness = try Harness(directory: directory, account: account)
        harness.clock.set(600)
        try await harness.start()
        await harness.sessions([try session("s1", .working, since: 700)], at: 700)

        // Collection began before this range; its first segment starts much later but nothing is missing.
        let recent = await harness.engine.timeline(accountID: harness.accountID, interval: DateInterval(start: at(300), end: at(900)))
        #expect(recent.segments.map(\.start) == [at(700)])
        #expect(recent.coverageStart == at(300))
        // A range reaching back before collection began is covered from the first start, not from this run's.
        let long = await harness.engine.timeline(accountID: harness.accountID, interval: DateInterval(start: at(-300), end: at(900)))
        #expect(long.coverageStart == at(0))
        // A range that ended before collection began is not covered at all.
        let before = await harness.engine.timeline(accountID: harness.accountID, interval: DateInterval(start: at(-300), end: at(-100)))
        #expect(before.coverageStart == at(-100))
        await harness.engine.stop()
    }

    @Test("Disabling an account closes its open segments")
    func disabling() async throws {
        let harness = try Harness()
        try await harness.start()
        await harness.sessions([try session("s1", .working, since: 0)], at: 0)
        harness.clock.set(7)
        await harness.engine.apply(settings: try AppSettings(accounts: [try harness.account.updated(isEnabled: false)]))
        #expect(try await harness.segments().map(\.end) == [at(7)])
        await harness.engine.stop()
    }
}

@Suite("Engine history queries")
struct EngineHistoryQueryTests {
    @Test("Token usage events are stored in buckets; samples of other accounts and empty samples are ignored")
    func tokensPersisted() async throws {
        let harness = try Harness(provider: .codex)
        try await harness.start()
        await harness.engine.handle(.tokenUsage(harness.accountID, [
            try tokens("s1", account: harness.accountID, project: "/Users/me/app", at: 1, input: 100, output: 5),
            try tokens("s1", account: harness.accountID, project: "/Users/me/app", at: 3, input: 50),
            try tokens("s1", account: AccountID(), project: "/Users/me/app", at: 3, input: 999),
            try tokens("s1", account: harness.accountID, project: "/Users/me/app", at: 3, input: 0),
        ]))
        await harness.engine.handle(.tokenUsage(harness.accountID, [
            try tokens("s1", account: harness.accountID, project: "/Users/me/app", at: 4, input: 1),
        ]))
        await harness.engine.flushHistory()
        let stored = try await harness.store.tokenSamples(accountID: harness.accountID, interval: DateInterval(start: at(0), end: at(60)))
        #expect(stored.count == 1)
        #expect(stored.first?.delta.input == 151)
        #expect(stored.first?.delta.output == 5)
        await harness.engine.stop()
    }

    @Test("Token usage is stored while paused; samples with implausible times are dropped")
    func tokensWhilePaused() async throws {
        let harness = try Harness(provider: .codex)
        harness.clock.set(0)
        try await harness.start()
        await harness.engine.setPaused(true)
        harness.clock.set(10)
        await harness.engine.handle(.tokenUsage(harness.accountID, [
            try tokens("s1", account: harness.accountID, project: nil, at: 9, input: 7),
            try tokens("s1", account: harness.accountID, project: nil, at: 10 + 24 * 60, input: 1_000),
            try tokens("s1", account: harness.accountID, project: nil, at: -60 * 24 * 40, input: 1_000),
        ]))
        await harness.engine.flushHistory()
        let stored = try await harness.store.tokenSamples(
            accountID: harness.accountID,
            interval: DateInterval(start: at(-60 * 24 * 50), end: at(60 * 24 * 2))
        )
        #expect(stored.map(\.delta.input) == [7])
        await harness.engine.stop()
    }

    @Test("Attribution splits the headline window's consumed points by weighted tokens")
    func attributionEndToEnd() async throws {
        let harness = try Harness()
        // Collection starts with the monitor, 5 minutes into the range queried below.
        harness.clock.set(-5)
        try await harness.start()
        let id = harness.accountID

        #expect(await harness.engine.attribution(accountID: id, interval: DateInterval(start: at(-10), end: at(200)), grouping: .project) == nil)

        for (minutes, used) in [(0.0, 10.0), (60, 30), (120, 40)] {
            harness.clock.set(minutes)
            await harness.engine.handle(.reading(id, try claudeReading(used: used, at: minutes)))
        }
        harness.clock.set(130)
        await harness.engine.handle(.tokenUsage(id, [
            // Claude weights: input 1, output 5. alpha: 1_000 + 400 × 5 = 3_000; beta: 1_000.
            try tokens("a1", account: id, project: "/Users/me/alpha", at: 20, input: 600, output: 400),
            try tokens("a2", account: id, project: "/Users/me/alpha", at: 70, input: 400),
            try tokens("b1", account: id, project: "/Users/me/beta", at: 90, input: 1_000),
        ]))

        let interval = DateInterval(start: at(-10), end: at(130))
        let byProject = try #require(await harness.engine.attribution(accountID: id, interval: interval, grouping: .project))
        #expect(byProject.usedPoints == 30)
        #expect(byProject.windowTitleSource?.id == "session")
        #expect(byProject.totalWeightedTokens == 4_000)
        #expect(byProject.shares.map(\.subject) == [.project("alpha"), .project("beta")])
        #expect(byProject.shares.map(\.share) == [0.75, 0.25])
        #expect(byProject.shares.map(\.estimatedPoints) == [22.5, 7.5])
        #expect(byProject.coverageStart == at(-5))

        let bySession = try #require(await harness.engine.attribution(accountID: id, interval: interval, grouping: .session))
        #expect(bySession.shares.map(\.id) == ["session:a1", "session:b1", "session:a2"])
        #expect(bySession.shares.first?.subject == .session(SessionLabelParts(folder: "alpha", idSuffix: "a1")))

        // A range that starts inside a bucket still covers it; data exists from before the range.
        let late = try #require(await harness.engine.attribution(accountID: id, interval: DateInterval(start: at(72), end: at(130)), grouping: .project))
        #expect(late.shares.map(\.subject) == [.project("beta"), .project("alpha")])
        #expect(late.coverageStart == at(72))
        #expect(late.usedPoints == nil)

        let timeline = await harness.engine.timeline(accountID: id, interval: interval)
        #expect(timeline.usage?.points.map(\.used) == [10, 30, 40])
        #expect(timeline.segments.isEmpty)
        #expect(timeline.coverageStart == at(-5))
        await harness.engine.stop()
    }

    @Test("Attribution never credits usage from before collection or across a restart or sleep")
    func attributionCoverage() async throws {
        let directory = try TemporaryDirectory()
        let account: AccountProfile
        do {
            let first = try Harness(directory: directory)
            account = first.account
            let id = first.accountID
            // Usage recorded by an older version before collection ever started.
            for (minutes, used) in [(-120.0, 0.0), (-60, 20), (-15, 39)] {
                try await first.store.record(try claudeReading(used: used, at: minutes), identity: nil, for: id)
            }
            first.clock.set(0)
            try await first.start()
            for (minutes, used) in [(1.0, 40.0), (30, 43)] {
                first.clock.set(minutes)
                await first.engine.handle(.reading(id, try claudeReading(used: used, at: minutes)))
            }
            // The Mac sleeps from 40 to 100; 10 points are used elsewhere meanwhile.
            first.clock.set(40)
            await first.engine.setPaused(true)
            first.clock.set(100)
            await first.engine.setPaused(false)
            for (minutes, used) in [(101.0, 53.0), (130, 55)] {
                first.clock.set(minutes)
                await first.engine.handle(.reading(id, try claudeReading(used: used, at: minutes)))
            }
            first.clock.set(140)
            await first.engine.stop()
        }

        // Quit from 140 to 200; relaunched, 5 more points were used meanwhile.
        let second = try Harness(directory: directory, account: account)
        let id = second.accountID
        second.clock.set(200)
        try await second.start()
        for (minutes, used) in [(201.0, 60.0), (230, 64)] {
            second.clock.set(minutes)
            await second.engine.handle(.reading(id, try claudeReading(used: used, at: minutes)))
        }
        await second.engine.handle(.tokenUsage(id, [try tokens("s1", account: id, project: "/Users/me/app", at: 210, input: 100)]))

        let whole = DateInterval(start: at(-240), end: at(240))
        let report = try #require(await second.engine.attribution(accountID: id, interval: whole, grouping: .project))
        // Counted: 40→43 (3), 53→55 (2), 60→64 (4). Not: before minute 0, the sleep, the quit.
        #expect(report.usedPoints == 9)
        #expect(report.shares.map(\.estimatedPoints) == [9])
        #expect(report.coverageStart == at(0))
        #expect(try await second.store.collectionStarts(accountID: id, interval: whole) == [at(0), at(100), at(200)])
        await second.engine.stop()
    }

    @Test("Window history finds a reset right after `since` using the observation before it")
    func windowHistoryReset() async throws {
        let harness = try Harness()
        try await harness.start()
        let id = harness.accountID
        harness.clock.set(0)
        await harness.engine.handle(.reading(id, try claudeReading(used: 80, at: 0, resetsAt: 50)))
        harness.clock.set(60)
        await harness.engine.handle(.reading(id, try claudeReading(used: 5, at: 60, resetsAt: 350)))
        harness.clock.set(70)
        await harness.engine.handle(.reading(id, try claudeReading(used: 9, at: 70, resetsAt: 350)))

        let series = await harness.engine.windowHistory(accountID: id, bucketID: "claude", windowID: "session", since: at(50))
        #expect(series.points.map(\.used) == [5, 9])
        #expect(series.resets == [at(50)])

        let all = await harness.engine.windowHistory(accountID: id, bucketID: "claude", windowID: "session", since: .distantPast)
        #expect(all.points.map(\.used) == [80, 5, 9])
        #expect(all.resets == [at(50)])
        await harness.engine.stop()
    }
}

@Suite("History recorder")
struct HistoryRecorderTests {
    @Test("Writes keep their order, and flush does not wait out the coalescing delay")
    func orderAndFlush() async throws {
        let directory = try TemporaryDirectory()
        let store = try UsageHistoryStore(databaseURL: directory.url.appendingPathComponent("history.sqlite"))
        let recorder = HistoryRecorder(store: store, coalescingDelay: .seconds(600))
        let account = AccountID()
        let segment = try SessionSegment(
            accountID: account, sessionID: "s1", title: nil, project: nil, activity: .working, start: at(0), end: nil
        )
        recorder.enqueue([
            .openSegment(segment, lastSeen: at(0)),
            .tokens([try tokens("s1", account: account, project: nil, at: 0, input: 1)]),
            .tokens([try tokens("s1", account: account, project: nil, at: 1, input: 2)]),
            .closeSegment(segment, at: at(3)),
            .removeAccount(account),
            .openSegment(segment, lastSeen: at(4)),
        ])
        let started = ContinuousClock.now
        await recorder.flush()
        #expect(ContinuousClock.now - started < .seconds(60))

        let range = DateInterval(start: at(0), end: at(10))
        let stored = try await store.segments(accountID: account, interval: range)
        #expect(stored.map(\.isOpen) == [true])
        #expect(try await store.tokenSamples(accountID: account, interval: range).isEmpty)

        recorder.enqueue(.tokens([try tokens("s1", account: account, project: nil, at: 0, input: 5)]))
        await recorder.flush()
        await recorder.flush()
        #expect(try await store.tokenSamples(accountID: account, interval: range).first?.delta.input == 5)
    }
}

@Suite("History coverage")
struct HistoryCoverageTests {
    @Test("Coverage starts at the collection start or the earliest data, clamped into the interval")
    func start() {
        let interval = DateInterval(start: at(0), end: at(60))
        #expect(HistoryCoverage.start(collection: nil, earliestData: nil, interval: interval) == nil)
        #expect(HistoryCoverage.start(collection: at(-100), earliestData: at(30), interval: interval) == at(0))
        #expect(HistoryCoverage.start(collection: at(20), earliestData: at(30), interval: interval) == at(20))
        #expect(HistoryCoverage.start(collection: at(40), earliestData: at(30), interval: interval) == at(30))
        #expect(HistoryCoverage.start(collection: nil, earliestData: at(10), interval: interval) == at(10))
        #expect(HistoryCoverage.start(collection: at(90), earliestData: nil, interval: interval) == at(60))
    }

    @Test("Only the account's samples with tokens and a plausible time are recordable")
    func recordableTokens() throws {
        let account = AccountID()
        let retentionMinutes = UsageHistoryStore.defaultRetention / 60
        let samples = [
            try tokens("recent", account: account, project: nil, at: -60, input: 1),
            try tokens("zero", account: account, project: nil, at: 0, input: 0),
            try tokens("foreign", account: AccountID(), project: nil, at: 0, input: 1),
            try tokens("expired", account: account, project: nil, at: -retentionMinutes - 1, input: 1),
            try tokens("future", account: account, project: nil, at: 6, input: 1),
            try tokens("skewed", account: account, project: nil, at: 4, input: 1),
        ]
        let kept = HistoryCoverage.recordableTokens(samples, accountID: account, now: at(0))
        #expect(kept.map(\.sessionID) == ["recent", "skewed"])
    }
}

@Suite("Engine collection runs and data controls")
struct EngineDataTests {
    private func runs(_ harness: Harness, from: Double = -600, to: Double = 600) async throws -> [CollectionRun] {
        await harness.engine.flushHistory()
        return try await harness.store.collectionRuns(
            accountID: harness.accountID,
            interval: DateInterval(start: at(from), end: at(to))
        )
    }

    @Test("A run opens at launch, is kept alive by events, and ends with the reason it ended for")
    func runLifecycle() async throws {
        let harness = try Harness()
        harness.clock.set(0)
        try await harness.start()
        #expect(try await runs(harness).map(\.endReason) == [nil])

        // Events keep the open run alive, at most once a minute.
        await harness.sessions([try session("s1", .working, since: 1)], at: 2)
        #expect(try await runs(harness).map(\.lastSeen) == [at(2)])
        await harness.sessions([try session("s1", .working, since: 1)], at: 2.5)
        #expect(try await runs(harness).map(\.lastSeen) == [at(2)])
        await harness.sessions([try session("s1", .working, since: 1)], at: 3.5)
        #expect(try await runs(harness).map(\.lastSeen) == [at(3.5)])

        harness.clock.set(10)
        await harness.engine.setPaused(true)
        #expect(try await runs(harness).map(\.endReason) == [.sleep])

        harness.clock.set(30)
        await harness.engine.setPaused(false)
        #expect(try await runs(harness).map(\.endReason) == [.sleep, nil])

        harness.clock.set(40)
        await harness.engine.stop()
        #expect(try await runs(harness).map(\.endReason) == [.sleep, .quit])
        #expect(try await runs(harness).map(\.end) == [at(10), at(40)])
    }

    @Test("Turning an account off ends its run, and turning it on starts a new one")
    func disabledAccount() async throws {
        let harness = try Harness()
        harness.clock.set(0)
        try await harness.start()

        harness.clock.set(20)
        let disabled = try harness.account.updated(isEnabled: false)
        await harness.engine.apply(settings: try AppSettings(accounts: [disabled]))
        #expect(try await runs(harness).map(\.endReason) == [.disabled])

        harness.clock.set(50)
        await harness.engine.apply(settings: try AppSettings(accounts: [harness.account]))
        #expect(try await runs(harness).map(\.endReason) == [.disabled, nil])
        await harness.engine.stop()
    }

    @Test("Runs a previous process left open are closed as a crash at the next launch")
    func crashedRun() async throws {
        let directory = try TemporaryDirectory()
        let account = try AccountProfile(
            provider: .claude,
            label: try AccountLabel(validating: "Test"),
            directory: try ProfileDirectory(validating: directory.url.appendingPathComponent(".profile").path)
        )
        do {
            let first = try Harness(directory: directory, account: account)
            first.clock.set(0)
            try await first.start()
            await first.sessions([try session("s1", .working, since: 1)], at: 5)
            await first.engine.flushHistory()
            // No `stop()`: the process disappeared.
        }
        let second = try Harness(directory: directory, account: account)
        second.clock.set(100)
        try await second.start()
        let stored = try await runs(second)
        #expect(stored.map(\.endReason) == [.crash, nil])
        #expect(stored.first?.end == at(5))
        await second.engine.stop()
    }

    @Test("The timeline marks the stretches where nothing could be collected")
    func timelineGaps() async throws {
        let directory = try TemporaryDirectory()
        let account = try AccountProfile(
            provider: .claude,
            label: try AccountLabel(validating: "Test"),
            directory: try ProfileDirectory(validating: directory.url.appendingPathComponent(".profile").path)
        )
        do {
            let first = try Harness(directory: directory, account: account)
            first.clock.set(0)
            try await first.start()
            first.clock.set(20)
            await first.engine.stop()
        }
        // Quit from minute 20 to minute 200, then a sleep from 210 to 400.
        let second = try Harness(directory: directory, account: account)
        second.clock.set(200)
        try await second.start()
        second.clock.set(210)
        await second.engine.setPaused(true)
        second.clock.set(400)
        await second.engine.setPaused(false)
        second.clock.set(500)
        await second.engine.flushHistory()

        let timeline = await second.engine.timeline(
            accountID: second.accountID,
            interval: DateInterval(start: at(0), end: at(500))
        )
        #expect(timeline.gaps.map(\.reason) == [.appNotRunning, .macAsleep])
        #expect(timeline.gaps.map(\.interval.start) == [at(20), at(210)])
        #expect(timeline.gaps.map(\.interval.end) == [at(200), at(400)])
        // Nothing is hatched before collection ever started.
        #expect(timeline.gaps.allSatisfy { $0.interval.start >= (timeline.coverageStart ?? .distantPast) })
        await second.engine.stop()
    }

    @Test("Changing the retention prunes what no longer fits right away")
    func retentionChange() async throws {
        let harness = try Harness()
        harness.clock.set(0)
        try await harness.start()
        let id = harness.accountID
        // Two readings ten days apart, the newer one "now".
        harness.clock.set(-14 * 24 * 60)
        await harness.engine.handle(.reading(id, try claudeReading(used: 20, at: -14 * 24 * 60)))
        harness.clock.set(0)
        await harness.engine.handle(.reading(id, try claudeReading(used: 30, at: 0)))
        await harness.engine.flushHistory()
        let all = DateInterval(start: at(-40 * 24 * 60), end: at(60))
        #expect(try await harness.store.samples(accountID: id, bucketID: "claude", windowID: "session", since: all.start).count == 2)

        var general = GeneralSettings()
        general.historyRetention = try HistoryRetention(days: 7)
        await harness.engine.apply(settings: try AppSettings(accounts: [harness.account], general: general))
        await harness.engine.flushHistory()
        #expect(await harness.store.retention == 7 * 86_400)
        #expect(try await harness.store.samples(accountID: id, bucketID: "claude", windowID: "session", since: all.start).map(\.used.value) == [30])
        await harness.engine.stop()
    }

    @Test("An export carries the history and never the account identity")
    func exportOmitsIdentity() async throws {
        let harness = try Harness()
        harness.clock.set(0)
        try await harness.start()
        let id = harness.accountID
        await harness.engine.handle(.identity(id, AccountIdentity(email: "person@example.com", organization: "Example", plan: "Max 20x")))
        await harness.engine.handle(.reading(id, try claudeReading(used: 30, at: 0)))
        await harness.sessions([try session("s1", .working, since: 1)], at: 2)
        await harness.engine.handle(.tokenUsage(id, [try tokens("s1", account: id, project: "/Users/me/app", at: 0, input: 100)]))

        let url = harness.directory.url.appendingPathComponent("Codometer History.json", isDirectory: false)
        let summary = try await harness.engine.export(
            HistoryExportRequest(
                format: .json,
                includeAccountNames: true,
                labels: [id: "Work"],
                appVersion: "1.0.0",
                retentionDays: 35,
                readmeText: "unused for JSON"
            ),
            to: url
        )
        #expect(summary.rowCount > 0)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("@") == false)
        #expect(text.contains("person") == false)
        #expect(text.contains("Example") == false)
        // Rule 0.2: no absolute home paths either — the project is stored (and exported) as its folder name.
        #expect(text.contains("/Users/") == false)
        #expect(text.contains("\"projectFolder\":\"app\""))
        #expect(text.contains("Work"))
        #expect(text.contains("claudeUsageCommand"))
        // A second export to the same name is refused instead of replacing it.
        await #expect(throws: HistoryExportError.destinationExists) {
            _ = try await harness.engine.export(
                HistoryExportRequest(
                    format: .json, includeAccountNames: false, labels: [:], appVersion: "1.0.0",
                    retentionDays: 35, readmeText: ""
                ),
                to: url
            )
        }
        await harness.engine.stop()
    }

    @Test("Preparing for an erase closes the database, so nothing is written afterwards")
    func prepareForErase() async throws {
        let harness = try Harness()
        harness.clock.set(0)
        try await harness.start()
        await harness.sessions([try session("s1", .working, since: 1)], at: 2)
        await harness.engine.prepareForErase()

        await #expect(throws: SQLiteError.closed) {
            _ = try await harness.store.accountIDs()
        }
        // The engine tolerates later calls: they have nowhere to write.
        await harness.engine.prepareForErase()
        // Profile readiness needs no database: the account's folder is simply gone.
        #expect(await harness.engine.inspectProfiles().map(\.state) == [.missingFolder])
    }
}
