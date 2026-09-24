import CodometerCore
import AppKit
@testable import CodometerUI
import CoreGraphics
import QuartzCore
import Foundation
import Testing

/// The pure parts of the finishing sequence: what a change of activity means, how long each phase lasts, where the
/// frozen comet is, and whether the check mark fits its circle.
@Suite("Activity transitions")
struct ActivityTransitionTests {
    private static let states: [AgentActivity?] = [nil, .idle, .working, .waiting]

    @Test("Every pair of activities maps to exactly one transition")
    func matrix() {
        var seen: [ActivityTransition: Int] = [:]
        for old in Self.states {
            for new in Self.states {
                seen[ActivityTransition.between(old, new), default: 0] += 1
            }
        }
        // 4 × 4 pairs, and every case of the enum is reachable.
        #expect(seen.values.reduce(0, +) == 16)
        #expect(Set(seen.keys) == [.none, .startWorking, .startWaiting, .finish, .stopWaiting, .clear])
    }

    @Test("Work ending is a finish, whether the session goes idle or disappears")
    func finishing() {
        #expect(ActivityTransition.between(.working, .idle) == .finish)
        #expect(ActivityTransition.between(.working, nil) == .finish)
        #expect(ActivityTransition.between(.working, .working) == .none)
        #expect(ActivityTransition.between(.working, .waiting) == .startWaiting)
    }

    @Test("Work starting from anywhere restarts the comet")
    func starting() {
        #expect(ActivityTransition.between(nil, .working) == .startWorking)
        #expect(ActivityTransition.between(.idle, .working) == .startWorking)
        #expect(ActivityTransition.between(.waiting, .working) == .startWorking)
    }

    @Test("A wait that ends without work is no finish, and a vanished session simply clears")
    func waiting() {
        #expect(ActivityTransition.between(.waiting, .idle) == .stopWaiting)
        #expect(ActivityTransition.between(.waiting, nil) == .clear)
        #expect(ActivityTransition.between(.idle, nil) == .clear)
        #expect(ActivityTransition.between(nil, .idle) == .none)
        #expect(ActivityTransition.between(nil, nil) == .none)
    }

    @Test("The phases follow one another and the whole finish stays inside its budget", arguments: [FinishSequence.Style.orbit, .glyph])
    func phases(style: FinishSequence.Style) {
        // The ring only settles once the circle is sealed.
        #expect(FinishSequence.settleStart(style) >= FinishSequence.closeDuration)
        // The check mark never starts before the ring has begun to settle.
        #expect(FinishSequence.checkStart(style) >= FinishSequence.settleStart(style))
        #expect(FinishSequence.checkStart(style) + FinishSequence.checkDuration(style) <= FinishSequence.total(style))
        #expect(FinishSequence.settleStart(style) + FinishSequence.settleDuration(style) <= FinishSequence.total(style))
        #expect(FinishSequence.total(style) <= FinishSequence.maximum)
        // The tail is gone long before the ring closes.
        #expect(FinishSequence.tailFadeDuration < FinishSequence.closeDuration)
    }

    @Test("A session row takes longer than a dial, because it hands over to the still glyph")
    func glyphIsLonger() {
        #expect(FinishSequence.total(.glyph) > FinishSequence.total(.orbit))
        // The still check mark fades in exactly while the drawn one fades out.
        #expect(FinishSequence.idleRevealDelay(.glyph) + FinishSequence.idleRevealDuration == FinishSequence.total(.glyph))
        #expect(FinishSequence.idleRevealDelay(.glyph) >= FinishSequence.checkStart(.glyph) + FinishSequence.checkDuration(.glyph))
        // A dial's check mark starts to leave while the sealed ring is still fading, and both end together.
        #expect(FinishSequence.idleRevealDelay(.orbit) + FinishSequence.idleRevealDuration == FinishSequence.total(.orbit))
    }

    @Test("An accumulated rotation reads as an angle inside one turn")
    func cometAngle() {
        let turn = 2 * Double.pi
        #expect(CometAngle.normalized(0) == 0)
        #expect(abs(CometAngle.normalized(-turn * 5 - 1) - (turn - 1)) < 1e-9)
        #expect(abs(CometAngle.normalized(turn * 3 + 0.5) - 0.5) < 1e-9)
        #expect((0..<turn).contains(CometAngle.normalized(-0.000_1)))
        // A layer that has not been committed yet reports nothing usable.
        #expect(CometAngle.normalized(.nan) == 0)
        #expect(CometAngle.normalized(.infinity) == 0)
    }

    @Test("The check mark stays inside its circle at every size the app draws", arguments: [14.0, 22.0, 30.0, 46.0, 60.0])
    func checkmarkBounds(size: Double) {
        let side = CGFloat(size)
        let points = CheckmarkPath.points(in: side)
        #expect(points.count == 3)
        // Inside the box…
        for point in points {
            #expect(point.x > 0 && point.x < side)
            #expect(point.y > 0 && point.y < side)
        }
        // …and inside the inscribed circle, with room for the stroke.
        let room = (side / 2 - CheckmarkPath.lineWidth(for: side) / 2) / (side / 2)
        #expect(CheckmarkPath.extent(in: side) < room)
        // A mark that reads as a check: down to the elbow, then up and to the right.
        #expect(points[1].y > points[0].y && points[1].y > points[2].y)
        #expect(points[0].x < points[1].x && points[1].x < points[2].x)
    }

    @MainActor
    @Test("Work ending outside a window leaves nothing drawn, so the still glyph takes over cleanly")
    func finishWithoutAWindow() {
        let side: CGFloat = 44
        let view = ActivityLayerView(frame: CGRect(x: 0, y: 0, width: side, height: side))
        view.configure(radius: side / 2, lineWidth: 4)
        view.layout()
        view.apply(activity: .working, style: .glyph, contractedRadius: side / 2 - 4)
        view.apply(activity: .idle, style: .glyph, contractedRadius: side / 2 - 4)
        #expect(view.activity == .idle)
        // Nothing plays where nobody looks: every layer it built is hidden or fully transparent.
        let visible = (view.layer?.sublayers ?? []).filter { !$0.isHidden && $0.opacity > 0 }
        #expect(visible.isEmpty, "\(visible.count) layers left drawn")
    }

    @MainActor
    @Test("Work starting again cancels a finish instead of leaving half a check mark")
    func flapping() {
        let side: CGFloat = 44
        let view = ActivityLayerView(frame: CGRect(x: 0, y: 0, width: side, height: side))
        view.configure(radius: side / 2, lineWidth: 4)
        view.layout()
        for activity in [AgentActivity.working, .idle, .working, .idle, .waiting, .working] {
            view.apply(activity: activity, style: .orbit, contractedRadius: side / 2)
        }
        #expect(view.activity == .working)
        let drawn = (view.layer?.sublayers ?? []).filter { !$0.isHidden && $0.opacity > 0 }
        // Only the comet is left: no sealed ring, no check mark.
        #expect(drawn.count <= 1)
    }

    @MainActor
    @Test("A comet that starts again after a real finish is not left invisible")
    func restartAfterFinish() throws {
        let side: CGFloat = 60
        let view = ActivityLayerView(frame: CGRect(x: 0, y: 0, width: side, height: side))
        view.configure(radius: side / 2 - 3, lineWidth: 5)
        view.layout()
        view.apply(activity: .working, style: .orbit, contractedRadius: side / 4)
        view.apply(activity: .idle, style: .orbit, contractedRadius: side / 4)
        // What a visible view does at that point; a test has no window for the gate to pass. The finish fades the
        // tail out and pins it there, so the sealed circle is alone on the ring.
        view.runFinish()
        let orbit = try #require(Self.orbitLayer(of: view), "the comet's container")
        #expect(orbit.animation(forKey: "finish") != nil, "the tail fades out during a finish")
        // Work starts again before the account settles: the comet has to come back.
        view.apply(activity: .working, style: .orbit, contractedRadius: side / 4)
        #expect(orbit.animation(forKey: "finish") == nil, "the pinned fade would keep the comet at opacity 0")
        #expect(orbit.opacity == 1)
        #expect(orbit.isHidden == false)
    }

    /// The comet's container: the only plain `CALayer` among the view's sublayers (the rest are shape layers).
    @MainActor
    private static func orbitLayer(of view: ActivityLayerView) -> CALayer? {
        (view.layer?.sublayers ?? []).first { !($0 is CAShapeLayer) }
    }

    @MainActor
    @Test("The finish puts one sealing ring and one check mark on the render server", arguments: FinishSequence.Style.allCases)
    func finishAnimations(style: FinishSequence.Style) throws {
        let side: CGFloat = 60
        let view = ActivityLayerView(frame: CGRect(x: 0, y: 0, width: side, height: side))
        view.configure(radius: side / 2 - 3, lineWidth: 5)
        view.layout()
        view.apply(activity: .working, style: style, contractedRadius: side / 4)
        view.runFinish()
        let layers = view.layer?.sublayers ?? []
        let sealing = try #require(layers.first { $0.animation(forKey: "settle") != nil })
        let check = try #require(layers.first { $0.animation(forKey: "finish") is CAAnimationGroup })
        #expect(sealing !== check)
        // The circle closes first, then the ring settles, then the mark draws.
        let seal = try #require(sealing.animation(forKey: "finish") as? CABasicAnimation)
        #expect(seal.keyPath == "strokeEnd" && seal.duration == FinishSequence.closeDuration)
        let settle = try #require(sealing.animation(forKey: "settle") as? CAAnimationGroup)
        #expect(settle.duration == FinishSequence.settleDuration(style))
        let mark = try #require(check.animation(forKey: "finish") as? CAAnimationGroup)
        #expect(mark.duration == FinishSequence.total(style) - FinishSequence.checkStart(style))
        #expect(mark.animations?.count == 3, "draw, hold and hand over")
        // Nothing repeats and nothing is left running.
        #expect(settle.repeatCount == 0 && mark.repeatCount == 0)
    }

    @Test("A degenerate size still produces a usable mark")
    func checkmarkDegenerate() {
        #expect(CheckmarkPath.points(in: 0).count == 3)
        #expect(CheckmarkPath.lineWidth(for: 0) == 1.2)
        #expect(CheckmarkPath.extent(in: 0) > 0)
    }
}
