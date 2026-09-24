import Foundation

/// One stored observation of a window's usage.
public struct UsagePoint: Hashable, Sendable {
    public let at: Date
    /// Percent used on the 0–100 scale; overdrawn windows go above 100.
    public let used: Double

    public init(at: Date, used: Double) throws(ValidationError) {
        guard used.isFinite else { throw .notFinite(field: "usage.used") }
        guard used >= 0, used <= Percentage.upperSanityBound else {
            throw .outOfRange(field: "usage.used", value: used, lowerBound: 0, upperBound: Percentage.upperSanityBound)
        }
        self.at = at
        self.used = used
    }
}

/// The recorded usage of one window of one account over a time range.
public struct HistorySeries: Hashable, Sendable {
    public let accountID: AccountID
    public let bucketID: String
    public let windowID: String
    /// Observations in ascending time order; only the current window period when requested so.
    public let points: [UsagePoint]
    /// Detected window resets inside the range, ascending.
    public let resets: [Date]

    /// Points and resets are put in ascending order, so callers may pass them in any order.
    public init(accountID: AccountID, bucketID: String, windowID: String, points: [UsagePoint], resets: [Date]) {
        self.accountID = accountID
        self.bucketID = bucketID
        self.windowID = windowID
        self.points = points.enumerated()
            .sorted { lhs, rhs in lhs.element.at == rhs.element.at ? lhs.offset < rhs.offset : lhs.element.at < rhs.element.at }
            .map(\.element)
        self.resets = resets.sorted()
    }

    public var isEmpty: Bool { points.isEmpty }
}
