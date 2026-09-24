import Foundation

/// A limit window that started a new period, detected between two readings.
public struct WindowResetEvent: Hashable, Sendable, Identifiable {
    public let accountID: AccountID
    public let bucketID: String
    public let windowID: String
    public let previousUsed: Percentage
    public let newUsed: Percentage
    public let detectedAt: Date

    public init(
        accountID: AccountID,
        bucketID: String,
        windowID: String,
        previousUsed: Percentage,
        newUsed: Percentage,
        detectedAt: Date
    ) throws(ValidationError) {
        self.accountID = accountID
        self.bucketID = try StableIdentifier.validate(bucketID, field: "reset.bucketID")
        self.windowID = try StableIdentifier.validate(windowID, field: "reset.windowID")
        self.previousUsed = previousUsed
        self.newUsed = newUsed
        self.detectedAt = detectedAt
    }

    /// `account/bucket/window/seconds`: the same reset seen twice in one second has one id.
    public var id: String {
        "\(accountID)/\(bucketID)/\(windowID)/\(Int(detectedAt.timeIntervalSince1970.rounded(.down)))"
    }
}

/// Detects limit resets. Notifications (`AlertEvaluator`) and the reset ceremony share one rule.
public enum ResetDetector {
    /// A new window period moves the reset at least this far; smaller moves are source precision noise.
    public static let resetShiftTolerance: TimeInterval = 30 * 60
    /// A drop this large also means the window was reset, for sources without reset times.
    public static let resetDropPoints = 20.0
    /// A ceremony needs something to celebrate: at least this much was used before the reset…
    public static let minimumCeremonyUsage = 5.0
    /// …and usage really dropped (reset-time jitter alone never celebrates).
    public static let minimumCeremonyDrop = 5.0

    /// The reset moved by more than 30 minutes, or, without reset times on both sides, usage dropped by 20 points or more.
    public static func isReset(from old: LimitWindow, to new: LimitWindow) -> Bool {
        if let oldReset = old.resetsAt, let newReset = new.resetsAt {
            return newReset.timeIntervalSince(oldReset) > resetShiftTolerance
        }
        return old.used.value - new.used.value >= resetDropPoints
    }

    /// Resets worth a ceremony between two states: only accounts present in both, only when the new reading is newer,
    /// every bucket and window. Alert settings and group mutes are ignored.
    public static func resets(from previous: TrackerState, to current: TrackerState, at now: Date) -> [WindowResetEvent] {
        current.accounts.flatMap { account -> [WindowResetEvent] in
            guard
                let oldReading = previous.account(account.id)?.reading,
                let newReading = account.reading,
                newReading.capturedAt > oldReading.capturedAt
            else { return [] }
            return newReading.buckets.flatMap { bucket in
                bucket.windows.compactMap { window -> WindowResetEvent? in
                    guard
                        let oldWindow = oldReading.bucket(id: bucket.id)?.window(id: window.id),
                        isReset(from: oldWindow, to: window),
                        oldWindow.used.value >= minimumCeremonyUsage,
                        oldWindow.used.value - window.used.value >= minimumCeremonyDrop
                    else { return nil }
                    return try? WindowResetEvent(
                        accountID: account.id,
                        bucketID: bucket.id,
                        windowID: window.id,
                        previousUsed: oldWindow.used,
                        newUsed: window.used,
                        detectedAt: now
                    )
                }
            }
        }
    }
}
