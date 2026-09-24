import CoreGraphics
import Foundation

/// The magnetic pull shared by the island's edge snapping and the floating card (one law for both surfaces).
///
/// Inside half the radius the carried surface sits exactly on the target; between half the radius and the radius it
/// eases toward the pointer (smoothstep, so there is no jump); beyond the radius it follows the pointer freely.
public enum MagnetLaw {
    /// Snap radius at scale 1, in points.
    public static let radius: CGFloat = 28
    /// At most one haptic per this many seconds while dragging.
    public static let minimumHapticInterval: TimeInterval = 0.15

    /// 1 for `distance ≤ radius / 2`, 0 for `distance ≥ radius`, smoothstep in between. 0 for a non-positive or
    /// non-finite radius or a non-finite distance.
    public static func pull(distance: CGFloat, radius: CGFloat) -> CGFloat {
        guard radius > 0, radius.isFinite, distance.isFinite else { return 0 }
        let distance = abs(distance)
        let core = radius / 2
        if distance <= core { return 1 }
        if distance >= radius { return 0 }
        let t = (radius - distance) / (radius - core)
        return t * t * (3 - 2 * t)
    }
}

/// Decides when snapping should play a haptic: once when a target locks (distance ≤ radius / 2), re-armed only after
/// the pointer leaves that target's radius, and never more often than `MagnetLaw.minimumHapticInterval`.
///
/// Locking at half the radius and releasing beyond the full radius is the hysteresis that keeps a pointer resting
/// near the edge of the radius from flickering between locked and free.
public struct MagnetArming: Hashable, Sendable {
    /// The target the carried surface is locked onto, if any.
    public private(set) var lockedTargetID: String?
    private var lastHapticAt: TimeInterval?

    public init() {}

    /// Feeds the nearest target (or `nil` when none is in range) for one pointer sample.
    /// - Returns: `true` when a haptic should play now.
    public mutating func update(targetID: String?, distance: CGFloat, radius: CGFloat, now: TimeInterval) -> Bool {
        guard let targetID, distance.isFinite, radius > 0, abs(distance) <= radius else {
            lockedTargetID = nil
            return false
        }
        if targetID == lockedTargetID { return false }
        guard abs(distance) <= radius / 2 else {
            // Nearest to another target but not in its core yet: the previous lock no longer holds.
            if lockedTargetID != nil { lockedTargetID = nil }
            return false
        }
        lockedTargetID = targetID
        if let lastHapticAt, now >= lastHapticAt, now - lastHapticAt < MagnetLaw.minimumHapticInterval {
            return false
        }
        lastHapticAt = now
        return true
    }
}

/// A haptic the drag loop asks for.
public enum SnapHaptic: Sendable, CaseIterable {
    /// A snap target locked.
    case lock
    /// The island's landing edge changed during a carry.
    case edgeChange
    /// The carried surface moved onto another display.
    case displayChange
}
