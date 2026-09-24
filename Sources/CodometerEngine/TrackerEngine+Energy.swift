import CodometerCore
import Foundation

/// Energy-aware scheduling: the app passes every new `EnergyDecision`; monitors stretch their schedules by its factor.
extension TrackerEngine {
    /// Stores the decision (new monitors start with its factor, Diagnostics reports it) and forwards the factor to
    /// every running monitor. Manual refreshes are never delayed, and a factor that went down may bring an armed
    /// refresh forward (`RefreshTimerPlan.rearm`).
    ///
    /// - Parameter power: the conditions the decision came from, shown in Diagnostics. Left out, the last known
    ///   conditions stay.
    public func setEnergy(_ decision: EnergyDecision, power: PowerSnapshot? = nil) async {
        if let power {
            diagnosticsState.power = power
        }
        guard decision != energyDecision else { return }
        energyDecision = decision
        for monitor in monitors.values {
            await monitor.setEnergyFactor(decision.factor)
        }
    }
}
