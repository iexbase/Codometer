import Foundation

/// How many days of usage history are kept: 7–90 (weekly windows need at least a week).
public struct HistoryRetention: Hashable, Sendable, Comparable, CustomStringConvertible {
    public static let allowedDays: ClosedRange<Int> = 7...90

    public let days: Int

    public init(days: Int) throws(ValidationError) {
        guard Self.allowedDays.contains(days) else {
            throw .outOfRange(
                field: "general.historyRetention",
                value: Double(days),
                lowerBound: Double(Self.allowedDays.lowerBound),
                upperBound: Double(Self.allowedDays.upperBound)
            )
        }
        self.days = days
    }

    private init(trustedDays: Int) {
        days = trustedDays
    }

    /// Five weeks, the retention of earlier releases.
    public static let standard = HistoryRetention(trustedDays: 35)

    /// The picker's choices: 1 week, 2 weeks, 5 weeks, 3 months. A hand-edited value in range is shown as custom.
    public static let choices: [HistoryRetention] = [7, 14, 35, 90].map { HistoryRetention(trustedDays: $0) }

    public var timeInterval: TimeInterval { TimeInterval(days) * 86_400 }

    public var description: String { "\(days)d" }

    public static func < (lhs: HistoryRetention, rhs: HistoryRetention) -> Bool { lhs.days < rhs.days }
}

extension HistoryRetention: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try Int(from: decoder)
        do throws(ValidationError) {
            self = try HistoryRetention(days: raw)
        } catch {
            throw error.decodingError(at: decoder.codingPath)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        try days.encode(to: encoder)
    }
}
