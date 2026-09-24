import CodometerClaude
import CodometerCore
import CodometerPlatform
import Foundation

/// Watches one Claude Code profile.
///
/// - Sessions come from the profile's `sessions/` directory (file events plus a slow liveness rescan).
///   Turn timings are derived from their status transitions (`TurnTracker`).
/// - Token usage comes from the live sessions' transcripts under `projects/` (`ClaudeTranscriptUsageReader`),
///   which also tells when a session last wrote anything.
/// - Limits come from the official CLI on a schedule, plus one extra refresh shortly after a turn ends.
actor ClaudeAccountMonitor: AccountMonitor {
    static let livenessRescanInterval: TimeInterval = 20
    static let refreshDelayAfterTurn: TimeInterval = 8
    static let minimumGapBetweenRefreshes: TimeInterval = 90
    /// After this many outputs in a row without limit lines, stop until the binary changes or the user asks.
    static let formatFailureLimit = 3
    static let formatFailureCooldown: TimeInterval = 60 * 60
    static let offlineRetry: TimeInterval = 60
    static let missingExecutableRetry: TimeInterval = 30 * 60

    private let profile: AccountProfile
    private let layout: ClaudeProfileLayout
    private let probe: ClaudeUsageProbe
    private let scanner: ClaudeSessionScanner
    private let transcripts: ClaudeTranscriptUsageReader
    private let network: NetworkStatusMonitor
    private let sink: AsyncStream<MonitorEvent>.Continuation
    private let now: @Sendable () -> Date
    private let loop = RefreshLoop()

    private var sessions: [AgentSession] = []
    private var turnTracker = TurnTracker()
    /// Session id → newest transcript activity, folded into `sessions` as `lastEventAt`.
    private var transcriptActivity: [String: Date] = [:]
    private var isRescanning = false
    private var rescanPending = false
    private var identity: AccountIdentity?
    private var latestReading: UsageReading?
    private var consecutiveFailures = 0
    private var consecutiveFormatFailures = 0
    private var pausedUntilManualRefresh = false
    private var lastRefreshAt: Date?
    private var manualRequested = false
    private var isPaused = false
    private var isStopped = false
    /// Stretches scheduled refreshes and the liveness rescan; manual refreshes are never delayed.
    private var energyFactor = EnergyFactor.normal
    private var hasStarted = false
    /// Recent refresh attempts, for the Diagnostics pane (in memory only).
    private var ledger = ProbeLedger(kind: .claudeUsageCommand)
    /// What the CLI's output looked like compared with what this version expects.
    private var drift = FormatDrift()
    /// The moment the armed timer is due, so a lower energy factor can bring it forward.
    private var armedAt: Date?

    private var loopTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var watchTask: Task<Void, Never>?
    private var transcriptWatchTask: Task<Void, Never>?
    private var rescanTask: Task<Void, Never>?
    private var afterTurnTask: Task<Void, Never>?

    init(
        profile: AccountProfile,
        homeDirectory: URL,
        probe: ClaudeUsageProbe,
        ownProcesses: ChildProcessRegistry,
        network: NetworkStatusMonitor,
        sink: AsyncStream<MonitorEvent>.Continuation,
        now: @escaping @Sendable () -> Date
    ) {
        self.profile = profile
        layout = ClaudeProfileLayout(configDirectory: profile.directory.url, homeDirectory: homeDirectory)
        self.probe = probe
        scanner = ClaudeSessionScanner(layout: layout, ownProcesses: ownProcesses)
        transcripts = ClaudeTranscriptUsageReader(layout: layout, accountID: profile.id)
        self.network = network
        self.sink = sink
        self.now = now
    }

    func start() async {
        // Set before the first suspension, so a second `start` while the initial scan runs does nothing.
        guard !hasStarted, !isStopped else { return }
        hasStarted = true
        refreshIdentity()
        await rescanSessions()
        guard !isStopped else { return }

        let sessionsDirectory = layout.sessionsDirectory
        watchTask = Task { [weak self] in
            for await _ in DirectoryEvents.changes(in: [sessionsDirectory], latency: 0.3) {
                await self?.rescanSessions()
            }
        }
        let projectsDirectory = transcripts.projectsDirectory
        transcriptWatchTask = Task { [weak self] in
            let changes = DirectoryEvents.changes(
                in: [projectsDirectory],
                latency: ClaudeTranscriptUsageReader.eventLatency
            )
            for await paths in changes {
                await self?.processTranscripts(paths)
            }
        }
        rescanTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = await self?.livenessRescanDelay() else { return }
                try? await Task.sleep(for: .seconds(interval), tolerance: .seconds(interval * 0.25))
                await self?.rescanSessions()
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
        [loopTask, timerTask, watchTask, transcriptWatchTask, rescanTask, afterTurnTask].forEach { $0?.cancel() }
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
            lastLogReadingAt: nil,
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
        guard decreased, !isStopped, !isPaused, !pausedUntilManualRefresh, timerTask != nil else { return }
        guard let moved = RefreshTimerPlan.rearm(
            armedAt: armedAt,
            lastRefreshAt: lastRefreshAt,
            newDelay: successDelay(),
            now: now()
        ) else { return }
        arm(after: max(0, moved.timeIntervalSince(now())))
    }

    /// How long the liveness rescan sleeps under the current energy factor.
    func livenessRescanDelay() -> TimeInterval {
        Self.livenessRescanInterval * energyFactor.value
    }

    // MARK: - Refresh

    private func refresh() async {
        let manual = manualRequested
        manualRequested = false
        guard !isStopped, !isPaused || manual else { return }
        if pausedUntilManualRefresh && !manual {
            ledger.skip(.pausedAfterFormatDrift, at: now())
            return
        }
        if manual {
            pausedUntilManualRefresh = false
            drift.pausedUntilManualRefresh = false
        }

        guard network.isOnline else {
            ledger.skip(.offline, at: now())
            report(issue: .offline, detail: "no network connection")
            schedule(after: RefreshSchedule.scaled(Self.offlineRetry, by: energyFactor))
            return
        }

        sink.yield(.refreshStarted(profile.id))
        refreshIdentity()
        ledger.begin(at: now())
        do throws(ClaudeProbeError) {
            let probed = try await probe.fetchReport(layout: layout)
            lastRefreshAt = now()
            consecutiveFailures = 0
            consecutiveFormatFailures = 0
            latestReading = probed.reading
            ledger.end(at: now(), outcome: .reading(windowCount: Self.windowCount(of: probed.reading)))
            recordDrift(probed.stats)
            sink.yield(.reading(profile.id, probed.reading))
            sink.yield(.issue(profile.id, nil))
            schedule(after: successDelay())
        } catch {
            lastRefreshAt = now()
            consecutiveFailures += 1
            ledger.end(at: now(), outcome: .failure(error.issueKind))
            report(issue: error.issueKind, detail: error.description)
            schedule(after: failureDelay(for: error))
        }
    }

    /// How many limit windows one reading carries, for the probe ledger.
    static func windowCount(of reading: UsageReading) -> Int {
        reading.buckets.reduce(0) { $0 + $1.windows.count }
    }

    /// Folds one output's layout into the drift counters shown in Diagnostics.
    private func recordDrift(_ stats: ClaudeParseStats) {
        drift.consecutiveOutputsWithoutLimits = 0
        drift.pausedUntilManualRefresh = false
        guard !stats.genericTitles.isEmpty || stats.droppedInvalid > 0 else { return }
        for title in stats.genericTitles where !drift.unknownClaudeWindowTitles.contains(title) {
            drift.unknownClaudeWindowTitles.append(title)
        }
        drift.droppedInvalidLimitLines += stats.droppedInvalid
        drift.lastDriftAt = now()
    }

    /// The energy factor stretches the regular interval; the reset and urgency caps are applied afterwards, so a
    /// saving schedule still wakes up right after a reset and while a limit is nearly used up.
    private func successDelay() -> TimeInterval {
        var delay = RefreshSchedule.delay(interval: profile.pollInterval, consecutiveFailures: 0, jitter: unitJitter())
        if sessions.contains(where: { $0.activity == .working }) {
            delay = min(delay, profile.provider.minimumPollInterval.timeInterval)
        }
        delay = RefreshSchedule.scaled(delay, by: energyFactor)
        delay = RefreshSchedule.delay(delay, wakingForResetsIn: latestReading, now: now())
        return RefreshSchedule.delay(
            delay,
            urgentAbove: 90,
            cap: urgentCap(),
            reading: latestReading
        )
    }

    /// The ≥ 90 % cap, stretched by the gentler urgent-cap factor.
    private func urgentCap() -> TimeInterval {
        profile.provider.minimumPollInterval.timeInterval * RefreshSchedule.urgentCapFactor(for: energyFactor).value
    }

    private func failureDelay(for error: ClaudeProbeError) -> TimeInterval {
        if case .output(.noLimitLines) = error {
            consecutiveFormatFailures += 1
            drift.consecutiveOutputsWithoutLimits = consecutiveFormatFailures
            drift.lastDriftAt = now()
            if consecutiveFormatFailures >= Self.formatFailureLimit {
                // The CLI may have changed how it treats `/usage`; never risk turning it into a model prompt.
                pausedUntilManualRefresh = true
                drift.pausedUntilManualRefresh = true
                // Not scaled: the cooldown is longer than the schedule's own cap and the timer is disarmed anyway.
                return Self.formatFailureCooldown
            }
        } else {
            consecutiveFormatFailures = 0
            drift.consecutiveOutputsWithoutLimits = 0
        }
        if case .executable(.notFound) = error {
            return RefreshSchedule.scaled(Self.missingExecutableRetry, by: energyFactor)
        }
        return RefreshSchedule.scaled(
            RefreshSchedule.delay(
                interval: profile.pollInterval,
                consecutiveFailures: consecutiveFailures,
                jitter: unitJitter()
            ),
            by: energyFactor
        )
    }

    private func schedule(after delay: TimeInterval) {
        guard !pausedUntilManualRefresh else {
            timerTask?.cancel()
            timerTask = nil
            armedAt = nil
            sink.yield(.refreshFinished(profile.id, nextRefreshAt: nil))
            return
        }
        arm(after: delay)
    }

    /// (Re-)arms the refresh timer and publishes the new deadline.
    private func arm(after delay: TimeInterval) {
        timerTask?.cancel()
        timerTask = loop.arm(after: delay)
        armedAt = now().addingTimeInterval(delay)
        sink.yield(.refreshFinished(profile.id, nextRefreshAt: armedAt))
    }

    private func report(issue kind: TrackerIssue.Kind, detail: String) {
        sink.yield(.issue(profile.id, TrackerIssue(kind: kind, detail: detail, occurredAt: now())))
    }

    // MARK: - Identity and sessions

    private func refreshIdentity() {
        guard let current = try? ClaudeAccountReader.identity(for: layout), current != identity else { return }
        identity = current
        sink.yield(.identity(profile.id, current))
    }

    /// Rescans are serialised: a request that arrives while one awaits the transcript reader runs right after it.
    private func rescanSessions() async {
        guard !isStopped else { return }
        guard !isRescanning else {
            rescanPending = true
            return
        }
        isRescanning = true
        repeat {
            rescanPending = false
            let current = now()
            let scanned = scanner.scan(now: current)
            let liveIDs = Set(scanned.map(\.id))
            transcriptActivity = transcriptActivity.filter { liveIDs.contains($0.key) }
            let timed = turnTracker.apply(to: scanned, now: current)
            publish(SessionActivityFolding.fold(timed, activity: transcriptActivity, previous: sessions, now: current))
            let primed = await transcripts.track(scanned, now: current)
            // A session busy at launch: its transcripts' last write is its latest activity until new lines arrive.
            let primedLive = primed.filter { liveIDs.contains($0.key) }
            if !primedLive.isEmpty, !isStopped {
                for (id, date) in primedLive {
                    transcriptActivity[id] = transcriptActivity[id].map { max($0, date) } ?? date
                }
                publish(SessionActivityFolding.fold(sessions, activity: transcriptActivity, previous: sessions, now: now()))
            }
        } while rescanPending && !isStopped
        isRescanning = false
    }

    /// Emits the token usage of one burst of transcript writes and folds the activity into the sessions.
    private func processTranscripts(_ paths: Set<String>) async {
        guard !isStopped else { return }
        let update = await transcripts.process(changedPaths: paths, now: now())
        guard !isStopped, !update.isEmpty else { return }
        if !update.samples.isEmpty {
            sink.yield(.tokenUsage(profile.id, update.samples))
        }
        let liveIDs = Set(sessions.map(\.id))
        for (id, date) in update.lastEventAt where liveIDs.contains(id) {
            transcriptActivity[id] = transcriptActivity[id].map { max($0, date) } ?? date
        }
        guard !update.lastEventAt.isEmpty else { return }
        publish(SessionActivityFolding.fold(sessions, activity: transcriptActivity, previous: sessions, now: now()))
    }

    private func publish(_ updated: [AgentSession]) {
        guard updated != sessions else { return }
        let turnEnded = sessions.contains { old in
            old.activity == .working && updated.first(where: { $0.id == old.id })?.activity != .working
        }
        sessions = updated
        sink.yield(.sessions(profile.id, updated))
        if turnEnded {
            scheduleRefreshAfterTurn()
        }
    }

    /// Usage changes most right after a turn, so refresh then — but never more often than every 90 s.
    private func scheduleRefreshAfterTurn() {
        guard afterTurnTask == nil, !isPaused, !pausedUntilManualRefresh else { return }
        let sinceLast = lastRefreshAt.map { now().timeIntervalSince($0) } ?? .infinity
        // The 8 s delay stays; only the minimum gap between refreshes follows the energy factor (item 19).
        let gap = Self.minimumGapBetweenRefreshes * energyFactor.value
        let wait = max(Self.refreshDelayAfterTurn, gap - sinceLast)
        afterTurnTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait), tolerance: .seconds(2))
            await self?.fireAfterTurnRefresh()
        }
    }

    private func fireAfterTurnRefresh() {
        afterTurnTask = nil
        guard !Task.isCancelled, !isStopped else { return }
        loop.fire()
    }
}
