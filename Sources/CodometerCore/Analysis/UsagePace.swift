import Foundation

/// Compares usage with the share of the window that has elapsed.
///
/// If 60 % of a window is used when only 40 % of its time has passed, usage runs
/// 20 points ahead of an even pace, and at that rate the limit runs out early.
public struct UsagePace: Hashable, Sendable {
    public enum Verdict: Hashable, Sendable {
        case onTrack
        /// Usage runs ahead of time: the limit will be tight.
        case ahead(points: Double)
        /// Usage runs behind time: there is headroom.
        case behind(points: Double)
    }

    /// Points within which usage counts as on track.
    public static let tolerancePoints = 3.0
    /// Too little of the window has elapsed for a straight-line projection to mean anything.
    public static let minimumElapsedFractionForProjection = 0.15

    public let elapsedFraction: Double
    public let expectedUsed: Double
    /// `used − expected`, in percentage points.
    public let deltaPoints: Double
    public let verdict: Verdict
    /// When the limit runs out at the current average rate, if that happens before the reset.
    public let projectedExhaustion: Date?

    public init?(window: LimitWindow, now: Date) {
        guard
            let resetsAt = window.resetsAt,
            let duration = window.duration,
            resetsAt > now
        else { return nil }

        let windowLength = duration.timeInterval
        let remaining = min(resetsAt.timeIntervalSince(now), windowLength)
        let elapsed = windowLength - remaining
        let elapsedFraction = elapsed / windowLength
        let used = window.used.value

        self.elapsedFraction = elapsedFraction
        expectedUsed = elapsedFraction * 100
        deltaPoints = used - expectedUsed

        if deltaPoints > Self.tolerancePoints {
            verdict = .ahead(points: deltaPoints)
        } else if deltaPoints < -Self.tolerancePoints {
            verdict = .behind(points: -deltaPoints)
        } else {
            verdict = .onTrack
        }

        guard
            !window.used.isExhausted,
            used > 0,
            elapsedFraction >= Self.minimumElapsedFractionForProjection,
            elapsed > 0
        else {
            projectedExhaustion = nil
            return
        }
        let pointsPerSecond = used / elapsed
        let secondsToExhaustion = (100 - used) / pointsPerSecond
        let exhaustion = now.addingTimeInterval(secondsToExhaustion)
        projectedExhaustion = exhaustion < resetsAt ? exhaustion : nil
    }
}
