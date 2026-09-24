import CodometerCore
import SwiftUI

/// One account's ring travelling between its rail dial and its deck dial.
///
/// Both rects are the dials' **ring boxes** (the gauge frame without its orbit margin) in the island stage's
/// coordinate space, which is what `RingAnchorSink` collects.
public struct RingFlightPair: Equatable, Sendable, Identifiable {
    public let id: AccountID
    public let rail: CGRect
    public let deck: CGRect

    public init(id: AccountID, rail: CGRect, deck: CGRect) {
        self.id = id
        self.rail = rail
        self.deck = deck
    }
}

/// Chooses which accounts fly between the rail and the deck.
public enum RingFlightPlanner {
    /// At most this many rings fly at once: more would be visual clutter, and each one costs a view.
    public static let maximumPairs = 8

    /// Pairs for accounts that have a measured dial on **both** sides, in `order`.
    ///
    /// An account is left out when either box is missing or empty (it is filtered out of the rail by a group filter,
    /// or its deck dial has not been laid out), or when its deck dial is not fully inside `deckViewport` (the dial row
    /// scrolls horizontally when there are more accounts than fit). A `nil` viewport does not clip.
    public static func pairs(
        rail: [AccountID: CGRect],
        deck: [AccountID: CGRect],
        deckViewport: CGRect?,
        order: [AccountID]
    ) -> [RingFlightPair] {
        var pairs: [RingFlightPair] = []
        var seen: Set<AccountID> = []
        for id in order {
            guard pairs.count < maximumPairs, seen.insert(id).inserted else { continue }
            guard let railBox = rail[id], let deckBox = deck[id] else { continue }
            guard Self.isUsable(railBox), Self.isUsable(deckBox) else { continue }
            if let deckViewport, !Self.contains(deckViewport, deckBox) { continue }
            pairs.append(RingFlightPair(id: id, rail: railBox, deck: deckBox))
        }
        return pairs
    }

    private static func isUsable(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite && rect.width > 0 && rect.height > 0
            && rect.origin.x.isFinite && rect.origin.y.isFinite
    }

    /// `CGRect.contains(_:)` with a hair of tolerance, so a dial exactly on the viewport's edge still flies.
    private static func contains(_ viewport: CGRect, _ rect: CGRect) -> Bool {
        guard isUsable(viewport) else { return true }
        let slack: CGFloat = 0.5
        return rect.minX >= viewport.minX - slack && rect.maxX <= viewport.maxX + slack
            && rect.minY >= viewport.minY - slack && rect.maxY <= viewport.maxY + slack
    }
}

/// Where a flying ring is at a moment of the flight. Pure, so every curve is testable without views.
public enum RingFlightPath {
    /// How far out of the screen edge the arc bows, as a share of the travel between the two dials.
    public static let bow: CGFloat = 0.18
    /// The diameter eases with `progress` raised to this power, so the ring grows a little later than it travels.
    public static let diameterEase: CGFloat = 1.15
    /// The crossfade between the rail-style ring and the deck-style stack runs over this range of the flight.
    public static let crossfadeRange: ClosedRange<CGFloat> = 0.25...0.75

    /// The ring box at `progress` (0 = the rail dial, 1 = the deck dial).
    ///
    /// The centre follows a quadratic Bézier whose control point is pushed `bow` of the travel **away from the screen
    /// edge**, so rings drop out of the island with the droplet instead of sliding along it. Progress outside 0…1
    /// (a spring's overshoot) is clamped, so an overshooting open never pushes rings past their dials.
    public static func box(for pair: RingFlightPair, progress: CGFloat, edge: ScreenEdge) -> CGRect {
        let t = clamp(progress)
        let from = CGPoint(x: pair.rail.midX, y: pair.rail.midY)
        let to = CGPoint(x: pair.deck.midX, y: pair.deck.midY)
        let control = controlPoint(from: from, to: to, edge: edge)
        let centre = quadratic(from: from, control: control, to: to, t: t)
        let eased = t == 0 ? 0 : pow(t, diameterEase)
        let width = pair.rail.width + (pair.deck.width - pair.rail.width) * eased
        let height = pair.rail.height + (pair.deck.height - pair.rail.height) * eased
        return CGRect(x: centre.x - width / 2, y: centre.y - height / 2, width: width, height: height)
    }

    /// Opacity of the rail-style single ring and of the deck-style stack at `progress`; they always sum to 1.
    public static func crossfade(_ progress: CGFloat) -> (rail: Double, deck: Double) {
        let t = clamp(progress)
        let lower = crossfadeRange.lowerBound
        let upper = crossfadeRange.upperBound
        let deck: CGFloat
        if t <= lower {
            deck = 0
        } else if t >= upper {
            deck = 1
        } else {
            let x = (t - lower) / (upper - lower)
            deck = x * x * (3 - 2 * x)
        }
        return (rail: Double(1 - deck), deck: Double(deck))
    }

    /// The Bézier control point: the midpoint pushed away from the screen edge.
    static func controlPoint(from: CGPoint, to: CGPoint, edge: ScreenEdge) -> CGPoint {
        let travel = hypot(to.x - from.x, to.y - from.y)
        let push = travel * bow
        let away = outward(edge)
        return CGPoint(x: (from.x + to.x) / 2 + away.dx * push, y: (from.y + to.y) / 2 + away.dy * push)
    }

    /// The direction away from the screen edge, in the island stage's coordinates (origin top-left).
    static func outward(_ edge: ScreenEdge) -> CGVector {
        switch edge {
        case .top: CGVector(dx: 0, dy: 1)
        case .bottom: CGVector(dx: 0, dy: -1)
        case .left: CGVector(dx: 1, dy: 0)
        case .right: CGVector(dx: -1, dy: 0)
        }
    }

    private static func quadratic(from: CGPoint, control: CGPoint, to: CGPoint, t: CGFloat) -> CGPoint {
        let inverse = 1 - t
        let a = inverse * inverse
        let b = 2 * inverse * t
        let c = t * t
        return CGPoint(x: a * from.x + b * control.x + c * to.x, y: a * from.y + b * control.y + c * to.y)
    }

    private static func clamp(_ progress: CGFloat) -> CGFloat {
        guard progress.isFinite else { return 0 }
        return min(max(progress, 0), 1)
    }
}

/// Reports the deck's dial row as the viewport a dial has to be inside to fly.
///
/// The row scrolls horizontally when there are more accounts than fit; an account scrolled out of sight has a ring
/// box outside this rect and simply does not fly.
struct DeckViewportReporter: ViewModifier {
    @Environment(\.ringAnchorSink) private var sink

    func body(content: Content) -> some View {
        if let sink {
            content
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named(RingAnchorSink.coordinateSpace))
                } action: { frame in
                    sink.deckViewport = frame
                }
                .onDisappear {
                    sink.deckViewport = nil
                }
        } else {
            content
        }
    }
}

// MARK: - Rendering

/// The flying rings, drawn above the rail and the deck inside the island's clip.
///
/// Draw-only: it never lays anything out, takes no clicks and is hidden from VoiceOver (the real dials keep their
/// labels). Each ring is built once, at the deck's diameter, and only scaled and moved by the render server.
struct RingFlightLayer: View {
    let pairs: [RingFlightPair]
    let progress: CGFloat
    let edge: ScreenEdge
    let accounts: [AccountID: AccountPresentation]
    let deckDiameter: CGFloat
    let showsInnerRings: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(pairs) { pair in
                if let presentation = accounts[pair.id] {
                    FlightRing(
                        pair: pair,
                        progress: progress,
                        edge: edge,
                        presentation: presentation,
                        diameter: deckDiameter,
                        showsInnerRings: showsInnerRings
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One flying ring: the rail's single ring crossfading into the deck's ring stack, both drawn at the deck's
/// diameter and scaled down to wherever the flight currently is.
private struct FlightRing: View {
    let pair: RingFlightPair
    let progress: CGFloat
    let edge: ScreenEdge
    let presentation: AccountPresentation
    let diameter: CGFloat
    let showsInnerRings: Bool

    var body: some View {
        ZStack {
            stack(maximumRings: 1)
                .modifier(FlightFade(progress: progress, isRailStyle: true))
            stack(maximumRings: showsInnerRings ? RingGeometry.maximumRings : 1)
                .modifier(FlightFade(progress: progress, isRailStyle: false))
        }
        .modifier(FlightPlacement(progress: progress, pair: pair, edge: edge, diameter: diameter))
    }

    /// A ring stack without the activity orbit: the real dials keep their orbits, and a flying copy of one would
    /// start a second Core Animation layer for the length of the flight.
    private func stack(maximumRings: Int) -> some View {
        RingStack(
            specs: RingGeometry.specs(
                headline: presentation.headline,
                windows: presentation.windows,
                maximumRings: maximumRings,
                diameter: diameter
            ),
            diameter: diameter,
            orbitMargin: 0,
            isStale: presentation.isStale,
            activity: nil
        ) {
            ProviderGlyph(provider: presentation.provider, tinted: false)
                .foregroundStyle(presentation.isStale ? .tertiary : .secondary)
        }
    }
}

/// Places a flying ring: `animatableData` is the flight's progress, so the whole flight is one animated number
/// and the scale and position it produces are render-server transforms.
private struct FlightPlacement: ViewModifier, Animatable {
    var progress: CGFloat
    let pair: RingFlightPair
    let edge: ScreenEdge
    let diameter: CGFloat

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let box = RingFlightPath.box(for: pair, progress: progress, edge: edge)
        return content
            .scaleEffect(diameter > 0 ? box.width / diameter : 1)
            .position(x: box.midX, y: box.midY)
    }
}

/// Crossfades one of the two ring styles along the same animated progress.
private struct FlightFade: ViewModifier, Animatable {
    var progress: CGFloat
    let isRailStyle: Bool

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let fade = RingFlightPath.crossfade(progress)
        return content.opacity(isRailStyle ? fade.rail : fade.deck)
    }
}
