/// A usage percentage on the 0–100 scale.
///
/// Values above 100 are legal (a limit can be overdrawn) up to a sanity bound that
/// rejects garbage such as a fraction mistaken for a percentage multiplied twice.
public struct Percentage: Hashable, Comparable, Sendable {
    public static let upperSanityBound: Double = 1_000

    public let value: Double

    public init(validating value: Double, field: String = "percentage") throws(ValidationError) {
        guard value.isFinite else { throw .notFinite(field: field) }
        guard value >= 0, value <= Self.upperSanityBound else {
            throw .outOfRange(field: field, value: value, lowerBound: 0, upperBound: Self.upperSanityBound)
        }
        self.value = value
    }

    private init(trusted value: Double) {
        self.value = value
    }

    public static let zero = Percentage(trusted: 0)
    public static let full = Percentage(trusted: 100)

    /// 0.0 for 0 %, 1.0 for 100 %, unclamped.
    public var fraction: Double { value / 100 }

    /// The fraction clamped to 0...1, for drawing arcs and bars.
    public var clampedFraction: Double { min(max(value / 100, 0), 1) }

    /// Percentage points left before the limit, never negative.
    public var remaining: Double { max(0, 100 - value) }

    public var isExhausted: Bool { value >= 100 }

    public static func < (lhs: Percentage, rhs: Percentage) -> Bool {
        lhs.value < rhs.value
    }
}

extension Percentage: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try Double(from: decoder)
        do throws(ValidationError) {
            self = try Percentage(validating: raw)
        } catch {
            throw error.decodingError(at: decoder.codingPath)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        try value.encode(to: encoder)
    }
}
