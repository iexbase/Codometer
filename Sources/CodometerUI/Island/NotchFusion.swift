import CodometerCore
import CoreGraphics
import Foundation

/// How the rail's items are split around the camera notch.
public struct NotchWings: Equatable, Sendable {
    /// Indices of the accounts drawn left of the notch.
    public let left: Range<Int>
    /// Indices of the accounts drawn right of the notch.
    public let right: Range<Int>
    /// Accounts that fit in neither wing; shown as a "+N" chip at the end of the left wing.
    public let overflow: Int
    /// The attention tab ends the right wing.
    public let hasAttention: Bool

    public init(left: Range<Int>, right: Range<Int>, overflow: Int, hasAttention: Bool) {
        self.left = left
        self.right = right
        self.overflow = overflow
        self.hasAttention = hasAttention
    }

    public var showsOverflowChip: Bool { overflow > 0 }
}

/// What each wing of a fused rail draws besides its own dials.
public struct WingContents: Equatable, Sendable {
    /// The attention tab ends the left wing (only when the right one has no accounts to end).
    public let showsTabOnLeft: Bool
    /// The attention tab ends the right wing, as it normally does.
    public let showsTabOnRight: Bool
    /// The right wing draws `RailView`'s "no accounts" placeholder, because neither wing has an account.
    public let showsPlaceholder: Bool

    public init(showsTabOnLeft: Bool, showsTabOnRight: Bool, showsPlaceholder: Bool) {
        self.showsTabOnLeft = showsTabOnLeft
        self.showsTabOnRight = showsTabOnRight
        self.showsPlaceholder = showsPlaceholder
    }
}

/// Fusing the island with a MacBook's camera notch: when it happens, how the rail splits around the notch,
/// and how big its dials may be inside the menu bar.
///
/// Pure geometry. `NotchGeometry` itself (detection from `NSScreen`) lives in Core.
public enum NotchFusion {
    /// How close to the middle of the edge the island has to sit to fuse; the notch snap target lands exactly there.
    public static let centerTolerance: Double = 0.005
    /// Share of the narrower auxiliary menu bar area a wing may cover, so status items stay reachable.
    public static let wingShareOfAuxiliary: CGFloat = 0.45
    /// Clear space between a wing and the notch.
    public static let wingGap: CGFloat = 4
    /// The smallest a fused dial may become, whatever the menu bar height.
    public static let minimumDialDiameter: CGFloat = 14

    /// Whether the island should be drawn fused with the notch.
    ///
    /// Only with fusion on, on the top edge, attached, centred (within `centerTolerance`), on a display that has a
    /// notch, and not while the island is carried (a carried island is always a free capsule).
    public static func isFused(
        mode: NotchFusionMode,
        edge: ScreenEdge,
        style: IslandStyle,
        offset: Double,
        notch: NotchGeometry?,
        dragging: Bool
    ) -> Bool {
        guard mode == .automatic, edge == .top, style == .attached, notch != nil, !dragging else { return false }
        guard offset.isFinite else { return false }
        // The tolerance itself is a rounding allowance, so compare with a hair of slack of its own.
        return abs(offset - 0.5) <= centerTolerance + 1e-9
    }

    /// Ring diameter of a fused dial: the rail's own dial unless the menu bar is too shallow for it.
    ///
    /// On a 32 pt menu bar with a 4 pt orbit margin this is 22 pt.
    public static func dialDiameter(railDial: CGFloat, menuBarHeight: CGFloat, orbitMargin: CGFloat) -> CGFloat {
        let room = menuBarHeight - orbitMargin * 2 - 2
        guard room.isFinite, railDial.isFinite else { return max(minimumDialDiameter, railDial) }
        return max(minimumDialDiameter, min(railDial, room))
    }

    /// How many items one wing may hold beside the notch.
    public static func maximumWingItems(notch: NotchGeometry, itemWidth: CGFloat) -> Int {
        guard itemWidth > 0, itemWidth.isFinite else { return 0 }
        let auxiliary = min(notch.leftAuxiliaryWidth, notch.rightAuxiliaryWidth)
        guard auxiliary.isFinite, auxiliary > 0 else { return 0 }
        return max(0, Int(((auxiliary * wingShareOfAuxiliary) / itemWidth).rounded(.down)))
    }

    /// Splits `accountCount` accounts into a left and a right wing, the attention tab ending the right one.
    ///
    /// Accounts keep their order: the first half goes left, the rest right. When they do not all fit, the last slot
    /// of the left wing becomes the "+N" chip and the accounts it displaces are counted in `overflow`.
    public static func wings(accountCount: Int, hasAttention: Bool, maximumWingItems: Int) -> NotchWings {
        let count = max(0, accountCount)
        let capacity = max(0, maximumWingItems)
        let rightCapacity = max(0, capacity - (hasAttention ? 1 : 0))

        let fitted = split(count: count, leftCapacity: capacity, rightCapacity: rightCapacity)
        if fitted.left.count + fitted.right.count == count {
            return NotchWings(left: fitted.left, right: fitted.right, overflow: 0, hasAttention: hasAttention)
        }
        // One left slot goes to the chip.
        let reduced = split(count: count, leftCapacity: max(0, capacity - 1), rightCapacity: rightCapacity)
        let shown = reduced.left.count + reduced.right.count
        return NotchWings(left: reduced.left, right: reduced.right, overflow: count - shown, hasAttention: hasAttention)
    }

    /// Which wing carries the attention tab, and whether the rail keeps `RailView`'s "no accounts" placeholder.
    ///
    /// The tab ends the right wing. A right wing with no accounts of its own would have to be an empty `RailView` to
    /// carry it, and an empty `RailView` draws the "no accounts" placeholder — wrong beside a left wing that is full
    /// of them (one account plus a waiting agent is the everyday case). The tab then ends the left wing instead,
    /// which the layout pushes against the notch anyway, so it barely moves. Only a rail with no account on either
    /// side keeps the placeholder, exactly as an unfused rail does.
    public static func wingContents(leftCount: Int, rightCount: Int) -> WingContents {
        let empty = leftCount <= 0 && rightCount <= 0
        return WingContents(
            showsTabOnLeft: rightCount <= 0 && !empty,
            showsTabOnRight: rightCount > 0 || empty,
            showsPlaceholder: empty
        )
    }

    /// Balanced split of `count` items over two capped wings, first half left.
    private static func split(count: Int, leftCapacity: Int, rightCapacity: Int) -> (left: Range<Int>, right: Range<Int>) {
        let total = min(count, leftCapacity + rightCapacity)
        guard total > 0 else { return (0..<0, 0..<0) }
        var left = min(leftCapacity, (total + 1) / 2)
        var right = total - left
        if right > rightCapacity {
            right = rightCapacity
            left = total - right
        }
        return (0..<left, left..<(left + right))
    }
}
