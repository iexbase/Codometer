import CodometerCore
import Foundation

/// Turns stored limit observations into the domain's `HistorySeries`, detecting window resets on the way.
enum HistorySeriesBuilder {
    /// One stored observation of a window, independent of the storage layer's row type.
    struct Observation: Hashable, Sendable {
        let at: Date
        let used: Double
        let resetsAt: Date?
    }

    /// A reset time moving later by at least this much between two observations means a new window period.
    /// Smaller moves are the drift of rolling windows and source precision noise.
    static let resetShift: TimeInterval = AlertEvaluator.resetShiftTolerance
    /// A drop this large also means a new window period, for observations without reset times.
    static let resetDrop: Double = UsageAttribution.periodDropPoints

    /// Builds the series of the observations inside `interval` (all of them when `nil`).
    ///
    /// Observations that fail `UsagePoint` validation are skipped rather than failing the whole series.
    static func series(
        accountID: AccountID,
        bucketID: String,
        windowID: String,
        observations: [Observation],
        interval: DateInterval? = nil
    ) -> HistorySeries {
        let ordered = observations.sorted { $0.at < $1.at }
        let inside = interval.map { range in ordered.filter { range.contains($0.at) } } ?? ordered
        let points = inside.compactMap { observation in
            try? UsagePoint(at: observation.at, used: observation.used)
        }
        let resets = resets(in: ordered).filter { date in interval?.contains(date) ?? true }
        return HistorySeries(accountID: accountID, bucketID: bucketID, windowID: windowID, points: points, resets: resets)
    }

    /// Resets between consecutive observations (ascending input expected).
    ///
    /// A reset time that passed between two observations is the reset itself. Otherwise a reset time that moved
    /// later by `resetShift` or a usage drop of `resetDrop` points means a reset happened, and it is placed at
    /// the later observation, the earliest moment it is known.
    static func resets(in observations: [Observation]) -> [Date] {
        var resets: [Date] = []
        for (previous, current) in zip(observations, observations.dropFirst()) {
            if let resetsAt = previous.resetsAt, resetsAt > previous.at, resetsAt <= current.at {
                resets.append(resetsAt)
            } else if let old = previous.resetsAt, let new = current.resetsAt, new.timeIntervalSince(old) >= resetShift {
                resets.append(current.at)
            } else if previous.used - current.used >= resetDrop {
                resets.append(current.at)
            }
        }
        return resets
    }
}
