import CodometerCore
@testable import CodometerEngine
import CodometerPlatform
import Foundation
import Synchronization
import Testing

/// A monitor that reports nothing by itself and records the energy factors it receives.
private actor RecordingMonitor: AccountMonitor {
    let profile: AccountProfile
    private(set) var factors: [EnergyFactor] = []

    init(profile: AccountProfile) {
        self.profile = profile
    }

    func start() async {}
    func stop() {}
    func refreshNow() {}
    func setPaused(_ paused: Bool) {}
    func diagnostics() -> AccountDiagnostics { .empty(accountID: profile.id, provider: profile.provider) }
    func setEnergyFactor(_ factor: EnergyFactor) { factors.append(factor) }
}

@Suite("Engine resets")
struct EngineResetsTests {
    private static let start = Date(timeIntervalSince1970: 1_789_600_000)

    private final class Clock: Sendable {
        private let current = Mutex(EngineResetsTests.start)
        var now: Date { current.withLock { $0 } }
        func advance(_ seconds: TimeInterval) { current.withLock { $0 = $0.addingTimeInterval(seconds) } }
    }

    private final class Monitors: Sendable {
        private let created = Mutex<[RecordingMonitor]>([])
        var all: [RecordingMonitor] { created.withLock { $0 } }
        func add(_ monitor: RecordingMonitor) { created.withLock { $0.append(monitor) } }
    }

    private func engine(clock: Clock, monitors: Monitors = Monitors()) throws -> TrackerEngine {
        let home = FileManager.default.temporaryDirectory
        let live = EngineDependencies.live(homeDirectory: home, directories: AppDirectories(root: home), history: nil)
        let dependencies = EngineDependencies(
            homeDirectory: home,
            history: nil,
            network: live.network,
            ownProcesses: live.ownProcesses,
            claudeProbe: live.claudeProbe,
            codexProbe: live.codexProbe,
            now: { clock.now }
        )
        return TrackerEngine(dependencies: dependencies, historyCoalescing: .zero, monitorFactory: { profile, _ in
            let monitor = RecordingMonitor(profile: profile)
            monitors.add(monitor)
            return monitor
        })
    }

    private func reading(used: Double, resetsIn: TimeInterval, at date: Date) throws -> UsageReading {
        try UsageReading(
            capturedAt: date,
            source: .codexAppServer,
            buckets: [try LimitBucket(id: "codex", title: nil, windows: [
                try LimitWindow(id: "primary", scope: .rolling, used: try Percentage(validating: used), duration: .fiveHours, resetsAt: date.addingTimeInterval(resetsIn)),
            ], isLimitReached: false)],
            credits: nil
        )
    }

    /// Every update the engine published, after it stopped (stopping finishes the stream).
    private func updates(of engine: TrackerEngine) async -> [EngineUpdate] {
        await engine.stop()
        var collected: [EngineUpdate] = []
        for await update in engine.updates {
            collected.append(update)
        }
        return collected
    }

    private func resets(in updates: [EngineUpdate]) -> [WindowResetEvent] {
        updates.flatMap { update -> [WindowResetEvent] in
            if case .resets(let events) = update { return events }
            return []
        }
    }

    private func alerts(in updates: [EngineUpdate]) -> [TrackerAlert] {
        updates.flatMap { update -> [TrackerAlert] in
            if case .alerts(let alerts) = update { return alerts }
            return []
        }
    }

    @Test("Resets are published even with reset notifications off and usage alerts muted for the group")
    func ignoresAlertSettings() async throws {
        let clock = Clock()
        let engine = try engine(clock: clock)
        let group = AccountGroup(name: try AccountLabel(validating: "Muted"), mutesUsageAlerts: true)
        let account = try AccountProfile(
            provider: .codex,
            label: try AccountLabel(validating: "Side project"),
            directory: try ProfileDirectory(validating: "/Users/example/.codex"),
            groupID: group.id
        )
        var alertSettings = AlertSettings()
        alertSettings.notifiesOnReset = false
        await engine.start(settings: try AppSettings(accounts: [account], groups: [group], alerts: alertSettings))

        await engine.handle(.reading(account.id, try reading(used: 64, resetsIn: 600, at: clock.now)))
        clock.advance(900)
        await engine.handle(.reading(account.id, try reading(used: 3, resetsIn: 5 * 3_600, at: clock.now)))

        let published = await updates(of: engine)
        let events = resets(in: published)
        #expect(events.count == 1)
        let event = try #require(events.first)
        #expect(event.accountID == account.id)
        #expect(event.bucketID == "codex" && event.windowID == "primary")
        #expect(event.previousUsed.value == 64 && event.newUsed.value == 3)
        #expect(event.detectedAt == clock.now)
        // Notifications still follow the settings: no reset alert.
        #expect(!alerts(in: published).contains { if case .limitReset = $0 { true } else { false } })
    }

    @Test("Readings without a reset, and events other than readings, publish no resets")
    func noResets() async throws {
        let clock = Clock()
        let engine = try engine(clock: clock)
        let account = try AccountProfile(
            provider: .codex,
            label: try AccountLabel(validating: "Side project"),
            directory: try ProfileDirectory(validating: "/Users/example/.codex")
        )
        await engine.start(settings: try AppSettings(accounts: [account]))
        await engine.handle(.reading(account.id, try reading(used: 40, resetsIn: 3_600, at: clock.now)))
        clock.advance(60)
        await engine.handle(.reading(account.id, try reading(used: 45, resetsIn: 3_540, at: clock.now)))
        await engine.handle(.refreshStarted(account.id))
        await engine.handle(.refreshFinished(account.id, nextRefreshAt: clock.now.addingTimeInterval(300)))
        #expect(resets(in: await updates(of: engine)).isEmpty)
    }

    @Test("New monitors start with the current energy factor, and setEnergy reaches running monitors")
    func energyForwarding() async throws {
        let clock = Clock()
        let monitors = Monitors()
        let engine = try engine(clock: clock, monitors: monitors)
        let saver = EnergyPolicy.decide(.nominalAC, mode: .saveBattery)
        await engine.setEnergy(saver)
        let account = try AccountProfile(
            provider: .claude,
            label: try AccountLabel(validating: "Work"),
            directory: try ProfileDirectory(validating: "/Users/example/.claude")
        )
        await engine.start(settings: try AppSettings(accounts: [account]))
        let monitor = try #require(monitors.all.first)
        #expect(await monitor.factors == [saver.factor])

        await engine.setEnergy(.normal)
        #expect(await monitor.factors == [saver.factor, EnergyFactor.normal])
        let diagnostics = await engine.diagnostics()
        #expect(diagnostics.energy == .normal)
        #expect(diagnostics.accounts.map(\.accountID) == [account.id])
        await engine.stop()
    }
}
