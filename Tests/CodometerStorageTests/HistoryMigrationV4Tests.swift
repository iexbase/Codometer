import CodometerCore
import CodometerStorage
import Foundation
import Testing

/// The exact schema release 2 created, as version 3 left it (collection runs without an end).
private let version3Schema = """
    CREATE TABLE schema_version (version INTEGER NOT NULL);
    CREATE TABLE limit_samples (
        account_id TEXT NOT NULL,
        bucket_id TEXT NOT NULL,
        window_id TEXT NOT NULL,
        captured_at REAL NOT NULL,
        used_percent REAL NOT NULL CHECK (used_percent >= 0 AND used_percent <= 1000),
        duration_minutes INTEGER,
        resets_at REAL,
        source TEXT NOT NULL,
        PRIMARY KEY (account_id, bucket_id, window_id, captured_at)
    ) WITHOUT ROWID;
    CREATE TABLE last_state (
        account_id TEXT PRIMARY KEY NOT NULL,
        reading_json BLOB,
        identity_json BLOB,
        updated_at REAL NOT NULL
    );
    CREATE TABLE session_segments (
        account_id TEXT NOT NULL,
        session_id TEXT NOT NULL,
        title TEXT NOT NULL,
        project TEXT,
        activity TEXT NOT NULL CHECK (activity IN ('working', 'waiting')),
        started_at REAL NOT NULL,
        ended_at REAL CHECK (ended_at IS NULL OR ended_at >= started_at),
        last_seen REAL NOT NULL,
        PRIMARY KEY (account_id, session_id, activity, started_at)
    ) WITHOUT ROWID;
    CREATE TABLE token_usage (
        account_id TEXT NOT NULL,
        session_id TEXT NOT NULL,
        project TEXT NOT NULL DEFAULT '',
        model TEXT NOT NULL DEFAULT '',
        bucket_start INTEGER NOT NULL CHECK (bucket_start % 300 = 0),
        input INTEGER NOT NULL DEFAULT 0 CHECK (input >= 0),
        cached_input INTEGER NOT NULL DEFAULT 0 CHECK (cached_input >= 0),
        cache_write INTEGER NOT NULL DEFAULT 0 CHECK (cache_write >= 0),
        output INTEGER NOT NULL DEFAULT 0 CHECK (output >= 0),
        reasoning_output INTEGER NOT NULL DEFAULT 0 CHECK (reasoning_output >= 0),
        PRIMARY KEY (account_id, bucket_start, session_id, project, model)
    ) WITHOUT ROWID;
    CREATE TABLE collection_starts (
        account_id TEXT PRIMARY KEY NOT NULL,
        started_at REAL NOT NULL
    ) WITHOUT ROWID;
    CREATE TABLE collection_runs (
        account_id TEXT NOT NULL,
        started_at REAL NOT NULL,
        PRIMARY KEY (account_id, started_at)
    ) WITHOUT ROWID;
    INSERT INTO schema_version (version) VALUES (1);
    INSERT INTO schema_version (version) VALUES (2);
    INSERT INTO schema_version (version) VALUES (3);
    """

private let base = Date(timeIntervalSince1970: 1_789_599_900)

private func at(_ minutes: Double) -> Date {
    base.addingTimeInterval(minutes * 60)
}

@Suite("History schema v4")
struct HistoryMigrationV4Tests {
    /// A version 3 file with three runs of one account: the first has a limit sample in it, the second a segment
    /// heartbeat, the third no evidence at all, and the newest one is still open.
    private func makeVersion3(at path: String, account: AccountID, other: AccountID) throws {
        let raw = try RawDatabase(path: path)
        try raw.execute(version3Schema)
        func seconds(_ minutes: Double) -> String { "\(at(minutes).timeIntervalSince1970)" }
        try raw.execute("""
            INSERT INTO collection_runs VALUES
                ('\(account)', \(seconds(0))),
                ('\(account)', \(seconds(120))),
                ('\(account)', \(seconds(300))),
                ('\(account)', \(seconds(600))),
                ('\(other)', \(seconds(60)));
            INSERT INTO limit_samples VALUES
                ('\(account)', 'claude', 'session', \(seconds(40)), 42, 300, NULL, 'claudeUsageCommand'),
                ('\(account)', 'claude', 'session', \(seconds(700)), 44, 300, NULL, 'claudeUsageCommand');
            INSERT INTO session_segments VALUES
                ('\(account)', 's1', 'app · s1', 'app', 'working', \(seconds(130)), \(seconds(150)), \(seconds(155)));
            """)
    }

    @Test("Version 3 runs are given ends from the evidence inside them, and the newest stays open")
    func backfillsEnds() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.file("history.sqlite")
        let account = AccountID()
        let other = AccountID()
        try makeVersion3(at: url.path, account: account, other: other)

        let store = try UsageHistoryStore(databaseURL: url)
        let raw = try RawDatabase(path: url.path)
        #expect(try raw.column("SELECT version FROM schema_version ORDER BY version") == ["1", "2", "3", "4"])
        #expect(try raw.column("SELECT value FROM schema_meta WHERE key = 'min_reader_version'") == ["4"])

        let runs = try await store.collectionRuns(
            accountID: account,
            interval: DateInterval(start: at(-60), end: at(1_000))
        )
        #expect(runs.map(\.start) == [at(0), at(120), at(300), at(600)])
        // The first run ends at its newest limit sample, the second at the segment's heartbeat, the third has no
        // evidence and ends where it started; the newest run of the account is still open.
        #expect(runs.map(\.end) == [at(40), at(155), at(300), nil])
        #expect(runs.map(\.endReason) == [.inferred, .inferred, .inferred, nil])
        // The other account's only run is its newest, so it stays open too.
        let others = try await store.collectionRuns(accountID: other, interval: DateInterval(start: at(-60), end: at(1_000)))
        #expect(others.map(\.end) == [nil])
    }

    @Test("Migrating twice changes nothing")
    func idempotent() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.file("history.sqlite")
        let account = AccountID()
        try makeVersion3(at: url.path, account: account, other: AccountID())
        let interval = DateInterval(start: at(-60), end: at(1_000))
        let first: [CollectionRun]
        do {
            let store = try UsageHistoryStore(databaseURL: url)
            first = try await store.collectionRuns(accountID: account, interval: interval)
        }
        let store = try UsageHistoryStore(databaseURL: url)
        #expect(try await store.collectionRuns(accountID: account, interval: interval) == first)
        let raw = try RawDatabase(path: url.path)
        #expect(try raw.column("SELECT version FROM schema_version ORDER BY version") == ["1", "2", "3", "4"])
        #expect(try raw.column("SELECT count(*) FROM schema_meta") == ["1"])
    }

    @Test("A fresh database records the version a writer must understand")
    func freshDatabase() async throws {
        let directory = try TemporaryDirectory()
        let store = try UsageHistoryStore(databaseURL: directory.file("history.sqlite"))
        #expect(store.initialHealth == .ok)
        #expect(await store.allowsWrites)
        let raw = try RawDatabase(path: directory.file("history.sqlite").path)
        #expect(try raw.column("SELECT value FROM schema_meta WHERE key = 'min_reader_version'") == ["4"])
    }

    @Test("Only a reason the app can write is accepted by the column's check")
    func endReasonCheck() throws {
        let directory = try TemporaryDirectory()
        let url = directory.file("history.sqlite")
        _ = try UsageHistoryStore(databaseURL: url)
        let raw = try RawDatabase(path: url.path)
        let account = AccountID()
        try raw.execute("INSERT INTO collection_runs (account_id, started_at) VALUES ('\(account)', 1)")
        for reason in CollectionRun.EndReason.allCases {
            try raw.execute("UPDATE collection_runs SET end_reason = '\(reason.rawValue)'")
        }
        #expect(throws: RawDatabaseError.self) {
            try raw.execute("UPDATE collection_runs SET end_reason = 'wandered off'")
        }
    }
}
