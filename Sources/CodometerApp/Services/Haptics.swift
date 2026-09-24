import CodometerCore
import AppKit

/// Plays snapping feedback. The island and the floating card talk to this protocol, so tests use a recorder.
@MainActor
protocol HapticPerforming {
    func perform(_ haptic: SnapHaptic)
}

/// Force Touch trackpad feedback for snapping. Needs no permission; mice and the Magic Mouse simply feel nothing.
@MainActor
struct TrackpadHaptics: HapticPerforming {
    /// Read at call time (e.g. `{ store.settings.appearance.playsHaptics }`), so a settings change applies at once.
    let isEnabled: @MainActor () -> Bool

    func perform(_ haptic: SnapHaptic) {
        guard isEnabled() else { return }
        let pattern: NSHapticFeedbackManager.FeedbackPattern = haptic == .lock ? .alignment : .levelChange
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}
