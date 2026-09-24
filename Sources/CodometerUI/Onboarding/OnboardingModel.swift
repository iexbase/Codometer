import CodometerCore
import CodometerL10n
import Foundation
import Observation

/// What the welcome flow shows and does, between the pure `OnboardingFlow` and the window that hosts it.
///
/// Periodic work is limited to the wizard's waiting stage: a readiness check every two seconds, in a task the view
/// cancels when the stage leaves the screen. Nothing else polls.
@MainActor
@Observable
public final class OnboardingModel {
    /// How often the wizard looks for a finished sign-in while its waiting stage is on screen.
    public static let readinessInterval: Duration = .seconds(2)

    public let store: TrackerStore
    public private(set) var flow: OnboardingFlow
    /// Profile folders as the inspector last saw them; empty until a step asks for them.
    public private(set) var readiness: [ProfileReadiness] = []
    /// Synthetic readiness for captures and renders: no real profile is inspected while this is on.
    public private(set) var usesFixtureReadiness = false
    public private(set) var notifications: NotificationAuthorization = .notDetermined
    /// A rejected account change or login-item failure, shown where it happened.
    public var issue: String?

    /// The home folder the wizard's profile paths are built in.
    let homePath: String
    /// Called once, when the flow finishes or is skipped.
    @ObservationIgnored public var onComplete: ((OnboardingFlow.Outcome) -> Void)?

    public init(store: TrackerStore, isFirstRun: Bool = true, homePath: String = NSHomeDirectory()) {
        self.store = store
        self.homePath = homePath
        flow = OnboardingFlow(isFirstRun: isFirstRun)
    }

    public var step: OnboardingStep { flow.step }
    public var wizard: SecondAccountWizard { flow.wizard }

    // MARK: Navigation

    public func next() {
        guard !flow.advanceWizard(readiness: readiness, home: homePath) else { return }
        flow.next()
        completeIfNeeded()
    }

    /// Whether the primary button does anything right now (a half-typed profile name stops it).
    public var canAdvance: Bool { flow.canAdvance }

    public func back() {
        flow.back()
    }

    public func escape() {
        flow.escape()
        completeIfNeeded()
    }

    public func skip() {
        flow.skip()
        completeIfNeeded()
    }

    public func finish() {
        flow.finish()
        completeIfNeeded()
    }

    /// A debug scenario jumps to a step; captures of a step never walk the whole flow.
    public func go(to step: OnboardingStep) {
        flow.go(to: step)
    }

    private func completeIfNeeded() {
        guard let outcome = flow.outcome else { return }
        let handler = onComplete
        onComplete = nil
        handler?(outcome)
    }

    // MARK: Readiness

    /// Reads the profile folders again (filesystem metadata only). Does nothing while synthetic readiness is in use.
    public func refreshReadiness() async {
        guard !usesFixtureReadiness else { return }
        let found = await store.actions.inspectProfiles()
        guard found != readiness else { return }
        readiness = found
        flow.applyReadiness(found, home: homePath)
    }

    /// Replaces readiness with synthetic folders, so renders and captures never show a real profile or plan. Nothing
    /// is inspected while this is on.
    public func installFixtureReadiness(_ custom: [ProfileReadiness]? = nil) {
        usesFixtureReadiness = true
        readiness = custom ?? OnboardingModel.fixtureReadiness(home: homePath)
    }

    /// Two Claude folders (one signed in, one waiting for a sign-in) and a Codex folder that is signed in.
    public static func fixtureReadiness(home: String) -> [ProfileReadiness] {
        let folders: [(ProviderKind, String, ProfileReadiness.State)] = [
            (.claude, ".claude", .signedIn(plan: "Pro 20x")),
            (.claude, ".claude-work", .notSignedIn),
            (.codex, ".codex", .signedIn(plan: nil)),
        ]
        return folders.compactMap { provider, name, state in
            guard let directory = try? ProfileDirectory(validating: (home as NSString).appendingPathComponent(name)) else {
                return nil
            }
            return ProfileReadiness(provider: provider, directory: directory, state: state, cli: nil)
        }
    }

    // MARK: Accounts

    /// Every profile folder the "Found on this Mac" step lists: the accounts already in settings first, then folders
    /// that are not tracked yet, each with what the filesystem says about it.
    public var foundProfiles: [FoundProfile] {
        var rows: [FoundProfile] = []
        var seen = Set<String>()
        for account in store.settings.accounts {
            let key = "\(account.provider.rawValue):\(account.directory.path)"
            seen.insert(key)
            rows.append(FoundProfile(
                id: key,
                provider: account.provider,
                directory: account.directory,
                label: account.label.value,
                accountID: account.id,
                isTracked: account.isEnabled,
                state: readiness.first { $0.id == key }?.state
            ))
        }
        for found in readiness where !seen.contains(found.id) {
            if case .missingFolder = found.state { continue }
            rows.append(FoundProfile(
                id: found.id,
                provider: found.provider,
                directory: found.directory,
                label: OnboardingAccounts.suggestedLabel(provider: found.provider, directory: found.directory),
                accountID: nil,
                isTracked: false,
                state: found.state
            ))
        }
        return rows
    }

    /// The "Track" switch of one row: enables or disables an account, or adds the folder as a new account.
    public func setTracked(_ row: FoundProfile, _ isTracked: Bool, l10n: Localizer) {
        if let accountID = row.accountID {
            guard let profile = store.settings.account(accountID) else { return }
            guard let updated = try? profile.updated(isEnabled: isTracked) else { return }
            report(store.replaceAccount(updated), l10n: l10n)
            return
        }
        guard isTracked, let label = try? AccountLabel(validating: row.label) else { return }
        guard let profile = try? AccountProfile(provider: row.provider, label: label, directory: row.directory) else { return }
        report(store.addAccount(profile), l10n: l10n)
    }

    /// Adds the account the wizard prepared, then returns the wizard to its offer.
    public func addWizardAccount(l10n: Localizer) {
        guard let suffix = wizard.suffix, let path = wizard.folderPath(home: homePath) else { return }
        let fallback = OnboardingAccounts.label(provider: wizard.provider, suffix: suffix.value)
        let text = wizard.label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let label = try? AccountLabel(validating: text.isEmpty ? fallback : text),
            let directory = try? ProfileDirectory(validating: path),
            let profile = try? AccountProfile(provider: wizard.provider, label: label, directory: directory, groupID: wizard.groupID)
        else { return }
        if let failure = store.addAccount(profile) {
            report(failure, l10n: l10n)
            return
        }
        issue = nil
        flow.accountAdded()
    }

    private func report(_ failure: ValidationError?, l10n: Localizer) {
        issue = failure.map { SettingsCopy.accountMessage(for: $0, l10n: l10n) }
    }

    // MARK: Wizard events

    public func startWizard() {
        flow.startWizard()
    }

    /// Picks the service and moves on (the service stage's own action).
    public func chooseService(_ provider: ProviderKind) {
        flow.chooseService(provider)
        flow.setLabel(defaultWizardLabel)
    }

    /// Picks the service without leaving the stage; the footer's button moves on.
    public func setService(_ provider: ProviderKind) {
        flow.setService(provider)
        flow.setLabel(defaultWizardLabel)
    }

    public func setSuffixText(_ text: String) {
        flow.setSuffixText(text)
        flow.setLabel(defaultWizardLabel)
    }

    public func setWizardLabel(_ text: String) {
        flow.setLabel(text)
    }

    public func setWizardGroup(_ id: AccountGroupID?) {
        flow.setGroup(id)
    }

    public func confirmProfileName() {
        flow.confirmProfileName(readiness: readiness, home: homePath)
    }

    public func startWaitingForSignIn() {
        flow.startWaitingForSignIn()
    }

    /// The label the last stage offers: "Claude · work".
    public var defaultWizardLabel: String {
        OnboardingAccounts.label(provider: wizard.provider, suffix: wizard.suffix?.value ?? wizard.suffixText)
    }

    // MARK: Notifications

    public func refreshNotificationAuthorization() async {
        let status = await store.actions.notificationAuthorization()
        guard status != notifications else { return }
        notifications = status
    }

    public func requestNotifications() async {
        _ = await store.actions.requestNotificationPermission()
        await refreshNotificationAuthorization()
    }
}

/// One row of "Found on this Mac": a profile folder, whether Codometer watches it, and what the filesystem says.
public struct FoundProfile: Identifiable, Hashable, Sendable {
    public let id: String
    public let provider: ProviderKind
    public let directory: ProfileDirectory
    public let label: String
    /// The account in settings, when the folder is already one.
    public let accountID: AccountID?
    public let isTracked: Bool
    /// `nil` before the inspector has looked at this folder.
    public let state: ProfileReadiness.State?
}

/// Naming rules shared by the wizard and the "Found on this Mac" step, all on Core's `ProfileSuffix`, so a
/// folder the flow proposes is one `ProfileDiscovery` recognises.
public enum OnboardingAccounts {
    /// `""` for the default folder, the suffix for `.<provider>-<suffix>`, `nil` for anything else.
    public static func suffix(ofFolder name: String, provider: ProviderKind) -> String? {
        let base = provider.defaultDirectoryName
        if name == base { return "" }
        guard name.hasPrefix(base + "-") else { return nil }
        return (try? ProfileSuffix(String(name.dropFirst(base.count + 1))))?.value
    }

    /// "Claude" for the default folder, "Claude · work" for a variant.
    public static func label(provider: ProviderKind, suffix: String) -> String {
        let base = WidgetText.providerName(provider)
        return suffix.isEmpty ? base : "\(base) · \(suffix)"
    }

    /// The label a folder gets when it becomes an account.
    public static func suggestedLabel(provider: ProviderKind, directory: ProfileDirectory) -> String {
        label(provider: provider, suffix: suffix(ofFolder: directory.lastComponent, provider: provider) ?? "")
    }

    /// A profile folder as text, with the home folder written `~` — whose home it is never shows, in the window or
    /// in a capture of it.
    public static func displayPath(_ path: String, home: String) -> String {
        guard !home.isEmpty, path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }
}
