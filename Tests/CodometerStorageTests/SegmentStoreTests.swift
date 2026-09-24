import CodometerCore
import CodometerStorage
import Foundation
import Testing

private let base = Date(timeIntervalSince1970: 1_789_599_900)

private func at(_ minutes: Double) -> Date {
    base.addingTimeInterval(minutes * 60)
}

private func span(_ from: Double, _ to: Double) -> DateInterval {
    DateInterval(start: at(from), end: at(to))
}

private func segment(
    _ sessionID: String,
    _ activity: AgentActivity = .working,
    start: Double,
    account: AccountID,
    title: String? = "Задача",
    project: String? = "/Users/me/app"
) throws -> SessionSegment {
    try SessionSegment(
        accountID: account, sessionID: sessionID, title: title, project: project,
        activity: activity, start: at(start), end: nil
    )
}

private func makeStore(_ directory: TemporaryDirectory) throws -> UsageHistoryStore {
    try UsageHistoryStore(databaseURL: directory.file("history.sqlite"))
}

@Suite("Session segment storage")
struct SegmentStoreTests {
    @Test("Open segments are returned open, closed ones with their end")
    func openAndClose() async throws {
        let directory = try TemporaryDirectory()
        let store = try makeStore(directory)
        let account = AccountID()
        let working = try segment("s1", start: 0, account: account)
        let waiting = try segment("s1", .waiting, start: 10, account: account)

        try await store.openSegment(working, lastSeen: at(0))
        #expect(try await store.segments(accountID: account, interval: span(0, 60)).map(\.end) == [nil])

        try await store.closeSegment(working, at: at(10))
        try await store.openSegment(waiting, lastSeen: at(10))
        let stored = try await store.segments(accountID: account, interval: span(0, 60))
        #expect(stored.map(\.activity) == [.working, .waiting])
        #expect(stored.map(\.end) == [at(10), nil])
        // The session's own title is never stored: the label is the project folder and the end of the id.
        #expect(stored.first?.title == "app · s1")
        #expect(stored.first?.project == "app")
        #expect(stored.first?.id == working.id)
    }

    @Test("Only segments overlapping the interval are returned")
    func overlap() async throws {
        let directory = try TemporaryDirectory()
        let store = try makeStore(directory)
        let account = AccountID()
        let other = AccountID()
        for (id, start, end) in [("before", 0.0, 10.0), ("spanning", 5.0, 100.0), ("inside", 30.0, 40.0), ("after", 70.0, 80.0)] {
            let value = try segment(id, start: start, account: account)
            try await store.openSegment(value, lastSeen: at(start))
            try await store.closeSegment(value, at: at(end))
        }
        try await store.openSegment(try segment("open", start: 50, account: account), lastSeen: at(50))
        try await store.openSegment(try segment("foreign", start: 30, account: other), lastSeen: at(30))

        let stored = try await store.segments(accountID: account, interval: span(20, 60))
        #expect(stored.map(\.sessionID) == ["spanning", "inside", "open"])
        #expect(stored.last?.isOpen == true)
    }

    @Test("Reopening a segment clears its end and refreshes the project; ends never precede starts")
    func reopenAndClamp() async throws {
        let directory = try TemporaryDirectory()
        let store = try makeStore(directory)
        let account = AccountID()
        let first = try segment("s1", start: 0, account: account, project: "/Users/me/old")
        try await store.openSegment(first, lastSeen: at(0))
        try await store.closeSegment(first, at: at(5))
        try await store.openSegment(try segment("s1", start: 0, account: account, project: "/Users/me/new"), lastSeen: at(5))

        var stored = try await store.segments(accountID: account, interval: span(0, 60))
        #expect(stored.count == 1)
        #expect(stored.first?.isOpen == true)
        #expect(stored.first?.title == "new · s1")
        #expect(stored.first?.project == "new")

        try await store.closeSegment(first, at: at(-10))
        stored = try await store.segments(accountID: account, interval: span(0, 60))
        #expect(stored.first?.end == at(0))
    }

    @Test("Closing a segment whose open write was lost still records it")
    func closeWithoutOpen() async throws {
        let directory = try TemporaryDirectory()
        let store = try makeStore(directory)
        let account = AccountID()
        try await store.closeSegment(try segment("s1", .waiting, start: 1, account: account), at: at(2))
        let stored = try await store.segments(accountID: account, interval: span(0, 60))
        #expect(stored.map(\.end) == [at(2)])
        #expect(stored.map(\.activity) == [.waiting])
    }

    @Test("Dangling segments close at their last seen time; open ones close per account")
    func dangling() async throws {
        let directory = try TemporaryDirectory()
        let store = try makeStore(directory)
        let account = AccountID()
        let other = AccountID()
        let first = try segment("s1", start: 0, account: account)
        try await store.openSegment(first, lastSeen: at(0))
        try await store.touchOpenSegments(at: at(7))
        try await store.openSegment(try segment("s2", start: 3, account: account), lastSeen: at(3))
        try await store.touchSegment(try segment("s2", start: 3, account: account), at: at(9))
        try await store.openSegment(try segment("s3", start: 4, account: other), lastSeen: at(4))

        #expect(try await store.closeOpenSegments(accountID: other, at: at(20)) == 1)
        #expect(try await store.closeDanglingSegments() == 2)
        #expect(try await store.closeDanglingSegments() == 0)

        let stored = try await store.segments(accountID: account, interval: span(0, 60))
        #expect(stored.map(\.end) == [at(7), at(9)])
        #expect(try await store.segments(accountID: other, interval: span(0, 60)).map(\.end) == [at(20)])
    }

    @Test("Stored labels and projects are sanitised folder names")
    func sanitised() async throws {
        let directory = try TemporaryDirectory()
        let store = try makeStore(directory)
        let account = AccountID()
        let long = String(repeating: "я", count: 200)
        try await store.openSegment(try segment("s1", start: 0, account: account, project: "/tmp/p\u{0}x"), lastSeen: at(0))
        try await store.openSegment(try segment("s2", start: 0, account: account, project: "/tmp/\(long)/"), lastSeen: at(0))
        try await store.openSegment(try segment("s3", start: 0, account: account, project: nil), lastSeen: at(0))
        let stored = try await store.segments(accountID: account, interval: span(0, 1))
        #expect(stored.map(\.project) == ["px", String(repeating: "я", count: SessionLabel.maximumFolderLength - 1) + "…", nil])
        #expect(stored.map(\.title).first == "px · s1")
        #expect(stored.map(\.title).last == "s3")
        for title in stored.map(\.title) {
            #expect(title.count <= AgentSession.maximumTitleLength)
            #expect(!title.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) })
        }
    }

    @Test("A session's own title and full project path never reach the database file")
    func noSessionTitleOnDisk() async throws {
        let directory = try TemporaryDirectory()
        let store = try makeStore(directory)
        let account = AccountID()
        let secret = "Починить утечку ключей в billing-сервисе"
        let value = try segment("3f9a1c2b", start: 0, account: account, title: secret, project: "/Users/someone/billing")
        try await store.openSegment(value, lastSeen: at(0))
        try await store.closeSegment(value, at: at(3))

        let raw = try RawDatabase(path: directory.file("history.sqlite").path)
        #expect(try raw.column("SELECT title FROM session_segments") == ["billing · 9a1c2b"])
        #expect(try raw.column("SELECT project FROM session_segments") == ["billing"])
        #expect(try raw.column("SELECT count(*) FROM session_segments WHERE title LIKE '%утечку%' OR project LIKE '%someone%'") == ["0"])
    }
}
