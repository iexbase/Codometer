import Foundation

/// A stretch of time one session spent working or waiting.
public struct SessionSegment: Hashable, Sendable, Identifiable {
    public let accountID: AccountID
    public let sessionID: String
    /// The segment's label, sanitised like `AgentSession.title`. Recorded segments use `SessionLabel.neutral`
    /// («Codometer · 3f9a1c»), never the session's own title, which can carry conversation content.
    public let title: String
    /// The session's project folder, sanitised (recorded segments never keep the full path).
    public let project: String?
    /// `.working` or `.waiting`; idle time is never recorded.
    public let activity: AgentActivity
    public let start: Date
    /// `nil` while the segment is still open.
    public let end: Date?

    public init(
        accountID: AccountID,
        sessionID: String,
        title: String?,
        project: String?,
        activity: AgentActivity,
        start: Date,
        end: Date?
    ) throws(ValidationError) {
        guard let cleanID = DisplayText.sanitize(sessionID, maximumLength: 128), cleanID == sessionID else {
            throw .invalidCharacters(field: "segment.sessionID")
        }
        guard activity != .idle else {
            throw .inconsistent(field: "segment.activity", reason: "only working and waiting time is recorded")
        }
        if let end, end < start {
            throw .inconsistent(field: "segment.end", reason: "a segment cannot end before it starts")
        }
        let cleanProject = DisplayText.sanitize(project, maximumLength: ProfileDirectory.maximumLength)
        let folderName = cleanProject.map { ($0 as NSString).lastPathComponent }
        self.accountID = accountID
        self.sessionID = sessionID
        self.title = DisplayText.sanitize(title, maximumLength: AgentSession.maximumTitleLength)
            ?? DisplayText.sanitize(folderName, maximumLength: AgentSession.maximumTitleLength)
            ?? "—"
        self.project = cleanProject
        self.activity = activity
        self.start = start
        self.end = end
    }

    /// Unique per segment: a session has at most one segment of an activity starting at a given millisecond.
    public var id: String {
        let startMilliseconds = Int64((start.timeIntervalSince1970 * 1_000).rounded())
        return "\(accountID)/\(sessionID)/\(activity.rawValue)/\(startMilliseconds)"
    }

    public var isOpen: Bool { end == nil }

    /// Length of the segment, counting an open segment up to `now`; never negative.
    public func duration(now: Date) -> TimeInterval {
        max(0, (end ?? now).timeIntervalSince(start))
    }
}

/// What one account's timeline shows: session lanes over the headline window's usage curve.
public struct TimelineSnapshot: Hashable, Sendable {
    public let accountID: AccountID
    public let interval: DateInterval
    /// Segments ordered by start time.
    public let segments: [SessionSegment]
    /// The headline primary window over the interval; may span resets.
    public let usage: HistorySeries?
    /// Where recorded data of the interval begins: when live collection began for the account (or the earliest
    /// segment start, if older), clamped into the interval, so it may equal the interval's end. Segments are
    /// collected live, so views show «данные с HH:mm» when this is later than the interval start; `nil` when
    /// neither is known.
    public let coverageStart: Date?
    /// Stretches inside the interval without collected data (app not running, Mac asleep, account off), ordered by
    /// start; see `CollectionGaps`.
    public let gaps: [CollectionGap]

    public init(
        accountID: AccountID,
        interval: DateInterval,
        segments: [SessionSegment],
        usage: HistorySeries?,
        coverageStart: Date? = nil,
        gaps: [CollectionGap] = []
    ) {
        self.accountID = accountID
        self.interval = interval
        self.segments = segments.sorted { lhs, rhs in lhs.start == rhs.start ? lhs.id < rhs.id : lhs.start < rhs.start }
        self.usage = usage
        self.coverageStart = coverageStart
        self.gaps = gaps.sorted { $0.interval.start < $1.interval.start }
    }
}
