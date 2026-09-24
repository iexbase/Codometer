import CodometerCore
@testable import CodometerEngine
import CodometerStorage
import Foundation
import Testing

private let base = Date(timeIntervalSince1970: 1_789_599_900)
private let account = "6C1E0A5C-2C0B-4C2E-9B0F-9C7C1D0E2F30"
private let otherAccount = "1B2C3D4E-5F60-4718-8293-A4B5C6D7E8F9"

/// A source with a fixed set of rows, paged like the store's.
private struct FixedSource: HistoryExportSource {
    var samples: [ExportedLimitSample] = []
    var segments: [ExportedSessionSegment] = []
    var buckets: [ExportedTokenBucket] = []
    var runs: [ExportedCollectionRun] = []
    /// Hands out rows in pages of this size, so the exporter's paging loop runs more than once.
    var pageSize = UsageHistoryStore.exportPageSize

    private func page<Row>(_ rows: [Row], after cursor: Row?, matches: (Row, Row) -> Bool) -> [Row] {
        let start = cursor.flatMap { value in rows.firstIndex { matches($0, value) }.map { $0 + 1 } } ?? 0
        guard start < rows.count else { return [] }
        return Array(rows[start..<min(start + pageSize, rows.count)])
    }

    func limitSamples(after cursor: ExportedLimitSample?) async throws(HistoryExportError) -> [ExportedLimitSample] {
        page(samples, after: cursor) { $0 == $1 }
    }

    func sessionSegments(after cursor: ExportedSessionSegment?) async throws(HistoryExportError) -> [ExportedSessionSegment] {
        page(segments, after: cursor) { $0 == $1 }
    }

    func tokenBuckets(after cursor: ExportedTokenBucket?) async throws(HistoryExportError) -> [ExportedTokenBucket] {
        page(buckets, after: cursor) { $0 == $1 }
    }

    func collectionRuns(after cursor: ExportedCollectionRun?) async throws(HistoryExportError) -> [ExportedCollectionRun] {
        page(runs, after: cursor) { $0 == $1 }
    }
}

private func request(
    _ format: HistoryExportFormat,
    includeAccountNames: Bool = true,
    readme: String = "Columns are described here."
) -> HistoryExportRequest {
    HistoryExportRequest(
        format: format,
        includeAccountNames: includeAccountNames,
        labels: [:],
        appVersion: "1.0.0",
        retentionDays: 35,
        readmeText: readme
    )
}

private func exporter(
    _ format: HistoryExportFormat,
    includeAccountNames: Bool = true,
    labels: [String: String] = [account: "Work", otherAccount: "Side, \"project\""],
    timeZone: TimeZone = TimeZone(secondsFromGMT: 3 * 3_600) ?? .gmt
) -> HistoryExporter {
    HistoryExporter(
        request: request(format, includeAccountNames: includeAccountNames),
        accounts: [
            HistoryExporter.Account(id: account, label: labels[account], provider: "claude"),
            HistoryExporter.Account(id: otherAccount, label: labels[otherAccount], provider: "codex"),
        ],
        exportedAt: base,
        timeZone: timeZone
    )
}

private func source() -> FixedSource {
    FixedSource(
        samples: (0..<3).map { index in
            ExportedLimitSample(
                accountID: account,
                bucketID: "claude",
                windowID: "session",
                capturedAt: base.addingTimeInterval(Double(index) * 600),
                usedPercent: Double(index) * 12.5,
                durationMinutes: 300,
                resetsAt: base.addingTimeInterval(3_600),
                source: "claudeUsageCommand"
            )
        },
        segments: [
            ExportedSessionSegment(
                accountID: account,
                sessionID: "4ecca291-a70a-4fe9-9306-426595e70d2d",
                activity: "working",
                startedAt: base,
                endedAt: base.addingTimeInterval(125),
                project: "=formula, \"quoted\"\nfolder"
            ),
            ExportedSessionSegment(
                accountID: otherAccount,
                sessionID: "short",
                activity: "waiting",
                startedAt: base,
                endedAt: nil,
                project: nil
            ),
        ],
        buckets: [
            ExportedTokenBucket(
                accountID: account,
                bucketStart: base,
                sessionID: "4ecca291-a70a-4fe9-9306-426595e70d2d",
                project: "app",
                model: "-claude-fable-5",
                input: 10, cachedInput: 1, cacheWrite: 2, output: 3, reasoningOutput: 4
            ),
        ],
        runs: [
            ExportedCollectionRun(accountID: account, startedAt: base, endedAt: base.addingTimeInterval(600), endReason: "quit"),
            ExportedCollectionRun(accountID: otherAccount, startedAt: base, endedAt: nil, endReason: nil),
        ]
    )
}

@Suite("History export writing")
struct HistoryExporterTests {
    // MARK: - Cells and values

    @Test("CSV cells follow RFC 4180 and guard against formulas")
    func csvCells() {
        #expect(HistoryExporter.csvCell("plain") == "plain")
        #expect(HistoryExporter.csvCell("with, comma") == "\"with, comma\"")
        #expect(HistoryExporter.csvCell("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(HistoryExporter.csvCell("two\nlines") == "\"two\nlines\"")
        #expect(HistoryExporter.csvCell("=SUM(A1)") == "'=SUM(A1)")
        #expect(HistoryExporter.csvCell("+1") == "'+1")
        #expect(HistoryExporter.csvCell("-lead") == "'-lead")
        #expect(HistoryExporter.csvCell("@handle") == "'@handle")
        #expect(HistoryExporter.csvCell("=a,b") == "\"'=a,b\"")
        #expect(HistoryExporter.csvCell("") == "")
        #expect(HistoryExporter.csvLine(["a", "b"]) == "a,b\r\n")
    }

    @Test("Times carry the offset of the export's time zone, and numbers use a dot")
    func formats() {
        let moscow = TimeZone(secondsFromGMT: 3 * 3_600) ?? .gmt
        #expect(HistoryExporter.iso8601(base, timeZone: moscow) == "2026-09-17T02:05:00+03:00")
        #expect(HistoryExporter.iso8601(base, timeZone: .gmt) == "2026-09-16T23:05:00+00:00")
        let chatham = TimeZone(secondsFromGMT: -(5 * 3_600 + 30 * 60)) ?? .gmt
        #expect(HistoryExporter.iso8601(base, timeZone: chatham) == "2026-09-16T17:35:00-05:30")
        #expect(HistoryExporter.decimal(64) == "64")
        #expect(HistoryExporter.decimal(64.25) == "64.25")
        #expect(HistoryExporter.decimal(0.00001) == "0")
        #expect(HistoryExporter.decimal(.infinity) == "0")
        #expect(HistoryExporter.sessionReference("4ecca291-a70a-4fe9-9306-426595e70d2d") == "426595e70d2d")
        #expect(HistoryExporter.sessionReference("short") == "short")
    }

    // MARK: - JSON

    @Test("A JSON export parses back with every row, and never names an account when asked not to")
    func jsonRoundTrip() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("Codometer History.json", isDirectory: false)
        var rows = source()
        rows.pageSize = 2
        let summary = try await exporter(.json).write(from: rows, to: url)
        #expect(summary.rowCount == 3 + 2 + 1 + 2)
        #expect(summary.destination == url)

        let data = try Data(contentsOf: url)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["format"] as? String == "codometer-history")
        #expect(object["version"] as? Int == 1)
        #expect(object["appVersion"] as? String == "1.0.0")
        #expect(object["retentionDays"] as? Int == 35)
        #expect(object["exportedAt"] as? String == "2026-09-17T02:05:00+03:00")
        let accounts = try #require(object["accounts"] as? [[String: Any]])
        #expect(accounts.map { $0["label"] as? String } == ["Work", "Side, \"project\""])
        #expect(accounts.map { $0["provider"] as? String } == ["claude", "codex"])
        #expect((object["limitSamples"] as? [[String: Any]])?.count == 3)
        #expect((object["sessionSegments"] as? [[String: Any]])?.count == 2)
        #expect((object["tokenUsage"] as? [[String: Any]])?.count == 1)
        #expect((object["collectionRuns"] as? [[String: Any]])?.count == 2)

        let segments = try #require(object["sessionSegments"] as? [[String: Any]])
        #expect(segments.first?["sessionRef"] as? String == "426595e70d2d")
        #expect(segments.first?["durationSeconds"] as? Double == 125)
        #expect(segments.last?["endedAt"] is NSNull)
        // The whole session id is never written out.
        #expect(String(decoding: data, as: UTF8.self).contains("4ecca291") == false)

        // Without names, the accounts table carries no label.
        let bare = directory.url.appendingPathComponent("Bare.json", isDirectory: false)
        _ = try await exporter(.json, includeAccountNames: false).write(from: rows, to: bare)
        let bareObject = try #require(try JSONSerialization.jsonObject(with: try Data(contentsOf: bare)) as? [String: Any])
        let bareAccounts = try #require(bareObject["accounts"] as? [[String: Any]])
        #expect(bareAccounts.allSatisfy { $0["label"] is NSNull })
        #expect(String(decoding: try Data(contentsOf: bare), as: UTF8.self).contains("Work") == false)
    }

    @Test("An empty history still writes a valid envelope")
    func emptyExport() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("Empty.json", isDirectory: false)
        let summary = try await exporter(.json).write(from: FixedSource(), to: url)
        #expect(summary.rowCount == 0)
        let object = try #require(try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        #expect((object["limitSamples"] as? [Any])?.isEmpty == true)
        #expect((object["collectionRuns"] as? [Any])?.isEmpty == true)
    }

    // MARK: - CSV

    @Test("A CSV export writes one file per table plus the README, with English headers")
    func csvFolder() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("Codometer History", isDirectory: true)
        var rows = source()
        rows.pageSize = 1
        let summary = try await exporter(.csvFolder).write(from: rows, to: url)
        #expect(summary.rowCount == 8)
        #expect(try FileManager.default.contentsOfDirectory(atPath: url.path).sorted() == [
            "README.txt", "collection-runs.csv", "limits.csv", "sessions.csv", "tokens.csv",
        ])
        #expect(try String(contentsOf: url.appendingPathComponent("README.txt"), encoding: .utf8) == "Columns are described here.")

        let limits = try String(contentsOf: url.appendingPathComponent("limits.csv"), encoding: .utf8)
        let limitLines = limits.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        #expect(limitLines.first == "account_id,account_label,provider,bucket_id,window_id,window_title,captured_at,used_percent,duration_minutes,resets_at,source")
        #expect(limitLines.count == 4)
        #expect(limitLines[1] == "\(account),Work,claude,claude,session,,2026-09-17T02:05:00+03:00,0,300,2026-09-17T03:05:00+03:00,claudeUsageCommand")

        let sessions = try String(contentsOf: url.appendingPathComponent("sessions.csv"), encoding: .utf8)
        // A project folder that looks like a formula is escaped and quoted, and the label with a comma is quoted.
        #expect(sessions.contains("\"'=formula, \"\"quoted\"\"\nfolder\""))
        #expect(sessions.contains("\"Side, \"\"project\"\"\""))
        #expect(sessions.contains("426595e70d2d"))
        #expect(sessions.contains("4ecca291") == false)

        let tokens = try String(contentsOf: url.appendingPathComponent("tokens.csv"), encoding: .utf8)
        #expect(tokens.contains("'-claude-fable-5"))
        #expect(tokens.contains(",10,1,2,3,4"))

        let runs = try String(contentsOf: url.appendingPathComponent("collection-runs.csv"), encoding: .utf8)
        #expect(runs.components(separatedBy: "\r\n").filter { !$0.isEmpty }.first == "account_id,started_at,ended_at,end_reason")
        #expect(runs.contains(",quit"))

        for name in ["README.txt", "limits.csv"] {
            let mode = try FileManager.default.attributesOfItem(atPath: url.appendingPathComponent(name).path)[.posixPermissions] as? NSNumber
            #expect(mode?.intValue == 0o600)
        }
    }

    @Test("Without account names the label column stays empty")
    func csvWithoutLabels() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("Bare", isDirectory: true)
        _ = try await exporter(.csvFolder, includeAccountNames: false).write(from: source(), to: url)
        let limits = try String(contentsOf: url.appendingPathComponent("limits.csv"), encoding: .utf8)
        #expect(limits.contains("Work") == false)
        #expect(limits.contains("\(account),,claude,"))
    }

    // MARK: - Destination handling

    @Test("An existing destination is refused and left untouched, and nothing partial is left behind")
    func refusesExistingDestination() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("Taken.json", isDirectory: false)
        try Data("mine".utf8).write(to: url)
        await #expect(throws: HistoryExportError.destinationExists) {
            _ = try await exporter(.json).write(from: source(), to: url)
        }
        #expect(try String(contentsOf: url, encoding: .utf8) == "mine")
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.url.path) == ["Taken.json"])

        let folder = directory.url.appendingPathComponent("Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        await #expect(throws: HistoryExportError.destinationExists) {
            _ = try await exporter(.csvFolder).write(from: source(), to: folder)
        }
    }

    @Test("A write that cannot start reports a reason without a path")
    func reportsFailuresWithoutPaths() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("nowhere/Codometer History.json", isDirectory: false)
        do {
            _ = try await exporter(.json).write(from: source(), to: url)
            Issue.record("expected the export to fail")
        } catch {
            guard case .writeFailed(let reason) = error else {
                Issue.record("expected a write failure, got \(error)")
                return
            }
            #expect(reason.contains("/") == false)
            #expect(reason.contains("nowhere") == false)
        }
    }
}
