import CodometerCore
import CodometerPlatform
import CodometerStorage
import Foundation
import os

/// History queries: window usage, timelines and attribution, read from the history store after pending writes.
extension TrackerEngine {
    /// Recorded usage of one window since `since`, ascending, with the resets detected in between.
    ///
    /// The last observation before `since` takes part in reset detection only, so a reset right after `since`
    /// is still found. Empty when history storage is unavailable or unreadable.
    public func windowHistory(accountID: AccountID, bucketID: String, windowID: String, since: Date) async -> HistorySeries {
        await recorder?.flush()
        return await usageSeries(
            accountID: accountID,
            bucketID: bucketID,
            windowID: windowID,
            interval: DateInterval(start: since, end: max(since, .distantFuture))
        )
    }

    /// One account's activity timeline over `interval`: session segments under the headline primary window's usage,
    /// plus the stretches where nothing could be collected.
    ///
    /// Segments overlapping the interval are included whole (open ones with `end == nil`). `coverageStart` is where
    /// live collection began for the account (or the earliest segment start, if older), clamped into the interval,
    /// so a quiet stretch after collection began never reads as missing data. `gaps` are the breaks between the
    /// account's collection runs (the app was not running, the Mac slept, the account was off).
    public func timeline(accountID: AccountID, interval: DateInterval) async -> TimelineSnapshot {
        await recorder?.flush()
        let segments = await storedSegments(accountID: accountID, interval: interval)
        let headline = await headlineSeries(accountID: accountID, interval: interval)
        let collection = await collectionStart(accountID: accountID)
        let coverageStart = HistoryCoverage.start(
            collection: collection,
            earliestData: segments.lazy.map(\.start).min(),
            interval: interval
        )
        let runs = await collectionRuns(accountID: accountID, interval: interval)
        return TimelineSnapshot(
            accountID: accountID,
            interval: interval,
            segments: segments,
            usage: headline?.series,
            coverageStart: coverageStart,
            gaps: CollectionGaps.gaps(
                runs: runs,
                interval: interval,
                coverageStart: coverageStart,
                now: dependencies.now()
            )
        )
    }

    /// How the account's usage over `interval` splits across projects or sessions, estimated in points of the
    /// headline primary window; `nil` while no token data exists for the interval.
    public func attribution(accountID: AccountID, interval: DateInterval, grouping: AttributionGrouping) async -> AttributionReport? {
        guard let history = dependencies.history, let provider = state.account(accountID)?.profile.provider else {
            return nil
        }
        await recorder?.flush()
        let totals: [TokenUsageTotal]
        do throws(SQLiteError) {
            totals = try await history.tokenTotals(accountID: accountID, interval: interval)
        } catch {
            AppLog.storage.error("token history read failed: \(error.description, privacy: .public)")
            return nil
        }
        guard !totals.isEmpty else { return nil }
        let headline = await headlineSeries(accountID: accountID, interval: interval)
        let collection = await collectionStart(accountID: accountID)
        let runs = await collectionStarts(accountID: accountID, interval: interval)
        return AttributionBuilder.report(
            accountID: accountID,
            totals: totals,
            provider: provider,
            usage: headline?.series,
            reference: headline?.window,
            interval: interval,
            grouping: grouping,
            collectionStart: collection,
            collectionStarts: runs ?? []
        )
    }

    /// Waits until every history write produced so far is stored.
    func flushHistory() async {
        await recorder?.flush()
    }

    /// The current headline primary window and its usage over `interval`; `nil` without a reading.
    private func headlineSeries(accountID: AccountID, interval: DateInterval) async -> (series: HistorySeries, window: LimitWindow)? {
        guard let reading = state.account(accountID)?.reading else { return nil }
        let headline = HeadlineWindows(reading: reading)
        let series = await usageSeries(
            accountID: accountID,
            bucketID: headline.bucket.id,
            windowID: headline.primary.id,
            interval: interval
        )
        return (series, headline.primary)
    }

    private func usageSeries(accountID: AccountID, bucketID: String, windowID: String, interval: DateInterval) async -> HistorySeries {
        let observations = await observations(accountID: accountID, bucketID: bucketID, windowID: windowID, since: interval.start)
        return HistorySeriesBuilder.series(
            accountID: accountID,
            bucketID: bucketID,
            windowID: windowID,
            observations: observations,
            interval: interval
        )
    }

    /// Stored observations since `since`, preceded by the latest one before it (for reset detection).
    private func observations(
        accountID: AccountID,
        bucketID: String,
        windowID: String,
        since: Date
    ) async -> [HistorySeriesBuilder.Observation] {
        guard let history = dependencies.history else { return [] }
        do throws(SQLiteError) {
            let previous = try await history.latestSample(accountID: accountID, bucketID: bucketID, windowID: windowID, before: since)
            let samples = try await history.samples(accountID: accountID, bucketID: bucketID, windowID: windowID, since: since)
            return ((previous.map { [$0] } ?? []) + samples).map { sample in
                HistorySeriesBuilder.Observation(at: sample.capturedAt, used: sample.used.value, resetsAt: sample.resetsAt)
            }
        } catch {
            AppLog.storage.error("history read failed: \(error.description, privacy: .public)")
            return []
        }
    }

    private func collectionStart(accountID: AccountID) async -> Date? {
        guard let history = dependencies.history else { return nil }
        do throws(SQLiteError) {
            return try await history.collectionStart(accountID: accountID)
        } catch {
            AppLog.storage.error("collection start read failed: \(error.description, privacy: .public)")
            return nil
        }
    }

    /// When collection runs overlapping `interval` started; `nil` when history is unreadable.
    private func collectionStarts(accountID: AccountID, interval: DateInterval) async -> [Date]? {
        guard let history = dependencies.history else { return nil }
        do throws(SQLiteError) {
            return try await history.collectionStarts(accountID: accountID, interval: interval)
        } catch {
            AppLog.storage.error("collection runs read failed: \(error.description, privacy: .public)")
            return nil
        }
    }

    /// The collection runs overlapping `interval`; empty when history is unreadable.
    private func collectionRuns(accountID: AccountID, interval: DateInterval) async -> [CollectionRun] {
        guard let history = dependencies.history else { return [] }
        do throws(SQLiteError) {
            return try await history.collectionRuns(accountID: accountID, interval: interval)
        } catch {
            AppLog.storage.error("collection runs read failed: \(error.description, privacy: .public)")
            return []
        }
    }

    private func storedSegments(accountID: AccountID, interval: DateInterval) async -> [SessionSegment] {
        guard let history = dependencies.history else { return [] }
        do throws(SQLiteError) {
            return try await history.segments(accountID: accountID, interval: interval)
        } catch {
            AppLog.storage.error("segment history read failed: \(error.description, privacy: .public)")
            return []
        }
    }
}
