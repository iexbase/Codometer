import Foundation

/// How badly a vendor's service is affected, from its public status page. Ordered from least to most severe.
public enum ServiceStatusLevel: String, Sendable, CaseIterable, Comparable {
    case maintenance
    case degraded
    case partialOutage
    case majorOutage

    private var rank: Int {
        switch self {
        case .maintenance: 0
        case .degraded: 1
        case .partialOutage: 2
        case .majorOutage: 3
        }
    }

    public static func < (lhs: ServiceStatusLevel, rhs: ServiceStatusLevel) -> Bool { lhs.rank < rhs.rank }
}

/// The latest status check of one vendor (in memory only, never persisted).
public struct ServiceStatus: Hashable, Sendable {
    public static let maximumComponents = 3
    public static let maximumComponentLength = 60

    public let provider: ProviderKind
    /// `nil`: the components Codometer watches are fine.
    public let level: ServiceStatusLevel?
    /// Affected component names, at most three, sanitised to 60 characters.
    public let affectedComponents: [String]
    public let checkedAt: Date

    public init(provider: ProviderKind, level: ServiceStatusLevel?, affectedComponents: [String], checkedAt: Date) {
        self.provider = provider
        self.level = level
        var names: [String] = []
        for name in affectedComponents {
            guard names.count < Self.maximumComponents else { break }
            guard let clean = DisplayText.sanitize(name, maximumLength: Self.maximumComponentLength), !names.contains(clean) else { continue }
            names.append(clean)
        }
        self.affectedComponents = names
        self.checkedAt = checkedAt
    }

    /// The vendor's public status page (fixed URLs, opened in the browser).
    public var statusPageURL: URL {
        switch provider {
        case .claude: Self.claudeStatusPage
        case .codex: Self.openAIStatusPage
        }
    }

    private static let claudeStatusPage = URL(string: "https://status.claude.com") ?? URL(filePath: "/")
    private static let openAIStatusPage = URL(string: "https://status.openai.com") ?? URL(filePath: "/")
}

/// Every vendor's latest status and failure time.
public struct ServiceStatusBoard: Hashable, Sendable {
    /// Older checks are not shown.
    public static let maximumAge: TimeInterval = 30 * 60
    public static let empty = ServiceStatusBoard()

    public var statuses: [ProviderKind: ServiceStatus]
    public var lastFailureAt: [ProviderKind: Date]

    public init(statuses: [ProviderKind: ServiceStatus] = [:], lastFailureAt: [ProviderKind: Date] = [:]) {
        self.statuses = statuses
        self.lastFailureAt = lastFailureAt
    }

    /// The status to show for `provider`: checked at most 30 minutes before `now` and with a problem.
    public func visible(for provider: ProviderKind, now: Date) -> ServiceStatus? {
        guard
            let status = statuses[provider],
            status.level != nil,
            now.timeIntervalSince(status.checkedAt) <= Self.maximumAge
        else { return nil }
        return status
    }
}
