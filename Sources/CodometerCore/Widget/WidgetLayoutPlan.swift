import Foundation

/// How the large widget fits its accounts into a fixed height.
///
/// Every account first gets its summary row, most constrained accounts first; accounts that do not fit are counted
/// in an "N more accounts" footer. The remaining height is shared out as window rows one round at a time, in settings
/// order, so accounts end up with equal row counts (earlier accounts get the extra one) and nothing ever overflows.
public struct WidgetLayoutPlan: Hashable, Sendable {
    public struct Metrics: Hashable, Sendable {
        public var availableHeight: Double
        public var accountHeight: Double
        public var accountSpacing: Double
        /// Space between an account's summary row and its first window row.
        public var rowsInset: Double
        public var rowHeight: Double
        public var rowSpacing: Double
        public var footerHeight: Double

        public init(
            availableHeight: Double,
            accountHeight: Double,
            accountSpacing: Double,
            rowsInset: Double,
            rowHeight: Double,
            rowSpacing: Double,
            footerHeight: Double
        ) {
            self.availableHeight = availableHeight
            self.accountHeight = accountHeight
            self.accountSpacing = accountSpacing
            self.rowsInset = rowsInset
            self.rowHeight = rowHeight
            self.rowSpacing = rowSpacing
            self.footerHeight = footerHeight
        }
    }

    public struct Entry: Hashable, Sendable {
        /// Index into the planned accounts.
        public let index: Int
        public let rowCount: Int

        public init(index: Int, rowCount: Int) {
            self.index = index
            self.rowCount = rowCount
        }
    }

    /// Visible accounts in their original order.
    public let entries: [Entry]
    public let hiddenCount: Int

    /// - Parameters:
    ///   - rowCounts: how many window rows each account could show, in settings order.
    ///   - priority: account indices, most important first; indices missing from it are appended in order.
    public init(rowCounts: [Int], priority: [Int], metrics: Metrics) {
        let count = rowCounts.count
        var order = priority.filter { rowCounts.indices.contains($0) }
        var seen = Set<Int>()
        order = order.filter { seen.insert($0).inserted }
        order += rowCounts.indices.filter { !seen.contains($0) }

        var visibleCount = 0
        for candidate in stride(from: count, through: 0, by: -1) {
            if Self.summaryHeight(accounts: candidate, total: count, metrics: metrics) <= metrics.availableHeight {
                visibleCount = candidate
                break
            }
        }
        let visible = order.prefix(visibleCount).sorted()
        var used = Self.summaryHeight(accounts: visibleCount, total: count, metrics: metrics)
        var rows = Array(repeating: 0, count: visible.count)

        var addedInRound = true
        while addedInRound {
            addedInRound = false
            for (slot, index) in visible.enumerated() where rows[slot] < max(0, rowCounts[index]) {
                let cost = metrics.rowHeight + (rows[slot] == 0 ? metrics.rowsInset : metrics.rowSpacing)
                guard used + cost <= metrics.availableHeight else {
                    addedInRound = false
                    break
                }
                rows[slot] += 1
                used += cost
                addedInRound = true
            }
        }

        entries = visible.enumerated().map { Entry(index: $0.element, rowCount: rows[$0.offset]) }
        hiddenCount = count - visibleCount
    }

    /// Whether every account and every one of its rows made it in.
    public func showsEverything(rowCounts: [Int]) -> Bool {
        hiddenCount == 0 && entries.allSatisfy { entry in
            rowCounts.indices.contains(entry.index) && entry.rowCount == max(0, rowCounts[entry.index])
        }
    }

    static func summaryHeight(accounts: Int, total: Int, metrics: Metrics) -> Double {
        guard accounts > 0 else { return total > 0 ? metrics.footerHeight : 0 }
        var height = Double(accounts) * metrics.accountHeight + Double(accounts - 1) * metrics.accountSpacing
        if accounts < total {
            height += metrics.accountSpacing + metrics.footerHeight
        }
        return height
    }
}
