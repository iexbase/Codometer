import CodometerCore
import Foundation

/// A monitor's recent refresh attempts, newest first, in memory only.
///
/// A ring buffer of at most `AccountDiagnostics.maximumProbes` records: the Diagnostics pane draws the last eight as
/// dots, and the rest bound what one long-running account can hold. Nothing here is ever written to disk.
struct ProbeLedger: Sendable {
    static let capacity = AccountDiagnostics.maximumProbes

    let kind: ProbeRecord.Kind
    /// Newest first, at most `capacity`.
    private(set) var records: [ProbeRecord] = []
    /// When the attempt that is running now started, if one is.
    private(set) var startedAt: Date?

    init(kind: ProbeRecord.Kind) {
        self.kind = kind
    }

    var isRunning: Bool { startedAt != nil }

    /// Marks the start of an attempt. A second `begin` without an `end` (a monitor that was stopped mid-probe and
    /// started again) replaces the first: only the newer attempt can still finish.
    mutating func begin(at now: Date) {
        startedAt = now
    }

    /// Closes the attempt `begin` opened. Without an open attempt the record is stamped as instantaneous, so an
    /// outcome is never lost.
    mutating func end(at now: Date, outcome: ProbeRecord.Outcome) {
        let started = startedAt ?? now
        startedAt = nil
        append(ProbeRecord(kind: kind, startedAt: started, finishedAt: now, outcome: outcome))
    }

    /// A scheduled refresh that did not run the probe at all. Skips need no `begin` and never close an attempt that
    /// is still running.
    mutating func skip(_ reason: ProbeRecord.SkipReason, at now: Date) {
        append(ProbeRecord(kind: kind, startedAt: now, finishedAt: now, outcome: .skipped(reason)))
    }

    private mutating func append(_ record: ProbeRecord) {
        records.insert(record, at: 0)
        if records.count > Self.capacity {
            records.removeLast(records.count - Self.capacity)
        }
    }
}
