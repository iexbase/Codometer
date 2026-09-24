import CodometerClaude
import CodometerCodex
import CodometerCore
import CodometerPlatform
import CodometerStorage
import Foundation

/// What the engine remembers for the Diagnostics pane between pulls (in memory only, never persisted).
///
/// `TrackerEngine` holds one value (`diagnosticsState`), so diagnostics collection adds its fields here without
/// changing the engine's own file.
struct EngineDiagnosticsState: Sendable {
    /// The power conditions behind the latest energy decision (`TrackerEngine+Energy`).
    var power: PowerSnapshot?
    /// Where the app keeps its data. Remembered from the first `checkSystem(directories:)`, so later checks can test
    /// the file modes even when the caller passes nothing.
    var directories: AppDirectories?

    init() {}
}

/// Diagnostics, pulled by the Diagnostics pane while it is visible: nothing here runs on a schedule.
extension TrackerEngine {
    /// Per-account refresh history, executables, history facts and the energy decision, gathered now.
    ///
    /// Costs one `lstat` per provider binary while nothing changes: signature information and the Claude CLI's
    /// version are cached in the probes by the binary's metadata, so a pane that pulls every five seconds starts no
    /// processes after the first pull.
    public func diagnostics() async -> EngineDiagnostics {
        var accounts: [AccountDiagnostics] = []
        for profile in settings.accounts where profile.isEnabled {
            if let monitor = monitors[profile.id] {
                accounts.append(await monitor.diagnostics())
            } else {
                accounts.append(.empty(accountID: profile.id, provider: profile.provider))
            }
        }
        let retentionDays = settings.general.historyRetention.days
        let history = if let store = dependencies.history {
            await store.diagnostics()
        } else {
            HistoryDiagnostics.unavailable(reason: "history is not open", retentionDays: retentionDays)
        }
        return EngineDiagnostics(
            generatedAt: dependencies.now(),
            accounts: accounts,
            executables: await executables(),
            history: history,
            energy: energyDecision,
            power: diagnosticsState.power
        )
    }

    /// "Check System": executables, profiles, history integrity, file modes and network.
    ///
    /// Runs off the main actor (the engine is an actor of its own) and stops adding items once `SystemCheck.budget`
    /// has passed, so a stuck filesystem cannot keep the pane's progress spinner turning.
    ///
    /// - Parameter directories: where the app keeps its data, for the two file-mode items. The first call that
    ///   passes them is remembered; without them the engine falls back to the data root this process was started
    ///   with, which is the same folder the app opened.
    public func checkSystem(directories: AppDirectories? = nil) async -> SystemCheckReport {
        let started = dependencies.now()
        if let directories {
            diagnosticsState.directories = directories
        }
        var items: [SystemCheckReport.Item] = []

        let providers = Set(settings.accounts.filter(\.isEnabled).map(\.provider))
        if providers.contains(.claude) {
            items.append(
                SystemCheck.executableItem(
                    kind: .claudeExecutable,
                    inspections: await dependencies.claudeProbe.inspectCandidates(),
                    diagnostics: await dependencies.claudeProbe.executableDiagnostics()
                )
            )
        }
        if providers.contains(.codex) {
            items.append(
                SystemCheck.executableItem(
                    kind: .codexExecutable,
                    inspections: await dependencies.codexProbe.inspectCandidates(),
                    diagnostics: await dependencies.codexProbe.executableDiagnostics()
                )
            )
        }

        for profile in settings.accounts where profile.isEnabled {
            guard !isOverBudget(since: started) else { break }
            items.append(profileItem(for: profile))
        }

        if let store = dependencies.history, !isOverBudget(since: started) {
            let quickCheck = await store.quickCheck(timeout: SystemCheck.historyTimeout)
            items.append(SystemCheck.historyItem(quickCheck: quickCheck, diagnostics: await store.diagnostics()))
        } else if dependencies.history == nil {
            items.append(
                SystemCheck.historyItem(
                    quickCheck: nil,
                    diagnostics: .unavailable(reason: "history is not open", retentionDays: settings.general.historyRetention.days)
                )
            )
        }

        if let directories = resolvedDirectories() {
            items.append(
                SystemCheck.modeItem(
                    id: SystemCheckItemKind.settingsPermissions.rawValue,
                    kind: .settingsPermissions,
                    url: directories.settingsFile,
                    expected: SystemCheck.privateFileMode
                )
            )
            items.append(
                SystemCheck.modeItem(
                    id: SystemCheckItemKind.dataFolderPermissions.rawValue,
                    kind: .dataFolderPermissions,
                    url: directories.root,
                    expected: SystemCheck.privateDirectoryMode
                )
            )
        }
        items.append(SystemCheck.networkItem(isOnline: dependencies.network.isOnline))

        return SystemCheckReport(ranAt: dependencies.now(), items: items)
    }

    // MARK: - Pieces

    /// The provider CLIs behind the enabled accounts. Providers nobody uses are not looked up at all.
    private func executables() async -> [ProviderKind: ExecutableDiagnostics] {
        var found: [ProviderKind: ExecutableDiagnostics] = [:]
        let providers = Set(settings.accounts.filter(\.isEnabled).map(\.provider))
        if providers.contains(.claude) {
            found[.claude] = await dependencies.claudeProbe.executableDiagnostics()
        }
        if providers.contains(.codex) {
            found[.codex] = await dependencies.codexProbe.executableDiagnostics()
        }
        return found
    }

    private func profileItem(for profile: AccountProfile) -> SystemCheckReport.Item {
        let directory = profile.directory.url
        switch profile.provider {
        case .claude:
            let layout = ClaudeProfileLayout(configDirectory: directory, homeDirectory: dependencies.homeDirectory)
            let signIn: SystemCheck.SignInState
            do throws(ClaudeAccountReadError) {
                signIn = try ClaudeAccountReader.identity(for: layout) == nil ? .signedOut : .signedIn
            } catch {
                signIn = .unreadable(SystemCheck.reason(for: error))
            }
            return SystemCheck.profileItem(
                id: SystemCheck.profileItemID(kind: .claudeProfile, accountID: profile.id),
                kind: .claudeProfile,
                directory: directory,
                signIn: signIn
            )
        case .codex:
            // Metadata only: `auth.json` holds credentials and is never read.
            let authFile = directory.appendingPathComponent("auth.json", isDirectory: false)
            let metadata = SecureFileIO.metadata(at: authFile)
            return SystemCheck.profileItem(
                id: SystemCheck.profileItemID(kind: .codexProfile, accountID: profile.id),
                kind: .codexProfile,
                directory: directory,
                signIn: metadata?.isRegularFile == true ? .signedIn : .signedOut
            )
        }
    }

    /// The directories a check should test: the ones a caller handed over, else this process's own data root.
    private func resolvedDirectories() -> AppDirectories? {
        if let remembered = diagnosticsState.directories { return remembered }
        let resolved = try? AppDirectories.standard(environment: ProcessInfo.processInfo.environment)
        diagnosticsState.directories = resolved
        return resolved
    }

    private func isOverBudget(since started: Date) -> Bool {
        dependencies.now().timeIntervalSince(started) >= SystemCheck.budget
    }
}
