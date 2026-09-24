import Foundation

/// Signs that a provider's output no longer matches what this version expects.
public struct FormatDrift: Hashable, Sendable {
    public static let maximumTitles = 3
    public static let maximumTitleLength = 60

    /// How much the drift matters to the user.
    public enum Severity: String, Sendable, CaseIterable, Comparable {
        case none
        /// Something unfamiliar was seen; readings still work.
        case note
        /// Claude refreshes are paused until the user refreshes by hand.
        case paused

        private var rank: Int {
            switch self {
            case .none: 0
            case .note: 1
            case .paused: 2
            }
        }

        public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rank < rhs.rank }
    }

    /// Titles of Claude limit windows without a known meaning (provider UI text, never conversation), at most three,
    /// each sanitised to 60 characters.
    public var unknownClaudeWindowTitles: [String] {
        didSet { unknownClaudeWindowTitles = Self.boundedTitles(unknownClaudeWindowTitles) }
    }
    public var droppedInvalidLimitLines: Int
    public var consecutiveOutputsWithoutLimits: Int
    public var pausedUntilManualRefresh: Bool
    /// A count only; event names are not kept.
    public var codexUnknownEventTypes: Int
    public var codexOversizedLinesSkipped: Int
    public var codexUnexpectedResponses: Int
    public var lastDriftAt: Date?

    public init(
        unknownClaudeWindowTitles: [String] = [],
        droppedInvalidLimitLines: Int = 0,
        consecutiveOutputsWithoutLimits: Int = 0,
        pausedUntilManualRefresh: Bool = false,
        codexUnknownEventTypes: Int = 0,
        codexOversizedLinesSkipped: Int = 0,
        codexUnexpectedResponses: Int = 0,
        lastDriftAt: Date? = nil
    ) {
        self.unknownClaudeWindowTitles = Self.boundedTitles(unknownClaudeWindowTitles)
        self.droppedInvalidLimitLines = max(0, droppedInvalidLimitLines)
        self.consecutiveOutputsWithoutLimits = max(0, consecutiveOutputsWithoutLimits)
        self.pausedUntilManualRefresh = pausedUntilManualRefresh
        self.codexUnknownEventTypes = max(0, codexUnknownEventTypes)
        self.codexOversizedLinesSkipped = max(0, codexOversizedLinesSkipped)
        self.codexUnexpectedResponses = max(0, codexUnexpectedResponses)
        self.lastDriftAt = lastDriftAt
    }

    public static let empty = FormatDrift()

    /// `paused` while refreshes wait for a manual refresh; `note` for unknown window titles, dropped limit lines,
    /// outputs without limits or unexpected Codex responses; otherwise `none`. Unknown Codex event types and skipped
    /// oversized lines are routine counters (new event types appear often) and never raise the severity alone.
    public var severity: Severity {
        if pausedUntilManualRefresh { return .paused }
        let noticed = !unknownClaudeWindowTitles.isEmpty
            || droppedInvalidLimitLines > 0
            || consecutiveOutputsWithoutLimits > 0
            || codexUnexpectedResponses > 0
        return noticed ? .note : .none
    }

    private static func boundedTitles(_ titles: [String]) -> [String] {
        var result: [String] = []
        for title in titles {
            guard result.count < maximumTitles else { break }
            guard let clean = DisplayText.sanitize(title, maximumLength: maximumTitleLength), !result.contains(clean) else { continue }
            result.append(clean)
        }
        return result
    }
}
