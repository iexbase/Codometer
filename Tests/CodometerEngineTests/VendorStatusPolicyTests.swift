import CodometerCore
@testable import CodometerEngine
import Foundation
import Synchronization
import Testing

@Suite("Vendor status policy")
struct VendorStatusPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_789_600_000)

    @Test("Checks need the setting, a visible surface, a tracked vendor, mains power, and a plain network")
    func conditions() {
        let allowed = VendorStatusConditions(isEnabled: true, hasDemand: true, providers: [.claude])
        #expect(allowed.allowsChecks)
        #expect(allowed.checkedProviders == [.claude])

        #expect(!VendorStatusConditions.off.allowsChecks)
        #expect(!VendorStatusConditions(isEnabled: false, hasDemand: true, providers: [.claude]).allowsChecks)
        #expect(!VendorStatusConditions(isEnabled: true, hasDemand: false, providers: [.claude]).allowsChecks)
        #expect(!VendorStatusConditions(isEnabled: true, hasDemand: true, providers: []).allowsChecks)
        #expect(!VendorStatusConditions(isEnabled: true, hasDemand: true, providers: [.claude], lowPowerMode: true).allowsChecks)
        #expect(!VendorStatusConditions(isEnabled: true, hasDemand: true, providers: [.claude], isOnline: false).allowsChecks)
        #expect(!VendorStatusConditions(isEnabled: true, hasDemand: true, providers: [.claude], isConstrained: true).allowsChecks)
        #expect(!VendorStatusConditions(isEnabled: true, hasDemand: true, providers: [.claude], isExpensive: true).allowsChecks)
        #expect(VendorStatusConditions.off.checkedProviders.isEmpty)

        // A vendor without an enabled account is never among the checked ones.
        let codexOnly = VendorStatusConditions(isEnabled: true, hasDemand: true, providers: [.codex])
        #expect(codexOnly.checkedProviders == [.codex])
        let both = VendorStatusConditions(isEnabled: true, hasDemand: true, providers: [.claude, .codex])
        #expect(both.checkedProviders == [.claude, .codex])
    }

    @Test("Ten minutes while it works, then 10 → 20 → 40 → 60 and no further")
    func backoffSequence() {
        #expect(VendorStatusPolicy.delay(consecutiveFailures: 0) == 600)
        #expect(VendorStatusPolicy.delay(consecutiveFailures: 1) == 600)
        #expect(VendorStatusPolicy.delay(consecutiveFailures: 2) == 1_200)
        #expect(VendorStatusPolicy.delay(consecutiveFailures: 3) == 2_400)
        #expect(VendorStatusPolicy.delay(consecutiveFailures: 4) == 3_600)
        #expect(VendorStatusPolicy.delay(consecutiveFailures: 40) == 3_600)
    }

    @Test("Jitter stays inside ±10 % and never retries faster than the step")
    func jitterBounds() {
        for step in VendorStatusPolicy.backoff + [VendorStatusPolicy.interval] {
            #expect(VendorStatusPolicy.jittered(step, random: 0) == step * 0.9)
            #expect(VendorStatusPolicy.jittered(step, random: 1) == step * 1.1)
            #expect(VendorStatusPolicy.jittered(step, random: 0.5) == step)
            // Out-of-range input cannot push a request outside the band.
            for random in [-5.0, 2.0, 0.25, 0.75] {
                let delay = VendorStatusPolicy.jittered(step, random: random)
                #expect(delay >= step * 0.9 && delay <= step * 1.1)
            }
        }
        let next = VendorStatusPolicy.nextCheck(after: now, consecutiveFailures: 2, random: 0)
        #expect(next.timeIntervalSince(now) == 1_200 * 0.9)
    }

    @Test("A surface appearing refreshes a reading older than five minutes and nothing fresher")
    func refreshOnShow() {
        // Never checked: at once.
        #expect(VendorStatusPolicy.nextCheckOnShow(scheduled: nil, lastCheckAt: nil, consecutiveFailures: 0) == .distantPast)
        // Checked a minute ago, next due in ten: the appearance does not pull it forward past the five-minute floor.
        let scheduled = now.addingTimeInterval(540)
        let lastCheck = now.addingTimeInterval(-60)
        #expect(VendorStatusPolicy.nextCheckOnShow(scheduled: scheduled, lastCheckAt: lastCheck, consecutiveFailures: 0) == lastCheck.addingTimeInterval(300))
        // Checked nine minutes ago: due now.
        let old = now.addingTimeInterval(-540)
        #expect(VendorStatusPolicy.nextCheckOnShow(scheduled: now.addingTimeInterval(60), lastCheckAt: old, consecutiveFailures: 0) <= now)
        // In backoff: the appearance never shortens the backoff.
        let failed = now.addingTimeInterval(-400)
        #expect(VendorStatusPolicy.nextCheckOnShow(scheduled: failed.addingTimeInterval(1_200), lastCheckAt: failed, consecutiveFailures: 2) == failed.addingTimeInterval(1_200))
    }
}

@Suite("Vendor status service")
struct VendorStatusServiceTests {
    private let start = Date(timeIntervalSince1970: 1_789_600_000)

    /// A fetcher that answers from a script and counts what it was asked.
    private final class Fetcher: VendorStatusFetching, @unchecked Sendable {
        private struct State {
            var outcomes: [ProviderKind: [VendorStatusOutcome]] = [:]
            var calls: [ProviderKind] = []
        }

        private let state = Mutex(State())

        init(_ outcomes: [ProviderKind: [VendorStatusOutcome]]) {
            state.withLock { $0.outcomes = outcomes }
        }

        var calls: [ProviderKind] { state.withLock { $0.calls } }

        func fetch(_ provider: ProviderKind, checkedAt: Date) async -> VendorStatusOutcome {
            state.withLock { state in
                state.calls.append(provider)
                guard var queued = state.outcomes[provider], !queued.isEmpty else { return .failed("no script") }
                let outcome = queued.removeFirst()
                // The last scripted answer repeats.
                state.outcomes[provider] = queued.isEmpty ? [outcome] : queued
                return outcome
            }
        }
    }

    private final class Published: @unchecked Sendable {
        private let boards = Mutex<[ServiceStatusBoard]>([])
        var all: [ServiceStatusBoard] { boards.withLock { $0 } }
        var last: ServiceStatusBoard? { boards.withLock { $0.last } }
        func record(_ board: ServiceStatusBoard) { boards.withLock { $0.append(board) } }
    }

    /// A hand-wound clock the service reads.
    private final class Clock: @unchecked Sendable {
        private let value = Mutex(Date())

        init(_ date: Date) {
            value.withLock { $0 = date }
        }

        var now: Date { value.withLock { $0 } }

        func set(_ date: Date) {
            value.withLock { $0 = date }
        }
    }

    private func makeService(
        _ fetcher: Fetcher,
        published: Published,
        clock: Clock,
        random: @escaping @Sendable () -> Double = { 0.5 }
    ) -> VendorStatusService {
        VendorStatusService(
            fetcher: fetcher,
            publish: { published.record($0) },
            now: { clock.now },
            random: random,
            // The loop never sleeps in tests: `tick()` is driven by hand.
            sleep: { _ in try await Task.sleep(for: .seconds(3_600)) }
        )
    }

    @Test("Nothing is fetched while the conditions forbid it")
    func neverChecksWhenForbidden() async {
        let clock = Clock(start)
        let fetcher = Fetcher([.claude: [.status(nil)]])
        let published = Published()
        let service = makeService(fetcher, published: published, clock: clock)

        for conditions in [
            VendorStatusConditions.off,
            VendorStatusConditions(isEnabled: false, hasDemand: true, providers: [.claude]),
            VendorStatusConditions(isEnabled: true, hasDemand: false, providers: [.claude]),
            VendorStatusConditions(isEnabled: true, hasDemand: true, providers: []),
            VendorStatusConditions(isEnabled: true, hasDemand: true, providers: [.claude], lowPowerMode: true),
            VendorStatusConditions(isEnabled: true, hasDemand: true, providers: [.claude], isOnline: false),
        ] {
            await service.update(conditions)
            #expect(await service.tick() == nil)
            #expect(await !service.isRunning)
        }
        #expect(fetcher.calls.isEmpty)
        #expect(published.all.isEmpty)
    }

    @Test("Only vendors with an enabled account are ever fetched")
    func checksOnlyTrackedVendors() async throws {
        let clock = Clock(start)
        let fetcher = Fetcher([
            .claude: [.status(ServiceStatus(provider: .claude, level: .partialOutage, affectedComponents: ["Claude Code"], checkedAt: start))],
            .codex: [.status(nil)],
        ])
        let published = Published()
        let service = makeService(fetcher, published: published, clock: clock)
        await service.update(VendorStatusConditions(isEnabled: true, hasDemand: true, providers: [.claude]))
        _ = await service.tick()
        #expect(fetcher.calls == [.claude])
        let board = try #require(published.last)
        #expect(board.visible(for: .claude, now: start)?.level == .partialOutage)
        #expect(board.statuses[.codex] == nil)
    }

    @Test("A working vendor is re-checked on the ten-minute cadence, not before")
    func cadence() async {
        let clock = Clock(start)
        let fetcher = Fetcher([.claude: [.status(nil)]])
        let published = Published()
        let service = makeService(fetcher, published: published, clock: clock)
        await service.update(VendorStatusConditions(isEnabled: true, hasDemand: true, providers: [.claude]))

        let firstDelay = await service.tick()
        #expect(fetcher.calls.count == 1)
        #expect(firstDelay == 600)

        clock.set(start.addingTimeInterval(599))
        #expect(await service.tick() == 1)
        #expect(fetcher.calls.count == 1)

        clock.set(start.addingTimeInterval(600))
        _ = await service.tick()
        #expect(fetcher.calls.count == 2)
    }

    @Test("Failures back off 10 → 20 → 40 → 60 minutes and recover on the next success")
    func backoff() async {
        let clock = Clock(start)
        let fetcher = Fetcher([.claude: [.failed("a"), .failed("b"), .failed("c"), .failed("d"), .failed("e"), .status(nil)]])
        let published = Published()
        let service = makeService(fetcher, published: published, clock: clock)
        await service.update(VendorStatusConditions(isEnabled: true, hasDemand: true, providers: [.claude]))

        var delays: [TimeInterval] = []
        for step in 0..<5 {
            clock.set(start.addingTimeInterval(TimeInterval(step) * 10_000))
            if let delay = await service.tick() {
                delays.append(delay)
            }
        }
        #expect(delays == [600, 1_200, 2_400, 3_600, 3_600])
        #expect(published.last?.lastFailureAt[.claude] != nil)

        clock.set(start.addingTimeInterval(100_000))
        let recovered = await service.tick()
        #expect(recovered == 600)
        #expect(published.last?.lastFailureAt[.claude] == nil)
    }

    @Test("A 304 keeps the reading and only moves its timestamp, so it stays visible")
    func notModifiedRefreshesFreshness() async throws {
        let clock = Clock(start)
        let outage = ServiceStatus(provider: .claude, level: .majorOutage, affectedComponents: ["Claude Code"], checkedAt: start)
        let fetcher = Fetcher([.claude: [.status(outage), .notModified]])
        let published = Published()
        let service = makeService(fetcher, published: published, clock: clock)
        await service.update(VendorStatusConditions(isEnabled: true, hasDemand: true, providers: [.claude]))
        _ = await service.tick()

        let later = start.addingTimeInterval(1_800)
        clock.set(later)
        _ = await service.tick()
        let board = try #require(published.last)
        #expect(board.statuses[.claude]?.level == .majorOutage)
        #expect(board.statuses[.claude]?.checkedAt == later)
        // Without the refreshed timestamp the reading would have aged out of the 30-minute window.
        #expect(board.visible(for: .claude, now: later) != nil)
    }

    @Test("Switching the toggle off mid-backoff cancels the pending work at once")
    func toggleOffCancels() async {
        let clock = Clock(start)
        let fetcher = Fetcher([.claude: [.failed("down")]])
        let published = Published()
        let service = makeService(fetcher, published: published, clock: clock)
        await service.update(VendorStatusConditions(isEnabled: true, hasDemand: true, providers: [.claude]))
        _ = await service.tick()
        #expect(await service.isRunning)
        #expect(fetcher.calls.count == 1)

        await service.update(VendorStatusConditions(isEnabled: false, hasDemand: true, providers: [.claude]))
        #expect(await !service.isRunning)

        // Even at the moment the backoff would have expired, nothing runs any more.
        clock.set(start.addingTimeInterval(10_000))
        #expect(await service.tick() == nil)
        #expect(fetcher.calls.count == 1)
    }

    @Test("A surface closing and opening again re-checks only a reading older than five minutes")
    func surfaceReappearing() async {
        let clock = Clock(start)
        let fetcher = Fetcher([.claude: [.status(nil)]])
        let published = Published()
        let service = makeService(fetcher, published: published, clock: clock)
        let visible = VendorStatusConditions(isEnabled: true, hasDemand: true, providers: [.claude])
        let hidden = VendorStatusConditions(isEnabled: true, hasDemand: false, providers: [.claude])

        await service.update(visible)
        _ = await service.tick()
        #expect(fetcher.calls.count == 1)

        // Closed and reopened after two minutes: the reading is still fresh.
        clock.set(start.addingTimeInterval(120))
        await service.update(hidden)
        await service.update(visible)
        _ = await service.tick()
        #expect(fetcher.calls.count == 1)

        // Reopened after six minutes: worth a new check, although the cadence would wait ten.
        clock.set(start.addingTimeInterval(360))
        await service.update(hidden)
        await service.update(visible)
        _ = await service.tick()
        #expect(fetcher.calls.count == 2)
    }
}
