import CodometerCore
import Foundation

/// Combines readings from sources that see different subsets of an account's buckets.
///
/// A Codex session log only carries the bucket of the model in use, while `app-server`
/// returns all buckets. Merging keeps the newest value per bucket without dropping the rest.
public enum ReadingMerger {
    /// Returns the merged reading, or `nil` when `incoming` adds nothing to `current`.
    public static func merge(current: UsageReading?, incoming: UsageReading, now: Date) -> UsageReading? {
        guard let current else { return incoming }

        let incomingIsNewer = incoming.capturedAt >= current.capturedAt
        let primary = incomingIsNewer ? incoming : current
        let secondary = incomingIsNewer ? current : incoming

        let primaryIDs = Set(primary.buckets.map(\.id))
        let carried = secondary.buckets.filter { bucket in
            !primaryIDs.contains(bucket.id) && !bucket.windows.contains { $0.hasReset(at: now) }
        }
        guard incomingIsNewer || !carried.isEmpty else { return nil }

        let buckets = Array((primary.buckets + carried).prefix(UsageReading.maximumBuckets))
        return try? UsageReading(
            capturedAt: primary.capturedAt,
            source: primary.source,
            buckets: buckets,
            credits: primary.credits ?? secondary.credits
        )
    }
}
