import CodometerCore
import Foundation

/// Turns successive session snapshots into session-segment writes.
///
/// A segment opens when a session enters working or waiting and closes when the session leaves that activity or
/// disappears. Writes happen only on transitions, so repeated identical snapshots cost nothing. Pure value type:
/// the engine owns one and forwards the returned writes to `HistoryRecorder`.
///
/// Times:
/// - a segment starts at the session's `activitySince`, but never before the recording `floor` (collection is
///   live: nothing is back-filled from before the monitor started or the Mac woke) and never after `now`;
/// - a segment that ends because the session changed activity ends at the new `activitySince` (clamped to
///   start…now); one whose session disappeared ends at `now`;
/// - if the same activity of the same session resumes within `resumeGap` of its previous segment's end, that
///   segment is reopened instead of starting a new one, so status flapping does not fragment lanes;
/// - a session's segments never overlap each other.
///
/// Segments never carry the session's own title, which can hold conversation content: they are labelled with the
/// project folder and the end of the session id (`SessionLabel.neutral`), and keep only the project's folder name.
struct SegmentTracker {
    static let resumeGap: TimeInterval = 3
    /// Open segments are marked as seen at most this often, so a crash loses at most about this much.
    static let touchInterval: TimeInterval = 60
    /// Closed segments are remembered this long for resume merging, then forgotten.
    static let closedMemory: TimeInterval = 5 * 60

    private struct Key: Hashable, Comparable {
        let accountID: AccountID
        let sessionID: String

        static func < (lhs: Key, rhs: Key) -> Bool {
            (lhs.accountID.description, lhs.sessionID) < (rhs.accountID.description, rhs.sessionID)
        }
    }

    /// A closed segment and its end, kept for resume merging.
    private struct Closed {
        let segment: SessionSegment
        let end: Date
    }

    private var open: [Key: SessionSegment] = [:]
    private var closed: [Key: Closed] = [:]
    private var lastTouch: Date?

    /// Segments currently open, ordered by account and session.
    var openSegments: [SessionSegment] {
        open.sorted { $0.key < $1.key }.map(\.value)
    }

    /// Applies one account's full session list observed at `now`.
    mutating func update(accountID: AccountID, sessions: [AgentSession], now: Date, floor: Date) -> [HistoryWrite] {
        var active: [String: AgentSession] = [:]
        var latest: [String: AgentSession] = [:]
        for session in sessions {
            if latest[session.id] == nil { latest[session.id] = session }
            if session.activity != .idle, active[session.id] == nil { active[session.id] = session }
        }

        var writes: [HistoryWrite] = []
        let wasEmpty = open.isEmpty

        for (key, segment) in open.sorted(by: { $0.key < $1.key }) where key.accountID == accountID {
            if active[key.sessionID]?.activity == segment.activity { continue }
            let proposed = latest[key.sessionID].map { min($0.activitySince, now) } ?? now
            writes.append(close(key, segment, at: proposed))
        }

        for session in sessions where active[session.id] == session {
            let key = Key(accountID: accountID, sessionID: session.id)
            if let current = open[key] {
                if let refreshed = renamed(current, to: session) {
                    open[key] = refreshed
                    writes.append(.openSegment(refreshed, lastSeen: now))
                }
                continue
            }
            if let write = start(key, session: session, now: now, floor: floor) {
                writes.append(write)
            }
        }

        if wasEmpty, !open.isEmpty {
            lastTouch = now
        }
        forgetClosed(before: now)
        return writes
    }

    /// Closes the open segments of one account (all accounts when `nil`) at `date`.
    mutating func closeAll(accountID: AccountID? = nil, at date: Date) -> [HistoryWrite] {
        open.sorted { $0.key < $1.key }
            .filter { accountID == nil || $0.key.accountID == accountID }
            .map { key, segment in close(key, segment, at: date) }
    }

    /// Drops everything known about an account without writing, e.g. once its history is deleted.
    mutating func forget(accountID: AccountID) {
        open = open.filter { $0.key.accountID != accountID }
        closed = closed.filter { $0.key.accountID != accountID }
    }

    /// A `last_seen` refresh for the open segments when the previous one is at least `touchInterval` old.
    mutating func touchIfDue(now: Date) -> HistoryWrite? {
        guard !open.isEmpty else { return nil }
        if let lastTouch, now.timeIntervalSince(lastTouch) < Self.touchInterval, now >= lastTouch {
            return nil
        }
        lastTouch = now
        return .touchOpenSegments(at: now)
    }

    // MARK: - Transitions

    private mutating func close(_ key: Key, _ segment: SessionSegment, at proposed: Date) -> HistoryWrite {
        let end = Self.milliseconds(max(segment.start, proposed))
        open[key] = nil
        closed[key] = Closed(segment: segment, end: end)
        return .closeSegment(segment, at: end)
    }

    private mutating func start(_ key: Key, session: AgentSession, now: Date, floor: Date) -> HistoryWrite? {
        var begin = min(max(session.activitySince, floor), now)
        if let previous = closed[key] {
            if previous.segment.activity == session.activity, begin.timeIntervalSince(previous.end) <= Self.resumeGap {
                let resumed = renamed(previous.segment, to: session) ?? previous.segment
                closed[key] = nil
                open[key] = resumed
                return .openSegment(resumed, lastSeen: now)
            }
            begin = max(begin, previous.end)
        }
        guard let segment = try? SessionSegment(
            accountID: key.accountID,
            sessionID: session.id,
            title: SessionLabel.neutral(sessionID: session.id, project: session.projectPath),
            project: SessionLabel.folder(of: session.projectPath),
            activity: session.activity,
            start: Self.milliseconds(begin),
            end: nil
        ) else { return nil }
        closed[key] = nil
        open[key] = segment
        return .openSegment(segment, lastSeen: now)
    }

    /// The segment with the session's current project (and so its label), or `nil` when it did not change.
    private func renamed(_ segment: SessionSegment, to session: AgentSession) -> SessionSegment? {
        guard let candidate = try? SessionSegment(
            accountID: segment.accountID,
            sessionID: segment.sessionID,
            title: SessionLabel.neutral(sessionID: segment.sessionID, project: session.projectPath),
            project: SessionLabel.folder(of: session.projectPath),
            activity: segment.activity,
            start: segment.start,
            end: nil
        ) else { return nil }
        return candidate.title == segment.title && candidate.project == segment.project ? nil : candidate
    }

    private mutating func forgetClosed(before now: Date) {
        guard closed.contains(where: { now.timeIntervalSince($0.value.end) > Self.closedMemory }) else { return }
        closed = closed.filter { now.timeIntervalSince($0.value.end) <= Self.closedMemory }
    }

    /// Stored times are whole milliseconds, so a segment's key round-trips through storage exactly.
    static func milliseconds(_ date: Date) -> Date {
        let seconds = date.timeIntervalSince1970
        guard seconds.isFinite else { return date }
        return Date(timeIntervalSince1970: (seconds * 1_000).rounded() / 1_000)
    }
}
