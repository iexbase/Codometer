import CodometerCore
import Foundation

/// Token counts of one session, project and model summed over a range of 5-minute buckets.
public struct TokenUsageTotal: Hashable, Sendable {
    public let sessionID: String
    public let project: String?
    public let model: String?
    /// Start of the earliest bucket in the range with tokens.
    public let firstBucket: Date
    /// Start of the latest bucket in the range with tokens.
    public let lastBucket: Date
    public let counts: TokenCounts

    public init(
        sessionID: String,
        project: String?,
        model: String?,
        firstBucket: Date,
        lastBucket: Date,
        counts: TokenCounts
    ) throws(ValidationError) {
        guard let cleanID = DisplayText.sanitize(sessionID, maximumLength: 128), cleanID == sessionID else {
            throw .invalidCharacters(field: "tokens.sessionID")
        }
        guard firstBucket <= lastBucket else {
            throw .inconsistent(field: "tokens.lastBucket", reason: "the last bucket cannot precede the first")
        }
        self.sessionID = sessionID
        self.project = DisplayText.sanitize(project, maximumLength: ProfileDirectory.maximumLength)
        self.model = DisplayText.sanitize(model, maximumLength: AgentSession.maximumModelLength)
        self.firstBucket = firstBucket
        self.lastBucket = lastBucket
        self.counts = counts
    }
}

/// Token usage in 5-minute buckets per account, session, project and model.
///
/// Samples are summed per bucket in memory and written with one UPSERT per changed bucket that adds to the
/// stored counts, saturating at `Int64.max`. No conversation content is ever stored: only ids, the project
/// folder name (never the full path), the model name and counts.
extension UsageHistoryStore {
    static let tokenBucketSeconds: Int64 = 300

    /// Adds the samples' counts to their 5-minute buckets in one transaction. Zero samples are skipped.
    public func addTokenSamples(_ samples: [TokenSample]) throws(SQLiteError) {
        var buckets: [TokenBucketKey: TokenCounts] = [:]
        for sample in samples where !sample.delta.isZero {
            let key = TokenBucketKey(
                accountID: sample.accountID,
                sessionID: sample.sessionID,
                project: Self.storedProject(sample.project) ?? "",
                model: DisplayText.sanitize(sample.model, maximumLength: AgentSession.maximumModelLength) ?? "",
                bucketStart: Self.bucketStart(ofSeconds: Self.storedSeconds(sample.at))
            )
            buckets[key] = (buckets[key] ?? .zero) + sample.delta
        }
        guard !buckets.isEmpty, allowsWrites else { return }

        let upsert = try connection.prepare("""
            INSERT INTO token_usage
            (account_id, session_id, project, model, bucket_start, input, cached_input, cache_write, output, reasoning_output)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (account_id, bucket_start, session_id, project, model) DO UPDATE SET
                input = \(Self.saturatingSum("input")),
                cached_input = \(Self.saturatingSum("cached_input")),
                cache_write = \(Self.saturatingSum("cache_write")),
                output = \(Self.saturatingSum("output")),
                reasoning_output = \(Self.saturatingSum("reasoning_output"))
            """)
        let ordered = buckets.sorted { lhs, rhs in lhs.key < rhs.key }
        try writing { () throws(SQLiteError) in
            try self.connection.transaction { () throws(SQLiteError) in
                for (key, counts) in ordered {
                    try upsert.run([
                        .text(key.accountID.description),
                        .text(key.sessionID),
                        .text(key.project),
                        .text(key.model),
                        .integer(key.bucketStart),
                        .integer(max(counts.input, 0)),
                        .integer(max(counts.cachedInput, 0)),
                        .integer(max(counts.cacheWrite, 0)),
                        .integer(max(counts.output, 0)),
                        .integer(max(counts.reasoningOutput, 0)),
                    ])
                }
            }
        }
    }

    /// Stored buckets of the account overlapping `interval`, ascending by bucket start. Each sample's `at` is its
    /// bucket's start, so the first one may lie up to 5 minutes before `interval.start`.
    /// At most `maximumRows`, the latest ones; rows that fail validation are skipped.
    public func tokenSamples(accountID: AccountID, interval: DateInterval) throws(SQLiteError) -> [TokenSample] {
        let query = try connection.prepare("""
            SELECT session_id, project, model, bucket_start, input, cached_input, cache_write, output, reasoning_output
            FROM token_usage
            WHERE account_id = ? AND bucket_start >= ? AND bucket_start <= ?
            ORDER BY bucket_start DESC, session_id DESC, project DESC, model DESC
            LIMIT ?
            """)
        try query.bind(Self.bucketRangeBindings(accountID: accountID, interval: interval) + [.integer(Int64(Self.maximumRows))])
        var samples: [TokenSample] = []
        while try query.step() {
            guard
                let sessionID = query.text(0),
                let bucketStart = query.integer(3),
                let counts = Self.counts(from: query, startingAt: 4)
            else { continue }
            let sample = try? TokenSample(
                accountID: accountID,
                sessionID: sessionID,
                project: query.text(1).flatMap(Self.nonEmpty),
                model: query.text(2).flatMap(Self.nonEmpty),
                at: Date(timeIntervalSince1970: TimeInterval(bucketStart)),
                delta: counts
            )
            if let sample {
                samples.append(sample)
            }
        }
        return samples.reversed()
    }

    /// The account's token counts over the buckets overlapping `interval`, summed per session, project and model.
    ///
    /// Unlike `tokenSamples` this never drops old buckets of a long range: it returns one row per group,
    /// at most `maximumRows` groups, the most recently active first.
    public func tokenTotals(accountID: AccountID, interval: DateInterval) throws(SQLiteError) -> [TokenUsageTotal] {
        // TOTAL() sums as floating point and never fails on overflow, unlike SUM().
        let query = try connection.prepare("""
            SELECT session_id, project, model, MIN(bucket_start), MAX(bucket_start),
                TOTAL(input), TOTAL(cached_input), TOTAL(cache_write), TOTAL(output), TOTAL(reasoning_output)
            FROM token_usage
            WHERE account_id = ? AND bucket_start >= ? AND bucket_start <= ?
            GROUP BY session_id, project, model
            ORDER BY MAX(bucket_start) DESC, session_id, project, model
            LIMIT ?
            """)
        try query.bind(Self.bucketRangeBindings(accountID: accountID, interval: interval) + [.integer(Int64(Self.maximumRows))])
        var totals: [TokenUsageTotal] = []
        while try query.step() {
            guard
                let sessionID = query.text(0),
                let first = query.integer(3),
                let last = query.integer(4)
            else { continue }
            let sums = (5...9).map { column in Self.clampedCount(query.double(Int32(column))) }
            guard let counts = try? TokenCounts(
                input: sums[0],
                cachedInput: sums[1],
                cacheWrite: sums[2],
                output: sums[3],
                reasoningOutput: sums[4]
            ) else { continue }
            let total = try? TokenUsageTotal(
                sessionID: sessionID,
                project: query.text(1).flatMap(Self.nonEmpty),
                model: query.text(2).flatMap(Self.nonEmpty),
                firstBucket: Date(timeIntervalSince1970: TimeInterval(first)),
                lastBucket: Date(timeIntervalSince1970: TimeInterval(last)),
                counts: counts
            )
            if let total {
                totals.append(total)
            }
        }
        return totals
    }

    // MARK: - Buckets

    /// The start of the 5-minute bucket containing `seconds` (floor, also for dates before 1970).
    ///
    /// The input is clamped first, so the result is always a multiple of 300 (the table's CHECK) and fits `Int64`.
    static func bucketStart(ofSeconds seconds: Double) -> Int64 {
        let bounded = seconds.isFinite ? min(max(seconds, -storedSecondsLimit), storedSecondsLimit) : 0
        return Int64((bounded / Double(tokenBucketSeconds)).rounded(.down)) * tokenBucketSeconds
    }

    private struct TokenBucketKey: Hashable, Comparable {
        let accountID: AccountID
        let sessionID: String
        let project: String
        let model: String
        let bucketStart: Int64

        static func < (lhs: TokenBucketKey, rhs: TokenBucketKey) -> Bool {
            (lhs.accountID.description, lhs.bucketStart, lhs.sessionID, lhs.project, lhs.model)
                < (rhs.accountID.description, rhs.bucketStart, rhs.sessionID, rhs.project, rhs.model)
        }
    }

    /// Account id plus the bucket-start bounds of the buckets overlapping `interval`.
    private static func bucketRangeBindings(accountID: AccountID, interval: DateInterval) -> [SQLiteValue] {
        [
            .text(accountID.description),
            .integer(bucketStart(ofSeconds: storedSeconds(interval.start))),
            .integer(Int64(storedSeconds(interval.end).rounded(.down))),
        ]
    }

    private static func saturatingSum(_ column: String) -> String {
        HistorySchema.saturatingSum(column)
    }

    private static func counts(from query: SQLiteStatement, startingAt column: Int32) -> TokenCounts? {
        guard
            let input = query.integer(column),
            let cachedInput = query.integer(column + 1),
            let cacheWrite = query.integer(column + 2),
            let output = query.integer(column + 3),
            let reasoningOutput = query.integer(column + 4)
        else { return nil }
        return try? TokenCounts(
            input: input,
            cachedInput: cachedInput,
            cacheWrite: cacheWrite,
            output: output,
            reasoningOutput: reasoningOutput
        )
    }

    /// A floating-point sum as a count; negative or non-finite sums (a corrupt file) become -1 and fail validation.
    private static func clampedCount(_ value: Double?) -> Int64 {
        guard let value, value.isFinite, value >= 0 else { return -1 }
        return value >= 9.2e18 ? .max : Int64(value)
    }

    private static func nonEmpty(_ text: String) -> String? {
        text.isEmpty ? nil : text
    }
}
