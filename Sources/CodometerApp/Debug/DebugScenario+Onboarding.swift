#if DEBUG
import CodometerUI
import Foundation

/// Onboarding and data control steps.
extension DebugScenario {
    /// Handles `onboarding`, `finishOnboarding`, `eraseSheet`, `exportSheet` and `relaunch`.
    static func handleOnboardingStep(_ key: String, _ value: Any, _ context: DebugContext) async throws -> Bool {
        switch key {
        case DebugStepKeys.onboarding:
            try showOnboarding(value, context)
        case "finishOnboarding":
            guard DebugValue.bool(value) == true else {
                throw DebugScenarioError(description: "finishOnboarding: expected true")
            }
            context.controller.finishOnboarding(startTracking: true)
        case "eraseSheet":
            guard DebugValue.bool(value) == true else {
                throw DebugScenarioError(description: "eraseSheet: expected true")
            }
            context.controller.settingsWindow.show(pane: .general)
            DataControls.shared.showsEraseSheet = true
        case "exportSheet":
            guard DebugValue.bool(value) == true else {
                throw DebugScenarioError(description: "exportSheet: expected true")
            }
            context.controller.settingsWindow.show(pane: .general)
            context.controller.exportHistory()
        case "relaunch":
            guard DebugValue.bool(value) == true else {
                throw DebugScenarioError(description: "relaunch: expected true")
            }
            context.controller.relaunch()
        default:
            return false
        }
        return true
    }

    /// `{"onboarding": {"step": 3, "fixture": true}}`: opens the welcome flow (if it is not open) and shows one step.
    ///
    /// `fixture` replaces the profile readiness with synthetic folders, so a capture never shows a real profile or a
    /// real plan name.
    private static func showOnboarding(_ value: Any, _ context: DebugContext) throws {
        guard let object = DebugValue.object(value) else {
            throw DebugScenarioError(description: "onboarding: expected an object")
        }
        if let unknown = object.keys.first(where: { $0 != "step" && $0 != "fixture" }) {
            throw DebugScenarioError(description: "onboarding: unknown key \(unknown)")
        }
        let controller = context.controller
        if controller.onboardingModel == nil {
            controller.showOnboarding()
        }
        guard let model = controller.onboardingModel else {
            throw DebugScenarioError(description: "onboarding: the welcome window did not open")
        }
        if let fixture = object["fixture"], DebugValue.bool(fixture) == true {
            model.installFixtureReadiness()
        }
        if let raw = object["step"] {
            guard
                let number = DebugValue.number(raw),
                let step = OnboardingStep(rawValue: Int(number) - 1)
            else {
                throw DebugScenarioError(description: "onboarding: step must be 1…\(OnboardingStep.total)")
            }
            model.go(to: step)
        }
    }

    /// Fields this domain adds to `capture` and `trace` lines.
    static func onboardingTraceFields(_ context: DebugContext) -> [String: Any] {
        var fields: [String: Any] = [:]
        if let model = context.controller.onboardingModel {
            fields["onboardingStep"] = model.step.number
            fields["onboardingWizard"] = String(describing: model.wizard.stage)
        }
        switch DataControls.shared.export {
        case .idle: break
        case .running: fields["exportPhase"] = "running"
        case .finished(let rows, _): fields["exportPhase"] = "finished"; fields["exportRows"] = rows
        case .failed: fields["exportPhase"] = "failed"
        }
        if DataControls.shared.showsEraseSheet {
            fields["eraseSheet"] = true
        }
        return fields
    }
}
#endif
