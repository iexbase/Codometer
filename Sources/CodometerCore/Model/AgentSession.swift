import Foundation

/// What a coding-agent session is doing right now.
public enum AgentActivity: String, Sendable, Codable, CaseIterable, Comparable {
    case idle
    case working
    /// Blocked on the user: a permission prompt, a question, an approval.
    case waiting

    /// Waiting outranks working, which outranks idle — the order the UI surfaces them in.
    private var priority: Int {
        switch self {
        case .idle: 0
        case .working: 1
        case .waiting: 2
        }
    }

    public static func < (lhs: AgentActivity, rhs: AgentActivity) -> Bool {
        lhs.priority < rhs.priority
    }
}

/// A live agent session belonging to an account.
///
/// Token counts are deliberately not part of a session: they change with every response and travel
/// separately as `TokenSample`s.
public struct AgentSession: Hashable, Sendable, Identifiable {
    public static let maximumTitleLength = 80
    public static let maximumDetailLength = 120
    public static let maximumModelLength = 60

    public let id: String
    public let title: String
    public let projectPath: String?
    public let activity: AgentActivity
    /// What the session waits for ("permission prompt"), when known.
    public let detail: String?
    /// When the session entered its current activity — used for "working for 3 min".
    public let activitySince: Date
    public let processID: Int32?
    /// Terminal CLI or desktop app.
    public let origin: SessionOrigin
    /// The model the session last used, sanitised; `nil` when unknown.
    public let model: String?
    /// The most recent completed or aborted turn, when known.
    public let lastTurn: TurnTiming?
    /// The last observed log or status activity, when known. Drives `SessionHealth.quiet`.
    public let lastEventAt: Date?

    public init(
        id: String,
        title: String?,
        projectPath: String?,
        activity: AgentActivity,
        detail: String?,
        activitySince: Date,
        processID: Int32?,
        origin: SessionOrigin = .unknown,
        model: String? = nil,
        lastTurn: TurnTiming? = nil,
        lastEventAt: Date? = nil
    ) throws(ValidationError) {
        guard let cleanID = DisplayText.sanitize(id, maximumLength: 128), cleanID == id else {
            throw .invalidCharacters(field: "session.id")
        }
        let folderName = projectPath.map { ($0 as NSString).lastPathComponent }
        self.id = id
        self.title = DisplayText.sanitize(title, maximumLength: Self.maximumTitleLength)
            ?? DisplayText.sanitize(folderName, maximumLength: Self.maximumTitleLength)
            ?? "—"
        self.projectPath = DisplayText.sanitize(projectPath, maximumLength: ProfileDirectory.maximumLength)
        self.activity = activity
        self.detail = DisplayText.sanitize(detail, maximumLength: Self.maximumDetailLength)
        self.activitySince = activitySince
        self.processID = processID
        self.origin = origin
        self.model = DisplayText.sanitize(model, maximumLength: Self.maximumModelLength)
        self.lastTurn = lastTurn
        self.lastEventAt = lastEventAt
    }

    /// The same session without turn timing, e.g. when the timing it carries belongs to an earlier turn.
    public func removingLastTurn() -> AgentSession {
        guard lastTurn != nil else { return self }
        return AgentSession(copying: self, lastTurn: nil)
    }

    /// Copies already validated values, so no validation can fail.
    private init(copying session: AgentSession, lastTurn: TurnTiming?) {
        id = session.id
        title = session.title
        projectPath = session.projectPath
        activity = session.activity
        detail = session.detail
        activitySince = session.activitySince
        processID = session.processID
        origin = session.origin
        model = session.model
        self.lastTurn = lastTurn
        lastEventAt = session.lastEventAt
    }
}
