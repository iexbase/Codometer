import CodometerCore
import Foundation
import Testing

@Suite("Diagnostics models")
struct DiagnosticsModelTests {
    private let home = "/Users/jane.doe"

    @Test("Report text has no e-mails, no @, no home paths, no project folders, no session ids and no labels")
    func sanitizedWithoutNames() {
        let text = DiagnosticsFixtures.report.text(includeAccountNames: false, labels: DiagnosticsFixtures.labels)
        #expect(!text.contains("@"))
        #expect(!text.contains("/Users/"))
        #expect(!text.contains("jane"))
        #expect(!text.contains("Jane"))
        #expect(!text.contains("acme"))
        #expect(!text.contains("Acme"))
        #expect(!text.contains("orion"))
        #expect(!text.contains("3F2504E0"))
        #expect(!text.contains(DiagnosticsFixtures.workID.description))
        #expect(text.contains("<email>"))
        #expect(text.contains("~/.local/bin/claude 2.1.12"))
        #expect(text.contains("~/Downloads/Codometer.app"))
        #expect(text.contains("~/Library/Application Support/Codometer/history.sqlite"))
        #expect(text.contains("~/…/.claude"))
        #expect(text.contains("Anthropic PBC (Q6L2SF6YDW)"))
        #expect(text.contains("/opt/homebrew/bin/codex"))
        #expect(text.contains("codex_cli_rs/0.154.0"))
        #expect(text.contains("<id>"))
        // Provider-only labels are not personal and stay readable.
        #expect(text.contains("~/.claude (Claude)"))
    }

    @Test("Accounts are numbered by first mention; with names included, ids become labels")
    func accountNames() {
        let hidden = DiagnosticsFixtures.report.text(includeAccountNames: false, labels: DiagnosticsFixtures.labels)
        #expect(hidden.contains("(claudeProfile.Account 1): ~/…/.claude signed in as <email> for Account 1, session <id>"))
        #expect(hidden.contains("(claudeProfile.Account 2): ~/.claude-personal: signed in as <email> (Account 2)"))
        #expect(hidden.contains("(claudeProfile.Account 3): ~/.claude (Claude): ops(at)(at)team"))

        let shown = DiagnosticsFixtures.report.text(includeAccountNames: true, labels: DiagnosticsFixtures.labels)
        #expect(shown.contains("(claudeProfile.Jane personal): ~/.claude-personal: signed in as <email> (Jane personal)"))
        #expect(shown.contains("for Acme Consulting"))
        #expect(!shown.contains("@"))
        #expect(!shown.contains("/Users/"))
        #expect(!shown.contains("acme-secret-launch"))
    }

    @Test("Items are in check order with stable ids, and the text is deterministic")
    func stableOrdering() {
        let report = DiagnosticsFixtures.report
        #expect(report.items.map(\.kind) == [
            .claudeExecutable, .codexExecutable, .claudeProfile, .claudeProfile, .claudeProfile, .historyDatabase, .network, .appLocation,
        ])
        let profileIDs = report.items.filter { $0.kind == .claudeProfile }.map(\.id)
        #expect(profileIDs == profileIDs.sorted())
        #expect(report.overallStatus == .failure)
        let shuffled = SystemCheckReport(ranAt: report.ranAt, items: Array(report.items.reversed()))
        #expect(shuffled == report)
        let first = report.text(includeAccountNames: false, labels: DiagnosticsFixtures.labels)
        #expect(first == shuffled.text(includeAccountNames: false, labels: DiagnosticsFixtures.labels))
        #expect(first.hasPrefix("Codometer system check\nRan at: 2026-09-16T"))
        #expect(first.contains("Overall: failure"))
        #expect(first.contains("[failure] History database (historyDatabase): quick_check failed"))
        #expect(SystemCheckReport(ranAt: report.ranAt, items: []).overallStatus == .ok)
    }

    @Test("Redaction collapses personal folders but keeps useful paths")
    func redaction() {
        let redaction = SupportTextRedaction(homeDirectory: "/var/root", labels: [:], includeAccountNames: false)
        #expect(redaction.apply(to: "/var/root/.codex/auth.json") == "~/.codex/auth.json")
        #expect(redaction.apply(to: "~/Projects/secret/.claude-work") == "~/…/.claude-work")
        #expect(redaction.apply(to: "~/Projects/secret") == "~/…")
        #expect(redaction.apply(to: "/var/rootless/x and /var/root") == "/var/rootless/x and ~")
        #expect(redaction.apply(to: "~/code/a/b/c/claude") == "~/…/claude")
        #expect(redaction.apply(to: "~/.npm-global/bin/claude") == "~/.npm-global/bin/claude")
        // Folder names with spaces collapse whole; a second home path in the same sentence stays separate.
        #expect(redaction.apply(to: "~/Client Work/acme corp/.claude signed in") == "~/…/.claude signed in")
        #expect(redaction.apply(to: "~/Library/Mobile Documents/com~apple~CloudDocs/Projects/.codex-work: missing") == "~/Library/…/.codex-work: missing")
        #expect(redaction.apply(to: "~/Library/Application Support/Codometer/history.sqlite") == "~/Library/Application Support/Codometer/history.sqlite")
        #expect(redaction.apply(to: "~/.codex/auth.json and ~/Secret Stuff/x") == "~/.codex/auth.json and ~/…")
        #expect(redaction.apply(to: "mail me: a.b+c@sub.example.co.uk, or x@y") == "mail me: <email>, or <email>")
        #expect(redaction.apply(to: "@@ handle") == "(at)(at) handle")
        #expect(SupportTextRedaction.abbreviatingHome(in: "/Users/bob/x and /Users/alice", homeDirectory: nil) == "~/x and ~")
        // A label that looks like a placeholder never rewrites another account's placeholder.
        let first = AccountID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-000000000001") ?? UUID())
        let second = AccountID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-000000000002") ?? UUID())
        let tricky = SupportTextRedaction(homeDirectory: nil, labels: [first: "Account", second: "Account 1"], includeAccountNames: false)
        #expect(tricky.apply(to: "\(first) then \(second): Account 1 and Account") == "Account 1 then Account 2: Account 2 and Account 1")
    }

    @Test("Executable diagnostics abbreviate the home folder and validate versions")
    func executables() {
        let found = ExecutableDiagnostics(
            path: "/Users/jane.doe/.local/bin/claude",
            homeDirectory: home,
            version: "2.1.12",
            signature: .trusted(publisher: "Anthropic PBC", teamID: "Q6L2SF6YDW"),
            modifiedAt: nil,
            sizeBytes: -5
        )
        #expect(found.displayPath == "~/.local/bin/claude")
        #expect(found.version == "2.1.12")
        #expect(found.sizeBytes == 0)
        for bad in ["2.1.12 (Claude Code)", "", String(repeating: "1", count: 33), "1.0\n"] {
            #expect(ExecutableDiagnostics(path: "/opt/codex", homeDirectory: nil, version: bad, signature: .unsigned, modifiedAt: nil, sizeBytes: nil).version == nil)
        }
        #expect(ExecutableDiagnostics(path: "/Users/x/bin/codex-1.0+beta", homeDirectory: nil, version: "0.154.0-alpha+1", signature: .notFound, modifiedAt: nil, sizeBytes: nil).version == "0.154.0-alpha+1")
        let long = ExecutableDiagnostics(path: "/" + String(repeating: "a", count: 900), homeDirectory: nil, version: nil, signature: .invalid(status: -67_062), modifiedAt: nil, sizeBytes: nil)
        #expect(long.displayPath.count == ExecutableDiagnostics.maximumPathLength)
    }

    @Test("Probe records never have negative durations")
    func probeRecords() {
        let start = DiagnosticsFixtures.ranAt
        let record = ProbeRecord(kind: .claudeUsageCommand, startedAt: start, finishedAt: start.addingTimeInterval(2.4), outcome: .reading(windowCount: 3))
        #expect(abs(record.duration - 2.4) < 1e-6)
        let backwards = ProbeRecord(kind: .codexAppServer, startedAt: start, finishedAt: start.addingTimeInterval(-30), outcome: .skipped(.offline))
        #expect(backwards.duration == 0)
        #expect(ProbeRecord(kind: .codexAppServer, startedAt: start, finishedAt: start, outcome: .reading(windowCount: -2)).outcome == .reading(windowCount: 0))
        #expect(ProbeRecord.SkipReason.allCases.count == 4)
    }

    @Test("Format drift severity and bounded titles")
    func drift() {
        #expect(FormatDrift.empty.severity == .none)
        #expect(FormatDrift(codexUnknownEventTypes: 12, codexOversizedLinesSkipped: 3).severity == .none)
        #expect(FormatDrift(unknownClaudeWindowTitles: ["Current week (Opus 5)"]).severity == .note)
        #expect(FormatDrift(droppedInvalidLimitLines: 1).severity == .note)
        #expect(FormatDrift(consecutiveOutputsWithoutLimits: 2).severity == .note)
        #expect(FormatDrift(codexUnexpectedResponses: 1).severity == .note)
        #expect(FormatDrift(unknownClaudeWindowTitles: ["x"], pausedUntilManualRefresh: true).severity == .paused)
        #expect(FormatDrift.Severity.none < .note && FormatDrift.Severity.note < .paused)

        var drift = FormatDrift(unknownClaudeWindowTitles: ["a", "a", " ", "b", "c", "d"], droppedInvalidLimitLines: -4)
        #expect(drift.unknownClaudeWindowTitles == ["a", "b", "c"])
        #expect(drift.droppedInvalidLimitLines == 0)
        drift.unknownClaudeWindowTitles = [String(repeating: "t", count: 100), "\u{0}", "e", "f", "g"]
        #expect(drift.unknownClaudeWindowTitles.count == 3)
        #expect(drift.unknownClaudeWindowTitles.first?.count == FormatDrift.maximumTitleLength)
    }

    @Test("Account diagnostics keep the newest sixteen probes and a valid factor")
    func accountDiagnostics() {
        let start = DiagnosticsFixtures.ranAt
        let probes = (0..<20).map { index in
            ProbeRecord(kind: .codexAppServer, startedAt: start.addingTimeInterval(Double(index)), finishedAt: start.addingTimeInterval(Double(index) + 1), outcome: .failure(.timedOut))
        }
        let diagnostics = AccountDiagnostics(
            accountID: DiagnosticsFixtures.workID,
            provider: .codex,
            recentProbes: probes,
            lastLogReadingAt: nil,
            nextRefreshAt: nil,
            consecutiveFailures: -1,
            energyFactor: 9,
            drift: .empty
        )
        #expect(diagnostics.recentProbes.count == AccountDiagnostics.maximumProbes)
        #expect(diagnostics.recentProbes.first?.startedAt == start.addingTimeInterval(19))
        #expect(diagnostics.recentProbes.last?.startedAt == start.addingTimeInterval(4))
        #expect(diagnostics.consecutiveFailures == 0)
        #expect(diagnostics.energyFactor == 4)
        let empty = AccountDiagnostics.empty(accountID: DiagnosticsFixtures.personalID, provider: .claude)
        #expect(empty.recentProbes.isEmpty && empty.energyFactor == 1 && empty.drift == .empty && empty.provider == .claude)
        let nanFactor = AccountDiagnostics(accountID: DiagnosticsFixtures.workID, provider: .codex, recentProbes: [], lastLogReadingAt: nil, nextRefreshAt: nil, consecutiveFailures: 0, energyFactor: .nan, drift: .empty)
        #expect(nanFactor.energyFactor == 1)
    }

    @Test("Engine diagnostics carry the energy decision and power snapshot; history diagnostics are bounded")
    func engineAndHistory() {
        let history = HistoryDiagnostics(health: .ok, fileBytes: -1, schemaVersion: 4, oldestSampleAt: nil, retentionDays: 35, rowCounts: ["limit_samples": 10, "bad": -3])
        #expect(history.fileBytes == 0)
        #expect(history.rowCounts == ["limit_samples": 10, "bad": 0])
        let unavailable = HistoryDiagnostics.unavailable(reason: "closed", retentionDays: 7)
        #expect(unavailable.health == .unavailable(reason: "closed") && unavailable.rowCounts.isEmpty)
        let engine = EngineDiagnostics(
            generatedAt: DiagnosticsFixtures.ranAt,
            accounts: [.empty(accountID: DiagnosticsFixtures.workID, provider: .codex)],
            executables: [.codex: ExecutableDiagnostics(path: "/opt/homebrew/bin/codex", homeDirectory: nil, version: "0.154.0", signature: .unsigned, modifiedAt: nil, sizeBytes: 1)],
            history: history,
            energy: .normal,
            power: .nominalAC
        )
        #expect(engine.energy == .normal && engine.power == .nominalAC)
        #expect(engine.accounts.count == 1)
        #expect(SystemCheckItemKind.allCases.count == 16)
        #expect(Set(SystemCheckItemKind.allCases.map(\.reportTitle)).count == 16)
    }

    @Test("App status models sanitise their text")
    func appStatus() throws {
        let info = AppBuildInfo(version: " 1.0.0\n", build: "", locationKind: .diskImage, licenseName: "  ")
        #expect(info.version == "1.0.0" && info.build == "—" && info.licenseName == nil)
        #expect(AppLocationKind.allCases.count == 6)
        let crash = try CrashReportSummary(id: "crash-1790000000", date: DiagnosticsFixtures.ranAt, kind: .hang)
        #expect(crash.id == "crash-1790000000" && crash.kind == .hang)
        #expect(throws: ValidationError.self) { try CrashReportSummary(id: "../payload", date: DiagnosticsFixtures.ranAt, kind: .crash) }
    }

    @Test("History export and erase models")
    func historyModels() {
        let request = HistoryExportRequest(
            format: .csvFolder,
            includeAccountNames: true,
            labels: [DiagnosticsFixtures.workID: " Work\n", DiagnosticsFixtures.personalID: "\u{1}"],
            appVersion: "",
            retentionDays: 35,
            readmeText: "Columns"
        )
        #expect(request.labels == [DiagnosticsFixtures.workID: "Work"])
        #expect(request.appVersion == "unknown")
        #expect(HistoryExportFormat.allCases == [.json, .csvFolder])
        let summary = HistoryExportSummary(rowCount: -1, destination: URL(filePath: "/tmp/export.json"))
        #expect(summary.rowCount == 0)
        #expect(EraseSummary(removedItems: 5, refusedSymlinks: 0, failures: 0).isComplete)
        #expect(!EraseSummary(removedItems: 5, refusedSymlinks: 1, failures: -2).isComplete)
        #expect(EraseSummary(removedItems: -5, refusedSymlinks: 0, failures: -2).failures == 0)
        let error: HistoryExportError = .writeFailed("disk full")
        #expect(error != .cancelled)
        #expect(HistoryHealth.readOnlyNewerSchema(version: 5) != .ok)
    }
}
