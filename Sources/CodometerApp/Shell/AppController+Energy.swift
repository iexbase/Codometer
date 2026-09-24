import CodometerCore
import CodometerEngine
import CodometerPlatform
import CodometerUI
import Foundation

/// State of energy-aware polling: the power monitor and the task following it.
@MainActor
final class EnergyCoordinator {
    /// Notification-driven; nothing here polls.
    let monitor = PowerStateMonitor()
    var task: Task<Void, Never>?
    /// The latest conditions the monitor reported.
    var snapshot: PowerSnapshot = .nominalAC
    #if DEBUG
    /// Conditions a debug scenario's `power` step installed; they replace the monitor's until it is cleared.
    var override: PowerSnapshot?
    #endif

    init() {}

    /// What the policy decides on: the scenario's conditions when one is installed, otherwise the real ones.
    var effectiveSnapshot: PowerSnapshot {
        #if DEBUG
        return override ?? snapshot
        #else
        return snapshot
        #endif
    }
}

/// Energy-aware polling: power conditions → `EnergyDecision` → engine schedules and live effects.
extension AppController {
    /// Starts following power conditions and applies the first decision.
    ///
    /// Low Power Mode, thermal pressure and the power source arrive as notifications, so nothing runs while they
    /// stay the same; the energy mode is followed with observation, not a timer.
    func startEnergyMonitoring() {
        let coordinator = energyCoordinator
        coordinator.monitor.start()
        observeEnergyMode()
        coordinator.task = Task { [weak self] in
            for await snapshot in coordinator.monitor.snapshots() {
                guard let self else { return }
                coordinator.snapshot = snapshot
                applyEnergy()
            }
        }
    }

    /// Recomputes the decision from the latest conditions and the user's energy mode, then hands it to the engine
    /// (schedules) and the store (live effects).
    func applyEnergy() {
        let snapshot = energyCoordinator.effectiveSnapshot
        let decision = EnergyPolicy.decide(snapshot, mode: store.settings.general.energyMode)
        store.setEnergy(decision)
        let engine = engine
        Task {
            await engine.setEnergy(decision, power: snapshot)
        }
    }

    /// Re-decides when the user picks another energy mode. Observation fires on a settings change and re-registers,
    /// so nothing runs while the settings stand still; a change that leaves the decision alone is dropped by
    /// `store.setEnergy` and `engine.setEnergy`.
    private func observeEnergyMode() {
        withObservationTracking {
            _ = store.settings.general.energyMode
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.observeEnergyMode()
                self.applyEnergy()
            }
        }
    }
}
