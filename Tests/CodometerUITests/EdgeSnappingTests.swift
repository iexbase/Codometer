import CodometerCore
@testable import CodometerUI
import CoreGraphics
import Foundation
import Testing

/// Magnetic snapping of the carried island to the centre, the corners and the camera notch
///.
@Suite("Edge snapping")
struct EdgeSnappingTests {
    private let screen = CGRect(x: 0, y: 0, width: 1_600, height: 1_000)
    private let visible = CGRect(x: 0, y: 60, width: 1_600, height: 900)
    private let railSize = CGSize(width: 200, height: 34)

    private func area(_ edge: ScreenEdge, style: IslandStyle = .floating) -> CGRect {
        IslandGeometry.area(edge: edge, style: style, screen: screen, visible: visible)
    }

    private func notch() -> NotchGeometry {
        let width: CGFloat = 200
        let aux = (screen.width - width) / 2
        guard let notch = NotchGeometry.make(
            screen: screen,
            safeTop: 32,
            auxLeft: CGRect(x: 0, y: screen.maxY - 32, width: aux, height: 32),
            auxRight: CGRect(x: aux + width, y: screen.maxY - 32, width: aux, height: 32)
        ) else {
            fatalError("the fixture must produce a notch")
        }
        return notch
    }

    // MARK: - Targets

    @Test("Every edge offers the centre and both corners", arguments: ScreenEdge.allCases)
    func targetsPerEdge(edge: ScreenEdge) {
        let targets = EdgeSnapping.targets(
            edge: edge,
            railLength: max(railSize.width, railSize.height),
            area: area(edge),
            style: .floating,
            notch: nil,
            scale: 1
        )
        #expect(Set(targets.map(\.kind)) == [.center, .start, .end])
        #expect(targets.first(where: { $0.kind == .center })?.offset == 0.5)
        #expect(targets.first(where: { $0.kind == .start })?.offset == 0)
        #expect(targets.first(where: { $0.kind == .end })?.offset == 1)
        #expect(targets.allSatisfy { $0.radius == EdgeSnapping.targetRadius })
    }

    @Test("Both island styles offer the same kinds of target", arguments: [IslandStyle.attached, .floating])
    func targetsPerStyle(style: IslandStyle) {
        let targets = EdgeSnapping.targets(
            edge: .top,
            railLength: 200,
            area: area(.top, style: style),
            style: style,
            notch: nil,
            scale: 1
        )
        #expect(Set(targets.map(\.kind)) == [.center, .start, .end])
    }

    @Test("Corners are left out when the travel is shorter than two radii")
    func shortTravel() {
        // A rail nearly as wide as the screen leaves almost no travel: only the centre is offered.
        let targets = EdgeSnapping.targets(
            edge: .top,
            railLength: screen.width - 30,
            area: area(.top),
            style: .floating,
            notch: nil,
            scale: 1
        )
        #expect(targets.map(\.kind) == [.center])
    }

    @Test("The notch target exists only on the top edge, with a stronger pull")
    func notchTarget() {
        let top = EdgeSnapping.targets(edge: .top, railLength: 200, area: area(.top, style: .attached), style: .attached, notch: notch(), scale: 1)
        let notchTarget = top.first { $0.kind == .notch }
        #expect(notchTarget != nil)
        #expect(notchTarget?.radius == EdgeSnapping.notchRadius)
        // A centred notch sits exactly where the centre target is.
        #expect(abs((notchTarget?.offset ?? 0) - 0.5) < 0.0001)
        for edge in [ScreenEdge.bottom, .left, .right] {
            let targets = EdgeSnapping.targets(edge: edge, railLength: 200, area: area(edge, style: .attached), style: .attached, notch: notch(), scale: 1)
            #expect(!targets.contains { $0.kind == .notch })
        }
    }

    @Test("Radii follow the island's scale")
    func scaledRadii() {
        let targets = EdgeSnapping.targets(edge: .top, railLength: 200, area: area(.top), style: .floating, notch: nil, scale: 1.5)
        #expect(targets.first?.radius == EdgeSnapping.targetRadius * 1.5)
    }

    // MARK: - Resolve

    /// A pointer near the top edge at the given fraction of the edge's travel.
    private func pointer(offset: Double, edge: ScreenEdge = .top) -> CGPoint {
        let area = self.area(edge)
        let travel = EdgeSnapping.travel(edge: edge, railLength: railSize.width, area: area, style: .floating)
        let gap = IslandGeometry.gap(for: .floating)
        return CGPoint(x: area.minX + gap + railSize.width / 2 + travel * CGFloat(offset), y: area.maxY - 10)
    }

    private func resolve(
        offset: Double,
        state: EdgeSnapState = EdgeSnapState(),
        now: TimeInterval = 100,
        bypass: Bool = false,
        edge: ScreenEdge = .top,
        pointer point: CGPoint? = nil
    ) -> EdgeSnapResolution {
        let area = self.area(edge)
        let targets = EdgeSnapping.targets(edge: edge, railLength: railSize.width, area: area, style: .floating, notch: nil, scale: 1)
        return EdgeSnapping.resolve(
            pointer: point ?? pointer(offset: offset, edge: edge),
            placement: (edge, offset),
            targets: targets,
            area: area,
            railLength: railSize.width,
            style: .floating,
            state: state,
            now: now,
            bypass: bypass
        )
    }

    @Test("A locked target drops on exactly 0, 0.5 or 1")
    func lockedOffsets() {
        #expect(resolve(offset: 0.5).dropOffset == 0.5)
        #expect(resolve(offset: 0).dropOffset == 0)
        #expect(resolve(offset: 1).dropOffset == 1)
        #expect(resolve(offset: 0.5).locked == .center)
        #expect(resolve(offset: 0).locked == .start)
        #expect(resolve(offset: 1).locked == .end)
    }

    @Test("Far from every target the carry is free and nothing is locked")
    func freeCarry() {
        let resolution = resolve(offset: 0.25)
        #expect(resolution.locked == nil)
        #expect(resolution.displayShift == .zero)
        #expect(abs(resolution.dropOffset - 0.25) < 0.0001)
        #expect(resolution.haptic == nil)
    }

    @Test("The carried capsule never jumps: it moves smoothly across the whole radius and always forwards")
    func continuity() {
        let area = self.area(.top)
        let travel = EdgeSnapping.travel(edge: .top, railLength: railSize.width, area: area, style: .floating)
        var state = EdgeSnapState()
        var previous: CGFloat?
        var point = pointer(offset: 0.35)
        for step in 0...400 {
            point.x = pointer(offset: 0.35).x + CGFloat(step)
            let offset = Double((point.x - (area.minX + IslandGeometry.gap(for: .floating) + railSize.width / 2)) / travel)
            let resolution = resolve(offset: min(max(offset, 0), 1), state: state, now: 100 + Double(step), pointer: point)
            state = resolution.state
            let drawn = point.x + resolution.displayShift.dx
            if let previous {
                // The capsule follows the pointer (1 pt), plus at most the magnet's own easing slope inside the
                // radius; it never goes backwards and never jumps.
                #expect(drawn - previous >= -0.0001)
                #expect(drawn - previous <= 3.1)
            }
            previous = drawn
        }
    }

    @Test("A lock buzzes once and re-arms only after leaving the radius")
    func hapticOncePerLock() {
        var resolution = resolve(offset: 0.5, now: 100)
        #expect(resolution.haptic == .lock)
        // Still inside the core: no second haptic.
        resolution = resolve(offset: 0.5, state: resolution.state, now: 101)
        #expect(resolution.haptic == nil)
        // Away and back: a new lock buzzes again.
        resolution = resolve(offset: 0.25, state: resolution.state, now: 102)
        #expect(resolution.haptic == nil)
        resolution = resolve(offset: 0.5, state: resolution.state, now: 103)
        #expect(resolution.haptic == .lock)
    }

    @Test("Two locks closer together than 150 ms play one haptic")
    func hapticRateLimit() {
        var resolution = resolve(offset: 0.5, now: 100)
        #expect(resolution.haptic == .lock)
        resolution = resolve(offset: 0.25, state: resolution.state, now: 100.01)
        resolution = resolve(offset: 0, state: resolution.state, now: 100.05)
        #expect(resolution.locked == .start)
        #expect(resolution.haptic == nil)
        resolution = resolve(offset: 0.25, state: resolution.state, now: 100.06)
        resolution = resolve(offset: 0, state: resolution.state, now: 100.4)
        #expect(resolution.haptic == .lock)
    }

    @Test("⌘ bypasses the magnet completely")
    func bypass() {
        let resolution = resolve(offset: 0.5, bypass: true)
        #expect(resolution.locked == nil)
        #expect(resolution.displayShift == .zero)
        #expect(resolution.haptic == nil)
        #expect(resolution.dropOffset == 0.5)
    }

    @Test("Outside the drop zone the carry is free")
    func outsideDropZone() {
        let area = self.area(.top)
        let far = CGPoint(x: area.midX, y: area.maxY - EdgeSnapping.dropZone - 50)
        let resolution = resolve(offset: 0.5, pointer: far)
        #expect(resolution.locked == nil)
        #expect(resolution.haptic == nil)
        #expect(resolution.displayShift == .zero)
    }

    @Test("A locked target on a side edge pulls vertically, not horizontally")
    func sideEdgeAxis() {
        let resolution = resolve(offset: 0.48, edge: .right)
        #expect(resolution.displayShift.dx == 0)
    }

    @Test("Hysteresis: a pointer resting at the radius never flickers between locked and free")
    func hysteresis() {
        let area = self.area(.top)
        let travel = EdgeSnapping.travel(edge: .top, railLength: railSize.width, area: area, style: .floating)
        // Exactly the radius away from the centre: outside the core, so nothing locks, whatever the history.
        let offset = 0.5 + Double(EdgeSnapping.targetRadius / travel)
        var state = EdgeSnapState()
        var haptics = 0
        for step in 0...20 {
            let resolution = resolve(offset: offset, state: state, now: 100 + Double(step))
            state = resolution.state
            if resolution.haptic != nil { haptics += 1 }
            #expect(resolution.locked == nil)
        }
        #expect(haptics == 0)
    }

    @Test("The magnet law itself: locked core, free beyond the radius, smooth in between")
    func magnetLaw() {
        #expect(MagnetLaw.pull(distance: 0, radius: 28) == 1)
        #expect(MagnetLaw.pull(distance: 14, radius: 28) == 1)
        #expect(MagnetLaw.pull(distance: 28, radius: 28) == 0)
        #expect(MagnetLaw.pull(distance: 40, radius: 28) == 0)
        var previous: CGFloat = 1
        for step in 0...280 {
            let pull = MagnetLaw.pull(distance: CGFloat(step) / 10, radius: 28)
            #expect(pull <= previous + 0.0001)
            previous = pull
        }
        // Continuous: a one-point step never changes the pull by more than half.
        var last = MagnetLaw.pull(distance: 0, radius: 28)
        for distance in 1...40 {
            let pull = MagnetLaw.pull(distance: CGFloat(distance), radius: 28)
            #expect(abs(pull - last) <= 0.5)
            last = pull
        }
    }
}
