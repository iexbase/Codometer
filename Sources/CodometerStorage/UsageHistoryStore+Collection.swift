import CodometerCore
import Foundation

/// When live collection of segments and token usage ran per account.
///
/// Segments and tokens are collected live only, so a range that begins before collection started is partly
/// unknown. Remembering the first start lets views show "data since HH:mm" for that case only, instead of for every
/// quiet stretch before the first recorded activity. Every later start (a launch, a wake from sleep, an account
/// enabled again) begins a new collection run, so attribution can tell usage measured while tokens were collected
/// from usage while the app was not running.
///
/// A run also records when it ended and why (quit, sleep, account turned off, or closed as a crash on the next
/// launch) plus a heartbeat, so the timeline can hatch the stretches where nothing could be collected.
extension UsageHistoryStore {
    /// Records a collection run starting at `date`, and remembers `date` as the account's collection start unless
    /// one is already stored. A run of the same account that is still open is closed first (defensively: the app
    /// normally ends its runs itself). One transaction per call.
    public func beginCollection(accountID: AccountID, at date: Date) throws(SQLiteError) {
        let seconds = Self.storedSeconds(date)
        let values: [SQLiteValue] = [.text(accountID.description), .real(seconds)]
        try writing { () throws(SQLiteError) in
            try self.connection.transaction { () throws(SQLiteError) in
                try self.endRunsStatement(account: true)
                    .run([.real(seconds), .text(CollectionRun.EndReason.quit.rawValue), .text(accountID.description)])
                try self.connection.prepare("INSERT OR IGNORE INTO collection_starts (account_id, started_at) VALUES (?, ?)")
                    .run(values)
                try self.connection.prepare("INSERT OR IGNORE INTO collection_runs (account_id, started_at) VALUES (?, ?)")
                    .run(values)
            }
        }
    }

    /// Marks every open run (of one account, or of all when `nil`) as still collecting at `date`.
    public func touchCollectionRuns(accountID: AccountID? = nil, at date: Date) throws(SQLiteError) {
        let seconds = SQLiteValue.real(Self.storedSeconds(date))
        try writing { () throws(SQLiteError) in
            if let accountID {
                try self.connection.prepare("""
                    UPDATE collection_runs SET last_seen = MAX(started_at, ?)
                    WHERE account_id = ? AND ended_at IS NULL
                    """)
                    .run([seconds, .text(accountID.description)])
            } else {
                try self.connection.prepare("""
                    UPDATE collection_runs SET last_seen = MAX(started_at, ?) WHERE ended_at IS NULL
                    """)
                    .run([seconds])
            }
        }
    }

    /// Ends every open run (of one account, or of all when `nil`) at `date` with `reason`, never before its start.
    /// Returns how many runs were ended.
    @discardableResult
    public func endCollectionRuns(
        accountID: AccountID?,
        at date: Date,
        reason: CollectionRun.EndReason
    ) throws(SQLiteError) -> Int {
        let seconds = Self.storedSeconds(date)
        return try writing { () throws(SQLiteError) -> Int in
            let statement = try self.endRunsStatement(account: accountID != nil)
            if let accountID {
                try statement.run([.real(seconds), .text(reason.rawValue), .text(accountID.description)])
            } else {
                try statement.run([.real(seconds), .text(reason.rawValue)])
            }
            return self.connection.changes
        } ?? 0
    }

    /// Closes runs a previous process left open (it crashed or was force quit) at their last heartbeat.
    /// Call at launch, before new runs begin. Returns how many runs were closed.
    @discardableResult
    public func closeDanglingCollectionRuns() throws(SQLiteError) -> Int {
        try writing { () throws(SQLiteError) -> Int in
            try self.connection.prepare("""
                UPDATE collection_runs
                SET ended_at = MAX(started_at, COALESCE(last_seen, started_at)), end_reason = ?
                WHERE ended_at IS NULL
                """)
                .run([.text(CollectionRun.EndReason.crash.rawValue)])
            return self.connection.changes
        } ?? 0
    }

    /// The first time collection started for the account; `nil` when it never did.
    public func collectionStart(accountID: AccountID) throws(SQLiteError) -> Date? {
        let query = try connection.prepare("SELECT started_at FROM collection_starts WHERE account_id = ?")
        try query.bind([.text(accountID.description)])
        guard try query.step(), let seconds = query.double(0), seconds.isFinite else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// Starts of the collection runs that overlap `interval`, ascending: the latest one at or before its start (the
    /// run already going when the interval begins) and every one inside it. At most `maximumRows`, the latest ones.
    public func collectionStarts(accountID: AccountID, interval: DateInterval) throws(SQLiteError) -> [Date] {
        try runs(accountID: accountID, interval: interval).map(\.start)
    }

    /// The collection runs overlapping `interval`, ascending by start: the latest run at or before its start plus
    /// every one inside it. At most `maximumRows`, the latest ones.
    public func collectionRuns(accountID: AccountID, interval: DateInterval) throws(SQLiteError) -> [CollectionRun] {
        try runs(accountID: accountID, interval: interval)
    }

    // MARK: - Helpers

    private func runs(accountID: AccountID, interval: DateInterval) throws(SQLiteError) -> [CollectionRun] {
        let query = try connection.prepare("""
            SELECT started_at, ended_at, last_seen, end_reason FROM collection_runs
            WHERE account_id = ?1 AND started_at <= ?3 AND started_at >= COALESCE(
                (SELECT MAX(started_at) FROM collection_runs WHERE account_id = ?1 AND started_at <= ?2),
                ?2
            )
            ORDER BY started_at DESC
            LIMIT ?4
            """)
        try query.bind([
            .text(accountID.description),
            .real(Self.storedSeconds(interval.start)),
            .real(Self.storedSeconds(interval.end)),
            .integer(Int64(Self.maximumRows)),
        ])
        var runs: [CollectionRun] = []
        while try query.step() {
            guard let start = query.double(0), start.isFinite else { continue }
            runs.append(CollectionRun(
                start: Date(timeIntervalSince1970: start),
                end: Self.date(query.double(1)),
                lastSeen: Self.date(query.double(2)),
                endReason: query.text(3).flatMap(CollectionRun.EndReason.init(rawValue:))
            ))
        }
        return runs.reversed()
    }

    /// `UPDATE` that ends open runs; binds are `?1` end, `?2` reason and, when `account`, `?3` account id.
    private func endRunsStatement(account: Bool) throws(SQLiteError) -> SQLiteStatement {
        try connection.prepare("""
            UPDATE collection_runs SET ended_at = MAX(started_at, ?1), end_reason = ?2
            WHERE ended_at IS NULL\(account ? " AND account_id = ?3" : "")
            """)
    }

    private static func date(_ seconds: Double?) -> Date? {
        guard let seconds, seconds.isFinite else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}
