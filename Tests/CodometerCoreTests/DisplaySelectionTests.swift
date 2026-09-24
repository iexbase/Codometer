import CodometerCore
import CoreGraphics
import Foundation
import Testing

@Suite("Display selection")
struct DisplaySelectionTests {
    private let remembered = RememberedDisplay(id: Displays.id(Displays.leftID), name: "LG UltraFine")

    @Test("whereLeft: the remembered display while connected, else main; nothing without displays")
    func whereLeft() {
        #expect(DisplaySelection.resolve(policy: .whereLeft, remembered: nil, displays: Displays.all)?.id == Displays.builtIn.id)
        #expect(DisplaySelection.resolve(policy: .whereLeft, remembered: remembered, displays: Displays.all)?.id == Displays.left.id)
        #expect(DisplaySelection.resolve(policy: .whereLeft, remembered: remembered, displays: [Displays.builtIn, Displays.above])?.id == Displays.builtIn.id)
        #expect(DisplaySelection.resolve(policy: .whereLeft, remembered: remembered, displays: []) == nil)
    }

    @Test("main: always the display with the menu bar, else the first")
    func main() {
        #expect(DisplaySelection.resolve(policy: .main, remembered: remembered, displays: Displays.all)?.id == Displays.builtIn.id)
        #expect(DisplaySelection.resolve(policy: .main, remembered: nil, displays: [Displays.left, Displays.above])?.id == Displays.left.id)
    }

    @Test("display(id): that display while connected, else re-adopted by name, else main")
    func specific() throws {
        let policy = DisplayPolicy.display(Displays.id(Displays.leftID))
        #expect(DisplaySelection.resolve(policy: policy, remembered: nil, displays: Displays.all)?.id == Displays.left.id)
        #expect(DisplaySelection.resolve(policy: policy, remembered: nil, displays: [Displays.builtIn])?.id == Displays.builtIn.id)
        // The dock reported a new UUID for the same monitor.
        let renumbered = Displays.display("99999999-2222-3333-4444-555555555555", name: "LG UltraFine", frame: Displays.left.frame)
        #expect(DisplaySelection.resolve(policy: policy, remembered: remembered, displays: [Displays.builtIn, renumbered])?.id == renumbered.id)
        let other = RememberedDisplay(id: Displays.id(Displays.aboveID), name: "LG UltraFine")
        #expect(DisplaySelection.resolve(policy: policy, remembered: other, displays: [Displays.builtIn, renumbered])?.id == Displays.builtIn.id)
    }

    @Test("Adoption needs a unique name match")
    func adopt() {
        let twin = Displays.display("99999999-2222-3333-4444-555555555555", name: "LG UltraFine", frame: .zero)
        let twin2 = Displays.display("88888888-2222-3333-4444-555555555555", name: "LG UltraFine", frame: .zero)
        #expect(DisplaySelection.adopt(remembered, displays: Displays.all)?.id == Displays.left.id)
        #expect(DisplaySelection.adopt(remembered, displays: [Displays.builtIn, twin])?.id == twin.id)
        #expect(DisplaySelection.adopt(remembered, displays: [Displays.builtIn, twin, twin2]) == nil)
        #expect(DisplaySelection.adopt(RememberedDisplay(id: remembered.id, name: nil), displays: [Displays.builtIn, twin]) == nil)
        #expect(DisplaySelection.resolve(policy: .whereLeft, remembered: remembered, displays: [Displays.builtIn, twin])?.id == twin.id)
    }

    @Test("The display under a point: inside, negative origins, stacked, and the nearest from a gap", arguments: [
        (CGPoint(x: 100, y: 100), Displays.mainID),
        (CGPoint(x: -1000, y: 500), Displays.leftID),
        (CGPoint(x: 700, y: 1500), Displays.aboveID),
        (CGPoint(x: 700, y: 3000), Displays.aboveID),
        (CGPoint(x: 1600, y: 100), Displays.mainID),
        (CGPoint(x: -3000, y: -900), Displays.leftID),
        (CGPoint(x: 1500, y: 990), Displays.aboveID),
    ])
    func displayAtPoint(point: CGPoint, expected: String) {
        #expect(DisplaySelection.display(at: point, in: Displays.all)?.id.rawValue == expected)
    }

    @Test("No displays, or a non-finite point, never crash")
    func displayAtEdgeCases() {
        #expect(DisplaySelection.display(at: .zero, in: []) == nil)
        #expect(DisplaySelection.display(at: CGPoint(x: CGFloat.nan, y: 0), in: Displays.all)?.id == Displays.builtIn.id)
    }

    @Test("Drops: whereLeft allows any connected display; main and display(id) only their own")
    func allowsDrop() {
        let disconnected = Displays.display("12345678-2222-3333-4444-555555555555", name: "Gone", frame: .zero)
        #expect(Displays.all.allSatisfy { DisplaySelection.allowsDrop(on: $0, policy: .whereLeft, displays: Displays.all) })
        #expect(!DisplaySelection.allowsDrop(on: disconnected, policy: .whereLeft, displays: Displays.all))
        #expect(DisplaySelection.allowsDrop(on: Displays.builtIn, policy: .main, displays: Displays.all))
        #expect(!DisplaySelection.allowsDrop(on: Displays.left, policy: .main, displays: Displays.all))
        let policy = DisplayPolicy.display(Displays.id(Displays.leftID))
        #expect(DisplaySelection.allowsDrop(on: Displays.left, policy: policy, displays: Displays.all))
        #expect(!DisplaySelection.allowsDrop(on: Displays.builtIn, policy: policy, displays: Displays.all))
        // While the chosen display is disconnected, the main display stands in for it.
        #expect(DisplaySelection.allowsDrop(on: Displays.builtIn, policy: policy, displays: [Displays.builtIn, Displays.above]))
        #expect(!DisplaySelection.allowsDrop(on: Displays.above, policy: policy, displays: [Displays.builtIn, Displays.above]))
    }

    @Test("The union spans every display; empty is zero")
    func union() {
        #expect(DisplaySelection.union(of: Displays.all) == CGRect(x: -2560, y: -200, width: 4072, height: 2082))
        #expect(DisplaySelection.union(of: [Displays.builtIn]) == Displays.builtIn.frame)
        #expect(DisplaySelection.union(of: []) == .zero)
    }

    @Test("Descriptors sanitise names and fall back to a generic one")
    func descriptorNames() {
        #expect(Displays.display(Displays.mainID, name: "\u{1}", frame: .zero).name.isEmpty)
        #expect(Displays.display(Displays.mainID, name: "\u{1}", frame: .zero).remembered.name == nil)
        #expect(Displays.display(Displays.mainID, name: String(repeating: "n", count: 80), frame: .zero).name.count == 64)
        #expect(Displays.builtIn.remembered == RememberedDisplay(id: Displays.builtIn.id, name: "Built-in Retina Display"))
    }
}
