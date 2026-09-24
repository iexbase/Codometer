import CodometerCore
import Foundation

/// One `limit_samples` row as exported.
public struct ExportedLimitSample: Hashable, Sendable {
    public let accountID: String
    public let bucketID: String
    public let windowID: String
    public let capturedAt: Date
    public let usedPercent: Double
    public let durationMinutes: Int?
    public let resetsAt: Date?
    public let source: String

    public init(
        accountID: String,
        bucketID: String,
        windowID: String,
        capturedAt: Date,
        usedPercent: Double,
        durationMinutes: Int?,
        resetsAt: Date?,
        source: String
    ) {
        self.accountID = accountID
        self.bucketID = bucketID
        self.windowID = windowID
        self.capturedAt = capturedAt
        self.usedPercent = usedPercent
        self.durationMinutes = durationMinutes
        self.resetsAt = resetsAt
        self.source = source
    }
}

/// One `session_segments` row as exported. The stored title is never exported: it is rebuilt from the id and folder.
public struct ExportedSessionSegment: Hashable, Sendable {
    public let accountID: String
    public let sessionID: String
    public let activity: String
    public let startedAt: Date
    public let endedAt: Date?
    public let project: String?

    public init(accountID: String, sessionID: String, activity: String, startedAt: Date, endedAt: Date?, project: String?) {
        self.accountID = accountID
        self.sessionID = sessionID
        self.activity = activity
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.project = project
    }
}

/// One `token_usage` bucket as exported.
public struct ExportedTokenBucket: Hashable, Sendable {
    public let accountID: String
    public let bucketStart: Date
    public let sessionID: String
    public let project: String
    public let model: String
    public let input: Int64
    public let cachedInput: Int64
    public let cacheWrite: Int64
    public let output: Int64
    public let reasoningOutput: Int64

    public init(
        accountID: String,
        bucketStart: Date,
        sessionID: String,
        project: String,
        model: String,
        input: Int64,
        cachedInput: Int64,
        cacheWrite: Int64,
        output: Int64,
        reasoningOutput: Int64
    ) {
        self.accountID = accountID
        self.bucketStart = bucketStart
        self.sessionID = sessionID
        self.project = project
        self.model = model
        self.input = input
        self.cachedInput = cachedInput
        self.cacheWrite = cacheWrite
        self.output = output
        self.reasoningOutput = reasoningOutput
    }
}

/// One `collection_runs` row as exported.
public struct ExportedCollectionRun: Hashable, Sendable {
    public let accountID: String
    public let startedAt: Date
    public let endedAt: Date?
    public let endReason: String?

    public init(accountID: String, startedAt: Date, endedAt: Date?, endReason: String?) {
        self.accountID = accountID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.endReason = endReason
    }
}

/// Reading the history tables for an export, one bounded page at a time.
///
/// Pages are keyset-paginated over each table's primary key, so an export never holds more than one page in memory
/// and never reads a row twice, even while the app keeps recording. A row written behind the cursor while the export
/// runs is simply not in that export. The account id is exported as it is stored (its raw text), so a row whose id is
/// not a valid identifier still moves the cursor forward instead of stalling it. `last_state` is never exported: it
/// holds the account identity, including the e-mail.
extension UsageHistoryStore {
    /// Rows per page.
    public static let exportPageSize = 2_000

    public func exportLimitSamples(
        after cursor: ExportedLimitSample?,
        limit: Int = UsageHistoryStore.exportPageSize
    ) throws(SQLiteError) -> [ExportedLimitSample] {
        let columns = "account_id, bucket_id, window_id, captured_at, used_percent, duration_minutes, resets_at, source"
        let key = "account_id, bucket_id, window_id, captured_at"
        let query = try page(table: "limit_samples", columns: columns, key: key, keyCount: 4, hasCursor: cursor != nil)
        var values: [SQLiteValue] = []
        if let cursor {
            values = [
                .text(cursor.accountID), .text(cursor.bucketID), .text(cursor.windowID),
                .real(Self.storedSeconds(cursor.capturedAt)),
            ]
        }
        try query.bind(values + [.integer(Self.pageLimit(limit))])
        var rows: [ExportedLimitSample] = []
        while try query.step() {
            guard
                let accountID = query.text(0),
                let bucketID = query.text(1),
                let windowID = query.text(2),
                let capturedAt = query.double(3),
                let used = query.double(4),
                let source = query.text(7)
            else { continue }
            rows.append(ExportedLimitSample(
                accountID: accountID,
                bucketID: bucketID,
                windowID: windowID,
                capturedAt: Date(timeIntervalSince1970: capturedAt),
                usedPercent: used,
                durationMinutes: query.integer(5).map { Int($0) },
                resetsAt: query.double(6).map { Date(timeIntervalSince1970: $0) },
                source: source
            ))
        }
        return rows
    }

    public func exportSessionSegments(
        after cursor: ExportedSessionSegment?,
        limit: Int = UsageHistoryStore.exportPageSize
    ) throws(SQLiteError) -> [ExportedSessionSegment] {
        let columns = "account_id, session_id, activity, started_at, ended_at, project"
        let key = "account_id, session_id, activity, started_at"
        let query = try page(table: "session_segments", columns: columns, key: key, keyCount: 4, hasCursor: cursor != nil)
        var values: [SQLiteValue] = []
        if let cursor {
            values = [
                .text(cursor.accountID), .text(cursor.sessionID), .text(cursor.activity),
                .real(Self.storedSeconds(cursor.startedAt)),
            ]
        }
        try query.bind(values + [.integer(Self.pageLimit(limit))])
        var rows: [ExportedSessionSegment] = []
        while try query.step() {
            guard
                let accountID = query.text(0),
                let sessionID = query.text(1),
                let activity = query.text(2),
                let startedAt = query.double(3)
            else { continue }
            rows.append(ExportedSessionSegment(
                accountID: accountID,
                sessionID: sessionID,
                activity: activity,
                startedAt: Date(timeIntervalSince1970: startedAt),
                endedAt: query.double(4).map { Date(timeIntervalSince1970: $0) },
                project: query.text(5)
            ))
        }
        return rows
    }

    public func exportTokenBuckets(
        after cursor: ExportedTokenBucket?,
        limit: Int = UsageHistoryStore.exportPageSize
    ) throws(SQLiteError) -> [ExportedTokenBucket] {
        let columns = """
            account_id, bucket_start, session_id, project, model, input, cached_input, cache_write, output, reasoning_output
            """
        let key = "account_id, bucket_start, session_id, project, model"
        let query = try page(table: "token_usage", columns: columns, key: key, keyCount: 5, hasCursor: cursor != nil)
        var values: [SQLiteValue] = []
        if let cursor {
            values = [
                .text(cursor.accountID),
                .integer(Self.bucketStart(ofSeconds: Self.storedSeconds(cursor.bucketStart))),
                .text(cursor.sessionID), .text(cursor.project), .text(cursor.model),
            ]
        }
        try query.bind(values + [.integer(Self.pageLimit(limit))])
        var rows: [ExportedTokenBucket] = []
        while try query.step() {
            guard
                let accountID = query.text(0),
                let bucketStart = query.integer(1),
                let sessionID = query.text(2)
            else { continue }
            rows.append(ExportedTokenBucket(
                accountID: accountID,
                bucketStart: Date(timeIntervalSince1970: TimeInterval(bucketStart)),
                sessionID: sessionID,
                project: query.text(3) ?? "",
                model: query.text(4) ?? "",
                input: query.integer(5) ?? 0,
                cachedInput: query.integer(6) ?? 0,
                cacheWrite: query.integer(7) ?? 0,
                output: query.integer(8) ?? 0,
                reasoningOutput: query.integer(9) ?? 0
            ))
        }
        return rows
    }

    public func exportCollectionRuns(
        after cursor: ExportedCollectionRun?,
        limit: Int = UsageHistoryStore.exportPageSize
    ) throws(SQLiteError) -> [ExportedCollectionRun] {
        let columns = "account_id, started_at, ended_at, end_reason"
        let query = try page(table: "collection_runs", columns: columns, key: "account_id, started_at", keyCount: 2, hasCursor: cursor != nil)
        var values: [SQLiteValue] = []
        if let cursor {
            values = [.text(cursor.accountID), .real(Self.storedSeconds(cursor.startedAt))]
        }
        try query.bind(values + [.integer(Self.pageLimit(limit))])
        var rows: [ExportedCollectionRun] = []
        while try query.step() {
            guard let accountID = query.text(0), let startedAt = query.double(1) else { continue }
            rows.append(ExportedCollectionRun(
                accountID: accountID,
                startedAt: Date(timeIntervalSince1970: startedAt),
                endedAt: query.double(2).map { Date(timeIntervalSince1970: $0) },
                endReason: query.text(3)
            ))
        }
        return rows
    }

    // MARK: - Helpers

    /// One page of `table`, ordered by its primary key, after the row the cursor placeholders describe.
    private func page(
        table: String,
        columns: String,
        key: String,
        keyCount: Int,
        hasCursor: Bool
    ) throws(SQLiteError) -> SQLiteStatement {
        let placeholders = Array(repeating: "?", count: keyCount).joined(separator: ", ")
        let condition = hasCursor ? "WHERE (\(key)) > (\(placeholders))" : ""
        return try connection.prepare("""
            SELECT \(columns) FROM \(table)
            \(condition)
            ORDER BY \(key)
            LIMIT ?
            """)
    }

    private static func pageLimit(_ limit: Int) -> Int64 {
        Int64(min(max(limit, 1), maximumRows))
    }
}
