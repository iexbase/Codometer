#if DEBUG
import CodometerCore
import CodometerUI
import Foundation

/// Energy and reliability steps.
extension DebugScenario {
    /// Handles `power` (overrides the power snapshot).
    ///
    /// `{"power": {"lowPower": true, "battery": 15, "thermal": "serious", "onBattery": true}}` installs conditions
    /// the policy decides on; every key is optional. `{"power": null}` follows the real monitor again. A battery
    /// percentage implies `onBattery` unless the step says otherwise.
    static func handleReliabilityStep(_ key: String, _ value: Any, _ context: DebugContext) async throws -> Bool {
        guard key == "power" else { return false }
        func fail(_ reason: String) -> DebugScenarioError {
            DebugScenarioError(description: "\(key): \(reason)")
        }
        let controller = context.controller
        if DebugValue.isNull(value) {
            controller.energyCoordinator.override = nil
            controller.applyEnergy()
            return true
        }
        guard let fields = DebugValue.object(value),
              Set(fields.keys).isSubset(of: ["lowPower", "battery", "thermal", "onBattery"]) else {
            throw fail("expected {lowPower, battery, thermal, onBattery} or null")
        }
        let lowPower = fields["lowPower"].flatMap(DebugValue.bool) ?? false
        var percentage: Percentage?
        if let raw = fields["battery"] {
            guard let number = DebugValue.number(raw), let value = try? Percentage(validating: number) else {
                throw fail("battery must be a percentage in 0…100")
            }
            percentage = value
        }
        var thermal = ThermalLevel.nominal
        if let raw = fields["thermal"] {
            guard let name = DebugValue.string(raw), let level = ThermalLevel(rawValue: name) else {
                throw fail("thermal must be nominal, fair, serious or critical")
            }
            thermal = level
        }
        let onBattery = fields["onBattery"].flatMap(DebugValue.bool) ?? (percentage != nil)
        controller.energyCoordinator.override = PowerSnapshot(
            lowPowerMode: lowPower,
            onBattery: onBattery,
            batteryPercent: percentage,
            thermal: thermal
        )
        controller.applyEnergy()
        return true
    }

    /// Fields this domain adds to `capture` and `trace` lines.
    static func reliabilityTraceFields(_ context: DebugContext) -> [String: Any] {
        let energy = context.store.energy
        return [
            "energyFactor": energy.factor.value,
            "energyReason": energy.reason.rawValue,
            "liveEffects": context.store.allowsLiveEffects,
        ]
    }
}
#endif
