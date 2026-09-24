@testable import CodometerApp
import CodometerCore
import Foundation
import Testing

/// Where a launch goes: through the welcome flow, or straight into tracking.
///
/// Missing or recovered settings are written with `OnboardingState.notStarted`, so they route to onboarding; loaded
/// and read-only settings keep whatever they carry, and settings written before the key existed decode as completed.
@Suite("First-run routing")
struct FirstRunRouteTests {
    @Test("Settings that never finished onboarding open the welcome flow")
    func freshInstall() {
        #expect(FirstRunRoute.route(onboarding: .notStarted, debugScenarioStepKeys: nil) == .onboarding)
    }

    @Test("An existing install goes straight to the engine")
    func existingInstall() throws {
        #expect(FirstRunRoute.route(onboarding: .completed, debugScenarioStepKeys: nil) == .engine)
        // A version written by a newer build counts as completed.
        let newer = try OnboardingState(completedVersion: OnboardingState.currentVersion + 1)
        #expect(FirstRunRoute.route(onboarding: newer, debugScenarioStepKeys: nil) == .engine)
    }

    @Test("Settings from before the key existed decode as completed, so nobody is asked again")
    func missingKeyDecodesCompleted() throws {
        let json = Data(#"{"schemaVersion":1,"general":{}}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        #expect(!settings.general.onboarding.needsOnboarding)
        #expect(FirstRunRoute.route(onboarding: settings.general.onboarding, debugScenarioStepKeys: nil) == .engine)
    }

    @Test("A debug scenario without an onboarding step never opens the flow")
    func debugScenarioSkips() {
        #expect(FirstRunRoute.route(onboarding: .notStarted, debugScenarioStepKeys: []) == .engine)
        #expect(FirstRunRoute.route(onboarding: .notStarted, debugScenarioStepKeys: ["fixture", "capture"]) == .engine)
    }

    @Test("A debug scenario that asks for an onboarding step gets the flow")
    func debugScenarioWithOnboarding() {
        #expect(FirstRunRoute.route(onboarding: .notStarted, debugScenarioStepKeys: ["fixture", "onboarding"]) == .onboarding)
        // It still respects completed settings: the step opens the guide itself.
        #expect(FirstRunRoute.route(onboarding: .completed, debugScenarioStepKeys: ["onboarding"]) == .engine)
    }

    @Test("A launch headed for the welcome flow keeps settings out of the engine until the flow hands it over")
    func engineHandover() {
        // Before the flow ends: the launch bookkeeping and every step's save stay out of the engine, so no monitor
        // and no CLI probe starts.
        #expect(FirstRunRoute.defersEngineUpdates(hasStartedEngine: false, route: .onboarding))
        // After the hand-over, and on every launch that never wanted the flow, edits reach the engine as usual.
        #expect(!FirstRunRoute.defersEngineUpdates(hasStartedEngine: true, route: .onboarding))
        #expect(!FirstRunRoute.defersEngineUpdates(hasStartedEngine: false, route: .engine))
        #expect(!FirstRunRoute.defersEngineUpdates(hasStartedEngine: true, route: .engine))
    }

    @Test("Fresh settings are written as “not started”, so a first launch and a start over both route to the flow")
    func initialSettingsNeedOnboarding() {
        #expect(GeneralSettings(onboarding: .notStarted).onboarding.needsOnboarding)
        #expect(OnboardingState.notStarted.completedVersion == 0)
        #expect(!OnboardingState.completed.needsOnboarding)
    }
}
