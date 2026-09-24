import CodometerCore
import Darwin
import Foundation
import SQLite3

/// One stored observation of a limit window.
public struct LimitSample: Hashable, Sendable {
    public let capturedAt: Date
    public let used: Percentage
    public let resetsAt: Date?
    public let source: ReadingSource
}

public struct RestoredAccountState: Sendable {
    public let reading: UsageReading?
    public let identity: AccountIdentity?
}

/// What opening `history.sqlite` produced: a store with its health, or only the reason the app runs without history.
public enum HistoryOpenResult: Sendable {
    case opened(UsageHistoryStore, HistoryHealth)
    case unavailable(HistoryHealth)
}

/// Usage history, last known readings, session segments and token usage, persisted in SQLite.
///
/// Writes stop while the file was written by a newer build (`readOnlyNewerSchema`) or the disk is full
/// (`writesPaused`, retried at the next prune), and every call after `close()` throws `.closed`.
///
/// Samples are written only when a value changes (or every 30 minutes as a heartbeat),
/// so a month of history for several accounts stays well under a megabyte. Segments are written only on
/// activity transitions and token counts are folded into 5-minute buckets (see the extensions).
/// Every query returns at most `maximumRows` rows, the most recent ones.
public actor UsageHistoryStore {
    /// How long history is kept until the user picks something else (`HistoryRetention.standard`).
    public static let defaultRetention: TimeInterval = 35 * 24 * 60 * 60
    /// Upper bound on the rows any single query returns.
    public static let maximumRows = 5_000
    /// How long `open` may spend checking a file's integrity before it gives the file the benefit of the doubt.
    public static let openCheckTimeout: TimeInterval = 1.5
    /// Damaged files are moved to `history.corrupt-<seconds since 1970>.sqlite` and its companions.
    public static let corruptPrefix = "history.corrupt-"
    static let heartbeat: TimeInterval = 30 * 60
    static let resetTolerance: TimeInterval = 120
    static let schemaVersion: Int64 = HistorySchema.currentVersion

    private struct SampleKey: Hashable {
        let accountID: AccountID
        let bucketID: String
        let windowID: String
    }

    private struct SampleFingerprint {
        let used: Double
        let resetsAt: Double?
        let capturedAt: Date
    }

    let connection: SQLiteConnection
    /// What the file looked like when it was opened; readable without entering the actor, so the synchronous
    /// `open(databaseURL:)` can report it.
    public nonisolated let initialHealth: HistoryHealth
    private var lastWritten: [SampleKey: SampleFingerprint] = [:]
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    /// The current state of the file. Writes stop while it is `readOnlyNewerSchema` or `writesPaused`; a full disk
    /// replaces a recovery state with `writesPaused`, and `initialHealth` keeps what opening the file found.
    public private(set) var health: HistoryHealth
    /// How long history is kept. Set from the user's choice at launch and whenever it changes.
    public private(set) var retention: TimeInterval = UsageHistoryStore.defaultRetention

    /// Opens (or creates) the database and migrates it, unless it was written by a build that forbids older writers
    /// (`schema_meta.min_reader_version`), in which case it is opened read-only.
    public init(databaseURL: URL) throws(SQLiteError) {
        try self.init(databaseURL: databaseURL, checkingIntegrity: false)
    }

    /// `checkingIntegrity` runs `PRAGMA quick_check(1)` (bounded by `openCheckTimeout`) before migrating and reports a
    /// definite "damaged" answer as a corruption failure. The launch path (`open`) uses it; a check that times out is
    /// not treated as damage. `recoveredFrom` names the file a damaged database was just moved aside to, so this
    /// fresh file reports the recovery for as long as it is open (the Diagnostics pane reads it from `health`).
    init(databaseURL: URL, checkingIntegrity: Bool, recoveredFrom: String? = nil) throws(SQLiteError) {
        connection = try SQLiteConnection(path: databaseURL.path)
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        if checkingIntegrity, connection.quickCheck(timeout: Self.openCheckTimeout) == false {
            throw .open(code: SQLITE_CORRUPT, message: "quick_check reported a damaged file")
        }
        let version = (try? HistorySchema.version(of: connection)) ?? 0
        if HistorySchema.requiresReadOnly(version: version, minimumReader: HistorySchema.minimumReaderVersion(of: connection)) {
            initialHealth = .readOnlyNewerSchema(version: Int(version))
            health = initialHealth
            return
        }
        initialHealth = recoveredFrom.map { .recoveredFromCorruption(backupFileName: $0) } ?? .ok
        health = initialHealth
        try HistorySchema.migrate(connection)
    }

    /// Opens (or creates) the database for the launch path, recovering from a damaged file.
    ///
    /// A file that SQLite refuses as corrupt or not a database, or that fails `PRAGMA quick_check(1)`, is moved aside
    /// with its companions as `history.corrupt-<timestamp>.sqlite*` and replaced by a fresh one. A check that times out
    /// is not treated as damage: history is never thrown away on a slow disk. Any other failure leaves the file alone
    /// and reports history as unavailable.
    public static func open(databaseURL: URL) -> HistoryOpenResult {
        switch prepare(databaseURL: databaseURL) {
        case .success(let store):
            return .opened(store, store.initialHealth)
        case .failure(let error):
            guard error.meansCorruption else { return .unavailable(.unavailable(reason: error.description)) }
            guard let backupName = moveAside(databaseURL: databaseURL) else {
                return .unavailable(.unavailable(reason: error.description))
            }
            switch prepare(databaseURL: databaseURL, recoveredFrom: backupName) {
            case .success(let store):
                return .opened(store, store.initialHealth)
            case .failure(let second):
                return .unavailable(.unavailable(reason: second.description))
            }
        }
    }

    /// Opens the file with an integrity check, so a definite "damaged" answer reaches the caller as a corruption
    /// failure and the file can be moved aside.
    private static func prepare(
        databaseURL: URL,
        recoveredFrom: String? = nil
    ) -> Result<UsageHistoryStore, SQLiteError> {
        do throws(SQLiteError) {
            return .success(try UsageHistoryStore(
                databaseURL: databaseURL,
                checkingIntegrity: true,
                recoveredFrom: recoveredFrom
            ))
        } catch {
            return .failure(error)
        }
    }

    /// Renames the database and its companions out of the way. Returns the new database file's name.
    private static func moveAside(databaseURL: URL) -> String? {
        let stamp = Int(Date().timeIntervalSince1970)
        let directory = databaseURL.deletingLastPathComponent()
        let name = "\(corruptPrefix)\(stamp).sqlite"
        let destination = directory.appendingPathComponent(name, isDirectory: false)
        guard rename(databaseURL.path, destination.path) == 0 else { return nil }
        _ = chmod(destination.path, SQLiteConnection.filePermissions)
        for suffix in SQLiteConnection.companionSuffixes {
            let companion = databaseURL.path + suffix
            var info = stat()
            guard lstat(companion, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { continue }
            let target = destination.path + suffix
            if rename(companion, target) == 0 {
                _ = chmod(target, SQLiteConnection.filePermissions)
            }
        }
        return name
    }

    /// Whether history writes are allowed: a file from a newer build is never written, and a full disk pauses writes
    /// until the next maintenance pass.
    public var allowsWrites: Bool {
        switch health {
        case .ok, .recoveredFromCorruption, .unavailable: true
        case .readOnlyNewerSchema, .writesPaused: false
        }
    }

    /// Closes the database, so its files can be removed. Every later call throws `.closed`.
    public func close() {
        connection.close()
    }

    /// Caps the database at `pages` pages, so further writes fail with `SQLITE_FULL`.
    ///
    /// The only way to exercise the full-disk path (writes pause and resume at the next maintenance) without
    /// filling a real disk; it is not part of the public surface.
    func setMaximumPageCount(_ pages: Int) throws(SQLiteError) {
        try connection.execute("PRAGMA max_page_count = \(max(pages, 1))")
    }

    /// Keeps history for `seconds`; the next prune uses it.
    public func setRetention(_ seconds: TimeInterval) {
        retention = min(max(seconds, 86_400), 400 * 86_400)
    }

    /// Runs a write unless the store is read-only or writes are paused, and pauses writes when the disk is full.
    ///
    /// Used by every write in this file and its extensions; `nil` means the write was skipped.
    @discardableResult
    func writing<T>(_ body: () throws(SQLiteError) -> T) throws(SQLiteError) -> T? {
        guard allowsWrites else { return nil }
        do throws(SQLiteError) {
            return try body()
        } catch {
            if error.meansDiskFull {
                health = .writesPaused(reason: error.description)
            }
            throw error
        }
    }

    /// Stores a reading's windows (deduplicated) and remembers it as the account's last known state.
    public func record(_ reading: UsageReading, identity: AccountIdentity?, for accountID: AccountID) throws(SQLiteError) {
        try writing { () throws(SQLiteError) in
            try self.recordUnchecked(reading, identity: identity, for: accountID)
        }
    }

    private func recordUnchecked(_ reading: UsageReading, identity: AccountIdentity?, for accountID: AccountID) throws(SQLiteError) {
        let insert = try connection.prepare("""
            INSERT OR IGNORE INTO limit_samples
            (account_id, bucket_id, window_id, captured_at, used_percent, duration_minutes, resets_at, source)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """)
        let upsert = try connection.prepare("""
            INSERT INTO last_state (account_id, reading_json, identity_json, updated_at) VALUES (?, ?, ?, ?)
            ON CONFLICT(account_id) DO UPDATE SET
                reading_json = excluded.reading_json,
                identity_json = excluded.identity_json,
                updated_at = excluded.updated_at
            """)
        let readingData = try? encoder.encode(reading)
        let identityData = identity.flatMap { try? encoder.encode($0) }

        try connection.transaction { () throws(SQLiteError) in
            for bucket in reading.buckets {
                for window in bucket.windows {
                    let key = SampleKey(accountID: accountID, bucketID: bucket.id, windowID: window.id)
                    let fingerprint = SampleFingerprint(
                        used: window.used.value,
                        resetsAt: window.resetsAt?.timeIntervalSince1970,
                        capturedAt: reading.capturedAt
                    )
                    guard shouldWrite(fingerprint, for: key) else { continue }
                    try insert.run([
                        .text(accountID.description),
                        .text(bucket.id),
                        .text(window.id),
                        .real(reading.capturedAt.timeIntervalSince1970),
                        .real(window.used.value),
                        window.duration.map { .integer(Int64($0.minutes)) } ?? .null,
                        window.resetsAt.map { .real($0.timeIntervalSince1970) } ?? .null,
                        .text(reading.source.rawValue),
                    ])
                    lastWritten[key] = fingerprint
                }
            }
            try upsert.run([
                .text(accountID.description),
                readingData.map { .blob($0) } ?? .null,
                identityData.map { .blob($0) } ?? .null,
                .real(Date().timeIntervalSince1970),
            ])
        }
    }

    public func restoredStates() throws(SQLiteError) -> [AccountID: RestoredAccountState] {
        let query = try connection.prepare("SELECT account_id, reading_json, identity_json FROM last_state")
        try query.bind([])
        var states: [AccountID: RestoredAccountState] = [:]
        while try query.step() {
            guard let rawID = query.text(0), let uuid = UUID(uuidString: rawID) else { continue }
            let reading = query.blob(1).flatMap { try? decoder.decode(UsageReading.self, from: $0) }
            let identity = query.blob(2).flatMap { try? decoder.decode(AccountIdentity.self, from: $0) }
            states[AccountID(rawValue: uuid)] = RestoredAccountState(reading: reading, identity: identity)
        }
        return states
    }

    /// Stored observations of one window captured at or after `since`, ascending; the most recent
    /// `maximumRows` when there are more.
    public func samples(
        accountID: AccountID,
        bucketID: String,
        windowID: String,
        since: Date
    ) throws(SQLiteError) -> [LimitSample] {
        let query = try connection.prepare("""
            SELECT captured_at, used_percent, resets_at, source FROM (
                SELECT captured_at, used_percent, resets_at, source FROM limit_samples
                WHERE account_id = ? AND bucket_id = ? AND window_id = ? AND captured_at >= ?
                ORDER BY captured_at DESC
                LIMIT ?
            ) ORDER BY captured_at
            """)
        try query.bind([
            .text(accountID.description),
            .text(bucketID),
            .text(windowID),
            .real(Self.storedSeconds(since)),
            .integer(Int64(Self.maximumRows)),
        ])
        var samples: [LimitSample] = []
        while try query.step() {
            if let sample = Self.limitSample(from: query) {
                samples.append(sample)
            }
        }
        return samples
    }

    /// The latest stored observation of one window captured strictly before `date`, if any.
    ///
    /// Lets callers detect a reset between the last observation before a range and the first one inside it.
    public func latestSample(
        accountID: AccountID,
        bucketID: String,
        windowID: String,
        before date: Date
    ) throws(SQLiteError) -> LimitSample? {
        let query = try connection.prepare("""
            SELECT captured_at, used_percent, resets_at, source FROM limit_samples
            WHERE account_id = ? AND bucket_id = ? AND window_id = ? AND captured_at < ?
            ORDER BY captured_at DESC
            LIMIT 1
            """)
        try query.bind([
            .text(accountID.description), .text(bucketID), .text(windowID), .real(Self.storedSeconds(date)),
        ])
        return try query.step() ? Self.limitSample(from: query) : nil
    }

    /// Every account that has any stored data, so data of accounts removed from settings can be deleted.
    public func accountIDs() throws(SQLiteError) -> Set<AccountID> {
        let query = try connection.prepare("""
            SELECT account_id FROM last_state
            UNION SELECT account_id FROM limit_samples
            UNION SELECT account_id FROM session_segments
            UNION SELECT account_id FROM token_usage
            UNION SELECT account_id FROM collection_starts
            UNION SELECT account_id FROM collection_runs
            """)
        try query.bind([])
        var identifiers = Set<AccountID>()
        while try query.step() {
            guard let raw = query.text(0), let uuid = UUID(uuidString: raw) else { continue }
            identifiers.insert(AccountID(rawValue: uuid))
        }
        return identifiers
    }

    /// Deletes everything stored for the account: samples, last state, segments, token usage and its collection
    /// start and runs.
    public func removeAccount(_ accountID: AccountID) throws(SQLiteError) {
        try writing { () throws(SQLiteError) in
            try self.connection.transaction { () throws(SQLiteError) in
                for table in ["limit_samples", "last_state", "session_segments", "token_usage", "collection_starts", "collection_runs"] {
                    try self.connection.prepare("DELETE FROM \(table) WHERE account_id = ?").run([.text(accountID.description)])
                }
            }
            self.lastWritten = self.lastWritten.filter { $0.key.accountID != accountID }
        }
    }

    /// Deletes data older than `retention`: samples, closed segments that ended before the cutoff, token
    /// buckets that ended before it and collection runs that started before it. Open segments are kept however old
    /// they are, and so is each account's latest run, which may still be going.
    public func prune(now: Date) throws(SQLiteError) {
        // Maintenance is also when paused writes are retried: the disk may have room again. The state the file was
        // opened in comes back, so a recovery earlier in this launch is not forgotten by a passing full disk.
        if case .writesPaused = health {
            health = initialHealth
        }
        let cutoff = Self.storedSeconds(now.addingTimeInterval(-retention))
        let lastExpiredBucket = Self.bucketStart(ofSeconds: cutoff) - Int64(Self.tokenBucketSeconds)
        try writing { () throws(SQLiteError) in
            try self.connection.transaction { () throws(SQLiteError) in
                try self.connection.prepare("DELETE FROM limit_samples WHERE captured_at < ?").run([.real(cutoff)])
                try self.connection.prepare("DELETE FROM session_segments WHERE ended_at IS NOT NULL AND ended_at < ?")
                    .run([.real(cutoff)])
                try self.connection.prepare("DELETE FROM token_usage WHERE bucket_start <= ?").run([.integer(lastExpiredBucket)])
                try self.connection.prepare("""
                    DELETE FROM collection_runs WHERE started_at < ? AND started_at < (
                        SELECT MAX(latest.started_at) FROM collection_runs AS latest
                        WHERE latest.account_id = collection_runs.account_id
                    )
                    """)
                    .run([.real(cutoff)])
            }
        }
    }

    // MARK: - Helpers

    private static func limitSample(from query: SQLiteStatement) -> LimitSample? {
        guard
            let capturedAt = query.double(0),
            let rawUsed = query.double(1),
            let used = try? Percentage(validating: rawUsed),
            let source = query.text(3).flatMap(ReadingSource.init(rawValue:))
        else { return nil }
        return LimitSample(
            capturedAt: Date(timeIntervalSince1970: capturedAt),
            used: used,
            resetsAt: query.double(2).map { Date(timeIntervalSince1970: $0) },
            source: source
        )
    }

    /// Seconds since 1970 for binding, clamped so `distantPast`/`distantFuture` and corrupt dates stay usable.
    static func storedSeconds(_ date: Date) -> Double {
        let seconds = date.timeIntervalSince1970
        guard seconds.isFinite else { return 0 }
        return min(max(seconds, -Self.storedSecondsLimit), Self.storedSecondsLimit)
    }

    /// ±3000 years around 1970: comfortably covers `Date.distantPast` / `distantFuture` and any real timestamp.
    static let storedSecondsLimit: Double = 1e11

    /// Rolling windows report a reset time that drifts with every poll; only real moves count.
    private func resetMoved(from old: Double?, to new: Double?) -> Bool {
        switch (old, new) {
        case let (old?, new?): abs(new - old) >= Self.resetTolerance
        case (nil, nil): false
        default: true
        }
    }

    private func shouldWrite(_ fingerprint: SampleFingerprint, for key: SampleKey) -> Bool {
        guard let previous = lastWritten[key] else { return true }
        guard fingerprint.capturedAt > previous.capturedAt else { return false }
        return previous.used != fingerprint.used
            || resetMoved(from: previous.resetsAt, to: fingerprint.resetsAt)
            || fingerprint.capturedAt.timeIntervalSince(previous.capturedAt) >= Self.heartbeat
    }
}
