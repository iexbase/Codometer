import CodometerCore
import CodometerEngine
import CodometerPlatform
import CodometerUI
import Foundation
import os

/// State of first-run onboarding: its window and the flow.
@MainActor
final class OnboardingCoordinator {
    var windowController: OnboardingWindowController?
    /// Set when the welcome flow hands the engine over, so later settings edits reach it again.
    var hasStartedEngine = false

    init() {}
}

/// Where a fresh launch goes: through the welcome flow, or straight into tracking.
///
/// Pure, so the rule is testable without a window: settings that never finished onboarding get the flow, and a
/// DEBUG scenario skips it unless the scenario itself asks for an `onboarding` step.
enum FirstRunRoute: Equatable {
    case onboarding
    case engine

    /// Whether settings edits stay out of the engine: a launch that is headed for the welcome flow keeps the engine
    /// stopped until the flow hands it over, because `TrackerEngine.apply(settings:)` starts a monitor — and so a CLI
    /// probe — for every enabled account.
    static func defersEngineUpdates(hasStartedEngine: Bool, route: FirstRunRoute) -> Bool {
        !hasStartedEngine && route == .onboarding
    }

    static func route(onboarding state: OnboardingState, debugScenarioStepKeys: Set<String>?) -> FirstRunRoute {
        if let keys = debugScenarioStepKeys, !keys.contains(DebugStepKeys.onboarding) {
            return .engine
        }
        return state.needsOnboarding ? .onboarding : .engine
    }
}

/// Step keys the routing rule needs to know about, named here so the rule stays testable in release builds too.
enum DebugStepKeys {
    static let onboarding = "onboarding"
}

/// First-run onboarding.
extension AppController {
    /// Shows onboarding instead of starting the engine when these settings need it; returns whether it did.
    ///
    /// No CLI probe runs before the user finishes or skips the flow, so the engine stays stopped until then.
    func routeFirstRun(settings: AppSettings) -> Bool {
        let route = FirstRunRoute.route(onboarding: settings.general.onboarding, debugScenarioStepKeys: debugScenarioStepKeys)
        guard route == .onboarding else { return false }
        presentOnboarding(isFirstRun: true)
        return true
    }

    /// Opens the welcome guide again (from General → "Show Welcome Guide…"). The engine keeps running.
    func showOnboarding() {
        presentOnboarding(isFirstRun: false)
    }

    /// Closes onboarding, records it as completed and, with `startTracking`, starts the engine.
    ///
    /// Both finishing and skipping complete it: nobody is asked twice. The engine is started before the settings
    /// are saved, and `hasStartedEngine` is set last, so the write that completes onboarding does not race
    /// `engine.start` with an `apply` of its own.
    func finishOnboarding(startTracking: Bool) {
        let controller = onboarding.windowController
        onboarding.windowController = nil
        controller?.close()
        if startTracking {
            startEngine(settings: store.settings)
            AppLog.interface.notice("onboarding finished: engine started")
        }
        store.updateSettings { $0.general.onboarding = .completed }
        onboarding.hasStartedEngine = true
    }

    /// Whether settings edits stay out of the engine for now.
    ///
    /// A first run reaches `persist` before the welcome flow is even on screen (the launch bookkeeping saves the
    /// version), and `TrackerEngine.apply(settings:)` starts a monitor — and so a CLI probe — for every enabled
    /// account. None of that may happen before the user finishes or skips the flow, so every write is
    /// saved to disk and applied in memory, and the engine gets the finished settings from `startEngine`.
    var defersEngineUpdates: Bool {
        FirstRunRoute.defersEngineUpdates(
            hasStartedEngine: onboarding.hasStartedEngine,
            route: FirstRunRoute.route(
                onboarding: store.settings.general.onboarding,
                debugScenarioStepKeys: debugScenarioStepKeys
            )
        )
    }

    /// Readiness of the profile folders, and — after the first read — the provider CLIs' signatures.
    ///
    /// The readiness itself is filesystem metadata and answers in a millisecond. Looking a CLI binary's signature
    /// up reads the whole file and takes a second or two the first time, so it happens after the answer instead of
    /// before it: the wizard's list appears at once, and the signature is there for the next read ("Check Again"
    /// or the second-account step's two-second watch). Nothing is spawned either way, as onboarding requires.
    func inspectProfiles() async -> [ProfileReadiness] {
        let readiness = await engine.inspectProfiles()
        Task { [engine] in await engine.warmExecutableSignatures() }
        return readiness
    }

    func requestNotificationPermission() async -> Bool {
        await alerts.requestAuthorization()
    }

    /// The model a debug scenario drives (`onboarding`, `finishOnboarding` steps).
    var onboardingModel: OnboardingModel? {
        onboarding.windowController?.model
    }

    private func presentOnboarding(isFirstRun: Bool) {
        if let existing = onboarding.windowController {
            existing.show()
            return
        }
        let controller = OnboardingWindowController(store: store, isFirstRun: isFirstRun) { [weak self] _ in
            // A first run starts tracking once the flow is over; a reopened guide changes nothing.
            self?.finishOnboarding(startTracking: isFirstRun)
        }
        onboarding.windowController = controller
        controller.show()
        AppLog.interface.notice("welcome flow opened")
    }

    /// The step keys of the debug scenario this process was started with, or `nil` in a release build or without one.
    fileprivate var debugScenarioStepKeys: Set<String>? {
        #if DEBUG
        guard ProcessInfo.processInfo.environment[DebugScenario.scenarioVariable] != nil else { return nil }
        return DebugScenario.requestedStepKeys()
        #else
        return nil
        #endif
    }
}
