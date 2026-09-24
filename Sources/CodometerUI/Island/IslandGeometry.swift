import CodometerCore
import CoreGraphics

/// Where the island sits in each of its states.
public struct IslandFrames: Equatable, Sendable {
    public var rail: CGRect
    public var deck: CGRect

    public init(rail: CGRect, deck: CGRect) {
        self.rail = rail
        self.deck = deck
    }

    public func frame(expanded: Bool) -> CGRect {
        expanded ? deck : rail
    }

    /// The smallest rect holding both states.
    public var union: CGRect {
        rail.union(deck)
    }
}

/// Both states of the island inside one stable box, in the box's own top-left coordinates.
///
/// The island's content is laid out at its final place in the box and never moves; only the silhouette
/// animates between `rail` and `deck`, so opening reveals the deck where it will stay instead of sliding it.
public struct IslandMorphLayout: Equatable, Sendable {
    public let size: CGSize
    public let rail: CGRect
    public let deck: CGRect

    public init(size: CGSize, rail: CGRect, deck: CGRect) {
        self.size = size
        self.rail = rail
        self.deck = deck
    }

    /// The stage for frames in any coordinate space; its box is their union.
    public init(frames: IslandFrames) {
        let union = frames.union
        self.init(
            size: union.size,
            rail: frames.rail.offsetBy(dx: -union.minX, dy: -union.minY),
            deck: frames.deck.offsetBy(dx: -union.minX, dy: -union.minY)
        )
    }

    /// A stage without window geometry (previews): both states pinned to the same anchor of their box.
    public static func anchored(rail: CGSize, deck: CGSize, anchor: IslandAnchor) -> IslandMorphLayout {
        let size = CGSize(width: max(rail.width, deck.width), height: max(rail.height, deck.height))
        func place(_ item: CGSize) -> CGRect {
            let x: CGFloat = switch anchor {
            case .topLeading, .leading, .bottomLeading: 0
            case .top, .bottom: ((size.width - item.width) / 2).rounded()
            case .topTrailing, .trailing, .bottomTrailing: size.width - item.width
            }
            let y: CGFloat = switch anchor {
            case .topLeading, .top, .topTrailing: 0
            case .leading, .trailing: ((size.height - item.height) / 2).rounded()
            case .bottomLeading, .bottom, .bottomTrailing: size.height - item.height
            }
            return CGRect(origin: CGPoint(x: x, y: y), size: item)
        }
        return IslandMorphLayout(size: size, rail: place(rail), deck: place(deck))
    }

    public func frame(expanded: Bool) -> CGRect {
        expanded ? deck : rail
    }
}

/// Pure placement math. Screen rects use AppKit coordinates (origin bottom-left); "local" rects use the
/// island canvas view's coordinates (origin top-left), which is what SwiftUI lays the island out in.
public enum IslandGeometry {
    /// Distance between a floating island and the screen edge.
    public static let floatingGap: CGFloat = 8

    public static func gap(for style: IslandStyle) -> CGFloat {
        style == .floating ? floatingGap : 0
    }

    /// The region the island lives in. An attached island touches the physical screen edge
    /// (at the top it hangs over the menu bar, like a notch); a floating one stays inside the
    /// area not covered by the menu bar and the Dock.
    public static func area(edge: ScreenEdge, style: IslandStyle, screen: CGRect, visible: CGRect) -> CGRect {
        guard style == .attached else { return visible }
        switch edge {
        case .top:
            return CGRect(x: screen.minX, y: visible.minY, width: screen.width, height: screen.maxY - visible.minY)
        case .bottom:
            return CGRect(x: screen.minX, y: visible.minY, width: screen.width, height: visible.height)
        case .left, .right:
            return CGRect(x: screen.minX, y: visible.minY, width: screen.width, height: visible.height)
        }
    }

    /// The collapsed island's frame for an edge and a position along it.
    ///
    /// A rail fused with the camera notch (`fusedNotch`) ignores the offset: it is centred on the notch and flush
    /// with the top of the screen, so the two wings sit in the menu bar beside the notch.
    public static func railFrame(
        size: CGSize,
        edge: ScreenEdge,
        offset: Double,
        style: IslandStyle,
        in area: CGRect,
        fusedNotch: NotchGeometry? = nil
    ) -> CGRect {
        if let fusedNotch, edge == .top {
            var x = fusedNotch.rect.midX - size.width / 2
            x = min(max(x, area.minX), max(area.minX, area.maxX - size.width))
            return CGRect(x: x.rounded(), y: (area.maxY - size.height).rounded(), width: size.width, height: size.height)
        }
        let gap = gap(for: style)
        let t = CGFloat(min(max(offset, 0), 1))
        switch edge {
        case .top, .bottom:
            let travel = max(0, area.width - size.width - gap * 2)
            let x = area.minX + gap + travel * t
            let y = edge == .top ? area.maxY - gap - size.height : area.minY + gap
            return CGRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
        case .left, .right:
            let travel = max(0, area.height - size.height - gap * 2)
            let top = area.maxY - gap - travel * t
            let x = edge == .left ? area.minX + gap : area.maxX - gap - size.width
            return CGRect(x: x.rounded(), y: (top - size.height).rounded(), width: size.width, height: size.height)
        }
    }

    /// Grow away from the edge, centred on the rail in the middle third of an edge and away from the
    /// nearer corner in the outer thirds.
    public static func anchor(edge: ScreenEdge, offset: Double) -> IslandAnchor {
        let third = Self.third(offset)
        switch edge {
        case .top:
            return [.topLeading, .top, .topTrailing][third]
        case .bottom:
            return [.bottomLeading, .bottom, .bottomTrailing][third]
        case .left:
            return [.topLeading, .leading, .bottomLeading][third]
        case .right:
            return [.topTrailing, .trailing, .bottomTrailing][third]
        }
    }

    /// 0 for the first third of an edge, 1 for the middle third, 2 for the last one.
    private static func third(_ offset: Double) -> Int {
        offset < 1.0 / 3 ? 0 : offset > 2.0 / 3 ? 2 : 1
    }

    /// The expanded island's frame: it keeps the rail's anchored side (or centre) where it was, then is
    /// nudged back inside `area` if it would leave it.
    public static func expandedFrame(rail: CGRect, size: CGSize, anchor: IslandAnchor, in area: CGRect) -> CGRect {
        let width = max(size.width, rail.width)
        let height = max(size.height, rail.height)
        let x: CGFloat = switch anchor {
        case .topLeading, .leading, .bottomLeading: rail.minX
        case .top, .bottom: rail.midX - width / 2
        case .topTrailing, .trailing, .bottomTrailing: rail.maxX - width
        }
        let y: CGFloat = switch anchor {
        case .topLeading, .top, .topTrailing: rail.maxY - height
        case .leading, .trailing: rail.midY - height / 2
        case .bottomLeading, .bottom, .bottomTrailing: rail.minY
        }
        var frame = CGRect(x: x.rounded(), y: y.rounded(), width: width, height: height)
        if frame.maxX > area.maxX { frame.origin.x = area.maxX - frame.width }
        if frame.minX < area.minX { frame.origin.x = area.minX }
        if frame.maxY > area.maxY { frame.origin.y = area.maxY - frame.height }
        if frame.minY < area.minY { frame.origin.y = area.minY }
        return frame
    }

    /// Both states' frames in screen coordinates for a placement and measured sizes.
    public static func frames(
        sizes: IslandSizes,
        edge: ScreenEdge,
        offset: Double,
        style: IslandStyle,
        in area: CGRect,
        fusedNotch: NotchGeometry? = nil
    ) -> IslandFrames {
        let rail = railFrame(size: sizes.rail, edge: edge, offset: offset, style: style, in: area, fusedNotch: fusedNotch)
        guard let fusedNotch, edge == .top else {
            let deck = expandedFrame(rail: rail, size: sizes.deck, anchor: anchor(edge: edge, offset: offset), in: area)
            return IslandFrames(rail: rail, deck: deck)
        }
        // A fused island grows straight down out of the notch, centred on it, and keeps the deck's own width: the
        // rail is wide because it reaches around the notch, which is no reason to stretch the deck.
        let seam = CGRect(x: fusedNotch.rect.midX, y: rail.minY, width: 0, height: rail.height)
        let deck = expandedFrame(rail: seam, size: sizes.deck, anchor: .top, in: area)
        return IslandFrames(rail: rail, deck: deck)
    }

    /// The bounds a carried island's panel may cover: the union of every connected display, so a drag can cross
    /// from one display to another instead of stopping at the edge of the one the island started on.
    public static func dragBounds(displays: [DisplayDescriptor], fallback: CGRect) -> CGRect {
        let union = DisplaySelection.union(of: displays)
        guard !union.isNull, union.width > 0, union.height > 0 else { return fallback }
        return union
    }

    /// The tallest deck that fits `area` for a style (a floating island keeps its gap at both ends).
    public static func maximumDeckHeight(style: IslandStyle, in area: CGRect) -> CGFloat {
        max(0, (area.height - gap(for: style) * 2).rounded(.down))
    }

    /// The panel frame that holds `rects` with `margin` of transparent room around them, so rim light and
    /// shadow are never clipped. An attached island gets no margin on the screen edge it grows from.
    /// The result never leaves `bounds` (the screen).
    public static func panelFrame(containing rects: [CGRect], edge: ScreenEdge, attached: Bool, margin: CGFloat, within bounds: CGRect) -> CGRect {
        guard let first = rects.first else { return .zero }
        let union = rects.dropFirst().reduce(first) { $0.union($1) }
        let m = max(0, margin)
        var frame = union.insetBy(dx: -m, dy: -m)
        if attached {
            switch edge {
            case .top: frame.size.height -= m
            case .bottom:
                frame.origin.y += m
                frame.size.height -= m
            case .left:
                frame.origin.x += m
                frame.size.width -= m
            case .right: frame.size.width -= m
            }
        }
        let clamped = frame.intersection(bounds)
        return clamped.isNull ? union : clamped.integral
    }

    /// A screen rect in a canvas view whose top-left corner sits at `canvas`'s top-left corner.
    public static func local(_ rect: CGRect, in canvas: CGRect) -> CGRect {
        CGRect(x: rect.minX - canvas.minX, y: canvas.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The inverse of `local(_:in:)`.
    public static func screen(_ rect: CGRect, in canvas: CGRect) -> CGRect {
        CGRect(x: rect.minX + canvas.minX, y: canvas.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    /// A local (top-left origin) rect in a view's own coordinate space, flipped or not.
    public static func viewRect(_ rect: CGRect, boundsHeight: CGFloat, isFlipped: Bool) -> CGRect {
        guard !isFlipped else { return rect }
        return CGRect(x: rect.minX, y: boundsHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// A rect of `size` centred on `point`, on whole points.
    public static func rect(centeredAt point: CGPoint, size: CGSize) -> CGRect {
        CGRect(x: (point.x - size.width / 2).rounded(), y: (point.y - size.height / 2).rounded(), width: size.width, height: size.height)
    }

    /// Nearest edge and position along it for a pointer during a drag, keeping the island centred on it.
    public static func placement(
        for point: CGPoint,
        railSize: CGSize,
        style: IslandStyle,
        screen: CGRect,
        visible: CGRect
    ) -> (edge: ScreenEdge, offset: Double) {
        let distances: [(ScreenEdge, CGFloat)] = [
            (.top, screen.maxY - point.y),
            (.bottom, point.y - screen.minY),
            (.left, point.x - screen.minX),
            (.right, screen.maxX - point.x),
        ]
        let edge = distances.min { $0.1 < $1.1 }?.0 ?? .top
        let area = area(edge: edge, style: style, screen: screen, visible: visible)
        let gap = gap(for: style)
        // The island turns 90° when it changes orientation, so measure its long side along the new edge.
        let length = max(railSize.width, railSize.height)
        switch edge {
        case .top, .bottom:
            let travel = area.width - length - gap * 2
            guard travel > 0 else { return (edge, 0.5) }
            return (edge, Double(min(max((point.x - length / 2 - area.minX - gap) / travel, 0), 1)))
        case .left, .right:
            let travel = area.height - length - gap * 2
            guard travel > 0 else { return (edge, 0.5) }
            return (edge, Double(min(max((area.maxY - gap - (point.y + length / 2)) / travel, 0), 1)))
        }
    }
}
