import CodometerCore
import CodometerStorage
import Foundation
import SQLite3
import Testing

/// A raw SQLite handle for building and inspecting database files independently of the store.
final class RawDatabase {
    private var handle: OpaquePointer?

    init(path: String) throws {
        guard sqlite3_open(path, &handle) == SQLITE_OK else {
            sqlite3_close(handle)
            throw RawDatabaseError(message: "open failed")
        }
    }

    deinit {
        sqlite3_close(handle)
    }

    func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            throw RawDatabaseError(message: String(cString: sqlite3_errmsg(handle)))
        }
    }

    /// The first column of every row as text (NULL as "NULL").
    func column(_ sql: String) throws -> [String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw RawDatabaseError(message: String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        var values: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            values.append(sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? "NULL")
        }
        return values
    }
}

struct RawDatabaseError: Error {
    let message: String
}

/// The exact schema release 1 created.
private let version1Schema = """
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
    INSERT INTO schema_version (version) VALUES (1);
    """

/// The tables release 2 added on top of `version1Schema`.
private let version2Additions = """
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
    CREATE INDEX session_segments_by_start ON session_segments (account_id, started_at);
    CREATE INDEX session_segments_open ON session_segments (account_id) WHERE ended_at IS NULL;
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
    INSERT INTO schema_version (version) VALUES (2);
    """

private let base = Date(timeIntervalSince1970: 1_789_599_900)

@Suite("History schema migration")
struct HistoryMigrationTests {
    @Test("A release 1 database upgrades in place and keeps its data")
    func upgradesVersion1() async throws {
        let directory = try TemporaryDirectory()
        let path = directory.file("history.sqlite").path
        let accountID = AccountID()
        do {
            let raw = try RawDatabase(path: path)
            try raw.execute(version1Schema)
            try raw.execute("""
                INSERT INTO limit_samples VALUES
                ('\(accountID)', 'claude', 'session', \(base.timeIntervalSince1970), 42, 300, NULL, 'claudeUsageCommand');
                INSERT INTO last_state VALUES ('\(accountID)', NULL, NULL, \(base.timeIntervalSince1970));
                """)
        }

        let store = try UsageHistoryStore(databaseURL: URL(fileURLWithPath: path))
        let samples = try await store.samples(accountID: accountID, bucketID: "claude", windowID: "session", since: .distantPast)
        #expect(samples.map(\.used.value) == [42])
        #expect(try await store.accountIDs() == [accountID])

        let segment = try SessionSegment(
            accountID: accountID, sessionID: "s1", title: "Работа", project: "/Users/me/app",
            activity: .working, start: base, end: nil
        )
        try await store.openSegment(segment, lastSeen: base)
        try await store.addTokenSamples([
            try TokenSample(
                accountID: accountID, sessionID: "s1", project: "/Users/me/app", model: "claude-fable-5",
                at: base, delta: try TokenCounts(input: 10, cachedInput: 0, cacheWrite: 0, output: 1, reasoningOutput: 0)
            ),
        ])
        let week = DateInterval(start: base.addingTimeInterval(-3_600), duration: 7 * 86_400)
        #expect(try await store.segments(accountID: accountID, interval: week).map(\.sessionID) == ["s1"])
        #expect(try await store.tokenSamples(accountID: accountID, interval: week).count == 1)

        let raw = try RawDatabase(path: path)
        #expect(try raw.column("SELECT version FROM schema_version ORDER BY version") == ["1", "2", "3", "4"])
        let indexes = try raw.column("SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'session_segments_%' ORDER BY name")
        #expect(indexes == ["session_segments_by_start", "session_segments_open"])
    }

    @Test("A new database gets every table, and reopening does not migrate again")
    func newDatabase() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.file("history.sqlite")
        do {
            _ = try UsageHistoryStore(databaseURL: url)
        }
        _ = try UsageHistoryStore(databaseURL: url)
        let raw = try RawDatabase(path: url.path)
        #expect(try raw.column("SELECT version FROM schema_version ORDER BY version") == ["1", "2", "3", "4"])
        let tables = try raw.column("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")
        #expect(tables == [
            "collection_runs", "collection_starts", "last_state", "limit_samples", "schema_meta", "schema_version",
            "session_segments", "token_usage",
        ])
    }

    @Test("A release 2 database drops session titles and full project paths, merging token rows, and seeds a run")
    func upgradesVersion2() async throws {
        let directory = try TemporaryDirectory()
        let path = directory.file("history.sqlite").path
        let account = AccountID()
        let start = base.timeIntervalSince1970
        let bucket = Int64(start)
        do {
            let raw = try RawDatabase(path: path)
            try raw.execute(version1Schema)
            try raw.execute(version2Additions)
            try raw.execute("""
                INSERT INTO collection_starts VALUES ('\(account)', \(start - 600));
                INSERT INTO session_segments VALUES
                    ('\(account)', '4ecca291-a70a-4fe9-9306-426595e70d2d', 'Секретный план по переезду', '/Users/me/Project Путь/',
                     'working', \(start), \(start + 60), \(start + 60)),
                    ('\(account)', 'short', 'Ещё одно название', NULL, 'waiting', \(start), NULL, \(start)),
                    ('\(account)', 'plain', 'Название', 'Codometer', 'working', \(start), NULL, \(start));
                INSERT INTO token_usage VALUES
                    ('\(account)', 'c1', '/Users/me/app', 'gpt-5.5', \(bucket), 10, 1, 0, 2, 3),
                    ('\(account)', 'c1', '/Volumes/work/app', 'gpt-5.5', \(bucket), 5, 0, 0, 1, 0),
                    ('\(account)', 'c1', 'app', 'gpt-5.5', \(bucket), 9223372036854775800, 0, 0, 0, 0),
                    ('\(account)', 'c2', '/', '', \(bucket), 7, 0, 0, 0, 0),
                    ('\(account)', 'c3', 'Codometer', 'claude-opus-5', \(bucket), 4, 0, 0, 0, 0);
                """)
        }

        let store = try UsageHistoryStore(databaseURL: URL(fileURLWithPath: path))
        let raw = try RawDatabase(path: path)
        #expect(try raw.column("SELECT version FROM schema_version ORDER BY version") == ["1", "2", "3", "4"])
        #expect(try raw.column("SELECT title || ' | ' || coalesce(project, 'NULL') FROM session_segments ORDER BY session_id") == [
            "Project Путь · e70d2d | Project Путь",
            "Codometer · plain | Codometer",
            "сессия short | NULL",
        ])
        #expect(try raw.column("SELECT count(*) FROM session_segments WHERE title LIKE '%план%' OR title LIKE '%назван%'") == ["0"])
        #expect(try raw.column("""
            SELECT session_id || ' ' || project || ' ' || input || ' ' || cached_input || ' ' || output || ' ' || reasoning_output
            FROM token_usage ORDER BY session_id, project
            """) == [
                "c1 app 9223372036854775807 1 3 3",
                "c2  7 0 0 0",
                "c3 Codometer 4 0 0 0",
            ])
        #expect(try raw.column("SELECT count(*) FROM token_usage WHERE instr(project, '/') > 0") == ["0"])

        // The existing collection start becomes the first run; reads rebuild labels from the id and folder.
        let week = DateInterval(start: base.addingTimeInterval(-3_600), duration: 7 * 86_400)
        #expect(try await store.collectionStarts(accountID: account, interval: week) == [base.addingTimeInterval(-600)])
        let segments = try await store.segments(accountID: account, interval: week)
        // Reads rebuild the language-neutral stored form; the release 2 wording written by the migration is never read.
        #expect(Set(segments.map(\.title)) == ["Project Путь · e70d2d", "Codometer · plain", "short"])
    }

    @Test("Upgrading a release 2 database leaves no copy of old session titles or paths in any of its files")
    func scrubsOldContent() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.file("history.sqlite")
        let account = AccountID()
        let secret = "SecretConversationSummary"
        let raw = try RawDatabase(path: url.path)
        try raw.execute("PRAGMA journal_mode = WAL")
        try raw.execute(version1Schema)
        try raw.execute(version2Additions)
        // Many versions of the row in the WAL, like `last_seen` touches of a run that never closed its connection.
        try raw.execute("""
            INSERT INTO session_segments VALUES
            ('\(account)', 's1', '\(secret)', '/Users/secretuser/app', 'working', \(base.timeIntervalSince1970), NULL, 0);
            """)
        for touch in 1...50 {
            try raw.execute("UPDATE session_segments SET last_seen = \(touch)")
        }

        // Inspected while connections are still open: closing the last one would checkpoint and delete the WAL,
        // which an app that is quit or crashes does not get to do.
        let store = try UsageHistoryStore(databaseURL: url)
        for suffix in ["", "-wal", "-shm"] where FileManager.default.fileExists(atPath: url.path + suffix) {
            let bytes = try Data(contentsOf: URL(fileURLWithPath: url.path + suffix))
            #expect(bytes.range(of: Data(secret.utf8)) == nil, "found in \(suffix)")
            #expect(bytes.range(of: Data("secretuser".utf8)) == nil, "found in \(suffix)")
        }
        let week = DateInterval(start: base.addingTimeInterval(-3_600), duration: 7 * 86_400)
        #expect(try await store.segments(accountID: account, interval: week).map(\.title) == ["app · s1"])
    }

    @Test("Database files are owner-only, existing ones are tightened, and symlinks are refused")
    func privateFiles() async throws {
        func permissions(_ path: String) throws -> Int {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
        }
        let directory = try TemporaryDirectory()
        let url = directory.file("history.sqlite")
        do {
            let store = try UsageHistoryStore(databaseURL: url)
            try await store.beginCollection(accountID: AccountID(), at: base)
            for suffix in ["", "-wal", "-shm"] {
                #expect(try permissions(url.path + suffix) == 0o600)
            }
        }

        // A file left world-readable by an older version, with its WAL.
        let loose = directory.file("loose.sqlite")
        do {
            let raw = try RawDatabase(path: loose.path)
            try raw.execute("PRAGMA journal_mode = WAL; CREATE TABLE t (x); INSERT INTO t VALUES (1);")
            for suffix in ["", "-wal", "-shm"] where FileManager.default.fileExists(atPath: loose.path + suffix) {
                try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: loose.path + suffix)
            }
            _ = try UsageHistoryStore(databaseURL: loose)
            for suffix in ["", "-wal", "-shm"] where FileManager.default.fileExists(atPath: loose.path + suffix) {
                #expect(try permissions(loose.path + suffix) == 0o600)
            }
        }

        let target = directory.file("target.sqlite")
        _ = try UsageHistoryStore(databaseURL: target)
        let link = directory.file("link.sqlite")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(throws: SQLiteError.self) { try UsageHistoryStore(databaseURL: link) }

        let companionLink = directory.file("companion.sqlite")
        try FileManager.default.createSymbolicLink(atPath: companionLink.path + "-wal", withDestinationPath: target.path)
        #expect(throws: SQLiteError.self) { try UsageHistoryStore(databaseURL: companionLink) }
    }

    @Test("A database from a newer release is opened without migrating it")
    func newerVersion() throws {
        let directory = try TemporaryDirectory()
        let path = directory.file("history.sqlite").path
        do {
            let raw = try RawDatabase(path: path)
            try raw.execute(version1Schema)
            try raw.execute("INSERT INTO schema_version (version) VALUES (5)")
        }
        _ = try UsageHistoryStore(databaseURL: URL(fileURLWithPath: path))
        let raw = try RawDatabase(path: path)
        #expect(try raw.column("SELECT version FROM schema_version ORDER BY version") == ["1", "5"])
        #expect(try raw.column("SELECT name FROM sqlite_master WHERE name = 'token_usage'").isEmpty)
    }
}
