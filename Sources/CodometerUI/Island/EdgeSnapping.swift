import CodometerCore
import CoreGraphics
import Foundation

/// A place along the landing edge the carried island is pulled towards.
public struct EdgeSnapTarget: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable {
        /// The middle of the edge.
        case center
        /// The corner where the edge starts (offset 0).
        case start
        /// The corner where the edge ends (offset 1).
        case end
        /// The camera notch's centre, which fuses the island with it.
        case notch
    }

    public let kind: Kind
    /// The offset along the edge the island lands on when this target locks.
    public let offset: Double
    /// Pull radius in points, already scaled.
    public let radius: CGFloat

    public var id: String { kind.rawValue }

    public init(kind: Kind, offset: Double, radius: CGFloat) {
        self.kind = kind
        self.offset = offset
        self.radius = radius
    }
}

/// What the snapping remembers between pointer samples: what is locked, and when the last haptic played.
public struct EdgeSnapState: Equatable, Sendable {
    public private(set) var locked: EdgeSnapTarget.Kind?
    /// The magnet's hysteresis and haptic rate limit (`MagnetLaw`), shared with the floating card.
    var arming = MagnetArming()

    public init() {}

    public init(locked: EdgeSnapTarget.Kind?) {
        self.locked = locked
    }
}

/// One pointer sample resolved: where the capsule is drawn, where it would land, and whether to buzz.
public struct EdgeSnapResolution: Equatable, Sendable {
    /// Added to the pointer-driven canvas shift, so the capsule is pulled while the pointer is not moved.
    public let displayShift: CGVector
    /// The offset a drop would save (exactly 0, 0.5 or 1 while a target is locked).
    public let dropOffset: Double
    public let state: EdgeSnapState
    public let haptic: SnapHaptic?
    /// The target the carry is locked onto, for the rim's snapped look and the debug trace.
    public let locked: EdgeSnapTarget.Kind?

    public init(displayShift: CGVector, dropOffset: Double, state: EdgeSnapState, haptic: SnapHaptic?, locked: EdgeSnapTarget.Kind?) {
        self.displayShift = displayShift
        self.dropOffset = dropOffset
        self.state = state
        self.haptic = haptic
        self.locked = locked
    }
}

/// Magnetic snapping of the carried island to the centre, the corners and the camera notch of the landing edge.
///
/// Pure arithmetic per `mouseDragged` event: the controller passes the pointer and the placement it computed, and
/// gets back how far to pull the capsule, what a drop would save, and whether to play a haptic.
public enum EdgeSnapping {
    /// The pointer has to be this close to the landing edge before snapping arms at all, at scale 1.
    public static let dropZone: CGFloat = 120
    /// Pull radius of the centre and the corners at scale 1.
    public static let targetRadius: CGFloat = MagnetLaw.radius
    /// The notch pulls harder: fusing with it is the placement users are aiming for.
    public static let notchRadius: CGFloat = 40

    /// The snap targets along `edge`, in the order they are offered.
    ///
    /// The ends are left out when the island's travel along the edge is shorter than two radii, where a corner and
    /// the centre would overlap. The notch target exists only on the top edge of a display that has one.
    public static func targets(
        edge: ScreenEdge,
        railLength: CGFloat,
        area: CGRect,
        style: IslandStyle,
        notch: NotchGeometry?,
        scale: CGFloat
    ) -> [EdgeSnapTarget] {
        let scale = scale.isFinite && scale > 0 ? scale : 1
        let radius = targetRadius * scale
        let travel = self.travel(edge: edge, railLength: railLength, area: area, style: style)
        var targets = [EdgeSnapTarget(kind: .center, offset: 0.5, radius: radius)]
        if travel >= radius * 2 {
            targets.append(EdgeSnapTarget(kind: .start, offset: 0, radius: radius))
            targets.append(EdgeSnapTarget(kind: .end, offset: 1, radius: radius))
        }
        if edge == .top, let notch, let offset = notchOffset(notch: notch, railLength: railLength, area: area, style: style) {
            targets.append(EdgeSnapTarget(kind: .notch, offset: offset, radius: notchRadius * scale))
        }
        return targets
    }

    /// Resolves one pointer sample against `targets`.
    ///
    /// Outside the drop zone, or with `bypass` (⌘ held), the carry is free: no pull, no haptic, no lock. Inside the
    /// magnet's core (half the radius) the drop offset is exactly the target's; between the core and the radius the
    /// capsule eases towards the target (`MagnetLaw.pull`), so there is never a jump.
    public static func resolve(
        pointer: CGPoint,
        placement: (edge: ScreenEdge, offset: Double),
        targets: [EdgeSnapTarget],
        area: CGRect,
        railLength: CGFloat,
        style: IslandStyle,
        state: EdgeSnapState,
        now: TimeInterval,
        bypass: Bool
    ) -> EdgeSnapResolution {
        var state = state
        guard !bypass, pointer.x.isFinite, pointer.y.isFinite,
              withinDropZone(pointer: pointer, edge: placement.edge, area: area) else {
            _ = state.arming.update(targetID: nil, distance: .infinity, radius: 1, now: now)
            state = EdgeSnapState(locked: nil, arming: state.arming)
            return EdgeSnapResolution(displayShift: .zero, dropOffset: placement.offset, state: state, haptic: nil, locked: nil)
        }

        let travel = self.travel(edge: placement.edge, railLength: railLength, area: area, style: style)
        guard travel > 0, let nearest = nearest(to: placement.offset, in: targets, travel: travel) else {
            _ = state.arming.update(targetID: nil, distance: .infinity, radius: 1, now: now)
            state = EdgeSnapState(locked: nil, arming: state.arming)
            return EdgeSnapResolution(displayShift: .zero, dropOffset: placement.offset, state: state, haptic: nil, locked: nil)
        }

        let distance = abs(CGFloat(nearest.offset - placement.offset)) * travel
        let plays = state.arming.update(targetID: nearest.id, distance: distance, radius: nearest.radius, now: now)
        let locked = state.arming.lockedTargetID.flatMap(EdgeSnapTarget.Kind.init(rawValue:))
        state = EdgeSnapState(locked: locked, arming: state.arming)

        let pull = MagnetLaw.pull(distance: distance, radius: nearest.radius)
        let displayed = placement.offset + (nearest.offset - placement.offset) * Double(pull)
        // A locked target lands exactly on it; outside the core the drop follows where the capsule is drawn.
        let dropOffset = locked == nearest.kind ? nearest.offset : displayed
        let shift = (displayed - placement.offset) * Double(travel)
        return EdgeSnapResolution(
            displayShift: vector(along: placement.edge, by: CGFloat(shift)),
            dropOffset: min(max(dropOffset, 0), 1),
            state: state,
            haptic: plays ? .lock : nil,
            locked: locked
        )
    }

    /// How far the island's centre can travel along `edge` between the two extreme offsets.
    public static func travel(edge: ScreenEdge, railLength: CGFloat, area: CGRect, style: IslandStyle) -> CGFloat {
        let gap = IslandGeometry.gap(for: style)
        let span = edge.isHorizontal ? area.width : area.height
        return max(0, span - railLength - gap * 2)
    }

    /// Whether the pointer is close enough to the landing edge for snapping to arm.
    static func withinDropZone(pointer: CGPoint, edge: ScreenEdge, area: CGRect) -> Bool {
        guard !area.isNull, area.width > 0, area.height > 0 else { return false }
        let distance: CGFloat = switch edge {
        case .top: area.maxY - pointer.y
        case .bottom: pointer.y - area.minY
        case .left: pointer.x - area.minX
        case .right: area.maxX - pointer.x
        }
        return distance <= dropZone && distance >= -dropZone
    }

    /// The nearest target by distance along the edge, in points.
    static func nearest(to offset: Double, in targets: [EdgeSnapTarget], travel: CGFloat) -> EdgeSnapTarget? {
        var best: (target: EdgeSnapTarget, distance: CGFloat)?
        for target in targets {
            let distance = abs(CGFloat(target.offset - offset)) * travel
            if best == nil || distance < (best?.distance ?? .infinity) {
                best = (target, distance)
            }
        }
        return best?.target
    }

    /// The offset that centres the island on the notch, or `nil` when the notch is not reachable.
    static func notchOffset(notch: NotchGeometry, railLength: CGFloat, area: CGRect, style: IslandStyle) -> Double? {
        let travel = travel(edge: .top, railLength: railLength, area: area, style: style)
        guard travel > 0 else { return nil }
        let gap = IslandGeometry.gap(for: style)
        let start = area.minX + gap + railLength / 2
        let offset = Double((notch.rect.midX - start) / travel)
        guard offset.isFinite, offset >= 0, offset <= 1 else { return nil }
        return offset
    }

    /// A shift of `length` points along `edge`, in screen coordinates (origin bottom-left).
    static func vector(along edge: ScreenEdge, by length: CGFloat) -> CGVector {
        switch edge {
        case .top, .bottom: CGVector(dx: length, dy: 0)
        // A larger offset on a side edge moves the island **down**, so the shift is negative in screen coordinates.
        case .left, .right: CGVector(dx: 0, dy: -length)
        }
    }
}

extension EdgeSnapState {
    init(locked: EdgeSnapTarget.Kind?, arming: MagnetArming) {
        self.init(locked: locked)
        self.arming = arming
    }
}
