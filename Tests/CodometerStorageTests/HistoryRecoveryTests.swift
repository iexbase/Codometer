import CodometerCore
@testable import CodometerStorage
import Foundation
import Testing

private let base = Date(timeIntervalSince1970: 1_789_599_900)

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

/// Names of every file in a folder, sorted.
private func names(in directory: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
}

@Suite("History recovery")
struct HistoryRecoveryTests {
    @Test("A file that is not a database is moved aside with its companions and replaced")
    func notADatabase() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.file("history.sqlite")
        try Data(repeating: 0x7A, count: 4_096).write(to: url)
        try Data("stale wal".utf8).write(to: URL(fileURLWithPath: url.path + "-wal"))

        guard case let .opened(store, health) = UsageHistoryStore.open(databaseURL: url) else {
            Issue.record("expected a recovered store")
            return
        }
        guard case .recoveredFromCorruption(let backup) = health else {
            Issue.record("expected recovery, got \(health)")
            return
        }
        #expect(backup.hasPrefix(UsageHistoryStore.corruptPrefix))
        #expect(backup.hasSuffix(".sqlite"))
        let saved = try names(in: directory.url)
        #expect(saved.contains(backup))
        #expect(saved.contains(backup + "-wal"))
        // The moved-aside copy stays private.
        let mode = try FileManager.default.attributesOfItem(atPath: directory.file(backup).path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
        // The replacement is a working, writable database.
        #expect(await store.allowsWrites)
        let account = AccountID()
        try await store.record(try reading(used: 12, at: base), identity: nil, for: account)
        #expect(try await store.samples(accountID: account, bucketID: "claude", windowID: "session", since: .distantPast).count == 1)
        // Diagnostics keep reporting the recovery for as long as the fresh file is open.
        #expect(store.initialHealth == health)
        #expect(await store.health == health)
        #expect(await store.diagnostics().health == health)
    }

    @Test("A full disk during a launch that recovered does not erase the recovery from diagnostics")
    func recoveryOutlivesAPausedWrite() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.file("history.sqlite")
        try Data(repeating: 0x7A, count: 4_096).write(to: url)
        guard case let .opened(store, health) = UsageHistoryStore.open(databaseURL: url),
              case .recoveredFromCorruption = health else {
            Issue.record("expected a recovered store")
            return
        }
        let account = AccountID()
        try await store.setMaximumPageCount(2)
        await #expect(throws: SQLiteError.self) {
            for minute in 1...400 {
                try await store.record(
                    try reading(used: Double(minute % 90), at: base.addingTimeInterval(Double(minute) * 60)),
                    identity: nil,
                    for: account
                )
            }
        }
        guard case .writesPaused = await store.health else {
            Issue.record("expected writes to be paused, got \(await store.health)")
            return
        }
        try await store.setMaximumPageCount(100_000)
        try await store.prune(now: base)
        #expect(await store.health == health)
        #expect(await store.allowsWrites)
    }

    @Test("A database with damaged pages is recovered, and the healthy one is left alone")
    func damagedPages() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.file("history.sqlite")
        let account = AccountID()
        do {
            let store = try UsageHistoryStore(databaseURL: url)
            for minute in 0..<200 {
                try await store.record(
                    try reading(used: Double(minute % 90), at: base.addingTimeInterval(Double(minute) * 60)),
                    identity: nil,
                    for: account
                )
            }
            await store.close()
        }
        // Healthy: opened as it is.
        guard case .opened(_, let healthy) = UsageHistoryStore.open(databaseURL: url) else {
            Issue.record("expected an opened store")
            return
        }
        #expect(healthy == .ok)

        // Scribble over everything after the header page: SQLite still opens the file, and the damage shows up in
        // `quick_check` (or in the first read of a table).
        let size = try #require(FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber).intValue
        #expect(size > 8_192)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seek(toOffset: 4_096)
        try handle.write(contentsOf: Data(repeating: 0xFF, count: size - 4_096))
        try handle.close()

        guard case .opened(_, let health) = UsageHistoryStore.open(databaseURL: url) else {
            Issue.record("expected a recovered store")
            return
        }
        guard case .recoveredFromCorruption = health else {
            Issue.record("expected recovery, got \(health)")
            return
        }
        #expect(try names(in: directory.url).contains { $0.hasPrefix(UsageHistoryStore.corruptPrefix) })
    }

    @Test("A file a newer build forbids older writers to touch opens read-only and is never written")
    func newerSchemaIsReadOnly() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.file("history.sqlite")
        let account = AccountID()
        do {
            let store = try UsageHistoryStore(databaseURL: url)
            try await store.record(try reading(used: 30, at: base), identity: nil, for: account)
            await store.close()
        }
        let raw = try RawDatabase(path: url.path)
        try raw.execute("""
            INSERT INTO schema_version (version) VALUES (5);
            UPDATE schema_meta SET value = '5' WHERE key = 'min_reader_version';
            """)

        guard case let .opened(store, health) = UsageHistoryStore.open(databaseURL: url) else {
            Issue.record("expected an opened store")
            return
        }
        #expect(health == .readOnlyNewerSchema(version: 5))
        #expect(await store.allowsWrites == false)
        // Reads still work.
        #expect(try await store.samples(accountID: account, bucketID: "claude", windowID: "session", since: .distantPast).count == 1)
        // Writes and pruning do nothing at all.
        try await store.record(try reading(used: 80, at: base.addingTimeInterval(3_600)), identity: nil, for: account)
        try await store.prune(now: base.addingTimeInterval(400 * 86_400))
        #expect(try await store.samples(accountID: account, bucketID: "claude", windowID: "session", since: .distantPast).map(\.used.value) == [30])
        #expect(try await store.closeDanglingSegments() == 0)
        let diagnostics = await store.diagnostics()
        #expect(diagnostics.health == .readOnlyNewerSchema(version: 5))
    }

    @Test("A newer file that still allows this writer stays writable")
    func newerSchemaWithOlderReaderStaysWritable() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.file("history.sqlite")
        do {
            let store = try UsageHistoryStore(databaseURL: url)
            await store.close()
        }
        let raw = try RawDatabase(path: url.path)
        try raw.execute("INSERT INTO schema_version (version) VALUES (5)")

        let store = try UsageHistoryStore(databaseURL: url)
        #expect(store.initialHealth == .ok)
        #expect(await store.allowsWrites)
    }

    @Test("A full database pauses writes and picks them up again at the next maintenance")
    func diskFullPausesWrites() async throws {
        let directory = try TemporaryDirectory()
        let store = try UsageHistoryStore(databaseURL: directory.file("history.sqlite"))
        let account = AccountID()
        try await store.record(try reading(used: 10, at: base), identity: nil, for: account)
        try await store.setMaximumPageCount(2)

        await #expect(throws: SQLiteError.self) {
            for minute in 1...400 {
                try await store.record(
                    try reading(used: Double(minute % 90), at: base.addingTimeInterval(Double(minute) * 60)),
                    identity: nil,
                    for: account
                )
            }
        }
        guard case .writesPaused = await store.health else {
            Issue.record("expected writes to be paused, got \(await store.health)")
            return
        }
        #expect(await store.allowsWrites == false)
        // A write while paused is skipped silently instead of throwing again.
        try await store.record(try reading(used: 99, at: base.addingTimeInterval(500 * 60)), identity: nil, for: account)

        // Maintenance retries: with room again, writes resume.
        try await store.setMaximumPageCount(100_000)
        try await store.prune(now: base)
        #expect(await store.health == .ok)
        #expect(await store.allowsWrites)
        try await store.record(try reading(used: 44, at: base.addingTimeInterval(600 * 60)), identity: nil, for: account)
        let samples = try await store.samples(accountID: account, bucketID: "claude", windowID: "session", since: .distantPast)
        #expect(samples.map(\.used.value).contains(44))
    }

    @Test("A closed store refuses every later call, and its files can be removed")
    func closedStore() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.file("history.sqlite")
        let store = try UsageHistoryStore(databaseURL: url)
        let account = AccountID()
        try await store.record(try reading(used: 10, at: base), identity: nil, for: account)
        await store.close()
        await store.close()

        await #expect(throws: SQLiteError.closed) {
            try await store.record(try reading(used: 20, at: base), identity: nil, for: account)
        }
        await #expect(throws: SQLiteError.closed) {
            _ = try await store.samples(accountID: account, bucketID: "claude", windowID: "session", since: .distantPast)
        }
        #expect(await store.quickCheck(timeout: 1) == nil)
        try FileManager.default.removeItem(at: url)
        #expect(FileManager.default.fileExists(atPath: url.path) == false)
    }
}
