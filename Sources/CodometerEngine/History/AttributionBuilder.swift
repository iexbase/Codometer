import CodometerCore
import CodometerStorage
import Foundation

/// Builds «Кто съел лимит» reports from stored token totals.
///
/// Storage sums tokens per session, project and model over the interval, so a week of 5-minute buckets is never
/// truncated. Each total becomes one `TokenSample` placed at its latest bucket (clamped into the interval), which
/// keeps `UsageAttribution`'s "latest known project" rule for session grouping. Coverage starts where the
/// account's collection began (or at the earliest bucket, if older), clamped into the interval.
///
/// Points are estimated only over the collection runs `collectionStarts` describes, so usage from before the first
/// start or from while the app was not running is never credited to projects. Without known runs (`nil`) every
/// stored observation of the interval counts.
enum AttributionBuilder {
    /// `nil` when there are no token totals in the interval.
    static func report(
        accountID: AccountID,
        totals: [TokenUsageTotal],
        provider: ProviderKind,
        usage: HistorySeries?,
        reference: LimitWindow?,
        interval: DateInterval,
        grouping: AttributionGrouping,
        collectionStart: Date? = nil,
        collectionStarts: [Date]? = nil
    ) -> AttributionReport? {
        let samples = totals.compactMap { total in
            try? TokenSample(
                accountID: accountID,
                sessionID: total.sessionID,
                project: total.project,
                model: total.model,
                at: clamp(total.lastBucket, into: interval),
                delta: total.counts
            )
        }
        guard !samples.isEmpty else { return nil }
        let report = UsageAttribution.report(
            samples: samples,
            provider: provider,
            usage: usage,
            interval: interval,
            grouping: grouping,
            reference: reference,
            collectionStarts: collectionStarts
        )
        return AttributionReport(
            interval: report.interval,
            windowTitleSource: report.windowTitleSource,
            usedPoints: report.usedPoints,
            shares: report.shares,
            totalWeightedTokens: report.totalWeightedTokens,
            coverageStart: HistoryCoverage.start(
                collection: collectionStart,
                earliestData: totals.lazy.map(\.firstBucket).min(),
                interval: interval
            )
        )
    }

    static func clamp(_ date: Date, into interval: DateInterval) -> Date {
        min(max(date, interval.start), interval.end)
    }
}
