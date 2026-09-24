// RenderIconLayers.swift — draws the four layer images of Packaging/AppIcon.icon.
//
// Usage: swift Scripts/icon/RenderIconLayers.swift <out-dir> [--warm-tail]
//
// The icon tells the product's own story — "island, droplet, gauge":
//   • the attached island silhouette hangs from the top edge of the icon body,
//   • a droplet falls out of it, its neck passing through the gap at 12 o'clock,
//   • its belly rests at the centre of a usage gauge, the gauge's hub.
//
// The layers are written as four premultiplied Display P3 PNGs, 1024 × 1024, which
// Packaging/AppIcon.icon/icon.json composes into the Liquid Glass groups. The background is a
// fill in icon.json rather than an image, so the system can re-tint it.
//
// Geometry mirrors the app's own shapes; every ratio below names the type it comes from
// (CodometerUI: IslandMetrics, LiquidMorph, Palette). Rendering is deterministic: fixed
// constants, no dates, no randomness, no system colours — running it twice produces identical files.
//
// This is a standalone script, not a package target, so the package stays clean. It is run by
// Scripts/build-icon.sh; the rendered layers are committed so an ordinary build never renders them.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Output

/// Everything the script prints goes to stderr, so a caller can capture the file list on stdout.
func note(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func fail(_ message: String) -> Never {
    note("RenderIconLayers: error: \(message)")
    exit(1)
}

// MARK: - Canvas

/// Icon Composer composes macOS icons on a square canvas whose full extent is the icon body; the
/// system applies the squircle mask, so a shape may bleed to the edge.
let side = 1024
let S = CGFloat(side)

guard let p3 = CGColorSpace(name: CGColorSpace.displayP3) else {
    fail("Display P3 colour space unavailable")
}

/// A colour in Display P3, the space every value in this script is authored in.
func rgba(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat) -> CGColor {
    guard let color = CGColor(colorSpace: p3, components: [red, green, blue, alpha]) else {
        fail("could not make a Display P3 colour")
    }
    return color
}

func white(_ alpha: CGFloat) -> CGColor { rgba(1, 1, 1, alpha) }

/// A fresh transparent canvas whose coordinates run top-down, like the design notes and like
/// SwiftUI: (0, 0) is the top-left corner of the icon body, (1024, 1024) the bottom-right one.
func makeCanvas() -> CGContext {
    guard let context = CGContext(
        data: nil,
        width: side,
        height: side,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: p3,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fail("could not create a \(side)×\(side) Display P3 bitmap")
    }
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high
    context.translateBy(x: 0, y: S)
    context.scaleBy(x: 1, y: -1)
    return context
}

func writePNG(_ context: CGContext, to url: URL) {
    guard let image = context.makeImage() else { fail("could not snapshot \(url.lastPathComponent)") }
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else {
        fail("could not create \(url.path)")
    }
    // No date, no software tag: two runs must produce byte-identical files.
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("could not write \(url.path)") }
}

// MARK: - Geometry helpers

typealias P = CGPoint

func point(_ x: CGFloat, _ y: CGFloat) -> P { P(x: x, y: y) }

/// Continuous ("squircle") corners, the shape language of the island: a corner of radius `r`
/// starts `r × reach` along each side, with control points `handle` of that reach towards the
/// corner. The two constants are `LiquidMorph.cornerReach` / `cornerHandle`.
enum Corner {
    static let reach: CGFloat = 1.22
    static let handle: CGFloat = 0.62
}

/// Handle length of a cubic quarter circle (`LiquidMorph.circleHandle`).
let circleHandle: CGFloat = 0.5523

/// A turn expressed in radians, measured clockwise from 12 o'clock — the grammar every ring in the
/// app uses, so "0.72 of a turn" in the design notes is 0.72 here.
func angle(turns: CGFloat) -> CGFloat { -.pi / 2 + turns * 2 * .pi }

func onCircle(_ centre: P, _ radius: CGFloat, turns: CGFloat) -> P {
    let a = angle(turns: turns)
    return point(centre.x + cos(a) * radius, centre.y + sin(a) * radius)
}

/// Linear interpolation between two Display P3 triples.
func mixed(_ from: (CGFloat, CGFloat, CGFloat), _ to: (CGFloat, CGFloat, CGFloat), _ t: CGFloat) -> CGColor {
    let u = min(max(t, 0), 1)
    return rgba(from.0 + (to.0 - from.0) * u, from.1 + (to.1 - from.1) * u, from.2 + (to.2 - from.2) * u, 1)
}

// MARK: - Design constants

/// The island, in `IslandMetrics` proportions: shoulder 12 : free-side corner 16 : rail height 40.
/// The tab is as wide a share of the icon body as the rail is of a screen it hangs from.
enum Island {
    /// Width where the tab meets the top edge, and its depth, as shares of the canvas.
    static let width: CGFloat = 0.52
    static let depth: CGFloat = 0.15
    /// One `IslandMetrics` design point on this canvas.
    static let unit: CGFloat = depth / 40
    /// `IslandMetrics.shoulder` (12) and `.railCorner` (16).
    static let shoulder: CGFloat = 12 * unit
    static let corner: CGFloat = 16 * unit
    /// How far the tab is drawn past the top edge, so the mask never leaves a seam.
    static let bleed: CGFloat = 0.02
    /// Opacity of the glass sheet: below the droplet's, so the drop stays the brightest thing in
    /// the tinted and clear renditions, and translucent enough for the graphite to show through.
    static let opacity: CGFloat = 0.86
}

/// The usage gauge: the same ring grammar as `RingGauge`, centred a little below the middle so the
/// island and the drop have room above it.
enum Gauge {
    static let centre = point(0.5, 0.543)
    /// Centre line of the band and its stroke width, as shares of the canvas.
    static let radius: CGFloat = 0.2715
    static let stroke: CGFloat = 0.073
    /// The unused track: a dim full circle, cut by seven odometer ticks — one per day of a week
    /// ring. The tick at 12 o'clock is the gap the droplet's neck falls through.
    static let trackOpacity: CGFloat = 0.22
    static let tickCount = 7
    static let tickWidth: CGFloat = 0.0105
    /// The used arc. It starts just right of 12 o'clock, leaving the gap at the top.
    static let arcStart: CGFloat = 0.035
    static let arcEnd: CGFloat = 0.72
    /// The transparent "now" notch inside the arc.
    static let nowAt: CGFloat = 0.55
    static let nowWidth: CGFloat = 0.0075
    /// `Palette.bandGradient(.ample)`: the calm band, start to end along the arc.
    static let ampleStart: (CGFloat, CGFloat, CGFloat) = (0.30, 0.86, 0.62)
    static let ampleEnd: (CGFloat, CGFloat, CGFloat) = (0.05, 0.68, 0.46)
    /// `Palette.bandGradient(.watch).start`, used only by `--warm-tail`.
    static let watchStart: (CGFloat, CGFloat, CGFloat) = (1.00, 0.82, 0.26)
    /// Share of the arc the warm tail covers.
    static let warmTail: CGFloat = 0.28
}

/// The droplet, built like `LiquidMorph`'s: a concave neck (surface tension), a waist where it
/// passes through the ring, and a round belly that becomes the gauge's hub.
enum Drop {
    /// Half width where it leaves the island, and the concave fillet into the island's underside.
    static let topHalfWidth: CGFloat = 0.052
    static let fillet: CGFloat = 0.034
    /// The waist sits in the ring's band, so the neck is thinnest exactly where it crosses.
    static let waistY: CGFloat = 0.268
    static let waistHalfWidth: CGFloat = 0.0225
    /// The belly: centred on the gauge, wide enough to read as a hub at 16 pt.
    static let bellyRadius: CGFloat = 0.115
    /// How far the drop is drawn up into the island, so the two glass groups never leave a hairline.
    static let overlap: CGFloat = 0.008
}

// MARK: - Paths

/// The attached island: concave shoulders where it meets the top edge, continuous corners on its
/// free side. Mirrors the attached branch of `LiquidMorph.build(in:closed:)`.
func islandPath() -> CGPath {
    let path = CGMutablePath()
    let w = Island.width * S
    let depth = Island.depth * S
    let shoulder = Island.shoulder * S
    let corner = Island.corner * S
    let bleed = Island.bleed * S
    let left = (S - w) / 2
    let right = left + w
    let wallLeft = left + shoulder
    let wallRight = right - shoulder
    let reach = min(corner * Corner.reach, (wallRight - wallLeft) / 2, depth - shoulder)
    let pull = reach * (1 - Corner.handle)

    path.move(to: point(left, -bleed))
    path.addLine(to: point(left, 0))
    // Concave shoulder: out of the top edge and into the wall.
    path.addCurve(
        to: point(wallLeft, shoulder),
        control1: point(left + shoulder * Corner.handle, 0),
        control2: point(wallLeft, shoulder * Corner.handle)
    )
    path.addLine(to: point(wallLeft, depth - reach))
    path.addCurve(
        to: point(wallLeft + reach, depth),
        control1: point(wallLeft, depth - pull),
        control2: point(wallLeft + pull, depth)
    )
    path.addLine(to: point(wallRight - reach, depth))
    path.addCurve(
        to: point(wallRight, depth - reach),
        control1: point(wallRight - pull, depth),
        control2: point(wallRight, depth - pull)
    )
    path.addLine(to: point(wallRight, shoulder))
    path.addCurve(
        to: point(right, 0),
        control1: point(wallRight, shoulder * Corner.handle),
        control2: point(right - shoulder * Corner.handle, 0)
    )
    path.addLine(to: point(right, -bleed))
    path.closeSubpath()
    return path
}

/// The droplet hanging from the island's underside.
func dropPath() -> CGPath {
    let path = CGMutablePath()
    let cx = S / 2
    let top = Island.depth * S
    let topHalf = Drop.topHalfWidth * S
    let fillet = Drop.fillet * S
    let waistY = Drop.waistY * S
    let waistHalf = Drop.waistHalfWidth * S
    let belly = Drop.bellyRadius * S
    let bellyY = Gauge.centre.y * S
    let overlap = Drop.overlap * S
    let neckRun = waistY - (top + fillet)
    let bellyRun = bellyY - waistY
    let k = belly * circleHandle

    path.move(to: point(cx - topHalf - fillet, top - overlap))
    path.addLine(to: point(cx - topHalf - fillet, top))
    // Concave neck: the same fillet construction as the island's shoulder, mirrored downwards.
    path.addCurve(
        to: point(cx - topHalf, top + fillet),
        control1: point(cx - topHalf - fillet * (1 - Corner.handle), top),
        control2: point(cx - topHalf, top + fillet * (1 - Corner.handle))
    )
    // Taper to the waist, then bulge into the belly: both tangents vertical, so the silhouette
    // never kinks.
    path.addCurve(
        to: point(cx - waistHalf, waistY),
        control1: point(cx - topHalf, top + fillet + neckRun * 0.5),
        control2: point(cx - waistHalf, waistY - neckRun * 0.42)
    )
    path.addCurve(
        to: point(cx - belly, bellyY),
        control1: point(cx - waistHalf, waistY + bellyRun * 0.45),
        control2: point(cx - belly, bellyY - bellyRun * 0.55)
    )
    // Round bottom.
    path.addCurve(
        to: point(cx, bellyY + belly),
        control1: point(cx - belly, bellyY + k),
        control2: point(cx - k, bellyY + belly)
    )
    path.addCurve(
        to: point(cx + belly, bellyY),
        control1: point(cx + k, bellyY + belly),
        control2: point(cx + belly, bellyY + k)
    )
    // Mirror of the way down.
    path.addCurve(
        to: point(cx + waistHalf, waistY),
        control1: point(cx + belly, bellyY - bellyRun * 0.55),
        control2: point(cx + waistHalf, waistY + bellyRun * 0.45)
    )
    path.addCurve(
        to: point(cx + topHalf, top + fillet),
        control1: point(cx + waistHalf, waistY - neckRun * 0.42),
        control2: point(cx + topHalf, top + fillet + neckRun * 0.5)
    )
    path.addCurve(
        to: point(cx + topHalf + fillet, top),
        control1: point(cx + topHalf, top + fillet * (1 - Corner.handle)),
        control2: point(cx + topHalf + fillet * (1 - Corner.handle), top)
    )
    path.addLine(to: point(cx + topHalf + fillet, top - overlap))
    path.closeSubpath()
    return path
}

/// One band segment of the gauge, from `from` to `to` turns, as a stroked arc.
func bandSegment(from: CGFloat, to: CGFloat, cap: CGLineCap) -> CGPath {
    let centre = point(Gauge.centre.x * S, Gauge.centre.y * S)
    let radius = Gauge.radius * S
    let arc = CGMutablePath()
    arc.move(to: onCircle(centre, radius, turns: from))
    arc.addArc(
        center: centre,
        radius: radius,
        startAngle: angle(turns: from),
        endAngle: angle(turns: to),
        clockwise: false
    )
    return arc.copy(strokingWithWidth: Gauge.stroke * S, lineCap: cap, lineJoin: .round, miterLimit: 10)
}

// MARK: - Layers

func drawIsland(_ context: CGContext) {
    context.addPath(islandPath())
    context.setFillColor(white(Island.opacity))
    context.fillPath()
}

func drawDrop(_ context: CGContext) {
    context.addPath(dropPath())
    context.setFillColor(white(1))
    context.fillPath()
}

/// The unused track: a dim circle in seven odometer ticks, the top one left open for the droplet.
func drawTrack(_ context: CGContext) {
    context.setFillColor(white(Gauge.trackOpacity))
    let step = 1 / CGFloat(Gauge.tickCount)
    let half = Gauge.tickWidth / 2
    for tick in 0..<Gauge.tickCount {
        let from = CGFloat(tick) * step + half
        let to = CGFloat(tick + 1) * step - half
        context.addPath(bandSegment(from: from, to: to, cap: .butt))
        context.fillPath()
    }
}

/// The used arc, in the ample band gradient, with a transparent "now" notch.
func drawArc(_ context: CGContext, warmTail: Bool) {
    let centre = point(Gauge.centre.x * S, Gauge.centre.y * S)
    let radius = Gauge.radius * S
    let stroke = Gauge.stroke * S
    context.saveGState()
    context.addPath(bandSegment(from: Gauge.arcStart, to: Gauge.arcEnd, cap: .round))
    context.clip()

    // An angular gradient, drawn as overlapping wedges: Core Graphics has no conic gradient, and a
    // clipped sweep of fixed steps stays deterministic.
    let span = Gauge.arcEnd - Gauge.arcStart
    let steps = 240
    let outer = radius + stroke
    for step in 0..<steps {
        let t = CGFloat(step) / CGFloat(steps - 1)
        let colour: CGColor
        if warmTail, t > 1 - Gauge.warmTail {
            let local = (t - (1 - Gauge.warmTail)) / Gauge.warmTail
            colour = mixed(Gauge.ampleEnd, Gauge.watchStart, local)
        } else {
            let base = warmTail ? t / (1 - Gauge.warmTail) : t
            colour = mixed(Gauge.ampleStart, Gauge.ampleEnd, base)
        }
        let from = Gauge.arcStart + span * (CGFloat(step) - 0.75) / CGFloat(steps - 1)
        let to = Gauge.arcStart + span * (CGFloat(step) + 0.75) / CGFloat(steps - 1)
        let wedge = CGMutablePath()
        wedge.move(to: centre)
        wedge.addArc(
            center: centre,
            radius: outer,
            startAngle: angle(turns: from),
            endAngle: angle(turns: to),
            clockwise: false
        )
        wedge.closeSubpath()
        context.addPath(wedge)
        context.setFillColor(colour)
        context.fillPath()
    }
    context.restoreGState()

    // The "now" notch: a transparent slit straight through the band.
    context.saveGState()
    context.setBlendMode(.clear)
    let inner = radius - stroke
    let outerReach = radius + stroke
    let a = Gauge.nowAt - Gauge.nowWidth / 2
    let b = Gauge.nowAt + Gauge.nowWidth / 2
    let notch = CGMutablePath()
    notch.move(to: onCircle(centre, inner, turns: a))
    notch.addLine(to: onCircle(centre, outerReach, turns: a))
    notch.addLine(to: onCircle(centre, outerReach, turns: b))
    notch.addLine(to: onCircle(centre, inner, turns: b))
    notch.closeSubpath()
    context.addPath(notch)
    context.fillPath()
    context.restoreGState()
}

// MARK: - Main

let arguments = CommandLine.arguments.dropFirst()
let flags = arguments.filter { $0.hasPrefix("--") }
let paths = arguments.filter { !$0.hasPrefix("--") }
let warmTail = flags.contains("--warm-tail")

for flag in flags where flag != "--warm-tail" {
    fail("unknown option \(flag)\nusage: swift RenderIconLayers.swift <out-dir> [--warm-tail]")
}
guard paths.count == 1, let outPath = paths.first else {
    fail("usage: swift RenderIconLayers.swift <out-dir> [--warm-tail]")
}

let outDirectory = URL(fileURLWithPath: outPath, isDirectory: true)
do {
    try FileManager.default.createDirectory(at: outDirectory, withIntermediateDirectories: true)
} catch {
    fail("could not create \(outDirectory.path): \(error.localizedDescription)")
}

let layers: [(name: String, draw: (CGContext) -> Void)] = [
    ("ring-track.png", drawTrack),
    ("ring-arc.png", { drawArc($0, warmTail: warmTail) }),
    ("island.png", drawIsland),
    ("droplet.png", drawDrop),
]

for layer in layers {
    let canvas = makeCanvas()
    layer.draw(canvas)
    writePNG(canvas, to: outDirectory.appendingPathComponent(layer.name))
}

note("RenderIconLayers: wrote \(layers.count) layers (\(side)×\(side), Display P3\(warmTail ? ", warm tail" : "")) to \(outDirectory.path)")
