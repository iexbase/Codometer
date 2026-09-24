import Foundation

/// Where usage lands by the window's reset at the average pace since the window started.
///
/// Deterministic and history-free, consistent with `UsagePace`: "at this pace" means this average.
public struct UsageForecast: Hashable, Sendable {
    /// Forecasts that add less than this many points to current usage show nothing.
    public static let minimumVisibleGain = 2.0

    /// Projected usage at the reset, in points (may exceed 100).
    public let projectedUsed: Double
    /// `projectedUsed >= 100`.
    public let reachesLimit: Bool
    /// The band of `min(projectedUsed, 100)` with the user's thresholds.
    public let band: UsageBand

    /// `nil` when the window has no reset time or duration, the reset has passed, less than
    /// `UsagePace.minimumElapsedFractionForProjection` (15 %) of the window has elapsed (a reset further away than one
    /// window, from clock skew, counts as nothing elapsed), nothing is used, the limit is already exhausted, or the
    /// forecast adds less than `minimumVisibleGain` points.
    public init?(window: LimitWindow, now: Date, thresholds: BandThresholds) {
        guard
            let resetsAt = window.resetsAt,
            let duration = window.duration,
            resetsAt > now
        else { return nil }
        let windowLength = duration.timeInterval
        let remaining = min(resetsAt.timeIntervalSince(now), windowLength)
        let elapsedFraction = (windowLength - remaining) / windowLength
        let used = window.used.value
        guard
            elapsedFraction >= UsagePace.minimumElapsedFractionForProjection,
            used > 0,
            !window.used.isExhausted
        else { return nil }

        let projected = used / elapsedFraction
        guard projected.isFinite, projected - used >= Self.minimumVisibleGain else { return nil }
        projectedUsed = projected
        reachesLimit = projected >= 100
        let capped = (try? Percentage(validating: min(projected, 100))) ?? .full
        band = UsageBand(used: capped, thresholds: thresholds)
    }
}
