import CodometerCore
import CodometerStorage
import Foundation
import Testing

private let base = Date(timeIntervalSince1970: 1_789_599_900)

private func at(_ minutes: Double) -> Date {
    base.addingTimeInterval(minutes * 60)
}

@Suite("Collection runs")
struct CollectionRunsTests {
    @Test("A run is opened, kept alive and ended with its reason")
    func lifecycle() async throws {
        let directory = try TemporaryDirectory()
        let store = try UsageHistoryStore(databaseURL: directory.file("history.sqlite"))
        let account = AccountID()
        try await store.beginCollection(accountID: account, at: at(0))
        try await store.touchCollectionRuns(at: at(30))
        let open = try await store.collectionRuns(accountID: account, interval: DateInterval(start: at(-10), end: at(60)))
        #expect(open.count == 1)
        #expect(open.first?.end == nil)
        #expect(open.first?.lastSeen == at(30))

        #expect(try await store.endCollectionRuns(accountID: nil, at: at(45), reason: .quit) == 1)
        let ended = try await store.collectionRuns(accountID: account, interval: DateInterval(start: at(-10), end: at(60)))
        #expect(ended.first?.end == at(45))
        #expect(ended.first?.endReason == .quit)
        // Ending twice changes nothing: only open runs are ended.
        #expect(try await store.endCollectionRuns(accountID: nil, at: at(50), reason: .sleep) == 0)
        #expect(try await store.collectionRuns(accountID: account, interval: DateInterval(start: at(-10), end: at(60))).first?.endReason == .quit)
    }

    @Test("Only the named account's runs are ended, and a new run closes an open one of the same account")
    func perAccount() async throws {
        let directory = try TemporaryDirectory()
        let store = try UsageHistoryStore(databaseURL: directory.file("history.sqlite"))
        let first = AccountID()
        let second = AccountID()
        try await store.beginCollection(accountID: first, at: at(0))
        try await store.beginCollection(accountID: second, at: at(0))
        #expect(try await store.endCollectionRuns(accountID: first, at: at(10), reason: .disabled) == 1)

        let window = DateInterval(start: at(-10), end: at(120))
        #expect(try await store.collectionRuns(accountID: first, interval: window).map(\.endReason) == [.disabled])
        #expect(try await store.collectionRuns(accountID: second, interval: window).map(\.endReason) == [nil])

        // A second run of the same account defensively closes the one still open.
        try await store.beginCollection(accountID: second, at: at(60))
        let runs = try await store.collectionRuns(accountID: second, interval: window)
        #expect(runs.map(\.start) == [at(0), at(60)])
        #expect(runs.map(\.endReason) == [.quit, nil])
        #expect(runs.first?.end == at(60))
    }

    @Test("Runs a crashed process left open are closed at their last heartbeat")
    func danglingRuns() async throws {
        let directory = try TemporaryDirectory()
        let store = try UsageHistoryStore(databaseURL: directory.file("history.sqlite"))
        let account = AccountID()
        try await store.beginCollection(accountID: account, at: at(0))
        try await store.touchCollectionRuns(at: at(25))
        #expect(try await store.closeDanglingCollectionRuns() == 1)
        let runs = try await store.collectionRuns(accountID: account, interval: DateInterval(start: at(-10), end: at(120)))
        #expect(runs.map(\.end) == [at(25)])
        #expect(runs.map(\.endReason) == [.crash])
        #expect(try await store.closeDanglingCollectionRuns() == 0)

        // A run without any heartbeat ends where it started.
        try await store.beginCollection(accountID: account, at: at(60))
        #expect(try await store.closeDanglingCollectionRuns() == 1)
        #expect(try await store.collectionRuns(accountID: account, interval: DateInterval(start: at(50), end: at(120))).last?.end == at(60))
    }

    @Test("A range returns the run it began inside and every later one, and the account's first start is kept")
    func overlapping() async throws {
        let directory = try TemporaryDirectory()
        let store = try UsageHistoryStore(databaseURL: directory.file("history.sqlite"))
        let account = AccountID()
        for start in [0.0, 100, 200, 300] {
            try await store.beginCollection(accountID: account, at: at(start))
            try await store.endCollectionRuns(accountID: account, at: at(start + 50), reason: .quit)
        }
        let runs = try await store.collectionRuns(accountID: account, interval: DateInterval(start: at(150), end: at(250)))
        #expect(runs.map(\.start) == [at(100), at(200)])
        #expect(try await store.collectionStarts(accountID: account, interval: DateInterval(start: at(150), end: at(250))) == [at(100), at(200)])
        #expect(try await store.collectionStart(accountID: account) == at(0))
    }

    @Test("Ends never precede starts, and unknown reasons are dropped on the way back")
    func clamping() async throws {
        let directory = try TemporaryDirectory()
        let store = try UsageHistoryStore(databaseURL: directory.file("history.sqlite"))
        let account = AccountID()
        try await store.beginCollection(accountID: account, at: at(100))
        try await store.touchCollectionRuns(at: at(10))
        try await store.endCollectionRuns(accountID: nil, at: at(20), reason: .sleep)
        let runs = try await store.collectionRuns(accountID: account, interval: DateInterval(start: at(0), end: at(200)))
        #expect(runs.map(\.start) == [at(100)])
        #expect(runs.map(\.end) == [at(100)])
        #expect(runs.map(\.lastSeen) == [at(100)])
    }

    @Test("Removing an account removes its runs")
    func removal() async throws {
        let directory = try TemporaryDirectory()
        let store = try UsageHistoryStore(databaseURL: directory.file("history.sqlite"))
        let account = AccountID()
        try await store.beginCollection(accountID: account, at: at(0))
        try await store.removeAccount(account)
        #expect(try await store.collectionRuns(accountID: account, interval: DateInterval(start: at(-10), end: at(10))).isEmpty)
    }
}
