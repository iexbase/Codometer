import CodometerCore
import AppKit
import QuartzCore
import SwiftUI

/// One layer-backed view that lives through every activity state, so a change can be animated instead of swapped.
///
/// It owns four lazily built pieces: the comet (a rotating container with a tapered tail and a round head), the
/// waiting pulse, the ring that closes when work finishes, and the check mark that draws afterwards. Everything runs
/// on the render server; the app does no per-frame work, and infinite animations stop whenever the window is hidden
/// or occluded (`LiveLayerView`).
///
/// The view keeps its previous activity and asks `ActivityTransition` what to play, so working → idle → working
/// flapping restarts the comet from the angle it froze at instead of jumping.
final class ActivityLayerView: LiveLayerView {
    private static let orbitKey = "orbit"
    private static let pulseKey = "pulse"
    private static let finishKey = "finish"

    /// The comet's container (tail and head), rotated as one.
    private var orbit: CALayer?
    private var segments: [CAShapeLayer] = []
    private var head: CAShapeLayer?
    private var pulse: CAShapeLayer?
    private var closing: CAShapeLayer?
    private var check: CAShapeLayer?

    private static let segmentCount = 20

    private(set) var activity: AgentActivity?
    private var style: FinishSequence.Style = .orbit
    /// Radius the sealed ring contracts to in `.glyph` style; the orbit radius otherwise.
    private var contractedRadius: CGFloat = 0
    /// The angle the comet froze at, so a restart picks up where it stopped.
    private var frozenAngle: Double = 0
    private var isFinishing = false

    /// Sets the activity and plays the transition. Call it from `updateNSView` only.
    func apply(activity newActivity: AgentActivity?, style: FinishSequence.Style, contractedRadius: CGFloat) {
        let changedShape = self.style != style || self.contractedRadius != contractedRadius
        self.style = style
        self.contractedRadius = contractedRadius
        let transition = ActivityTransition.between(activity, newActivity)
        activity = newActivity
        if changedShape {
            needsLayout = true
        }
        play(transition)
    }

    // MARK: Transitions

    private func play(_ transition: ActivityTransition) {
        switch transition {
        case .none:
            return
        case .startWorking:
            cancelFinish()
            pulse?.removeAnimation(forKey: Self.pulseKey)
            pulse?.isHidden = true
            buildComet()
            orbit?.isHidden = false
            orbit?.opacity = 1
            startAnimating()
        case .startWaiting:
            cancelFinish()
            orbit?.isHidden = true
            orbit?.removeAnimation(forKey: Self.orbitKey)
            buildPulse()
            pulse?.isHidden = false
            startAnimating()
        case .finish:
            finish()
        case .stopWaiting, .clear:
            cancelFinish()
            stopAnimating()
            orbit?.isHidden = true
            pulse?.isHidden = true
        }
    }

    /// Without a visible window the state simply jumps, the way the static views do.
    private func finish() {
        guard isVisibleOnScreen, bounds.width > 0, radius > 0 else {
            orbit?.isHidden = true
            pulse?.isHidden = true
            return
        }
        runFinish()
    }

    /// Freezes the comet where it is, seals the circle and draws the check mark. `finish()` decides whether to call
    /// it; tests call it directly, because a test has no window for the visibility gate to pass.
    func runFinish() {
        freezeComet()
        buildFinishLayers()
        guard let closing, let check else { return }
        isFinishing = true

        let head = CGFloat(Double.pi / 2 + frozenAngle)
        let path = CGMutablePath()
        path.addArc(center: CGPoint(x: bounds.midX, y: bounds.midY), radius: radius, startAngle: head, endAngle: head - 2 * .pi, clockwise: true)
        closing.path = path
        closing.isHidden = false
        closing.opacity = 1
        closing.strokeEnd = 1
        closing.transform = CATransform3DIdentity

        // 1. The comet seals its circle: the tail fades while the stroke runs once around from the head.
        let seal = CABasicAnimation(keyPath: "strokeEnd")
        seal.fromValue = 0
        seal.toValue = 1
        seal.duration = FinishSequence.closeDuration
        seal.timingFunction = CAMediaTimingFunction(name: .easeOut)
        closing.add(seal, forKey: Self.finishKey)

        if let orbit {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            fade.duration = FinishSequence.tailFadeDuration
            fade.fillMode = .forwards
            fade.isRemovedOnCompletion = false
            orbit.opacity = 0
            orbit.add(fade, forKey: Self.finishKey)
        }

        // 2. It settles: the sealed ring fades away, or contracts to the glyph's inner circle and then hands over.
        let settle = CAAnimationGroup()
        settle.beginTime = CACurrentMediaTime() + FinishSequence.settleStart(style)
        settle.duration = FinishSequence.settleDuration(style)
        settle.fillMode = .forwards
        settle.isRemovedOnCompletion = false
        settle.timingFunction = CAMediaTimingFunction(name: .easeOut)
        switch style {
        case .orbit:
            let dim = CABasicAnimation(keyPath: "opacity")
            dim.fromValue = 1
            dim.toValue = 0
            settle.animations = [dim]
        case .glyph:
            let shrink = CABasicAnimation(keyPath: "transform.scale")
            shrink.fromValue = 1
            shrink.toValue = radius > 0 ? contractedRadius / radius : 1
            settle.animations = [shrink]
            closing.add(crossfadeOut(), forKey: "handover")
        }
        closing.add(settle, forKey: "settle")

        // 3. The check mark draws on and crossfades into the still glyph underneath.
        check.isHidden = false
        check.strokeEnd = 1
        check.opacity = 0
        let draw = CABasicAnimation(keyPath: "strokeEnd")
        draw.fromValue = 0
        draw.toValue = 1
        draw.duration = FinishSequence.checkDuration(style)
        draw.timingFunction = CAMediaTimingFunction(name: .easeOut)
        let appear = CABasicAnimation(keyPath: "opacity")
        appear.fromValue = 1
        appear.toValue = 1
        appear.duration = max(0.01, FinishSequence.idleRevealDelay(style) - FinishSequence.checkStart(style))
        let leave = CABasicAnimation(keyPath: "opacity")
        leave.fromValue = 1
        leave.toValue = 0
        leave.beginTime = appear.duration
        leave.duration = FinishSequence.idleRevealDuration
        leave.fillMode = .forwards
        leave.isRemovedOnCompletion = false
        let group = CAAnimationGroup()
        group.animations = [draw, appear, leave]
        group.beginTime = CACurrentMediaTime() + FinishSequence.checkStart(style)
        group.duration = FinishSequence.total(style) - FinishSequence.checkStart(style)
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        check.add(group, forKey: Self.finishKey)
    }

    /// The fade that hands the moment over to the still glyph underneath.
    private func crossfadeOut() -> CABasicAnimation {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.beginTime = CACurrentMediaTime() + FinishSequence.idleRevealDelay(style)
        fade.duration = FinishSequence.idleRevealDuration
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        return fade
    }

    private func cancelFinish() {
        // The tail's fade is pinned forwards so the sealed circle stays alone; leaving it on the comet would make a
        // restarted comet run invisibly. Taking it off is what lets working → idle → working flap cleanly.
        if let orbit {
            orbit.removeAnimation(forKey: Self.finishKey)
            orbit.opacity = 1
        }
        guard isFinishing else { return }
        isFinishing = false
        closing?.removeAllAnimations()
        closing?.isHidden = true
        check?.removeAllAnimations()
        check?.isHidden = true
    }

    /// Reads the running rotation and pins the comet to it, so removing the animation causes no jump.
    private func freezeComet() {
        guard let orbit else { return }
        let presented = orbit.presentation()?.value(forKeyPath: "transform.rotation.z") as? Double
        frozenAngle = CometAngle.normalized(presented ?? 0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        orbit.setValue(frozenAngle, forKeyPath: "transform.rotation.z")
        CATransaction.commit()
        orbit.removeAnimation(forKey: Self.orbitKey)
    }

    // MARK: Layers

    private func buildComet() {
        guard orbit == nil else { return }
        let container = CALayer()
        for _ in 0..<Self.segmentCount {
            let segment = CAShapeLayer()
            segment.fillColor = nil
            segment.lineCap = .butt
            segments.append(segment)
            container.addSublayer(segment)
        }
        let dot = CAShapeLayer()
        container.addSublayer(dot)
        head = dot
        orbit = container
        layer?.insertSublayer(container, at: 0)
        needsLayout = true
    }

    private func buildPulse() {
        guard pulse == nil else { return }
        let ring = CAShapeLayer()
        ring.fillColor = nil
        pulse = ring
        layer?.addSublayer(ring)
        needsLayout = true
    }

    private func buildFinishLayers() {
        if closing == nil {
            let ring = CAShapeLayer()
            ring.fillColor = nil
            ring.lineCap = .round
            closing = ring
            layer?.addSublayer(ring)
        }
        if check == nil {
            let mark = CAShapeLayer()
            mark.fillColor = nil
            mark.lineCap = .round
            mark.lineJoin = .round
            check = mark
            layer?.addSublayer(mark)
        }
        layoutFinishLayers()
    }

    // MARK: LiveLayerView

    override func rebuild() {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let color = resolved(.labelColor)
        if let orbit {
            orbit.bounds = bounds
            orbit.position = center
            // Layer space is y-up: 12 o'clock is π/2 and "behind" a clockwise head is a larger angle.
            let top = CGFloat.pi / 2
            for (layer, segment) in zip(segments, OrbitGeometry.tailSegments(count: Self.segmentCount)) {
                let path = CGMutablePath()
                path.addArc(
                    center: center,
                    radius: radius,
                    startAngle: top + CGFloat(segment.from * 2 * .pi),
                    endAngle: top + CGFloat(segment.to * 2 * .pi),
                    clockwise: true
                )
                layer.frame = bounds
                layer.path = path
                layer.lineWidth = lineWidth * CGFloat(segment.width)
                layer.strokeColor = color.copy(alpha: CGFloat(segment.opacity))
            }
            let dot = lineWidth * 0.62
            head?.frame = bounds
            head?.path = CGPath(ellipseIn: CGRect(x: center.x - dot, y: center.y + radius - dot, width: dot * 2, height: dot * 2), transform: nil)
            head?.fillColor = color.copy(alpha: 0.92)
        }
        if let pulse {
            pulse.frame = bounds
            pulse.path = CGPath(
                ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2),
                transform: nil
            )
            pulse.lineWidth = lineWidth
            pulse.strokeColor = resolved(NSColor(Theme.attention))
        }
        layoutFinishLayers()
    }

    private func layoutFinishLayers() {
        guard closing != nil || check != nil else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let color = resolved(.labelColor)
        if let closing {
            closing.frame = bounds
            closing.bounds = bounds
            closing.position = center
            closing.lineWidth = lineWidth
            closing.strokeColor = color.copy(alpha: 0.92)
        }
        if let check {
            let side = checkSide
            let box = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
            let points = CheckmarkPath.points(in: side)
            let path = CGMutablePath()
            // Layer space is y-up; the path's points are given y-down, so they are mirrored into the box.
            let mapped = points.map { CGPoint(x: box.minX + $0.x, y: box.maxY - $0.y) }
            path.move(to: mapped[0])
            path.addLine(to: mapped[1])
            path.addLine(to: mapped[2])
            check.frame = bounds
            check.path = path
            check.lineWidth = CheckmarkPath.lineWidth(for: side)
            check.strokeColor = color.copy(alpha: 0.85)
        }
    }

    /// How big the check mark is: a small mark beside an orbit, the glyph's own inner circle in a session row.
    private var checkSide: CGFloat {
        switch style {
        case .orbit: max(8, lineWidth * 6)
        case .glyph: max(8, contractedRadius * 1.6)
        }
    }

    override func startAnimating() {
        switch activity {
        case .working?:
            guard let orbit, orbit.animation(forKey: Self.orbitKey) == nil, !isFinishing else { return }
            let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
            rotation.fromValue = frozenAngle
            rotation.toValue = frozenAngle - Double.pi * 2
            rotation.duration = OrbitGeometry.lapDuration
            rotation.repeatCount = .infinity
            rotation.isRemovedOnCompletion = false
            orbit.add(rotation, forKey: Self.orbitKey)
        case .waiting?:
            guard let pulse, pulse.animation(forKey: Self.pulseKey) == nil else { return }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.25
            fade.toValue = 1
            let swell = CABasicAnimation(keyPath: "lineWidth")
            swell.fromValue = lineWidth * 0.7
            swell.toValue = lineWidth * 1.15
            let group = CAAnimationGroup()
            group.animations = [fade, swell]
            group.duration = OrbitGeometry.pulseDuration
            group.autoreverses = true
            group.repeatCount = .infinity
            group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            group.isRemovedOnCompletion = false
            pulse.add(group, forKey: Self.pulseKey)
        case .idle?, nil:
            return
        }
    }

    override func stopAnimating() {
        if let orbit, orbit.animation(forKey: Self.orbitKey) != nil {
            frozenAngle = CometAngle.normalized((orbit.presentation()?.value(forKeyPath: "transform.rotation.z") as? Double) ?? frozenAngle)
            orbit.removeAnimation(forKey: Self.orbitKey)
        }
        pulse?.removeAnimation(forKey: Self.pulseKey)
    }
}
