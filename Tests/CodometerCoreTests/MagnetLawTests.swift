import CodometerCore
import CoreGraphics
import Foundation
import Testing

@Suite("Magnet law")
struct MagnetLawTests {
    @Test("Full pull inside half the radius, none beyond the radius")
    func bounds() {
        let r = MagnetLaw.radius
        #expect(MagnetLaw.pull(distance: 0, radius: r) == 1)
        #expect(MagnetLaw.pull(distance: r / 2, radius: r) == 1)
        #expect(MagnetLaw.pull(distance: -r / 4, radius: r) == 1)
        #expect(MagnetLaw.pull(distance: r, radius: r) == 0)
        #expect(MagnetLaw.pull(distance: r * 3, radius: r) == 0)
        #expect(MagnetLaw.pull(distance: r * 0.75, radius: r) == 0.5)
        #expect(MagnetLaw.pull(distance: 5, radius: 0) == 0)
        #expect(MagnetLaw.pull(distance: 5, radius: -3) == 0)
        #expect(MagnetLaw.pull(distance: .nan, radius: r) == 0)
        #expect(MagnetLaw.pull(distance: 5, radius: .infinity) == 0)
    }

    @Test("Monotonic and continuous: no step in the pull, never steeper than smoothstep allows", arguments: [0.75, 1.0, 1.5])
    func continuity(scale: CGFloat) {
        let radius = MagnetLaw.radius * scale
        // Smoothstep's steepest slope is 1.5 over the easing band (radius / 2).
        let maximumSlope = 1.5 / (radius / 2)
        let step: CGFloat = 0.25
        var previous = MagnetLaw.pull(distance: 0, radius: radius)
        var distance = step
        while distance <= radius * 1.5 {
            let pull = MagnetLaw.pull(distance: distance, radius: radius)
            #expect(pull <= previous)
            #expect(previous - pull <= maximumSlope * step + 1e-9, "step at \(distance)")
            previous = pull
            distance += step
        }
        #expect(MagnetLaw.pull(distance: radius / 2 + 0.001, radius: radius) > 0.999)
        #expect(MagnetLaw.pull(distance: radius - 0.001, radius: radius) < 0.001)
    }

    @Test("The shared constants")
    func constants() {
        #expect(MagnetLaw.radius == 28)
        #expect(MagnetLaw.minimumHapticInterval == 0.15)
        #expect(SnapHaptic.allCases.count == 3)
    }
}

@Suite("Magnet arming")
struct MagnetArmingTests {
    /// One pointer sample: the nearest target, its distance, the time, whether a haptic should play and the lock after it.
    private struct Sample {
        let target: String?
        let distance: CGFloat
        let now: TimeInterval
        let plays: Bool
        let locked: String?
    }

    private func run(_ samples: [Sample], sourceLocation: SourceLocation = #_sourceLocation) {
        var arming = MagnetArming()
        for (index, sample) in samples.enumerated() {
            let plays = arming.update(targetID: sample.target, distance: sample.distance, radius: 28, now: sample.now)
            #expect(plays == sample.plays, "sample \(index)", sourceLocation: sourceLocation)
            #expect(arming.lockedTargetID == sample.locked, "sample \(index)", sourceLocation: sourceLocation)
        }
    }

    @Test("One haptic when a target locks, none while it stays locked, no flicker between half the radius and the radius")
    func locksOnce() {
        run([
            Sample(target: "center", distance: 26, now: 0, plays: false, locked: nil),
            Sample(target: "center", distance: 13, now: 0.1, plays: true, locked: "center"),
            Sample(target: "center", distance: 2, now: 0.5, plays: false, locked: "center"),
            Sample(target: "center", distance: 20, now: 0.6, plays: false, locked: "center"),
            Sample(target: "center", distance: 13, now: 0.7, plays: false, locked: "center"),
            Sample(target: "center", distance: 27.9, now: 0.8, plays: false, locked: "center"),
            Sample(target: "center", distance: 14, now: 0.9, plays: false, locked: "center"),
        ])
    }

    @Test("Re-arms only after leaving the radius or losing the target")
    func rearm() {
        run([
            Sample(target: "end", distance: 0, now: 0, plays: true, locked: "end"),
            Sample(target: "end", distance: 28, now: 1, plays: false, locked: "end"),
            Sample(target: "end", distance: 10, now: 2, plays: false, locked: "end"),
            Sample(target: "end", distance: 28.5, now: 3, plays: false, locked: nil),
            Sample(target: "end", distance: 10, now: 4, plays: true, locked: "end"),
            Sample(target: nil, distance: 0, now: 5, plays: false, locked: nil),
            Sample(target: "end", distance: 0, now: 6, plays: true, locked: "end"),
            Sample(target: "end", distance: .infinity, now: 7, plays: false, locked: nil),
        ])
    }

    @Test("Locks within 150 ms of the last haptic stay silent; a clock that went back never blocks")
    func rateLimit() {
        run([
            Sample(target: "a", distance: 0, now: 10, plays: true, locked: "a"),
            Sample(target: "b", distance: 0, now: 10.1, plays: false, locked: "b"),
            Sample(target: "a", distance: 0, now: 10.3, plays: true, locked: "a"),
            Sample(target: "b", distance: 0, now: 1, plays: true, locked: "b"),
        ])
    }

    @Test("Approaching another target releases the previous lock before locking the new one")
    func switchTargets() {
        run([
            Sample(target: "start", distance: 0, now: 0, plays: true, locked: "start"),
            Sample(target: "center", distance: 20, now: 1, plays: false, locked: nil),
            Sample(target: "center", distance: 5, now: 2, plays: true, locked: "center"),
        ])
    }
}
