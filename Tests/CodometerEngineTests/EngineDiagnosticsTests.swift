import CodometerCore
@testable import CodometerEngine
import CodometerPlatform
import Foundation
import Synchronization
import Testing

/// A monitor that reports nothing by itself; it remembers the energy factors it was given and answers with a fixed
/// set of diagnostics, so the engine's own folding is what the tests see.
private actor StubMonitor: AccountMonitor {
    let profile: AccountProfile
    private(set) var factors: [EnergyFactor] = []
    private var ledger: ProbeLedger

    init(profile: AccountProfile, now: Date) {
        self.profile = profile
        ledger = ProbeLedger(kind: profile.provider == .claude ? .claudeUsageCommand : .codexAppServer)
        ledger.begin(at: now)
        ledger.end(at: now.addingTimeInterval(1.5), outcome: .reading(windowCount: 2))
    }

    func start() async {}
    func stop() {}
    func refreshNow() {}
    func setPaused(_ paused: Bool) {}
    func setEnergyFactor(_ factor: EnergyFactor) { factors.append(factor) }

    func diagnostics() -> AccountDiagnostics {
        AccountDiagnostics(
            accountID: profile.id,
            provider: profile.provider,
            recentProbes: ledger.records,
            lastLogReadingAt: nil,
            nextRefreshAt: nil,
            consecutiveFailures: 0,
            energyFactor: factors.last?.value ?? 1,
            drift: .empty
        )
    }
}

@Suite("Engine diagnostics")
struct EngineDiagnosticsTests {
    private static let start = Date(timeIntervalSince1970: 1_789_600_000)

    /// A clock that either stands still or jumps by a fixed step on every reading.
    private final class Clock: Sendable {
        private let state: Mutex<(now: Date, step: TimeInterval)>

        init(step: TimeInterval = 0) {
            state = Mutex((EngineDiagnosticsTests.start, step))
        }

        var now: Date {
            state.withLock { state in
                defer { state.now = state.now.addingTimeInterval(state.step) }
                return state.now
            }
        }
    }

    private final class Monitors: Sendable {
        private let created = Mutex<[StubMonitor]>([])
        var all: [StubMonitor] { created.withLock { $0 } }
        func add(_ monitor: StubMonitor) { created.withLock { $0.append(monitor) } }
    }

    private func engine(clock: Clock, monitors: Monitors, home: URL) -> TrackerEngine {
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
            let monitor = StubMonitor(profile: profile, now: Self.start)
            monitors.add(monitor)
            return monitor
        })
    }

    private func profile(_ provider: ProviderKind, at directory: URL, enabled: Bool = true) throws -> AccountProfile {
        try AccountProfile(
            provider: provider,
            label: try AccountLabel(validating: provider == .claude ? "Claude" : "Codex"),
            directory: try ProfileDirectory(validating: directory.path),
            isEnabled: enabled
        )
    }

    /// A profile directory of its own, so the settings' "one account per directory" rule holds.
    private func directory(_ root: URL, _ name: String) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("One entry per enabled account, with the monitor's probe history")
    func oneEntryPerAccount() async throws {
        let directory = try TemporaryDirectory()
        let clock = Clock()
        let monitors = Monitors()
        let engine = engine(clock: clock, monitors: monitors, home: directory.url)
        let claude = try profile(.claude, at: try self.directory(directory.url, ".claude"))
        let codex = try profile(.codex, at: try self.directory(directory.url, ".codex"))
        let disabled = try profile(.codex, at: try self.directory(directory.url, ".codex-off"), enabled: false)
        await engine.start(settings: try AppSettings(accounts: [claude, codex, disabled]))

        let diagnostics = await engine.diagnostics()
        #expect(diagnostics.accounts.count == 2)
        #expect(Set(diagnostics.accounts.map(\.accountID)) == [claude.id, codex.id])
        #expect(diagnostics.accounts.allSatisfy { $0.recentProbes.count == 1 })
        #expect(diagnostics.accounts.first?.recentProbes.first?.duration == 1.5)
        // No history store: the pane says so instead of guessing.
        #expect(diagnostics.history.health == .unavailable(reason: "history is not open"))
        await engine.stop()
    }

    @Test("An account without a monitor still appears, empty")
    func accountWithoutMonitor() async throws {
        let directory = try TemporaryDirectory()
        let clock = Clock()
        let engine = engine(clock: clock, monitors: Monitors(), home: directory.url)
        let claude = try profile(.claude, at: try self.directory(directory.url, ".claude"))
        // Never started: `apply` is what creates monitors, so nothing is known yet.
        let before = await engine.diagnostics()
        #expect(before.accounts.isEmpty)
        await engine.apply(settings: try AppSettings(accounts: [claude]))
        let after = await engine.diagnostics()
        #expect(after.accounts.map(\.accountID) == [claude.id])
        await engine.stop()
    }

    @Test("Setting the energy decision forwards the factor and shows the conditions behind it")
    func energyForwarded() async throws {
        let directory = try TemporaryDirectory()
        let clock = Clock()
        let monitors = Monitors()
        let engine = engine(clock: clock, monitors: monitors, home: directory.url)
        let claude = try profile(.claude, at: try self.directory(directory.url, ".claude"))
        await engine.start(settings: try AppSettings(accounts: [claude]))

        let snapshot = PowerSnapshot(
            lowPowerMode: true,
            onBattery: true,
            batteryPercent: try Percentage(validating: 12),
            thermal: .fair
        )
        let decision = EnergyPolicy.decide(snapshot, mode: .automatic)
        await engine.setEnergy(decision, power: snapshot)

        let diagnostics = await engine.diagnostics()
        #expect(diagnostics.energy == decision)
        #expect(diagnostics.power == snapshot)
        #expect(diagnostics.accounts.first?.energyFactor == decision.factor.value)
        let factors = await monitors.all.first?.factors
        #expect(factors?.last == decision.factor)
        await engine.stop()
    }

    @Test("Check System reports file modes, network and the profile it can read")
    func systemCheckItems() async throws {
        let directory = try TemporaryDirectory()
        let root = directory.url.appendingPathComponent("root", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let settingsFile = root.appendingPathComponent("settings.json", isDirectory: false)
        try Data("{}".utf8).write(to: settingsFile)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsFile.path)

        let clock = Clock()
        let engine = engine(clock: clock, monitors: Monitors(), home: directory.url)
        let codex = try profile(.codex, at: try self.directory(directory.url, ".codex"))
        await engine.start(settings: try AppSettings(accounts: [codex]))

        let report = await engine.checkSystem(directories: AppDirectories(root: root))
        let byKind = Dictionary(grouping: report.items, by: \.kind)
        #expect(byKind[.settingsPermissions]?.first?.status == .ok)
        #expect(byKind[.dataFolderPermissions]?.first?.status == .ok)
        #expect(byKind[.network]?.count == 1)
        // The directory exists but holds no auth.json, so the profile reads as "not signed in".
        #expect(byKind[.codexProfile]?.first?.status == .warning)
        #expect(byKind[.codexProfile]?.first?.id.contains(codex.id.description) == true)
        #expect(byKind[.historyDatabase]?.first?.status == .failure)
        // Items come out in check order, so a report always reads the same way.
        let order = SystemCheckItemKind.allCases
        let positions = report.items.compactMap { order.firstIndex(of: $0.kind) }
        #expect(positions == positions.sorted())
        await engine.stop()
    }

    @Test("Loose file modes are reported, never changed")
    func systemCheckLooseModes() async throws {
        let directory = try TemporaryDirectory()
        let root = directory.url.appendingPathComponent("open", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        let settingsFile = root.appendingPathComponent("settings.json", isDirectory: false)
        try Data("{}".utf8).write(to: settingsFile)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: settingsFile.path)

        let engine = engine(clock: Clock(), monitors: Monitors(), home: directory.url)
        await engine.start(settings: .empty)
        let report = await engine.checkSystem(directories: AppDirectories(root: root))
        let modes = report.items.filter { $0.kind == .settingsPermissions || $0.kind == .dataFolderPermissions }
        #expect(modes.count == 2)
        #expect(modes.allSatisfy { $0.status == .warning })
        #expect(modes.contains { $0.detail?.contains("0644") == true })
        #expect(SystemCheck.posixMode(of: settingsFile) == 0o644)
        await engine.stop()
    }

    /// `FileAccessError.description` names the file it failed on, and a profile may live outside the home folder,
    /// where the support report's `~` abbreviation cannot help. The detail is shown verbatim in the pane, so it has
    /// to carry the finding alone.
    @Test("A profile that cannot be read is reported without its path")
    func systemCheckProfileDetailHasNoPath() async throws {
        let directory = try TemporaryDirectory()
        let profileDirectory = try self.directory(directory.url, "claude-work")
        // A directory where the account state file belongs: readable profile, unreadable sign-in state.
        try FileManager.default.createDirectory(
            at: profileDirectory.appendingPathComponent(".claude.json", isDirectory: true),
            withIntermediateDirectories: true
        )

        let engine = engine(clock: Clock(), monitors: Monitors(), home: directory.url)
        let claude = try profile(.claude, at: profileDirectory)
        await engine.start(settings: try AppSettings(accounts: [claude]))
        let report = await engine.checkSystem(directories: AppDirectories(root: directory.url))
        let item = try #require(report.items.first { $0.kind == .claudeProfile })
        let detail = try #require(item.detail)
        #expect(item.status == .warning)
        #expect(detail.contains("sign-in state unknown"))
        #expect(!detail.contains("/"))
        #expect(!detail.contains(profileDirectory.lastPathComponent))
        #expect(!detail.contains(directory.url.path))
        await engine.stop()
    }

    @Test("The history item reads as a sentence, with the size after one comma")
    func historyItemDetail() {
        let diagnostics = HistoryDiagnostics(
            health: .ok,
            fileBytes: 40_960,
            schemaVersion: 4,
            oldestSampleAt: nil,
            retentionDays: 35,
            rowCounts: [:]
        )
        #expect(SystemCheck.historyItem(quickCheck: true, diagnostics: diagnostics).detail == "integrity check passed, 40 KiB")
        #expect(SystemCheck.historyItem(quickCheck: nil, diagnostics: diagnostics).detail == "integrity check did not finish, 40 KiB")
        #expect(SystemCheck.historyItem(quickCheck: false, diagnostics: diagnostics).detail == "integrity check failed")
    }

    @Test("Check System stops adding items once its budget is gone")
    func systemCheckBudget() async throws {
        let directory = try TemporaryDirectory()
        // Every reading of the clock jumps six seconds, so the budget runs out during the profile loop.
        let clock = Clock(step: 6)
        let engine = engine(clock: clock, monitors: Monitors(), home: directory.url)
        let profiles = try (0..<4).map { index in
            try profile(.codex, at: try self.directory(directory.url, ".codex-\(index)"))
        }
        await engine.start(settings: try AppSettings(accounts: profiles))
        let report = await engine.checkSystem(directories: AppDirectories(root: directory.url))
        #expect(report.items.filter { $0.kind == .codexProfile }.count < profiles.count)
        #expect(report.items.contains { $0.kind == .network })
        await engine.stop()
    }
}
