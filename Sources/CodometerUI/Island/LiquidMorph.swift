import CodometerCore
import CoreGraphics
import SwiftUI

/// The island's outline at one moment of its liquid morph between the rail and the deck.
///
/// The outline is computed in a canonical frame where `u` runs along the screen edge and `v` points away from it,
/// then mapped onto the island's edge, so every edge and both styles share one construction:
/// - a **body** (the rail growing into the deck) fused to the screen edge through concave shoulders when attached,
///   or rounded on the screen side too when floating;
/// - a **droplet** hanging from the body's free side: a concave neck (surface tension), a round belly that bulges
///   slightly past its neck, and a cap. It swells out of the rail first, then widens and flattens while the body
///   catches up, until its cap is exactly the deck's free-side corners.
///
/// Folding runs the same curve backwards: the body contracts first, so the deck briefly becomes a droplet that is
/// absorbed into the rail. Progress slightly past the ends (a spring's overshoot) never moves the frames: it only
/// bows the free side outwards by at most `wobble` points, inside the panel's transparent margin.
///
/// The path is about twenty cubic segments with no allocation beyond `Path`, cheap enough for every frame.
public struct LiquidMorph: Equatable, Sendable {
    public var edge: ScreenEdge
    /// 1 attached (shoulders, bleeding past the screen edge), 0 floating (rounded on the screen side too).
    public var attachment: CGFloat
    /// Both states in the coordinates of the rect the outline is drawn in.
    public var rail: CGRect
    public var deck: CGRect
    /// Free-side corner radius of the rail (a large value makes a floating rail a capsule) and of the deck.
    public var railCorner: CGFloat
    public var deckCorner: CGFloat
    /// Width of the concave shoulders of an attached island.
    public var shoulder: CGFloat
    /// 0 is the rail, 1 the deck.
    public var progress: CGFloat
    /// 0 … 1: the rail's gentle swell while the pointer rests on it, the first stage of the droplet.
    public var swell: CGFloat
    /// The furthest the free side may bow outwards when the spring overshoots, in points.
    public var wobble: CGFloat
    /// `false` morphs as a plain rounded rectangle (Reduce Motion): no droplet, swell or wobble.
    public var isLiquid: Bool

    public init(
        edge: ScreenEdge,
        attachment: CGFloat,
        rail: CGRect,
        deck: CGRect,
        railCorner: CGFloat,
        deckCorner: CGFloat,
        shoulder: CGFloat,
        progress: CGFloat,
        swell: CGFloat = 0,
        wobble: CGFloat = 0,
        isLiquid: Bool = true
    ) {
        self.edge = edge
        self.attachment = attachment
        self.rail = rail
        self.deck = deck
        self.railCorner = railCorner
        self.deckCorner = deckCorner
        self.shoulder = shoulder
        self.progress = progress
        self.swell = swell
        self.wobble = wobble
        self.isLiquid = isLiquid
    }

    /// How far an attached outline reaches past the screen edge, so no rim is drawn along it.
    public static let bleed: CGFloat = 6
    /// Continuous corners: a corner of radius 1 starts this far along each side…
    static let cornerReach: CGFloat = 1.22
    /// …with its control points this share of the reach towards the corner.
    static let cornerHandle: CGFloat = 0.62
    /// Handle share of a cubic quarter circle.
    static let circleHandle: CGFloat = 0.5523
    /// How far past its ends progress turns into the full wobble.
    static let wobbleOvershoot: CGFloat = 0.04

    // MARK: - Outline

    /// A corner as the distance it reaches along both sides and the share of that reach its handles take.
    struct Corner: Equatable {
        var reach: CGFloat
        var handle: CGFloat

        /// A continuous corner of `radius`, clamped to `limit`; the tighter the clamp, the closer it gets to a
        /// circular quarter, so a clamped floating rail ends in true half circles.
        init(radius: CGFloat, limit: CGFloat) {
            let radius = max(0, radius)
            let limit = max(0, limit)
            let natural = radius * LiquidMorph.cornerReach
            guard natural > limit, radius > 0 else {
                self.init(reach: natural, handle: LiquidMorph.cornerHandle)
                return
            }
            let tightness = Self.unit((natural - limit) / (radius * (LiquidMorph.cornerReach - 1)))
            self.init(reach: limit, handle: LiquidMorph.cornerHandle + (LiquidMorph.circleHandle - LiquidMorph.cornerHandle) * tightness)
        }

        init(reach: CGFloat, handle: CGFloat) {
            self.reach = reach
            self.handle = handle
        }

        func mixed(with other: Corner, by t: CGFloat) -> Corner {
            Corner(reach: LiquidMorph.mix(reach, other.reach, t), handle: LiquidMorph.mix(handle, other.handle, t))
        }

        private static func unit(_ value: CGFloat) -> CGFloat {
            min(max(value, 0), 1)
        }
    }

    /// The outline's parameters at the current progress, in the canonical frame.
    struct Outline: Equatable {
        /// Body span along the edge, shoulders included.
        var start: CGFloat
        var end: CGFloat
        /// The body's screen-side and free-side lines.
        var near: CGFloat
        var far: CGFloat
        var attachment: CGFloat
        var shoulder: CGFloat
        var bleed: CGFloat
        var screenCorner: Corner
        var freeCorner: Corner
        /// Droplet centre along the edge.
        var center: CGFloat
        /// From the centre to where the neck meets the belly.
        var halfWidth: CGFloat
        /// The concave neck's extent along the free side and away from it.
        var neckWidth: CGFloat
        var neckDepth: CGFloat
        /// Direction the belly leaves its neck in, radians from `+u` towards `+v`: π/2 hangs straight down, more
        /// bulges outward, less makes a gentle swell.
        var neckAngle: CGFloat
        /// How far the belly's widest point reaches past its neck (a pear rather than a finger).
        var bulge: CGFloat
        /// The droplet's apex beyond `far`.
        var protrusion: CGFloat
        /// The cap corner's reach along the free side (measured from the neck) and away from it.
        var capWidth: CGFloat
        var capDepth: CGFloat
        var capHandle: CGFloat
        /// Extra outward bow at the centre of the free side (wobble).
        var bow: CGFloat
        /// The hover swell: how far the flat free side rises towards its middle, as a share (0 … 1.25) of `liftDepth`.
        var lift: CGFloat = 0
        /// The swell's full depth in points, before `build` limits it to a gentle slope over the flat stretch.
        var liftDepth: CGFloat = 0
    }

    /// Droplet parameters alone.
    private struct Droplet {
        var halfWidth: CGFloat = 0
        var neckWidth: CGFloat = 0
        var neckDepth: CGFloat = 0
        var neckAngle: CGFloat = .pi / 2
        var bulge: CGFloat = 0
        var protrusion: CGFloat = 0
        var capWidth: CGFloat = 0
        var capDepth: CGFloat = 0
        var capHandle: CGFloat = LiquidMorph.circleHandle
    }

    func outline() -> Outline {
        let frame = EdgeFrame(edge: edge, reference: rail)
        let r = frame.extent(of: rail)
        let d = frame.extent(of: deck)
        let m = Self.unit(attachment)
        let s = max(0, shoulder)
        let liquid = isLiquid
        // A spring moves fastest right at its start, which would flash the droplet past in a couple of frames. Easing
        // progress in holds the surface for a moment (surface tension), then lets the drop form and pour, both when
        // opening and, mirrored, when the deck is absorbed back into the rail.
        let c = liquid ? pow(Self.unit(progress), Tuning.progressEase) : Self.unit(progress)

        let railLength = max(0, r.end - r.start)
        let deckLength = max(0, d.end - d.start)
        let railDepth = max(0, r.far - r.near)
        let deckDepth = max(0, d.far - d.near)
        let railFree = Corner(radius: railCorner, limit: min((railLength - 2 * s * m) / 2, Self.mix(railDepth / 2, railDepth - s, m)))
        let deckFree = Corner(radius: deckCorner, limit: min((deckLength - 2 * s * m) / 2, Self.mix(deckDepth / 2, deckDepth - s, m)))
        let railScreen = Corner(radius: railCorner, limit: min(railLength / 2, railDepth / 2))
        let deckScreen = Corner(radius: deckCorner, limit: min(deckLength / 2, deckDepth / 2))

        // The droplet leads and the body follows: its walls widen once the droplet needs the room, and its free
        // side deepens last, so for most of the morph the depth is the droplet's.
        let span = liquid ? Self.smoothstep(Tuning.spanStart, Tuning.spanEnd, c) : c
        let deepen = liquid ? Self.smoothstep(Tuning.deepenStart, 1, c) : c

        var outline = Outline(
            start: Self.mix(r.start, d.start, span),
            end: Self.mix(r.end, d.end, span),
            near: Self.mix(r.near, d.near, span),
            far: Self.mix(r.far, d.far, deepen),
            attachment: m,
            shoulder: s,
            bleed: Self.bleed * m,
            screenCorner: railScreen.mixed(with: deckScreen, by: span),
            freeCorner: railFree.mixed(with: deckFree, by: span),
            center: Self.mix((r.start + r.end) / 2, (d.start + d.end) / 2, span),
            halfWidth: 0,
            neckWidth: 0,
            neckDepth: 0,
            neckAngle: .pi / 2,
            bulge: 0,
            protrusion: 0,
            capWidth: 0,
            capDepth: 0,
            capHandle: Self.circleHandle,
            bow: 0
        )
        guard liquid else { return outline }

        // At the end the droplet's cap is the deck's free-side corners, so the body stops short of them.
        outline.far = Self.mix(r.far, d.far - deckFree.reach, deepen)
        let wallHalf = max(0, (outline.end - outline.start) / 2 - s * m)
        let growth = max(0, d.far - r.far)
        let settle = Self.smoothstep(Tuning.settleStart, 1, c)
        let form = Self.smoothstep(0, Tuning.formEnd, c)

        // The droplet: first a round drop about as wide as the rail's free side, then it pours towards the deck's
        // depth and widens to its walls, and finally its round cap tightens into the deck's corners.
        let railFlatHalf = max(0, railLength - 2 * s * m - 2 * railFree.reach) / 2
        let radius = min(railFlatHalf * Tuning.dropWidth, growth * Tuning.dropDepthShare) * form
        let apex = max(
            outline.far,
            Self.mix(r.far, d.far, Self.smoothstep(0, Tuning.pourEnd, c)),
            r.far + radius * Tuning.dropElongation
        )
        let fade = 1 - Self.smoothstep(Tuning.closeStart, Tuning.closeEnd, c)
        var drop = Droplet()
        let closing = Self.smoothstep(Tuning.closeStart, Tuning.closeEnd, c)
        drop.halfWidth = min(wallHalf, max(radius, wallHalf * Self.mix(Tuning.bodyGap * Self.smoothstep(0, Tuning.widenEnd, c), 1, closing)))
        // Surface tension: until the droplet has widened, it hangs no longer than its width allows, so a narrow rail
        // grows a round drop instead of a stalk.
        let roundLimit = max(radius * Tuning.dropElongation, drop.halfWidth * Tuning.maximumElongation)
        let released = Self.smoothstep(Tuning.releaseStart, Tuning.releaseEnd, c)
        let poured = apex - outline.far
        drop.protrusion = Self.mix(min(poured, roundLimit), poured, released)
        drop.neckWidth = max(radius, drop.halfWidth * 0.4) * Tuning.neckShare * fade
        drop.neckDepth = min(drop.neckWidth * 0.8, drop.protrusion * 0.4)
        drop.neckAngle = .pi / 2 + Tuning.bulbAngle * fade
        drop.bulge = drop.halfWidth * Tuning.bulgeShare * fade * form
        drop.capWidth = Self.mix(drop.halfWidth, deckFree.reach, settle)
        let roundCap = min(drop.capWidth + drop.bulge, max(0, drop.protrusion - drop.neckDepth))
        drop.capDepth = min(Self.mix(roundCap, deckFree.reach, settle), max(0, drop.protrusion - drop.neckDepth))
        drop.capHandle = Self.mix(Self.circleHandle, deckFree.handle, settle)

        // The hover swell (and a small recoil when a fold overshoots): the flat free side between the corners rises in
        // one smooth, low arch, which fades out as the droplet forms. A springy swell may overshoot a little: past 1
        // the arch only grows deeper, up to a quarter more. The arch's height and its slope are set in `build`.
        let recoil = progress < 0 ? Self.unit(-progress / Self.wobbleOvershoot) * 0.8 : 0
        outline.lift = min(1.25, max(0, swell) * (1 - Self.smoothstep(0, 0.25, c)) + recoil)
        outline.liftDepth = min(max(railDepth * Tuning.swellDepthShare, 2), Tuning.swellDepthLimit)

        outline.halfWidth = min(drop.halfWidth, wallHalf)
        let wallStart = outline.start + s * m
        let wallEnd = outline.end - s * m
        outline.center = min(max(outline.center, wallStart + outline.halfWidth), wallEnd - outline.halfWidth)
        outline.neckWidth = drop.neckWidth
        outline.neckDepth = drop.neckDepth
        // A pear needs room: as the belly nears the walls it hangs straight and never bulges past them.
        let gap = max(0, wallHalf - outline.halfWidth)
        // Only a drop smaller than the rail's free side is pear-shaped; a wide one hangs straight from the walls.
        let small = 1 - Self.smoothstep(0.8, 1.6, outline.halfWidth / max(railFlatHalf, 1))
        let roomy = Self.unit(gap / max(1, outline.freeCorner.reach + drop.neckWidth)) * small
        outline.neckAngle = .pi / 2 + (drop.neckAngle - .pi / 2) * (drop.neckAngle > .pi / 2 ? roomy : 1)
        outline.bulge = min(drop.bulge * roomy, gap * 0.5)
        outline.protrusion = drop.protrusion
        outline.capWidth = min(drop.capWidth, outline.halfWidth)
        outline.capDepth = drop.capDepth
        outline.capHandle = drop.capHandle
        if progress > 1 {
            outline.bow = Self.unit((progress - 1) / Self.wobbleOvershoot) * max(0, wobble)
        }
        return outline
    }

    /// The shape of the morph over progress, in one place for tuning.
    enum Tuning {
        /// Exponent easing progress into the morph (see `outline()`).
        static let progressEase: CGFloat = 1.7
        /// The body's walls widen over this progress range.
        static let spanStart: CGFloat = 0.12
        static let spanEnd: CGFloat = 0.75
        /// The body's free side starts deepening here and reaches the deck at the end; by then the droplet fills the
        /// walls, so the body's free side is hidden inside it.
        static let deepenStart: CGFloat = 0.6
        /// The droplet's round cap tightens into the deck's corners from here.
        static let settleStart: CGFloat = 0.5
        /// The droplet closes the gap to the walls (and its necks fade) over this range.
        static let closeStart: CGFloat = 0.3
        static let closeEnd: CGFloat = 0.72
        /// The first drop is fully formed here.
        static let formEnd: CGFloat = 0.3
        /// The apex reaches the deck's free side here.
        static let pourEnd: CGFloat = 0.9
        /// The droplet reaches its widest (short of the walls) here.
        static let widenEnd: CGFloat = 0.5
        /// The first drop's half-width as a share of half the rail's free side, and at most this share of the growth.
        static let dropWidth: CGFloat = 0.8
        static let dropDepthShare: CGFloat = 0.3
        /// A drop hangs a little longer than it is wide…
        static let dropElongation: CGFloat = 1.3
        /// …and, until it is released over this progress range, never longer than this many half-widths.
        static let maximumElongation: CGFloat = 1.7
        static let releaseStart: CGFloat = 0.45
        static let releaseEnd: CGFloat = 0.8
        /// Until it settles, the droplet stays this share of the walls' half-width, leaving room for its necks.
        static let bodyGap: CGFloat = 0.88
        /// Neck width as a share of the droplet's half-width.
        static let neckShare: CGFloat = 0.45
        /// Extra angle the belly leaves its neck at, and how far its widest point bulges past the neck.
        static let bulbAngle: CGFloat = 0.12
        static let bulgeShare: CGFloat = 0.1
        /// The hover swell's depth as a share of the rail's depth, and its limit in points.
        static let swellDepthShare: CGFloat = 0.09
        static let swellDepthLimit: CGFloat = 4.5
        /// The steepest the swell's arch may be on average: its height over the flat stretch from a corner to the
        /// middle. A short flat stretch arches less, and a rail that is all corners (round, or empty) not at all.
        static let swellSlope: CGFloat = 0.08
    }

    // MARK: - Paths

    /// The closed outline, drawn inside `bounds` (the rects are offset by its origin).
    public func path(in bounds: CGRect) -> Path {
        build(in: bounds, closed: true)
    }

    /// The outline without the side along the screen edge (attached), for rim light; floating islands get it all.
    public func outlinePath(in bounds: CGRect) -> Path {
        build(in: bounds, closed: attachment < 0.5)
    }

    /// The rect the island covers right now (bleed and wobble excluded), in the drawing rect's coordinates.
    public func envelope(in bounds: CGRect = .zero) -> CGRect {
        let outline = outline()
        let frame = EdgeFrame(edge: edge, reference: rail)
        let a = frame.point(outline.start, outline.near)
        let b = frame.point(outline.end, outline.far + outline.protrusion + outline.lift * outline.liftDepth)
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
            .offsetBy(dx: bounds.minX, dy: bounds.minY)
    }

    private func build(in bounds: CGRect, closed: Bool) -> Path {
        guard rail.width > 0, rail.height > 0 else { return Path() }
        let o = outline()
        let frame = EdgeFrame(edge: edge, reference: rail, offset: CGPoint(x: bounds.minX, y: bounds.minY))
        var pen = Pen(frame: frame)
        let m = o.attachment
        let s = o.shoulder

        // Screen side, left: the attached shoulder and the floating corner, mixed by attachment.
        let screen = o.screenCorner
        let startPoint = CanonicalPoint(Self.mix(o.start + screen.reach, o.start, m), o.near)
        let shoulderControl1 = CanonicalPoint(
            Self.mix(o.start + screen.reach - screen.reach * screen.handle, o.start + s * 0.62, m),
            o.near
        )
        let shoulderControl2 = CanonicalPoint(
            Self.mix(o.start, o.start + s, m),
            Self.mix(o.near + screen.reach - screen.reach * screen.handle, o.near + s * 0.62, m)
        )
        let wallTop = CanonicalPoint(Self.mix(o.start, o.start + s, m), Self.mix(o.near + screen.reach, o.near + s, m))

        if closed {
            pen.move(CanonicalPoint(startPoint.u, o.near - o.bleed))
            pen.line(startPoint)
        } else {
            pen.move(startPoint)
        }
        pen.curve(wallTop, shoulderControl1, shoulderControl2)

        // The free side, from the left wall to the right one.
        let wallLeft = wallTop.u
        let wallRight = o.end - (wallTop.u - o.start)
        let maximumReach = max(0, min(o.far - wallTop.v, (wallRight - wallLeft) / 2))
        let freeReach = min(o.freeCorner.reach, maximumReach)
        let neckLeft = o.center - o.halfWidth
        let neckRight = o.center + o.halfWidth
        // The swell arches the flat stretches between the corners and the droplet's necks; the droplet hangs from it.
        let flatLeft = neckLeft - o.neckWidth - (wallLeft + freeReach)
        let flatRight = wallRight - freeReach - (neckRight + o.neckWidth)
        let lift = o.lift * min(o.liftDepth, max(0, min(flatLeft, flatRight)) * Tuning.swellSlope)
        let left = shoulderToNeck(wall: wallLeft, neck: neckLeft, reach: freeReach, lift: lift, outline: o, mirrored: false)
        let right = shoulderToNeck(wall: wallRight, neck: neckRight, reach: freeReach, lift: lift, outline: o, mirrored: true)

        // Left wall, body corner, flat free side and concave neck (or, when the belly nearly fills the walls, one
        // smooth taper from the wall into the belly).
        pen.line(left.wallEnd)
        left.draw(into: &pen, reversed: false)
        let leftNeck = left.neck
        // Left belly: leaves the neck along its direction, bulges to its widest point, then turns along the edge in
        // its cap.
        let leftSide = belly(neck: leftNeck, lift: lift, outline: o, mirrored: false)
        leftSide.draw(into: &pen, reversed: false)

        // The flat (or, while wobbling, bowed) middle of the free side.
        let rightNeck = right.neck
        let rightSide = belly(neck: rightNeck, lift: lift, outline: o, mirrored: true)
        let apex = o.far + lift + o.protrusion
        if o.bow > 0.01 {
            let middle = CanonicalPoint(o.center, apex + o.bow)
            let leftRun = (middle.u - leftSide.cap.u) * 0.55
            let rightRun = (rightSide.cap.u - middle.u) * 0.55
            pen.curve(middle, CanonicalPoint(leftSide.cap.u + leftRun, apex), CanonicalPoint(middle.u - leftRun, middle.v))
            pen.curve(rightSide.cap, CanonicalPoint(middle.u + rightRun, middle.v), CanonicalPoint(rightSide.cap.u - rightRun, apex))
        } else {
            pen.line(rightSide.cap)
        }

        // Right belly, neck, body corner and wall: the left side mirrored.
        rightSide.draw(into: &pen, reversed: true)
        right.draw(into: &pen, reversed: true)
        pen.line(CanonicalPoint(wallRight, wallTop.v))

        // Screen side, right.
        let endPoint = CanonicalPoint(o.end - (startPoint.u - o.start), o.near)
        pen.curve(
            endPoint,
            CanonicalPoint(o.end - (shoulderControl2.u - o.start), shoulderControl2.v),
            CanonicalPoint(o.end - (shoulderControl1.u - o.start), shoulderControl1.v)
        )
        if closed {
            pen.line(CanonicalPoint(endPoint.u, o.near - o.bleed))
            pen.close()
        }
        return pen.path
    }

    /// A belly from its neck to its cap: a side that leaves the neck along the neck's direction and reaches its
    /// widest point, then a cap corner that turns to run along the edge at the apex.
    private struct Belly {
        var neck: CanonicalPoint
        var sideControl1: CanonicalPoint
        var sideControl2: CanonicalPoint
        var widest: CanonicalPoint
        var capControl1: CanonicalPoint
        var capControl2: CanonicalPoint
        var cap: CanonicalPoint

        func draw(into pen: inout Pen, reversed: Bool) {
            if reversed {
                pen.curve(widest, capControl2, capControl1)
                pen.curve(neck, sideControl2, sideControl1)
            } else {
                pen.curve(widest, sideControl1, sideControl2)
                pen.curve(cap, capControl1, capControl2)
            }
        }
    }

    private func belly(neck: CanonicalPoint, lift: CGFloat, outline o: Outline, mirrored: Bool) -> Belly {
        let sign: CGFloat = mirrored ? -1 : 1
        let apex = o.far + lift + o.protrusion
        let direction = (u: cos(o.neckAngle) * sign, v: sin(o.neckAngle))
        let widest = CanonicalPoint(neck.u - o.bulge * sign, max(neck.v, apex - o.capDepth))
        let length = widest.v - neck.v
        // Along a real side the belly arrives vertically; without one (a low swell) it keeps the neck's direction.
        let straighten = Self.unit(length / 4)
        let tangent = (u: direction.u * (1 - straighten), v: direction.v * (1 - straighten) + straighten)
        let norm = max(hypot(tangent.u, tangent.v), 0.001)
        let unit = (u: tangent.u / norm, v: tangent.v / norm)
        let capReach = o.capWidth + o.bulge
        let cap = CanonicalPoint(widest.u + capReach * sign, apex)
        let capLead = o.capDepth * o.capHandle / max(unit.v, 0.35)
        return Belly(
            neck: neck,
            sideControl1: CanonicalPoint(neck.u + direction.u * length * 0.5, neck.v + direction.v * length * 0.5),
            sideControl2: CanonicalPoint(widest.u, widest.v - length * 0.45),
            widest: widest,
            capControl1: CanonicalPoint(widest.u + unit.u * capLead, widest.v + unit.v * capLead),
            capControl2: CanonicalPoint(cap.u - capReach * o.capHandle * sign, apex),
            cap: cap
        )
    }

    /// The free side between a wall and the belly's neck: a convex body corner, a flat stretch and a concave neck.
    /// The corner and the neck share the room between the wall and the neck, shrinking together as the belly widens;
    /// once that room is small they blend into one S-shaped taper, which becomes a straight wall when the belly
    /// reaches it, so the shrinking corner and neck never read as a notch.
    private struct Transition {
        var wallEnd: CanonicalPoint
        var cornerControl1: CanonicalPoint
        var cornerControl2: CanonicalPoint
        var cornerEnd: CanonicalPoint
        var foot: CanonicalPoint
        var neckControl1: CanonicalPoint
        var neckControl2: CanonicalPoint
        var neck: CanonicalPoint

        func draw(into pen: inout Pen, reversed: Bool) {
            if reversed {
                pen.curve(foot, neckControl2, neckControl1)
                flat(into: &pen, from: foot, to: cornerEnd)
                pen.curve(wallEnd, cornerControl2, cornerControl1)
            } else {
                pen.curve(cornerEnd, cornerControl1, cornerControl2)
                flat(into: &pen, from: cornerEnd, to: foot)
                pen.curve(neck, neckControl1, neckControl2)
            }
        }

        /// The stretch between the corner and the neck: straight, or rising by the swell as a smoothstep over its whole
        /// length (level at both ends, so it joins the corner and the neck without a kink). The handles sit at a third
        /// of the run from each end, so the curve advances evenly along the edge and the rise spreads over the whole
        /// stretch; mirrored on the other side it makes one low, raised-cosine arch across the free side. (Handles at
        /// the middle would bunch the rise into a short step halfway along, which reads as a lump.)
        private func flat(into pen: inout Pen, from start: CanonicalPoint, to end: CanonicalPoint) {
            guard abs(end.v - start.v) > 0.01 else {
                pen.line(end)
                return
            }
            let third = (end.u - start.u) / 3
            pen.curve(end, CanonicalPoint(start.u + third, start.v), CanonicalPoint(end.u - third, end.v))
        }
    }

    private func shoulderToNeck(wall: CGFloat, neck neckU: CGFloat, reach: CGFloat, lift: CGFloat, outline o: Outline, mirrored: Bool) -> Transition {
        let sign: CGFloat = mirrored ? -1 : 1
        let available = max(0, (neckU - wall) * sign)
        let need = reach + o.neckWidth
        let share = need > 0 ? min(1, available / need) : 1
        // Classic: corner, flat, neck, scaled into the room.
        let cornerReach = reach * share
        let neckWidth = o.neckWidth * share
        let neckDepth = o.neckDepth * share.squareRoot()
        let direction = (u: cos(o.neckAngle) * sign, v: sin(o.neckAngle))
        let steepness = max(sin(o.neckAngle), 0.35)
        let handle = o.freeCorner.handle
        // Where the swell raises the flat stretch, the neck and the droplet below it move out by the same amount.
        let plainNeck = CanonicalPoint(neckU, o.far + lift + neckDepth)

        // Taper: one S from the wall (where a full corner would start) into the neck, several times taller than the
        // gap it closes, so it reads as a gentle waist rather than a step.
        let taperStart = CanonicalPoint(wall, o.far - reach)
        let taperNeck = CanonicalPoint(neckU, o.far + lift + max(neckDepth, min(available * 3.5 - reach, o.protrusion * 0.6)))
        let height = max(taperNeck.v - taperStart.v, 0.001)
        let middle = CanonicalPoint((wall + neckU) / 2, (taperStart.v + taperNeck.v) / 2)
        let slope = (u: (neckU - wall) / height, v: CGFloat(1))
        let slopeNorm = max(hypot(slope.u, slope.v), 0.001)
        let slant = (u: slope.u / slopeNorm, v: slope.v / slopeNorm)
        let taperLead = height * 0.28

        let classic = Self.smoothstep(0.12, 0.65, share)
        func blend(_ taper: CanonicalPoint, _ plain: CanonicalPoint) -> CanonicalPoint {
            CanonicalPoint(Self.mix(taper.u, plain.u, classic), Self.mix(taper.v, plain.v, classic))
        }
        let neck = blend(taperNeck, plainNeck)
        let wallEnd = blend(taperStart, CanonicalPoint(wall, o.far - cornerReach))
        let cornerEnd = blend(middle, CanonicalPoint(wall + cornerReach * sign, o.far))
        let foot = blend(middle, CanonicalPoint(neckU - neckWidth * sign, o.far + lift))
        // Where a flat stretch joins the corner and the neck, both must leave along it.
        let flat = Self.unit(abs(foot.u - cornerEnd.u) / 2)
        let blended = (u: Self.mix(slant.u, sign, classic), v: Self.mix(slant.v, 0, classic))
        let tangent = (u: Self.mix(blended.u, sign, flat), v: Self.mix(blended.v, 0, flat))
        let tangentNorm = max(hypot(tangent.u, tangent.v), 0.001)
        let unit = (u: tangent.u / tangentNorm, v: tangent.v / tangentNorm)
        let cornerLead = Self.mix(taperLead, cornerReach * handle, classic)
        let footLead = Self.mix(taperLead, neckWidth * Self.circleHandle, classic)
        let neckLead = Self.mix(taperLead, neckDepth * Self.circleHandle / steepness, classic)
        return Transition(
            wallEnd: wallEnd,
            cornerControl1: CanonicalPoint(wall, wallEnd.v + Self.mix(taperLead, cornerReach * handle, classic)),
            cornerControl2: CanonicalPoint(cornerEnd.u - unit.u * cornerLead, cornerEnd.v - unit.v * cornerLead),
            cornerEnd: cornerEnd,
            foot: foot,
            neckControl1: CanonicalPoint(foot.u + unit.u * footLead, foot.v + unit.v * footLead),
            neckControl2: CanonicalPoint(neck.u - direction.u * neckLead, neck.v - direction.v * neckLead),
            neck: neck
        )
    }

    // MARK: - Math

    static func mix(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }

    static func unit(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }

    /// Hermite smoothstep: 0 below `edge0`, 1 above `edge1`, with zero slope at both ends.
    static func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
        guard edge1 > edge0 else { return x < edge0 ? 0 : 1 }
        let t = unit((x - edge0) / (edge1 - edge0))
        return t * t * (3 - 2 * t)
    }
}

/// A point in the canonical frame: `u` along the screen edge, `v` away from it.
struct CanonicalPoint: Equatable {
    var u: CGFloat
    var v: CGFloat

    init(_ u: CGFloat, _ v: CGFloat) {
        self.u = u
        self.v = v
    }
}

/// Maps the canonical frame onto an edge.
struct EdgeFrame {
    struct Extent: Equatable {
        var start: CGFloat
        var end: CGFloat
        var near: CGFloat
        var far: CGFloat
    }

    let edge: ScreenEdge
    /// The screen-side line of the reference rect.
    let line: CGFloat
    let offset: CGPoint

    init(edge: ScreenEdge, reference: CGRect, offset: CGPoint = .zero) {
        self.edge = edge
        self.offset = offset
        line = switch edge {
        case .top: reference.minY
        case .bottom: reference.maxY
        case .left: reference.minX
        case .right: reference.maxX
        }
    }

    func point(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
        let point = switch edge {
        case .top: CGPoint(x: u, y: line + v)
        case .bottom: CGPoint(x: u, y: line - v)
        case .left: CGPoint(x: line + v, y: u)
        case .right: CGPoint(x: line - v, y: u)
        }
        return CGPoint(x: point.x + offset.x, y: point.y + offset.y)
    }

    func extent(of rect: CGRect) -> Extent {
        switch edge {
        case .top: Extent(start: rect.minX, end: rect.maxX, near: rect.minY - line, far: rect.maxY - line)
        case .bottom: Extent(start: rect.minX, end: rect.maxX, near: line - rect.maxY, far: line - rect.minY)
        case .left: Extent(start: rect.minY, end: rect.maxY, near: rect.minX - line, far: rect.maxX - line)
        case .right: Extent(start: rect.minY, end: rect.maxY, near: line - rect.maxX, far: line - rect.minX)
        }
    }
}

/// Builds a path from canonical points, skipping segments too short to draw.
private struct Pen {
    let frame: EdgeFrame
    private(set) var path = Path()
    private var current: CanonicalPoint?

    init(frame: EdgeFrame) {
        self.frame = frame
    }

    mutating func move(_ point: CanonicalPoint) {
        path.move(to: frame.point(point.u, point.v))
        current = point
    }

    mutating func line(_ point: CanonicalPoint) {
        guard let current, !Self.isClose(current, point) else { return }
        path.addLine(to: frame.point(point.u, point.v))
        self.current = point
    }

    mutating func curve(_ point: CanonicalPoint, _ control1: CanonicalPoint, _ control2: CanonicalPoint) {
        guard let current else { return }
        if Self.isClose(current, point), Self.isClose(current, control1), Self.isClose(current, control2) { return }
        path.addCurve(
            to: frame.point(point.u, point.v),
            control1: frame.point(control1.u, control1.v),
            control2: frame.point(control2.u, control2.v)
        )
        self.current = point
    }

    mutating func close() {
        path.closeSubpath()
    }

    private static func isClose(_ a: CanonicalPoint, _ b: CanonicalPoint) -> Bool {
        abs(a.u - b.u) < 0.01 && abs(a.v - b.v) < 0.01
    }
}
