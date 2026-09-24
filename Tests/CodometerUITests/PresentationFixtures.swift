import CodometerCore
@testable import CodometerUI
import Foundation

/// Shared builders for the presentation-layer tests.
enum UIFixture {
    static let now = Date(timeIntervalSince1970: 1_789_600_000)

    static func window(
        _ id: String,
        _ scope: LimitWindowScope = .rolling,
        used: Double,
        duration: WindowDuration? = .fiveHours,
        resetsIn seconds: TimeInterval? = 3_600,
        label: String? = nil
    ) throws -> LimitWindow {
        try LimitWindow(
            id: id,
            scope: scope,
            used: try Percentage(validating: used),
            duration: duration,
            resetsAt: seconds.map { now.addingTimeInterval($0) },
            label: label
        )
    }

    static func bucket(_ id: String, title: String? = nil, _ windows: [LimitWindow], limitReached: Bool = false) throws -> LimitBucket {
        try LimitBucket(id: id, title: title, windows: windows, isLimitReached: limitReached)
    }

    static func reading(_ buckets: [LimitBucket], capturedAgo: TimeInterval = 60) throws -> UsageReading {
        try UsageReading(capturedAt: now.addingTimeInterval(-capturedAgo), source: .claudeUsageCommand, buckets: buckets, credits: nil)
    }

    /// The account's id is derived from its provider and label, never minted: `AccountStyleResolver` seeds an
    /// automatic tint with a hash of the id, so a random one would paint the same surface a different colour in
    /// every run — and in the English and the Russian pass of the same gated render, which are compared side by side.
    /// Pass `id` when one fixture needs two accounts that agree on provider and label.
    static func profile(
        _ label: String,
        provider: ProviderKind = .claude,
        isEnabled: Bool = true,
        group: AccountGroup? = nil,
        tint: AccountTint = .automatic,
        monogram: AccountMonogram? = nil,
        id: AccountID? = nil
    ) throws -> AccountProfile {
        try AccountProfile(
            id: id ?? accountID("\(provider.rawValue)/\(label)"),
            provider: provider,
            label: try AccountLabel(validating: label),
            directory: try ProfileDirectory(validating: "/Users/me/.\(provider.rawValue)-\(label.lowercased())"),
            isEnabled: isEnabled,
            groupID: group?.id,
            tint: tint,
            monogram: monogram
        )
    }

    /// Named like `profile`, the group's id comes from its name so a rail filtered by group renders the same twice.
    static func group(_ name: String, id: AccountGroupID? = nil) throws -> AccountGroup {
        AccountGroup(id: id ?? groupID(name), name: try AccountLabel(validating: name))
    }

    /// A stable `AccountID` for `seed`: the same seed is the same account in every process, so automatic tints and
    /// anything else keyed by the id are reproducible.
    static func accountID(_ seed: String) -> AccountID {
        AccountID(rawValue: uuid(seed))
    }

    /// A stable `AccountGroupID` for `seed`, for the same reason as `accountID`.
    static func groupID(_ seed: String) -> AccountGroupID {
        AccountGroupID(rawValue: uuid(seed))
    }

    /// A version-4-shaped UUID whose bytes are two 64-bit FNV-1a hashes of `seed` (the hash `AccountStyleResolver`
    /// itself uses; never `Hasher`, which is seeded per process).
    private static func uuid(_ seed: String) -> UUID {
        let bytes = Array(seed.utf8)
        let first = fnv1a(bytes, offset: 0xCBF2_9CE4_8422_2325).bigEndian
        let second = fnv1a([0x2E] + bytes, offset: 0x8422_2325_CBF2_9CE4).bigEndian
        var raw = withUnsafeBytes(of: first) { Array($0) } + withUnsafeBytes(of: second) { Array($0) }
        raw[6] = (raw[6] & 0x0F) | 0x40
        raw[8] = (raw[8] & 0x3F) | 0x80
        return UUID(uuid: (
            raw[0], raw[1], raw[2], raw[3], raw[4], raw[5], raw[6], raw[7],
            raw[8], raw[9], raw[10], raw[11], raw[12], raw[13], raw[14], raw[15]
        ))
    }

    private static func fnv1a(_ bytes: [UInt8], offset: UInt64) -> UInt64 {
        var hash = offset
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    static func session(_ id: String, _ activity: AgentActivity, since secondsAgo: TimeInterval = 60) throws -> AgentSession {
        try AgentSession(
            id: id,
            title: id,
            projectPath: "/Users/me/\(id)",
            activity: activity,
            detail: nil,
            activitySince: now.addingTimeInterval(-secondsAgo),
            processID: nil
        )
    }

    static func turn(duration: TimeInterval, firstToken: TimeInterval? = nil, aborted: Bool = false) throws -> TurnTiming {
        try TurnTiming(
            startedAt: now.addingTimeInterval(-duration),
            endedAt: now,
            duration: duration,
            firstTokenLatency: firstToken,
            wasAborted: aborted
        )
    }

    @MainActor
    static func actions(
        loadWindowHistory: @escaping @MainActor (AccountID, String, String, Date) async -> HistorySeries? = { _, _, _, _ in nil },
        loadTimeline: @escaping @MainActor (AccountID, DateInterval) async -> TimelineSnapshot? = { _, _ in nil },
        loadAttribution: @escaping @MainActor (AccountID, DateInterval, AttributionGrouping) async -> AttributionReport? = { _, _, _ in nil }
    ) -> TrackerActions {
        TrackerActions(
            refresh: { _ in },
            persistSettings: { _ in },
            discoverProfiles: { [] },
            revealDataFolder: {},
            setLaunchAtLogin: { _ in nil },
            openSettings: {},
            quit: {},
            loadWindowHistory: loadWindowHistory,
            loadTimeline: loadTimeline,
            loadAttribution: loadAttribution
        )
    }
}
