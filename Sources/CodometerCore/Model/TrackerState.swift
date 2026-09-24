import Foundation

/// Why the latest refresh of an account did not produce a reading.
public struct TrackerIssue: Hashable, Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        /// The provider's CLI is not installed where the app looks for it.
        case executableMissing
        /// A binary was found but its code signature is not from the expected publisher.
        case executableUntrusted
        /// The profile is not signed in.
        case signedOut
        /// The provider answered in a format this version does not understand.
        case unexpectedOutput
        /// The CLI or server exited with an error.
        case commandFailed
        case timedOut
        /// The profile directory does not exist.
        case profileMissing
        case offline
        case internalFailure
    }

    public static let maximumDetailLength = 300

    public let kind: Kind
    /// Technical detail for logs and tooltips. Never contains credentials.
    public let detail: String
    public let occurredAt: Date

    public init(kind: Kind, detail: String, occurredAt: Date) {
        self.kind = kind
        self.detail = DisplayText.sanitize(detail, maximumLength: Self.maximumDetailLength) ?? kind.rawValue
        self.occurredAt = occurredAt
    }
}

/// How current an account's reading is.
public enum ReadingFreshness: Hashable, Sendable {
    case missing
    case fresh
    case stale(since: Date)
}

/// Everything the UI shows for one account.
public struct AccountStatus: Hashable, Sendable, Identifiable {
    /// A reading older than this is drawn dimmed. Longer than any poll interval so one missed poll is not flagged.
    public static let defaultStaleAfter: TimeInterval = 15 * 60

    public var profile: AccountProfile
    public var identity: AccountIdentity?
    public var reading: UsageReading?
    public var issue: TrackerIssue?
    public var isRefreshing: Bool
    public var lastAttemptAt: Date?
    public var nextRefreshAt: Date?
    public var sessions: [AgentSession]

    public init(
        profile: AccountProfile,
        identity: AccountIdentity? = nil,
        reading: UsageReading? = nil,
        issue: TrackerIssue? = nil,
        isRefreshing: Bool = false,
        lastAttemptAt: Date? = nil,
        nextRefreshAt: Date? = nil,
        sessions: [AgentSession] = []
    ) {
        self.profile = profile
        self.identity = identity
        self.reading = reading
        self.issue = issue
        self.isRefreshing = isRefreshing
        self.lastAttemptAt = lastAttemptAt
        self.nextRefreshAt = nextRefreshAt
        self.sessions = sessions
    }

    public var id: AccountID { profile.id }

    public func freshness(at now: Date, staleAfter: TimeInterval = defaultStaleAfter) -> ReadingFreshness {
        guard let reading else { return .missing }
        if reading.containsExpiredWindow(at: now) || now.timeIntervalSince(reading.capturedAt) > staleAfter {
            return .stale(since: reading.capturedAt)
        }
        return .fresh
    }

    /// The most urgent activity across the account's sessions.
    public var dominantActivity: AgentActivity? {
        sessions.map(\.activity).max()
    }
}

/// The complete observable state of the tracker.
public struct TrackerState: Hashable, Sendable {
    public var accounts: [AccountStatus]

    public init(accounts: [AccountStatus] = []) {
        self.accounts = accounts
    }

    public static let empty = TrackerState()

    public func account(_ id: AccountID) -> AccountStatus? {
        accounts.first { $0.id == id }
    }
}
