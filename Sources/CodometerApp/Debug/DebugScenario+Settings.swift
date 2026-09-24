#if DEBUG
import CodometerCore
import CodometerUI
import Foundation

/// Settings pane steps: fake diagnostics and energy decisions, so the General and Diagnostics panes can be captured
/// without real probes, a real battery or a real CLI on the machine.
extension DebugScenario {
    /// Handles `diagnosticsFixture` and `energyFixture`.
    ///
    /// `{"diagnosticsFixture": "ok"|"drift"|"failures"}` makes `loadDiagnostics()` and "Check System" answer with
    /// synthetic data (`null` goes back to the engine). `{"energyFixture": "battery"|"lowPower"|"thermal"|"none"}`
    /// puts one energy decision in the store; it changes no schedule, unlike the `power` step.
    static func handleSettingsStep(_ key: String, _ value: Any, _ context: DebugContext) async throws -> Bool {
        switch key {
        case "diagnosticsFixture":
            try applyDiagnosticsFixture(value, context)
            return true
        case "energyFixture":
            try applyEnergyFixture(value, context)
            return true
        default:
            return false
        }
    }

    private static func applyDiagnosticsFixture(_ value: Any, _ context: DebugContext) throws {
        let coordinator = context.controller.diagnosticsCoordinator
        if DebugValue.isNull(value) {
            coordinator.fixture = nil
            DiagnosticsDebugReport.value = nil
            context.log(["action": "diagnosticsFixture", "fixture": "none"])
            return
        }
        guard let name = DebugValue.string(value), let fixture = DiagnosticsFixture(rawValue: name) else {
            throw DebugScenarioError(description: "diagnosticsFixture: expected null or one of \(DiagnosticsFixture.allCases.map(\.rawValue))")
        }
        coordinator.fixture = fixture
        // So a capture of the pane already shows the item list, as if Check System had been pressed.
        let report = fixture.report(now: context.store.now.addingTimeInterval(-120))
        coordinator.lastReport = report
        DiagnosticsDebugReport.value = report
        context.log(["action": "diagnosticsFixture", "fixture": fixture.rawValue])
    }

    private static func applyEnergyFixture(_ value: Any, _ context: DebugContext) throws {
        if DebugValue.isNull(value) {
            context.store.setEnergy(.normal)
            context.log(["action": "energyFixture", "fixture": "none"])
            return
        }
        guard let name = DebugValue.string(value), let snapshot = EnergyFixture(rawValue: name) else {
            throw DebugScenarioError(description: "energyFixture: expected null or one of \(EnergyFixture.allCases.map(\.rawValue))")
        }
        let decision = EnergyPolicy.decide(snapshot.snapshot, mode: snapshot.mode)
        context.store.setEnergy(decision)
        context.log(["action": "energyFixture", "fixture": name, "energyReason": decision.reason.rawValue])
    }

    /// Fields this domain adds to `capture` and `trace` lines.
    static func settingsTraceFields(_ context: DebugContext) -> [String: Any] {
        guard let fixture = context.controller.diagnosticsCoordinator.fixture else { return [:] }
        return ["diagnosticsFixture": fixture.rawValue]
    }
}

/// Synthetic engine diagnostics and system-check results for captures of the Diagnostics pane.
enum DiagnosticsFixture: String, CaseIterable {
    /// Everything works.
    case ok
    /// The providers' output drifted: one account is paused, the other only noticed unfamiliar names.
    case drift
    /// Repeated failures, a missing tool and a damaged history file.
    case failures

    /// One entry per account the store shows, so the pane's rows line up with the fixture accounts.
    func diagnostics(accounts: [(id: AccountID, provider: ProviderKind)], now: Date) -> EngineDiagnostics {
        EngineDiagnostics(
            generatedAt: now,
            accounts: accounts.enumerated().map { index, account in
                self.account(id: account.id, provider: account.provider, index: index, now: now)
            },
            executables: executables(now: now),
            history: history(),
            energy: .normal,
            power: PowerSnapshot.nominalAC
        )
    }

    /// The check result the "Check System" button answers with.
    func report(now: Date) -> SystemCheckReport {
        SystemCheckReport(ranAt: now, items: items())
    }

    // MARK: - Parts

    private func account(id: AccountID, provider: ProviderKind, index: Int, now: Date) -> AccountDiagnostics {
        let kind: ProbeRecord.Kind = provider == .claude ? .claudeUsageCommand : .codexAppServer
        var probes: [ProbeRecord] = []
        for step in 0..<8 {
            let started = now.addingTimeInterval(TimeInterval(-300 * (step + 1)))
            probes.append(ProbeRecord(
                kind: kind,
                startedAt: started,
                finishedAt: started.addingTimeInterval(1.4 + Double(step % 3) * 0.6),
                outcome: outcome(step: step, index: index)
            ))
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
        case .ok:
            return step == 5 ? .skipped(.logsFresh) : .reading(windowCount: 3)
        case .drift:
            return step % 4 == 1 ? .skipped(.pausedAfterFormatDrift) : .reading(windowCount: 2)
        case .failures:
            if step < 3 { return .failure(index == 0 ? .commandFailed : .timedOut) }
            return step == 4 ? .skipped(.offline) : .reading(windowCount: 3)
        }
    }

    private func drift(index: Int, now: Date) -> FormatDrift {
        switch self {
        case .ok:
            return .empty
        case .drift:
            return index == 0
                ? FormatDrift(
                    unknownClaudeWindowTitles: ["Current week (Opus 5)"],
                    droppedInvalidLimitLines: 2,
                    consecutiveOutputsWithoutLimits: 3,
                    pausedUntilManualRefresh: true,
                    lastDriftAt: now.addingTimeInterval(-900)
                )
                : FormatDrift(codexUnknownEventTypes: 4, codexOversizedLinesSkipped: 1, lastDriftAt: now.addingTimeInterval(-1_800))
        case .failures:
            return FormatDrift(codexUnexpectedResponses: 2, lastDriftAt: now.addingTimeInterval(-600))
        }
    }

    private func executables(now: Date) -> [ProviderKind: ExecutableDiagnostics] {
        let claude = ExecutableDiagnostics(
            path: "~/.local/bin/claude",
            homeDirectory: nil,
            version: self == .failures ? nil : "2.1.12",
            signature: self == .failures ? .unsigned : .trusted(publisher: "Anthropic PBC", teamID: "Q6L2SF6YDW"),
            modifiedAt: now.addingTimeInterval(-86_400),
            sizeBytes: 48_200_000
        )
        let codex = ExecutableDiagnostics(
            path: "/Applications/ChatGPT.app/Contents/Helpers/codex",
            homeDirectory: nil,
            version: self == .failures ? nil : "0.154.0",
            signature: self == .failures ? .notFound : .trusted(publisher: "OpenAI, Inc.", teamID: "2DC432GLL2"),
            modifiedAt: self == .failures ? nil : now.addingTimeInterval(-172_800),
            sizeBytes: self == .failures ? nil : 61_400_000
        )
        return [.claude: claude, .codex: codex]
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
}

/// Power conditions the `energyFixture` step puts straight into the store.
enum EnergyFixture: String, CaseIterable {
    case battery
    case lowBattery
    case lowPower
    case thermal
    case saver

    var snapshot: PowerSnapshot {
        switch self {
        case .battery:
            PowerSnapshot(lowPowerMode: false, onBattery: true, batteryPercent: try? Percentage(validating: 68), thermal: .nominal)
        case .lowBattery:
            PowerSnapshot(lowPowerMode: false, onBattery: true, batteryPercent: try? Percentage(validating: 15), thermal: .nominal)
        case .lowPower:
            PowerSnapshot(lowPowerMode: true, onBattery: true, batteryPercent: try? Percentage(validating: 22), thermal: .nominal)
        case .thermal:
            PowerSnapshot(lowPowerMode: false, onBattery: false, batteryPercent: nil, thermal: .serious)
        case .saver:
            PowerSnapshot.nominalAC
        }
    }

    var mode: EnergyMode { self == .saver ? .saveBattery : .automatic }
}
#endif
