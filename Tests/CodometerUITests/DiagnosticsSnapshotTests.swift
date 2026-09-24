import CodometerCore
import CodometerL10n
@testable import CodometerUI
import AppKit
import Foundation
import SwiftUI
import Testing

/// Synthetic engine diagnostics and check reports for the renders: the same three shapes the debug harness installs
/// (`diagnosticsFixture`), built here because the UI tests cannot import the app.
enum DiagnosticsRenderFixture: String, CaseIterable {
    case ok, drift, failures

    func diagnostics(accounts: [(id: AccountID, provider: ProviderKind)], now: Date) -> EngineDiagnostics {
        EngineDiagnostics(
            generatedAt: now,
            accounts: accounts.enumerated().map { index, account in
                self.account(id: account.id, provider: account.provider, index: index, now: now)
            },
            executables: executables(now: now),
            history: history(),
            energy: self == .failures
                ? EnergyDecision(factor: (try? EnergyFactor(2)) ?? .normal, urgentCapFactor: .normal, reason: .battery, pausesLiveEffects: false)
                : .normal,
            power: .nominalAC
        )
    }

    func report(now: Date) -> SystemCheckReport {
        SystemCheckReport(ranAt: now, items: items())
    }

    /// The same three item lists the debug harness installs, so the renders match the harness captures.
    private func items() -> [SystemCheckReport.Item] {
        func make(_ kind: SystemCheckItemKind, _ status: SystemCheckReport.Item.Status, _ detail: String) -> SystemCheckReport.Item {
            SystemCheckReport.Item(id: kind.rawValue, status: status, kind: kind, detail: detail)
        }
        switch self {
        case .ok:
            return [
                make(.claudeExecutable, .ok, "~/.local/bin/claude, signed by Anthropic PBC (Q6L2SF6YDW), version 2.1.12"),
                make(.codexExecutable, .ok, "codex, signed by OpenAI, Inc. (2DC432GLL2), version 0.154.0"),
                make(.claudeProfile, .ok, "readable, signed in"),
                make(.codexProfile, .ok, "readable, signed in"),
                make(.historyDatabase, .ok, "integrity check passed, 3793 KiB"),
                make(.settingsPermissions, .ok, "mode 0600"),
                make(.dataFolderPermissions, .ok, "mode 0700"),
                make(.network, .ok, "a network path is available"),
                make(.notifications, .ok, "allowed"),
                make(.loginItem, .ok, "registered"),
                make(.shortcut, .ok, "registered"),
                make(.widgetSnapshot, .ok, "last written 2 min ago"),
                make(.displays, .ok, "2 connected"),
                make(.appLocation, .ok, "Applications"),
                make(.crashReports, .ok, "none stored"),
                make(.serviceStatus, .ok, "off, so nothing is requested"),
            ]
        case .drift:
            return [
                make(.claudeExecutable, .ok, "~/.local/bin/claude, signed by Anthropic PBC (Q6L2SF6YDW), version 2.1.12"),
                make(.codexExecutable, .ok, "codex, signed by OpenAI, Inc. (2DC432GLL2), version 0.154.0"),
                make(.claudeProfile, .ok, "readable, signed in"),
                make(.codexProfile, .warning, "readable, but the profile is not signed in"),
                make(.historyDatabase, .note, "integrity check did not finish, 3793 KiB"),
                make(.settingsPermissions, .ok, "mode 0600"),
                make(.dataFolderPermissions, .ok, "mode 0700"),
                make(.network, .ok, "a network path is available"),
                make(.notifications, .note, "not asked for yet"),
                make(.loginItem, .ok, "off"),
                make(.shortcut, .warning, "used by a macOS shortcut, 2 free alternatives"),
                make(.widgetSnapshot, .note, "last written 94 min ago"),
                make(.displays, .ok, "1 connected"),
                make(.appLocation, .note, "not in an Applications folder"),
                make(.crashReports, .ok, "none stored"),
                make(.serviceStatus, .ok, "on"),
            ]
        case .failures:
            return [
                make(.claudeExecutable, .warning, "found, but not signed by the expected publisher: unsigned"),
                make(.codexExecutable, .failure, "not installed in any known location"),
                make(.claudeProfile, .failure, "directory is missing"),
                make(.codexProfile, .failure, "a symbolic link, which the app refuses to follow"),
                make(.historyDatabase, .warning, "the previous file was damaged and was moved aside"),
                make(.settingsPermissions, .warning, "mode 0644, expected 0600"),
                make(.dataFolderPermissions, .ok, "mode 0700"),
                make(.network, .warning, "offline"),
                make(.notifications, .warning, "not allowed; alerts will not appear"),
                make(.loginItem, .warning, "waiting for approval in System Settings"),
                make(.shortcut, .warning, "held exclusively by another app, 1 free alternative"),
                make(.widgetSnapshot, .warning, "mode 0644, expected 0600"),
                make(.displays, .note, "none reported"),
                make(.appLocation, .warning, "running from a disk image; move it to Applications"),
                make(.crashReports, .note, "2 stored on this Mac"),
                make(.serviceStatus, .note, "on, 1 vendor check failed last time"),
            ]
        }
    }

    private func account(id: AccountID, provider: ProviderKind, index: Int, now: Date) -> AccountDiagnostics {
        let kind: ProbeRecord.Kind = provider == .claude ? .claudeUsageCommand : .codexAppServer
        let probes = (0..<8).map { step -> ProbeRecord in
            let started = now.addingTimeInterval(TimeInterval(-300 * (step + 1)))
            return ProbeRecord(
                kind: kind,
                startedAt: started,
                finishedAt: started.addingTimeInterval(1.4 + Double(step % 3) * 0.6),
                outcome: outcome(step: step, index: index)
            )
        }
        return AccountDiagnostics(
            accountID: id,
            provider: provider,
            recentProbes: probes,
            lastLogReadingAt: provider == .codex ? now.addingTimeInterval(-90) : nil,
            nextRefreshAt: now.addingTimeInterval(self == .failures ? 600 : 180),
            consecutiveFailures: self == .failures ? 3 : 0,
            energyFactor: self == .failures ? 2 : 1,
            drift: drift(index: index, now: now)
        )
    }

    private func outcome(step: Int, index: Int) -> ProbeRecord.Outcome {
        switch self {
        case .ok: step == 5 ? .skipped(.logsFresh) : .reading(windowCount: 3)
        case .drift: step % 4 == 1 ? .skipped(.pausedAfterFormatDrift) : .reading(windowCount: 2)
        case .failures: step < 3 ? .failure(index == 0 ? .commandFailed : .timedOut) : (step == 4 ? .skipped(.offline) : .reading(windowCount: 3))
        }
    }

    private func drift(index: Int, now: Date) -> FormatDrift {
        switch self {
        case .ok:
            .empty
        case .drift:
            index == 0
                ? FormatDrift(
                    unknownClaudeWindowTitles: ["Current week (Opus 5)"],
                    droppedInvalidLimitLines: 2,
                    consecutiveOutputsWithoutLimits: 3,
                    pausedUntilManualRefresh: true,
                    lastDriftAt: now.addingTimeInterval(-900)
                )
                : FormatDrift(codexUnknownEventTypes: 4, codexOversizedLinesSkipped: 1, lastDriftAt: now.addingTimeInterval(-1_800))
        case .failures:
            FormatDrift(codexUnexpectedResponses: 2, lastDriftAt: now.addingTimeInterval(-600))
        }
    }

    private func executables(now: Date) -> [ProviderKind: ExecutableDiagnostics] {
        [
            .claude: ExecutableDiagnostics(
                path: "~/.local/bin/claude",
                homeDirectory: nil,
                version: self == .failures ? nil : "2.1.12",
                signature: self == .failures ? .unsigned : .trusted(publisher: "Anthropic PBC", teamID: "Q6L2SF6YDW"),
                modifiedAt: now.addingTimeInterval(-86_400),
                sizeBytes: 48_200_000
            ),
            .codex: ExecutableDiagnostics(
                path: "/Applications/ChatGPT.app/Contents/Helpers/codex",
                homeDirectory: nil,
                version: self == .failures ? nil : "0.154.0",
                signature: self == .failures ? .notFound : .trusted(publisher: "OpenAI, Inc.", teamID: "2DC432GLL2"),
                modifiedAt: self == .failures ? nil : now.addingTimeInterval(-172_800),
                sizeBytes: self == .failures ? nil : 61_400_000
            ),
        ]
    }

    private func history() -> HistoryDiagnostics {
        HistoryDiagnostics(
            health: self == .failures ? .recoveredFromCorruption(backupFileName: "history.corrupt-20260918.sqlite") : .ok,
            fileBytes: 3_884_646,
            schemaVersion: 4,
            oldestSampleAt: Date(timeIntervalSince1970: 1_786_998_000),
            retentionDays: 35,
            rowCounts: ["limit_samples": 41_208, "session_segments": 3_940, "token_usage": 9_112, "collection_runs": 128]
        )
    }
}

/// Holds the account ids the fixture answers for, so the store and its diagnostics closures can refer to each other.
@MainActor
final class AccountIDBox {
    var accounts: [(id: AccountID, provider: ProviderKind)] = []
}

/// The Diagnostics pane drawn whole, in English and Russian, light and dark, with everything working, with format
/// drift and with failures. Runs only with `CODOMETER_SNAPSHOT_DIR`.
@MainActor
@Suite("Diagnostics pane renders", .enabled(if: ProcessInfo.processInfo.environment["CODOMETER_SNAPSHOT_DIR"] != nil))
struct DiagnosticsSnapshotTests {
    private let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODOMETER_SNAPSHOT_DIR"] ?? "/tmp", isDirectory: true)

    @Test("Diagnostics in both languages, light and dark, for every fixture")
    func renderDiagnostics() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (preference, region) in [(LanguagePreference.english, "en_US"), (.russian, "ru_RU")] {
            for fixture in DiagnosticsRenderFixture.allCases {
                for dark in [false, true] {
                    let store = try makeStore(fixture: fixture, language: preference, region: region)
                    DiagnosticsDebugReport.value = fixture.report(now: C6Store.now.addingTimeInterval(-120))
                    try await SettingsPaneRenderer.render(
                        store: store,
                        pane: .diagnostics,
                        width: C6Measure.defaultDetailWidth,
                        dark: dark,
                        to: directory.appendingPathComponent(SettingsPaneRenderer.fileName(
                            "settings-diagnostics-\(fixture.rawValue)",
                            language: store.localizer.language,
                            dark: dark,
                            narrow: false
                        ))
                    )
                }
            }
            // The narrowest column with the longest copy (the paused drift note).
            let narrow = try makeStore(fixture: .drift, language: preference, region: region)
            DiagnosticsDebugReport.value = DiagnosticsRenderFixture.drift.report(now: C6Store.now.addingTimeInterval(-120))
            try await SettingsPaneRenderer.render(
                store: narrow,
                pane: .diagnostics,
                width: C6Measure.narrowestDetailWidth,
                dark: false,
                to: directory.appendingPathComponent(SettingsPaneRenderer.fileName(
                    "settings-diagnostics-drift",
                    language: narrow.localizer.language,
                    dark: false,
                    narrow: true
                ))
            )
        }
    }

    private func makeStore(fixture: DiagnosticsRenderFixture, language: LanguagePreference, region: String) throws -> TrackerStore {
        let now = C6Store.now
        // The fixture needs the store's account ids, and the store needs the fixture's closures: the box breaks the knot.
        let box = AccountIDBox()
        let crashes = fixture == .failures
            ? [try CrashReportSummary(id: "2026-09-17-crash", date: now.addingTimeInterval(-7_200), kind: .crash)]
            : []
        let store = try C6Store.make(
            language: language,
            region: Locale(identifier: region),
            loadDiagnostics: { fixture.diagnostics(accounts: box.accounts, now: now) },
            runSystemCheck: { fixture.report(now: now.addingTimeInterval(-120)) },
            crashReports: crashes
        )
        box.accounts = store.settings.accounts.map { (id: $0.id, provider: $0.provider) }
        return store
    }
}

/// Words the Diagnostics pane builds, in both languages, and whether they fit their rows.
@MainActor
@Suite("Diagnostics pane copy")
struct DiagnosticsCopyTests {
    static let now = Date(timeIntervalSince1970: 1_789_590_000)

    @Test("Every check item has a localized title and a status word, never colour alone")
    func itemTitles() {
        for l10n in C6Measure.languages {
            for kind in SystemCheckItemKind.allCases {
                let title = DiagnosticsText.title(kind, l10n: l10n)
                #expect(!title.isEmpty)
                #expect(title != kind.rawValue, "\(l10n.language) \(kind) is untranslated")
            }
            for status in SystemCheckReport.Item.Status.allCases {
                #expect(!DiagnosticsText.status(status, l10n: l10n).isEmpty)
                #expect(!DiagnosticsText.symbol(status).isEmpty)
            }
            // Four distinct words, so the status is readable without the colour.
            let words = Set(SystemCheckReport.Item.Status.allCases.map { DiagnosticsText.status($0, l10n: l10n) })
            #expect(words.count == SystemCheckReport.Item.Status.allCases.count)
        }
    }

    @Test("A check row's title and status word fit beside each other at the narrowest width")
    func itemRowFits() {
        let room = C6Measure.rowWidth(C6Measure.narrowestDetailWidth) - 24
        for l10n in C6Measure.languages {
            for kind in SystemCheckItemKind.allCases {
                for status in SystemCheckReport.Item.Status.allCases {
                    let width = C6Measure.width(DiagnosticsText.title(kind, l10n: l10n), C6Measure.body)
                        + C6Measure.width(DiagnosticsText.status(status, l10n: l10n), C6Measure.callout)
                        + 18
                    #expect(width <= room, "\(l10n.language) \(kind)/\(status): \(width) > \(room)")
                }
            }
        }
    }

    @Test("The last-refresh line stays within two lines in both languages")
    func lastRefreshLine() {
        let room = C6Measure.rowWidth(C6Measure.narrowestDetailWidth)
        for l10n in C6Measure.languages {
            for outcome in [ProbeRecord.Outcome.reading(windowCount: 12), .failure(.timedOut), .skipped(.pausedAfterFormatDrift)] {
                let probe = ProbeRecord(
                    kind: .claudeUsageCommand,
                    startedAt: Self.now.addingTimeInterval(-300),
                    finishedAt: Self.now.addingTimeInterval(-297.6),
                    outcome: outcome
                )
                let diagnostics = AccountDiagnostics(
                    accountID: AccountID(),
                    provider: .claude,
                    recentProbes: [probe],
                    lastLogReadingAt: nil,
                    nextRefreshAt: nil,
                    consecutiveFailures: 0,
                    energyFactor: 1,
                    drift: .empty
                )
                let text = DiagnosticsText.lastRefresh(diagnostics, provider: .claude, l10n: l10n)
                #expect(C6Measure.lines(text, C6Measure.callout, width: room) <= 2, "\(l10n.language): \(text)")
                #expect(text.contains("·"))
            }
            #expect(DiagnosticsText.lastRefresh(nil, provider: .claude, l10n: l10n) == l10n.diagnostics.noRefreshYet)
        }
    }

    @Test("Probe outcomes read in words, and every outcome has its own shape and colour")
    func probeMarks() {
        for l10n in C6Measure.languages {
            #expect(DiagnosticsText.outcome(.reading(windowCount: 1), provider: .claude, l10n: l10n) != DiagnosticsText.outcome(.reading(windowCount: 5), provider: .claude, l10n: l10n))
            for reason in ProbeRecord.SkipReason.allCases {
                let text = DiagnosticsText.outcome(.skipped(reason), provider: .codex, l10n: l10n)
                #expect(text.contains(DiagnosticsText.skip(reason, l10n: l10n)))
            }
            let failure = DiagnosticsText.outcome(.failure(.timedOut), provider: .codex, l10n: l10n)
            #expect(failure == UsageFormat.issue(TrackerIssue(kind: .timedOut, detail: "", occurredAt: .distantPast), provider: .codex, l10n: l10n))
        }
        // Shapes differ, so the marks work without colour.
        let reading = DiagnosticsText.shape(for: .reading(windowCount: 1))
        let failed = DiagnosticsText.shape(for: .failure(.offline))
        let skipped = DiagnosticsText.shape(for: .skipped(.offline))
        let box = CGRect(x: 0, y: 0, width: 9, height: 9)
        #expect(reading.path(in: box).description != failed.path(in: box).description)
        #expect(failed.path(in: box).description != skipped.path(in: box).description)
        #expect(reading.path(in: box).description != skipped.path(in: box).description)
    }

    @Test("Russian plurals agree with the count")
    func plurals() {
        let ru = Localizer.testRussian
        #expect(ru.diagnostics.limitsRead(1) == "1 лимит")
        #expect(ru.diagnostics.limitsRead(3) == "3 лимита")
        #expect(ru.diagnostics.limitsRead(11) == "11 лимитов")
        #expect(ru.diagnostics.days(1) == "1 день")
        #expect(ru.diagnostics.days(35) == "35 дней")
        #expect(ru.diagnostics.days(2) == "2 дня")
        let en = Localizer.testEnglish
        #expect(en.diagnostics.limitsRead(1) == "1 limit")
        #expect(en.diagnostics.limitsRead(3) == "3 limits")
        #expect(en.diagnostics.days(35) == "35 days")
    }

    @Test("File sizes and energy factors read naturally in both languages")
    func numbers() {
        #expect(DiagnosticsText.fileSize(3_884_646, l10n: .testEnglish) == "3.7 MB")
        #expect(DiagnosticsText.fileSize(3_884_646, l10n: .testRussian) == "3,7\u{00A0}МБ")
        #expect(DiagnosticsText.fileSize(41_000, l10n: .testEnglish) == "40 KB")
        #expect(DiagnosticsText.factor(2, l10n: .testEnglish) == "2")
        #expect(DiagnosticsText.factor(1.5, l10n: .testEnglish) == "1.5")
        #expect(DiagnosticsText.factor(1.5, l10n: .testRussian) == "1,5")
    }

    @Test("An entry weeks back keeps its date instead of a bare weekday")
    func pastDates() {
        // 30 days before `now`: `format.moment` treats every past date as "within six days" and prints the weekday
        // alone, which names no particular Tuesday.
        let old = Self.now.addingTimeInterval(-30 * 86_400)
        for l10n in C6Measure.languages {
            let past = l10n.diagnostics.pastMoment(old)
            #expect(past != l10n.format.moment(old, now: Self.now), "\(l10n.language): \(past)")
            #expect(past.contains(l10n.format.clock(old)), "\(l10n.language): \(past)")
            // A weekday name alone would leave the month out.
            #expect(!past.contains(l10n.format.weekdayShort(old)), "\(l10n.language): \(past)")
        }
        #expect(Localizer.testEnglish.diagnostics.pastMoment(old).contains("Aug"))
        #expect(Localizer.testRussian.diagnostics.pastMoment(old).contains("авг"))
    }

    @Test("Every history health and signature state has words")
    func states() {
        for l10n in C6Measure.languages {
            let healths: [HistoryHealth] = [
                .ok,
                .unavailable(reason: "closed"),
                .recoveredFromCorruption(backupFileName: "history.corrupt.sqlite"),
                .readOnlyNewerSchema(version: 5),
                .writesPaused(reason: "disk full"),
            ]
            #expect(Set(healths.map { DiagnosticsText.health($0, l10n: l10n) }).count == healths.count)
            let signatures: [ExecutableDiagnostics.Signature] = [
                .trusted(publisher: "Anthropic PBC", teamID: "Q6L2SF6YDW"),
                .untrusted(teamID: "ABCDE12345"),
                .untrusted(teamID: nil),
                .unsigned,
                .notFound,
                .invalid(status: -67062),
            ]
            #expect(Set(signatures.map { DiagnosticsText.signature($0, l10n: l10n) }).count == signatures.count)
            #expect(DiagnosticsText.signature(signatures[0], l10n: l10n).contains("Q6L2SF6YDW"))
            #expect(DiagnosticsText.signature(signatures[5], l10n: l10n).contains("-67062"))
            for kind in CrashReportSummary.Kind.allCases {
                #expect(!DiagnosticsText.crashKind(kind, l10n: l10n).isEmpty)
            }
        }
    }

    @Test("The drift note and the pause explanation fit the narrowest column")
    func driftCopy() {
        let room = C6Measure.rowWidth(C6Measure.narrowestDetailWidth) - 20
        for l10n in C6Measure.languages {
            #expect(C6Measure.lines(l10n.diagnostics.driftNote, C6Measure.callout, width: room) <= 3, "\(l10n.language)")
            #expect(C6Measure.lines(l10n.diagnostics.driftPaused, C6Measure.callout, width: room) <= 8, "\(l10n.language)")
            #expect(C6Measure.lines(l10n.diagnostics.reportFooter, C6Measure.subheadline, width: room) <= 6, "\(l10n.language)")
        }
    }

    @Test("Each account's Refresh Now is named, so identical buttons are told apart")
    func refreshLabels() {
        for l10n in C6Measure.languages {
            let work = l10n.diagnostics.refreshAccountA11y("Work")
            let personal = l10n.diagnostics.refreshAccountA11y("Personal")
            #expect(work != personal)
            #expect(work.contains("Work"))
            #expect(work != l10n.accounts.refreshNow)
        }
    }
}

/// Counts how often the pane asks the engine, so "no work while the pane is hidden" is measured, not assumed.
@MainActor
final class DiagnosticsLoadCounter {
    private(set) var loads = 0

    func record() { loads += 1 }
}

/// The pull loop: one load when the pane appears, and nothing more once the pane is gone.
@MainActor
@Suite("Diagnostics pane refresh", .timeLimit(.minutes(1)))
struct DiagnosticsRefreshTests {
    @Test("Leaving the pane stops the five-second refresh")
    func loopStopsOnDisappear() async throws {
        let counter = DiagnosticsLoadCounter()
        let now = C6Store.now
        let store = try C6Store.make(
            language: .english,
            region: Locale(identifier: "en_US"),
            loadDiagnostics: {
                counter.record()
                return DiagnosticsRenderFixture.ok.diagnostics(accounts: [], now: now)
            }
        )
        let window = NSWindow(
            contentRect: NSRect(x: -30_000, y: -30_000, width: 700, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsPaneCaptureView(store: store, pane: .diagnostics))
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        // The load the pane runs when it appears; the machine may be busy, so wait for it rather than assume a delay.
        var waited = 0
        while counter.loads == 0, waited < 100 {
            try await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
        let afterAppear = counter.loads
        #expect(afterAppear >= 1, "the pane never loaded diagnostics")

        // Another pane replaces it: the loop must be cancelled with the view.
        window.contentView = NSHostingView(rootView: SettingsPaneCaptureView(store: store, pane: .general))
        // Longer than the interval plus its tolerance, so a live loop would certainly tick.
        try await Task.sleep(for: .seconds(DiagnosticsPane.refreshInterval.components.seconds + 3))
        #expect(counter.loads == afterAppear, "the pane kept loading after it went away")
    }
}
