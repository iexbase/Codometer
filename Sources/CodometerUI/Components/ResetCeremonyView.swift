import CodometerCore
import AppKit
import QuartzCore
import SwiftUI

/// The reset ceremonies one surface may play, and where to report that it has.
///
/// A surface that celebrates puts this in the environment for its rings: the rail does it for its own dials, and the
/// deck, the popover and the floating card do it for theirs. Without a stage — measurement copies, settings previews,
/// static renders — nothing is ever celebrated.
public struct CeremonyStage {
    public let surface: CeremonySurface
    public let board: CeremonyBoard
    /// The store's clock, so what is live is decided once and renders stay deterministic.
    public let now: Date
    /// Called on a later main-actor turn, never inside a view update.
    public let markPlayed: @MainActor (UUID, CeremonySurface) -> Void

    public init(
        surface: CeremonySurface,
        board: CeremonyBoard,
        now: Date,
        markPlayed: @escaping @MainActor (UUID, CeremonySurface) -> Void
    ) {
        self.surface = surface
        self.board = board
        self.now = now
        self.markPlayed = markPlayed
    }

    /// This account's live ceremonies that the surface has not played, keyed `"<bucketID>/<windowID>"` the way
    /// `WindowPresentation.id` is, ready for `RingGeometry.specs(ceremonies:)`.
    public func ceremonies(of accountID: AccountID) -> [String: ResetCeremony] {
        let unplayed = board.unplayed(on: surface, now: now).filter { $0.event.accountID == accountID }
        return Dictionary(
            unplayed.map { ("\($0.event.bucketID)/\($0.event.windowID)", $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }
}

extension CeremonyStage: Equatable {
    /// The closure is the surface's own and never changes what is drawn.
    public static func == (lhs: CeremonyStage, rhs: CeremonyStage) -> Bool {
        lhs.surface == rhs.surface && lhs.now == rhs.now && lhs.board == rhs.board
    }
}

extension EnvironmentValues {
    /// Set by a surface that celebrates limit resets on its rings; `nil` everywhere else.
    @Entry public var ceremonyStage: CeremonyStage? = nil
}

/// The timings of a reset ceremony: the arc unwinds to the new value, a glint rides its end, and a green ring
/// flashes once the arc has arrived.
///
/// The unwind is the ring's own `Motion.gauge` animation of a changed value; only the glint and the flash are drawn
/// here, as two one-shot Core Animation runs.
public enum ResetCeremonyPlan {
    /// The glint rides the arc for exactly as long as the arc takes to move.
    public static let glintDuration: CFTimeInterval = 0.9
    /// The flash starts while the arc is settling.
    public static let flashDelay: CFTimeInterval = 0.72
    public static let flashDuration: CFTimeInterval = 0.55
    /// Inner rings of the same account that reset together follow one after another.
    public static let ringStagger: CFTimeInterval = 0.12
    /// With Reduce Motion the green ring only fades, and nothing moves or scales.
    public static let reducedDuration: CFTimeInterval = 0.25

    /// The whole ceremony, about the 1.25 s the design asks for.
    public static let total: CFTimeInterval = flashDelay + flashDuration

    /// How far the flash ring swells.
    public static let flashScale: CGFloat = 1.16
    /// The glint's diameter, relative to the ring's line width.
    public static let glintSize: CGFloat = 0.7
}

/// One ring's celebration, drawn over it: a glint riding the unwinding arc and a green flash ring.
///
/// Layer-backed and event-driven like `SheenSweepView`: the layers are built on the first play, both animations run
/// on the render server, and nothing at all happens while the ring rests.
struct ResetCeremonyRing: NSViewRepresentable {
    let ceremony: ResetCeremony
    let ring: RingGeometry.Ring
    /// Where the arc ends now, as a fraction of a turn.
    let fraction: Double
    /// Staggers inner rings of the same account.
    let delay: CFTimeInterval
    let reduceMotion: Bool
    let onPlayed: @MainActor (UUID) -> Void

    func makeNSView(context: Context) -> ResetCeremonyView {
        ResetCeremonyView()
    }

    func updateNSView(_ view: ResetCeremonyView, context: Context) {
        view.onPlayed = onPlayed
        view.update(
            ceremony: ceremony,
            ring: ring,
            fraction: fraction,
            delay: delay,
            reduceMotion: reduceMotion
        )
    }
}

final class ResetCeremonyView: LiveLayerView {
    private static let glintKey = "glint"
    private static let flashKey = "flash"

    private var glint: CAShapeLayer?
    private var flash: CAShapeLayer?

    private var ceremony: ResetCeremony?
    private var fraction: Double = 0
    private var delay: CFTimeInterval = 0
    private var reduceMotion = false
    /// The last ceremony this view actually played, so a re-render never replays it.
    private var playedID: UUID?

    var onPlayed: (@MainActor (UUID) -> Void)?

    func update(ceremony: ResetCeremony, ring: RingGeometry.Ring, fraction: Double, delay: CFTimeInterval, reduceMotion: Bool) {
        self.ceremony = ceremony
        self.fraction = fraction
        self.delay = delay
        self.reduceMotion = reduceMotion
        configure(radius: ring.radius, lineWidth: ring.lineWidth)
        playIfPossible()
    }

    /// Plays once the ring is on screen. A ceremony that arrives while the surface is hidden waits for it to appear;
    /// when it expires first, nothing is played and nothing is marked.
    private func playIfPossible() {
        guard let ceremony, ceremony.id != playedID, isVisibleOnScreen, bounds.width > 0, radius > 0 else { return }
        playedID = ceremony.id
        play(ceremony)
        let id = ceremony.id
        let report = onPlayed
        // Never inside a view update: the store's board is changed on a later turn.
        Task { @MainActor in
            report?(id)
        }
    }

    /// Builds and starts the ceremony's two one-shot animations. `playIfPossible` decides whether to call it; tests
    /// call it directly, because a test has no window for the visibility gate to pass.
    func play(_ ceremony: ResetCeremony) {
        buildLayers()
        guard let flash else { return }
        let start = CACurrentMediaTime() + delay
        let green = Theme.color(Palette.bandGradient(.ample).start)
        let stroke = resolved(NSColor(green))
        flash.strokeColor = stroke
        flash.shadowColor = stroke
        flash.isHidden = false

        if reduceMotion {
            // Opacity only: no glint, no swell.
            glint?.isHidden = true
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.85
            fade.toValue = 0
            fade.beginTime = start
            fade.duration = ResetCeremonyPlan.reducedDuration
            fade.fillMode = .forwards
            fade.isRemovedOnCompletion = false
            flash.add(fade, forKey: Self.flashKey)
            return
        }

        if let glint {
            glint.isHidden = false
            let path = CGMutablePath()
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            // Layer space is y-up: a fraction of a turn clockwise from 12 o'clock is π/2 − f·2π, so unwinding
            // towards a smaller fraction sweeps counter-clockwise.
            let from = CGFloat(Double.pi / 2 - ceremony.previousFraction * 2 * .pi)
            let to = CGFloat(Double.pi / 2 - min(max(fraction, 0), 1) * 2 * .pi)
            path.addArc(center: center, radius: radius, startAngle: from, endAngle: to, clockwise: false)

            let ride = CAKeyframeAnimation(keyPath: "position")
            ride.path = path
            ride.calculationMode = .paced
            ride.duration = ResetCeremonyPlan.glintDuration
            ride.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]
            fade.keyTimes = [0, 0.08, 0.85, 1]
            fade.duration = ResetCeremonyPlan.glintDuration
            let group = CAAnimationGroup()
            group.animations = [ride, fade]
            group.beginTime = start
            group.duration = ResetCeremonyPlan.glintDuration
            group.fillMode = .backwards
            glint.opacity = 0
            glint.shadowColor = stroke
            glint.add(group, forKey: Self.glintKey)
        }

        let swell = CABasicAnimation(keyPath: "transform.scale")
        swell.fromValue = 1
        swell.toValue = ResetCeremonyPlan.flashScale
        let dim = CABasicAnimation(keyPath: "opacity")
        dim.fromValue = 0.85
        dim.toValue = 0
        let bloom = CABasicAnimation(keyPath: "shadowOpacity")
        bloom.fromValue = 0.6
        bloom.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [swell, dim, bloom]
        group.beginTime = start + ResetCeremonyPlan.flashDelay
        group.duration = ResetCeremonyPlan.flashDuration
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        // No fill in either direction: a ring filling backwards would sit on the dial at full opacity for the whole
        // 0.72 s of the unwind, which is a green halo, not a flash. Before it begins and after it ends the layer's
        // own opacity of 0 is what shows.
        group.fillMode = .removed
        flash.opacity = 0
        flash.add(group, forKey: Self.flashKey)
    }

    private func buildLayers() {
        if flash == nil {
            let ring = CAShapeLayer()
            ring.fillColor = nil
            ring.shadowOffset = .zero
            ring.shadowOpacity = 0
            flash = ring
            layer?.addSublayer(ring)
        }
        if glint == nil, !reduceMotion {
            let dot = CAShapeLayer()
            dot.strokeColor = nil
            dot.fillColor = CGColor(gray: 1, alpha: 0.95)
            dot.shadowOffset = .zero
            dot.shadowOpacity = 0.9
            glint = dot
            layer?.addSublayer(dot)
        }
        layoutLayers()
    }

    override func rebuild() {
        layoutLayers()
    }

    private func layoutLayers() {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        if let flash {
            flash.bounds = bounds
            flash.position = center
            flash.path = CGPath(
                ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2),
                transform: nil
            )
            flash.lineWidth = lineWidth
            flash.shadowRadius = lineWidth
        }
        if let glint {
            let size = max(1, lineWidth * ResetCeremonyPlan.glintSize)
            glint.bounds = CGRect(x: 0, y: 0, width: size * 2, height: size * 2)
            glint.path = CGPath(ellipseIn: CGRect(x: size / 2, y: size / 2, width: size, height: size), transform: nil)
            glint.shadowRadius = lineWidth
            glint.position = center
        }
    }

    /// Nothing runs on its own: the ceremony is one shot, played when it arrives.
    override func startAnimating() {
        playIfPossible()
    }
}
