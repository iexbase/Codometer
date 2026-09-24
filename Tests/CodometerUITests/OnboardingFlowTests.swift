import CodometerCore
import CodometerL10n
@testable import CodometerUI
import AppKit
import Foundation
import Testing

/// The welcome flow's reducer: stepping forward and back, Escape, skipping, finishing, and the language picker.
@MainActor
@Suite("Onboarding flow")
struct OnboardingFlowTests {
    @Test("Six steps, in order, each numbered for the indicator")
    func steps() {
        #expect(OnboardingStep.total == 6)
        #expect(OnboardingStep.allCases.map(\.number) == [1, 2, 3, 4, 5, 6])
        #expect(OnboardingStep.welcome.previous == nil)
        #expect(OnboardingStep.done.next == nil)
    }

    @Test("Next walks to the last step and then finishes")
    func next() {
        var flow = OnboardingFlow()
        #expect(flow.step == .welcome)
        for expected in [OnboardingStep.found, .presentation, .secondAccount, .notifications, .done] {
            flow.next()
            #expect(flow.step == expected)
            #expect(flow.outcome == nil)
        }
        #expect(flow.isLastStep)
        flow.next()
        #expect(flow.outcome == .finished)
        #expect(flow.isComplete)
    }

    @Test("Back walks to the first step and stops there")
    func back() {
        var flow = OnboardingFlow()
        flow.go(to: .notifications)
        for expected in [OnboardingStep.secondAccount, .presentation, .found, .welcome] {
            flow.back()
            #expect(flow.step == expected)
        }
        flow.back()
        #expect(flow.step == .welcome)
        #expect(flow.outcome == nil)
    }

    @Test("Escape goes back, and skips on the first step")
    func escape() {
        var flow = OnboardingFlow()
        flow.go(to: .found)
        #expect(flow.canGoBack)
        flow.escape()
        #expect(flow.step == .welcome)
        #expect(flow.outcome == nil)
        #expect(!flow.canGoBack)
        flow.escape()
        #expect(flow.outcome == .skipped)
    }

    @Test("Back inside the wizard steps its stages before leaving the step")
    func backThroughWizard() {
        var flow = OnboardingFlow()
        flow.go(to: .secondAccount)
        flow.startWizard()
        flow.chooseService(.codex)
        #expect(flow.wizard.stage == .name)
        flow.back()
        #expect(flow.wizard.stage == .service)
        #expect(flow.step == .secondAccount)
        flow.back()
        #expect(flow.wizard.stage == .intro)
        #expect(flow.step == .secondAccount)
        flow.back()
        #expect(flow.step == .presentation)
    }

    @Test("An outcome is reported once: skipping after finishing changes nothing")
    func outcomeIsFinal() {
        var flow = OnboardingFlow()
        flow.finish()
        #expect(flow.outcome == .finished)
        flow.skip()
        #expect(flow.outcome == .finished)

        var skipped = OnboardingFlow()
        skipped.skip()
        skipped.finish()
        #expect(skipped.outcome == .skipped)
    }

    @Test("Closing the window counts as skipped, and both outcomes complete onboarding")
    func closeCompletes() {
        var flow = OnboardingFlow()
        #expect(!flow.isComplete)
        flow.skip()
        #expect(flow.isComplete)
        #expect(flow.outcome == .skipped)
    }

    @Test("A model reports its outcome exactly once")
    func modelReportsOnce() {
        let model = OnboardingModel(store: OnboardingFixture.store(), homePath: "/Users/tester")
        var outcomes: [OnboardingFlow.Outcome] = []
        model.onComplete = { outcomes.append($0) }
        model.go(to: .done)
        model.next()
        model.skip()
        #expect(outcomes == [.finished])
    }

    @Test("The language picker changes general.language and the store's localizer at once")
    func languagePicker() {
        let store = OnboardingFixture.store()
        #expect(store.settings.general.language == .english)
        #expect(store.localizer.language == .en)
        WelcomeStep.setLanguage(.russian, in: store)
        #expect(store.settings.general.language == .russian)
        #expect(store.localizer.language == .ru)
        WelcomeStep.setLanguage(.english, in: store)
        #expect(store.localizer.language == .en)
    }

    @Test("Language choices are named in their own language, whatever the interface language")
    func languageNames() {
        for l10n in [Localizer.testEnglish, .testRussian] {
            #expect(WelcomeStep.name(.english, l10n: l10n) == "English")
            #expect(WelcomeStep.name(.russian, l10n: l10n) == "Русский")
        }
        #expect(WelcomeStep.name(.system, l10n: .testEnglish) == "System Language")
        #expect(WelcomeStep.name(.system, l10n: .testRussian) == "Язык системы")
    }

    @Test("Readiness words never repeat and never depend on colour", arguments: [Localizer.testEnglish, .testRussian])
    func readinessWords(l10n: Localizer) {
        let states: [ProfileReadiness.State?] = [
            .signedIn(plan: nil), .signedIn(plan: "Pro 20x"), .notSignedIn, .missingFolder, .notAProfile, .symlinkRefused, nil,
        ]
        let words = states.map { FoundProfilesCopy.readiness($0, provider: .claude, l10n: l10n) }
        #expect(words.allSatisfy { !$0.isEmpty })
        #expect(Set(words).count == words.count, "\(words)")
    }

    @Test("Synthetic readiness carries no real profile and covers the three states that matter")
    func fixtureReadiness() {
        let readiness = OnboardingModel.fixtureReadiness(home: "/Users/tester")
        #expect(readiness.count == 3)
        #expect(readiness.allSatisfy { $0.directory.path.hasPrefix("/Users/tester/.") })
        #expect(readiness.contains { if case .signedIn = $0.state { return true } else { return false } })
        #expect(readiness.contains { $0.state == .notSignedIn })
    }

    @Test("The last step says notifications were never asked for, instead of calling them off in System Settings", arguments: [Localizer.testEnglish, .testRussian])
    func notificationSummary(l10n: Localizer) {
        let asked = DoneStep.notifications(.authorized, l10n: l10n)
        let denied = DoneStep.notifications(.denied, l10n: l10n)
        let notAsked = DoneStep.notifications(.notDetermined, l10n: l10n)
        #expect(asked.1 == l10n.onboarding.notificationsOn)
        #expect(denied.1 == l10n.onboarding.notificationsOff)
        #expect(notAsked.1 == l10n.onboarding.notificationsNotAsked)
        // Three different states, three different words and three different symbols.
        #expect(Set([asked.1, denied.1, notAsked.1]).count == 3)
        #expect(Set([asked.0, denied.0, notAsked.0]).count == 3)
        #expect(DoneStep.notifications(.provisional, l10n: l10n).1 == l10n.onboarding.notificationsOn)
    }

    @Test("The profile-name rule and the rejection are different sentences, so neither screen says the same thing twice", arguments: [Localizer.testEnglish, .testRussian])
    func profileNameCopy(l10n: Localizer) {
        #expect(l10n.onboarding.profileNameRule != l10n.onboarding.profileNameInvalid)
        #expect(!l10n.onboarding.profileNameInvalid.isEmpty)
        // The offer's note is a statement about the step, not a second button next to "Set Up a Second Account".
        #expect(l10n.onboarding.secondAccountOptional != l10n.onboarding.secondAccountStart)
        #expect(l10n.onboarding.secondAccountOptional.hasSuffix("."))
    }

    @Test("Found rows list the accounts in settings first, then folders that are not tracked yet")
    func foundRows() throws {
        let home = "/Users/tester"
        let store = try OnboardingFixture.storeWithAccount(home: home)
        let model = OnboardingModel(store: store, homePath: home)
        model.installFixtureReadiness()
        let rows = model.foundProfiles
        #expect(rows.first?.accountID != nil)
        #expect(rows.first?.label == "Claude")
        // The fixture's third folder is a Codex profile that is not an account yet.
        #expect(rows.contains { $0.accountID == nil && $0.provider == .codex })
        // A missing folder is never offered.
        #expect(rows.allSatisfy { $0.state != .missingFolder })
    }
}

/// Copy the flow shows, measured in the fonts the views use, in both languages.
@MainActor
@Suite("Onboarding copy fit")
struct OnboardingCopyFitTests {
    nonisolated static let languages = [Localizer.testEnglish, .testRussian]
    private let callout = NSFont.preferredFont(forTextStyle: .callout)
    private let caption = NSFont.preferredFont(forTextStyle: .caption1)

    private func width(_ text: String, _ font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
    }

    @Test("The primary button template is at least as wide as every label it stands in for", arguments: languages)
    func primaryButtonTemplate(l10n: Localizer) {
        let template = width(l10n.onboarding.primaryButtonTemplate, callout)
        for label in [l10n.onboarding.start, l10n.onboarding.continueAction] {
            #expect(width(label, callout) <= template, "\(label) in \(l10n.language)")
        }
    }

    @Test("The shortcut row shows General's own status words, so the flow invents no second wording", arguments: languages)
    func shortcutStatus(l10n: Localizer) {
        // A status left over from another combination reads as the chosen one, exactly as in Settings.
        let reported = ShortcutStatus.unavailable(.controlOptionCommandU, reason: .usedByAnotherApp, alternatives: [.controlOptionCommandL])
        #expect(GeneralPane.status(reported, for: .controlOptionCommandU) == reported)
        #expect(GeneralPane.status(reported, for: .controlOptionCommandL) == .active(.controlOptionCommandL))
        #expect(GeneralPane.status(.off, for: .off) == .off)
        // The conflict text names the keys and says what to do.
        let keys = ShortcutKeys.title(.controlOptionCommandU, l10n: l10n)
        #expect(l10n.shortcut.unavailableApp(keys: keys).contains(keys))
        #expect(!l10n.shortcut.tryInstead.isEmpty)
    }

    @Test("The step indicator stays inside the room the chrome leaves it", arguments: languages)
    func stepIndicator(l10n: Localizer) {
        for index in 1...OnboardingStep.total {
            let text = l10n.onboarding.step(index, of: OnboardingStep.total)
            // 680 pt window − 2 × 32 pt padding − the six dots and their spacing (about 100 pt).
            #expect(width(text, caption) <= 200, "\(text): \(width(text, caption)) pt")
        }
    }

    @Test("A readiness word fits the column the row leaves it", arguments: languages)
    func readinessColumn(l10n: Localizer) {
        let texts = [
            l10n.onboarding.signedIn,
            l10n.onboarding.signedInPlan("Pro 20x"),
            l10n.onboarding.notSignedIn,
            l10n.onboarding.notInstalled("Claude Code"),
            l10n.onboarding.notAProfile,
        ]
        // Row width 616 pt − glyph 30 − label column 250 − switch 60 − paddings 40.
        for text in texts {
            #expect(width(text, caption) <= 236, "\(text): \(width(text, caption)) pt")
        }
    }
}

/// A store with no accounts and no actions, for the pure flow tests.
@MainActor
enum OnboardingFixture {
    static let now = Date(timeIntervalSince1970: 1_789_590_000)

    static func store(language: LanguagePreference = .english) -> TrackerStore {
        var settings = AppSettings.empty
        settings.general.language = language
        return TrackerStore(
            state: .empty,
            settings: settings,
            now: now,
            actions: UIFixture.actions(),
            preferredLanguages: { ["en-US"] },
            region: { Locale(identifier: "en_US") }
        )
    }

    static func storeWithAccount(home: String) throws -> TrackerStore {
        let claude = try AccountProfile(
            provider: .claude,
            label: try AccountLabel(validating: "Claude"),
            directory: try ProfileDirectory(validating: home + "/.claude")
        )
        let settings = try AppSettings(accounts: [claude])
        return TrackerStore(
            state: .empty,
            settings: settings,
            now: now,
            actions: UIFixture.actions(),
            preferredLanguages: { ["en-US"] },
            region: { Locale(identifier: "en_US") }
        )
    }
}
