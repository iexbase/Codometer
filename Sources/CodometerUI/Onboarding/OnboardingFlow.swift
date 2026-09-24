import CodometerCore
import Foundation

/// The six steps of the welcome flow, in order.
public enum OnboardingStep: Int, CaseIterable, Hashable, Sendable, Identifiable {
    case welcome
    case found
    case presentation
    case secondAccount
    case notifications
    case done

    public var id: Int { rawValue }

    /// How many steps the indicator counts ("Step 2 of 6").
    public static var total: Int { allCases.count }

    /// 1-based, for the indicator.
    public var number: Int { rawValue + 1 }

    var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }
    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
}

/// The optional second-account sub-flow, driven entirely by values: which service, what the profile folder is called,
/// the Terminal commands to run, and what the filesystem says about the folder.
///
/// The naming rule is Core's `ProfileSuffix`, the same one `ProfileDiscovery.variant` uses, so a folder the wizard
/// proposes is one the engine recognises.
public struct SecondAccountWizard: Hashable, Sendable {
    public enum Stage: Hashable, Sendable {
        /// The offer, with "Set Up a Second Account" and "Not now".
        case intro
        case service
        case name
        case signIn
        case waiting
        case detected
    }

    public static let defaultSuffix = "work"

    public private(set) var stage: Stage = .intro
    public var provider: ProviderKind = .claude
    /// What the user typed; `suffix` is the validated form.
    public var suffixText: String = SecondAccountWizard.defaultSuffix
    /// The label offered on the last stage, once the profile was found.
    public var label: String = ""
    public var groupID: AccountGroupID?

    public init() {}

    public var suffix: ProfileSuffix? { try? ProfileSuffix(suffixText) }

    /// `~/.claude-work`; `nil` while the typed suffix is invalid.
    public var folderDisplayPath: String? {
        suffix.map { "~/" + $0.folderName(for: provider) }
    }

    /// The absolute path of the folder the wizard is about to watch, in `home`.
    public func folderPath(home: String) -> String? {
        suffix.map { (home as NSString).appendingPathComponent($0.folderName(for: provider)) }
    }

    /// The Terminal commands for this service and folder, from Core (never localized).
    public var commands: [String] {
        guard let suffix else { return [] }
        return SecondAccountCommands.signIn(provider: provider, suffix: suffix)
    }

    // MARK: Transitions

    mutating func start() {
        stage = .service
    }

    mutating func chose(_ provider: ProviderKind) {
        self.provider = provider
        stage = .name
    }

    /// Leaves the name stage. A folder that already looks like a profile skips the commands: signed in goes straight
    /// to the last stage, a folder without a sign-in waits for one.
    mutating func confirmName(readiness: [ProfileReadiness], home: String) {
        guard suffix != nil else { return }
        switch existingState(readiness: readiness, home: home) {
        case .some(.signedIn):
            stage = .detected
        case .some(.notSignedIn):
            stage = .waiting
        case .some(.missingFolder), .some(.notAProfile), .some(.symlinkRefused), .none:
            stage = .signIn
        }
    }

    mutating func startWaiting() {
        stage = .waiting
    }

    /// The two-second watch delivered new readiness: a signed-in folder ends the wait.
    mutating func apply(readiness: [ProfileReadiness], home: String) {
        guard stage == .waiting else { return }
        guard case .some(.signedIn) = existingState(readiness: readiness, home: home) else { return }
        stage = .detected
    }

    /// One stage on; `false` when the wizard has nothing left to do and the flow should leave the step instead.
    ///
    /// The step's own footer button drives this, so the wizard never shows a second "Continue" of its own.
    mutating func advance(readiness: [ProfileReadiness], home: String) -> Bool {
        switch stage {
        case .intro, .waiting, .detected:
            return false
        case .service:
            stage = .name
            return true
        case .name:
            guard suffix != nil else { return false }
            confirmName(readiness: readiness, home: home)
            return true
        case .signIn:
            stage = .waiting
            return true
        }
    }

    /// Whether the footer's button would do anything here (a half-typed profile name stops it).
    var canAdvance: Bool {
        switch stage {
        case .intro, .waiting, .detected: return true
        case .service, .signIn: return true
        case .name: return suffix != nil
        }
    }

    /// One stage back; `false` when the wizard is already at its offer and the flow should leave the step instead.
    @discardableResult
    mutating func back() -> Bool {
        switch stage {
        case .intro: return false
        case .service: stage = .intro
        case .name: stage = .service
        case .signIn: stage = .name
        case .waiting: stage = .signIn
        case .detected: stage = .waiting
        }
        return true
    }

    /// After the account was added: back to the offer, with a fresh suffix, so another one can follow.
    mutating func reset() {
        self = SecondAccountWizard()
    }

    /// The readiness of the folder this wizard names, if the inspector saw it.
    func existingState(readiness: [ProfileReadiness], home: String) -> ProfileReadiness.State? {
        guard let path = folderPath(home: home) else { return nil }
        return readiness.first { $0.provider == provider && $0.directory.path == path }?.state
    }
}

/// Where the welcome flow is and how it ended. Pure: the window and the views read it and send events back.
public struct OnboardingFlow: Hashable, Sendable {
    public enum Outcome: Hashable, Sendable {
        /// "Start Using Codometer" on the last step.
        case finished
        /// Skip, Esc on the first step, or closing the window; onboarding counts as completed either way.
        case skipped
    }

    public private(set) var step: OnboardingStep = .welcome
    public private(set) var wizard = SecondAccountWizard()
    public private(set) var outcome: Outcome?
    /// The very first launch, as opposed to "Show Welcome Guide…" for someone who already uses Codometer.
    public let isFirstRun: Bool

    public init(isFirstRun: Bool = true) {
        self.isFirstRun = isFirstRun
    }

    /// Onboarding is over; the app saves `completedVersion` for both outcomes.
    public var isComplete: Bool { outcome != nil }

    /// The primary button leads to the next step, except on the last one, where it finishes.
    public var isLastStep: Bool { step == .done }

    /// Whether a "Back" button is offered (the wizard counts its own stages as steps back).
    public var canGoBack: Bool { step != .welcome || wizard.stage != .intro }

    public mutating func next() {
        guard let next = step.next else {
            finish()
            return
        }
        step = next
    }

    /// The second-account step's footer button: one wizard stage on, or `false` to leave the step.
    public mutating func advanceWizard(readiness: [ProfileReadiness], home: String) -> Bool {
        guard step == .secondAccount else { return false }
        return wizard.advance(readiness: readiness, home: home)
    }

    /// Whether the primary button does anything at all right now.
    public var canAdvance: Bool {
        step != .secondAccount || wizard.canAdvance
    }

    public mutating func back() {
        if step == .secondAccount, wizard.back() { return }
        guard let previous = step.previous else { return }
        step = previous
    }

    /// Esc: one step back, or Skip while there is nothing to go back to.
    public mutating func escape() {
        guard canGoBack else {
            skip()
            return
        }
        back()
    }

    public mutating func skip() {
        guard outcome == nil else { return }
        outcome = .skipped
    }

    public mutating func finish() {
        guard outcome == nil else { return }
        outcome = .finished
    }

    /// A debug scenario jumps straight to a step.
    public mutating func go(to step: OnboardingStep) {
        self.step = step
    }

    // MARK: Wizard events

    public mutating func startWizard() {
        wizard.start()
    }

    public mutating func chooseService(_ provider: ProviderKind) {
        wizard.chose(provider)
    }

    /// Changes the service without leaving the stage.
    public mutating func setService(_ provider: ProviderKind) {
        wizard.provider = provider
    }

    public mutating func confirmProfileName(readiness: [ProfileReadiness], home: String) {
        wizard.confirmName(readiness: readiness, home: home)
    }

    public mutating func startWaitingForSignIn() {
        wizard.startWaiting()
    }

    public mutating func applyReadiness(_ readiness: [ProfileReadiness], home: String) {
        wizard.apply(readiness: readiness, home: home)
    }

    /// The account was added; the wizard goes back to its offer so another account can follow.
    public mutating func accountAdded() {
        wizard.reset()
    }

    public mutating func setSuffixText(_ text: String) {
        wizard.suffixText = text
    }

    public mutating func setLabel(_ text: String) {
        wizard.label = text
    }

    public mutating func setGroup(_ id: AccountGroupID?) {
        wizard.groupID = id
    }
}
