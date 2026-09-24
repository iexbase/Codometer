import CodometerCore
import CodometerStorage
import Foundation
import Testing

private let base = Date(timeIntervalSince1970: 1_789_599_900)

private func days(_ count: Double) -> TimeInterval { count * 86_400 }

private func reading(used: Double, at date: Date) throws -> UsageReading {
    try UsageReading(
        capturedAt: date,
        source: .claudeUsageCommand,
        buckets: [try LimitBucket(
            id: "claude",
            title: nil,
            windows: [try LimitWindow(
                id: "session",
                scope: .session,
                used: try Percentage(validating: used),
                duration: .fiveHours,
                resetsAt: date.addingTimeInterval(3_600)
            )],
            isLimitReached: false
        )],
        credits: nil
    )
}

@Suite("Stored history retention")
struct RetentionTests {
    @Test("Pruning keeps exactly the chosen number of days, and a shorter choice deletes more at once")
    func retentionChoice() async throws {
        let directory = try TemporaryDirectory()
        let store = try UsageHistoryStore(databaseURL: directory.file("history.sqlite"))
        let account = AccountID()
        let now = base.addingTimeInterval(days(40))
        for age in [36.0, 34, 20, 10, 6, 1] {
            try await store.record(try reading(used: age, at: now.addingTimeInterval(-days(age))), identity: nil, for: account)
        }
        #expect(await store.retention == UsageHistoryStore.defaultRetention)

        // Five weeks: the 36-day-old sample goes.
        try await store.prune(now: now)
        var kept = try await store.samples(accountID: account, bucketID: "claude", windowID: "session", since: .distantPast)
        #expect(kept.map(\.used.value) == [34, 20, 10, 6, 1])

        // One week: everything older than seven days goes.
        await store.setRetention(try HistoryRetention(days: 7).timeInterval)
        #expect(await store.retention == days(7))
        try await store.prune(now: now)
        kept = try await store.samples(accountID: account, bucketID: "claude", windowID: "session", since: .distantPast)
        #expect(kept.map(\.used.value) == [6, 1])
    }

    @Test("Token buckets are pruned by whole buckets and segments only once they have ended")
    func bucketsAndSegments() async throws {
        let directory = try TemporaryDirectory()
        let store = try UsageHistoryStore(databaseURL: directory.file("history.sqlite"))
        let account = AccountID()
        let now = base.addingTimeInterval(days(40))
        let old = now.addingTimeInterval(-days(20))
        let recent = now.addingTimeInterval(-days(2))
        for at in [old, recent] {
            try await store.addTokenSamples([
                try TokenSample(
                    accountID: account,
                    sessionID: "s-\(at.timeIntervalSince1970)",
                    project: "/Users/me/app",
                    model: "claude-fable-5",
                    at: at,
                    delta: try TokenCounts(input: 5, cachedInput: 0, cacheWrite: 0, output: 1, reasoningOutput: 0)
                ),
            ])
        }
        let openSegment = try SessionSegment(
            accountID: account, sessionID: "open", title: "app · open", project: "/Users/me/app",
            activity: .working, start: old, end: nil
        )
        try await store.openSegment(openSegment, lastSeen: old)
        let closedSegment = try SessionSegment(
            accountID: account, sessionID: "closed", title: "app · closed", project: "/Users/me/app",
            activity: .working, start: old, end: old.addingTimeInterval(60)
        )
        try await store.closeSegment(closedSegment, at: old.addingTimeInterval(60))

        await store.setRetention(try HistoryRetention(days: 7).timeInterval)
        try await store.prune(now: now)

        let whole = DateInterval(start: base.addingTimeInterval(-days(10)), end: now)
        #expect(try await store.tokenSamples(accountID: account, interval: whole).count == 1)
        // An open segment is never pruned, however old it is; the closed one from 20 days ago is gone.
        #expect(try await store.segments(accountID: account, interval: whole).map(\.sessionID) == ["open"])
    }

    @Test("A retention outside the allowed range is clamped instead of trusted")
    func clampsAbsurdValues() async throws {
        let directory = try TemporaryDirectory()
        let store = try UsageHistoryStore(databaseURL: directory.file("history.sqlite"))
        await store.setRetention(-1)
        #expect(await store.retention == days(1))
        await store.setRetention(days(10_000))
        #expect(await store.retention == days(400))
        for choice in HistoryRetention.choices {
            await store.setRetention(choice.timeInterval)
            #expect(await store.retention == days(Double(choice.days)))
        }
    }

    @Test("Diagnostics report the retention in whole days")
    func diagnosticsReportRetention() async throws {
        let directory = try TemporaryDirectory()
        let store = try UsageHistoryStore(databaseURL: directory.file("history.sqlite"))
        await store.setRetention(try HistoryRetention(days: 90).timeInterval)
        #expect(await store.diagnostics().retentionDays == 90)
    }
}

@Suite("History size budget")
struct HistorySizeTests {
    /// A busy month: three accounts, 35 days, each day a full working day of five-minute polls, token buckets,
    /// session segments and a few collection runs. Written raw, in one transaction, so the test stays quick.
    @Test("Five weeks of three busy accounts stay well under the ten-megabyte budget")
    func fiveWeeksOfThreeAccounts() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.file("history.sqlite")
        let accounts = (0..<3).map { _ in AccountID() }
        let start = base
        let days = 35
        do {
            let store = try UsageHistoryStore(databaseURL: url)
            await store.close()
        }
        let raw = try RawDatabase(path: url.path)
        var sql = "BEGIN;\n"
        for (index, account) in accounts.enumerated() {
            for day in 0..<days {
                let dayStart = start.timeIntervalSince1970 + Double(day) * 86_400
                // Twelve hours of five-minute polls, two windows each.
                for poll in 0..<144 {
                    let at = dayStart + Double(poll) * 300
                    for window in ["session", "week"] {
                        sql += """
                            INSERT OR IGNORE INTO limit_samples VALUES ('\(account)', 'claude', '\(window)', \
                            \(at), \(Double(poll % 100)), 300, \(at + 18_000), 'claudeUsageCommand');\n
                            """
                    }
                }
                // Three sessions, each with a five-minute token bucket per poll and a segment every half hour.
                for session in 0..<3 {
                    let sessionID = "session-\(index)-\(day)-\(session)"
                    for poll in 0..<144 {
                        let bucket = Int64((dayStart + Double(poll) * 300) / 300) * 300
                        sql += """
                            INSERT OR IGNORE INTO token_usage VALUES ('\(account)', '\(sessionID)', 'project-\(session)', \
                            'claude-fable-5', \(bucket), 12000, 400, 900, 3000, 500);\n
                            """
                    }
                    for half in 0..<24 {
                        let segmentStart = dayStart + Double(half) * 1_800
                        sql += """
                            INSERT OR IGNORE INTO session_segments VALUES ('\(account)', '\(sessionID)', \
                            'project-\(session) · \(session)', 'project-\(session)', 'working', \(segmentStart), \
                            \(segmentStart + 900), \(segmentStart + 900));\n
                            """
                    }
                }
                for run in 0..<5 {
                    let runStart = dayStart + Double(run) * 10_000
                    sql += """
                        INSERT OR IGNORE INTO collection_runs VALUES ('\(account)', \(runStart), \
                        \(runStart + 9_000), \(runStart + 9_000), 'quit');\n
                        """
                }
            }
        }
        sql += "COMMIT;"
        try raw.execute(sql)
        try raw.execute("PRAGMA wal_checkpoint(TRUNCATE)")

        let store = try UsageHistoryStore(databaseURL: url)
        try await store.prune(now: start.addingTimeInterval(Double(days) * 86_400))
        let diagnostics = await store.diagnostics()
        let megabytes = Double(diagnostics.fileBytes ?? 0) / 1_048_576
        #expect(megabytes > 0.5, "the fixture should hold a realistic month of data")
        #expect(megabytes <= 10, "history grew to \(megabytes) MB, over the 10 MB budget")
        #expect((diagnostics.rowCounts["limit_samples"] ?? 0) > 20_000)
        #expect((diagnostics.rowCounts["token_usage"] ?? 0) > 20_000)
    }
}
