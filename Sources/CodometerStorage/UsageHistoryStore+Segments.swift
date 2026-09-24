import CodometerCore
import Foundation

/// Session segments: the working and waiting stretches the timeline draws as lanes.
///
/// A segment is keyed by account, session, activity and start. Writes happen only on transitions (open, close)
/// plus a `last_seen` refresh at most about once a minute while segments are open, so a segment left open by a
/// crash can later be closed where it was last known to be active (`closeDanglingSegments`).
///
/// A session's own title is never stored: it can carry conversation content. Rows keep the project folder (not the
/// full path), a title made from it and the end of the session id (`SessionLabel.neutral`), and reads rebuild that
/// title from the id and folder, so a row from an older version can never show a stored name.
extension UsageHistoryStore {
    /// Stores the segment as open, or reopens it when a segment with the same key exists (a resumed activity).
    /// Project and label are refreshed; `segment.title` and `segment.end` are ignored.
    public func openSegment(_ segment: SessionSegment, lastSeen: Date) throws(SQLiteError) {
        guard let activity = Self.storedActivity(segment.activity) else { return }
        let start = Self.storedSeconds(segment.start)
        try writing { () throws(SQLiteError) in
            try self.connection.prepare("""
                INSERT INTO session_segments
                (account_id, session_id, title, project, activity, started_at, ended_at, last_seen)
                VALUES (?, ?, ?, ?, ?, ?, NULL, ?)
                ON CONFLICT (account_id, session_id, activity, started_at) DO UPDATE SET
                    title = excluded.title,
                    project = excluded.project,
                    ended_at = NULL,
                    last_seen = MAX(session_segments.last_seen, excluded.last_seen)
                """)
                .run([
                    .text(segment.accountID.description),
                    .text(segment.sessionID),
                    .text(Self.storedTitle(segment)),
                    Self.storedProject(segment.project).map { .text($0) } ?? .null,
                    .text(activity),
                    .real(start),
                    .real(max(start, Self.storedSeconds(lastSeen))),
                ])
        }
    }

    /// Closes the segment at `end` (never before its start). A segment whose open write was lost is stored
    /// closed, so the stretch is not missing from the timeline. `segment.title` is ignored.
    public func closeSegment(_ segment: SessionSegment, at end: Date) throws(SQLiteError) {
        guard let activity = Self.storedActivity(segment.activity) else { return }
        let start = Self.storedSeconds(segment.start)
        let clampedEnd = max(start, Self.storedSeconds(end))
        try writing { () throws(SQLiteError) in
            try self.connection.prepare("""
                INSERT INTO session_segments
                (account_id, session_id, title, project, activity, started_at, ended_at, last_seen)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT (account_id, session_id, activity, started_at) DO UPDATE SET
                    ended_at = excluded.ended_at,
                    last_seen = excluded.last_seen
                """)
                .run([
                    .text(segment.accountID.description),
                    .text(segment.sessionID),
                    .text(Self.storedTitle(segment)),
                    Self.storedProject(segment.project).map { .text($0) } ?? .null,
                    .text(activity),
                    .real(start),
                    .real(clampedEnd),
                    .real(clampedEnd),
                ])
        }
    }

    /// Records that an open segment was still active at `date`.
    public func touchSegment(_ segment: SessionSegment, at date: Date) throws(SQLiteError) {
        guard let activity = Self.storedActivity(segment.activity) else { return }
        try writing { () throws(SQLiteError) in
            try self.connection.prepare("""
                UPDATE session_segments SET last_seen = MAX(started_at, ?)
                WHERE account_id = ? AND session_id = ? AND activity = ? AND started_at = ? AND ended_at IS NULL
                """)
                .run([
                    .real(Self.storedSeconds(date)),
                    .text(segment.accountID.description),
                    .text(segment.sessionID),
                    .text(activity),
                    .real(Self.storedSeconds(segment.start)),
                ])
        }
    }

    /// Records that every open segment (of one account, or of all when `nil`) was still active at `date`.
    public func touchOpenSegments(accountID: AccountID? = nil, at date: Date) throws(SQLiteError) {
        let seconds = SQLiteValue.real(Self.storedSeconds(date))
        try writing { () throws(SQLiteError) in
            if let accountID {
                try self.connection.prepare("""
                    UPDATE session_segments SET last_seen = MAX(started_at, ?)
                    WHERE account_id = ? AND ended_at IS NULL
                    """)
                    .run([seconds, .text(accountID.description)])
            } else {
                try self.connection.prepare("UPDATE session_segments SET last_seen = MAX(started_at, ?) WHERE ended_at IS NULL")
                    .run([seconds])
            }
        }
    }

    /// Closes every open segment (of one account, or of all when `nil`) at `date`, never before a segment's
    /// start. Returns how many segments were closed.
    @discardableResult
    public func closeOpenSegments(accountID: AccountID? = nil, at date: Date) throws(SQLiteError) -> Int {
        let seconds = SQLiteValue.real(Self.storedSeconds(date))
        return try writing { () throws(SQLiteError) -> Int in
            if let accountID {
                try self.connection.prepare("""
                    UPDATE session_segments SET ended_at = MAX(started_at, ?), last_seen = MAX(started_at, ?)
                    WHERE account_id = ? AND ended_at IS NULL
                    """)
                    .run([seconds, seconds, .text(accountID.description)])
            } else {
                try self.connection.prepare("""
                    UPDATE session_segments SET ended_at = MAX(started_at, ?), last_seen = MAX(started_at, ?)
                    WHERE ended_at IS NULL
                    """)
                    .run([seconds, seconds])
            }
            return self.connection.changes
        } ?? 0
    }

    /// Closes segments a previous run left open (it quit without closing them) where they were last seen.
    /// Call before recording starts. Returns how many segments were closed.
    @discardableResult
    public func closeDanglingSegments() throws(SQLiteError) -> Int {
        try writing { () throws(SQLiteError) -> Int in
            try self.connection.prepare("""
                UPDATE session_segments SET ended_at = MAX(started_at, last_seen)
                WHERE ended_at IS NULL
                """)
                .run([])
            return self.connection.changes
        } ?? 0
    }

    /// Segments of the account overlapping `interval` (open ones have `end == nil`), ascending by start.
    /// At most `maximumRows`, the latest-starting ones; rows that fail validation are skipped.
    public func segments(accountID: AccountID, interval: DateInterval) throws(SQLiteError) -> [SessionSegment] {
        let query = try connection.prepare("""
            SELECT session_id, title, project, activity, started_at, ended_at FROM session_segments
            WHERE account_id = ? AND started_at <= ? AND (ended_at IS NULL OR ended_at >= ?)
            ORDER BY started_at DESC, session_id DESC, activity DESC
            LIMIT ?
            """)
        try query.bind([
            .text(accountID.description),
            .real(Self.storedSeconds(interval.end)),
            .real(Self.storedSeconds(interval.start)),
            .integer(Int64(Self.maximumRows)),
        ])
        var segments: [SessionSegment] = []
        while try query.step() {
            guard
                let sessionID = query.text(0),
                let activity = query.text(3).flatMap(AgentActivity.init(rawValue:)),
                let start = query.double(4)
            else { continue }
            let project = Self.storedProject(query.text(2))
            let segment = try? SessionSegment(
                accountID: accountID,
                sessionID: sessionID,
                title: SessionLabel.neutral(sessionID: sessionID, project: project),
                project: project,
                activity: activity,
                start: Date(timeIntervalSince1970: start),
                end: query.double(5).map { Date(timeIntervalSince1970: $0) }
            )
            if let segment {
                segments.append(segment)
            }
        }
        return segments.reversed()
    }

    // MARK: - Values

    /// Only working and waiting time is stored; `SessionSegment` already rejects idle.
    private static func storedActivity(_ activity: AgentActivity) -> String? {
        activity == .idle ? nil : activity.rawValue
    }

    /// The label stored instead of the session's title: its project folder and the end of its id.
    private static func storedTitle(_ segment: SessionSegment) -> String {
        DisplayText.sanitize(
            SessionLabel.neutral(sessionID: segment.sessionID, project: storedProject(segment.project)),
            maximumLength: AgentSession.maximumTitleLength
        ) ?? "—"
    }

    /// Only the project's folder name is stored, never the full path (which names the user's home folder).
    static func storedProject(_ project: String?) -> String? {
        SessionLabel.folder(of: project)
    }
}
