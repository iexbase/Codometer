import CodometerCore
import SwiftUI

/// The island's outline.
///
/// Attached: flush with the screen edge, meeting it through concave shoulders so the island looks like it
/// grows out of the bezel, with smooth (continuous) corners on the free side. The attached side bleeds a few
/// points past the bounds so no glass rim is drawn along the screen edge. Corner radius and shoulder animate,
/// so while the rail tab grows into the deck the shoulders stay fused to the bezel the whole way.
/// Floating: a continuous rounded rectangle (a capsule when the radius is large).
public struct IslandSilhouette: Shape {
    public var edge: ScreenEdge
    public var style: IslandStyle
    public var cornerRadius: CGFloat
    public var shoulder: CGFloat
    /// Where the island sits inside the rect the shape is drawn in; `nil` fills that rect. Animating it grows
    /// the island inside a stable view, so content laid out in that view stays still while it is revealed.
    public var islandFrame: CGRect?

    /// How far the attached side reaches past the bounds.
    static let bleed: CGFloat = 6

    public init(edge: ScreenEdge, style: IslandStyle, cornerRadius: CGFloat, shoulder: CGFloat, islandFrame: CGRect? = nil) {
        self.edge = edge
        self.style = style
        self.cornerRadius = cornerRadius
        self.shoulder = shoulder
        self.islandFrame = islandFrame
    }

    public var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGRect.AnimatableData> {
        get { AnimatablePair(AnimatablePair(cornerRadius, shoulder), (islandFrame ?? .zero).animatableData) }
        set {
            cornerRadius = newValue.first.first
            shoulder = newValue.first.second
            if var frame = islandFrame {
                frame.animatableData = newValue.second
                islandFrame = frame
            }
        }
    }

    /// The same outline filling whatever rect it is drawn in.
    var filling: IslandSilhouette {
        var copy = self
        copy.islandFrame = nil
        return copy
    }

    public func path(in bounds: CGRect) -> Path {
        let rect = islandFrame.map { $0.offsetBy(dx: bounds.minX, dy: bounds.minY) } ?? bounds
        guard rect.width > 0, rect.height > 0 else { return Path() }
        switch style {
        case .floating:
            let radius = min(cornerRadius, min(rect.width, rect.height) / 2)
            return RoundedRectangle(cornerRadius: max(0, radius), style: .continuous).path(in: rect)
        case .attached:
            return attachedPath(in: rect, closed: true)
        }
    }

    /// The outline without the side that touches the screen edge, for rim light and highlights.
    public var outline: IslandSilhouetteOutline {
        IslandSilhouetteOutline(silhouette: self)
    }

    func attachedPath(in rect: CGRect, closed: Bool) -> Path {
        // Canonical frame: `u` runs along the edge, `v` points away from it.
        let length = edge.isHorizontal ? rect.width : rect.height
        let depth = edge.isHorizontal ? rect.height : rect.width
        let s = max(0, min(shoulder, length / 4, depth / 2))
        let r = max(0, min(cornerRadius, (length - s * 2) / 2 / Self.cornerReach, (depth - s) / Self.cornerReach))
        // A continuous corner starts a little before a circular one would and pulls its control points
        // further in, so curvature ramps up instead of jumping.
        let reach = r * Self.cornerReach
        let pull = reach * Self.cornerPull
        // The concave shoulder leaves the bezel tangentially and meets the side tangentially.
        let along = s * 0.62
        let down = s * 0.38

        func point(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
            switch edge {
            case .top: CGPoint(x: rect.minX + u, y: rect.minY + v)
            case .bottom: CGPoint(x: rect.minX + u, y: rect.maxY - v)
            case .left: CGPoint(x: rect.minX + v, y: rect.minY + u)
            case .right: CGPoint(x: rect.maxX - v, y: rect.minY + u)
            }
        }

        var path = Path()
        if closed {
            path.move(to: point(0, -Self.bleed))
            path.addLine(to: point(0, 0))
        } else {
            path.move(to: point(0, 0))
        }
        // Leading shoulder: concave, curving from the edge into the island's side.
        path.addCurve(to: point(s, s), control1: point(along, 0), control2: point(s, s - down))
        path.addLine(to: point(s, depth - reach))
        // Convex corners on the free side.
        path.addCurve(to: point(s + reach, depth), control1: point(s, depth - reach + pull), control2: point(s + reach - pull, depth))
        path.addLine(to: point(length - s - reach, depth))
        path.addCurve(to: point(length - s, depth - reach), control1: point(length - s - reach + pull, depth), control2: point(length - s, depth - reach + pull))
        path.addLine(to: point(length - s, s))
        // Trailing shoulder.
        path.addCurve(to: point(length, 0), control1: point(length - s, s - down), control2: point(length - along, 0))
        if closed {
            path.addLine(to: point(length, -Self.bleed))
            path.closeSubpath()
        }
        return path
    }

    /// How far along each side a corner of radius 1 starts.
    static let cornerReach: CGFloat = 1.22
    /// How far each control point sits towards the corner, as a share of the reach.
    static let cornerPull: CGFloat = 0.62
}

/// `IslandSilhouette` without its attached side: an open path from shoulder to shoulder for an attached
/// island, the full outline for a floating one.
public struct IslandSilhouetteOutline: Shape {
    public var silhouette: IslandSilhouette

    public var animatableData: IslandSilhouette.AnimatableData {
        get { silhouette.animatableData }
        set { silhouette.animatableData = newValue }
    }

    public func path(in bounds: CGRect) -> Path {
        let rect = silhouette.islandFrame.map { $0.offsetBy(dx: bounds.minX, dy: bounds.minY) } ?? bounds
        guard rect.width > 0, rect.height > 0 else { return Path() }
        switch silhouette.style {
        case .floating: return silhouette.filling.path(in: rect)
        case .attached: return silhouette.attachedPath(in: rect, closed: false)
        }
    }
}

/// The glass's reaction to urgency: a faint band tint and a thin rim light.
struct IslandGlass: Equatable {
    var tint: Color?
    var rim: Color?

    static let calm = IslandGlass(tint: nil, rim: nil)

    init(tint: Color?, rim: Color?) {
        self.tint = tint
        self.rim = rim
    }

    /// A bright white rim while the carried island is locked onto a snap target.
    static let snappedRim = Color.white.opacity(0.35)

    /// Tint follows the worst visible band; the rim lights up in the attention colour while an agent waits,
    /// otherwise in the band colour. Nothing at all when the user turned the effect off.
    ///
    /// - Parameters:
    ///   - snapped: The carry is locked onto a snap target: the rim turns white for that moment, whatever the
    ///     urgency, so the lock is visible and not only felt.
    ///   - fused: The island is drawn inside the camera notch: no rim at all, or it would outline the notch.
    init(glowsWithUrgency: Bool, urgency: UsageBand?, waiting: Bool, snapped: Bool = false, fused: Bool = false) {
        guard !fused else {
            self.init(tint: nil, rim: nil)
            return
        }
        guard glowsWithUrgency else {
            self.init(tint: nil, rim: snapped ? Self.snappedRim : nil)
            return
        }
        self.init(
            tint: Theme.glassTint(for: urgency),
            rim: snapped ? Self.snappedRim : Theme.rim(for: urgency, waiting: waiting)
        )
    }

    /// The rim gradient runs from the screen edge (brightest, where the concave shoulders are) to the free side.
    static func rimAxis(edge: ScreenEdge) -> (start: UnitPoint, end: UnitPoint) {
        switch edge {
        case .top: (.top, .bottom)
        case .bottom: (.bottom, .top)
        case .left: (.leading, .trailing)
        case .right: (.trailing, .leading)
        }
    }

    /// The same axis for an island occupying `island` of a larger view of `size`, in that view's unit space.
    static func rimAxis(edge: ScreenEdge, island: CGRect?, in size: CGSize?) -> (start: UnitPoint, end: UnitPoint) {
        guard let island, let size, size.width > 0, size.height > 0 else { return rimAxis(edge: edge) }
        let minX = island.minX / size.width
        let maxX = island.maxX / size.width
        let minY = island.minY / size.height
        let maxY = island.maxY / size.height
        let midX = (minX + maxX) / 2
        let midY = (minY + maxY) / 2
        return switch edge {
        case .top: (UnitPoint(x: midX, y: minY), UnitPoint(x: midX, y: maxY))
        case .bottom: (UnitPoint(x: midX, y: maxY), UnitPoint(x: midX, y: minY))
        case .left: (UnitPoint(x: minX, y: midY), UnitPoint(x: maxX, y: midY))
        case .right: (UnitPoint(x: maxX, y: midY), UnitPoint(x: minX, y: midY))
        }
    }

    /// Opacity along the rim axis: full at the shoulders, calm along the free side.
    static let rimStops: [(location: CGFloat, opacity: Double)] = [(0, 1), (0.18, 0.8), (1, 0.3)]

    /// Opacity of the inner highlight that catches light on the free side; the system glass draws its own.
    static func highlightOpacity(for surface: IslandSurface) -> Double {
        switch surface {
        case .glass: 0.05
        case .darkGlass: 0.16
        case .solid: 0.13
        }
    }

    /// Opacity of the specular glint concentrated in the middle of the free side, like light on a curved liquid
    /// surface; faint on the system glass, which has its own.
    static func glintOpacity(for surface: IslandSurface) -> Double {
        switch surface {
        case .glass: 0.16
        case .darkGlass: 0.42
        case .solid: 0.38
        }
    }

    /// How much light the dark surfaces gather towards their free side (a whisper of white over the fill), so a
    /// solid island has depth instead of a flat cut-out; none on the system glass.
    static func liftOpacity(for surface: IslandSurface) -> Double {
        switch surface {
        case .glass: 0
        case .darkGlass: 0.035
        case .solid: 0.06
        }
    }

    /// The glint's reach along the free side, in points: about a third of the island's length along the edge.
    static func glintRadius(edge: ScreenEdge, island: CGRect?, in size: CGSize) -> CGFloat {
        let rect = island ?? CGRect(origin: .zero, size: size)
        let length = edge.isHorizontal ? rect.width : rect.height
        return max(24, length * 0.34)
    }
}

/// Applies the chosen surface behind the island's content, with urgency tint, rim light and edge highlight.
struct IslandSurfaceModifier<IslandShape: IslandOutlinedShape>: ViewModifier {
    let surface: IslandSurface
    let shape: IslandShape
    var glass: IslandGlass = .calm
    /// The size of the view the shape is drawn in, when the island occupies only `shape.islandFrame` of it.
    var stageSize: CGSize?

    private var axis: (start: UnitPoint, end: UnitPoint) {
        IslandGlass.rimAxis(edge: shape.edge, island: shape.envelope, in: stageSize)
    }

    func body(content: Content) -> some View {
        surfaced(content)
            .overlay {
                // The very same (animating) shape as the glass and the clip, so the rim can never drift from the
                // edge during a morph; only the gradient axis is aimed at the island's rect inside the stage.
                IslandRimLight(
                    shape: shape,
                    axis: axis,
                    surface: surface,
                    rim: glass.rim
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .animation(Motion.content, value: glass)
    }

    @ViewBuilder
    private func surfaced(_ content: Content) -> some View {
        let floating = shape.isFloating
        switch surface {
        case .glass:
            // Interactive glass reacts to presses by swelling; an attached island must stay fused to the bezel.
            content
                .glassEffect(Glass.regular.tint(glass.tint).interactive(floating), in: shape)
        case .darkGlass:
            content
                .environment(\.colorScheme, .dark)
                .background { backing(Color.black.opacity(0.52), floating: floating) }
                .glassEffect(Glass.clear.interactive(floating), in: shape)
        case .solid:
            content
                .environment(\.colorScheme, .dark)
                .background { backing(Color.black, floating: floating) }
        }
    }

    /// The dark fill under dark glass and solid surfaces, tinted by urgency; floating islands cast a soft
    /// shadow, attached ones none so they fuse with the bezel.
    private func backing(_ fill: Color, floating: Bool) -> some View {
        ZStack {
            shape.fill(fill)
            if let tint = glass.tint {
                shape.fill(tint)
            }
            // Depth: a plain fill faded in towards the free side by a gradient mask (Core Animation, even mid-morph).
            shape.fill(Color.white.opacity(IslandGlass.liftOpacity(for: surface)))
                .mask { AxisRamp(axis: axis, stops: [(0, 0), (0.35, 0.25), (1, 1)], outset: 0) }
        }
        .compositingGroup()
        .shadow(color: .black.opacity(floating ? 0.3 : 0), radius: floating ? 14 : 0, y: floating ? 5 : 0)
    }
}

/// A thin rim light along the free outline (brightest at the shoulders), a faint inner highlight and a specular glint
/// in the middle of the free side.
private struct IslandRimLight<IslandShape: IslandOutlinedShape>: View {
    let shape: IslandShape
    let axis: (start: UnitPoint, end: UnitPoint)
    let surface: IslandSurface
    let rim: Color?

    /// How far the masks reach past the view, so the rim's outer glow is never cut off.
    private static var maskOutset: CGFloat { 8 }

    var body: some View {
        let outline = shape.rimOutline
        // Every stroke is a plain colour faded along the axis by a gradient mask. A gradient-filled stroke would be
        // repainted on the CPU (on the main thread) for every frame of the morph, which made opening and folding
        // drop frames; plain strokes and gradient masks are drawn by Core Animation.
        ZStack {
            // Inner highlight: stroked twice as wide and clipped, so only its inner half shows.
            outline
                .stroke(Color.white.opacity(IslandGlass.highlightOpacity(for: surface)), lineWidth: 2)
                .mask { AxisRamp(axis: axis, stops: [(0, 0), (1, 1)], outset: Self.maskOutset) }
                .clipShape(shape)
                .blendMode(.plusLighter)

            // Specular glint: the same kind of stroke, gathered around the middle of the free side by a radial mask.
            // The mask stays where the island will be, so a morph flows through the light like liquid past a lamp.
            outline
                .stroke(Color.white.opacity(IslandGlass.glintOpacity(for: surface)), lineWidth: 2.4)
                .mask {
                    GeometryReader { proxy in
                        RadialGradient(
                            colors: [.black, .black.opacity(0.35), .clear],
                            center: axis.end,
                            startRadius: 0,
                            endRadius: IslandGlass.glintRadius(edge: shape.edge, island: shape.envelope, in: proxy.size)
                        )
                    }
                }
                .clipShape(shape)
                .blendMode(.plusLighter)

            if let rim {
                ZStack {
                    outline
                        .stroke(rim, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                        .blur(radius: 3)
                        .opacity(0.55)
                    outline
                        .stroke(rim, style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
                }
                .mask { AxisRamp(axis: axis, stops: IslandGlass.rimStops, outset: Self.maskOutset) }
            }
        }
    }
}

/// Opacity stops along an axis as a gradient mask covering the view and `outset` points around it.
private struct AxisRamp: View {
    let axis: (start: UnitPoint, end: UnitPoint)
    let stops: [(location: CGFloat, opacity: Double)]
    let outset: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            LinearGradient(
                stops: stops.map { .init(color: .black.opacity($0.opacity), location: $0.location) },
                startPoint: Self.outset(axis.start, size: size, by: outset),
                endPoint: Self.outset(axis.end, size: size, by: outset)
            )
            .frame(width: size.width + outset * 2, height: size.height + outset * 2)
            .offset(x: -outset, y: -outset)
        }
    }

    /// The unit point of a view of `size` expressed in the same view grown by `outset` on every side.
    static func outset(_ point: UnitPoint, size: CGSize, by outset: CGFloat) -> UnitPoint {
        guard size.width > 0, size.height > 0 else { return point }
        return UnitPoint(
            x: (point.x * size.width + outset) / (size.width + outset * 2),
            y: (point.y * size.height + outset) / (size.height + outset * 2)
        )
    }
}
