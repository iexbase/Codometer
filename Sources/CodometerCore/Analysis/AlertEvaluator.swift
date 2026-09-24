import Foundation

/// Identifies the window an alert is about.
public struct AlertWindowContext: Hashable, Sendable {
    public let accountID: AccountID
    public let bucketID: String
    public let bucketTitle: String?
    public let window: LimitWindow

    public init(accountID: AccountID, bucketID: String, bucketTitle: String?, window: LimitWindow) {
        self.accountID = accountID
        self.bucketID = bucketID
        self.bucketTitle = bucketTitle
        self.window = window
    }
}

public enum TrackerAlert: Hashable, Sendable {
    case thresholdReached(AlertWindowContext, threshold: Percentage)
    case limitReset(AlertWindowContext)
    /// A turn ended; `session.lastTurn` carries the timing of that turn when known, never an earlier turn's.
    case sessionFinished(accountID: AccountID, session: AgentSession)
    case sessionNeedsAttention(accountID: AccountID, session: AgentSession)
    /// A session stopped waiting (or disappeared while waiting). Silent: it only lets the presenter
    /// withdraw the "needs attention" notification.
    case sessionAttentionResolved(accountID: AccountID, session: AgentSession)

    /// Deterministic notification identifier, so a newer alert about the same thing replaces the older one:
    /// `session.<account>.<session>` or `limit.<account>.<bucket>.<window>`.
    public var notificationIdentifier: String {
        switch self {
        case let .thresholdReached(context, _), let .limitReset(context):
            "limit.\(context.accountID).\(context.bucketID).\(context.window.id)"
        case let .sessionFinished(accountID, session),
             let .sessionNeedsAttention(accountID, session),
             let .sessionAttentionResolved(accountID, session):
            "session.\(accountID).\(session.id)"
        }
    }

    /// Notifications are grouped per account.
    public var threadIdentifier: String { accountID.description }

    public var accountID: AccountID {
        switch self {
        case let .thresholdReached(context, _), let .limitReset(context):
            context.accountID
        case let .sessionFinished(accountID, _),
             let .sessionNeedsAttention(accountID, _),
             let .sessionAttentionResolved(accountID, _):
            accountID
        }
    }

    /// Silent alerts never show a notification, play a sound or open the island.
    public var isSilent: Bool {
        if case .sessionAttentionResolved = self { return true }
        return false
    }
}

/// Derives alerts from two consecutive tracker states.
///
/// Alerts come only from transitions between two observations, so launching the app,
/// adding an account or restoring a saved reading never produces a burst of stale alerts.
public struct AlertEvaluator: Sendable {
    /// A new window period moves the reset at least this far; smaller moves are source precision noise.
    public static let resetShiftTolerance: TimeInterval = ResetDetector.resetShiftTolerance
    /// A drop this large also means the window was reset, for sources without reset times.
    public static let resetDropPoints = ResetDetector.resetDropPoints
    /// Resets of nearly unused windows are not worth a notification.
    public static let minimumUsageWorthResetAlert = 5.0

    public let settings: AlertSettings
    /// Groups keyed by id, for the mutes of the account being evaluated.
    private let groups: [AccountGroupID: AccountGroup]

    /// An evaluator without account groups, so nothing is muted.
    public init(settings: AlertSettings) {
        self.settings = settings
        groups = [:]
    }

    /// An evaluator that also honours the session and usage mutes of each account's group, looked up through
    /// the `groupID` of the profiles in the evaluated states. Resolved events are never muted.
    public init(appSettings: AppSettings) {
        settings = appSettings.alerts
        groups = Dictionary(appSettings.groups.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public func alerts(from previous: TrackerState, to current: TrackerState) -> [TrackerAlert] {
        let currentIDs = Set(current.accounts.map(\.id))
        let continuing = current.accounts.flatMap { account -> [TrackerAlert] in
            guard let before = previous.account(account.id) else { return [] }
            let group = account.profile.groupID.flatMap { groups[$0] }
            let usage = group?.mutesUsageAlerts == true ? [] : usageAlerts(before: before, after: account)
            return usage + sessionAlerts(before: before, after: account, muted: group?.mutesSessionAlerts == true)
        }
        // Waiting sessions of an account that is gone can no longer resolve on their own.
        let removed = previous.accounts
            .filter { !currentIDs.contains($0.id) }
            .flatMap { account in
                account.sessions.filter { $0.activity == .waiting }.compactMap { resolved(account.id, $0) }
            }
        return continuing + removed
    }

    // MARK: - Usage

    private func usageAlerts(before: AccountStatus, after: AccountStatus) -> [TrackerAlert] {
        guard
            let oldReading = before.reading,
            let newReading = after.reading,
            newReading.capturedAt > oldReading.capturedAt
        else { return [] }

        return newReading.buckets.flatMap { bucket in
            bucket.windows.compactMap { window -> TrackerAlert? in
                guard let oldWindow = oldReading.bucket(id: bucket.id)?.window(id: window.id) else {
                    return nil
                }
                let context = AlertWindowContext(
                    accountID: after.id,
                    bucketID: bucket.id,
                    bucketTitle: bucket.title,
                    window: window
                )
                return usageAlert(from: oldWindow, to: window, context: context)
            }
        }
    }

    private func usageAlert(from oldWindow: LimitWindow, to window: LimitWindow, context: AlertWindowContext) -> TrackerAlert? {
        if ResetDetector.isReset(from: oldWindow, to: window) {
            guard settings.notifiesOnReset, oldWindow.used.value >= Self.minimumUsageWorthResetAlert else {
                return nil
            }
            return .limitReset(context)
        }
        guard let threshold = settings.thresholds.highestCrossed(from: oldWindow.used, to: window.used) else {
            return nil
        }
        return .thresholdReached(context, threshold: threshold)
    }

    // MARK: - Sessions

    private func sessionAlerts(before: AccountStatus, after: AccountStatus, muted: Bool) -> [TrackerAlert] {
        let previousByID = Dictionary(before.sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let currentIDs = Set(after.sessions.map(\.id))

        let transitions = after.sessions.flatMap { session -> [TrackerAlert] in
            guard let old = previousByID[session.id], old.activity != session.activity else { return [] }
            var alerts: [TrackerAlert] = []
            if old.activity == .waiting, let resolved = resolved(after.id, session) {
                alerts.append(resolved)
            }
            guard !muted else { return alerts }
            switch (old.activity, session.activity) {
            case (.working, .idle) where settings.notifiesOnSessionFinished:
                if !settings.minimumTurnForFinishedAlert.suppresses(turnDuration: Self.turnDuration(from: old, to: session)) {
                    alerts.append(.sessionFinished(accountID: after.id, session: Self.finishedSession(from: old, to: session)))
                }
            case (_, .waiting) where settings.notifiesOnSessionWaiting:
                alerts.append(.sessionNeedsAttention(accountID: after.id, session: session))
            default:
                break
            }
            return alerts
        }
        let vanished = before.sessions
            .filter { $0.activity == .waiting && !currentIDs.contains($0.id) }
            .compactMap { resolved(after.id, $0) }
        return transitions + vanished
    }

    private func resolved(_ accountID: AccountID, _ session: AgentSession) -> TrackerAlert? {
        settings.withdrawsResolvedAlerts ? .sessionAttentionResolved(accountID: accountID, session: session) : nil
    }

    /// Length of the turn that just finished: the session's own turn timing when it describes this turn
    /// (it ended after the previous observation's activity started), else the time between the two
    /// activity changes.
    static func turnDuration(from old: AgentSession, to new: AgentSession) -> TimeInterval {
        if let turn = currentTurn(from: old, to: new) {
            return turn.duration
        }
        return new.activitySince.timeIntervalSince(old.activitySince)
    }

    /// The session a «закончил» alert carries: its turn timing only when that timing describes the turn that just
    /// ended. A stale turn left over from an earlier one is removed, so the notification never shows wrong timing.
    static func finishedSession(from old: AgentSession, to new: AgentSession) -> AgentSession {
        guard new.lastTurn != nil, currentTurn(from: old, to: new) == nil else { return new }
        return new.removingLastTurn()
    }

    /// `new.lastTurn` when it ended after the previous observation's activity started, else `nil`.
    private static func currentTurn(from old: AgentSession, to new: AgentSession) -> TurnTiming? {
        guard let turn = new.lastTurn, turn.endedAt > old.activitySince else { return nil }
        return turn
    }
}
