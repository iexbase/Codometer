import CodometerCore
import Foundation
import Testing

@Suite("Energy policy")
struct EnergyPolicyTests {
    private func snapshot(
        lowPower: Bool = false,
        battery: Bool = false,
        percent: Double? = nil,
        thermal: ThermalLevel = .nominal,
        warning: Bool = false
    ) -> PowerSnapshot {
        PowerSnapshot(
            lowPowerMode: lowPower,
            onBattery: battery,
            batteryPercent: percent.flatMap { try? Percentage(validating: $0) },
            thermal: thermal,
            lowBatteryWarning: warning
        )
    }

    private func expect(
        _ decision: EnergyDecision,
        _ factor: Double,
        _ cap: Double,
        _ reason: EnergyDecision.Reason,
        paused: Bool,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(decision.factor.value == factor, sourceLocation: sourceLocation)
        #expect(decision.urgentCapFactor.value == cap, sourceLocation: sourceLocation)
        #expect(decision.reason == reason, sourceLocation: sourceLocation)
        #expect(decision.pausesLiveEffects == paused, sourceLocation: sourceLocation)
    }

    @Test("Automatic: the table row by row")
    func automaticTable() {
        expect(EnergyPolicy.decide(.nominalAC, mode: .automatic), 1, 1, .normal, paused: false)
        #expect(EnergyPolicy.decide(.nominalAC, mode: .automatic) == .normal)
        expect(EnergyPolicy.decide(snapshot(thermal: .fair), mode: .automatic), 1, 1, .normal, paused: false)
        expect(EnergyPolicy.decide(snapshot(battery: true, percent: 80), mode: .automatic), 1.5, 1, .battery, paused: false)
        expect(EnergyPolicy.decide(snapshot(battery: true, percent: 20), mode: .automatic), 2, 1.5, .lowBattery, paused: false)
        expect(EnergyPolicy.decide(snapshot(battery: true, percent: 35, warning: true), mode: .automatic), 2, 1.5, .lowBattery, paused: false)
        expect(EnergyPolicy.decide(snapshot(lowPower: true), mode: .automatic), 3, 2, .lowPowerMode, paused: true)
        expect(EnergyPolicy.decide(snapshot(thermal: .serious), mode: .automatic), 2, 1.5, .thermal, paused: true)
        expect(EnergyPolicy.decide(snapshot(thermal: .critical), mode: .automatic), 4, 2, .thermal, paused: true)
    }

    @Test("Conditions combine by maximum, never by product")
    func maxCombination() {
        expect(EnergyPolicy.decide(snapshot(lowPower: true, battery: true, percent: 10, thermal: .serious), mode: .automatic), 3, 2, .lowPowerMode, paused: true)
        expect(EnergyPolicy.decide(snapshot(lowPower: true, battery: true, thermal: .critical), mode: .automatic), 4, 2, .thermal, paused: true)
        expect(EnergyPolicy.decide(snapshot(battery: true, percent: 10, thermal: .serious), mode: .automatic), 2, 1.5, .thermal, paused: true)
        expect(EnergyPolicy.decide(snapshot(battery: true, thermal: .serious), mode: .automatic), 2, 1.5, .thermal, paused: true)
    }

    @Test("Low battery needs a battery: a warning or low percent while plugged in is ignored")
    func lowBatteryOnlyOnBattery() {
        #expect(!snapshot(battery: false, percent: 5, warning: true).isLowBattery)
        expect(EnergyPolicy.decide(snapshot(battery: false, percent: 5, warning: true), mode: .automatic), 1, 1, .normal, paused: false)
        #expect(snapshot(battery: true, percent: nil, warning: true).isLowBattery)
        #expect(!snapshot(battery: true, percent: 20.5).isLowBattery)
    }

    @Test("Always fresh keeps the schedule; only Low Power Mode still pauses effects")
    func alwaysFresh() {
        expect(EnergyPolicy.decide(snapshot(battery: true, percent: 5, thermal: .critical), mode: .alwaysFresh), 1, 1, .normal, paused: false)
        expect(EnergyPolicy.decide(snapshot(lowPower: true), mode: .alwaysFresh), 1, 1, .normal, paused: true)
    }

    @Test("Save battery: at least 2× and 1.5×, more when automatic says so")
    func saveBattery() {
        expect(EnergyPolicy.decide(.nominalAC, mode: .saveBattery), 2, 1.5, .saver, paused: false)
        expect(EnergyPolicy.decide(snapshot(battery: true, percent: 90), mode: .saveBattery), 2, 1.5, .saver, paused: false)
        expect(EnergyPolicy.decide(snapshot(battery: true, percent: 10), mode: .saveBattery), 2, 1.5, .lowBattery, paused: false)
        expect(EnergyPolicy.decide(snapshot(lowPower: true), mode: .saveBattery), 3, 2, .lowPowerMode, paused: true)
        expect(EnergyPolicy.decide(snapshot(thermal: .critical), mode: .saveBattery), 4, 2, .thermal, paused: true)
    }

    @Test("Every decision stays within the allowed factors")
    func bounds() {
        for mode in EnergyMode.allCases {
            for lowPower in [false, true] {
                for battery in [false, true] {
                    for thermal in ThermalLevel.allCases {
                        let decision = EnergyPolicy.decide(snapshot(lowPower: lowPower, battery: battery, percent: 5, thermal: thermal), mode: mode)
                        #expect(EnergyFactor.allowed.contains(decision.factor.value))
                        #expect(decision.urgentCapFactor.value <= 2)
                    }
                }
            }
        }
    }

    @Test("Energy factors validate, thermal levels order")
    func factorValidation() throws {
        #expect(try EnergyFactor(1.5).value == 1.5)
        #expect(EnergyFactor.normal.value == 1)
        for bad in [0.99, 4.01, .nan, .infinity, -1] {
            #expect(throws: ValidationError.self) { try EnergyFactor(bad) }
        }
        #expect(try EnergyFactor(2) > EnergyFactor.normal)
        #expect(ThermalLevel.nominal < .fair && ThermalLevel.fair < .serious && ThermalLevel.serious < .critical)
        #expect(PowerSnapshot.nominalAC == PowerSnapshot(lowPowerMode: false, onBattery: false, batteryPercent: nil, thermal: .nominal))
    }
}
