import CodometerCore
import CoreGraphics
import Foundation

/// Where the floating card sits: snap targets, the magnet, gravity, frames per placement, clamping and the rules for
/// displays that come and go.
///
/// Everything here is a pure function of the pointer, the card's size and the displays, so the controller only feeds it
/// points. That is what keeps the magnet from overshooting: the rendered origin is a function of where the pointer is,
/// not an animation chasing it.
///
/// Coordinates are AppKit screen coordinates (origin at the bottom-left of the main display, y upwards), so "top"
/// means the larger y.
public enum FloatingCardGeometry {
    /// One axis of a snap target. `start` is leading/bottom, `end` is trailing/top.
    public enum Axis: String, Hashable, Sendable, CaseIterable {
        case start, middle, end
    }

    /// The area the card may occupy on one display: its visible frame (menu bar and Dock already removed) inset so the
    /// card never touches the edge, minus the notch's safe area at the top.
    public static func stage(of display: DisplayDescriptor, inset: CGFloat = CardMetrics.screenInset) -> CGRect {
        var frame = display.visibleFrame.insetBy(dx: inset, dy: inset)
        if let notch = display.notch {
            // The visible frame already excludes the menu bar on a notched Mac, but the notch's safe area can reach
            // further down; keep the card below whichever reaches further.
            let safeTop = notch.rect.minY - inset
            if frame.maxY > safeTop {
                frame = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: max(0, safeTop - frame.minY))
            }
        }
        return frame.width > 0 && frame.height > 0 ? frame : .zero
    }

    // MARK: - Anchors

    /// The anchor's two axes: horizontal first, then vertical.
    public static func axes(of anchor: CardAnchor) -> (x: Axis, y: Axis) {
        switch anchor {
        case .topLeading: (.start, .end)
        case .top: (.middle, .end)
        case .topTrailing: (.end, .end)
        case .leading: (.start, .middle)
        case .center: (.middle, .middle)
        case .trailing: (.end, .middle)
        case .bottomLeading: (.start, .start)
        case .bottom: (.middle, .start)
        case .bottomTrailing: (.end, .start)
        }
    }

    public static func anchor(x: Axis, y: Axis) -> CardAnchor {
        switch (x, y) {
        case (.start, .end): .topLeading
        case (.middle, .end): .top
        case (.end, .end): .topTrailing
        case (.start, .middle): .leading
        case (.middle, .middle): .center
        case (.end, .middle): .trailing
        case (.start, .start): .bottomLeading
        case (.middle, .start): .bottom
        case (.end, .start): .bottomTrailing
        }
    }

    /// The point of `frame` that `anchor` pins.
    public static func anchorPoint(of frame: CGRect, anchor: CardAnchor) -> CGPoint {
        let (x, y) = axes(of: anchor)
        return CGPoint(x: value(x, min: frame.minX, max: frame.maxX), y: value(y, min: frame.minY, max: frame.maxY))
    }

    /// The rect of `size` placed inside `container` so both share their `anchor` point.
    ///
    /// This is what ties the card and the pill together: a card snapped bottom-right shrinks up and to the left, and
    /// restoring lands on exactly the same pixels.
    public static func aligned(size: CGSize, in container: CGRect, anchor: CardAnchor) -> CGRect {
        frame(size: size, anchor: anchor, at: anchorPoint(of: container, anchor: anchor))
    }

    /// The frame of `size` whose `anchor` point sits exactly on `point`.
    public static func frame(size: CGSize, anchor: CardAnchor, at point: CGPoint) -> CGRect {
        let (x, y) = axes(of: anchor)
        let originX = point.x - offset(x, length: size.width)
        let originY = point.y - offset(y, length: size.height)
        return CGRect(x: originX, y: originY, width: size.width, height: size.height)
    }

    /// The snap target `anchor` names inside `stage`.
    public static func targetPoint(_ anchor: CardAnchor, in stage: CGRect) -> CGPoint {
        let (x, y) = axes(of: anchor)
        return CGPoint(x: value(x, min: stage.minX, max: stage.maxX), y: value(y, min: stage.minY, max: stage.maxY))
    }

    /// Every snap target of `stage`: four corners, four edge midpoints and the centre.
    public static func targets(in stage: CGRect) -> [(anchor: CardAnchor, point: CGPoint)] {
        CardAnchor.allCases.map { ($0, targetPoint($0, in: stage)) }
    }

    /// Which ninth of `stage` the card's centre is in, as the anchor that ninth pins.
    public static func gravity(of frame: CGRect, in stage: CGRect) -> CardAnchor {
        guard stage.width > 0, stage.height > 0 else { return .topTrailing }
        let u = (frame.midX - stage.minX) / stage.width
        let v = (frame.midY - stage.minY) / stage.height
        return anchor(x: third(u), y: third(v))
    }

    private static func third(_ fraction: Double) -> Axis {
        guard fraction.isFinite else { return .middle }
        if fraction < 1.0 / 3 { return .start }
        if fraction > 2.0 / 3 { return .end }
        return .middle
    }

    private static func value(_ axis: Axis, min low: CGFloat, max high: CGFloat) -> CGFloat {
        switch axis {
        case .start: low
        case .middle: (low + high) / 2
        case .end: high
        }
    }

    /// How far the anchor point is from the frame's origin along one axis.
    private static func offset(_ axis: Axis, length: CGFloat) -> CGFloat {
        switch axis {
        case .start: 0
        case .middle: length / 2
        case .end: length
        }
    }

    // MARK: - The magnet

    /// What the magnet did with one pointer sample.
    public struct Resolution: Equatable, Sendable {
        /// Where the card is drawn: the free frame pulled toward the snap targets in range.
        public let frame: CGRect
        /// The axes currently within the full radius, as an identity the haptic arming can compare. `nil` when the
        /// card is free on both axes.
        public let targetID: String?
        /// The distance the haptic arming judges: the larger distance over the axes in range, or `radius + 1` when the
        /// card is free. Locked means `distance <= radius / 2`.
        public let distance: CGFloat
        /// Both axes are locked exactly on a target, so a drop here is saved as snapped.
        public let snappedAnchor: CardAnchor?

        public var isLocked: Bool { snappedAnchor != nil }
    }

    /// Pulls `free` toward the snap targets of `stage`.
    ///
    /// Each axis is resolved on its own against three targets (leading/centre/trailing, bottom/middle/top), which is
    /// what makes corners, edge midpoints, the centre and the edge lines one rule instead of four: on an edge line only
    /// one axis is within range, so the card slides along that edge. Because `MagnetLaw.pull` is a smoothstep of the
    /// distance, the drawn position is continuous in the pointer: one point of pointer travel never moves the card by
    /// more than about one point.
    public static func resolve(free: CGRect, in stage: CGRect, radius: CGFloat, snaps: Bool) -> Resolution {
        guard snaps, stage.width > 0, stage.height > 0, radius > 0 else {
            return Resolution(frame: free, targetID: nil, distance: radius + 1, snappedAnchor: nil)
        }
        let x = axisPull(
            value: free.minX,
            length: free.width,
            low: stage.minX,
            high: stage.maxX,
            radius: radius
        )
        let y = axisPull(
            value: free.minY,
            length: free.height,
            low: stage.minY,
            high: stage.maxY,
            radius: radius
        )
        let frame = CGRect(x: x.origin, y: y.origin, width: free.width, height: free.height)
        let parts = [x.axis.map { "x:\($0.rawValue)" }, y.axis.map { "y:\($0.rawValue)" }].compactMap { $0 }
        let targetID = parts.isEmpty ? nil : parts.joined(separator: "|")
        let distance = parts.isEmpty ? radius + 1 : max(x.axis == nil ? 0 : x.distance, y.axis == nil ? 0 : y.distance)
        let snapped: CardAnchor? = if let ax = x.axis, let ay = y.axis, x.distance <= radius / 2, y.distance <= radius / 2 {
            anchor(x: ax, y: ay)
        } else {
            nil
        }
        return Resolution(frame: frame, targetID: targetID, distance: distance, snappedAnchor: snapped)
    }

    /// One axis of the magnet: the nearest of the three targets and the origin it pulls to.
    private static func axisPull(
        value origin: CGFloat,
        length: CGFloat,
        low: CGFloat,
        high: CGFloat,
        radius: CGFloat
    ) -> (origin: CGFloat, axis: Axis?, distance: CGFloat) {
        var best: (axis: Axis, distance: CGFloat, target: CGFloat)?
        for axis in Axis.allCases {
            let point = value(axis, min: low, max: high)
            let anchored = origin + offset(axis, length: length)
            let distance = abs(anchored - point)
            if best == nil || distance < (best?.distance ?? .infinity) {
                best = (axis, distance, point - offset(axis, length: length))
            }
        }
        guard let best, best.distance <= radius else { return (origin, nil, .infinity) }
        let pull = MagnetLaw.pull(distance: best.distance, radius: radius)
        return (origin + (best.target - origin) * pull, best.axis, best.distance)
    }

    /// Keeps the whole card inside `stage`; a card larger than the stage is aligned to its leading/top edge.
    public static func clamp(_ frame: CGRect, in stage: CGRect) -> CGRect {
        guard stage.width > 0, stage.height > 0 else { return frame }
        let x = frame.width >= stage.width ? stage.minX : min(max(frame.minX, stage.minX), stage.maxX - frame.width)
        let y = frame.height >= stage.height ? stage.maxY - frame.height : min(max(frame.minY, stage.minY), stage.maxY - frame.height)
        return CGRect(x: x, y: y, width: frame.width, height: frame.height)
    }

    // MARK: - Placements

    /// The placement to remember for a card drawn at `frame` on `display`.
    public static func placement(
        of frame: CGRect,
        on display: DisplayDescriptor,
        stage: CGRect,
        snappedAnchor: CardAnchor?
    ) -> CardPlacement {
        let anchor = snappedAnchor ?? gravity(of: frame, in: stage)
        let point = anchorPoint(of: frame, anchor: anchor)
        let x = stage.width > 0 ? (point.x - stage.minX) / stage.width : 0
        // Fractions run from the top down, so a card pinned to the top keeps y = 0 whatever the display's height.
        let y = stage.height > 0 ? (stage.maxY - point.y) / stage.height : 0
        return CardPlacement(
            displayID: display.id,
            anchor: anchor,
            snapped: snappedAnchor != nil,
            x: UnitInterval.clamped(x),
            y: UnitInterval.clamped(y)
        )
    }

    /// The frame `placement` resolves to for a card of `size`, clamped into `stage`.
    ///
    /// A snapped placement lands exactly on its target however the display changed; a free one keeps its anchor point
    /// at the same fractions of the stage.
    public static func frame(for placement: CardPlacement, size: CGSize, in stage: CGRect) -> CGRect {
        let point: CGPoint = if placement.snapped {
            targetPoint(placement.anchor, in: stage)
        } else {
            CGPoint(
                x: stage.minX + stage.width * placement.x.value,
                y: stage.maxY - stage.height * placement.y.value
            )
        }
        return clamp(frame(size: size, anchor: placement.anchor, at: point), in: stage)
    }

    /// The card's default place: snapped into the top-trailing corner.
    public static func defaultPlacement(on display: DisplayDescriptor) -> CardPlacement {
        CardPlacement(displayID: display.id, anchor: .topTrailing, snapped: true, x: .one, y: .zero)
    }

    // MARK: - Displays

    /// The display the card belongs on now, its placement there, and the placements to remember.
    public struct DisplayPlan: Equatable, Sendable {
        public let display: DisplayDescriptor
        public let placement: CardPlacement
        /// `placements` with `current` and `displacedFrom` brought up to date; `nil` when nothing changed.
        public let updatedPlacements: FloatingCardPlacements?
    }

    /// Resolves display changes:
    ///
    /// - the current display is still connected → stay on it;
    /// - it disconnected → move to the display the policy resolves to (the main one for `whereLeft`), remembering where
    ///   the card came from, so it can go back;
    /// - the display it was displaced from is connected again → return to it and forget the displacement;
    /// - `main` and `display(id)` policies always win over both.
    ///
    /// Returns `nil` when no display is connected.
    public static func plan(
        policy: DisplayPolicy,
        placements: FloatingCardPlacements,
        displays: [DisplayDescriptor]
    ) -> DisplayPlan? {
        guard !displays.isEmpty else { return nil }
        var updated = placements
        var target: DisplayDescriptor?

        switch policy {
        case .whereLeft:
            if let back = placements.displacedFrom, let display = displays.first(where: { $0.id == back }) {
                target = display
                updated.displacedFrom = nil
            } else if let current = placements.current, let display = displays.first(where: { $0.id == current }) {
                target = display
            } else {
                if let current = placements.current, updated.displacedFrom == nil {
                    updated.displacedFrom = current
                }
                target = DisplaySelection.main(in: displays)
            }
        case .main, .display:
            target = DisplaySelection.resolve(policy: policy, remembered: nil, displays: displays)
            updated.displacedFrom = nil
        }

        guard let display = target else { return nil }
        updated.current = display.id
        let placement = placements.placement(for: display.id) ?? defaultPlacement(on: display)
        return DisplayPlan(
            display: display,
            placement: placement,
            updatedPlacements: updated == placements ? nil : updated
        )
    }
}
