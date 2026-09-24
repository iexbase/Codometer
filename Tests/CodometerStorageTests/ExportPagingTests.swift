import CodometerCore
import CodometerStorage
import Foundation
import Testing

private let base = Date(timeIntervalSince1970: 1_789_599_900)

@Suite("History export paging")
struct ExportPagingTests {
    /// A store holding `rows` limit samples spread over two accounts, written in one raw transaction so the test
    /// stays fast.
    private func filled(_ directory: TemporaryDirectory, rows: Int) async throws -> (UsageHistoryStore, [AccountID]) {
        let url = directory.file("history.sqlite")
        let accounts = [AccountID(), AccountID()].sorted { $0.description < $1.description }
        do {
            let store = try UsageHistoryStore(databaseURL: url)
            for account in accounts {
                try await store.beginCollection(accountID: account, at: base)
            }
            await store.close()
        }
        let raw = try RawDatabase(path: url.path)
        var sql = "BEGIN;\n"
        for index in 0..<rows {
            let account = accounts[index % accounts.count]
            let at = base.addingTimeInterval(Double(index) * 60).timeIntervalSince1970
            sql += """
                INSERT INTO limit_samples VALUES                 ('\(account)', 'claude', 'session', \(at), \(index % 100), 300, NULL, 'claudeUsageCommand');\n
                """
        }
        sql += "COMMIT;"
        try raw.execute(sql)
        return (try UsageHistoryStore(databaseURL: url), accounts)
    }

    @Test("Every row is read exactly once across pages, in key order, past the single-query row cap")
    func pagesCoverEveryRow() async throws {
        let directory = try TemporaryDirectory()
        let rows = 5_200
        let (store, _) = try await filled(directory, rows: rows)

        var seen: [ExportedLimitSample] = []
        var cursor: ExportedLimitSample?
        var pages = 0
        while true {
            let page = try await store.exportLimitSamples(after: cursor, limit: 500)
            guard !page.isEmpty else { break }
            pages += 1
            seen.append(contentsOf: page)
            cursor = page.last
            if page.count < 500 { break }
        }
        #expect(pages > 10)
        #expect(seen.count == rows)
        #expect(Set(seen.map { "\($0.accountID)|\($0.capturedAt.timeIntervalSince1970)" }).count == rows)
        // Key order: accounts grouped, and inside an account the samples ascend by capture time.
        #expect(seen.map(\.accountID) == seen.map(\.accountID).sorted())
        for (_, rows) in Dictionary(grouping: seen, by: \.accountID) {
            #expect(rows.map(\.capturedAt) == rows.map(\.capturedAt).sorted())
        }
    }

    @Test("A page is bounded by the store's row cap however much is asked for")
    func pageLimitIsBounded() async throws {
        let directory = try TemporaryDirectory()
        let (store, _) = try await filled(directory, rows: 5_200)
        #expect(try await store.exportLimitSamples(after: nil, limit: 1_000_000).count == UsageHistoryStore.maximumRows)
        #expect(try await store.exportLimitSamples(after: nil, limit: 0).count == 1)
    }

    @Test("Segments, token buckets and runs page over their own keys")
    func otherTables() async throws {
        let directory = try TemporaryDirectory()
        let store = try UsageHistoryStore(databaseURL: directory.file("history.sqlite"))
        let account = AccountID()
        try await store.beginCollection(accountID: account, at: base)
        for index in 0..<40 {
            let start = base.addingTimeInterval(Double(index) * 600)
            let segment = try SessionSegment(
                accountID: account,
                sessionID: "session-\(index)",
                title: "app · \(index)",
                project: "/Users/me/app",
                activity: index.isMultiple(of: 2) ? .working : .waiting,
                start: start,
                end: start.addingTimeInterval(120)
            )
            try await store.closeSegment(segment, at: start.addingTimeInterval(120))
            try await store.addTokenSamples([
                try TokenSample(
                    accountID: account,
                    sessionID: "session-\(index)",
                    project: "/Users/me/app",
                    model: "claude-fable-5",
                    at: start,
                    delta: try TokenCounts(input: 10, cachedInput: 1, cacheWrite: 2, output: 3, reasoningOutput: 4)
                ),
            ])
        }

        var segments: [ExportedSessionSegment] = []
        var segmentCursor: ExportedSessionSegment?
        while true {
            let page = try await store.exportSessionSegments(after: segmentCursor, limit: 7)
            guard !page.isEmpty else { break }
            segments.append(contentsOf: page)
            segmentCursor = page.last
            if page.count < 7 { break }
        }
        #expect(segments.count == 40)
        #expect(Set(segments.map(\.sessionID)).count == 40)
        #expect(segments.allSatisfy { $0.project == "app" })

        var buckets: [ExportedTokenBucket] = []
        var bucketCursor: ExportedTokenBucket?
        while true {
            let page = try await store.exportTokenBuckets(after: bucketCursor, limit: 9)
            guard !page.isEmpty else { break }
            buckets.append(contentsOf: page)
            bucketCursor = page.last
            if page.count < 9 { break }
        }
        #expect(buckets.count == 40)
        #expect(buckets.allSatisfy { $0.input == 10 && $0.reasoningOutput == 4 })
        #expect(buckets.map(\.bucketStart) == buckets.map(\.bucketStart).sorted())

        let runs = try await store.exportCollectionRuns(after: nil)
        #expect(runs.map(\.accountID) == [account.description])
        #expect(runs.first?.endReason == nil)
    }
}
