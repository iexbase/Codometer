import CodometerCore
import CodometerStorage
import Foundation
import Testing

/// A multiple of five minutes, so bucket arithmetic in expectations stays readable.
private let base = Date(timeIntervalSince1970: 1_789_599_900)

private func at(_ minutes: Double) -> Date {
    base.addingTimeInterval(minutes * 60)
}

private func counts(input: Int64 = 0, cached: Int64 = 0, write: Int64 = 0, output: Int64 = 0, reasoning: Int64 = 0) throws -> TokenCounts {
    try TokenCounts(input: input, cachedInput: cached, cacheWrite: write, output: output, reasoningOutput: reasoning)
}

private func sample(
    _ sessionID: String,
    account: AccountID,
    at minutes: Double,
    model: String? = "gpt-5.5",
    project: String? = "/Users/me/app",
    _ delta: TokenCounts
) throws -> TokenSample {
    try TokenSample(accountID: account, sessionID: sessionID, project: project, model: model, at: at(minutes), delta: delta)
}

@Suite("Token usage storage")
struct TokenStoreTests {
    @Test("Samples are summed into 5-minute buckets per session, project and model, and later writes add up")
    func aggregation() async throws {
        let directory = try TemporaryDirectory()
        let store = try UsageHistoryStore(databaseURL: directory.file("history.sqlite"))
        let account = AccountID()
        try await store.addTokenSamples([
            try sample("s1", account: account, at: 0.5, try counts(input: 100, cached: 1_000, output: 10, reasoning: 4)),
            try sample("s1", account: account, at: 4.9, try counts(input: 50, write: 7, output: 5)),
            try sample("s1", account: account, at: 5, try counts(input: 1)),
            try sample("s1", account: account, at: 1, model: "gpt-5.5-mini", try counts(output: 3)),
            try sample("s2", account: account, at: 1, project: nil, try counts(input: 9)),
            try sample("s2", account: account, at: 1, project: nil, .zero),
        ])
        try await store.addTokenSamples([try sample("s1", account: account, at: 2, try counts(input: 1_000))])

        let stored = try await store.tokenSamples(accountID: account, interval: DateInterval(start: at(0), end: at(30)))
        #expect(stored.count == 4)
        let first = try #require(stored.first { $0.sessionID == "s1" && $0.model == "gpt-5.5" && $0.at == at(0) })
        #expect(first.delta == (try counts(input: 1_150, cached: 1_000, write: 7, output: 15, reasoning: 4)))
        // Only the folder name is stored, never the full path.
        #expect(first.project == "app")
        #expect(stored.contains { $0.sessionID == "s1" && $0.at == at(5) && $0.delta.input == 1 })
        #expect(stored.contains { $0.model == "gpt-5.5-mini" && $0.delta.output == 3 })
        let unknownProject = try #require(stored.first { $0.sessionID == "s2" })
        #expect(unknownProject.project == nil)
        #expect(unknownProject.delta.input == 9)
        #expect(stored.map(\.at) == stored.map(\.at).sorted())
    }

    @Test("Buckets overlapping the interval are returned, others are not")
    func interval() async throws {
        let directory = try TemporaryDirectory()
        let store = try UsageHistoryStore(databaseURL: directory.file("history.sqlite"))
        let account = AccountID()
        try await store.addTokenSamples([
            try sample("early", account: account, at: 1, try counts(input: 1)),
            try sample("straddling", account: account, at: 12, try counts(input: 1)),
            try sample("inside", account: account, at: 20, try counts(input: 1)),
            try sample("late", account: account, at: 36, try counts(input: 1)),
            try sample("other", account: AccountID(), at: 20, try counts(input: 1)),
        ])
        let stored = try await store.tokenSamples(accountID: account, interval: DateInterval(start: at(13), end: at(30)))
        #expect(stored.map(\.sessionID) == ["straddling", "inside"])
    }

    @Test("Totals sum a range per session, project and model with first and last buckets")
    func totals() async throws {
        let directory = try TemporaryDirectory()
        let store = try UsageHistoryStore(databaseURL: directory.file("history.sqlite"))
        let account = AccountID()
        try await store.addTokenSamples([
            try sample("s1", account: account, at: 0, try counts(input: 10, output: 1)),
            try sample("s1", account: account, at: 60, try counts(input: 20, output: 2)),
            try sample("s1", account: account, at: 120, project: "/Users/me/other", try counts(input: 5)),
            try sample("s2", account: account, at: 30, try counts(cached: 7)),
        ])
        let totals = try await store.tokenTotals(accountID: account, interval: DateInterval(start: at(0), end: at(180)))
        #expect(totals.map(\.sessionID) == ["s1", "s1", "s2"])
        let main = try #require(totals.first { $0.project == "app" && $0.sessionID == "s1" })
        #expect(main.counts == (try counts(input: 30, output: 3)))
        #expect(main.firstBucket == at(0))
        #expect(main.lastBucket == at(60))
        #expect(totals.first?.project == "other")
        #expect(try await store.tokenTotals(accountID: account, interval: DateInterval(start: at(200), end: at(300))).isEmpty)
    }

    @Test("Counts saturate instead of overflowing")
    func saturation() async throws {
        let directory = try TemporaryDirectory()
        let store = try UsageHistoryStore(databaseURL: directory.file("history.sqlite"))
        let account = AccountID()
        let huge = try counts(input: .max - 5, output: .max)
        try await store.addTokenSamples([try sample("s1", account: account, at: 0, huge)])
        try await store.addTokenSamples([try sample("s1", account: account, at: 1, try counts(input: 100, output: 1))])
        let stored = try await store.tokenSamples(accountID: account, interval: DateInterval(start: at(0), end: at(5)))
        #expect(stored.first?.delta.input == .max)
        #expect(stored.first?.delta.output == .max)
        let totals = try await store.tokenTotals(accountID: account, interval: DateInterval(start: at(0), end: at(5)))
        #expect(totals.first?.counts.output == .max)
    }

    @Test("Samples with absurd times never break the batch they arrive in")
    func extremeTimes() async throws {
        let directory = try TemporaryDirectory()
        let store = try UsageHistoryStore(databaseURL: directory.file("history.sqlite"))
        let account = AccountID()
        try await store.addTokenSamples([
            try TokenSample(
                accountID: account, sessionID: "ancient", project: nil, model: nil,
                at: Date(timeIntervalSince1970: -5e11), delta: try counts(input: 1)
            ),
            try TokenSample(
                accountID: account, sessionID: "distant", project: nil, model: nil,
                at: Date(timeIntervalSince1970: 5e11), delta: try counts(input: 1)
            ),
            try sample("s1", account: account, at: 0, try counts(input: 2)),
        ])
        let stored = try await store.tokenSamples(accountID: account, interval: DateInterval(start: at(0), end: at(5)))
        #expect(stored.map(\.delta.input) == [2])
    }

    @Test("Queries return at most the most recent maximumRows buckets")
    func bounded() async throws {
        let directory = try TemporaryDirectory()
        let store = try UsageHistoryStore(databaseURL: directory.file("history.sqlite"))
        let account = AccountID()
        let extra = 7
        let samples = try (0..<(UsageHistoryStore.maximumRows + extra)).map { index in
            try sample("s1", account: account, at: Double(index * 5), try counts(input: 1))
        }
        try await store.addTokenSamples(samples)
        let all = DateInterval(start: at(0), end: at(Double((UsageHistoryStore.maximumRows + extra) * 5)))
        let stored = try await store.tokenSamples(accountID: account, interval: all)
        #expect(stored.count == UsageHistoryStore.maximumRows)
        #expect(stored.first?.at == at(Double(extra * 5)))
        let totals = try await store.tokenTotals(accountID: account, interval: all)
        #expect(totals.first?.counts.input == Int64(UsageHistoryStore.maximumRows + extra))
    }
}

@Suite("History retention")
struct HistoryRetentionTests {
    @Test("Removing an account deletes its segments and token usage, and only its")
    func removeAccount() async throws {
        let directory = try TemporaryDirectory()
        let store = try UsageHistoryStore(databaseURL: directory.file("history.sqlite"))
        let account = AccountID()
        let kept = AccountID()
        for id in [account, kept] {
            try await store.openSegment(
                try SessionSegment(accountID: id, sessionID: "s1", title: nil, project: nil, activity: .working, start: at(0), end: nil),
                lastSeen: at(0)
            )
            try await store.addTokenSamples([try sample("s1", account: id, at: 0, try counts(input: 1))])
        }
        #expect(try await store.accountIDs() == [account, kept])

        try await store.removeAccount(account)
        let range = DateInterval(start: at(0), end: at(10))
        #expect(try await store.segments(accountID: account, interval: range).isEmpty)
        #expect(try await store.tokenSamples(accountID: account, interval: range).isEmpty)
        #expect(try await store.segments(accountID: kept, interval: range).count == 1)
        #expect(try await store.tokenSamples(accountID: kept, interval: range).count == 1)
        #expect(try await store.accountIDs() == [kept])
    }

    @Test("Collection runs overlapping a range are returned, pruned except the latest, and removed with the account")
    func collectionRuns() async throws {
        let directory = try TemporaryDirectory()
        let store = try UsageHistoryStore(databaseURL: directory.file("history.sqlite"))
        let account = AccountID()
        let other = AccountID()
        for minutes in [10.0, 50, 90, 50] {
            try await store.beginCollection(accountID: account, at: at(minutes))
        }
        try await store.beginCollection(accountID: other, at: at(60))

        func starts(_ from: Double, _ to: Double) async throws -> [Date] {
            try await store.collectionStarts(accountID: account, interval: DateInterval(start: at(from), end: at(to)))
        }
        // The run already going at the range's start, then every run starting inside it.
        #expect(try await starts(60, 100) == [at(50), at(90)])
        #expect(try await starts(50, 100) == [at(50), at(90)])
        #expect(try await starts(20, 40) == [at(10)])
        #expect(try await starts(0, 5).isEmpty)
        #expect(try await starts(0, 10) == [at(10)])
        #expect(try await starts(200, 300) == [at(90)])

        // Old runs go with retention, but the latest run of each account may still be going.
        try await store.prune(now: at(70).addingTimeInterval(UsageHistoryStore.defaultRetention))
        #expect(try await starts(0, 1_000) == [at(90)])
        let latest = at(90).addingTimeInterval(2 * UsageHistoryStore.defaultRetention)
        try await store.prune(now: latest)
        #expect(try await starts(0, 1_000) == [at(90)])
        #expect(try await store.collectionStarts(accountID: other, interval: DateInterval(start: at(0), end: at(100))) == [at(60)])

        try await store.removeAccount(account)
        #expect(try await starts(0, 1_000).isEmpty)
        #expect(try await store.accountIDs() == [other])
    }

    @Test("The first collection start is kept; removing the account forgets it")
    func collectionStart() async throws {
        let directory = try TemporaryDirectory()
        let store = try UsageHistoryStore(databaseURL: directory.file("history.sqlite"))
        let account = AccountID()
        #expect(try await store.collectionStart(accountID: account) == nil)
        try await store.beginCollection(accountID: account, at: at(10))
        try await store.beginCollection(accountID: account, at: at(20))
        #expect(try await store.collectionStart(accountID: account) == at(10))
        #expect(try await store.accountIDs() == [account])
        // Pruning never forgets when collection began.
        try await store.prune(now: at(10).addingTimeInterval(2 * UsageHistoryStore.defaultRetention))
        #expect(try await store.collectionStart(accountID: account) == at(10))

        try await store.removeAccount(account)
        #expect(try await store.collectionStart(accountID: account) == nil)
        #expect(try await store.accountIDs().isEmpty)
    }

    @Test("Pruning removes old closed segments and token buckets but keeps open segments")
    func prune() async throws {
        let directory = try TemporaryDirectory()
        let store = try UsageHistoryStore(databaseURL: directory.file("history.sqlite"))
        let account = AccountID()
        func segment(_ id: String, start: Double) throws -> SessionSegment {
            try SessionSegment(accountID: account, sessionID: id, title: nil, project: nil, activity: .working, start: at(start), end: nil)
        }
        try await store.openSegment(try segment("old", start: 0), lastSeen: at(0))
        try await store.closeSegment(try segment("old", start: 0), at: at(10))
        try await store.openSegment(try segment("recent", start: 20), lastSeen: at(20))
        try await store.closeSegment(try segment("recent", start: 20), at: at(40))
        try await store.openSegment(try segment("still-open", start: 5), lastSeen: at(5))
        try await store.addTokenSamples([
            try sample("old", account: account, at: 0, try counts(input: 1)),
            try sample("recent", account: account, at: 30, try counts(input: 1)),
        ])

        try await store.prune(now: at(30).addingTimeInterval(UsageHistoryStore.defaultRetention))
        let everything = DateInterval(start: .distantPast, end: .distantFuture)
        #expect(try await store.segments(accountID: account, interval: everything).map(\.sessionID) == ["still-open", "recent"])
        #expect(try await store.tokenSamples(accountID: account, interval: everything).map(\.sessionID) == ["recent"])
    }
}
