import CodometerCore
@testable import CodometerUI
import AppKit
import Foundation
import SwiftUI
import Testing

/// Typical island configurations (stage coordinates: the union of rail and deck).
enum LiquidFixture {
    struct Case: CustomStringConvertible, Sendable {
        let name: String
        let edge: ScreenEdge
        let style: IslandStyle
        let rail: CGRect
        let deck: CGRect

        var description: String { name }

        var attachment: CGFloat { style == .attached ? 1 : 0 }

        func morph(progress: CGFloat, swell: CGFloat = 0, wobble: CGFloat = 6, liquid: Bool = true) -> LiquidMorph {
            let metrics = IslandMetrics(scale: 1)
            return LiquidMorph(
                edge: edge,
                attachment: attachment,
                rail: rail,
                deck: deck,
                railCorner: style == .attached ? metrics.railCorner : 999,
                deckCorner: metrics.deckCorner,
                shoulder: metrics.shoulder,
                progress: progress,
                swell: swell,
                wobble: wobble,
                isLiquid: liquid
            )
        }

        var stage: CGRect { rail.union(deck) }
    }

    static let deckSize = CGSize(width: 412, height: 720)

    static let topCentre = Case(
        name: "top-centre-attached",
        edge: .top,
        style: .attached,
        rail: CGRect(x: 78, y: 0, width: 256, height: 48),
        deck: CGRect(origin: .zero, size: deckSize)
    )
    static let rightCentre = Case(
        name: "right-centre-attached",
        edge: .right,
        style: .attached,
        rail: CGRect(x: 412 - 66, y: 270, width: 66, height: 180),
        deck: CGRect(origin: .zero, size: deckSize)
    )
    static let bottomFloating = Case(
        name: "bottom-centre-floating",
        edge: .bottom,
        style: .floating,
        rail: CGRect(x: 90, y: 720 - 40, width: 232, height: 40),
        deck: CGRect(origin: .zero, size: deckSize)
    )
    static let leftNearTop = Case(
        name: "left-top-attached",
        edge: .left,
        style: .attached,
        rail: CGRect(x: 0, y: 0, width: 66, height: 180),
        deck: CGRect(origin: .zero, size: deckSize)
    )
    static let topLeadingFloating = Case(
        name: "top-leading-floating",
        edge: .top,
        style: .floating,
        rail: CGRect(x: 0, y: 0, width: 150, height: 40),
        deck: CGRect(origin: .zero, size: deckSize)
    )
    static let rightNarrow = Case(
        name: "right-narrow-floating",
        edge: .right,
        style: .floating,
        rail: CGRect(x: 412 - 44, y: 300, width: 44, height: 84),
        deck: CGRect(origin: .zero, size: deckSize)
    )

    static let all: [Case] = [topCentre, rightCentre, bottomFloating, leftNearTop, topLeadingFloating, rightNarrow]
}

@Suite("Liquid morph")
struct LiquidMorphTests {
    static let steps: [CGFloat] = (0...20).map { CGFloat($0) / 20 }

    @Test("At rest the outline is the rail and at the end the deck", arguments: LiquidFixture.all)
    func endpoints(fixture: LiquidFixture.Case) {
        let rail = fixture.morph(progress: 0).path(in: .zero).boundingRect
        let deck = fixture.morph(progress: 1).path(in: .zero).boundingRect
        Self.expectCovers(rail, fixture.rail, edge: fixture.edge, attached: fixture.style == .attached)
        Self.expectCovers(deck, fixture.deck, edge: fixture.edge, attached: fixture.style == .attached)
    }

    @Test("The deck at rest matches the attached silhouette", arguments: [LiquidFixture.topCentre, LiquidFixture.rightCentre, LiquidFixture.leftNearTop])
    func deckMatchesSilhouette(fixture: LiquidFixture.Case) {
        let metrics = IslandMetrics(scale: 1)
        let silhouette = IslandSilhouette(edge: fixture.edge, style: .attached, cornerRadius: metrics.deckCorner, shoulder: metrics.shoulder, islandFrame: fixture.deck)
        let liquid = fixture.morph(progress: 1).path(in: .zero)
        let reference = silhouette.path(in: fixture.stage)
        for point in Self.probePoints(in: fixture.deck.insetBy(dx: -4, dy: -4), count: 40) {
            #expect(liquid.contains(point) == reference.contains(point), "\(fixture) \(point)")
        }
    }

    @Test("Every frame stays inside the stage and its margin, fused to the screen edge", arguments: LiquidFixture.all)
    func bounds(fixture: LiquidFixture.Case) {
        let margin: CGFloat = 20
        let allowed = Self.allowedRect(fixture: fixture, margin: margin)
        for progress in Self.steps + [-0.03, 1.02, 1.06] {
            for swell in [CGFloat(0), 1] {
                let path = fixture.morph(progress: progress, swell: swell).path(in: .zero)
                let box = path.boundingRect
                #expect(allowed.contains(box), "\(fixture) p=\(progress) swell=\(swell) \(box)")
                if fixture.style == .attached {
                    // The screen side bleeds past the edge for the whole morph.
                    let edgePoint = Self.edgeProbe(fixture: fixture, progress: progress)
                    #expect(path.contains(edgePoint), "\(fixture) p=\(progress) edge \(edgePoint)")
                }
            }
        }
    }

    @Test("The path is one closed contour with finite points", arguments: LiquidFixture.all)
    func closedContour(fixture: LiquidFixture.Case) {
        for progress in Self.steps {
            let path = fixture.morph(progress: progress).path(in: .zero)
            var moves = 0
            var closes = 0
            var finite = true
            path.forEach { element in
                switch element {
                case .move(let point):
                    moves += 1
                    finite = finite && point.x.isFinite && point.y.isFinite
                case .line(let point):
                    finite = finite && point.x.isFinite && point.y.isFinite
                case .quadCurve(let point, let control):
                    finite = finite && point.x.isFinite && control.y.isFinite
                case .curve(let point, let control1, let control2):
                    finite = finite && point.x.isFinite && point.y.isFinite && control1.x.isFinite && control2.y.isFinite
                case .closeSubpath:
                    closes += 1
                }
            }
            #expect(moves == 1, "\(fixture) p=\(progress)")
            #expect(closes == 1, "\(fixture) p=\(progress)")
            #expect(finite, "\(fixture) p=\(progress)")
            #expect(Self.selfIntersections(of: path) == 0, "\(fixture) p=\(progress)")
        }
    }

    @Test("Area grows with progress (a small wobble aside)", arguments: LiquidFixture.all)
    func monotonicArea(fixture: LiquidFixture.Case) {
        var previous = -CGFloat.infinity
        for progress in Self.steps {
            let area = Self.area(of: fixture.morph(progress: progress).path(in: .zero))
            #expect(area >= previous - 1, "\(fixture) p=\(progress) \(area) < \(previous)")
            previous = area
        }
        let deck = Self.area(of: fixture.morph(progress: 1).path(in: .zero))
        let overshoot = Self.area(of: fixture.morph(progress: 1.05).path(in: .zero))
        #expect(overshoot >= deck)
        // The wobble is bounded by its amplitude along the free side.
        let freeLength = fixture.edge.isHorizontal ? fixture.deck.width : fixture.deck.height
        #expect(overshoot - deck <= freeLength * 6)
    }

    @Test("An overshooting spring only bows the free side, by at most the wobble, never along the edge", arguments: LiquidFixture.all)
    func wobbleBound(fixture: LiquidFixture.Case) {
        let deck = fixture.morph(progress: 1).path(in: .zero).boundingRect
        for progress: CGFloat in [1.01, 1.04, 1.2, 2] {
            let box = fixture.morph(progress: progress, wobble: 5).path(in: .zero).boundingRect
            let bow: CGFloat = switch fixture.edge {
            case .top: box.maxY - deck.maxY
            case .bottom: deck.minY - box.minY
            case .left: box.maxX - deck.maxX
            case .right: deck.minX - box.minX
            }
            #expect(bow >= 0, "\(fixture) p=\(progress)")
            #expect(bow <= 5 + 0.01, "\(fixture) p=\(progress)")
            if fixture.edge.isHorizontal {
                #expect(abs(box.minX - deck.minX) < 0.01 && abs(box.maxX - deck.maxX) < 0.01, "\(fixture) p=\(progress)")
            } else {
                #expect(abs(box.minY - deck.minY) < 0.01 && abs(box.maxY - deck.maxY) < 0.01, "\(fixture) p=\(progress)")
            }
        }
        // Undershoot past the rail is a small recoil of the rail's free side, not a smaller island.
        let rail = fixture.morph(progress: 0).path(in: .zero).boundingRect
        let recoil = fixture.morph(progress: -0.05).path(in: .zero).boundingRect
        #expect(recoil.contains(rail.insetBy(dx: 0.5, dy: 0.5)))
    }

    @Test("A droplet leads: mid-way the free side reaches further at its centre than at its corners")
    func dropletLeads() {
        let fixture = LiquidFixture.topCentre
        let morph = fixture.morph(progress: 0.3)
        let outline = morph.outline()
        #expect(outline.protrusion > 10)
        #expect(outline.halfWidth > 10)
        #expect(outline.neckWidth > 0)
        let path = morph.path(in: .zero)
        let centre = CGPoint(x: fixture.rail.midX, y: outline.far + outline.protrusion - 2)
        #expect(path.contains(centre))
        let corner = CGPoint(x: outline.start + fixture.style.shoulderWidth + 2, y: outline.far + outline.protrusion - 2)
        #expect(!path.contains(corner))
    }

    @Test("Folding passes through the same droplet it opened with")
    func reversible() {
        let fixture = LiquidFixture.rightCentre
        for progress in Self.steps {
            #expect(fixture.morph(progress: progress).path(in: .zero) == fixture.morph(progress: progress).path(in: .zero))
        }
    }

    @Test("The hover swell bulges the rail's free side a few points only")
    func swell() {
        for fixture in LiquidFixture.all {
            let rest = fixture.morph(progress: 0).path(in: .zero).boundingRect
            let swollen = fixture.morph(progress: 0, swell: 1).path(in: .zero).boundingRect
            let growth: CGFloat = switch fixture.edge {
            case .top: swollen.maxY - rest.maxY
            case .bottom: rest.minY - swollen.minY
            case .left: swollen.maxX - rest.maxX
            case .right: rest.minX - swollen.minX
            }
            #expect(growth > 1, "\(fixture)")
            #expect(growth <= 6, "\(fixture)")
            // A spring overshooting the swell bulges a little deeper, never wider.
            let overshoot = fixture.morph(progress: 0, swell: 1.3).path(in: .zero).boundingRect
            let along = fixture.edge.isHorizontal ? (overshoot.width, swollen.width) : (overshoot.height, swollen.height)
            let depth = fixture.edge.isHorizontal ? (overshoot.height, swollen.height) : (overshoot.width, swollen.width)
            #expect(along.0 <= along.1 + 0.5, "\(fixture)")
            #expect(depth.0 <= depth.1 + 2, "\(fixture)")
            #expect(overshoot != swollen, "\(fixture)")
            // Only the free side moves.
            if fixture.edge.isHorizontal {
                #expect(abs(swollen.width - rest.width) < 0.5, "\(fixture)")
            } else {
                #expect(abs(swollen.height - rest.height) < 0.5, "\(fixture)")
            }
        }
    }

    @Test("The hover swell is one even arch: it rises along the whole stretch from the corner to the middle, not in a step")
    func swellArch() {
        // Top rail 256 × 48 at x 78: the free side is at y 48, its flat stretch runs from the corner's end
        // (x 78 + shoulder 12 + corner reach 16 × 1.22) to the middle (x 206).
        let fixture = LiquidFixture.topCentre
        let path = fixture.morph(progress: 0, swell: 1).path(in: .zero)
        func bottom(atX x: CGFloat) -> CGFloat {
            var y: CGFloat = 40
            while y < 60, path.contains(CGPoint(x: x, y: y + 0.005)) {
                y += 0.005
            }
            return y
        }
        let cornerEnd: CGFloat = 78 + 12 + 16 * 1.22
        let middle: CGFloat = 206
        let base = bottom(atX: cornerEnd)
        let lift = bottom(atX: middle) - base
        #expect(abs(base - 48) < 0.05)
        #expect(lift > 1 && lift <= 6)
        func rise(_ share: CGFloat) -> CGFloat {
            (bottom(atX: cornerEnd + (middle - cornerEnd) * share) - base) / lift
        }
        // An even ease over the stretch: about a fifth of the height at a quarter, half at the half, four fifths at three
        // quarters. Handles bunched at the stretch's middle (the lumpy swell) stay low for longer and then rise in a step.
        #expect((0.16...0.24).contains(rise(0.25)), "\(rise(0.25))")
        #expect(abs(rise(0.5) - 0.5) < 0.04, "\(rise(0.5))")
        #expect((0.76...0.84).contains(rise(0.75)), "\(rise(0.75))")
        var previous: CGFloat = -1
        for step in 0...20 {
            let value = rise(CGFloat(step) / 20)
            #expect(value >= previous - 0.005, "step \(step)")
            previous = value
        }
    }

    @Test("Without liquid motion the outline is a plain rounded rectangle growing in one step")
    func plainMorph() {
        let fixture = LiquidFixture.topCentre
        let half = fixture.morph(progress: 0.5, swell: 1, liquid: false)
        let outline = half.outline()
        #expect(outline.protrusion == 0)
        #expect(outline.halfWidth == 0)
        #expect(half.path(in: .zero).boundingRect.height > fixture.rail.height)
        #expect(fixture.morph(progress: 1.05, liquid: false).path(in: .zero).boundingRect.maxY <= fixture.deck.maxY + 0.5)
    }

    @Test("Animatable data round-trips every animated number")
    func animatableData() {
        var shape = LiquidIslandShape(morph: LiquidFixture.rightCentre.morph(progress: 0.25, swell: 0.5))
        let target = LiquidFixture.topCentre.morph(progress: 0.75, swell: 0.1)
        let vector = LiquidMorphVector(target)
        shape.animatableData = vector
        #expect(shape.morph.progress == 0.75)
        #expect(shape.morph.swell == 0.1)
        #expect(shape.morph.rail == target.rail)
        #expect(shape.morph.deck == target.deck)
        #expect(shape.morph.railCorner == target.railCorner)
        var half = vector
        half.scale(by: 0.5)
        #expect(abs((half + half).magnitudeSquared - vector.magnitudeSquared) < 0.0001)
        #expect((vector - vector) == .zero)
    }

    @Test("Corners clamp towards circles, so a floating rail is a capsule")
    func capsuleCorners() {
        let corner = LiquidMorph.Corner(radius: 999, limit: 20)
        #expect(corner.reach == 20)
        #expect(abs(corner.handle - LiquidMorph.circleHandle) < 0.001)
        let free = LiquidMorph.Corner(radius: 16, limit: 100)
        #expect(abs(free.reach - 16 * LiquidMorph.cornerReach) < 0.001)
        #expect(free.handle == LiquidMorph.cornerHandle)
        #expect(LiquidMorph.smoothstep(0.2, 0.4, 0.1) == 0)
        #expect(LiquidMorph.smoothstep(0.2, 0.4, 0.5) == 1)
        #expect(abs(LiquidMorph.smoothstep(0.2, 0.4, 0.3) - 0.5) < 0.0001)
    }

    @Test(
        "Any rail and deck size, from an empty round rail to one wider than the deck, morphs without spikes or crossings",
        arguments: [ScreenEdge.top, .bottom, .left, .right]
    )
    func anySize(edge: ScreenEdge) {
        // (along the edge, depth) at scale 1: an empty or single rail, typical and very long rails.
        let rails: [(CGFloat, CGFloat)] = [(36, 36), (48, 44), (56, 48), (72, 48), (256, 48), (720, 52)]
        let decks: [(CGFloat, CGFloat)] = [(412, 720), (300, 180), (412, 90)]
        let progresses = (0...12).map { CGFloat($0) / 12 } + [-0.04, 1.03]
        var failures: [String] = []
        for scale in [CGFloat(0.85), 1.25] {
            let metrics = IslandMetrics(scale: scale)
            for style in [IslandStyle.attached, .floating] {
                for (railAlong, railDepth) in rails {
                    for (deckAlong, deckDepth) in decks {
                        for alignment in [CGFloat(0), 0.5, 1] {
                            let (rail, deck) = Self.stage(
                                edge: edge,
                                rail: (railAlong * scale, railDepth * scale),
                                deck: (deckAlong * scale, deckDepth * scale),
                                alignment: alignment
                            )
                            let allowed = rail.union(deck).insetBy(dx: -metrics.windowMargin - LiquidMorph.bleed, dy: -metrics.windowMargin - LiquidMorph.bleed)
                            for swell in [CGFloat(0), 1.25] {
                                for progress in progresses {
                                    let morph = LiquidMorph(
                                        edge: edge,
                                        attachment: style == .attached ? 1 : 0,
                                        rail: rail,
                                        deck: deck,
                                        railCorner: style == .attached ? metrics.railCorner : 999,
                                        deckCorner: metrics.deckCorner,
                                        shoulder: metrics.shoulder,
                                        progress: progress,
                                        swell: swell,
                                        wobble: metrics.liquidWobble
                                    )
                                    let path = morph.path(in: .zero)
                                    let box = path.boundingRect
                                    let label = "\(style) ×\(scale) rail \(railAlong)×\(railDepth) deck \(deckAlong)×\(deckDepth) at \(alignment) swell \(swell) p \(progress)"
                                    guard !path.isEmpty, box.minX.isFinite, box.maxX.isFinite, box.minY.isFinite, box.maxY.isFinite else {
                                        failures.append("empty or not finite: \(label)")
                                        continue
                                    }
                                    if !allowed.contains(box) {
                                        failures.append("outside the margin: \(label)")
                                    }
                                    if Self.selfIntersections(of: path) > 0 {
                                        failures.append("crosses itself: \(label)")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        #expect(failures.isEmpty, "\(edge): \(failures.count) failures, e.g. \(failures.prefix(5))")
    }

    @Test("A rail fused with the camera notch morphs cleanly at every menu bar depth and wing width")
    func fusedRail() {
        // Wide and short, the shape a fused rail always has: two wings in a 32–38 pt menu bar, and a deck below.
        let rails: [(CGFloat, CGFloat)] = [(360, 32), (520, 32), (760, 38), (1_100, 38)]
        let decks: [(CGFloat, CGFloat)] = [(412, 720), (412, 220)]
        let progresses = (0...12).map { CGFloat($0) / 12 } + [-0.04, 1.03]
        var failures: [String] = []
        for scale in [CGFloat(0.85), 1.25] {
            let metrics = IslandMetrics(scale: scale)
            // The fused rail's own corner and shoulders (`IslandRootView.fusedRailCorner` / `fusedShoulder`).
            for menuBar in [CGFloat(32), 38] {
                let corner = min(metrics.railCorner, menuBar * 0.3)
                let shoulder = 6 * scale
                for (railAlong, railDepth) in rails {
                    for (deckAlong, deckDepth) in decks {
                        // A fused island is always centred on the notch.
                        let (rail, deck) = Self.stage(
                            edge: .top,
                            rail: (railAlong * scale, railDepth * scale),
                            deck: (deckAlong * scale, deckDepth * scale),
                            alignment: 0.5
                        )
                        let allowed = rail.union(deck).insetBy(dx: -metrics.windowMargin - LiquidMorph.bleed, dy: -metrics.windowMargin - LiquidMorph.bleed)
                        for swell in [CGFloat(0), 1.25] {
                            for progress in progresses {
                                let morph = LiquidMorph(
                                    edge: .top,
                                    attachment: 1,
                                    rail: rail,
                                    deck: deck,
                                    railCorner: corner,
                                    deckCorner: metrics.deckCorner,
                                    shoulder: shoulder,
                                    progress: progress,
                                    swell: swell,
                                    wobble: metrics.liquidWobble
                                )
                                let path = morph.path(in: .zero)
                                let box = path.boundingRect
                                let label = "×\(scale) menu bar \(menuBar) rail \(railAlong)×\(railDepth) deck \(deckAlong)×\(deckDepth) swell \(swell) p \(progress)"
                                guard !path.isEmpty, box.minX.isFinite, box.maxX.isFinite, box.minY.isFinite, box.maxY.isFinite else {
                                    failures.append("empty or not finite: \(label)")
                                    continue
                                }
                                if !allowed.contains(box) {
                                    failures.append("outside the margin: \(label)")
                                }
                                if Self.selfIntersections(of: path) > 0 {
                                    failures.append("crosses itself: \(label)")
                                }
                                // The silhouette has to stay joined to the screen edge in every frame.
                                if box.minY > rail.minY + 0.5 {
                                    failures.append("left the screen edge: \(label)")
                                }
                            }
                        }
                    }
                }
            }
        }
        #expect(failures.isEmpty, "fused: \(failures.count) failures, e.g. \(failures.prefix(5))")
    }

    @Test("A rail without a flat free side keeps its shape under the pointer")
    func noSwellWithoutRoom() {
        let metrics = IslandMetrics(scale: 1)
        let round = CGRect(x: 100, y: 0, width: 40, height: 40)
        let deck = CGRect(x: 0, y: 0, width: 412, height: 720)
        let rest = LiquidMorph(edge: .top, attachment: 0, rail: round, deck: deck, railCorner: 999, deckCorner: metrics.deckCorner, shoulder: metrics.shoulder, progress: 0)
        var hovered = rest
        hovered.swell = 1
        #expect(hovered.path(in: .zero).boundingRect == rest.path(in: .zero).boundingRect)
    }

    @Test("The droplet opens a little quicker than the plain unfold it replaces, and never visibly overshoots")
    func openTiming() {
        let spring = Spring(response: Motion.liquidOpenResponse, dampingRatio: Motion.liquidOpenDamping)
        // The outline's visible share of the way, as `LiquidMorph.outline()` eases progress.
        let shape = { (time: Double) in
            pow(min(max(spring.value(target: 1.0, initialVelocity: 0, time: time), 0), 1), Double(LiquidMorph.Tuning.progressEase))
        }
        let plain = Spring(response: 0.42, dampingRatio: 1)
        let plainShape = { (time: Double) in plain.value(target: 1.0, initialVelocity: 0, time: time) }
        let plainNinety = Self.firstTime { plainShape($0) >= 0.9 }
        let plainDone = Self.firstTime { plainShape($0) >= 0.98 }
        #expect(Self.firstTime { shape($0) >= 0.9 } <= plainNinety + 0.005)
        let done = Self.firstTime { shape($0) >= 0.98 }
        #expect(done <= plainDone * 0.95)
        #expect(done >= plainDone * 0.8, "only slightly quicker, not drastically")
        // Settled (within half a percent for good) by 0.42 s.
        #expect(Self.lastTime { abs(spring.value(target: 1.0, initialVelocity: 0, time: $0) - 1) > 0.005 } <= 0.42)
        // Any overshoot bows the free side by less than a fifth of a point.
        let peak = stride(from: 0.0, through: 1.5, by: 0.002).map { spring.value(target: 1.0, initialVelocity: 0, time: $0) }.max() ?? 0
        let bow = CGFloat(max(0, peak - 1)) / LiquidMorph.wobbleOvershoot * IslandMetrics(scale: 1.5).liquidWobble
        #expect(bow < 0.2)
        // The deck's content is in place by 0.4 s.
        let reveal = Spring.smooth(duration: Motion.deckRevealDuration)
        #expect(Motion.deckRevealDelay + Self.firstTime { reveal.value(target: 1.0, initialVelocity: 0, time: $0) >= 0.995 } <= 0.4)
    }

    @Test("The fold absorbs the droplet a little quicker than the plain fold it replaces")
    func foldTiming() {
        let spring = Spring(response: Motion.liquidFoldResponse, dampingRatio: Motion.liquidFoldDamping)
        let shape = { (time: Double) in
            pow(max(1 - spring.value(target: 1.0, initialVelocity: 0, time: time), 0), Double(LiquidMorph.Tuning.progressEase))
        }
        let plain = Spring(response: 0.42, dampingRatio: 1)
        let plainDone = Self.firstTime { 1 - plain.value(target: 1.0, initialVelocity: 0, time: $0) <= 0.02 }
        let done = Self.firstTime { shape($0) <= 0.02 }
        #expect(done <= plainDone * 0.95)
        #expect(done >= plainDone * 0.75, "only slightly quicker, not drastically")
        // Never past the rail: no recoil.
        let lowest = stride(from: 0.0, through: 1.5, by: 0.002).map { 1 - spring.value(target: 1.0, initialVelocity: 0, time: $0) }.min() ?? 0
        #expect(lowest > -0.0005)
        // The rail's content is back by 0.4 s, after the droplet has mostly gone.
        let reveal = Spring.smooth(duration: Motion.railRevealDuration)
        #expect(Motion.railRevealDelay + Self.firstTime { reveal.value(target: 1.0, initialVelocity: 0, time: $0) >= 0.995 } <= 0.4)
        #expect(shape(Motion.railRevealDelay) < 0.35)
    }

    // MARK: - Helpers

    /// Rail and deck rects for an edge, both pinned to that edge and placed along it by `alignment` (0 start, 1 end).
    static func stage(edge: ScreenEdge, rail: (CGFloat, CGFloat), deck: (CGFloat, CGFloat), alignment: CGFloat) -> (CGRect, CGRect) {
        let along = max(rail.0, deck.0)
        let depth = max(rail.1, deck.1)
        func rect(_ item: (CGFloat, CGFloat)) -> CGRect {
            let offset = (along - item.0) * alignment
            return switch edge {
            case .top: CGRect(x: offset, y: 0, width: item.0, height: item.1)
            case .bottom: CGRect(x: offset, y: depth - item.1, width: item.0, height: item.1)
            case .left: CGRect(x: 0, y: offset, width: item.1, height: item.0)
            case .right: CGRect(x: depth - item.1, y: offset, width: item.1, height: item.0)
            }
        }
        return (rect(rail), rect(deck))
    }

    /// The first time, in 1 ms steps up to 2 s, at which `condition` holds; 2 when it never does.
    static func firstTime(_ condition: (Double) -> Bool) -> Double {
        stride(from: 0.0, through: 2, by: 0.001).first(where: condition) ?? 2
    }

    /// The last time, in 1 ms steps up to 2 s, at which `condition` holds; 0 when it never does.
    static func lastTime(_ condition: (Double) -> Bool) -> Double {
        stride(from: 0.0, through: 2, by: 0.001).reversed().first(where: condition) ?? 0
    }

    /// The stage plus the transparent margin on the free sides (none past an attached island's screen edge, where
    /// only the bleed may go).
    static func allowedRect(fixture: LiquidFixture.Case, margin: CGFloat) -> CGRect {
        var rect = fixture.stage.insetBy(dx: -margin, dy: -margin)
        guard fixture.style == .attached else { return rect }
        let bleed = LiquidMorph.bleed + 0.5
        switch fixture.edge {
        case .top:
            rect.origin.y = fixture.stage.minY - bleed
            rect.size.height = fixture.stage.height + bleed + margin
        case .bottom:
            rect.size.height = fixture.stage.height + bleed + margin
        case .left:
            rect.origin.x = fixture.stage.minX - bleed
            rect.size.width = fixture.stage.width + bleed + margin
        case .right:
            rect.size.width = fixture.stage.width + bleed + margin
        }
        return rect
    }

    static func expectCovers(_ box: CGRect, _ frame: CGRect, edge: ScreenEdge, attached: Bool) {
        let tolerance: CGFloat = 0.5
        let bleed = attached ? LiquidMorph.bleed : 0
        #expect(abs(box.minX - (edge == .left ? frame.minX - bleed : frame.minX)) < tolerance, "minX \(box) \(frame)")
        #expect(abs(box.maxX - (edge == .right ? frame.maxX + bleed : frame.maxX)) < tolerance, "maxX \(box) \(frame)")
        #expect(abs(box.minY - (edge == .top ? frame.minY - bleed : frame.minY)) < tolerance, "minY \(box) \(frame)")
        #expect(abs(box.maxY - (edge == .bottom ? frame.maxY + bleed : frame.maxY)) < tolerance, "maxY \(box) \(frame)")
    }

    /// A point just inside the screen edge, in the middle of the rail's span.
    static func edgeProbe(fixture: LiquidFixture.Case, progress: CGFloat) -> CGPoint {
        let rail = fixture.rail
        return switch fixture.edge {
        case .top: CGPoint(x: rail.midX, y: rail.minY + 0.5)
        case .bottom: CGPoint(x: rail.midX, y: rail.maxY - 0.5)
        case .left: CGPoint(x: rail.minX + 0.5, y: rail.midY)
        case .right: CGPoint(x: rail.maxX - 0.5, y: rail.midY)
        }
    }

    static func probePoints(in rect: CGRect, count: Int) -> [CGPoint] {
        (0...count).flatMap { row in
            (0...count).map { column in
                CGPoint(
                    x: rect.minX + rect.width * CGFloat(column) / CGFloat(count) + 0.37,
                    y: rect.minY + rect.height * CGFloat(row) / CGFloat(count) + 0.41
                )
            }
        }
    }

    /// The path flattened into a polygon.
    static func polygon(of path: Path, samples: Int = 12) -> [CGPoint] {
        var points: [CGPoint] = []
        var current = CGPoint.zero
        path.forEach { element in
            switch element {
            case .move(let point):
                points.append(point)
                current = point
            case .line(let point):
                points.append(point)
                current = point
            case .quadCurve(let point, let control):
                for step in 1...samples {
                    let t = CGFloat(step) / CGFloat(samples)
                    let a = (1 - t) * (1 - t)
                    let b = 2 * (1 - t) * t
                    let c = t * t
                    points.append(CGPoint(x: a * current.x + b * control.x + c * point.x, y: a * current.y + b * control.y + c * point.y))
                }
                current = point
            case .curve(let point, let control1, let control2):
                for step in 1...samples {
                    let t = CGFloat(step) / CGFloat(samples)
                    let a = (1 - t) * (1 - t) * (1 - t)
                    let b = 3 * (1 - t) * (1 - t) * t
                    let c = 3 * (1 - t) * t * t
                    let d = t * t * t
                    points.append(CGPoint(
                        x: a * current.x + b * control1.x + c * control2.x + d * point.x,
                        y: a * current.y + b * control1.y + c * control2.y + d * point.y
                    ))
                }
                current = point
            case .closeSubpath:
                break
            }
        }
        return points
    }

    static func area(of path: Path) -> CGFloat {
        let points = polygon(of: path)
        guard points.count > 2 else { return 0 }
        var sum: CGFloat = 0
        for index in points.indices {
            let a = points[index]
            let b = points[(index + 1) % points.count]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    /// Proper crossings between non-adjacent edges of the flattened outline.
    static func selfIntersections(of path: Path) -> Int {
        var points = polygon(of: path, samples: 8)
        // Drop repeated points so zero-length edges never count.
        points = points.reduce(into: []) { result, point in
            if let last = result.last, hypot(last.x - point.x, last.y - point.y) < 0.001 { return }
            result.append(point)
        }
        let count = points.count
        guard count > 3 else { return 0 }
        func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        var crossings = 0
        for i in 0..<count {
            let a1 = points[i]
            let a2 = points[(i + 1) % count]
            for j in stride(from: i + 2, to: count, by: 1) where !(i == 0 && j == count - 1) {
                let b1 = points[j]
                let b2 = points[(j + 1) % count]
                let d1 = cross(b1, b2, a1)
                let d2 = cross(b1, b2, a2)
                let d3 = cross(a1, a2, b1)
                let d4 = cross(a1, a2, b2)
                if ((d1 > 1e-6 && d2 < -1e-6) || (d1 < -1e-6 && d2 > 1e-6)) && ((d3 > 1e-6 && d4 < -1e-6) || (d3 < -1e-6 && d4 > 1e-6)) {
                    crossings += 1
                }
            }
        }
        return crossings
    }
}

extension IslandStyle {
    fileprivate var shoulderWidth: CGFloat {
        self == .attached ? IslandMetrics(scale: 1).shoulder : 0
    }
}

/// Renders the liquid morph frame by frame to PNG strips for visual review. Runs only when
/// `CODOMETER_LIQUID_SHOTS` names an output directory, e.g.
/// `CODOMETER_LIQUID_SHOTS=/tmp/liquid swift test --filter LiquidRender`.
@MainActor
@Suite("LiquidRender", .enabled(if: ProcessInfo.processInfo.environment["CODOMETER_LIQUID_SHOTS"] != nil))
struct LiquidRenderTests {
    private let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODOMETER_LIQUID_SHOTS"] ?? "/tmp", isDirectory: true)
    /// Appended to file names, so successive iterations never overwrite each other.
    private let tag = ProcessInfo.processInfo.environment["CODOMETER_LIQUID_TAG"].map { "-\($0)" } ?? ""
    static let progressSteps: [CGFloat] = (0...10).map { CGFloat($0) / 10 } + [1.04]

    @Test("Outline strips for every fixture")
    func outlineStrips() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for fixture in LiquidFixture.all {
            let cells = Self.progressSteps.map { progress in
                (label: String(format: "%.2f", Double(progress)), morph: fixture.morph(progress: progress))
            } + [0, 0.05, 0.1, 0.2].map { progress in
                (label: String(format: "swell %.2f", Double(progress)), morph: fixture.morph(progress: progress, swell: 1))
            } + [(label: "recoil", morph: fixture.morph(progress: -0.04))]
            try render(grid(cells: cells, fixture: fixture, columns: 7), name: "outline-\(fixture.name)", scale: 0.6)
        }
    }

    @Test("Mid-morph details at full size")
    func details() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for fixture in [LiquidFixture.rightCentre, LiquidFixture.topCentre, LiquidFixture.bottomFloating] {
            let cells = [0.25, 0.45, 0.55, 0.65].map { progress in
                (label: String(format: "%.2f", progress), morph: fixture.morph(progress: CGFloat(progress)))
            }
            try render(grid(cells: cells, fixture: fixture, columns: 4), name: "detail-\(fixture.name)", scale: 1)
        }
    }

    @Test("Zoomed junctions")
    func zoom() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cases: [(LiquidFixture.Case, CGFloat, CGRect)] = [
            (LiquidFixture.topCentre, 0.45, CGRect(x: 0, y: 0, width: 160, height: 160)),
            (LiquidFixture.topCentre, 0.55, CGRect(x: 0, y: 0, width: 160, height: 160)),
            (LiquidFixture.rightCentre, 0.45, CGRect(x: 252, y: 60, width: 160, height: 160)),
            (LiquidFixture.rightCentre, 0.55, CGRect(x: 252, y: 20, width: 160, height: 160)),
        ]
        let row = HStack(spacing: 8) {
            ForEach(Array(cases.enumerated()), id: \.offset) { _, item in
                let (fixture, progress, crop) = item
                ZStack(alignment: .topLeading) {
                    Self.wallpaper.frame(width: crop.width, height: crop.height)
                    LiquidIslandShape(morph: fixture.morph(progress: progress))
                        .fill(Color.black)
                        .frame(width: fixture.stage.width, height: fixture.stage.height)
                        .offset(x: -crop.minX, y: -crop.minY)
                        .frame(width: crop.width, height: crop.height, alignment: .topLeading)
                        .clipped()
                    LiquidIslandShape(morph: fixture.morph(progress: progress)).rimOutline
                        .stroke(Color.yellow, lineWidth: 0.4)
                        .frame(width: fixture.stage.width, height: fixture.stage.height)
                        .offset(x: -crop.minX, y: -crop.minY)
                        .frame(width: crop.width, height: crop.height, alignment: .topLeading)
                        .clipped()
                }
                .frame(width: crop.width, height: crop.height)
                .clipped()
            }
        }
        .padding(8)
        .background(Color.white)
        try render(row, name: "zoom", scale: 4)
    }

    @Test("The island with its content, frame by frame, on the solid surface")
    func islandStrips() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try LiquidStoreFixture.make()
        let configurations: [(String, ScreenEdge, IslandAnchor, IslandStyle)] = [
            ("island-right-centre-attached", .right, .trailing, .attached),
            ("island-top-centre-attached", .top, .top, .attached),
            ("island-bottom-centre-floating", .bottom, .bottom, .floating),
        ]
        for (name, edge, anchor, style) in configurations {
            let model = IslandModel(layout: IslandLayout(edge: edge, anchor: anchor, style: style, metrics: IslandMetrics(scale: 1)))
            let stage = measuredStage(store: store, model: model)
            let steps: [(String, CGFloat, CGFloat)] = Self.progressSteps.map { (String(format: "%.2f", Double($0)), $0, 0) }
                + [("swell", 0, 1)]
            let columns = edge.isHorizontal ? 5 : 4
            let rows = stride(from: 0, to: steps.count, by: columns).map { Array(steps[$0..<min($0 + columns, steps.count)]) }
            let grid = VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, step in
                            VStack(spacing: 4) {
                                islandFrame(store: store, model: model, stage: stage, progress: step.1, swell: step.2)
                                    .padding(24)
                                    .background(Self.wallpaper)
                                    .clipped()
                                Text(step.0)
                                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.black)
                            }
                        }
                    }
                }
            }
            .padding(12)
            .background(Color.white)
            try render(grid, name: name, scale: 0.6)
        }
    }

    @Test("Opening and folding sampled every 33 ms with the real springs")
    func timing() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try LiquidStoreFixture.make()
        let open = Spring(response: Motion.liquidOpenResponse, dampingRatio: Motion.liquidOpenDamping)
        let fold = Spring(response: Motion.liquidFoldResponse, dampingRatio: Motion.liquidFoldDamping)
        let reveal = Spring.smooth(duration: Motion.deckRevealDuration)
        let configurations: [(String, ScreenEdge, IslandAnchor, IslandStyle)] = [
            ("timing-top-centre-attached", .top, .top, .attached),
            ("timing-right-centre-attached", .right, .trailing, .attached),
        ]
        for (name, edge, anchor, style) in configurations {
            let model = IslandModel(layout: IslandLayout(edge: edge, anchor: anchor, style: style, metrics: IslandMetrics(scale: 1)))
            let stage = measuredStage(store: store, model: model)
            var frames: [(String, CGFloat, Double, Double)] = []
            for index in 0..<21 {
                let time = Double(index) * 0.033
                let progress = CGFloat(open.value(target: 1.0, initialVelocity: 0, time: time))
                let deck = time < Motion.deckRevealDelay ? 0 : min(1, reveal.value(target: 1.0, initialVelocity: 0, time: time - Motion.deckRevealDelay))
                let rail = max(0, 1 - time / 0.08)
                frames.append((String(format: "open %3.0f ms", time * 1_000), progress, deck, rail))
            }
            for index in 0..<15 {
                let time = Double(index) * 0.033
                let progress = CGFloat(1 - fold.value(target: 1.0, initialVelocity: 0, time: time))
                let deck = max(0, 1 - time / 0.09)
                let rail = time < Motion.railRevealDelay ? 0 : min(1, Spring.smooth(duration: Motion.railRevealDuration).value(target: 1.0, initialVelocity: 0, time: time - Motion.railRevealDelay))
                frames.append((String(format: "fold %3.0f ms", time * 1_000), progress, deck, rail))
            }
            let columns = edge.isHorizontal ? 9 : 6
            let rows = stride(from: 0, to: frames.count, by: columns).map { Array(frames[$0..<min($0 + columns, frames.count)]) }
            let grid = VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 6) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, frame in
                            VStack(spacing: 2) {
                                islandFrame(store: store, model: model, stage: stage, progress: frame.1, swell: 0, deckShown: frame.2, railShown: frame.3)
                                    .padding(20)
                                    .background(Self.wallpaper)
                                    .clipped()
                                Text(String(format: "%@ · %.2f", frame.0, Double(frame.1)))
                                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.black)
                            }
                        }
                    }
                }
            }
            .padding(10)
            .background(Color.white)
            try render(grid, name: name, scale: 0.4)
        }
    }

    @Test("The rail at rest: top and side, light and dark backdrops, solid and glass stand-in")
    func rails() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try LiquidStoreFixture.make(groups: true)
        let layouts: [(String, ScreenEdge, IslandAnchor, IslandStyle)] = [
            ("top", .top, .top, .attached),
            ("right", .right, .trailing, .attached),
            ("bottom-floating", .bottom, .bottom, .floating),
        ]
        for (name, edge, anchor, style) in layouts {
            let model = IslandModel(layout: IslandLayout(edge: edge, anchor: anchor, style: style, metrics: IslandMetrics(scale: 1)))
            let stage = measuredStage(store: store, model: model)
            let rail = IslandMorphLayout(size: stage.rail.size, rail: CGRect(origin: .zero, size: stage.rail.size), deck: CGRect(origin: .zero, size: stage.rail.size))
            let variants = HStack(spacing: 0) {
                ForEach([false, true], id: \.self) { dark in
                    VStack(spacing: 18) {
                        railIsland(store: store, model: model, stage: rail, surface: .solid, swell: 0)
                        railIsland(store: store, model: model, stage: rail, surface: .solid, swell: 1)
                        railIsland(store: store, model: model, stage: rail, surface: .glass, swell: 0)
                            .environment(\.colorScheme, dark ? .dark : .light)
                    }
                    .padding(28)
                    .background(dark ? AnyView(Self.darkWallpaper) : AnyView(Self.lightWallpaper))
                }
            }
            try render(variants, name: "rail-\(name)", scale: 2)
            if edge == .top {
                let close = HStack(spacing: 0) {
                    railIsland(store: store, model: model, stage: rail, surface: .solid, swell: 0)
                        .padding(20)
                        .background(Self.darkWallpaper)
                    railIsland(store: store, model: model, stage: rail, surface: .glass, swell: 0)
                        .padding(20)
                        .background(Self.lightWallpaper)
                }
                try render(close, name: "rail-top-close", scale: 3)
            }
        }
    }

    private func measuredStage(store: TrackerStore, model: IslandModel) -> IslandMorphLayout {
        let rail = NSHostingView(rootView: RailView(store: store, model: model, accounts: store.visiblePresentations)
            .environment(\.liveEffectsEnabled, false)).fittingSize
        let deck = NSHostingView(rootView: DeckContent(store: store, model: model, accounts: store.presentations, context: .island)
            .environment(\.liveEffectsEnabled, false)
            .environment(\.introAnimationsEnabled, false)).fittingSize
        return IslandMorphLayout.anchored(
            rail: CGSize(width: rail.width.rounded(.up), height: rail.height.rounded(.up)),
            deck: CGSize(width: deck.width.rounded(.up), height: deck.height.rounded(.up)),
            anchor: model.layout.anchor
        )
    }

    /// One frame of the morph as `IslandRootView` draws it, with the content's timing approximated from progress.
    private func islandFrame(
        store: TrackerStore,
        model: IslandModel,
        stage: IslandMorphLayout,
        progress: CGFloat,
        swell: CGFloat,
        deckShown explicitDeck: Double? = nil,
        railShown explicitRail: Double? = nil
    ) -> some View {
        var morph = IslandRootView.liquidShape(layout: model.layout, stage: stage, expanded: progress >= 0.5, swells: false, liquid: true).morph
        morph.progress = progress
        morph.swell = swell
        let shape = LiquidIslandShape(morph: morph)
        let deckShown = explicitDeck.map { CGFloat($0) } ?? LiquidMorph.smoothstep(0.55, 0.92, progress)
        let railShown = explicitRail.map { CGFloat($0) } ?? 1 - LiquidMorph.smoothstep(0, 0.12, progress)
        let layout = model.layout
        return ZStack(alignment: .topLeading) {
            DeckContent(store: store, model: model, accounts: store.presentations, context: .island)
                .fixedSize()
                .frame(width: stage.deck.width, height: stage.deck.height, alignment: layout.anchor.alignment)
                .opacity(deckShown)
                .scaleEffect(DeckRevealModifier.hiddenScale + (1 - DeckRevealModifier.hiddenScale) * deckShown, anchor: layout.anchor.unitPoint)
                .padding(.leading, stage.deck.minX)
                .padding(.top, stage.deck.minY)
            RailView(store: store, model: model, accounts: store.visiblePresentations)
                .fixedSize()
                .frame(width: stage.rail.width, height: stage.rail.height, alignment: layout.anchor.alignment)
                .opacity(railShown)
                .padding(.leading, stage.rail.minX)
                .padding(.top, stage.rail.minY)
        }
        .frame(width: stage.size.width, height: stage.size.height, alignment: .topLeading)
        .clipShape(shape)
        .modifier(IslandSurfaceModifier(
            surface: .solid,
            shape: shape,
            glass: IslandGlass(glowsWithUrgency: true, urgency: store.urgency, waiting: store.hasWaiting),
            stageSize: stage.size
        ))
    }

    private func railIsland(store: TrackerStore, model: IslandModel, stage: IslandMorphLayout, surface: IslandSurface, swell: CGFloat) -> some View {
        var morph = IslandRootView.liquidShape(layout: model.layout, stage: stage, expanded: false, swells: false, liquid: true).morph
        morph.swell = swell
        let shape = LiquidIslandShape(morph: morph)
        let glass = IslandGlass(glowsWithUrgency: true, urgency: store.urgency, waiting: store.hasWaiting)
        return RailView(store: store, model: model, accounts: store.visiblePresentations)
            .fixedSize()
            .frame(width: stage.size.width, height: stage.size.height)
            // `ImageRenderer` cannot draw Liquid Glass: a material stands in for it.
            .background { if surface == .glass { shape.fill(.regularMaterial) } }
            .clipShape(shape)
            .modifier(IslandSurfaceModifier(surface: surface, shape: shape, glass: glass, stageSize: stage.size))
            .padding(10)
    }

    static var lightWallpaper: some View {
        LinearGradient(colors: [Color(red: 0.93, green: 0.94, blue: 0.97), Color(red: 0.80, green: 0.86, blue: 0.95)], startPoint: .top, endPoint: .bottom)
    }

    static var darkWallpaper: some View {
        LinearGradient(colors: [Color(red: 0.10, green: 0.11, blue: 0.16), Color(red: 0.20, green: 0.16, blue: 0.30)], startPoint: .top, endPoint: .bottom)
    }

    private func grid(cells: [(label: String, morph: LiquidMorph)], fixture: LiquidFixture.Case, columns: Int) -> some View {
        let margin: CGFloat = 24
        let stage = fixture.stage
        let rows = stride(from: 0, to: cells.count, by: columns).map { Array(cells[$0..<min($0 + columns, cells.count)]) }
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 8) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        VStack(spacing: 4) {
                            Color.clear
                                .frame(width: stage.width, height: stage.height)
                                .modifier(IslandSurfaceModifier(surface: .solid, shape: LiquidIslandShape(morph: cell.morph)))
                                .padding(margin)
                                .background(Self.wallpaper)
                                .clipShape(Rectangle())
                            Text(cell.label)
                                .font(.system(size: 22, weight: .semibold, design: .rounded))
                                .foregroundStyle(.black)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color.white)
    }

    static var wallpaper: some View {
        LinearGradient(
            colors: [Color(red: 0.98, green: 0.55, blue: 0.40), Color(red: 0.55, green: 0.33, blue: 0.86), Color(red: 0.16, green: 0.50, blue: 0.92)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func render(_ view: some View, name: String, scale: CGFloat) throws {
        let content = view
            .environment(\.introAnimationsEnabled, false)
            .environment(\.liveEffectsEnabled, false)
            .environment(\.rendersGlass, false)
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        let image = try #require(renderer.cgImage)
        let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("\(name)\(tag).png"))
    }
}

/// A store with realistic accounts for the liquid renders.
@MainActor
enum LiquidStoreFixture {
    static func make(groups: Bool = false) throws -> TrackerStore {
        let now = UIFixture.now
        let work = try UIFixture.group("Работа")
        let personal = try UIFixture.group("Личное")
        let claude = try UIFixture.profile("Claude", provider: .claude, group: groups ? work : nil)
        let codex = try UIFixture.profile("Codex", provider: .codex, group: groups ? work : nil)
        let spare = try UIFixture.profile("Личный", provider: .claude, group: groups ? personal : nil)
        var settings = try AppSettings(accounts: groups ? [claude, codex, spare] : [claude, codex], groups: groups ? [work, personal] : [])
        settings.appearance.emailVisibility = .hidden
        let waiting = try AgentSession(
            id: "b", title: "exchanger-api", projectPath: "/Users/me/api", activity: .waiting,
            detail: "permission prompt", activitySince: now.addingTimeInterval(-65), processID: 2
        )
        let working = try AgentSession(
            id: "a", title: "Codometer", projectPath: "/Users/me/Codometer", activity: .working,
            detail: nil, activitySince: now.addingTimeInterval(-420), processID: 1, lastEventAt: now.addingTimeInterval(-20)
        )
        var accounts = [
            AccountStatus(
                profile: claude,
                identity: AccountIdentity(email: "me@example.com", organization: nil, plan: "Max 20x"),
                reading: try UIFixture.reading([try UIFixture.bucket("claude", [
                    try UIFixture.window("session", .session, used: 7, resetsIn: 4 * 3_600),
                    try UIFixture.window("week", .weekly(model: nil), used: 38, duration: .oneWeek, resetsIn: 4 * 86_400),
                ])], capturedAgo: 120),
                nextRefreshAt: now.addingTimeInterval(180),
                sessions: [working, waiting]
            ),
            AccountStatus(
                profile: codex,
                identity: AccountIdentity(email: "me@example.com", organization: nil, plan: "Pro"),
                reading: try UIFixture.reading([try UIFixture.bucket("codex", [
                    try UIFixture.window("primary", .rolling, used: 81, resetsIn: 2 * 3_600),
                ])], capturedAgo: 30),
                nextRefreshAt: now.addingTimeInterval(150)
            ),
        ]
        if groups {
            accounts.append(AccountStatus(
                profile: spare,
                reading: try UIFixture.reading([try UIFixture.bucket("claude", [
                    try UIFixture.window("session", .session, used: 46, resetsIn: 3 * 3_600),
                ])], capturedAgo: 60),
                nextRefreshAt: now.addingTimeInterval(200)
            ))
        }
        return TrackerStore(state: TrackerState(accounts: accounts), settings: settings, now: now, actions: UIFixture.actions())
    }
}
