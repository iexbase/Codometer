import CodometerCore
@testable import CodometerUI
import Foundation
import Testing

/// Counts loads from `@MainActor` loader closures.
@MainActor
final class LoadCounter {
    var count = 0
    var sinces: [Date] = []
    var intervals: [DateInterval] = []
    var groupings: [AttributionGrouping] = []
}

/// A clock the tests move by hand.
@MainActor
final class ManualClock {
    var now = UIFixture.now

    func advance(_ seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}

@MainActor
@Suite("Analytics cache")
struct AnalyticsCacheTests {
    private let account = AccountID()
    private let other = AccountID()

    private func makeCache(
        counter: LoadCounter,
        clock: ManualClock,
        interval: TimeInterval = AnalyticsCache.minimumReloadInterval
    ) -> AnalyticsCache {
        let actions = UIFixture.actions(
            loadWindowHistory: { account, bucket, window, since in
                counter.count += 1
                counter.sinces.append(since)
                let point = try? UsagePoint(at: since, used: Double(counter.count))
                return HistorySeries(accountID: account, bucketID: bucket, windowID: window, points: point.map { [$0] } ?? [], resets: [])
            },
            loadTimeline: { account, interval in
                counter.count += 1
                counter.intervals.append(interval)
                return TimelineSnapshot(accountID: account, interval: interval, segments: [], usage: nil)
            },
            loadAttribution: { _, interval, grouping in
                counter.count += 1
                counter.intervals.append(interval)
                counter.groupings.append(grouping)
                return grouping == .project
                    ? AttributionReport(interval: interval, windowTitleSource: nil, usedPoints: nil, shares: [], totalWeightedTokens: 0)
                    : nil
            }
        )
        return AnalyticsCache(actions: actions, minimumReloadInterval: interval, clock: { clock.now })
    }

    @Test("Nothing loads until a view requests it")
    func lazy() async {
        let counter = LoadCounter()
        let cache = makeCache(counter: counter, clock: ManualClock())
        #expect(cache.series(account: account, bucket: "claude", window: "session") == nil)
        #expect(cache.timeline(account: account, range: .day) == nil)
        cache.invalidate(account: account)
        cache.stateChanged(from: .empty, to: .empty)
        await cache.settle()
        #expect(counter.count == 0)
    }

    @Test("A request loads once; duplicates in flight and repeats of fresh data are dropped")
    func deduplicates() async {
        let counter = LoadCounter()
        let clock = ManualClock()
        let cache = makeCache(counter: counter, clock: clock)
        cache.requestSeries(account: account, bucket: "claude", window: "session", since: clock.now)
        cache.requestSeries(account: account, bucket: "claude", window: "session", since: clock.now)
        #expect(cache.isBusy(series: account, bucket: "claude", window: "session"))
        await cache.settle()
        #expect(counter.count == 1)
        #expect(cache.series(account: account, bucket: "claude", window: "session")?.points.first?.used == 1)

        clock.advance(600)
        cache.requestSeries(account: account, bucket: "claude", window: "session", since: UIFixture.now)
        await cache.settle()
        #expect(counter.count == 1)
        #expect(!cache.isBusy(series: account, bucket: "claude", window: "session"))

        // Other keys and accounts load independently.
        cache.requestSeries(account: account, bucket: "claude", window: "week", since: clock.now)
        cache.requestSeries(account: other, bucket: "claude", window: "session", since: clock.now)
        await cache.settle()
        #expect(counter.count == 3)
    }

    @Test("An invalidated key reloads at most once per interval")
    func throttles() async {
        let counter = LoadCounter()
        let clock = ManualClock()
        let cache = makeCache(counter: counter, clock: clock)
        cache.requestSeries(account: account, bucket: "claude", window: "session", since: UIFixture.now)
        await cache.settle()

        clock.advance(10)
        cache.invalidate(account: account)
        cache.requestSeries(account: account, bucket: "claude", window: "session", since: UIFixture.now)
        await cache.settle()
        #expect(counter.count == 1)
        // Remembered for when the interval has passed.
        #expect(cache.isBusy(series: account, bucket: "claude", window: "session"))
        #expect(cache.series(account: account, bucket: "claude", window: "session")?.points.first?.used == 1)

        clock.advance(51)
        cache.requestSeries(account: account, bucket: "claude", window: "session", since: UIFixture.now)
        await cache.settle()
        #expect(counter.count == 2)
        #expect(cache.series(account: account, bucket: "claude", window: "session")?.points.first?.used == 2)
        #expect(!cache.isBusy(series: account, bucket: "claude", window: "session"))

        // Fresh again: another invalidation is needed before the next load.
        clock.advance(120)
        cache.requestSeries(account: account, bucket: "claude", window: "session", since: UIFixture.now)
        await cache.settle()
        #expect(counter.count == 2)
    }

    @Test("A throttled request runs by itself once the interval passes")
    func deferredReload() async throws {
        let counter = LoadCounter()
        let cache = AnalyticsCache(
            actions: UIFixture.actions(loadTimeline: { account, interval in
                counter.count += 1
                return TimelineSnapshot(accountID: account, interval: interval, segments: [], usage: nil)
            }),
            minimumReloadInterval: 0.05
        )
        cache.requestTimeline(account: account, range: .fiveHours)
        await cache.settle()
        cache.invalidate(account: account)
        cache.requestTimeline(account: account, range: .fiveHours)
        #expect(counter.count == 1)

        let deadline = Date().addingTimeInterval(5)
        while counter.count < 2, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        await cache.settle()
        #expect(counter.count == 2)
    }

    @Test("A new series start counts as a change")
    func newSince() async {
        let counter = LoadCounter()
        let clock = ManualClock()
        let cache = makeCache(counter: counter, clock: clock)
        let first = UIFixture.now.addingTimeInterval(-3_600)
        let second = UIFixture.now.addingTimeInterval(1_000)
        cache.requestSeries(account: account, bucket: "claude", window: "session", since: first)
        await cache.settle()
        clock.advance(5)
        cache.requestSeries(account: account, bucket: "claude", window: "session", since: second)
        await cache.settle()
        #expect(counter.count == 1)

        clock.advance(60)
        cache.requestSeries(account: account, bucket: "claude", window: "session", since: second)
        await cache.settle()
        #expect(counter.sinces == [first, second])
    }

    @Test("Timelines and attribution cover the range ending when the load starts")
    func ranges() async {
        let counter = LoadCounter()
        let clock = ManualClock()
        let cache = makeCache(counter: counter, clock: clock)
        cache.requestTimeline(account: account, range: .fiveHours)
        cache.requestAttribution(account: account, range: .week, grouping: .project)
        cache.requestAttribution(account: account, range: .week, grouping: .session)
        await cache.settle()

        #expect(counter.count == 3)
        #expect(counter.intervals.contains(AnalyticsRange.fiveHours.interval(endingAt: clock.now)))
        #expect(counter.intervals.filter { $0 == AnalyticsRange.week.interval(endingAt: clock.now) }.count == 2)
        #expect(Set(counter.groupings) == [.project, .session])
        #expect(cache.timeline(account: account, range: .fiveHours)?.interval.end == clock.now)
        #expect(cache.timeline(account: account, range: .day) == nil)
        #expect(cache.attribution(account: account, range: .week, grouping: .project) != nil)
        #expect(cache.attribution(account: account, range: .week, grouping: .session) == nil)
    }

    @Test("Attribution without token data is nil, and a reload that finds none clears the cached report")
    func attributionWithoutData() async {
        let clock = ManualClock()
        let counter = LoadCounter()
        let actions = UIFixture.actions(loadAttribution: { _, interval, _ in
            counter.count += 1
            // The first load finds tokens, with coverage clamped to the interval end (collection began only when the
            // period ended); later loads find none.
            return counter.count == 1
                ? AttributionReport(interval: interval, windowTitleSource: nil, usedPoints: nil, shares: [], totalWeightedTokens: 0, coverageStart: interval.end)
                : nil
        })
        let cache = AnalyticsCache(actions: actions, minimumReloadInterval: 60, clock: { clock.now })
        cache.requestAttribution(account: account, range: .day, grouping: .project)
        await cache.settle()
        #expect(cache.attribution(account: account, range: .day, grouping: .project)?.coverageStart == clock.now)

        cache.invalidate(account: account)
        clock.advance(61)
        cache.requestAttribution(account: account, range: .day, grouping: .project)
        await cache.settle()
        #expect(counter.count == 2)
        #expect(cache.attribution(account: account, range: .day, grouping: .project) == nil)
        #expect(AttributionRows.showsPlaceholder(cache.attribution(account: account, range: .day, grouping: .project)))

        // Nil is a loaded result like any other: repeating the request does not load again.
        cache.requestAttribution(account: account, range: .day, grouping: .project)
        await cache.settle()
        #expect(counter.count == 2)
    }

    @Test("State changes invalidate changed accounts and forget removed ones")
    func stateChanges() async throws {
        let changedProfile = try UIFixture.profile("Changed")
        let sessionsProfile = try UIFixture.profile("Sessions")
        let sameProfile = try UIFixture.profile("Same")
        let removedProfile = try UIFixture.profile("Removed")
        let reading = try UIFixture.reading([try UIFixture.bucket("claude", [try UIFixture.window("session", .session, used: 10)])])
        let old = TrackerState(accounts: [
            AccountStatus(profile: changedProfile, reading: reading),
            AccountStatus(profile: sessionsProfile),
            AccountStatus(profile: sameProfile, reading: reading),
            AccountStatus(profile: removedProfile),
        ])
        var new = old
        new.accounts[0].reading = try UIFixture.reading(
            [try UIFixture.bucket("claude", [try UIFixture.window("session", .session, used: 10)])],
            capturedAgo: 0
        )
        new.accounts[1].sessions = [try UIFixture.session("s", .working)]
        new.accounts[2].isRefreshing = true
        new.accounts.removeLast()

        let changes = AnalyticsCache.changes(from: old, to: new)
        #expect(changes.changed == [changedProfile.id, sessionsProfile.id])
        #expect(changes.removed == [removedProfile.id])

        let counter = LoadCounter()
        let clock = ManualClock()
        let cache = makeCache(counter: counter, clock: clock)
        cache.requestSeries(account: removedProfile.id, bucket: "claude", window: "session", since: clock.now)
        cache.requestSeries(account: sameProfile.id, bucket: "claude", window: "session", since: clock.now)
        await cache.settle()
        cache.stateChanged(from: old, to: new)
        #expect(cache.series(account: removedProfile.id, bucket: "claude", window: "session") == nil)
        #expect(cache.series(account: sameProfile.id, bucket: "claude", window: "session") != nil)

        // A removed account's load that was already running is dropped when it returns.
        cache.requestSeries(account: removedProfile.id, bucket: "claude", window: "session", since: clock.now)
        cache.remove(account: removedProfile.id)
        try await Task.sleep(for: .milliseconds(50))
        #expect(cache.series(account: removedProfile.id, bucket: "claude", window: "session") == nil)
    }
}
