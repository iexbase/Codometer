import CodometerCore
import CodometerL10n
@testable import CodometerUI
import Foundation
import Testing

/// The second-account wizard: its stages, the folder name it proposes, the commands it shows, and the naming rule it
/// shares with profile discovery (Core's `ProfileSuffix`).
@MainActor
@Suite("Second account wizard")
struct SecondAccountWizardTests {
    private let home = "/Users/tester"

    private func readiness(_ entries: [(ProviderKind, String, ProfileReadiness.State)]) throws -> [ProfileReadiness] {
        try entries.map { provider, name, state in
            ProfileReadiness(
                provider: provider,
                directory: try ProfileDirectory(validating: (home as NSString).appendingPathComponent(name)),
                state: state,
                cli: nil
            )
        }
    }

    @Test("The wizard starts at its offer and walks service → name → commands → waiting")
    func stages() throws {
        var flow = OnboardingFlow()
        flow.go(to: .secondAccount)
        #expect(flow.wizard.stage == .intro)
        flow.startWizard()
        #expect(flow.wizard.stage == .service)
        flow.chooseService(.claude)
        #expect(flow.wizard.stage == .name)
        #expect(flow.wizard.suffixText == SecondAccountWizard.defaultSuffix)
        flow.confirmProfileName(readiness: [], home: home)
        #expect(flow.wizard.stage == .signIn)
        flow.startWaitingForSignIn()
        #expect(flow.wizard.stage == .waiting)
    }

    @Test("A folder that already looks like a profile skips the commands")
    func existingFolderJumpsToWaiting() throws {
        var flow = OnboardingFlow()
        flow.go(to: .secondAccount)
        flow.startWizard()
        flow.chooseService(.claude)
        let found = try readiness([(.claude, ".claude-work", .notSignedIn)])
        flow.confirmProfileName(readiness: found, home: home)
        #expect(flow.wizard.stage == .waiting)
    }

    @Test("A folder that is already signed in goes straight to the last stage")
    func signedInFolderJumpsToDetected() throws {
        var flow = OnboardingFlow()
        flow.go(to: .secondAccount)
        flow.startWizard()
        flow.chooseService(.codex)
        let found = try readiness([(.codex, ".codex-work", .signedIn(plan: nil))])
        flow.confirmProfileName(readiness: found, home: home)
        #expect(flow.wizard.stage == .detected)
    }

    @Test("The watch ends the wait only when that folder is signed in")
    func waitingEndsOnSignIn() throws {
        var flow = OnboardingFlow()
        flow.go(to: .secondAccount)
        flow.startWizard()
        flow.chooseService(.claude)
        flow.confirmProfileName(readiness: [], home: home)
        flow.startWaitingForSignIn()
        flow.applyReadiness(try readiness([(.claude, ".claude-work", .notSignedIn)]), home: home)
        #expect(flow.wizard.stage == .waiting)
        // Another folder signing in is not this one.
        flow.applyReadiness(try readiness([(.claude, ".claude-other", .signedIn(plan: nil))]), home: home)
        #expect(flow.wizard.stage == .waiting)
        flow.applyReadiness(try readiness([(.claude, ".claude-work", .signedIn(plan: "Pro"))]), home: home)
        #expect(flow.wizard.stage == .detected)
    }

    @Test("The step's own footer button walks the wizard, so no stage shows a second Continue")
    func footerAdvances() throws {
        var flow = OnboardingFlow()
        flow.go(to: .secondAccount)
        // At the offer the button leaves the step; the offer's own button starts the wizard.
        var advanced = flow.advanceWizard(readiness: [], home: home)
        #expect(!advanced)
        flow.startWizard()
        advanced = flow.advanceWizard(readiness: [], home: home)
        #expect(advanced)
        #expect(flow.wizard.stage == .name)
        #expect(flow.canAdvance)
        flow.setSuffixText("not a suffix")
        #expect(!flow.canAdvance)
        advanced = flow.advanceWizard(readiness: [], home: home)
        #expect(!advanced)
        #expect(flow.wizard.stage == .name)
        flow.setSuffixText("work")
        advanced = flow.advanceWizard(readiness: [], home: home)
        #expect(advanced)
        #expect(flow.wizard.stage == .signIn)
        advanced = flow.advanceWizard(readiness: [], home: home)
        #expect(advanced)
        #expect(flow.wizard.stage == .waiting)
        // Waiting and the last stage let the flow move on instead.
        advanced = flow.advanceWizard(readiness: [], home: home)
        #expect(!advanced)
        #expect(flow.canAdvance)
    }

    @Test("Outside the second-account step the footer never touches the wizard")
    func footerElsewhere() {
        var flow = OnboardingFlow()
        flow.startWizard()
        let advanced = flow.advanceWizard(readiness: [], home: home)
        #expect(!advanced)
        #expect(flow.canAdvance)
    }

    @Test("Readiness outside the waiting stage never moves the wizard")
    func readinessIgnoredOutsideWaiting() throws {
        var flow = OnboardingFlow()
        flow.go(to: .secondAccount)
        flow.startWizard()
        flow.chooseService(.claude)
        flow.applyReadiness(try readiness([(.claude, ".claude-work", .signedIn(plan: nil))]), home: home)
        #expect(flow.wizard.stage == .name)
    }

    @Test("The suffix is validated by Core's rule and the folder follows from it")
    func suffixValidation() {
        var wizard = SecondAccountWizard()
        for valid in ["work", "Work_2", "a.b", String(repeating: "x", count: ProfileSuffix.maximumLength)] {
            wizard.suffixText = valid
            #expect(wizard.suffix?.value == valid, "\(valid)")
        }
        for invalid in ["", " ", "with space", "слово", "a/b", ".", "..", String(repeating: "x", count: ProfileSuffix.maximumLength + 1)] {
            wizard.suffixText = invalid
            #expect(wizard.suffix == nil, "\(invalid)")
        }
    }

    @Test("Folder paths and display paths come from the suffix rule")
    func folderPaths() {
        var wizard = SecondAccountWizard()
        wizard.provider = .claude
        wizard.suffixText = "work"
        #expect(wizard.folderDisplayPath == "~/.claude-work")
        #expect(wizard.folderPath(home: home) == "/Users/tester/.claude-work")
        wizard.provider = .codex
        #expect(wizard.folderDisplayPath == "~/.codex-work")
        wizard.suffixText = "no spaces allowed"
        #expect(wizard.folderDisplayPath == nil)
        #expect(wizard.folderPath(home: home) == nil)
    }

    @Test("The commands are Core's, never localized, and quote nothing")
    func commands() throws {
        var wizard = SecondAccountWizard()
        wizard.provider = .claude
        wizard.suffixText = "work"
        #expect(wizard.commands == ["CLAUDE_CONFIG_DIR=~/.claude-work claude"])
        wizard.provider = .codex
        #expect(wizard.commands == ["mkdir -p ~/.codex-work && CODEX_HOME=~/.codex-work codex login"])
        wizard.suffixText = ""
        #expect(wizard.commands.isEmpty)
        let suffix = try ProfileSuffix("work")
        #expect(wizard.commands.isEmpty)
        #expect(SecondAccountCommands.signIn(provider: .claude, suffix: suffix).count == 1)
    }

    @Test("Folder names map to suffixes exactly as profile discovery reads them")
    func suffixParity() {
        let cases: [(String, ProviderKind, String?)] = [
            (".claude", .claude, ""),
            (".claude-work", .claude, "work"),
            (".claude-Work_2", .claude, "Work_2"),
            (".claude-", .claude, nil),
            (".claude-with space", .claude, nil),
            (".claude-.", .claude, nil),
            (".claudex", .claude, nil),
            (".codex", .codex, ""),
            (".codex-work", .codex, "work"),
            (".claude", .codex, nil),
        ]
        for (name, provider, expected) in cases {
            #expect(OnboardingAccounts.suffix(ofFolder: name, provider: provider) == expected, "\(name)")
        }
    }

    @Test("A profile folder's label matches what first-launch discovery would have written")
    func suggestedLabels() throws {
        #expect(OnboardingAccounts.label(provider: .claude, suffix: "") == "Claude")
        #expect(OnboardingAccounts.label(provider: .claude, suffix: "work") == "Claude · work")
        #expect(OnboardingAccounts.label(provider: .codex, suffix: "work") == "Codex · work")
        let directory = try ProfileDirectory(validating: home + "/.codex-work")
        #expect(OnboardingAccounts.suggestedLabel(provider: .codex, directory: directory) == "Codex · work")
    }

    @Test("Adding the account uses the typed name, or the suggestion when it is blank, and returns to the offer")
    func addAccount() throws {
        let store = OnboardingFixture.store()
        let model = OnboardingModel(store: store, homePath: home)
        model.startWizard()
        model.chooseService(.claude)
        model.setSuffixText("work")
        model.confirmProfileName()
        model.startWaitingForSignIn()
        model.setWizardLabel("   ")
        model.addWizardAccount(l10n: .testEnglish)
        #expect(store.settings.accounts.count == 1)
        #expect(store.settings.accounts.first?.label.value == "Claude · work")
        #expect(store.settings.accounts.first?.directory.path == "/Users/tester/.claude-work")
        #expect(model.wizard.stage == .intro)
        #expect(model.wizard.suffixText == SecondAccountWizard.defaultSuffix)
        #expect(model.issue == nil)
    }

    @Test("Choosing a service fills the suggested name, and typing a suffix keeps it in step")
    func labelFollowsSuffix() {
        let model = OnboardingModel(store: OnboardingFixture.store(), homePath: home)
        model.startWizard()
        model.chooseService(.codex)
        #expect(model.wizard.label == "Codex · work")
        model.setSuffixText("night")
        #expect(model.wizard.label == "Codex · night")
    }
}
