import CodometerCore
import CodometerStorage
import Foundation

/// Where recorded session and token data of a range begins, and which token samples are worth storing.
enum HistoryCoverage {
    /// Token samples stamped further in the future than this are corrupt and dropped.
    static let futureTolerance: TimeInterval = 5 * 60

    /// The `coverageStart` of a timeline or attribution report over `interval`.
    ///
    /// Data is collected live from the account's collection start, so that start (or the earliest stored data,
    /// if older) marks where the range stops being unknown. Clamped into the interval: a range that starts after
    /// collection began is fully covered (its start), one that ends before it is not covered at all (its end).
    /// `nil` when neither is known.
    static func start(collection: Date?, earliestData: Date?, interval: DateInterval) -> Date? {
        guard let earliest = [collection, earliestData].compactMap(\.self).min() else { return nil }
        return min(max(earliest, interval.start), interval.end)
    }

    /// The samples of `accountID` that carry tokens and a plausible time: not older than `retention`
    /// (pruning would delete them anyway) and not in the future beyond `futureTolerance`.
    static func recordableTokens(
        _ samples: [TokenSample],
        accountID: AccountID,
        now: Date,
        retention: TimeInterval = UsageHistoryStore.defaultRetention
    ) -> [TokenSample] {
        let oldest = now.addingTimeInterval(-retention)
        let newest = now.addingTimeInterval(futureTolerance)
        return samples.filter { sample in
            sample.accountID == accountID && !sample.delta.isZero && sample.at >= oldest && sample.at <= newest
        }
    }
}
