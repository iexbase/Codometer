import CodometerCore
import CoreGraphics
import Foundation

/// What has to happen on a ring when an account's activity changes.
///
/// Pure, so the animation layer only has to play what this decides.
public enum ActivityTransition: Hashable, Sendable {
    /// Nothing changed, or the change needs no motion.
    case none
    /// The comet starts running (from idle, from nothing, or out of a waiting pulse).
    case startWorking
    /// The waiting pulse starts.
    case startWaiting
    /// Work is done: the comet seals its circle and a check mark draws on.
    case finish
    /// The wait ended without work starting.
    case stopWaiting
    /// There is no activity to show at all any more (the account went away).
    case clear

    /// The transition between two activities; `nil` means "no session state at all".
    public nonisolated static func between(_ old: AgentActivity?, _ new: AgentActivity?) -> ActivityTransition {
        switch (old, new) {
        case (.working, .idle), (.working, nil):
            return .finish
        case (_, .working) where old != .working:
            return .startWorking
        case (_, .waiting) where old != .waiting:
            return .startWaiting
        case (.waiting, .idle):
            return .stopWaiting
        case (.waiting, nil), (.idle, nil):
            return .clear
        default:
            return .none
        }
    }
}

/// The timings of the finishing sequence: the comet freezes where it is, runs once more around to seal the circle,
/// and a check mark draws on.
///
/// Two shapes of the same sequence: an `.orbit` (rail and deck dials, the card) settles by fading the sealed ring out
/// under a small check mark beside it; a `.glyph` (a session row) contracts the ring and draws the check mark in its
/// centre, ending on exactly the static idle glyph.
public enum FinishSequence {
    public enum Style: Hashable, Sendable, CaseIterable {
        case orbit
        case glyph
    }

    /// Sealing the circle: the closing ring's stroke runs once around from the comet's head.
    public static let closeDuration: CFTimeInterval = 0.3
    /// The tail fades out while the ring closes.
    public static let tailFadeDuration: CFTimeInterval = 0.18
    /// A beat between the sealed circle and the orbit's fade; the glyph contracts straight away instead.
    public static let holdDuration: CFTimeInterval = 0.12
    /// How long the still idle glyph takes to fade in while the drawn check mark fades out, so a session row never
    /// shows two check marks.
    public static let idleRevealDuration: CFTimeInterval = 0.15

    /// The sealed ring fading away (`.orbit`), or contracting to the inner circle (`.glyph`).
    public static func settleDuration(_ style: Style) -> CFTimeInterval {
        switch style {
        case .orbit: 0.35
        case .glyph: 0.2
        }
    }

    /// When the sealed ring starts to settle.
    public static func settleStart(_ style: Style) -> CFTimeInterval {
        switch style {
        case .orbit: closeDuration + holdDuration
        case .glyph: closeDuration
        }
    }

    /// When the check mark starts drawing: beside the ring while it fades (`.orbit`), or in the middle once the ring
    /// has contracted (`.glyph`).
    public static func checkStart(_ style: Style) -> CFTimeInterval {
        switch style {
        case .orbit: settleStart(.orbit)
        case .glyph: settleStart(.glyph) + settleDuration(.glyph)
        }
    }

    /// How long the check mark takes to draw.
    public static func checkDuration(_ style: Style) -> CFTimeInterval {
        switch style {
        case .orbit: 0.22
        case .glyph: 0.24
        }
    }

    /// The whole sequence, from the freeze to the last frame. Never longer than `maximum`.
    public static func total(_ style: Style) -> CFTimeInterval {
        switch style {
        case .orbit: max(checkStart(.orbit) + checkDuration(.orbit), settleStart(.orbit) + settleDuration(.orbit))
        // The glyph hands over to the still idle check mark underneath, and that crossfade is part of the sequence.
        case .glyph: checkStart(.glyph) + checkDuration(.glyph) + idleRevealDuration
        }
    }

    /// When the drawn check mark starts to give way: to the still idle glyph (`.glyph`), or to nothing (`.orbit`).
    public static func idleRevealDelay(_ style: Style) -> CFTimeInterval {
        max(0, total(style) - idleRevealDuration)
    }

    /// The budget the design gives the sequence: a finish is a moment, not an animation to sit through.
    public static let maximum: CFTimeInterval = 0.95
}

/// The comet's angle, read off the running rotation so a freeze never jumps.
public enum CometAngle {
    /// A layer's accumulated `transform.rotation.z` mapped into 0 ..< 2π. The comet runs clockwise, which is a
    /// negative rotation in the layer's y-up space, so accumulated values are large negatives.
    public nonisolated static func normalized(_ radians: Double) -> Double {
        guard radians.isFinite else { return 0 }
        let turn = 2 * Double.pi
        let wrapped = radians.truncatingRemainder(dividingBy: turn)
        return wrapped < 0 ? wrapped + turn : wrapped
    }
}

/// The check mark drawn when an agent finishes: three points inside a circle of the given size.
public enum CheckmarkPath {
    /// The three points of the stroke — start, elbow, end — in a rect of `size` × `size`, y down.
    ///
    /// They stay inside the circle inscribed in that rect, with room for the stroke, at every size the app draws
    /// (14…60 pt).
    public nonisolated static func points(in size: CGFloat) -> [CGPoint] {
        let side = max(size, 1)
        return [
            CGPoint(x: side * 0.26, y: side * 0.52),
            CGPoint(x: side * 0.43, y: side * 0.69),
            CGPoint(x: side * 0.76, y: side * 0.32),
        ]
    }

    /// Stroke width for a check mark of this size.
    public nonisolated static func lineWidth(for size: CGFloat) -> CGFloat {
        max(1.2, size * 0.12)
    }

    /// The largest distance from the centre any point reaches, as a fraction of the radius. Below 1 the mark fits
    /// inside the circle; the drawing keeps `lineWidth / 2` on top of that.
    public nonisolated static func extent(in size: CGFloat) -> CGFloat {
        let side = max(size, 1)
        let center = CGPoint(x: side / 2, y: side / 2)
        let radius = side / 2
        return points(in: side)
            .map { hypot($0.x - center.x, $0.y - center.y) / radius }
            .max() ?? 0
    }
}
