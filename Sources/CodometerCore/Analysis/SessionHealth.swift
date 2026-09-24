import Foundation

/// A hedged verdict on a live session: nothing is known to be wrong, but something looks unusual.
public enum SessionHealth: Hashable, Sendable {
    case normal
    /// Working, but nothing was written to the session's log since `since`.
    case quiet(since: Date)
    /// Working for an unusually long time.
    case longTurn
    /// Waiting for the user for a long time.
    case waitingLong

    /// A working session with no log activity for this long looks stuck.
    public static let quietAfter: TimeInterval = 6 * 60
    /// A turn running this long is unusually long.
    public static let longTurnAfter: TimeInterval = 25 * 60
    /// A session waiting this long has probably been forgotten.
    public static let waitingLongAfter: TimeInterval = 10 * 60
}

extension AgentSession {
    /// The session's health at `now`. Silence outranks a long turn: a quiet session is the likelier problem.
    public func health(now: Date) -> SessionHealth {
        switch activity {
        case .idle:
            return .normal
        case .waiting:
            return now.timeIntervalSince(activitySince) >= SessionHealth.waitingLongAfter ? .waitingLong : .normal
        case .working:
            if let lastEventAt, now.timeIntervalSince(lastEventAt) >= SessionHealth.quietAfter {
                return .quiet(since: lastEventAt)
            }
            return now.timeIntervalSince(activitySince) >= SessionHealth.longTurnAfter ? .longTurn : .normal
        }
    }
}
