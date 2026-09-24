import CodometerCore
@testable import CodometerUI
import CoreGraphics
import Foundation
import Testing

/// Fusing the island with a MacBook's camera notch.
@Suite("Notch fusion")
struct NotchFusionTests {
    /// A notch on a display of `width` × `height` points: `notchWidth` wide, `top` deep.
    private func makeNotch(width: CGFloat = 1_512, height: CGFloat = 982, notchWidth: CGFloat = 197, top: CGFloat = 32) -> NotchGeometry? {
        let screen = CGRect(x: 0, y: 0, width: width, height: height)
        let aux = (width - notchWidth) / 2
        return NotchGeometry.make(
            screen: screen,
            safeTop: top,
            auxLeft: CGRect(x: 0, y: height - top, width: aux, height: top),
            auxRight: CGRect(x: aux + notchWidth, y: height - top, width: aux, height: top)
        )
    }

    // MARK: - isFused

    @Test("Fused only with fusion on, at the top, attached, centred and not dragging")
    func truthTable() throws {
        let notch = try #require(makeNotch())
        #expect(NotchFusion.isFused(mode: .automatic, edge: .top, style: .attached, offset: 0.5, notch: notch, dragging: false))
        #expect(!NotchFusion.isFused(mode: .off, edge: .top, style: .attached, offset: 0.5, notch: notch, dragging: false))
        #expect(!NotchFusion.isFused(mode: .automatic, edge: .bottom, style: .attached, offset: 0.5, notch: notch, dragging: false))
        #expect(!NotchFusion.isFused(mode: .automatic, edge: .top, style: .floating, offset: 0.5, notch: notch, dragging: false))
        #expect(!NotchFusion.isFused(mode: .automatic, edge: .top, style: .attached, offset: 0.5, notch: nil, dragging: false))
        #expect(!NotchFusion.isFused(mode: .automatic, edge: .top, style: .attached, offset: 0.5, notch: notch, dragging: true))
    }

    @Test("The offset has to be within 0.005 of the centre")
    func centreTolerance() throws {
        let notch = try #require(makeNotch())
        for offset in [0.5, 0.5 + NotchFusion.centerTolerance, 0.5 - NotchFusion.centerTolerance] {
            #expect(NotchFusion.isFused(mode: .automatic, edge: .top, style: .attached, offset: offset, notch: notch, dragging: false))
        }
        for offset in [0.49, 0.51, 0.0, 1.0, Double.nan] {
            #expect(!NotchFusion.isFused(mode: .automatic, edge: .top, style: .attached, offset: offset, notch: notch, dragging: false))
        }
    }

    // MARK: - Geometry detection (Core, used here)

    @Test("A 14-inch and a 16-inch MacBook Pro report their notch")
    func realGeometry() throws {
        let fourteen = try #require(makeNotch())
        #expect(abs(fourteen.rect.width - 197) < 0.001)
        #expect(fourteen.menuBarHeight == 32)
        #expect(abs(fourteen.leftAuxiliaryWidth - 657.5) < 0.001)

        let sixteen = try #require(makeNotch(width: 1_728, height: 1_117, notchWidth: 200, top: 38))
        #expect(sixteen.menuBarHeight == 38)
        #expect(abs(sixteen.rect.midX - 864) < 0.001)
    }

    @Test("Scaled (\"More Space\") resolutions still produce a notch")
    func scaled() throws {
        let scaled = try #require(makeNotch(width: 1_800, height: 1_169, notchWidth: 235, top: 38))
        #expect(abs(scaled.rect.width - 235) < 0.001)
    }

    @Test("Missing, inconsistent, too narrow or too wide auxiliary areas mean no notch")
    func rejects() {
        let screen = CGRect(x: 0, y: 0, width: 1_512, height: 982)
        #expect(NotchGeometry.make(screen: screen, safeTop: 32, auxLeft: nil, auxRight: nil) == nil)
        #expect(NotchGeometry.make(
            screen: screen,
            safeTop: 32,
            auxLeft: CGRect(x: 0, y: 950, width: 900, height: 32),
            auxRight: CGRect(x: 800, y: 950, width: 712, height: 32)
        ) == nil)
        #expect(makeNotch(notchWidth: 40) == nil)
        #expect(makeNotch(notchWidth: 1_000) == nil)
        #expect(NotchGeometry.make(
            screen: screen,
            safeTop: 0,
            auxLeft: CGRect(x: 0, y: 950, width: 657, height: 32),
            auxRight: CGRect(x: 855, y: 950, width: 657, height: 32)
        ) == nil)
    }

    // MARK: - Dial diameter

    @Test("A fused dial fits inside the menu bar")
    func dialDiameter() {
        // 32 pt menu bar, 4 pt orbit margin: 22 pt.
        #expect(NotchFusion.dialDiameter(railDial: 28, menuBarHeight: 32, orbitMargin: 4) == 22)
        // A deep menu bar never makes the dial larger than the rail's own.
        #expect(NotchFusion.dialDiameter(railDial: 28, menuBarHeight: 60, orbitMargin: 4) == 28)
        // A tiny menu bar still leaves a legible dial.
        #expect(NotchFusion.dialDiameter(railDial: 28, menuBarHeight: 12, orbitMargin: 4) == NotchFusion.minimumDialDiameter)
        #expect(NotchFusion.dialDiameter(railDial: 28, menuBarHeight: .nan, orbitMargin: 4) >= NotchFusion.minimumDialDiameter)
    }

    @Test("Wing capacity follows the narrower auxiliary area")
    func wingCapacity() throws {
        let notch = try #require(makeNotch())
        // 657.5 pt × 45 % = 295.9 pt; 60 pt per item leaves four.
        #expect(NotchFusion.maximumWingItems(notch: notch, itemWidth: 60) == 4)
        #expect(NotchFusion.maximumWingItems(notch: notch, itemWidth: 0) == 0)
        #expect(NotchFusion.maximumWingItems(notch: notch, itemWidth: 1_000) == 0)
    }

    // MARK: - Wings

    @Test("Accounts split with the first half on the left, in order", arguments: 1...16)
    func wingsSplit(count: Int) {
        let wings = NotchFusion.wings(accountCount: count, hasAttention: false, maximumWingItems: 8)
        let shown = wings.left.count + wings.right.count
        #expect(shown + wings.overflow == count)
        #expect(wings.left.lowerBound == 0)
        #expect(wings.right.lowerBound == wings.left.upperBound)
        // The left wing is never smaller than the right one, and never larger by more than one.
        #expect(wings.left.count >= wings.right.count)
        #expect(wings.left.count - wings.right.count <= 1)
    }

    @Test("The attention tab takes one slot of the right wing")
    func attentionTab() {
        let without = NotchFusion.wings(accountCount: 6, hasAttention: false, maximumWingItems: 3)
        #expect(without.left.count == 3 && without.right.count == 3 && without.overflow == 0)
        let with = NotchFusion.wings(accountCount: 6, hasAttention: true, maximumWingItems: 3)
        #expect(with.hasAttention)
        // Two account slots on the right, and the chip takes the left wing's last one.
        #expect(with.right.count == 2)
        #expect(with.left.count == 2)
        #expect(with.overflow == 2)
        #expect(with.showsOverflowChip)
    }

    @Test("Everything that does not fit is counted in the chip")
    func overflow() {
        let wings = NotchFusion.wings(accountCount: 12, hasAttention: false, maximumWingItems: 3)
        #expect(wings.left.count == 2)
        #expect(wings.right.count == 3)
        #expect(wings.overflow == 7)
        #expect(wings.left.upperBound == 2 && wings.right == 2..<5)
    }

    @Test("Nothing to show is an empty, chipless split")
    func empty() {
        let wings = NotchFusion.wings(accountCount: 0, hasAttention: false, maximumWingItems: 4)
        #expect(wings.left.isEmpty && wings.right.isEmpty)
        #expect(!wings.showsOverflowChip)
        let noRoom = NotchFusion.wings(accountCount: 3, hasAttention: false, maximumWingItems: 0)
        #expect(noRoom.left.isEmpty && noRoom.right.isEmpty)
        #expect(noRoom.overflow == 3)
    }

    @Test("The attention tab moves to the left wing rather than make the right one draw \"no accounts\"")
    func attentionTabWing() {
        // The everyday single-account case: one dial left of the notch, nothing right of it.
        let single = NotchFusion.wingContents(leftCount: 1, rightCount: 0)
        #expect(single.showsTabOnLeft)
        #expect(!single.showsTabOnRight)
        #expect(!single.showsPlaceholder)

        // Both wings filled: the tab ends the right one, as the design says.
        let both = NotchFusion.wingContents(leftCount: 2, rightCount: 1)
        #expect(!both.showsTabOnLeft)
        #expect(both.showsTabOnRight)
        #expect(!both.showsPlaceholder)

        // No account on either side (a group filter hid them all): the rail reads like an unfused empty one.
        let none = NotchFusion.wingContents(leftCount: 0, rightCount: 0)
        #expect(!none.showsTabOnLeft)
        #expect(none.showsTabOnRight)
        #expect(none.showsPlaceholder)

        // The tab is never offered to both wings at once.
        for left in 0...4 {
            for right in 0...4 {
                let contents = NotchFusion.wingContents(leftCount: left, rightCount: right)
                #expect(!(contents.showsTabOnLeft && contents.showsTabOnRight), "left \(left), right \(right)")
                #expect(contents.showsPlaceholder == (left == 0 && right == 0), "left \(left), right \(right)")
            }
        }
    }
}
