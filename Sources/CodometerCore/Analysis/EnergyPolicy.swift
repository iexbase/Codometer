import Foundation

/// The system's thermal pressure (`ProcessInfo.ThermalState`).
public enum ThermalLevel: String, Sendable, CaseIterable, Comparable {
    case nominal, fair, serious, critical

    private var rank: Int {
        switch self {
        case .nominal: 0
        case .fair: 1
        case .serious: 2
        case .critical: 3
        }
    }

    public static func < (lhs: ThermalLevel, rhs: ThermalLevel) -> Bool { lhs.rank < rhs.rank }
}

/// Power conditions the refresh schedule adapts to.
public struct PowerSnapshot: Hashable, Sendable {
    /// A battery at or below this level counts as low even before the system's warning.
    public static let lowBatteryPercent = 20.0

    public let lowPowerMode: Bool
    public let onBattery: Bool
    /// `nil` on Macs without a battery or when unknown; shown for information.
    public let batteryPercent: Percentage?
    public let thermal: ThermalLevel
    /// The system's battery warning (`IOPSGetBatteryWarningLevel() != kIOPSLowBatteryWarningNone`, about 22 % and
    /// below). Change notifications cover it, so low battery never needs polling.
    public let lowBatteryWarning: Bool

    public init(
        lowPowerMode: Bool,
        onBattery: Bool,
        batteryPercent: Percentage?,
        thermal: ThermalLevel,
        lowBatteryWarning: Bool = false
    ) {
        self.lowPowerMode = lowPowerMode
        self.onBattery = onBattery
        self.batteryPercent = batteryPercent
        self.thermal = thermal
        self.lowBatteryWarning = lowBatteryWarning
    }

    /// Plugged in, cool, no Low Power Mode.
    public static let nominalAC = PowerSnapshot(lowPowerMode: false, onBattery: false, batteryPercent: nil, thermal: .nominal)

    /// On battery with the system's warning or at most `lowBatteryPercent` left.
    public var isLowBattery: Bool {
        guard onBattery else { return false }
        return lowBatteryWarning || (batteryPercent.map { $0.value <= Self.lowBatteryPercent } ?? false)
    }
}

/// How much longer scheduled refreshes wait: 1× to 4×.
public struct EnergyFactor: Hashable, Sendable, Comparable, CustomStringConvertible {
    public static let allowed: ClosedRange<Double> = 1...4

    public let value: Double

    public init(_ value: Double) throws(ValidationError) {
        guard value.isFinite else { throw .notFinite(field: "energyFactor") }
        guard Self.allowed.contains(value) else {
            throw .outOfRange(field: "energyFactor", value: value, lowerBound: Self.allowed.lowerBound, upperBound: Self.allowed.upperBound)
        }
        self.value = value
    }

    fileprivate init(trusted value: Double) {
        self.value = value
    }

    public static let normal = EnergyFactor(trusted: 1)

    public var description: String { "\(value)×" }

    public static func < (lhs: EnergyFactor, rhs: EnergyFactor) -> Bool { lhs.value < rhs.value }
}

/// What the energy policy decided for the current power conditions.
public struct EnergyDecision: Hashable, Sendable {
    /// Why refreshes slowed down; the settings footnote explains it.
    public enum Reason: String, Sendable, CaseIterable {
        case normal, battery, lowBattery, lowPowerMode, thermal, saver
    }

    /// Multiplies scheduled refresh delays and liveness rescans.
    public let factor: EnergyFactor
    /// Multiplies the urgent-usage refresh cap (at most 2×).
    public let urgentCapFactor: EnergyFactor
    public let reason: Reason
    /// Live animations are drawn still (Low Power Mode or serious heat).
    public let pausesLiveEffects: Bool

    public init(factor: EnergyFactor, urgentCapFactor: EnergyFactor, reason: Reason, pausesLiveEffects: Bool) {
        self.factor = factor
        self.urgentCapFactor = urgentCapFactor
        self.reason = reason
        self.pausesLiveEffects = pausesLiveEffects
    }

    public static let normal = EnergyDecision(factor: .normal, urgentCapFactor: .normal, reason: .normal, pausesLiveEffects: false)
}

/// Maps power conditions and the user's energy mode to refresh factors. Pure; the App feeds it snapshots.
public enum EnergyPolicy {
    /// | Situation | factor | urgent cap | live effects |
    /// |---|---|---|---|
    /// | always fresh (any power) | 1 | 1 | on, except in Low Power Mode |
    /// | plugged in, nominal or fair | 1 | 1 | on |
    /// | on battery | 1.5 | 1 | on |
    /// | low battery | 2 | 1.5 | on |
    /// | Low Power Mode | 3 | 2 | paused |
    /// | thermal serious | 2 | 1.5 | paused |
    /// | thermal critical | 4 | 2 | paused |
    /// | save battery | max(2, automatic) | max(1.5, automatic) | as automatic |
    ///
    /// Conditions combine by maximum, never by product. The reason names the condition with the largest factor
    /// (ties: Low Power Mode, then heat, then low battery, then battery).
    public static func decide(_ snapshot: PowerSnapshot, mode: EnergyMode) -> EnergyDecision {
        switch mode {
        case .alwaysFresh:
            return EnergyDecision(
                factor: .normal,
                urgentCapFactor: .normal,
                reason: .normal,
                pausesLiveEffects: snapshot.lowPowerMode
            )
        case .automatic:
            return automatic(snapshot)
        case .saveBattery:
            let automatic = automatic(snapshot)
            let factor = max(automatic.factor.value, 2)
            let cap = max(automatic.urgentCapFactor.value, 1.5)
            let keepsReason = automatic.reason != .normal && automatic.reason != .battery && automatic.factor.value >= 2
            return EnergyDecision(
                factor: EnergyFactor(trusted: factor),
                urgentCapFactor: EnergyFactor(trusted: cap),
                reason: keepsReason ? automatic.reason : .saver,
                pausesLiveEffects: automatic.pausesLiveEffects
            )
        }
    }

    private struct Condition {
        let factor: Double
        let cap: Double
        let reason: EnergyDecision.Reason
        /// Breaks factor ties: higher wins.
        let priority: Int
    }

    private static func automatic(_ snapshot: PowerSnapshot) -> EnergyDecision {
        var conditions: [Condition] = []
        if snapshot.onBattery {
            conditions.append(snapshot.isLowBattery
                ? Condition(factor: 2, cap: 1.5, reason: .lowBattery, priority: 1)
                : Condition(factor: 1.5, cap: 1, reason: .battery, priority: 0))
        }
        if snapshot.lowPowerMode {
            conditions.append(Condition(factor: 3, cap: 2, reason: .lowPowerMode, priority: 3))
        }
        switch snapshot.thermal {
        case .nominal, .fair:
            break
        case .serious:
            conditions.append(Condition(factor: 2, cap: 1.5, reason: .thermal, priority: 2))
        case .critical:
            conditions.append(Condition(factor: 4, cap: 2, reason: .thermal, priority: 2))
        }
        guard let leading = conditions.max(by: { ($0.factor, $0.priority) < ($1.factor, $1.priority) }) else {
            return .normal
        }
        return EnergyDecision(
            factor: EnergyFactor(trusted: leading.factor),
            urgentCapFactor: EnergyFactor(trusted: conditions.map(\.cap).max() ?? 1),
            reason: leading.reason,
            pausesLiveEffects: snapshot.lowPowerMode || snapshot.thermal >= .serious
        )
    }
}
