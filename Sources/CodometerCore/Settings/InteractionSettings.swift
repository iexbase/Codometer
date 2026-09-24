import Foundation

/// What opens the island's deck.
public enum IslandOpenTrigger: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Hovering over the rail opens the deck; leaving it closes the deck.
    case hover
    /// A click opens the deck; a click outside or Esc closes it.
    case click
    /// Hover opens the deck, a click pins it open.
    case hoverOrClick

    public var id: String { rawValue }
}

/// How account e-mail addresses are shown on screen and in notifications.
public enum EmailVisibility: String, Codable, Sendable, CaseIterable, Identifiable {
    case visible
    /// `e••••e@test.com`
    case masked
    case hidden

    public var id: String { rawValue }
}

/// The system-wide key combination that toggles the deck.
public enum GlobalShortcut: String, Codable, Sendable, CaseIterable, Identifiable {
    case off
    /// ⌃⌥⌘U
    case controlOptionCommandU
    /// ⌃⌥Space
    case controlOptionSpace
    /// ⌃⌥⌘L
    case controlOptionCommandL

    public var id: String { rawValue }
}

/// "Agent finished" notifications are skipped for turns shorter than this: 0–600 seconds, 0 notifies always.
public struct TurnAlertThreshold: Hashable, Sendable, Comparable {
    public static let allowedSeconds: ClosedRange<Int> = 0...600

    public let seconds: Int

    public init(seconds: Int) throws(ValidationError) {
        guard Self.allowedSeconds.contains(seconds) else {
            throw .outOfRange(
                field: "alerts.minimumTurnForFinishedAlert",
                value: Double(seconds),
                lowerBound: Double(Self.allowedSeconds.lowerBound),
                upperBound: Double(Self.allowedSeconds.upperBound)
            )
        }
        self.seconds = seconds
    }

    private init(trustedSeconds: Int) {
        seconds = trustedSeconds
    }

    public static let standard = TurnAlertThreshold(trustedSeconds: 20)
    public static let always = TurnAlertThreshold(trustedSeconds: 0)

    public var timeInterval: TimeInterval { TimeInterval(seconds) }

    /// Whether a finished turn of this length is too short to notify about.
    public func suppresses(turnDuration: TimeInterval) -> Bool {
        seconds > 0 && turnDuration < timeInterval
    }

    public static func < (lhs: TurnAlertThreshold, rhs: TurnAlertThreshold) -> Bool { lhs.seconds < rhs.seconds }
}

extension TurnAlertThreshold: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try Int(from: decoder)
        do throws(ValidationError) {
            self = try TurnAlertThreshold(seconds: raw)
        } catch {
            throw error.decodingError(at: decoder.codingPath)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        try seconds.encode(to: encoder)
    }
}

/// How much the island (and the menu bar popover) shows once it opens.
public enum DeckDetail: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Every limit with what is used, what is left and the reset; no chart, no sessions, no timeline.
    case essentials
    /// The full page: hero chart, pace, sessions, the timeline and "who used the limit".
    case full

    public var id: String { rawValue }
}
