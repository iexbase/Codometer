import CodometerCore
import Foundation
import Testing

@Suite("Onboarding state")
struct OnboardingStateTests {
    private func general(_ json: String) throws -> GeneralSettings {
        try JSONDecoder().decode(GeneralSettings.self, from: Data(json.utf8))
    }

    @Test("A missing key means completed: existing users never see onboarding")
    func missingIsCompleted() throws {
        #expect(try general("{}").onboarding == .completed)
        #expect(GeneralSettings().onboarding == .completed)
        #expect(!OnboardingState.completed.needsOnboarding)
    }

    @Test("Version 0 needs onboarding; the current or a higher version counts as completed", arguments: [
        (0, true), (1, false), (2, false), (99, false),
    ])
    func versions(version: Int, needs: Bool) throws {
        let state = try general(#"{"onboarding": {"completedVersion": \#(version)}}"#).onboarding
        #expect(state.completedVersion == version)
        #expect(state.needsOnboarding == needs)
    }

    @Test("Fresh installs start at notStarted; invalid values fall back to completed")
    func freshAndInvalid() throws {
        #expect(OnboardingState.notStarted.completedVersion == 0)
        #expect(OnboardingState.notStarted.needsOnboarding)
        #expect(OnboardingState.currentVersion == 1)
        #expect(throws: ValidationError.self) { try OnboardingState(completedVersion: -1) }
        for json in [#"{"onboarding": {"completedVersion": -1}}"#, #"{"onboarding": {}}"#, #"{"onboarding": 1}"#, #"{"onboarding": null}"#] {
            #expect(try general(json).onboarding == .completed)
        }
        let encoded = try JSONEncoder().encode(OnboardingState.notStarted)
        #expect(String(decoding: encoded, as: UTF8.self) == #"{"completedVersion":0}"#)
    }
}
