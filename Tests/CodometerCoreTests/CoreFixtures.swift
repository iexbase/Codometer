import CodometerCore
import Foundation

/// Shared builders for the release-2 domain tests.
enum Fixture {
    static let now = Date(timeIntervalSince1970: 1_789_600_000)

    static func window(
        _ id: String,
        _ scope: LimitWindowScope = .rolling,
        used: Double,
        minutes: Int? = 300,
        resetsIn seconds: TimeInterval? = 3_600,
        label: String? = nil
    ) throws -> LimitWindow {
        try LimitWindow(
            id: id,
            scope: scope,
            used: try Percentage(validating: used),
            duration: try minutes.map { try WindowDuration(minutes: $0) },
            resetsAt: seconds.map { now.addingTimeInterval($0) },
            label: label
        )
    }

    static func bucket(_ id: String, _ windows: [LimitWindow], limitReached: Bool = false) throws -> LimitBucket {
        try LimitBucket(id: id, title: nil, windows: windows, isLimitReached: limitReached)
    }

    static func reading(_ buckets: [LimitBucket], at date: Date = now) throws -> UsageReading {
        try UsageReading(capturedAt: date, source: .claudeUsageCommand, buckets: buckets, credits: nil)
    }

    static func reading(_ windows: [LimitWindow], at date: Date = now) throws -> UsageReading {
        try reading([try bucket("main", windows)], at: date)
    }

    static func profile(
        _ provider: ProviderKind = .codex,
        path: String = "/tmp/.codex",
        label: String = "Codex",
        isEnabled: Bool = true,
        groupID: AccountGroupID? = nil
    ) throws -> AccountProfile {
        try AccountProfile(
            provider: provider,
            label: try AccountLabel(validating: label),
            directory: try ProfileDirectory(validating: path),
            isEnabled: isEnabled,
            groupID: groupID
        )
    }

    static func group(_ name: String, mutesSessions: Bool = false, mutesUsage: Bool = false) throws -> AccountGroup {
        AccountGroup(name: try AccountLabel(validating: name), mutesSessionAlerts: mutesSessions, mutesUsageAlerts: mutesUsage)
    }

    static func session(
        _ activity: AgentActivity,
        id: String = "s1",
        since: Date = now,
        lastTurn: TurnTiming? = nil,
        lastEventAt: Date? = nil
    ) throws -> AgentSession {
        try AgentSession(
            id: id,
            title: "project",
            projectPath: "/tmp/project",
            activity: activity,
            detail: nil,
            activitySince: since,
            processID: nil,
            lastTurn: lastTurn,
            lastEventAt: lastEventAt
        )
    }

    static func tokens(
        input: Int64 = 0,
        cachedInput: Int64 = 0,
        cacheWrite: Int64 = 0,
        output: Int64 = 0,
        reasoningOutput: Int64 = 0
    ) throws -> TokenCounts {
        try TokenCounts(
            input: input,
            cachedInput: cachedInput,
            cacheWrite: cacheWrite,
            output: output,
            reasoningOutput: reasoningOutput
        )
    }
}
