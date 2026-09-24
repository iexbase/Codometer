import CodometerCore
import Foundation

/// Derives Claude Code turn timings from session status transitions.
///
/// Claude Code's session records carry no turn events, only the current status and when it last changed.
/// A turn starts when a session enters `working` (the record's `activitySince`) and ends when it returns to
/// `idle`. Waiting for a permission prompt in between is part of the same turn. The first-token latency is
/// not observable from status files, so it stays `nil`.
///
/// Pure value type: the monitor owns one and feeds it every scan.
public struct TurnTracker: Sendable {
    /// Session id → when its open turn started.
    private var openTurns: [String: Date] = [:]
    /// Session id → the most recent finished turn, kept until the next one ends.
    private var lastTurns: [String: TurnTiming] = [:]

    public init() {}

    /// Advances the tracker with one scan and returns the sessions with `lastTurn` attached.
    ///
    /// Sessions missing from `sessions` have ended; everything known about them is forgotten.
    public mutating func apply(to sessions: [AgentSession], now: Date) -> [AgentSession] {
        let liveIDs = Set(sessions.map(\.id))
        openTurns = openTurns.filter { liveIDs.contains($0.key) }
        lastTurns = lastTurns.filter { liveIDs.contains($0.key) }

        for session in sessions {
            switch session.activity {
            case .working:
                if openTurns[session.id] == nil {
                    openTurns[session.id] = min(session.activitySince, now)
                }
            case .waiting:
                // A prompt mid-turn keeps the turn open; a session first seen waiting has an unknown start.
                break
            case .idle:
                guard let startedAt = openTurns.removeValue(forKey: session.id) else { break }
                if let timing = Self.timing(startedAt: startedAt, idleSince: session.activitySince, now: now) {
                    lastTurns[session.id] = timing
                }
            }
        }

        return sessions.map { session in
            guard let turn = lastTurns[session.id], turn != session.lastTurn else { return session }
            return SessionRebuild.session(session, lastTurn: turn, lastEventAt: session.lastEventAt)
        }
    }

    /// The last finished turn of a live session, if one was observed.
    public func lastTurn(sessionID: String) -> TurnTiming? {
        lastTurns[sessionID]
    }

    /// Whether a turn of the session is currently open.
    public func hasOpenTurn(sessionID: String) -> Bool {
        openTurns[sessionID] != nil
    }

    /// The turn from `startedAt` to the idle record's timestamp, or to `now` when that timestamp is not later
    /// than the start (a record without a status time). `nil` for implausible lengths.
    static func timing(startedAt: Date, idleSince: Date, now: Date) -> TurnTiming? {
        let endedAt = idleSince > startedAt ? min(idleSince, max(now, startedAt)) : now
        let duration = endedAt.timeIntervalSince(startedAt)
        return try? TurnTiming(
            startedAt: startedAt,
            endedAt: endedAt,
            duration: duration,
            firstTokenLatency: nil,
            wasAborted: false
        )
    }
}

/// Folds the newest known activity time into sessions without churning the published state.
///
/// Transcript writes arrive every few seconds while an agent works. `lastEventAt` only feeds hedged health
/// hints measured in minutes, so it advances in steps of `granularity`; smaller moves keep the previously
/// published value and the session compares equal, so no state update is sent.
public enum SessionActivityFolding {
    public static let granularity: TimeInterval = 30

    /// - Parameters:
    ///   - sessions: the current sessions, with the record's own `lastEventAt`.
    ///   - activity: session id → newest transcript activity.
    ///   - previous: the sessions published last time.
    public static func fold(
        _ sessions: [AgentSession],
        activity: [String: Date],
        previous: [AgentSession],
        now: Date
    ) -> [AgentSession] {
        let published = Dictionary(previous.map { ($0.id, $0.lastEventAt) }, uniquingKeysWith: { first, _ in first })
        return sessions.map { session in
            let candidate = newest(session.lastEventAt, activity[session.id]).map { min($0, now) }
            let value = folded(candidate: candidate, published: published[session.id] ?? nil)
            guard value != session.lastEventAt else { return session }
            return SessionRebuild.session(session, lastTurn: session.lastTurn, lastEventAt: value)
        }
    }

    /// The published value unless the candidate moved it forward by at least `granularity`.
    static func folded(candidate: Date?, published: Date?) -> Date? {
        guard let candidate else { return published }
        guard let published else { return candidate }
        return candidate.timeIntervalSince(published) >= granularity ? candidate : published
    }

    static func newest(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (left?, right?): max(left, right)
        case let (left?, nil): left
        case let (nil, right?): right
        case (nil, nil): nil
        }
    }
}

/// Rebuilds a session through its validating initialiser with new derived fields.
enum SessionRebuild {
    static func session(_ session: AgentSession, lastTurn: TurnTiming?, lastEventAt: Date?) -> AgentSession {
        (try? AgentSession(
            id: session.id,
            title: session.title,
            projectPath: session.projectPath,
            activity: session.activity,
            detail: session.detail,
            activitySince: session.activitySince,
            processID: session.processID,
            origin: session.origin,
            model: session.model,
            lastTurn: lastTurn,
            lastEventAt: lastEventAt
        )) ?? session
    }
}
