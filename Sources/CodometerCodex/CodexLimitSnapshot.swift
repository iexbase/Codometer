import CodometerCore
import Foundation

/// Codex rate limits for one metered bucket, independent of whether they came from a session log
/// (snake_case) or from `codex app-server` (camelCase).
public struct CodexLimitSnapshot: Hashable, Sendable {
    public struct Window: Hashable, Sendable {
        public let usedPercent: Double
        public let durationMinutes: Int?
        public let resetsAt: Date?

        public init(usedPercent: Double, durationMinutes: Int?, resetsAt: Date?) {
            self.usedPercent = usedPercent
            self.durationMinutes = durationMinutes
            self.resetsAt = resetsAt
        }
    }

    public let limitID: String?
    public let limitName: String?
    public let primary: Window?
    public let secondary: Window?
    public let credits: CreditsInfo?
    public let planType: String?
    public let isLimitReached: Bool

    public init(
        limitID: String?,
        limitName: String?,
        primary: Window?,
        secondary: Window?,
        credits: CreditsInfo?,
        planType: String?,
        isLimitReached: Bool
    ) {
        self.limitID = limitID
        self.limitName = limitName
        self.primary = primary
        self.secondary = secondary
        self.credits = credits
        self.planType = planType
        self.isLimitReached = isLimitReached
    }

    public func markingLimitReached() -> CodexLimitSnapshot {
        CodexLimitSnapshot(
            limitID: limitID,
            limitName: limitName,
            primary: primary,
            secondary: secondary,
            credits: credits,
            planType: planType,
            isLimitReached: true
        )
    }

    /// The bucket id used in readings: the backend's `limit_id`, made safe, defaulting to `codex`.
    public var bucketID: String {
        guard let limitID, !limitID.isEmpty else { return CodexLimitMapper.mainBucketID }
        let safe = String(limitID.unicodeScalars.prefix(StableIdentifier.maximumLength).map { scalar -> Character in
            let allowed = scalar.isASCII
                && (CharacterSet.alphanumerics.contains(scalar) || scalar == "." || scalar == "_" || scalar == "-")
            return allowed ? Character(scalar) : "_"
        })
        return safe
    }
}

public enum CodexLimitMapper {
    public static let mainBucketID = "codex"

    /// Turns snapshots into a reading. Windows with invalid values are dropped individually;
    /// the reading is `nil` only when nothing usable remains.
    public static func reading(
        from snapshots: [CodexLimitSnapshot],
        capturedAt: Date,
        source: ReadingSource
    ) -> UsageReading? {
        var buckets: [LimitBucket] = []
        var seen = Set<String>()
        for snapshot in snapshots {
            let id = snapshot.bucketID
            guard !seen.contains(id), let bucket = bucket(from: snapshot) else { continue }
            seen.insert(id)
            buckets.append(bucket)
        }
        buckets.sort { lhs, rhs in
            if lhs.id == mainBucketID { return rhs.id != mainBucketID }
            if rhs.id == mainBucketID { return false }
            return lhs.id < rhs.id
        }
        guard !buckets.isEmpty else { return nil }
        let credits = snapshots.first { $0.limitID == mainBucketID || $0.limitID == nil }?.credits
            ?? snapshots.first?.credits
        return try? UsageReading(
            capturedAt: capturedAt,
            source: source,
            buckets: Array(buckets.prefix(UsageReading.maximumBuckets)),
            credits: credits
        )
    }

    public static func bucket(from snapshot: CodexLimitSnapshot) -> LimitBucket? {
        let windows = [("primary", snapshot.primary), ("secondary", snapshot.secondary)]
            .compactMap { id, window in window.flatMap { limitWindow(id: id, from: $0) } }
        guard !windows.isEmpty else { return nil }
        return try? LimitBucket(
            id: snapshot.bucketID,
            title: snapshot.limitName,
            windows: windows,
            isLimitReached: snapshot.isLimitReached
        )
    }

    /// "pro" → "Pro", "self_serve_business_prolite" → "Self Serve Business Prolite".
    public static func planName(_ planType: String?) -> String? {
        guard let planType, planType != "unknown", !planType.isEmpty else { return nil }
        return planType.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    private static func limitWindow(id: String, from window: CodexLimitSnapshot.Window) -> LimitWindow? {
        guard let used = try? Percentage(validating: window.usedPercent, field: "codex.\(id).used") else {
            return nil
        }
        let duration = window.durationMinutes.flatMap { try? WindowDuration(minutes: $0) }
        return try? LimitWindow(id: id, scope: .rolling, used: used, duration: duration, resetsAt: window.resetsAt)
    }
}
