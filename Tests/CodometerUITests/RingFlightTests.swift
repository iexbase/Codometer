import CodometerCore
@testable import CodometerUI
import CoreGraphics
import Foundation
import Testing

/// The rings that fly between the rail and the deck: which accounts fly, and where each ring is at every moment
/// of the flight.
@Suite("Ring flight")
struct RingFlightTests {
    private func id(_ index: Int) -> AccountID {
        AccountID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-0000000000\(String(format: "%02d", index))") ?? UUID())
    }

    private func box(_ x: CGFloat, _ y: CGFloat, _ side: CGFloat) -> CGRect {
        CGRect(x: x, y: y, width: side, height: side)
    }

    private func pair(rail: CGRect = CGRect(x: 40, y: 10, width: 28, height: 28),
                      deck: CGRect = CGRect(x: 120, y: 200, width: 58, height: 58)) -> RingFlightPair {
        RingFlightPair(id: id(1), rail: rail, deck: deck)
    }

    // MARK: - Planner

    @Test("Only accounts measured on both sides fly, in the rail's order")
    func pairsKeepOrder() {
        let rail = [id(1): box(0, 0, 28), id(2): box(40, 0, 28), id(3): box(80, 0, 28)]
        let deck = [id(3): box(0, 100, 58), id(1): box(90, 100, 58)]
        let pairs = RingFlightPlanner.pairs(rail: rail, deck: deck, deckViewport: nil, order: [id(1), id(2), id(3)])
        #expect(pairs.map(\.id) == [id(1), id(3)])
        #expect(pairs.first?.rail == box(0, 0, 28))
        #expect(pairs.first?.deck == box(90, 100, 58))
    }

    @Test("A group filter that hides an account on the rail leaves it out")
    func filteredAccount() {
        let rail = [id(1): box(0, 0, 28)]
        let deck = [id(1): box(0, 100, 58), id(2): box(70, 100, 58)]
        let pairs = RingFlightPlanner.pairs(rail: rail, deck: deck, deckViewport: nil, order: [id(1)])
        #expect(pairs.map(\.id) == [id(1)])
    }

    @Test("An empty or missing box never flies")
    func emptyBoxes() {
        let rail = [id(1): CGRect(x: 0, y: 0, width: 0, height: 28), id(2): box(30, 0, 28)]
        let deck = [id(1): box(0, 100, 58)]
        let pairs = RingFlightPlanner.pairs(rail: rail, deck: deck, deckViewport: nil, order: [id(1), id(2)])
        #expect(pairs.isEmpty)
    }

    @Test("A deck dial scrolled out of the dial row's viewport does not fly")
    func clippedByViewport() {
        let viewport = CGRect(x: 0, y: 90, width: 200, height: 80)
        let rail = [id(1): box(0, 0, 28), id(2): box(40, 0, 28)]
        let deck = [id(1): box(10, 100, 58), id(2): box(180, 100, 58)]
        let pairs = RingFlightPlanner.pairs(rail: rail, deck: deck, deckViewport: viewport, order: [id(1), id(2)])
        #expect(pairs.map(\.id) == [id(1)])
    }

    @Test("At most eight rings fly")
    func capped() {
        var rail: [AccountID: CGRect] = [:]
        var deck: [AccountID: CGRect] = [:]
        var order: [AccountID] = []
        for index in 0..<12 {
            let account = id(index)
            rail[account] = box(CGFloat(index) * 30, 0, 28)
            deck[account] = box(CGFloat(index) * 60, 100, 58)
            order.append(account)
        }
        let pairs = RingFlightPlanner.pairs(rail: rail, deck: deck, deckViewport: nil, order: order)
        #expect(pairs.count == RingFlightPlanner.maximumPairs)
        #expect(pairs.map(\.id) == Array(order.prefix(8)))
    }

    // MARK: - Path

    @Test("The ends of the flight are exactly the two dials", arguments: ScreenEdge.allCases)
    func endpoints(edge: ScreenEdge) {
        let pair = pair()
        #expect(RingFlightPath.box(for: pair, progress: 0, edge: edge) == pair.rail)
        let landed = RingFlightPath.box(for: pair, progress: 1, edge: edge)
        #expect(abs(landed.midX - pair.deck.midX) < 0.001)
        #expect(abs(landed.midY - pair.deck.midY) < 0.001)
        #expect(abs(landed.width - pair.deck.width) < 0.001)
    }

    @Test("A spring's overshoot never pushes a ring past its dial")
    func clampsOvershoot() {
        let pair = pair()
        let overshoot = RingFlightPath.box(for: pair, progress: 1.03, edge: .top)
        let landed = RingFlightPath.box(for: pair, progress: 1, edge: .top)
        #expect(overshoot == landed)
        #expect(RingFlightPath.box(for: pair, progress: -0.2, edge: .top) == pair.rail)
        #expect(RingFlightPath.box(for: pair, progress: .nan, edge: .top) == pair.rail)
    }

    @Test("The diameter grows monotonically from the rail's to the deck's")
    func diameterMonotonic() {
        let pair = pair()
        var previous = RingFlightPath.box(for: pair, progress: 0, edge: .top).width
        for step in 1...100 {
            let width = RingFlightPath.box(for: pair, progress: CGFloat(step) / 100, edge: .top).width
            #expect(width >= previous - 0.0001)
            previous = width
        }
        #expect(previous > pair.rail.width)
    }

    @Test("The centre bows away from the screen edge", arguments: ScreenEdge.allCases)
    func controlPointDirection(edge: ScreenEdge) {
        let from = CGPoint(x: 100, y: 100)
        let to = CGPoint(x: 200, y: 300)
        let control = RingFlightPath.controlPoint(from: from, to: to, edge: edge)
        let midpoint = CGPoint(x: 150, y: 200)
        let away = RingFlightPath.outward(edge)
        let offset = CGVector(dx: control.x - midpoint.x, dy: control.y - midpoint.y)
        // The push is along the outward direction and nowhere else.
        #expect(offset.dx * away.dx + offset.dy * away.dy > 0)
        #expect(abs(offset.dx * away.dy - offset.dy * away.dx) < 0.0001)
        let travel = hypot(to.x - from.x, to.y - from.y)
        #expect(abs(hypot(offset.dx, offset.dy) - travel * RingFlightPath.bow) < 0.0001)
    }

    @Test("The flight is continuous: no jump between neighbouring samples")
    func continuous() {
        let pair = pair()
        var previous = RingFlightPath.box(for: pair, progress: 0, edge: .top)
        for step in 1...200 {
            let box = RingFlightPath.box(for: pair, progress: CGFloat(step) / 200, edge: .top)
            #expect(hypot(box.midX - previous.midX, box.midY - previous.midY) < 4)
            previous = box
        }
    }

    @Test("The crossfade runs once, sums to one and never exceeds it")
    func crossfade() {
        #expect(RingFlightPath.crossfade(0) == (rail: 1, deck: 0))
        #expect(RingFlightPath.crossfade(1) == (rail: 0, deck: 1))
        #expect(RingFlightPath.crossfade(0.2).rail == 1)
        #expect(RingFlightPath.crossfade(0.8).deck == 1)
        var previousDeck = 0.0
        for step in 0...100 {
            let fade = RingFlightPath.crossfade(CGFloat(step) / 100)
            #expect(fade.rail + fade.deck <= 1.0001)
            #expect(fade.deck >= previousDeck - 0.0001)
            previousDeck = fade.deck
        }
    }
}
