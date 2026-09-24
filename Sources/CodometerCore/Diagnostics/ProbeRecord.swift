import Foundation

/// One refresh attempt of an account, kept in memory for the Diagnostics pane.
public struct ProbeRecord: Hashable, Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        case claudeUsageCommand
        case codexAppServer
    }

    public enum Outcome: Hashable, Sendable {
        case reading(windowCount: Int)
        case failure(TrackerIssue.Kind)
        case skipped(SkipReason)
    }

    /// Why a scheduled refresh did not run the probe.
    public enum SkipReason: String, Sendable, CaseIterable {
        case offline
        case signedOutWait
        case logsFresh
        case pausedAfterFormatDrift
    }

    public let kind: Kind
    public let startedAt: Date
    /// Never before `startedAt`: a clock set back makes the duration zero.
    public let finishedAt: Date
    public let outcome: Outcome

    public init(kind: Kind, startedAt: Date, finishedAt: Date, outcome: Outcome) {
        self.kind = kind
        self.startedAt = startedAt
        self.finishedAt = max(finishedAt, startedAt)
        if case .reading(let count) = outcome {
            self.outcome = .reading(windowCount: max(0, count))
        } else {
            self.outcome = outcome
        }
    }

    public var duration: TimeInterval { finishedAt.timeIntervalSince(startedAt) }
}
