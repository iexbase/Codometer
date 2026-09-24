import CodometerCore
import CodometerPlatform
import CodometerStorage
import Darwin
import Foundation

/// Where an export reads its rows, one bounded page at a time (keyset pagination over each table's primary key).
protocol HistoryExportSource: Sendable {
    func limitSamples(after cursor: ExportedLimitSample?) async throws(HistoryExportError) -> [ExportedLimitSample]
    func sessionSegments(after cursor: ExportedSessionSegment?) async throws(HistoryExportError) -> [ExportedSessionSegment]
    func tokenBuckets(after cursor: ExportedTokenBucket?) async throws(HistoryExportError) -> [ExportedTokenBucket]
    func collectionRuns(after cursor: ExportedCollectionRun?) async throws(HistoryExportError) -> [ExportedCollectionRun]
}

/// The history store as an export source; read failures become `.writeFailed` with a path-free reason.
struct StoreExportSource: HistoryExportSource {
    let store: UsageHistoryStore

    func limitSamples(after cursor: ExportedLimitSample?) async throws(HistoryExportError) -> [ExportedLimitSample] {
        do throws(SQLiteError) {
            return try await store.exportLimitSamples(after: cursor)
        } catch {
            throw .writeFailed(error.description)
        }
    }

    func sessionSegments(after cursor: ExportedSessionSegment?) async throws(HistoryExportError) -> [ExportedSessionSegment] {
        do throws(SQLiteError) {
            return try await store.exportSessionSegments(after: cursor)
        } catch {
            throw .writeFailed(error.description)
        }
    }

    func tokenBuckets(after cursor: ExportedTokenBucket?) async throws(HistoryExportError) -> [ExportedTokenBucket] {
        do throws(SQLiteError) {
            return try await store.exportTokenBuckets(after: cursor)
        } catch {
            throw .writeFailed(error.description)
        }
    }

    func collectionRuns(after cursor: ExportedCollectionRun?) async throws(HistoryExportError) -> [ExportedCollectionRun] {
        do throws(SQLiteError) {
            return try await store.exportCollectionRuns(after: cursor)
        } catch {
            throw .writeFailed(error.description)
        }
    }
}

/// Writes the history tables to a JSON file or a folder of CSV files.
///
/// Only the history tables are exported: limit samples, session segments (project folder and the end of the session
/// id, never a title), token buckets and collection runs. `last_state` holds the account identity, including the
/// e-mail, and is never read here. Account labels appear only when the request asks for them.
///
/// Everything is streamed: one bounded page of rows is held at a time, the file is built as `<name>.partial` with
/// `O_EXCL | O_NOFOLLOW` at 0600 and renamed into place at the end, and a cancelled export leaves nothing behind.
struct HistoryExporter {
    /// One account as the export's lookup table lists it.
    struct Account: Hashable, Sendable {
        let id: String
        let label: String?
        let provider: String
    }

    static let formatName = "codometer-history"
    static let formatVersion = 1
    /// The end of a session id that identifies a session inside an export without naming it.
    static let sessionReferenceLength = 12
    static let partialSuffix = ".partial"

    let request: HistoryExportRequest
    /// Accounts known to the app, for the lookup table and the CSV label column.
    let accounts: [Account]
    let exportedAt: Date
    let timeZone: TimeZone

    init(request: HistoryExportRequest, accounts: [Account], exportedAt: Date, timeZone: TimeZone = .current) {
        self.request = request
        self.accounts = accounts
        self.exportedAt = exportedAt
        self.timeZone = timeZone
    }

    /// Writes the export to `url`, which must not exist yet.
    func write(from source: some HistoryExportSource, to url: URL) async throws(HistoryExportError) -> HistoryExportSummary {
        guard SecureFileIO.metadata(at: url) == nil else { throw .destinationExists }
        return switch request.format {
        case .json: try await writeJSON(from: source, to: url)
        case .csvFolder: try await writeCSVFolder(from: source, to: url)
        }
    }

    // MARK: - JSON

    private func writeJSON(from source: some HistoryExportSource, to url: URL) async throws(HistoryExportError) -> HistoryExportSummary {
        let partial = Self.partialURL(for: url)
        let file: ExclusiveFile
        do throws(FileAccessError) {
            file = try SecureFileIO.createExclusive(at: partial)
        } catch {
            throw .writeFailed(error.summary)
        }
        var rows = 0
        do throws(HistoryExportError) {
            try Self.write(Self.envelopeHead(
                exportedAt: Self.iso8601(exportedAt, timeZone: timeZone),
                appVersion: request.appVersion,
                retentionDays: request.retentionDays,
                accounts: exportedAccounts
            ), to: file)
            rows += try await writeJSONArray(name: "limitSamples", to: file, pages: source.limitSamples, row: jsonRow)
            try Self.write(",", to: file)
            rows += try await writeJSONArray(name: "sessionSegments", to: file, pages: source.sessionSegments, row: jsonRow)
            try Self.write(",", to: file)
            rows += try await writeJSONArray(name: "tokenUsage", to: file, pages: source.tokenBuckets, row: jsonRow)
            try Self.write(",", to: file)
            rows += try await writeJSONArray(name: "collectionRuns", to: file, pages: source.collectionRuns, row: jsonRow)
            try Self.write("}\n", to: file)
            try Self.close(file)
        } catch {
            Self.discard(partial)
            throw error
        }
        try Self.move(partial, to: url)
        return HistoryExportSummary(rowCount: rows, destination: url)
    }

    /// Writes `"name":[…]` by pulling pages until one comes back empty, and returns how many rows it wrote.
    private func writeJSONArray<Row>(
        name: String,
        to file: ExclusiveFile,
        pages: (Row?) async throws(HistoryExportError) -> [Row],
        row encode: (Row) -> String
    ) async throws(HistoryExportError) -> Int {
        try Self.write("\"\(name)\":[", to: file)
        var cursor: Row?
        var count = 0
        while true {
            let page = try await pages(cursor)
            guard !page.isEmpty else { break }
            var chunk = ""
            for value in page {
                chunk += count == 0 ? "" : ","
                chunk += encode(value)
                count += 1
            }
            try Self.write(chunk, to: file)
            cursor = page.last
            try Self.checkCancellation()
        }
        try Self.write("]", to: file)
        return count
    }

    // MARK: - CSV

    private func writeCSVFolder(from source: some HistoryExportSource, to url: URL) async throws(HistoryExportError) -> HistoryExportSummary {
        let partial = Self.partialURL(for: url)
        do {
            try FileManager.default.createDirectory(
                at: partial,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw .writeFailed("the export folder could not be created")
        }
        var rows = 0
        do throws(HistoryExportError) {
            rows += try await writeCSV(
                name: "limits.csv", in: partial,
                header: "account_id,account_label,provider,bucket_id,window_id,window_title,captured_at,used_percent,duration_minutes,resets_at,source",
                pages: source.limitSamples, row: csvRow
            )
            rows += try await writeCSV(
                name: "sessions.csv", in: partial,
                header: "account_id,account_label,session_ref,project_folder,activity,started_at,ended_at,duration_seconds",
                pages: source.sessionSegments, row: csvRow
            )
            rows += try await writeCSV(
                name: "tokens.csv", in: partial,
                header: "account_id,account_label,bucket_start,session_ref,project_folder,model,input,cached_input,cache_write,output,reasoning_output",
                pages: source.tokenBuckets, row: csvRow
            )
            rows += try await writeCSV(
                name: "collection-runs.csv", in: partial,
                header: "account_id,started_at,ended_at,end_reason",
                pages: source.collectionRuns, row: csvRow
            )
            let readme: ExclusiveFile
            do throws(FileAccessError) {
                readme = try SecureFileIO.createExclusive(at: partial.appendingPathComponent("README.txt", isDirectory: false))
            } catch {
                throw .writeFailed(error.summary)
            }
            try Self.write(request.readmeText, to: readme)
            try Self.close(readme)
        } catch {
            Self.discardFolder(partial)
            throw error
        }
        try Self.move(partial, to: url)
        return HistoryExportSummary(rowCount: rows, destination: url)
    }

    private func writeCSV<Row>(
        name: String,
        in directory: URL,
        header: String,
        pages: (Row?) async throws(HistoryExportError) -> [Row],
        row cells: (Row) -> [String]
    ) async throws(HistoryExportError) -> Int {
        let file: ExclusiveFile
        do throws(FileAccessError) {
            file = try SecureFileIO.createExclusive(at: directory.appendingPathComponent(name, isDirectory: false))
        } catch {
            throw .writeFailed(error.summary)
        }
        try Self.write(header + Self.lineBreak, to: file)
        var cursor: Row?
        var count = 0
        while true {
            let page = try await pages(cursor)
            guard !page.isEmpty else { break }
            var chunk = ""
            for value in page {
                chunk += Self.csvLine(cells(value))
                count += 1
            }
            try Self.write(chunk, to: file)
            cursor = page.last
            try Self.checkCancellation()
        }
        try Self.close(file)
        return count
    }

    // MARK: - Rows

    private var exportedAccounts: [Account] {
        accounts.map { account in
            Account(id: account.id, label: request.includeAccountNames ? account.label : nil, provider: account.provider)
        }
    }

    private func label(of accountID: String) -> String {
        guard request.includeAccountNames else { return "" }
        return accounts.first { $0.id == accountID }?.label ?? ""
    }

    private func provider(of accountID: String) -> String {
        accounts.first { $0.id == accountID }?.provider ?? ""
    }

    private func jsonRow(_ sample: ExportedLimitSample) -> String {
        Self.object([
            ("accountId", .text(sample.accountID)),
            ("bucketId", .text(sample.bucketID)),
            ("windowId", .text(sample.windowID)),
            ("capturedAt", .text(Self.iso8601(sample.capturedAt, timeZone: timeZone))),
            ("usedPercent", .number(Self.decimal(sample.usedPercent))),
            ("durationMinutes", sample.durationMinutes.map { .number("\($0)") } ?? .null),
            ("resetsAt", sample.resetsAt.map { .text(Self.iso8601($0, timeZone: timeZone)) } ?? .null),
            ("source", .text(sample.source)),
        ])
    }

    private func jsonRow(_ segment: ExportedSessionSegment) -> String {
        Self.object([
            ("accountId", .text(segment.accountID)),
            ("sessionRef", .text(Self.sessionReference(segment.sessionID))),
            ("projectFolder", segment.project.map { .text($0) } ?? .null),
            ("activity", .text(segment.activity)),
            ("startedAt", .text(Self.iso8601(segment.startedAt, timeZone: timeZone))),
            ("endedAt", segment.endedAt.map { .text(Self.iso8601($0, timeZone: timeZone)) } ?? .null),
            ("durationSeconds", segment.endedAt.map { .number(Self.decimal($0.timeIntervalSince(segment.startedAt))) } ?? .null),
        ])
    }

    private func jsonRow(_ bucket: ExportedTokenBucket) -> String {
        Self.object([
            ("accountId", .text(bucket.accountID)),
            ("bucketStart", .text(Self.iso8601(bucket.bucketStart, timeZone: timeZone))),
            ("sessionRef", .text(Self.sessionReference(bucket.sessionID))),
            ("projectFolder", bucket.project.isEmpty ? .null : .text(bucket.project)),
            ("model", bucket.model.isEmpty ? .null : .text(bucket.model)),
            ("input", .number("\(bucket.input)")),
            ("cachedInput", .number("\(bucket.cachedInput)")),
            ("cacheWrite", .number("\(bucket.cacheWrite)")),
            ("output", .number("\(bucket.output)")),
            ("reasoningOutput", .number("\(bucket.reasoningOutput)")),
        ])
    }

    private func jsonRow(_ run: ExportedCollectionRun) -> String {
        Self.object([
            ("accountId", .text(run.accountID)),
            ("startedAt", .text(Self.iso8601(run.startedAt, timeZone: timeZone))),
            ("endedAt", run.endedAt.map { .text(Self.iso8601($0, timeZone: timeZone)) } ?? .null),
            ("endReason", run.endReason.map { .text($0) } ?? .null),
        ])
    }

    private func csvRow(_ sample: ExportedLimitSample) -> [String] {
        [
            sample.accountID,
            label(of: sample.accountID),
            provider(of: sample.accountID),
            sample.bucketID,
            sample.windowID,
            "",
            Self.iso8601(sample.capturedAt, timeZone: timeZone),
            Self.decimal(sample.usedPercent),
            sample.durationMinutes.map { "\($0)" } ?? "",
            sample.resetsAt.map { Self.iso8601($0, timeZone: timeZone) } ?? "",
            sample.source,
        ]
    }

    private func csvRow(_ segment: ExportedSessionSegment) -> [String] {
        [
            segment.accountID,
            label(of: segment.accountID),
            Self.sessionReference(segment.sessionID),
            segment.project ?? "",
            segment.activity,
            Self.iso8601(segment.startedAt, timeZone: timeZone),
            segment.endedAt.map { Self.iso8601($0, timeZone: timeZone) } ?? "",
            segment.endedAt.map { Self.decimal($0.timeIntervalSince(segment.startedAt)) } ?? "",
        ]
    }

    private func csvRow(_ bucket: ExportedTokenBucket) -> [String] {
        [
            bucket.accountID,
            label(of: bucket.accountID),
            Self.iso8601(bucket.bucketStart, timeZone: timeZone),
            Self.sessionReference(bucket.sessionID),
            bucket.project,
            bucket.model,
            "\(bucket.input)",
            "\(bucket.cachedInput)",
            "\(bucket.cacheWrite)",
            "\(bucket.output)",
            "\(bucket.reasoningOutput)",
        ]
    }

    private func csvRow(_ run: ExportedCollectionRun) -> [String] {
        [
            run.accountID,
            Self.iso8601(run.startedAt, timeZone: timeZone),
            run.endedAt.map { Self.iso8601($0, timeZone: timeZone) } ?? "",
            run.endReason ?? "",
        ]
    }
}

// MARK: - Formatting

extension HistoryExporter {
    static let lineBreak = "\r\n"
    /// Cells starting with one of these are prefixed with `'`, so a spreadsheet never runs an exported value.
    static let formulaStarters: Set<Character> = ["=", "+", "-", "@", "\t", "\r"]

    enum JSONValue {
        case text(String)
        case number(String)
        case null
    }

    /// The last characters of a session id: enough to tell sessions apart, never the whole identifier.
    static func sessionReference(_ sessionID: String) -> String {
        String(sessionID.suffix(sessionReferenceLength))
    }

    /// A JSON object from ordered key/value pairs.
    static func object(_ fields: [(String, JSONValue)]) -> String {
        let body = fields.map { key, value in
            let encoded = switch value {
            case .text(let text): quoted(text)
            case .number(let number): number
            case .null: "null"
            }
            return "\(quoted(key)):\(encoded)"
        }
        return "{\(body.joined(separator: ","))}"
    }

    /// A JSON string: control characters, quotes and backslashes escaped; everything else stays UTF-8.
    static func quoted(_ text: String) -> String {
        var result = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                if scalar.value < 0x20 {
                    result += String(format: "\\u%04x", scalar.value)
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result + "\""
    }

    /// A number with a `.` decimal separator and no exponent, trailing zeros removed.
    static func decimal(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        var text = String(format: "%.4f", value)
        while text.hasSuffix("0") {
            text.removeLast()
        }
        if text.hasSuffix(".") {
            text.removeLast()
        }
        return text.isEmpty ? "0" : text
    }

    /// `2026-09-17T14:32:00+03:00`: ISO 8601 with the offset of `timeZone`, built without a locale.
    static func iso8601(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let offset = timeZone.secondsFromGMT(for: date)
        let sign = offset < 0 ? "-" : "+"
        let minutes = abs(offset) / 60
        return "\(pad(parts.year ?? 0, 4))-\(pad(parts.month ?? 1, 2))-\(pad(parts.day ?? 1, 2))"
            + "T\(pad(parts.hour ?? 0, 2)):\(pad(parts.minute ?? 0, 2)):\(pad(parts.second ?? 0, 2))"
            + "\(sign)\(pad(minutes / 60, 2)):\(pad(minutes % 60, 2))"
    }

    static func pad(_ value: Int, _ width: Int) -> String {
        let text = String(abs(value))
        return text.count >= width ? text : String(repeating: "0", count: width - text.count) + text
    }

    /// One CSV record (RFC 4180) ending in CRLF.
    static func csvLine(_ cells: [String]) -> String {
        cells.map(csvCell).joined(separator: ",") + lineBreak
    }

    /// One CSV cell: formula guard first, then RFC 4180 quoting.
    static func csvCell(_ text: String) -> String {
        var value = text
        if let first = value.first, formulaStarters.contains(first) {
            value = "'" + value
        }
        guard value.contains(where: { $0 == "\"" || $0 == "," || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// The envelope up to (and including) the first row array's key.
    static func envelopeHead(exportedAt: String, appVersion: String, retentionDays: Int, accounts: [Account]) -> String {
        let list = accounts.map { account in
            object([
                ("id", .text(account.id)),
                ("label", account.label.map { .text($0) } ?? .null),
                ("provider", .text(account.provider)),
            ])
        }
        return "{\(quoted("format")):\(quoted(formatName)),\(quoted("version")):\(formatVersion),"
            + "\(quoted("exportedAt")):\(quoted(exportedAt)),\(quoted("appVersion")):\(quoted(appVersion)),"
            + "\(quoted("retentionDays")):\(retentionDays),"
            + "\(quoted("accounts")):[\(list.joined(separator: ","))],"
    }
}

// MARK: - Files

extension HistoryExporter {
    static func partialURL(for url: URL) -> URL {
        url.deletingLastPathComponent()
            .appendingPathComponent(url.lastPathComponent + partialSuffix, isDirectory: false)
    }

    static func write(_ text: String, to file: ExclusiveFile) throws(HistoryExportError) {
        do throws(FileAccessError) {
            try file.write(text)
        } catch {
            throw .writeFailed(error.summary)
        }
    }

    static func close(_ file: ExclusiveFile) throws(HistoryExportError) {
        do throws(FileAccessError) {
            try file.close()
        } catch {
            throw .writeFailed(error.summary)
        }
    }

    static func checkCancellation() throws(HistoryExportError) {
        if Task.isCancelled { throw .cancelled }
    }

    /// Renames the finished export into place, refusing to replace anything that appeared meanwhile.
    static func move(_ partial: URL, to url: URL) throws(HistoryExportError) {
        guard renamex_np(partial.path, url.path, UInt32(RENAME_EXCL)) == 0 else {
            let code = errno
            if code == EEXIST {
                discardFolder(partial)
                discard(partial)
                throw .destinationExists
            }
            discardFolder(partial)
            discard(partial)
            throw .writeFailed("the export could not be renamed (errno \(code))")
        }
    }

    static func discard(_ url: URL) {
        _ = try? SecureFileIO.unlinkRegularFile(at: url)
    }

    /// Removes a partial CSV folder: its regular files one level, then the folder.
    static func discardFolder(_ url: URL) {
        guard SecureFileIO.metadata(at: url)?.isDirectory == true else { return }
        for name in (try? SecureFileIO.regularFileNames(in: url)) ?? [] {
            discard(url.appendingPathComponent(name, isDirectory: false))
        }
        _ = rmdir(url.path)
    }
}
