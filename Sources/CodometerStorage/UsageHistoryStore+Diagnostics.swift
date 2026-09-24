import CodometerCore
import Foundation

extension UsageHistoryStore {
    /// Tables Diagnostics counts rows of, in display order.
    static let countedTables = ["limit_samples", "session_segments", "token_usage", "collection_runs"]
    /// Upper bound on a counted table, so a damaged file can never turn a count into a long scan.
    static let maximumCountedRows = 2_000_000

    /// History facts for the Diagnostics pane: file size from the page count, schema version, the oldest stored
    /// sample and bounded row counts. Cheap and pull-only; unreadable values stay `nil`.
    public func diagnostics() async -> HistoryDiagnostics {
        HistoryDiagnostics(
            health: health,
            fileBytes: fileBytes(),
            schemaVersion: (try? HistorySchema.version(of: connection)).map { Int($0) },
            oldestSampleAt: oldestSampleAt(),
            retentionDays: Int((retention / 86_400).rounded()),
            rowCounts: rowCounts()
        )
    }

    /// Runs `PRAGMA quick_check(1)`, interrupted after `timeout`: `true` when the file is intact, `false` when damaged,
    /// `nil` when the check timed out or the store is closed.
    public func quickCheck(timeout: TimeInterval) async -> Bool? {
        connection.quickCheck(timeout: timeout)
    }

    private func fileBytes() -> Int64? {
        guard
            let pages = try? singleInteger("PRAGMA page_count"),
            let size = try? singleInteger("PRAGMA page_size")
        else { return nil }
        let (bytes, overflow) = pages.multipliedReportingOverflow(by: size)
        return overflow ? nil : bytes
    }

    private func oldestSampleAt() -> Date? {
        guard
            let query = try? connection.prepare("SELECT MIN(captured_at) FROM limit_samples"),
            (try? query.step()) == true,
            let seconds = query.double(0)
        else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private func rowCounts() -> [String: Int] {
        var counts: [String: Int] = [:]
        for table in Self.countedTables {
            guard let count = try? singleInteger(
                "SELECT COUNT(*) FROM (SELECT 1 FROM \(table) LIMIT \(Self.maximumCountedRows))"
            ) else { continue }
            counts[table] = Int(count)
        }
        return counts
    }

    private func singleInteger(_ sql: String) throws(SQLiteError) -> Int64? {
        let query = try connection.prepare(sql)
        return try query.step() ? query.integer(0) : nil
    }
}
