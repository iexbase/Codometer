import CodometerCore
import Foundation

/// Tokens a rollout line reports as consumed, before deduplication across files.
struct CodexTokenObservation: Hashable, Sendable {
    let counts: TokenCounts
    /// `token_usage_record.response_id`; `nil` for `token_count` fallbacks.
    let responseID: String?
    let at: Date
}

/// What one rollout file says about its session, folded from parsed events. A pure value: no I/O, no clock.
struct CodexSessionState: Sendable {
    enum CallKind: Hashable, Sendable {
        /// A command that asks to leave the sandbox; the user may have to approve it.
        case escalation
        /// A `request_user_input` question.
        case userInput
    }

    struct PendingCall: Hashable, Sendable {
        let kind: CallKind
        let at: Date
    }

    private struct TurnStart: Hashable, Sendable {
        let turnID: String?
        let at: Date
    }

    /// An escalated call without output for this long is showing the user an approval prompt. Shorter waits are
    /// commands approved automatically (by policy or rules) and must not flash «ждёт подтверждения».
    static let approvalPromptDelay: TimeInterval = 2
    static let maximumPendingCalls = 64
    /// `lastEventAt` is published in whole steps of this size so a busy log does not republish sessions on every
    /// line; «нет активности» only needs minutes.
    static let activityGranularity: TimeInterval = 60

    static let permissionPromptDetail = "permission prompt"
    static let inputNeededDetail = "input needed"

    /// The thread the file belongs to, from its file name (`rollout-<time>-<thread id>.jsonl`).
    let threadID: String
    var sessionID: String
    var workingDirectory: String?
    var origin: SessionOrigin = .unknown
    var model: String?
    var approvalPolicy: String?
    var approvalsReviewer: String?
    var activity: AgentActivity = .idle
    var activitySince: Date
    var lastEventAt: Date
    private(set) var lastTurn: TurnTiming?
    private(set) var pendingCalls: [String: PendingCall] = [:]
    private(set) var hasTokenUsageRecords = false
    private var currentTurn: TurnStart?
    private var lastTokenCount: TokenCounts?

    /// - Parameter sessionID: the id from the file name, until `session_meta` says otherwise.
    init(sessionID: String, activitySince: Date, lastEventAt: Date) {
        threadID = sessionID
        self.sessionID = sessionID
        self.activitySince = activitySince
        self.lastEventAt = lastEventAt
    }

    /// A subagent's file: subagent threads log under their parent's session id, the parent under its own thread id.
    var isSubagentThread: Bool {
        threadID != sessionID
    }

    var hasPendingCalls: Bool {
        !pendingCalls.isEmpty
    }

    /// Whether an escalated call would stop for the user: the policy may ask and nobody else reviews.
    /// A turn context without a reviewer predates automatic review, so the user reviews.
    var asksUserForApproval: Bool {
        guard let approvalPolicy, approvalPolicy != "never" else { return false }
        return (approvalsReviewer ?? "user") == "user"
    }

    // MARK: - Events

    /// Folds one event into the state. Returns the tokens the event reports as newly consumed, if any.
    mutating func apply(_ event: CodexRolloutEvent) -> CodexTokenObservation? {
        switch event {
        case let .sessionStarted(sessionID, workingDirectory, originator, _, at):
            if let sessionID { self.sessionID = sessionID }
            self.workingDirectory = workingDirectory ?? self.workingDirectory
            if let originator { origin = Self.origin(forOriginator: originator) }
            touch(at)
        case let .turnContext(workingDirectory, _, model, _, approvalPolicy, approvalsReviewer, at):
            self.workingDirectory = workingDirectory ?? self.workingDirectory
            self.model = model ?? self.model
            self.approvalPolicy = approvalPolicy ?? self.approvalPolicy
            self.approvalsReviewer = approvalsReviewer ?? self.approvalsReviewer
            touch(at)
        case .rateLimits(_, let at):
            touch(at)
        case let .turnStarted(turnID, at):
            pendingCalls.removeAll()
            currentTurn = TurnStart(turnID: turnID, at: at)
            transition(to: .working, at: at)
        case let .turnCompleted(turnID, durationMs, firstTokenMs, at):
            finishTurn(turnID: turnID, durationMs: durationMs, firstTokenMs: firstTokenMs, aborted: false, at: at)
        case let .turnAborted(turnID, durationMs, _, at):
            finishTurn(turnID: turnID, durationMs: durationMs, firstTokenMs: nil, aborted: true, at: at)
        case let .tokenUsage(counts, responseID, at):
            hasTokenUsageRecords = true
            touch(at)
            return CodexTokenObservation(counts: counts, responseID: responseID, at: at)
        case let .tokenCountLast(counts, at):
            touch(at)
            // `token_usage_record` carries the same numbers with an id; the fallback only serves older logs.
            guard !hasTokenUsageRecords, counts != lastTokenCount else { return nil }
            lastTokenCount = counts
            return CodexTokenObservation(counts: counts, responseID: nil, at: at)
        case let .escalatedCallStarted(callID, at):
            addPendingCall(callID, kind: .escalation, at: at)
        case let .userInputRequested(callID, at):
            addPendingCall(callID, kind: .userInput, at: at)
        case let .callOutput(callID, at):
            pendingCalls[callID] = nil
            touch(at)
        }
        return nil
    }

    /// Records log activity seen at `date` (any line, not only parsed events).
    mutating func touch(_ date: Date) {
        lastEventAt = max(lastEventAt, date)
    }

    /// The file was replaced or truncated: whatever was in progress is unknown now.
    mutating func restart() {
        activity = .idle
        pendingCalls.removeAll()
        currentTurn = nil
    }

    // MARK: - Derived state

    /// The session as the app shows it at `now`, or `nil` when it has been idle too long to list.
    ///
    /// - Parameter latestActivity: activity seen in other files of the same session (a subagent), published as
    ///   `lastEventAt` when newer than this file's own.
    func session(now: Date, latestActivity: Date? = nil) -> AgentSession? {
        var activity = activity
        var since = activitySince
        var detail: String?
        let silence = now.timeIntervalSince(lastEventAt)
        if activity == .working {
            if let blocking = blockingCall(now: now), silence <= CodexSessionLogReader.staleWaitTimeout {
                activity = .waiting
                since = blocking.at
                detail = blocking.kind == .escalation ? Self.permissionPromptDetail : Self.inputNeededDetail
            } else if silence > CodexSessionLogReader.staleTurnTimeout {
                activity = .idle
                since = lastEventAt
            }
        }
        guard activity != .idle || now.timeIntervalSince(since) <= CodexSessionLogReader.idleSessionVisibility else {
            return nil
        }
        return try? AgentSession(
            id: sessionID,
            title: nil,
            projectPath: workingDirectory,
            activity: activity,
            detail: detail,
            activitySince: since,
            processID: nil,
            origin: origin,
            model: model,
            lastTurn: lastTurn,
            lastEventAt: Self.published(max(lastEventAt, latestActivity ?? .distantPast))
        )
    }

    /// The earliest pending call that blocks on the user at `now`.
    func blockingCall(now: Date) -> PendingCall? {
        guard activity == .working else { return nil }
        return pendingCalls.values
            .filter { call in
                switch call.kind {
                case .userInput: true
                case .escalation: asksUserForApproval && now.timeIntervalSince(call.at) >= Self.approvalPromptDelay
                }
            }
            .min { $0.at < $1.at }
    }

    /// When a pending escalated call will have waited `approvalPromptDelay`, if that is still ahead of `now`.
    func nextRecheck(now: Date) -> Date? {
        guard activity == .working, asksUserForApproval else { return nil }
        return pendingCalls.values
            .filter { $0.kind == .escalation }
            .map { $0.at.addingTimeInterval(Self.approvalPromptDelay) }
            .filter { $0 > now }
            .min()
    }

    /// `codex-tui` and `codex exec` run in a terminal; `Codex Desktop` is the desktop app.
    static func origin(forOriginator originator: String) -> SessionOrigin {
        switch originator {
        case "codex-tui", "codex_exec", "codex exec":
            .terminal
        case "Codex Desktop", "codex_work_desktop":
            .desktopApp
        default:
            .unknown
        }
    }

    static func published(_ lastEventAt: Date) -> Date? {
        guard lastEventAt != .distantPast else { return nil }
        let seconds = lastEventAt.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (seconds / activityGranularity).rounded(.down) * activityGranularity)
    }

    // MARK: - Transitions

    private mutating func addPendingCall(_ callID: String, kind: CallKind, at: Date) {
        touch(at)
        if pendingCalls[callID] == nil, pendingCalls.count >= Self.maximumPendingCalls,
           let oldest = pendingCalls.min(by: { $0.value.at < $1.value.at }) {
            pendingCalls[oldest.key] = nil
        }
        pendingCalls[callID] = PendingCall(kind: kind, at: at)
    }

    private mutating func finishTurn(turnID: String?, durationMs: Int64?, firstTokenMs: Int64?, aborted: Bool, at: Date) {
        pendingCalls.removeAll()
        let start = currentTurn
        currentTurn = nil
        let measured: TimeInterval? = if let durationMs {
            TimeInterval(durationMs) / 1_000
        } else if let start, turnID == nil || start.turnID == nil || start.turnID == turnID {
            at.timeIntervalSince(start.at)
        } else {
            nil
        }
        if at >= (lastTurn?.endedAt ?? .distantPast) {
            // A newer turn ended: its timing, or nothing when it cannot be measured — never the previous turn's.
            lastTurn = measured.flatMap { measured in
                let firstToken = firstTokenMs.map { TimeInterval($0) / 1_000 }.flatMap { $0 <= measured ? $0 : nil }
                return try? TurnTiming(
                    startedAt: at.addingTimeInterval(-measured),
                    endedAt: at,
                    duration: measured,
                    firstTokenLatency: firstToken,
                    wasAborted: aborted
                )
            }
        }
        transition(to: .idle, at: at)
    }

    private mutating func transition(to newActivity: AgentActivity, at date: Date) {
        guard date >= activitySince || lastEventAt == .distantPast || activity != newActivity else {
            return
        }
        if activity != newActivity {
            activitySince = date
        }
        activity = newActivity
        touch(date)
    }
}
