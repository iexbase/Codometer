import CodometerCore
@testable import CodometerEngine
import Foundation
import Testing

@Suite("Refresh schedule under the energy policy")
struct RefreshScheduleEnergyTests {
    private func factor(_ value: Double) throws -> EnergyFactor {
        try EnergyFactor(value)
    }

    @Test("Scaling multiplies inside the schedule's own bounds")
    func bounds() throws {
        #expect(RefreshSchedule.scaled(300, by: .normal) == 300)
        #expect(RefreshSchedule.scaled(300, by: try factor(1.5)) == 450)
        #expect(RefreshSchedule.scaled(300, by: try factor(4)) == 1_200)
    }

    @Test("Scaling never goes below the minimum delay or above the 30 minute cap")
    func clamping() throws {
        #expect(RefreshSchedule.scaled(5, by: .normal) == RefreshSchedule.minimumDelay)
        #expect(RefreshSchedule.scaled(20, by: try factor(1.5)) == RefreshSchedule.minimumDelay)
        #expect(RefreshSchedule.scaled(1_200, by: try factor(4)) == RefreshSchedule.maximumBackoff)
        #expect(RefreshSchedule.scaled(RefreshSchedule.maximumBackoff, by: try factor(4)) == RefreshSchedule.maximumBackoff)
    }

    @Test("The backoff stays capped at 30 minutes however large the factor")
    func backoffWithFactor() throws {
        let interval = try PollInterval(seconds: 300)
        let base = RefreshSchedule.delay(interval: interval, consecutiveFailures: 6, jitter: 0)
        #expect(RefreshSchedule.scaled(base, by: try factor(4)) == RefreshSchedule.maximumBackoff)
    }

    @Test("The urgent cap factor reproduces every row of the energy policy table")
    func urgentCapMatchesPolicy() throws {
        let snapshots: [PowerSnapshot] = [
            .nominalAC,
            PowerSnapshot(lowPowerMode: false, onBattery: true, batteryPercent: try Percentage(validating: 80), thermal: .nominal),
            PowerSnapshot(lowPowerMode: false, onBattery: true, batteryPercent: try Percentage(validating: 15), thermal: .nominal),
            PowerSnapshot(lowPowerMode: false, onBattery: true, batteryPercent: nil, thermal: .nominal, lowBatteryWarning: true),
            PowerSnapshot(lowPowerMode: true, onBattery: true, batteryPercent: try Percentage(validating: 40), thermal: .nominal),
            PowerSnapshot(lowPowerMode: false, onBattery: false, batteryPercent: nil, thermal: .fair),
            PowerSnapshot(lowPowerMode: false, onBattery: false, batteryPercent: nil, thermal: .serious),
            PowerSnapshot(lowPowerMode: false, onBattery: false, batteryPercent: nil, thermal: .critical),
            PowerSnapshot(lowPowerMode: true, onBattery: true, batteryPercent: try Percentage(validating: 5), thermal: .critical),
            PowerSnapshot(lowPowerMode: false, onBattery: true, batteryPercent: try Percentage(validating: 50), thermal: .serious),
        ]
        for snapshot in snapshots {
            for mode in EnergyMode.allCases {
                let decision = EnergyPolicy.decide(snapshot, mode: mode)
                #expect(
                    RefreshSchedule.urgentCapFactor(for: decision.factor) == decision.urgentCapFactor,
                    "factor \(decision.factor.value) in \(mode.rawValue)"
                )
            }
        }
    }

    @Test("The urgent cap factor stays within its own bounds")
    func urgentCapBounds() throws {
        #expect(RefreshSchedule.urgentCapFactor(for: .normal) == .normal)
        #expect(RefreshSchedule.urgentCapFactor(for: try factor(1.5)) == .normal)
        #expect(RefreshSchedule.urgentCapFactor(for: try factor(2)) == (try factor(1.5)))
        #expect(RefreshSchedule.urgentCapFactor(for: try factor(3)) == (try factor(2)))
        #expect(RefreshSchedule.urgentCapFactor(for: try factor(4)) == (try factor(2)))
    }

    @Test("A stretched schedule still refreshes right after a reset")
    func resetStillWins() throws {
        let now = Date(timeIntervalSince1970: 1_789_600_000)
        let reading = try UsageReading(
            capturedAt: now,
            source: .claudeUsageCommand,
            buckets: [try LimitBucket(
                id: "claude",
                title: nil,
                windows: [try LimitWindow(
                    id: "session",
                    scope: .session,
                    used: try Percentage(validating: 20),
                    duration: .fiveHours,
                    resetsAt: now.addingTimeInterval(120)
                )],
                isLimitReached: false
            )],
            credits: nil
        )
        let stretched = RefreshSchedule.scaled(600, by: try factor(3))
        #expect(stretched == 1_800)
        #expect(RefreshSchedule.delay(stretched, wakingForResetsIn: reading, now: now) == 150)
    }
}
