import Foundation

/// The history database's tables and the steps that upgrade older files in place.
///
/// Each migration runs in its own transaction and records its version, so a database written by any earlier
/// release is brought forward step by step and a new database gets every table at once. A file from a newer
/// release (higher version) is left untouched.
enum HistorySchema {
    static let currentVersion: Int64 = 4
    /// The oldest schema version that may still write this file, recorded in `schema_meta`.
    ///
    /// A build that understands less than the file's `min_reader_version` opens it read-only instead of
    /// migrating or writing it.
    static let minimumReaderVersion: Int64 = 4
    static let schemaMetaTable = "schema_meta"
    static let minimumReaderVersionKey = "min_reader_version"

    /// A version and the statements that create it from the previous version.
    struct Migration: Sendable {
        let version: Int64
        let statements: [String]
        /// Whether the migration rewrites data that must not survive anywhere in the files: SQLite leaves the old
        /// bytes of rewritten rows in free page space and in WAL frames, so the file is rebuilt afterwards.
        var scrubsOldContent = false
    }

    static let migrations: [Migration] = [
        Migration(version: 1, statements: [
            """
            CREATE TABLE IF NOT EXISTS limit_samples (
                account_id TEXT NOT NULL,
                bucket_id TEXT NOT NULL,
                window_id TEXT NOT NULL,
                captured_at REAL NOT NULL,
                used_percent REAL NOT NULL CHECK (used_percent >= 0 AND used_percent <= 1000),
                duration_minutes INTEGER,
                resets_at REAL,
                source TEXT NOT NULL,
                PRIMARY KEY (account_id, bucket_id, window_id, captured_at)
            ) WITHOUT ROWID
            """,
            """
            CREATE TABLE IF NOT EXISTS last_state (
                account_id TEXT PRIMARY KEY NOT NULL,
                reading_json BLOB,
                identity_json BLOB,
                updated_at REAL NOT NULL
            )
            """,
        ]),
        Migration(version: 2, statements: [
            // Working and waiting stretches of sessions. `last_seen` is refreshed while a segment is open, so a
            // segment left open by a crash can be closed where it was last known to be active.
            """
            CREATE TABLE IF NOT EXISTS session_segments (
                account_id TEXT NOT NULL,
                session_id TEXT NOT NULL,
                title TEXT NOT NULL,
                project TEXT,
                activity TEXT NOT NULL CHECK (activity IN ('working', 'waiting')),
                started_at REAL NOT NULL,
                ended_at REAL CHECK (ended_at IS NULL OR ended_at >= started_at),
                last_seen REAL NOT NULL,
                PRIMARY KEY (account_id, session_id, activity, started_at)
            ) WITHOUT ROWID
            """,
            "CREATE INDEX IF NOT EXISTS session_segments_by_start ON session_segments (account_id, started_at)",
            "CREATE INDEX IF NOT EXISTS session_segments_open ON session_segments (account_id) WHERE ended_at IS NULL",
            // Token counts per session, project and model in 5-minute buckets. Unknown project or model is ''.
            """
            CREATE TABLE IF NOT EXISTS token_usage (
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
            ) WITHOUT ROWID
            """,
            // When live segment and token collection first started for an account, so views can tell
            // "nothing was collected yet" apart from "nothing happened".
            """
            CREATE TABLE IF NOT EXISTS collection_starts (
                account_id TEXT PRIMARY KEY NOT NULL,
                started_at REAL NOT NULL
            ) WITHOUT ROWID
            """,
        ]),
        Migration(version: 3, statements: [
            // Every start of live collection (launch, wake, account enabled), so usage from while the app was not
            // collecting is never attributed to the projects whose tokens were recorded.
            """
            CREATE TABLE IF NOT EXISTS collection_runs (
                account_id TEXT NOT NULL,
                started_at REAL NOT NULL,
                PRIMARY KEY (account_id, started_at)
            ) WITHOUT ROWID
            """,
            "INSERT OR IGNORE INTO collection_runs (account_id, started_at) SELECT account_id, started_at FROM collection_starts",
            // Session titles can carry conversation content (Claude names sessions after the conversation), and
            // projects were stored as full paths: keep only the project folder, and a title made from it and the
            // end of the session id. Reads rebuild the title with `SessionLabel.neutral`, so the wording written
            // here (release 2's) is historical and never shown.
            """
            UPDATE session_segments SET project = NULLIF(\(folderName(of: "project")), '')
            WHERE project IS NOT NULL AND instr(project, '/') > 0
            """,
            """
            UPDATE session_segments SET title = CASE
                WHEN project IS NULL OR project = '' THEN '\(v3UnnamedSessionPrefix)' || substr(session_id, -6)
                ELSE project || ' · ' || substr(session_id, -6)
            END
            """,
            // Token rows keyed by a full path move to the folder, adding up with any row already there.
            """
            INSERT INTO token_usage
            (account_id, session_id, project, model, bucket_start, input, cached_input, cache_write, output, reasoning_output)
            SELECT account_id, session_id, \(folderName(of: "project")), model, bucket_start,
                input, cached_input, cache_write, output, reasoning_output
            FROM token_usage WHERE instr(project, '/') > 0
            ON CONFLICT (account_id, bucket_start, session_id, project, model) DO UPDATE SET
                input = \(saturatingSum("input")),
                cached_input = \(saturatingSum("cached_input")),
                cache_write = \(saturatingSum("cache_write")),
                output = \(saturatingSum("output")),
                reasoning_output = \(saturatingSum("reasoning_output"))
            """,
            "DELETE FROM token_usage WHERE instr(project, '/') > 0",
        ], scrubsOldContent: true),
        Migration(version: 4, statements: [
            // Collection runs gain an end, a heartbeat and a reason, so the timeline can tell a quiet stretch
            // from one where nothing was collected. Each column is added by its own statement.
            "ALTER TABLE collection_runs ADD COLUMN ended_at REAL",
            "ALTER TABLE collection_runs ADD COLUMN last_seen REAL",
            """
            ALTER TABLE collection_runs ADD COLUMN end_reason TEXT
                CHECK (end_reason IS NULL OR end_reason IN ('quit', 'sleep', 'disabled', 'crash', 'inferred'))
            """,
            // Historical runs end at the last evidence before the next run of the same account started: the newest
            // limit sample or segment heartbeat inside them, else their own start. Only scalar correlated
            // subqueries (SQLite does not correlate a subquery used as a table); `max(a, b)` is the scalar form.
            """
            UPDATE collection_runs SET
                ended_at = COALESCE(NULLIF(max(
                    COALESCE((SELECT MAX(ls.captured_at) FROM limit_samples ls
                              WHERE ls.account_id = collection_runs.account_id
                                AND ls.captured_at >= collection_runs.started_at
                                AND ls.captured_at < (SELECT MIN(n.started_at) FROM collection_runs n
                                                      WHERE n.account_id = collection_runs.account_id
                                                        AND n.started_at > collection_runs.started_at)), 0),
                    COALESCE((SELECT MAX(ss.last_seen) FROM session_segments ss
                              WHERE ss.account_id = collection_runs.account_id
                                AND ss.last_seen >= collection_runs.started_at
                                AND ss.last_seen < (SELECT MIN(n.started_at) FROM collection_runs n
                                                    WHERE n.account_id = collection_runs.account_id
                                                      AND n.started_at > collection_runs.started_at)), 0)
                ), 0), started_at),
                end_reason = 'inferred'
            WHERE EXISTS (SELECT 1 FROM collection_runs n
                          WHERE n.account_id = collection_runs.account_id AND n.started_at > collection_runs.started_at)
            """,
            // The version a reader must understand to write this file.
            "CREATE TABLE IF NOT EXISTS schema_meta (key TEXT PRIMARY KEY, value TEXT)",
            "INSERT OR REPLACE INTO schema_meta (key, value) VALUES ('min_reader_version', '4')",
        ]),
    ]

    /// The prefix release 2 gave sessions without a project. Kept verbatim: the version 3 migration is historical and
    /// must stay the SQL it shipped as.
    static let v3UnnamedSessionPrefix = "сессия " // l10n-ignore: historical migration

    /// SQL for the last path component of a text column, ignoring trailing slashes; '' for a path of only slashes.
    ///
    /// `rtrim(path, <every character of path except '/'>)` strips back to the last slash, and what follows it is
    /// the folder. Matches `SessionLabel.folder(of:)` for real paths.
    static func folderName(of column: String) -> String {
        let trimmed = "rtrim(\(column), '/')"
        return "substr(\(trimmed), length(rtrim(\(trimmed), replace(\(trimmed), '/', ''))) + 1)"
    }

    /// Adds `excluded.<column>` to the stored value, saturating at `Int64.max`.
    static func saturatingSum(_ column: String) -> String {
        "CASE WHEN \(column) > 9223372036854775807 - excluded.\(column) THEN 9223372036854775807 ELSE \(column) + excluded.\(column) END"
    }

    /// Applies every migration newer than the database's recorded version.
    ///
    /// When a migration that scrubs old content ran on an existing file, the file is rebuilt (`VACUUM`) and the
    /// WAL checkpointed and truncated, so no copy of the rewritten values is left in free pages or old WAL frames.
    static func migrate(_ connection: SQLiteConnection) throws(SQLiteError) {
        try connection.execute("CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL)")
        let current = try version(of: connection)
        var scrubs = false
        for migration in migrations where migration.version > current {
            try connection.transaction { () throws(SQLiteError) in
                for statement in migration.statements {
                    try connection.execute(statement)
                }
                try connection.prepare("INSERT INTO schema_version (version) VALUES (?)")
                    .run([.integer(migration.version)])
            }
            scrubs = scrubs || (migration.scrubsOldContent && current > 0)
        }
        if scrubs {
            try connection.execute("VACUUM")
            try connection.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        }
    }

    /// The highest recorded schema version; 0 for a new file.
    static func version(of connection: SQLiteConnection) throws(SQLiteError) -> Int64 {
        let query = try connection.prepare("SELECT MAX(version) FROM schema_version")
        return try query.step() ? query.integer(0) ?? 0 : 0
    }

    /// The version a writer must understand, from `schema_meta`; `nil` for a file written before that table existed.
    static func minimumReaderVersion(of connection: SQLiteConnection) -> Int64? {
        guard
            let query = try? connection.prepare(
                "SELECT value FROM \(schemaMetaTable) WHERE key = '\(minimumReaderVersionKey)'"
            ),
            (try? query.step()) == true
        else { return nil }
        return query.text(0).flatMap { Int64($0) }
    }

    /// Whether a file must be opened read-only: it is newer than this build **and** says a newer reader is required.
    ///
    /// A newer file that still allows version-4 writers (`min_reader_version <= 4`) stays writable, which is what
    /// recording that key is for.
    static func requiresReadOnly(version: Int64, minimumReader: Int64?) -> Bool {
        version > currentVersion && (minimumReader ?? 0) > currentVersion
    }
}
