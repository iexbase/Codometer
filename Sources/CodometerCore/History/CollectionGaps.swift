import Foundation

/// One stretch of live collection for an account, from `collection_runs`.
public struct CollectionRun: Hashable, Sendable {
    /// Why a run ended.
    public enum EndReason: String, Sendable, CaseIterable {
        case quit
        case sleep
        /// The account was turned off.
        case disabled
        /// The app did not end the run; it was closed at its last heartbeat on the next launch.
        case crash
        /// Backfilled for history recorded before runs had ends; the end can be early.
        case inferred
    }

    public let start: Date
    /// `nil` while the run is open.
    public let end: Date?
    /// The latest heartbeat.
    public let lastSeen: Date?
    public let endReason: EndReason?

    /// An end or heartbeat before the start is moved to the start.
    public init(start: Date, end: Date?, lastSeen: Date?, endReason: EndReason?) {
        self.start = start
        self.end = end.map { max($0, start) }
        self.lastSeen = lastSeen.map { max($0, start) }
        self.endReason = endReason
    }
}

/// A stretch without collected data inside a timeline.
public struct CollectionGap: Hashable, Sendable {
    public enum Reason: Sendable, CaseIterable {
        case appNotRunning
        case macAsleep
        case accountOff
        case unknown
    }

    public let interval: DateInterval
    public let reason: Reason

    public init(interval: DateInterval, reason: Reason) {
        self.interval = interval
        self.reason = reason
    }
}

/// Finds the gaps between collection runs, so a timeline tells "nothing happened" from "nothing was recorded".
public enum CollectionGaps {
    /// Shorter breaks are heartbeat noise.
    public static let minimumGap: TimeInterval = 10 * 60
    /// Inferred ends (and runs without any end evidence) can be up to 30 minutes early, so they need a longer break.
    public static let minimumInferredGap: TimeInterval = 45 * 60

    /// Gaps between consecutive runs (from where the covered time ends to the next start) and after an ended last run
    /// (to `now` or the interval's end), clipped to `interval`, never before `coverageStart`, ordered by start.
    ///
    /// Overlapping runs merge. A run's covered time ends at `end`, else `lastSeen`, else its start. An open last run
    /// is still collecting, so it leaves no trailing gap. Reasons: quit/crash → app not running, sleep → Mac asleep,
    /// disabled → account off, inferred or no reason → unknown. Breaks shorter than `minimumGap`
    /// (`minimumInferredGap` after an inferred or evidence-free end) are not gaps.
    public static func gaps(runs: [CollectionRun], interval: DateInterval, coverageStart: Date?, now: Date) -> [CollectionGap] {
        let sorted = runs.sorted { lhs, rhs in
            lhs.start == rhs.start ? (lhs.end ?? .distantFuture) < (rhs.end ?? .distantFuture) : lhs.start < rhs.start
        }
        var result: [CollectionGap] = []
        var covered: (end: Date, run: CollectionRun)?
        for run in sorted {
            if let current = covered, run.start > current.end,
               let gap = gap(from: current.end, to: run.start, after: current.run, interval: interval, coverageStart: coverageStart) {
                result.append(gap)
            }
            let runEnd = run.end ?? run.lastSeen ?? run.start
            if let current = covered, current.end >= runEnd {
                continue
            }
            covered = (runEnd, run)
        }
        // The latest run ended and nothing has collected since: a trailing gap up to now.
        if let last = covered, !sorted.contains(where: { $0.end == nil && $0.start >= last.run.start }) {
            let end = min(now, interval.end)
            if end > last.end,
               let gap = gap(from: last.end, to: end, after: last.run, interval: interval, coverageStart: coverageStart) {
                result.append(gap)
            }
        }
        return result
    }

    private static func gap(
        from start: Date,
        to end: Date,
        after run: CollectionRun,
        interval: DateInterval,
        coverageStart: Date?
    ) -> CollectionGap? {
        let isUncertain = run.endReason == .inferred || (run.end == nil && run.lastSeen == nil)
        let minimum = isUncertain ? minimumInferredGap : minimumGap
        guard end.timeIntervalSince(start) >= minimum else { return nil }
        let clippedStart = max(start, interval.start, coverageStart ?? .distantPast)
        let clippedEnd = min(end, interval.end)
        guard clippedEnd > clippedStart else { return nil }
        return CollectionGap(interval: DateInterval(start: clippedStart, end: clippedEnd), reason: reason(for: run))
    }

    private static func reason(for run: CollectionRun) -> CollectionGap.Reason {
        switch run.endReason {
        case .quit, .crash: .appNotRunning
        case .sleep: .macAsleep
        case .disabled: .accountOff
        case .inferred, nil: .unknown
        }
    }
}
