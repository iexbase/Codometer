import CodometerCodex
import CodometerCore
import CodometerPlatform
import Foundation

/// Watches one Codex profile.
///
/// - Session logs give sessions, token usage and near-instant limits while Codex is working.
/// - `codex app-server` gives all buckets on a schedule, including when Codex is idle.
actor CodexAccountMonitor: AccountMonitor {
    static let sessionRecomputeInterval: TimeInterval = 30
    /// A one-shot recheck fires this long after the moment the reader asked for, so the threshold is crossed.
    static let recheckSlack: TimeInterval = 0.15
    /// While the logs delivered limits this recently, a live refresh adds little.
    static let freshLogWindow: TimeInterval = 60
    static let maximumLiveGap: TimeInterval = 5 * 60
    static let signedOutRetry: TimeInterval = 10 * 60
    static let offlineRetry: TimeInterval = 60
    static let missingExecutableRetry: TimeInterval = 30 * 60

    private let profile: AccountProfile
    private let layout: CodexProfileLayout
    private let probe: CodexAppServerProbe
    private let reader: CodexSessionLogReader
    private let network: NetworkStatusMonitor
    private let sink: AsyncStream<MonitorEvent>.Continuation
    private let now: @Sendable () -> Date
    private let loop = RefreshLoop()

    private var sessions: [AgentSession] = []
    private var identity: AccountIdentity?
    private var latestReading: UsageReading?
    private var lastLogReadingAt: Date?
    private var lastLiveRefreshAt: Date?
    private var consecutiveFailures = 0
    private var isSignedOut = false
    private var authFileMetadata: FileMetadata?
    private var manualRequested = false
    private var isPaused = false
    private var isStopped = false
    /// Stretches scheduled refreshes and the periodic session recompute; manual refreshes are never delayed.
    private var energyFactor = EnergyFactor.normal
    /// Recent refresh attempts, for the Diagnostics pane (in memory only).
    private var ledger = ProbeLedger(kind: .codexAppServer)
    /// What the session logs and the app server showed that this version does not understand.
    private var drift = FormatDrift()
    /// The moment the armed timer is due, so a lower energy factor can bring it forward.
    private var armedAt: Date?

    private var loopTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var watchTask: Task<Void, Never>?
    private var recomputeTask: Task<Void, Never>?
    private var recheckTask: Task<Void, Never>?
    /// The moment the armed recheck is for, and the latest moment a recheck already ran for.
    private var recheckAt: Date?
    private var lastRecheckFiredFor: Date?
    /// The newest reader snapshot applied so far.
    private var appliedGeneration: UInt64 = 0

    init(
        profile: AccountProfile,
        homeDirectory: URL,
        probe: CodexAppServerProbe,
        network: NetworkStatusMonitor,
        sink: AsyncStream<MonitorEvent>.Continuation,
        now: @escaping @Sendable () -> Date
    ) {
        self.profile = profile
        layout = CodexProfileLayout(home: profile.directory.url, homeDirectory: homeDirectory)
        self.probe = probe
        reader = CodexSessionLogReader(layout: layout, accountID: profile.id)
        self.network = network
        self.sink = sink
        self.now = now
    }

    func start() async {
        guard loopTask == nil, !isStopped else { return }
        apply(await reader.bootstrap(now: now()))

        let reader = reader
        let now = now
        let sessionsDirectory = layout.sessionsDirectory
        watchTask = Task { [weak self] in
            for await paths in DirectoryEvents.changes(in: [sessionsDirectory], latency: 1.0) {
                let snapshot = await reader.process(changedPaths: paths, now: now())
                await self?.apply(snapshot)
            }
        }
        recomputeTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = await self?.sessionRecomputeDelay() else { return }
                try? await Task.sleep(for: .seconds(interval), tolerance: .seconds(interval * 0.25))
                let snapshot = await reader.snapshot(now: now())
                await self?.apply(snapshot)
            }
        }
        let triggers = loop.triggers
        loopTask = Task { [weak self] in
            for await _ in triggers {
                await self?.refresh()
            }
        }
        loop.fire()
    }

    func stop() {
        isStopped = true
        armedAt = nil
        [loopTask, timerTask, watchTask, recomputeTask, recheckTask].forEach { $0?.cancel() }
        recheckTask = nil
        loop.finish()
    }

    func refreshNow() {
        manualRequested = true
        loop.fire()
    }

    func setPaused(_ paused: Bool) {
        let wasPaused = isPaused
        isPaused = paused
        if wasPaused && !paused {
            loop.fire()
        }
    }

    func diagnostics() -> AccountDiagnostics {
        AccountDiagnostics(
            accountID: profile.id,
            provider: profile.provider,
            recentProbes: ledger.records,
            lastLogReadingAt: lastLogReadingAt,
            nextRefreshAt: armedAt,
            consecutiveFailures: consecutiveFailures,
            energyFactor: energyFactor.value,
            drift: drift
        )
    }

    /// A lower factor may bring the armed refresh forward (`RefreshTimerPlan.rearm`); a higher one never postpones a
    /// refresh that is already armed.
    func setEnergyFactor(_ factor: EnergyFactor) {
        guard factor != energyFactor else { return }
        let decreased = factor < energyFactor
        energyFactor = factor
        guard decreased, !isStopped, !isPaused, timerTask != nil else { return }
        guard let moved = RefreshTimerPlan.rearm(
            armedAt: armedAt,
            lastRefreshAt: lastLiveRefreshAt,
            newDelay: successDelay(),
            now: now()
        ) else { return }
        schedule(after: max(0, moved.timeIntervalSince(now())))
    }

    /// How long the periodic session recompute sleeps under the current energy factor.
    func sessionRecomputeDelay() -> TimeInterval {
        Self.sessionRecomputeInterval * energyFactor.value
    }

    // MARK: - Session logs

    private func apply(_ snapshot: CodexLogSnapshot) {
        guard !isStopped else { return }
        recordDrift(snapshot.statistics)
        // Samples are drained into exactly one snapshot, so they are delivered whatever its age.
        if !snapshot.tokenSamples.isEmpty {
            sink.yield(.tokenUsage(profile.id, snapshot.tokenSamples))
        }
        // The watcher, the periodic recompute and the recheck take snapshots concurrently and can deliver them out of
        // order; an older snapshot must not roll sessions back or disarm the recheck a newer one asked for.
        guard snapshot.generation > appliedGeneration else { return }
        appliedGeneration = snapshot.generation
        if snapshot.sessions != sessions {
            sessions = snapshot.sessions
            sink.yield(.sessions(profile.id, snapshot.sessions))
        }
        if let reading = snapshot.reading, reading.capturedAt > (lastLogReadingAt ?? .distantPast) {
            lastLogReadingAt = reading.capturedAt
            latestReading = reading
            sink.yield(.reading(profile.id, reading))
        }
        if let plan = CodexLimitMapper.planName(snapshot.planType) {
            publish(identity: AccountIdentity(email: nil, organization: nil, plan: plan))
        }
        scheduleRecheck(at: snapshot.needsRecheckAt)
    }

    /// Folds the reader's counters into the drift shown in Diagnostics. Unknown event types and skipped oversized
    /// lines are routine (Codex adds event types often), so they never raise the severity on their own.
    private func recordDrift(_ statistics: CodexReaderStatistics) {
        let changed = statistics.unknownEventTypes != drift.codexUnknownEventTypes
            || statistics.oversizedLinesSkipped != drift.codexOversizedLinesSkipped
        guard changed else { return }
        // Snapshots can arrive out of order, and the reader's counters only ever grow.
        drift.codexUnknownEventTypes = max(drift.codexUnknownEventTypes, statistics.unknownEventTypes)
        drift.codexOversizedLinesSkipped = max(drift.codexOversizedLinesSkipped, statistics.oversizedLinesSkipped)
        drift.lastDriftAt = now()
    }

    /// Arms a single recompute for the moment a pending approval turns into a prompt, so «ждёт подтверждения»
    /// shows up about two seconds after the call instead of at the next periodic recompute. A newer snapshot
    /// replaces the armed recheck; there is never more than one and it never repeats.
    private func scheduleRecheck(at date: Date?) {
        guard date != recheckAt else { return }
        recheckTask?.cancel()
        recheckTask = nil
        recheckAt = nil
        // A recheck that already ran for this moment and still sees it ahead (a clock that did not move) must not
        // spin; the periodic recompute takes over.
        guard let date, !isStopped, date > (lastRecheckFiredFor ?? .distantPast) else { return }
        recheckAt = date
        let delay = max(date.timeIntervalSince(now()), 0) + Self.recheckSlack
        let reader = reader
        let now = now
        recheckTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay), tolerance: .milliseconds(100))
            guard !Task.isCancelled else { return }
            let snapshot = await reader.snapshot(now: now())
            await self?.recheckFired(for: date, snapshot: snapshot)
        }
    }

    private func recheckFired(for date: Date, snapshot: CodexLogSnapshot) {
        if recheckAt == date {
            recheckTask = nil
            recheckAt = nil
            lastRecheckFiredFor = date
        }
        // Also when replaced meanwhile: the snapshot's samples are delivered, and a stale snapshot changes nothing else.
        apply(snapshot)
    }

    // MARK: - Live refresh

    private func refresh() async {
        let manual = manualRequested
        manualRequested = false
        guard !isStopped, !isPaused || manual else { return }

        if !manual {
            if isSignedOut, !authFileChanged() {
                ledger.skip(.signedOutWait, at: now())
                schedule(after: RefreshSchedule.scaled(Self.signedOutRetry, by: energyFactor))
                return
            }
            if logsAreFresh() {
                ledger.skip(.logsFresh, at: now())
                schedule(after: RefreshSchedule.scaled(profile.pollInterval.timeInterval, by: energyFactor))
                return
            }
        }
        guard network.isOnline else {
            ledger.skip(.offline, at: now())
            report(issue: .offline, detail: "no network connection")
            schedule(after: RefreshSchedule.scaled(Self.offlineRetry, by: energyFactor))
            return
        }

        sink.yield(.refreshStarted(profile.id))
        ledger.begin(at: now())
        do throws(CodexProbeError) {
            let result = try await probe.fetch(layout: layout)
            lastLiveRefreshAt = now()
            consecutiveFailures = 0
            isSignedOut = false
            latestReading = result.reading
            ledger.end(at: now(), outcome: .reading(windowCount: Self.windowCount(of: result.reading)))
            sink.yield(.reading(profile.id, result.reading))
            if let identity = result.identity {
                publish(identity: identity)
            }
            sink.yield(.issue(profile.id, nil))
            schedule(after: successDelay())
        } catch {
            consecutiveFailures += 1
            ledger.end(at: now(), outcome: .failure(error.issueKind))
            if case .unexpectedResponse = error {
                drift.codexUnexpectedResponses += 1
                drift.lastDriftAt = now()
            }
            report(issue: error.issueKind, detail: error.description)
            schedule(after: failureDelay(for: error))
        }
    }

    /// How many limit windows one reading carries, for the probe ledger.
    static func windowCount(of reading: UsageReading) -> Int {
        reading.buckets.reduce(0) { $0 + $1.windows.count }
    }

    private func logsAreFresh() -> Bool {
        guard
            let lastLog = lastLogReadingAt,
            now().timeIntervalSince(lastLog) < Self.freshLogWindow,
            let lastLive = lastLiveRefreshAt
        else { return false }
        return now().timeIntervalSince(lastLive) < Self.maximumLiveGap
    }

    private func authFileChanged() -> Bool {
        let current = SecureFileIO.metadata(at: layout.home.appendingPathComponent("auth.json", isDirectory: false))
        return current != authFileMetadata
    }

    /// The energy factor stretches the regular interval; the reset and urgency caps are applied afterwards, so a
    /// saving schedule still wakes up right after a reset and while a limit is nearly used up.
    private func successDelay() -> TimeInterval {
        let delay = RefreshSchedule.delay(interval: profile.pollInterval, consecutiveFailures: 0, jitter: unitJitter())
        let scaled = RefreshSchedule.scaled(delay, by: energyFactor)
        let resetAware = RefreshSchedule.delay(scaled, wakingForResetsIn: latestReading, now: now())
        return RefreshSchedule.delay(
            resetAware,
            urgentAbove: 90,
            cap: profile.provider.minimumPollInterval.timeInterval
                * RefreshSchedule.urgentCapFactor(for: energyFactor).value,
            reading: latestReading
        )
    }

    private func failureDelay(for error: CodexProbeError) -> TimeInterval {
        switch error {
        case .signedOut:
            isSignedOut = true
            authFileMetadata = SecureFileIO.metadata(at: layout.home.appendingPathComponent("auth.json", isDirectory: false))
            return RefreshSchedule.scaled(Self.signedOutRetry, by: energyFactor)
        case .executable(.notFound):
            return RefreshSchedule.scaled(Self.missingExecutableRetry, by: energyFactor)
        default:
            return RefreshSchedule.scaled(
                RefreshSchedule.delay(
                    interval: profile.pollInterval,
                    consecutiveFailures: consecutiveFailures,
                    jitter: unitJitter()
                ),
                by: energyFactor
            )
        }
    }

    private func schedule(after delay: TimeInterval) {
        timerTask?.cancel()
        timerTask = loop.arm(after: delay)
        armedAt = now().addingTimeInterval(delay)
        sink.yield(.refreshFinished(profile.id, nextRefreshAt: armedAt))
    }

    private func report(issue kind: TrackerIssue.Kind, detail: String) {
        sink.yield(.issue(profile.id, TrackerIssue(kind: kind, detail: detail, occurredAt: now())))
    }

    private func publish(identity newIdentity: AccountIdentity) {
        let merged = identity.map { $0.merging(newIdentity) } ?? newIdentity
        guard merged != identity else { return }
        identity = merged
        sink.yield(.identity(profile.id, merged))
    }
}
