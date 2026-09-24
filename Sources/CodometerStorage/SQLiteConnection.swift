import Darwin
import Foundation
import SQLite3

public enum SQLiteError: Error, Equatable, Sendable, CustomStringConvertible {
    case open(code: Int32, message: String)
    case prepare(code: Int32, message: String)
    case execute(code: Int32, message: String)
    case bind(code: Int32)
    /// The database was closed (erasing all data closes it before the files are removed).
    case closed

    public var description: String {
        switch self {
        case let .open(code, message): "SQLite open failed (\(code)): \(message)"
        case let .prepare(code, message): "SQLite prepare failed (\(code)): \(message)"
        case let .execute(code, message): "SQLite execution failed (\(code)): \(message)"
        case .bind(let code): "SQLite bind failed (\(code))"
        case .closed: "the history database is closed"
        }
    }

    /// The SQLite result code behind the failure, or `SQLITE_OK` when there is none.
    public var code: Int32 {
        switch self {
        case let .open(code, _), let .prepare(code, _), let .execute(code, _), let .bind(code): code
        case .closed: SQLITE_OK
        }
    }

    /// A file the database cannot be read from: it is not a database, or its pages are damaged.
    public var meansCorruption: Bool {
        let code = code & 0xFF
        return code == SQLITE_CORRUPT || code == SQLITE_NOTADB
    }

    /// The volume is full, so writes must pause until there is room again.
    public var meansDiskFull: Bool {
        (code & 0xFF) == SQLITE_FULL
    }

    /// The check was interrupted by its timeout.
    public var meansInterrupted: Bool {
        (code & 0xFF) == SQLITE_INTERRUPT
    }
}

enum SQLiteValue {
    case text(String)
    case integer(Int64)
    case real(Double)
    case blob(Data)
    case null
}

/// A single-threaded SQLite connection. Owned by one actor, never shared across isolation domains.
///
/// The database holds project folder names and account identities, so its files are owner-only (`0600`) whatever
/// the umask, and a symlink at the database, its WAL, its shared-memory file or its journal is refused.
final class SQLiteConnection {
    static let filePermissions: mode_t = 0o600
    /// Files SQLite keeps next to the database; they are created with the database file's permissions.
    static let companionSuffixes = ["-wal", "-shm", "-journal"]

    private var handle: OpaquePointer?

    init(path: String) throws(SQLiteError) {
        try Self.preparePrivateFiles(path: path)
        var connection: OpaquePointer?
        // Not `SQLITE_OPEN_NOFOLLOW`: it refuses a symlink anywhere in the path (`/var` → `/private/var`, a moved
        // home folder). Like `SecureFileIO`, only the final components are checked, just above.
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
        let code = sqlite3_open_v2(path, &connection, flags, nil)
        guard code == SQLITE_OK, let connection else {
            let message = connection.map { String(cString: sqlite3_errmsg($0)) } ?? "no connection"
            sqlite3_close_v2(connection)
            throw .open(code: code, message: message)
        }
        handle = connection
        sqlite3_busy_timeout(handle, 2_000)
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA synchronous = NORMAL")
        try execute("PRAGMA foreign_keys = ON")
    }

    deinit {
        if let handle {
            sqlite3_close_v2(handle)
        }
    }

    /// Whether the connection was closed; every later call fails with `.closed`.
    var isClosed: Bool { handle == nil }

    /// Closes the connection. Later calls throw `.closed`, and the database files can be removed.
    func close() {
        guard let handle else { return }
        self.handle = nil
        sqlite3_close_v2(handle)
    }

    /// The open handle, or `.closed` once `close()` ran.
    private func activeHandle() throws(SQLiteError) -> OpaquePointer {
        guard let handle else { throw .closed }
        return handle
    }

    /// Creates the database file owner-only before SQLite opens it, and tightens an existing file and its companions.
    ///
    /// SQLite gives new WAL and shared-memory files the database file's permissions, so fixing the database file
    /// is enough for files created later; existing companions from an older version are fixed here.
    static func preparePrivateFiles(path: String) throws(SQLiteError) {
        try restrict(path: path, creating: true)
        for suffix in companionSuffixes {
            try restrict(path: path + suffix, creating: false)
        }
    }

    /// Opens `path` without following a symlink, checks it is a regular file and sets `filePermissions`.
    /// A missing companion (`creating == false`) is fine.
    private static func restrict(path: String, creating: Bool) throws(SQLiteError) {
        let flags = O_RDWR | O_NOFOLLOW | O_CLOEXEC | (creating ? O_CREAT : 0)
        let descriptor = open(path, flags, filePermissions)
        guard descriptor >= 0 else {
            let code = errno
            if !creating, code == ENOENT { return }
            throw .open(code: SQLITE_CANTOPEN, message: code == ELOOP ? "symlinks are refused" : "open failed (errno \(code))")
        }
        defer { Darwin.close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else {
            throw .open(code: SQLITE_CANTOPEN, message: "stat failed (errno \(errno))")
        }
        guard (info.st_mode & S_IFMT) == S_IFREG else {
            throw .open(code: SQLITE_CANTOPEN, message: "not a regular file")
        }
        guard (info.st_mode & 0o7777) != filePermissions else { return }
        guard fchmod(descriptor, filePermissions) == 0 else {
            throw .open(code: SQLITE_CANTOPEN, message: "chmod failed (errno \(errno))")
        }
    }

    func execute(_ sql: String) throws(SQLiteError) {
        let handle = try activeHandle()
        let code = sqlite3_exec(handle, sql, nil, nil, nil)
        guard code == SQLITE_OK else {
            throw .execute(code: code, message: lastMessage)
        }
    }

    func prepare(_ sql: String) throws(SQLiteError) -> SQLiteStatement {
        let handle = try activeHandle()
        var statement: OpaquePointer?
        let code = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard code == SQLITE_OK, let statement else {
            throw .prepare(code: code, message: lastMessage)
        }
        return SQLiteStatement(handle: statement, connection: self)
    }

    /// Runs `PRAGMA quick_check(1)`, interrupting it after `timeout`.
    ///
    /// `true` when the file reports "ok", `false` when it reports damage, `nil` when the check was interrupted or
    /// the connection is closed. The progress handler only compares a monotonic deadline, so it adds no work of
    /// its own, and it is removed again before returning.
    func quickCheck(timeout: TimeInterval) -> Bool? {
        guard let handle else { return nil }
        let nanoseconds = max(timeout, 0) * 1_000_000_000
        var deadline = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)
            &+ UInt64(nanoseconds.isFinite ? min(nanoseconds, 1e18) : 0)
        let interrupted: Bool? = withUnsafeMutablePointer(to: &deadline) { pointer in
            sqlite3_progress_handler(handle, 2_000, { raw in
                guard let raw else { return 0 }
                let deadline = raw.assumingMemoryBound(to: UInt64.self).pointee
                return clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) > deadline ? 1 : 0
            }, UnsafeMutableRawPointer(pointer))
            defer { sqlite3_progress_handler(handle, 0, nil, nil) }
            do throws(SQLiteError) {
                let query = try prepare("PRAGMA quick_check(1)")
                guard try query.step() else { return nil }
                return query.text(0) == "ok"
            } catch {
                return error.meansInterrupted ? nil : false
            }
        }
        return interrupted
    }

    /// Runs `body` inside a transaction that is rolled back if it throws.
    func transaction(_ body: () throws(SQLiteError) -> Void) throws(SQLiteError) {
        try execute("BEGIN IMMEDIATE")
        do throws(SQLiteError) {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    var lastMessage: String {
        guard let handle else { return "the history database is closed" }
        return String(cString: sqlite3_errmsg(handle))
    }

    /// Rows changed by the most recent INSERT, UPDATE or DELETE.
    var changes: Int {
        guard let handle else { return 0 }
        return Int(sqlite3_changes(handle))
    }
}

final class SQLiteStatement {
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private let handle: OpaquePointer
    private let connection: SQLiteConnection

    init(handle: OpaquePointer, connection: SQLiteConnection) {
        self.handle = handle
        self.connection = connection
    }

    deinit {
        sqlite3_finalize(handle)
    }

    func bind(_ values: [SQLiteValue]) throws(SQLiteError) {
        sqlite3_reset(handle)
        sqlite3_clear_bindings(handle)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let code: Int32 = switch value {
            case .text(let text): sqlite3_bind_text(handle, index, text, -1, Self.transient)
            case .integer(let number): sqlite3_bind_int64(handle, index, number)
            case .real(let number): sqlite3_bind_double(handle, index, number)
            case .blob(let data): data.withUnsafeBytes { raw in
                    sqlite3_bind_blob(handle, index, raw.baseAddress, Int32(raw.count), Self.transient)
                }
            case .null: sqlite3_bind_null(handle, index)
            }
            guard code == SQLITE_OK else { throw .bind(code: code) }
        }
    }

    /// Advances to the next row; `false` when the statement is done.
    func step() throws(SQLiteError) -> Bool {
        let code = sqlite3_step(handle)
        switch code {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw .execute(code: code, message: connection.lastMessage)
        }
    }

    func run(_ values: [SQLiteValue]) throws(SQLiteError) {
        try bind(values)
        while try step() {}
    }

    func text(_ column: Int32) -> String? {
        guard let pointer = sqlite3_column_text(handle, column) else { return nil }
        return String(cString: pointer)
    }

    func double(_ column: Int32) -> Double? {
        sqlite3_column_type(handle, column) == SQLITE_NULL ? nil : sqlite3_column_double(handle, column)
    }

    func integer(_ column: Int32) -> Int64? {
        sqlite3_column_type(handle, column) == SQLITE_NULL ? nil : sqlite3_column_int64(handle, column)
    }

    func blob(_ column: Int32) -> Data? {
        guard let pointer = sqlite3_column_blob(handle, column) else { return nil }
        return Data(bytes: pointer, count: Int(sqlite3_column_bytes(handle, column)))
    }
}
