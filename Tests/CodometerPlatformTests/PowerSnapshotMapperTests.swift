import CodometerCore
@testable import CodometerPlatform
import Foundation
import IOKit.ps
import Testing

/// Power-source dictionaries shaped like the ones `IOPSGetPowerSourceDescription` returns.
private enum Sources {
    static func internalBattery(current: Int, maximum: Int = 100, isPresent: Bool = true) -> [String: Any] {
        [
            kIOPSTypeKey: kIOPSInternalBatteryType,
            kIOPSTransportTypeKey: kIOPSInternalType,
            kIOPSIsPresentKey: isPresent,
            kIOPSCurrentCapacityKey: current,
            kIOPSMaxCapacityKey: maximum,
        ]
    }

    static func uninterruptiblePowerSupply() -> [String: Any] {
        [
            kIOPSTypeKey: kIOPSUPSType,
            kIOPSTransportTypeKey: kIOPSSerialTransportType,
            kIOPSIsPresentKey: true,
            kIOPSCurrentCapacityKey: 90,
            kIOPSMaxCapacityKey: 100,
        ]
    }
}

@Suite("Power snapshot mapping")
struct PowerSnapshotMapperTests {
    @Test("Thermal states map onto the domain's levels")
    func thermalLevels() {
        #expect(PowerSourceMapper.thermalLevel(.nominal) == .nominal)
        #expect(PowerSourceMapper.thermalLevel(.fair) == .fair)
        #expect(PowerSourceMapper.thermalLevel(.serious) == .serious)
        #expect(PowerSourceMapper.thermalLevel(.critical) == .critical)
    }

    @Test("Every warning level but `none` counts as a low battery")
    func warningLevels() {
        #expect(!PowerSourceMapper.isLowBatteryWarning(kIOPSLowBatteryWarningNone))
        #expect(PowerSourceMapper.isLowBatteryWarning(kIOPSLowBatteryWarningEarly))
        #expect(PowerSourceMapper.isLowBatteryWarning(kIOPSLowBatteryWarningFinal))
    }

    @Test("Only a present internal battery counts as one")
    func internalBatteries() {
        #expect(PowerSourceMapper.isInternalBattery(Sources.internalBattery(current: 50)))
        #expect(!PowerSourceMapper.isInternalBattery(Sources.internalBattery(current: 50, isPresent: false)))
        #expect(!PowerSourceMapper.isInternalBattery(Sources.uninterruptiblePowerSupply()))
        #expect(!PowerSourceMapper.isInternalBattery([:]))
    }

    @Test("The charge is the current capacity over the maximum")
    func percentages() {
        #expect(PowerSourceMapper.batteryPercent(in: Sources.internalBattery(current: 42))?.value == 42)
        #expect(PowerSourceMapper.batteryPercent(in: Sources.internalBattery(current: 2_600, maximum: 5_200))?.value == 50)
        #expect(PowerSourceMapper.batteryPercent(in: Sources.internalBattery(current: 120))?.value == 100)
        #expect(PowerSourceMapper.batteryPercent(in: Sources.internalBattery(current: 50, maximum: 0)) == nil)
        #expect(PowerSourceMapper.batteryPercent(in: Sources.internalBattery(current: -5)) == nil)
        #expect(PowerSourceMapper.batteryPercent(in: [:]) == nil)
    }

    @Test("A Mac on wall power is not on battery, whatever it carries")
    func onWallPower() {
        let snapshot = PowerSourceMapper.snapshot(
            providingPowerSourceType: PowerSourceMapper.acPowerType,
            descriptions: [Sources.internalBattery(current: 15)],
            lowPowerMode: false,
            thermal: .nominal,
            lowBatteryWarning: true
        )
        #expect(!snapshot.onBattery)
        #expect(!snapshot.lowBatteryWarning)
        #expect(!snapshot.isLowBattery)
        #expect(snapshot.batteryPercent?.value == 15)
    }

    @Test("A Mac on its battery carries the warning and the charge")
    func onBattery() {
        let snapshot = PowerSourceMapper.snapshot(
            providingPowerSourceType: kIOPSBatteryPowerValue,
            descriptions: [Sources.internalBattery(current: 18)],
            lowPowerMode: false,
            thermal: .fair,
            lowBatteryWarning: true
        )
        #expect(snapshot.onBattery)
        #expect(snapshot.lowBatteryWarning)
        #expect(snapshot.isLowBattery)
        #expect(snapshot.thermal == .fair)
        #expect(EnergyPolicy.decide(snapshot, mode: .automatic).reason == .lowBattery)
    }

    @Test("A desktop Mac reports wall power and no charge")
    func desktop() {
        let snapshot = PowerSourceMapper.snapshot(
            providingPowerSourceType: PowerSourceMapper.acPowerType,
            descriptions: [],
            lowPowerMode: false,
            thermal: .nominal,
            lowBatteryWarning: false
        )
        #expect(snapshot == .nominalAC)
        #expect(EnergyPolicy.decide(snapshot, mode: .automatic) == .normal)
    }

    @Test("Unknown power sources are treated as wall power")
    func unknownSource() {
        let snapshot = PowerSourceMapper.snapshot(
            providingPowerSourceType: nil,
            descriptions: [],
            lowPowerMode: true,
            thermal: .nominal,
            lowBatteryWarning: false
        )
        #expect(!snapshot.onBattery)
        #expect(snapshot.lowPowerMode)
    }

    @Test("The lowest internal battery wins and a UPS is ignored")
    func severalSources() {
        let snapshot = PowerSourceMapper.snapshot(
            providingPowerSourceType: kIOPSBatteryPowerValue,
            descriptions: [Sources.uninterruptiblePowerSupply(), Sources.internalBattery(current: 64), Sources.internalBattery(current: 31)],
            lowPowerMode: false,
            thermal: .nominal,
            lowBatteryWarning: false
        )
        #expect(snapshot.batteryPercent?.value == 31)
    }

    @Test("The charge is re-read only after a minute")
    func percentReadInterval() {
        let now = Date(timeIntervalSince1970: 1_789_600_000)
        let interval = PowerStateMonitor.batteryPercentInterval
        #expect(PowerStateMonitor.shouldReadPercent(lastReadAt: nil, now: now, interval: interval))
        #expect(!PowerStateMonitor.shouldReadPercent(lastReadAt: now.addingTimeInterval(-30), now: now, interval: interval))
        #expect(PowerStateMonitor.shouldReadPercent(lastReadAt: now.addingTimeInterval(-60), now: now, interval: interval))
        // A clock that moved back reads again rather than trusting a value from the future.
        #expect(PowerStateMonitor.shouldReadPercent(lastReadAt: now.addingTimeInterval(120), now: now, interval: interval))
    }

    @Test("The live monitor answers without a battery and without polling")
    func liveSnapshot() {
        let monitor = PowerStateMonitor()
        let snapshot = monitor.current()
        #expect(snapshot.thermal >= .nominal)
        // Whatever this Mac is, the decision has to be one the policy knows.
        #expect(EnergyFactor.allowed.contains(EnergyPolicy.decide(snapshot, mode: .automatic).factor.value))
    }
}
