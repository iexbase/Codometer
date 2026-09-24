import CodometerCore
import Foundation
import os
import WidgetKit

/// One public log line per WidgetKit request, so a widget that shows "No data" can be told apart from one that
/// never got the file: `log stream --predicate 'subsystem == "com.codometer.widgets"'`.
///
/// The line carries counts only — whether the snapshot file was read, how many accounts it has in total and in the
/// widget's scope, how many have numbers or look stale, how many entries were returned and how old the snapshot
/// is. Never labels, e-mails, window titles, paths or percentages.
enum WidgetDiagnostics {
    enum Request: String {
        case timeline
        case snapshot
    }

    /// What one request found, without any account content.
    struct Summary: Equatable {
        /// `SnapshotReadResult.name`.
        let file: String
        let totalAccounts: Int
        let scopedAccounts: Int
        let withReading: Int
        let stale: Int
        /// Seconds since the app wrote the snapshot; `nil` without a snapshot.
        let ageSeconds: Int?

        init(result: SnapshotReadResult, scope: WidgetScope, now: Date) {
            file = result.name
            let snapshot = result.snapshot
            totalAccounts = snapshot?.accounts.count ?? 0
            let states = snapshot?.scoped(to: scope).states(at: now) ?? []
            scopedAccounts = states.count
            withReading = states.count(where: \.hasReading)
            stale = states.count(where: \.isStale)
            ageSeconds = snapshot.map { Int(now.timeIntervalSince($0.generatedAt).rounded()) }
        }
    }

    private static let logger = Logger(subsystem: "com.codometer.widgets", category: "timeline")

    static func record(
        _ request: Request,
        scope: WidgetScope,
        kind: String? = nil,
        family: WidgetFamily,
        result: SnapshotReadResult,
        entries: Int,
        now: Date
    ) {
        let summary = Summary(result: result, scope: scope, now: now)
        logger.notice(
            """
            \(request.rawValue, privacy: .public) kind=\(kind ?? scope.kind, privacy: .public) family=\(String(describing: family), privacy: .public) \
            file=\(summary.file, privacy: .public) accounts=\(summary.scopedAccounts, privacy: .public)/\(summary.totalAccounts, privacy: .public) \
            readings=\(summary.withReading, privacy: .public) stale=\(summary.stale, privacy: .public) \
            entries=\(entries, privacy: .public) age=\(summary.ageSeconds ?? -1, privacy: .public)s
            """
        )
    }
}
