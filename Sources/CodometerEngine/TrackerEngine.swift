import CodometerClaude
import CodometerCodex
import CodometerCore
import CodometerPlatform
import CodometerStorage
import Foundation
import os

/// Everything the engine needs from the outside world, injectable for tests.
public struct EngineDependencies: Sendable {
    public let homeDirectory: URL
    public let history: UsageHistoryStore?
    public let network: NetworkStatusMonitor
    public let ownProcesses: ChildProcessRegistry
    public let claudeProbe: ClaudeUsageProbe
    public let codexProbe: CodexAppServerProbe
    public let now: @Sendable () -> Date

    public init(
        homeDirectory: URL,
        history: UsageHistoryStore?,
        network: NetworkStatusMonitor,
        ownProcesses: ChildProcessRegistry,
        claudeProbe: ClaudeUsageProbe,
        codexProbe: CodexAppServerProbe,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.homeDirectory = homeDirectory
        self.history = history
        self.network = network
        self.ownProcesses = ownProcesses
        self.claudeProbe = claudeProbe
        self.codexProbe = codexProbe
        self.now = now
    }

    /// Production wiring: signature-verified binaries, minimal child environments, one shared process registry.
    public static func live(homeDirectory: URL, directories: AppDirectories, history: UsageHistoryStore?) -> EngineDependencies {
        let registry = ChildProcessRegistry()
        let locator = TrustedExecutableLocator(verifier: CodeSignatureVerifier())
        return EngineDependencies(
            homeDirectory: homeDirectory,
            history: history,
            network: NetworkStatusMonitor(),
            ownProcesses: registry,
            claudeProbe: ClaudeUsageProbe(
                locator: locator,
                runner: ProcessRunner(registry: registry),
                homeDirectory: homeDirectory,
                workingDirectory: directories.probeWorkingDirectory
            ),
            codexProbe: CodexAppServerProbe(
                locator: locator,
                registry: registry,
                homeDirectory: homeDirectory,
                workingDirectory: directories.probeWorkingDirectory
            )
        )
    }
}

public enum EngineUpdate: Sendable {
    case state(TrackerState)
    case alerts([TrackerAlert])
    /// Limit windows that just reset (reading events only), whatever the alert settings and group mutes say: the app
    /// celebrates them on the rings.
    case resets([WindowResetEvent])
}

/// Owns one monitor per enabled account and folds their events into a single `TrackerState`.
///
/// History: readings are stored as limit samples, session transitions become segments and token samples become
/// 5-minute token buckets; `HistoryRecorder` writes all of them in order, off the event path. Queries flush
/// pending writes first, so they always see everything handled so far (`TrackerEngine+History`).
///
/// Features live in extensions (`+History`, `+Diagnostics`, `+Energy`, `+Data`); the state they share is internal here,
/// and each extension keeps its own stored state in one holder property declared below.
public actor TrackerEngine {
    /// Builds the monitor of one account; tests substitute monitors that report nothing on their own.
    typealias MonitorFactory = @Sendable (AccountProfile, AsyncStream<MonitorEvent>.Continuation) -> any AccountMonitor

    /// Old history is pruned again after this long, so an app that runs for weeks keeps its database small.
    static let pruneInterval: TimeInterval = 6 * 60 * 60
    /// Open collection runs are marked as alive at most this often, so a crash loses at most about this much.
    static let runTouchInterval: TimeInterval = 60

    public nonisolated let updates: AsyncStream<EngineUpdate>

    private let updatesContinuation: AsyncStream<EngineUpdate>.Continuation
    private let events: AsyncStream<MonitorEvent>
    private let eventsContinuation: AsyncStream<MonitorEvent>.Continuation
    let dependencies: EngineDependencies
    private let monitorFactory: MonitorFactory?
    let recorder: HistoryRecorder?

    var state = TrackerState.empty
    var settings = AppSettings.empty
    private var evaluator = AlertEvaluator(settings: AlertSettings())
    var monitors: [AccountID: any AccountMonitor] = [:]
    private var monitoredProfiles: [AccountID: AccountProfile] = [:]
    /// The latest energy decision; new monitors start with its factor (`TrackerEngine+Energy`).
    var energyDecision: EnergyDecision = .normal
    /// State kept for the Diagnostics pane (`TrackerEngine+Diagnostics`).
    var diagnosticsState = EngineDiagnosticsState()
    /// Profile readiness for onboarding, with its own metadata cache (`TrackerEngine+Data`).
    var profileInspector = ProfileInspector()
    private var restored: [AccountID: RestoredAccountState] = [:]
    private var eventTask: Task<Void, Never>?
    private var isPaused = false
    private var isStopped = false

    private var segments = SegmentTracker()
    /// Per account, the earliest time a new segment may start: when its monitor started or the Mac woke.
    private var segmentFloors: [AccountID: Date] = [:]
    /// Accounts with stored data when the engine started, so data of accounts removed meanwhile is deleted.
    private var storedAccounts: Set<AccountID> = []
    private var lastPrunedAt: Date?
    /// When open collection runs were last marked as alive.
    private var lastRunTouchAt: Date?

    public init(dependencies: EngineDependencies) {
        self.init(dependencies: dependencies, historyCoalescing: HistoryRecorder.defaultCoalescingDelay, monitorFactory: nil)
    }

    init(dependencies: EngineDependencies, historyCoalescing: Duration, monitorFactory: MonitorFactory?) {
        self.dependencies = dependencies
        self.monitorFactory = monitorFactory
        recorder = dependencies.history.map { HistoryRecorder(store: $0, coalescingDelay: historyCoalescing) }
        (updates, updatesContinuation) = AsyncStream.makeStream(of: EngineUpdate.self, bufferingPolicy: .bufferingNewest(16))
        (events, eventsContinuation) = AsyncStream.makeStream(of: MonitorEvent.self, bufferingPolicy: .unbounded)
    }

    public func start(settings: AppSettings) async {
        guard eventTask == nil else { return }
        dependencies.network.start()
        if let history = dependencies.history {
            restored = (try? await history.restoredStates()) ?? [:]
            let now = dependencies.now()
            await history.setRetention(settings.general.historyRetention.timeInterval)
            do throws(SQLiteError) {
                // Segments and runs a crashed or force-quit process left open end where they were last seen.
                let closed = try await history.closeDanglingSegments()
                if closed > 0 {
                    AppLog.storage.notice("closed \(closed, privacy: .public) segments left open by the previous run")
                }
                let runs = try await history.closeDanglingCollectionRuns()
                if runs > 0 {
                    AppLog.storage.notice("closed \(runs, privacy: .public) collection runs left open by the previous run")
                }
                try await history.prune(now: now)
                storedAccounts = try await history.accountIDs()
            } catch {
                AppLog.storage.error("history maintenance failed: \(error.description, privacy: .public)")
            }
            lastPrunedAt = now
        }
        let events = events
        eventTask = Task { [weak self] in
            for await event in events {
                await self?.handle(event)
            }
        }
        await apply(settings: settings)
    }

    /// Reconciles monitors with the account list: starts new ones, stops removed or changed ones.
    public func apply(settings newSettings: AppSettings) async {
        let previousAccounts = Set(settings.accounts.map(\.id))
        let previousRetention = settings.general.historyRetention
        settings = newSettings
        evaluator = AlertEvaluator(appSettings: newSettings)
        if newSettings.general.historyRetention != previousRetention {
            applyRetention(newSettings.general.historyRetention)
        }

        let wanted = Dictionary(uniqueKeysWithValues: newSettings.accounts.filter(\.isEnabled).map { ($0.id, $0) })
        for (id, monitor) in monitors where Self.needsNewMonitor(wanted: wanted[id], monitored: monitoredProfiles[id]) {
            await monitor.stop()
            monitors[id] = nil
            monitoredProfiles[id] = nil
        }
        for (id, profile) in wanted where monitors[id] != nil {
            monitoredProfiles[id] = profile
        }

        state.accounts = newSettings.accounts.map { profile in
            if var existing = state.account(profile.id) {
                existing.profile = profile
                if !profile.isEnabled {
                    existing.sessions = []
                    existing.isRefreshing = false
                    existing.nextRefreshAt = nil
                }
                return existing
            }
            let saved = restored[profile.id]
            return AccountStatus(profile: profile, identity: saved?.identity, reading: saved?.reading)
        }
        recordSettingsChange(previousAccounts: previousAccounts, now: dependencies.now())
        publishState()

        for (id, profile) in wanted where monitors[id] == nil {
            let monitor = makeMonitor(for: profile)
            monitors[id] = monitor
            monitoredProfiles[id] = profile
            recordCollectionStart(accountID: id, now: dependencies.now())
            await monitor.setEnergyFactor(energyDecision.factor)
            await monitor.setPaused(isPaused)
            await monitor.start()
        }
    }

    /// Whether a profile change needs its monitor restarted: only when what a monitor works with changed
    /// (`MonitorIdentity`). Label, group, tint and monogram edits only affect presentation and alerts.
    static func needsNewMonitor(wanted: AccountProfile?, monitored: AccountProfile?) -> Bool {
        wanted.map(MonitorIdentity.init) != monitored.map(MonitorIdentity.init)
    }

    public func refresh(accountID: AccountID?) async {
        for (id, monitor) in monitors where accountID == nil || id == accountID {
            await monitor.refreshNow()
        }
    }

    /// Pauses scheduled refreshes, e.g. while the Mac sleeps. Resuming refreshes every account once.
    public func setPaused(_ paused: Bool) async {
        guard paused != isPaused else { return }
        isPaused = paused
        recordPause(paused, now: dependencies.now())
        for monitor in monitors.values {
            await monitor.setPaused(paused)
        }
    }

    public func stop() async {
        if !isStopped, let recorder {
            // Everything still open ends now; nothing is recorded after this point.
            segments = SegmentTracker()
            let now = dependencies.now()
            recorder.enqueue(.closeOpenSegments(at: now))
            recorder.enqueue(.endCollection(nil, at: now, reason: .quit))
        }
        isStopped = true
        for monitor in monitors.values {
            await monitor.stop()
        }
        monitors.removeAll()
        monitoredProfiles.removeAll()
        eventTask?.cancel()
        eventTask = nil
        dependencies.network.stop()
        eventsContinuation.finish()
        updatesContinuation.finish()
        await recorder?.flush()
    }

    // MARK: - History recording

    /// Segments and token rows of accounts removed from settings are deleted; disabled accounts' segments close.
    private func recordSettingsChange(previousAccounts: Set<AccountID>, now: Date) {
        guard let recorder, !isStopped else { return }
        let known = Set(settings.accounts.map(\.id))
        for profile in settings.accounts where !profile.isEnabled {
            recorder.enqueue(segments.closeAll(accountID: profile.id, at: now))
            recorder.enqueue(.endCollection(profile.id, at: now, reason: .disabled))
        }
        let removed = previousAccounts.union(storedAccounts).union(restored.keys).subtracting(known)
        for id in removed.sorted(by: { $0.description < $1.description }) {
            segments.forget(accountID: id)
            segmentFloors[id] = nil
            recorder.enqueue(.removeAccount(id))
        }
        storedAccounts.subtract(removed)
        restored = restored.filter { known.contains($0.key) }
    }

    /// Pausing (sleep) closes every segment now; resuming reopens the ones the current state still shows active,
    /// starting now, and starts a new collection run: usage while the Mac slept has no recorded tokens.
    private func recordPause(_ paused: Bool, now: Date) {
        guard let recorder, !isStopped else { return }
        if paused {
            recorder.enqueue(segments.closeAll(at: now))
            recorder.enqueue(.endCollection(nil, at: now, reason: .sleep))
            return
        }
        for account in state.accounts where monitors[account.id] != nil {
            segmentFloors[account.id] = now
            recorder.enqueue(.beginCollection(account.id, at: now))
            recorder.enqueue(segments.update(accountID: account.id, sessions: account.sessions, now: now, floor: now))
        }
    }

    private func recordSessions(_ sessions: [AgentSession], accountID: AccountID, now: Date) {
        guard let recorder, !isPaused, !isStopped else { return }
        let floor = segmentFloors[accountID] ?? now
        recorder.enqueue(segments.update(accountID: accountID, sessions: sessions, now: now, floor: floor))
    }

    /// A monitor (re)started for the account: new segments may start from now, a new collection run begins, and
    /// coverage counts from the first time this ever happened.
    private func recordCollectionStart(accountID: AccountID, now: Date) {
        segmentFloors[accountID] = now
        guard let recorder, !isStopped else { return }
        recorder.enqueue(.beginCollection(accountID, at: now))
    }

    private func recordTokens(_ samples: [TokenSample], accountID: AccountID, now: Date) {
        guard let recorder, !isStopped else { return }
        let valid = HistoryCoverage.recordableTokens(
            samples,
            accountID: accountID,
            now: now,
            retention: settings.general.historyRetention.timeInterval
        )
        guard !valid.isEmpty else { return }
        recorder.enqueue([.tokens(valid)])
    }

    /// Periodic work piggybacks on events instead of timers: `last_seen` of open segments and pruning.
    private func recordHousekeeping(now: Date) {
        guard let recorder, !isStopped else { return }
        if !isPaused {
            recorder.enqueue(segments.touchIfDue(now: now))
            if lastRunTouchAt.map({ now.timeIntervalSince($0) >= Self.runTouchInterval }) ?? true {
                lastRunTouchAt = now
                recorder.enqueue(.touchCollectionRuns(at: now))
            }
        }
        if let lastPrunedAt, now.timeIntervalSince(lastPrunedAt) >= Self.pruneInterval {
            self.lastPrunedAt = now
            recorder.enqueue(.prune(now: now))
        }
    }

    // MARK: - Events

    private func makeMonitor(for profile: AccountProfile) -> any AccountMonitor {
        if let monitorFactory {
            return monitorFactory(profile, eventsContinuation)
        }
        return switch profile.provider {
        case .claude:
            ClaudeAccountMonitor(
                profile: profile,
                homeDirectory: dependencies.homeDirectory,
                probe: dependencies.claudeProbe,
                ownProcesses: dependencies.ownProcesses,
                network: dependencies.network,
                sink: eventsContinuation,
                now: dependencies.now
            )
        case .codex:
            CodexAccountMonitor(
                profile: profile,
                homeDirectory: dependencies.homeDirectory,
                probe: dependencies.codexProbe,
                network: dependencies.network,
                sink: eventsContinuation,
                now: dependencies.now
            )
        }
    }

    /// Folds one monitor event into the state. Internal so tests can drive the engine deterministically.
    func handle(_ event: MonitorEvent) async {
        guard
            monitors[event.accountID] != nil,
            let index = state.accounts.firstIndex(where: { $0.id == event.accountID })
        else { return }

        let now = dependencies.now()
        recordHousekeeping(now: now)
        let previous = state
        var recordReading: UsageReading?
        switch event {
        case .refreshStarted:
            state.accounts[index].isRefreshing = true
            state.accounts[index].lastAttemptAt = dependencies.now()
        case .refreshFinished(_, let next):
            state.accounts[index].isRefreshing = false
            state.accounts[index].nextRefreshAt = next
        case .reading(_, let reading):
            if let merged = ReadingMerger.merge(
                current: state.accounts[index].reading,
                incoming: reading,
                now: dependencies.now()
            ) {
                state.accounts[index].reading = merged
                recordReading = merged
            }
        case .identity(_, let identity):
            state.accounts[index].identity = state.accounts[index].identity.map { $0.merging(identity) } ?? identity
        case .sessions(let accountID, let sessions):
            state.accounts[index].sessions = sessions
            recordSessions(sessions, accountID: accountID, now: now)
        case .issue(_, let issue):
            state.accounts[index].issue = issue
        case .tokenUsage(let accountID, let samples):
            // Token samples do not change `TrackerState`; they only feed usage attribution.
            recordTokens(samples, accountID: accountID, now: now)
            return
        }

        guard state != previous else { return }
        let alerts = evaluator.alerts(from: previous, to: state)
        publishState()
        if !alerts.isEmpty {
            updatesContinuation.yield(.alerts(alerts))
        }
        if case .reading = event {
            let resets = ResetDetector.resets(from: previous, to: state, at: now)
            if !resets.isEmpty {
                updatesContinuation.yield(.resets(resets))
            }
        }

        if let reading = recordReading, !isStopped {
            let account = state.accounts[index]
            recorder?.enqueue(.reading(reading, identity: account.identity, accountID: account.id))
        }
    }

    func publishState() {
        updatesContinuation.yield(.state(state))
    }
}

/// What a monitor works with. Two profiles with the same identity share a monitor, so label, group, tint and monogram
/// edits never restart one (monitors use only the id, provider, directory and poll interval).
struct MonitorIdentity: Hashable, Sendable {
    let provider: ProviderKind
    let directory: ProfileDirectory
    let isEnabled: Bool
    let pollInterval: PollInterval

    init(_ profile: AccountProfile) {
        provider = profile.provider
        directory = profile.directory
        isEnabled = profile.isEnabled
        pollInterval = profile.pollInterval
    }
}
