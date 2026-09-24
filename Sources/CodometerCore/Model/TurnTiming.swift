import Foundation

/// Where a session runs: the terminal CLI or a desktop app.
public enum SessionOrigin: String, Sendable, Codable, CaseIterable {
    case terminal
    case desktopApp
    case unknown
}

/// How long one agent turn took: from the prompt to the end of the reply (or the abort).
public struct TurnTiming: Hashable, Sendable {
    /// Turns this long or longer are not real turns but clock or parsing errors.
    public static let maximumDuration: TimeInterval = 24 * 60 * 60

    public let startedAt: Date
    public let endedAt: Date
    /// Wall-clock length of the turn, `0 < duration < 24 h`.
    public let duration: TimeInterval
    /// Time from the start of the turn to the first streamed token, when the source reports it.
    public let firstTokenLatency: TimeInterval?
    /// The user interrupted the turn.
    public let wasAborted: Bool

    public init(
        startedAt: Date,
        endedAt: Date,
        duration: TimeInterval,
        firstTokenLatency: TimeInterval?,
        wasAborted: Bool
    ) throws(ValidationError) {
        guard endedAt >= startedAt else {
            throw .inconsistent(field: "turn.endedAt", reason: "a turn cannot end before it starts")
        }
        guard duration.isFinite else { throw .notFinite(field: "turn.duration") }
        guard duration > 0, duration < Self.maximumDuration else {
            throw .outOfRange(field: "turn.duration", value: duration, lowerBound: 0, upperBound: Self.maximumDuration)
        }
        if let firstTokenLatency {
            guard firstTokenLatency.isFinite else { throw .notFinite(field: "turn.firstTokenLatency") }
            guard firstTokenLatency >= 0, firstTokenLatency <= duration else {
                throw .outOfRange(
                    field: "turn.firstTokenLatency",
                    value: firstTokenLatency,
                    lowerBound: 0,
                    upperBound: duration
                )
            }
        }
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.duration = duration
        self.firstTokenLatency = firstTokenLatency
        self.wasAborted = wasAborted
    }
}
