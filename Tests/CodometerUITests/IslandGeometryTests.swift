import CodometerCore
import CodometerL10n
@testable import CodometerUI
import AppKit
import CoreGraphics
import CoreText
import Foundation
import SwiftUI
import Testing

/// A 1512×982 screen with a 32 pt menu bar and a 38 pt Dock.
private let screen = CGRect(x: 0, y: 0, width: 1_512, height: 982)
private let area = CGRect(x: 0, y: 38, width: 1_512, height: 912)
private let railH = CGSize(width: 180, height: 44)
private let railV = CGSize(width: 44, height: 150)
private let deck = CGSize(width: 404, height: 520)

@Suite("Island geometry")
struct IslandGeometryTests {
    @Test("Top and bottom rails are centred at offset 0.5 and keep the floating gap")
    func horizontalRails() {
        let top = IslandGeometry.railFrame(size: railH, edge: .top, offset: 0.5, style: .floating, in: area)
        #expect(top.maxY == area.maxY - IslandGeometry.floatingGap)
        #expect(abs(top.midX - area.midX) <= 1)
        let bottom = IslandGeometry.railFrame(size: railH, edge: .bottom, offset: 0, style: .attached, in: area)
        #expect(bottom.minY == area.minY)
        #expect(bottom.minX == area.minX)
    }

    @Test("Side rails run from the top (0) to the bottom (1)")
    func verticalRails() {
        let high = IslandGeometry.railFrame(size: railV, edge: .right, offset: 0, style: .floating, in: area)
        #expect(high.maxX == area.maxX - IslandGeometry.floatingGap)
        #expect(high.maxY == area.maxY - IslandGeometry.floatingGap)
        let low = IslandGeometry.railFrame(size: railV, edge: .left, offset: 1, style: .floating, in: area)
        #expect(low.minX == area.minX + IslandGeometry.floatingGap)
        #expect(low.minY == area.minY + IslandGeometry.floatingGap)
    }

    @Test("The island grows away from the edge: centred in the middle third, away from the nearer corner outside it", arguments: [
        (ScreenEdge.top, 0.1, IslandAnchor.topLeading),
        (.top, 0.5, .top),
        (.top, 0.9, .topTrailing),
        (.bottom, 0.2, .bottomLeading),
        (.bottom, 0.5, .bottom),
        (.bottom, 0.8, .bottomTrailing),
        (.left, 0.2, .topLeading),
        (.left, 0.5, .leading),
        (.left, 0.9, .bottomLeading),
        (.right, 0.1, .topTrailing),
        (.right, 0.5, .trailing),
        (.right, 0.8, .bottomTrailing),
        (.right, 1.0 / 3, .trailing),
        (.right, 2.0 / 3, .trailing),
    ])
    func anchors(edge: ScreenEdge, offset: Double, expected: IslandAnchor) {
        #expect(IslandGeometry.anchor(edge: edge, offset: offset) == expected)
    }

    @Test("Expanding keeps the anchored corner of the rail in place")
    func expansionKeepsCorner() {
        let rail = IslandGeometry.railFrame(size: railV, edge: .right, offset: 0.2, style: .floating, in: area)
        let frame = IslandGeometry.expandedFrame(rail: rail, size: deck, anchor: .topTrailing, in: area)
        #expect(frame.maxX == rail.maxX)
        #expect(frame.maxY == rail.maxY)
        #expect(frame.size == deck)

        let topRail = IslandGeometry.railFrame(size: railH, edge: .top, offset: 0.5, style: .floating, in: area)
        let topFrame = IslandGeometry.expandedFrame(rail: topRail, size: deck, anchor: .top, in: area)
        #expect(abs(topFrame.midX - topRail.midX) <= 1)
        #expect(topFrame.maxY == topRail.maxY)
    }

    @Test("A right-edge island at the centre grows out of the edge, vertically centred on the rail")
    func rightCentreExpandsCentred() {
        let attached = IslandGeometry.area(edge: .right, style: .attached, screen: screen, visible: area)
        let frames = IslandGeometry.frames(sizes: IslandSizes(rail: railV, deck: deck), edge: .right, offset: 0.5, style: .attached, in: attached)
        #expect(frames.deck.maxX == screen.maxX)
        #expect(frames.deck.maxX == frames.rail.maxX)
        #expect(abs(frames.deck.midY - frames.rail.midY) <= 1)
        #expect(frames.deck.size == deck)
        #expect(attached.contains(frames.deck))
    }

    @Test("Near the top of a side edge the deck grows downwards from the rail's top")
    func nearTopExpandsDown() {
        let rail = IslandGeometry.railFrame(size: railV, edge: .right, offset: 0.1, style: .attached, in: area)
        let anchor = IslandGeometry.anchor(edge: .right, offset: 0.1)
        let frame = IslandGeometry.expandedFrame(rail: rail, size: deck, anchor: anchor, in: area)
        #expect(frame.maxY == rail.maxY)
        #expect(frame.minY < rail.minY)
    }

    @Test("Near the bottom of a side edge the deck grows upwards from the rail's bottom")
    func nearBottomExpandsUp() {
        let rail = IslandGeometry.railFrame(size: railV, edge: .right, offset: 0.9, style: .attached, in: area)
        let anchor = IslandGeometry.anchor(edge: .right, offset: 0.9)
        let frame = IslandGeometry.expandedFrame(rail: rail, size: deck, anchor: anchor, in: area)
        #expect(frame.minY == rail.minY)
        #expect(frame.maxY > rail.maxY)
    }

    @Test("The left edge mirrors the right edge")
    func leftMirrorsRight() {
        let sizes = IslandSizes(rail: railV, deck: deck)
        for offset in [0.1, 0.5, 0.9] {
            let right = IslandGeometry.frames(sizes: sizes, edge: .right, offset: offset, style: .attached, in: area)
            let left = IslandGeometry.frames(sizes: sizes, edge: .left, offset: offset, style: .attached, in: area)
            #expect(left.deck.minX == area.minX)
            #expect(left.deck.minX == left.rail.minX)
            #expect(left.deck.minY == right.deck.minY)
            #expect(left.deck.size == right.deck.size)
            #expect(area.maxX - right.deck.maxX == left.deck.minX - area.minX)
        }
    }

    @Test("An expansion that would leave the screen is pushed back inside", arguments: [0.0, 0.25, 0.5, 0.75, 1.0])
    func expansionClamped(offset: Double) {
        let tall = CGSize(width: 404, height: 700)
        for edge in [ScreenEdge.left, .right] {
            let rail = IslandGeometry.railFrame(size: railV, edge: edge, offset: offset, style: .floating, in: area)
            let frame = IslandGeometry.expandedFrame(rail: rail, size: tall, anchor: IslandGeometry.anchor(edge: edge, offset: offset), in: area)
            #expect(area.contains(frame))
            #expect(frame.contains(rail))
        }
        let rail = IslandGeometry.railFrame(size: railH, edge: .top, offset: offset, style: .attached, in: area)
        let frame = IslandGeometry.expandedFrame(rail: rail, size: tall, anchor: IslandGeometry.anchor(edge: .top, offset: offset), in: area)
        #expect(area.contains(frame))
        #expect(frame.maxY == rail.maxY)
    }

    @Test("The deck is never smaller than the rail")
    func deckAtLeastRail() {
        let rail = IslandGeometry.railFrame(size: CGSize(width: 60, height: 600), edge: .right, offset: 0.5, style: .attached, in: area)
        let frame = IslandGeometry.expandedFrame(rail: rail, size: CGSize(width: 404, height: 300), anchor: .trailing, in: area)
        #expect(frame.height == 600)
        #expect(frame.contains(rail))
    }

    @Test("The deck may be as tall as its area, less the floating gaps")
    func maximumDeckHeight() {
        #expect(IslandGeometry.maximumDeckHeight(style: .attached, in: area) == 912)
        #expect(IslandGeometry.maximumDeckHeight(style: .floating, in: area) == 896)
        let tallDeck = CGSize(width: 404, height: IslandGeometry.maximumDeckHeight(style: .floating, in: area))
        for offset in [0.0, 0.5, 1.0] {
            let rail = IslandGeometry.railFrame(size: railV, edge: .right, offset: offset, style: .floating, in: area)
            let frame = IslandGeometry.expandedFrame(rail: rail, size: tallDeck, anchor: IslandGeometry.anchor(edge: .right, offset: offset), in: area)
            #expect(area.contains(frame))
        }
    }

    @Test("Dragging snaps to the nearest edge with the island centred on the pointer")
    func dragPlacement() {
        let nearRight = IslandGeometry.placement(for: CGPoint(x: 1_500, y: 500), railSize: railH, style: .floating, screen: screen, visible: area)
        #expect(nearRight.edge == .right)
        let nearTop = IslandGeometry.placement(for: CGPoint(x: area.midX, y: 960), railSize: railH, style: .floating, screen: screen, visible: area)
        #expect(nearTop.edge == .top)
        #expect(abs(nearTop.offset - 0.5) < 0.01)
        let corner = IslandGeometry.placement(for: CGPoint(x: -50, y: 2_000), railSize: railV, style: .floating, screen: screen, visible: area)
        #expect((0...1).contains(corner.offset))
    }

    @Test("Placement from a drag reproduces the dragged position")
    func placementRoundTrip() {
        let pointer = CGPoint(x: 400, y: 960)
        let placement = IslandGeometry.placement(for: pointer, railSize: railH, style: .attached, screen: screen, visible: area)
        let attachedArea = IslandGeometry.area(edge: placement.edge, style: .attached, screen: screen, visible: area)
        let rail = IslandGeometry.railFrame(size: railH, edge: placement.edge, offset: placement.offset, style: .attached, in: attachedArea)
        #expect(placement.edge == .top)
        #expect(abs(rail.midX - pointer.x) <= 1)
    }

    @Test("An attached island at the top hangs from the physical screen edge, over the menu bar")
    func attachedArea() {
        let top = IslandGeometry.area(edge: .top, style: .attached, screen: screen, visible: area)
        let rail = IslandGeometry.railFrame(size: railH, edge: .top, offset: 0.5, style: .attached, in: top)
        #expect(rail.maxY == screen.maxY)
        let side = IslandGeometry.area(edge: .right, style: .attached, screen: screen, visible: area)
        let sideRail = IslandGeometry.railFrame(size: railV, edge: .right, offset: 0, style: .attached, in: side)
        #expect(sideRail.maxX == screen.maxX)
        #expect(sideRail.maxY <= area.maxY)
        #expect(IslandGeometry.area(edge: .top, style: .floating, screen: screen, visible: area) == area)
    }
}

@Suite("Island panel and canvas")
struct IslandPanelGeometryTests {
    private let rail = CGRect(x: 666, y: 938, width: 180, height: 44)
    private let deckRect = CGRect(x: 554, y: 462, width: 404, height: 520)

    @Test("An attached island's panel has transparent margins on the free sides only", arguments: ScreenEdge.allCases)
    func attachedMargins(edge: ScreenEdge) {
        let island = CGRect(x: 600, y: 300, width: 200, height: 100)
        let frame = IslandGeometry.panelFrame(containing: [island], edge: edge, attached: true, margin: 20, within: screen)
        #expect(frame.maxY - island.maxY == (edge == .top ? 0 : 20))
        #expect(island.minY - frame.minY == (edge == .bottom ? 0 : 20))
        #expect(island.minX - frame.minX == (edge == .left ? 0 : 20))
        #expect(frame.maxX - island.maxX == (edge == .right ? 0 : 20))
    }

    @Test("A floating island's panel has margins on every side, and the panel never leaves the screen")
    func floatingMarginsAndClamping() {
        let island = CGRect(x: 600, y: 300, width: 200, height: 100)
        let floating = IslandGeometry.panelFrame(containing: [island], edge: .right, attached: false, margin: 20, within: screen)
        #expect(floating == island.insetBy(dx: -20, dy: -20))
        let nearEdge = CGRect(x: 1_460, y: 900, width: 44, height: 74)
        let clamped = IslandGeometry.panelFrame(containing: [nearEdge], edge: .right, attached: false, margin: 20, within: screen)
        #expect(screen.contains(clamped))
        #expect(clamped.contains(nearEdge))
    }

    @Test("The expanded panel covers rail and deck; the collapsed one only the rail")
    func panelCoversStates() {
        let collapsed = IslandGeometry.panelFrame(containing: [rail], edge: .top, attached: true, margin: 20, within: screen)
        let expanded = IslandGeometry.panelFrame(containing: [rail, deckRect], edge: .top, attached: true, margin: 20, within: screen)
        #expect(expanded.contains(rail))
        #expect(expanded.contains(deckRect))
        #expect(!collapsed.contains(deckRect))
        #expect(expanded.maxY == screen.maxY)
    }

    @Test("Screen and canvas coordinates convert both ways")
    func canvasConversion() {
        let canvas = CGRect(x: 0, y: 0, width: 1_512, height: 982)
        let local = IslandGeometry.local(rail, in: canvas)
        #expect(local == CGRect(x: 666, y: 0, width: 180, height: 44))
        #expect(IslandGeometry.screen(local, in: canvas) == rail)

        let shifted = canvas.offsetBy(dx: -120, dy: 35)
        #expect(IslandGeometry.screen(IslandGeometry.local(deckRect, in: shifted), in: shifted) == deckRect)
    }

    @Test("The interactive rect follows the view's flipping")
    func hitRect() {
        let local = CGRect(x: 10, y: 20, width: 100, height: 40)
        #expect(IslandGeometry.viewRect(local, boundsHeight: 500, isFlipped: true) == local)
        let unflipped = IslandGeometry.viewRect(local, boundsHeight: 500, isFlipped: false)
        #expect(unflipped == CGRect(x: 10, y: 440, width: 100, height: 40))
        #expect(unflipped.contains(CGPoint(x: 50, y: 460)))
        #expect(!unflipped.contains(CGPoint(x: 50, y: 30)))
    }

    @Test("Rects centre on a point on whole points")
    func centred() {
        let rect = IslandGeometry.rect(centeredAt: CGPoint(x: 100.4, y: 50), size: CGSize(width: 45, height: 30))
        #expect(rect.size == CGSize(width: 45, height: 30))
        #expect(rect.minX == rect.minX.rounded())
        #expect(abs(rect.midX - 100.4) <= 1)
    }
}

@Suite("Island morph layout")
struct IslandMorphLayoutTests {
    @Test("A stage is the union of both frames, with each state at its place inside it")
    func fromFrames() {
        let frames = IslandFrames(rail: CGRect(x: 2499, y: 235, width: 61, height: 180), deck: CGRect(x: 2156, y: 0, width: 404, height: 651))
        let stage = IslandMorphLayout(frames: frames)
        #expect(stage.size == CGSize(width: 404, height: 651))
        #expect(stage.deck == CGRect(x: 0, y: 0, width: 404, height: 651))
        #expect(stage.rail == CGRect(x: 343, y: 235, width: 61, height: 180))
        #expect(stage.frame(expanded: false) == stage.rail)
        #expect(frames.union == CGRect(x: 2156, y: 0, width: 404, height: 651))
    }

    @Test("Without window geometry both states share the anchor", arguments: [
        (IslandAnchor.trailing, CGPoint(x: 343, y: 236)),
        (.top, CGPoint(x: 172, y: 0)),
        (.bottomLeading, CGPoint(x: 0, y: 471)),
    ])
    func anchored(anchor: IslandAnchor, railOrigin: CGPoint) {
        let stage = IslandMorphLayout.anchored(rail: CGSize(width: 61, height: 180), deck: CGSize(width: 404, height: 651), anchor: anchor)
        #expect(stage.size == CGSize(width: 404, height: 651))
        #expect(stage.deck.origin == .zero)
        #expect(stage.rail.origin == railOrigin)
    }
}

@Suite("Island deck height")
struct IslandDeckHeightTests {
    @Test("Only a deck taller than its room is capped (and scrolls); unknown or invalid room never caps it")
    func deckCap() {
        #expect(IslandRootView.deckHeightCap(natural: 1_200, maximum: 912) == 912)
        #expect(IslandRootView.deckHeightCap(natural: 912, maximum: 912) == .infinity)
        #expect(IslandRootView.deckHeightCap(natural: 520, maximum: 912) == .infinity)
        #expect(IslandRootView.deckHeightCap(natural: 1_200, maximum: nil) == .infinity)
        #expect(IslandRootView.deckHeightCap(natural: 1_200, maximum: 0) == .infinity)
        #expect(IslandRootView.deckHeightCap(natural: 1_200, maximum: -4) == .infinity)
        #expect(IslandRootView.deckHeightCap(natural: 1_200, maximum: .nan) == .infinity)
    }

    @Test("The island is placed with the deck clamped to its room; the rail and a fitting deck are untouched")
    func placedSizes() {
        let measured = IslandSizes(rail: railV, deck: CGSize(width: 412, height: 1_100))
        let capped = IslandRootView.islandSizes(measured: measured, maximumDeckHeight: 912)
        #expect(capped == IslandSizes(rail: railV, deck: CGSize(width: 412, height: 912)))
        #expect(IslandRootView.islandSizes(measured: measured, maximumDeckHeight: 1_400) == measured)
        #expect(IslandRootView.islandSizes(measured: measured, maximumDeckHeight: nil) == measured)
    }

    @Test("A deck capped to the placement's room always fits its area, whatever the anchor", arguments: [0.1, 0.5, 0.9])
    func cappedDeckFits(offset: Double) {
        for style in [IslandStyle.attached, .floating] {
            for edge in ScreenEdge.allCases {
                let room = IslandGeometry.area(edge: edge, style: style, screen: screen, visible: area)
                let maximum = IslandGeometry.maximumDeckHeight(style: style, in: room)
                let rail = edge.isHorizontal ? railH : railV
                let frames = IslandGeometry.frames(
                    sizes: IslandSizes(rail: rail, deck: CGSize(width: deck.width, height: maximum)),
                    edge: edge,
                    offset: offset,
                    style: style,
                    in: room
                )
                #expect(room.contains(frames.deck), "\(edge) \(style)")
                #expect(frames.deck.contains(frames.rail), "\(edge) \(style)")
            }
        }
    }
}

@Suite("Island silhouette")
struct IslandSilhouetteTests {
    @Test("Attached outlines bleed past the edge and stay inside the free sides", arguments: ScreenEdge.allCases)
    func attachedBounds(edge: ScreenEdge) {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 60)
        let shape = IslandSilhouette(edge: edge, style: .attached, cornerRadius: 16, shoulder: 12)
        let bounds = shape.path(in: rect).boundingRect
        switch edge {
        case .top:
            #expect(bounds.minY < rect.minY)
            #expect(abs(bounds.maxY - rect.maxY) < 0.5)
        case .bottom:
            #expect(bounds.maxY > rect.maxY)
            #expect(abs(bounds.minY - rect.minY) < 0.5)
        case .left:
            #expect(bounds.minX < rect.minX)
            #expect(abs(bounds.maxX - rect.maxX) < 0.5)
        case .right:
            #expect(bounds.maxX > rect.maxX)
            #expect(abs(bounds.minX - rect.minX) < 0.5)
        }
    }

    @Test("The rim outline never runs along the screen edge", arguments: ScreenEdge.allCases)
    func outlineStaysInside(edge: ScreenEdge) {
        let rect = CGRect(x: 0, y: 0, width: 220, height: 90)
        let outline = IslandSilhouette(edge: edge, style: .attached, cornerRadius: 20, shoulder: 12).outline
        #expect(rect.insetBy(dx: -0.5, dy: -0.5).contains(outline.path(in: rect).boundingRect))
    }

    @Test("A right-edge tab meets the bezel through concave shoulders at its top and bottom")
    func sideShoulders() {
        let rect = CGRect(x: 0, y: 0, width: 60, height: 200)
        let path = IslandSilhouette(edge: .right, style: .attached, cornerRadius: 16, shoulder: 12).path(in: rect)
        // Flush with the bezel along its whole length…
        #expect(path.contains(CGPoint(x: rect.maxX - 0.3, y: rect.minY + 7)))
        #expect(path.contains(CGPoint(x: rect.maxX - 0.3, y: rect.maxY - 7)))
        // …and curving in towards the island's side a little away from it.
        #expect(!path.contains(CGPoint(x: rect.maxX - 9.6, y: rect.minY + 6)))
        #expect(!path.contains(CGPoint(x: rect.maxX - 9.6, y: rect.maxY - 6)))
        #expect(path.contains(CGPoint(x: rect.maxX - 9.6, y: rect.midY)))
    }

    @Test("Corner radius, shoulder and the island's frame inside its stage animate together")
    func animatable() {
        var shape = IslandSilhouette(edge: .right, style: .attached, cornerRadius: 16, shoulder: 12, islandFrame: CGRect(x: 343, y: 235, width: 61, height: 180))
        let deck = CGRect(x: 0, y: 0, width: 404, height: 651)
        shape.animatableData = AnimatablePair(AnimatablePair(28, 14), deck.animatableData)
        #expect(shape.cornerRadius == 28)
        #expect(shape.shoulder == 14)
        #expect(shape.islandFrame == deck)

        var filling = IslandSilhouette(edge: .top, style: .attached, cornerRadius: 16, shoulder: 12)
        filling.animatableData = AnimatablePair(AnimatablePair(10, 8), deck.animatableData)
        #expect(filling.islandFrame == nil)
        var outline = shape.outline
        outline.animatableData = AnimatablePair(AnimatablePair(10, 8), CGRect.zero.animatableData)
        #expect(outline.silhouette.cornerRadius == 10)
    }

    @Test("A silhouette with a frame draws only inside that frame of its bounds")
    func framedPath() {
        let stage = CGRect(x: 0, y: 0, width: 404, height: 651)
        let rail = CGRect(x: 343, y: 235, width: 61, height: 180)
        let shape = IslandSilhouette(edge: .right, style: .attached, cornerRadius: 16, shoulder: 12, islandFrame: rail)
        let bounds = shape.path(in: stage).boundingRect
        #expect(abs(bounds.minX - rail.minX) < 0.5)
        #expect(abs(bounds.minY - rail.minY) < 0.5)
        #expect(abs(bounds.maxY - rail.maxY) < 0.5)
        #expect(bounds.maxX > rail.maxX)
        #expect(shape.path(in: stage) == shape.filling.path(in: rail))
        #expect(shape.outline.path(in: stage).boundingRect.maxX <= rail.maxX + 0.5)
    }

    @Test("Floating outlines stay within their bounds")
    func floatingBounds() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 60)
        let bounds = IslandSilhouette(edge: .top, style: .floating, cornerRadius: 999, shoulder: 0).path(in: rect).boundingRect
        #expect(rect.insetBy(dx: -0.5, dy: -0.5).contains(bounds))
    }
}

@Suite("Urgency glass")
struct IslandGlassTests {
    @Test("Nothing glows when the setting is off")
    func disabled() {
        #expect(IslandGlass(glowsWithUrgency: false, urgency: .exhausted, waiting: true) == .calm)
    }

    @Test("Ample usage without waiting agents keeps the glass calm")
    func calm() {
        #expect(IslandGlass(glowsWithUrgency: true, urgency: .ample, waiting: false) == .calm)
        #expect(IslandGlass(glowsWithUrgency: true, urgency: nil, waiting: false) == .calm)
    }

    @Test("Tint follows the worst band and the rim prefers the attention colour", arguments: UsageBand.allCases)
    func bands(band: UsageBand) {
        let glass = IslandGlass(glowsWithUrgency: true, urgency: band, waiting: false)
        #expect(glass.tint == Theme.glassTint(for: band))
        #expect(glass.rim == Theme.rim(for: band, waiting: false))
        let waiting = IslandGlass(glowsWithUrgency: true, urgency: band, waiting: true)
        #expect(waiting.rim == Theme.rim(for: band, waiting: true))
        #expect(waiting.rim != nil)
    }

    @Test("The rim is brightest at the screen edge, where the shoulders are", arguments: ScreenEdge.allCases)
    func rimAxis(edge: ScreenEdge) {
        let axis = IslandGlass.rimAxis(edge: edge)
        let expected: UnitPoint = switch edge {
        case .top: .top
        case .bottom: .bottom
        case .left: .leading
        case .right: .trailing
        }
        #expect(axis.start == expected)
        #expect(axis.end != axis.start)
        #expect(IslandGlass.rimStops.first?.opacity == IslandGlass.rimStops.map(\.opacity).max())
    }

    @Test("Inside a stage the rim axis is aimed at the island's own rect")
    func stagedRimAxis() {
        let stage = CGSize(width: 400, height: 600)
        let rail = CGRect(x: 340, y: 210, width: 60, height: 180)
        let right = IslandGlass.rimAxis(edge: .right, island: rail, in: stage)
        #expect(right.start == UnitPoint(x: 1, y: 0.5))
        #expect(right.end == UnitPoint(x: 0.85, y: 0.5))
        let top = IslandGlass.rimAxis(edge: .top, island: CGRect(x: 100, y: 0, width: 200, height: 60), in: stage)
        #expect(top.start == UnitPoint(x: 0.5, y: 0))
        #expect(top.end == UnitPoint(x: 0.5, y: 0.1))
        #expect(IslandGlass.rimAxis(edge: .left, island: nil, in: stage) == (UnitPoint.leading, UnitPoint.trailing))
    }

    @Test("The system glass gets the faintest extra highlight")
    func highlight() {
        #expect(IslandGlass.highlightOpacity(for: .glass) < IslandGlass.highlightOpacity(for: .darkGlass))
        #expect(IslandGlass.highlightOpacity(for: .glass) < IslandGlass.highlightOpacity(for: .solid))
    }
}

@Suite("Island interaction")
struct IslandInteractionTests {
    typealias State = IslandInteractionState

    @Test("Hover: intent opens, leaving starts the grace period, grace closes")
    func hoverCycle() {
        var state = State(trigger: .hover)
        #expect(state.handle(.hoverEnter) == [.cancelGrace, .prepare, .startIntent])
        #expect(state.phase == .collapsed)
        #expect(state.handle(.intentElapsed) == [.expand])
        #expect(state.phase == .expanded(pinned: false))
        #expect(!state.wantsOutsideClickMonitor)
        #expect(state.handle(.hoverExit) == [.cancelIntent, .startGrace])
        #expect(state.handle(.graceElapsed) == [.collapse])
        #expect(state.phase == .collapsed)
    }

    @Test("Hover: leaving before the intent delay never opens; returning during grace keeps it open")
    func hoverIntentAndGrace() {
        var state = State(trigger: .hover)
        state.handle(.hoverEnter)
        // Collapsed: the hidden deck built for an opening that never came is let go after the release grace (L1).
        #expect(state.handle(.hoverExit) == [.cancelIntent, .releasePrewarm])
        #expect(state.handle(.intentElapsed) == [])
        #expect(state.phase == .collapsed)

        state.handle(.hoverEnter)
        state.handle(.intentElapsed)
        state.handle(.hoverExit)
        #expect(state.handle(.hoverEnter) == [.cancelGrace])
        #expect(state.handle(.graceElapsed) == [])
        #expect(state.isExpanded)
    }

    @Test("Hover: a click opens at once without pinning; the header does not close")
    func hoverClick() {
        var state = State(trigger: .hover)
        state.handle(.hoverEnter)
        #expect(state.handle(.click) == [.cancelIntent, .cancelGrace, .prepare, .expand])
        #expect(state.phase == .expanded(pinned: false))
        #expect(state.handle(.click) == [])
        #expect(state.handle(.headerClick) == [])
        #expect(state.isExpanded)
    }

    @Test("Click: hover only prepares, a click opens pinned, leaving does not close")
    func clickMode() {
        var state = State(trigger: .click)
        #expect(state.handle(.hoverEnter) == [.cancelGrace, .prepare])
        #expect(state.handle(.intentElapsed) == [])
        #expect(state.handle(.click) == [.cancelIntent, .cancelGrace, .prepare, .expand])
        #expect(state.phase == .expanded(pinned: true))
        #expect(state.wantsOutsideClickMonitor)
        #expect(state.wantsEscapeMonitor)
        #expect(state.handle(.hoverExit) == [.cancelIntent])
        #expect(state.handle(.graceElapsed) == [])
        #expect(state.isExpanded)
    }

    @Test("Click: an outside click, Esc or the header closes a pinned deck", arguments: [
        IslandInteractionState.Event.outsideClick, .escape, .headerClick,
    ])
    func clickClosers(event: IslandInteractionState.Event) {
        var state = State(trigger: .click)
        state.handle(.click)
        #expect(state.handle(event).contains(.collapse))
        #expect(state.phase == .collapsed)
        #expect(!state.wantsOutsideClickMonitor)
        #expect(!state.wantsEscapeMonitor)
    }

    @Test("Hover or click: hover opens, a click pins, leaving then keeps it open")
    func hoverOrClick() {
        var state = State(trigger: .hoverOrClick)
        state.handle(.hoverEnter)
        state.handle(.intentElapsed)
        #expect(state.phase == .expanded(pinned: false))
        #expect(state.handle(.click) == [.cancelGrace])
        #expect(state.isPinned)
        #expect(state.handle(.hoverExit) == [.cancelIntent])
        #expect(state.isExpanded)
        #expect(state.handle(.outsideClick) == [.cancelIntent, .cancelGrace, .collapse])
    }

    @Test("The header toggles: it pins a deck opened by hover, then closes the pinned deck")
    func headerToggles() {
        var state = State(trigger: .hoverOrClick)
        state.handle(.hoverEnter)
        state.handle(.intentElapsed)
        #expect(state.handle(.headerClick) == [.cancelGrace])
        #expect(state.isPinned)
        #expect(state.wantsOutsideClickMonitor)
        #expect(state.handle(.hoverExit) == [.cancelIntent])
        #expect(state.handle(.headerClick) == [.cancelIntent, .cancelGrace, .collapse])
        #expect(state.phase == .collapsed)

        var peeked = State(trigger: .click)
        peeked.handle(.peekStart)
        #expect(peeked.handle(.headerClick) == [.cancelGrace])
        #expect(peeked.isPinned)
        #expect(peeked.handle(.peekEnd) == [])
        #expect(peeked.isExpanded)

        var collapsed = State(trigger: .click)
        #expect(collapsed.handle(.headerClick) == [])
        #expect(collapsed.phase == .collapsed)
    }

    @Test("Hover or click: without a click the deck closes like on hover")
    func hoverOrClickUnpinned() {
        var state = State(trigger: .hoverOrClick)
        state.handle(.hoverEnter)
        state.handle(.intentElapsed)
        #expect(state.handle(.hoverExit) == [.cancelIntent, .startGrace])
        #expect(state.handle(.graceElapsed) == [.collapse])
    }

    @Test("A drag closes the deck, swallows clicks and intents, and the drop never opens it", arguments: IslandOpenTrigger.allCases)
    func dragging(trigger: IslandOpenTrigger) {
        var state = State(trigger: trigger)
        state.handle(.hoverEnter)
        state.handle(.click)
        #expect(state.handle(.dragBegan) == [.cancelIntent, .cancelGrace, .releasePrewarm, .collapse])
        #expect(state.phase == .collapsed)
        #expect(!state.wantsOutsideClickMonitor)
        #expect(state.handle(.click) == [])
        #expect(state.handle(.intentElapsed) == [])
        #expect(state.handle(.hoverExit) == [.cancelIntent, .releasePrewarm])
        #expect(state.handle(.hoverEnter) == [.cancelGrace])
        #expect(state.handle(.dragEnded(pointerInside: true)) == [])
        #expect(state.phase == .collapsed)
        #expect(state.isHovering)
        #expect(!state.isDragging)
    }

    @Test("Peek opens temporarily in every mode and closes unless the pointer is on the island", arguments: IslandOpenTrigger.allCases)
    func peek(trigger: IslandOpenTrigger) {
        var state = State(trigger: trigger)
        #expect(state.handle(.peekStart) == [.cancelGrace, .prepare, .expand])
        #expect(state.phase == .expanded(pinned: false))
        #expect(state.handle(.peekEnd) == [.collapse])

        state.handle(.peekStart)
        state.handle(.hoverEnter)
        #expect(state.handle(.peekEnd) == [])
        #expect(state.isExpanded)
    }

    @Test("Leaving during a peek does not close early; a pinned deck outlives the peek")
    func peekEdges() {
        var state = State(trigger: .hover)
        state.handle(.peekStart)
        state.handle(.hoverEnter)
        #expect(state.handle(.hoverExit) == [.cancelIntent])
        #expect(state.handle(.graceElapsed) == [])
        #expect(state.handle(.peekEnd) == [.collapse])

        var pinned = State(trigger: .click)
        pinned.handle(.click)
        #expect(pinned.handle(.peekStart) == [.cancelGrace])
        #expect(pinned.handle(.peekEnd) == [])
        #expect(pinned.isPinned)
    }

    @Test("The shortcut toggles a pinned deck")
    func toggle() {
        var state = State(trigger: .hover)
        #expect(state.handle(.toggle) == [.cancelIntent, .cancelGrace, .prepare, .expand])
        #expect(state.isPinned)
        #expect(state.handle(.toggle) == [.cancelIntent, .cancelGrace, .collapse])
        #expect(state.phase == .collapsed)
    }

    @Test("Pin opens a pinned deck in every mode, pins an open one and outlives a peek", arguments: IslandOpenTrigger.allCases)
    func pin(trigger: IslandOpenTrigger) {
        var state = State(trigger: trigger)
        #expect(state.handle(.pin) == [.cancelIntent, .cancelGrace, .prepare, .expand])
        #expect(state.isPinned)
        #expect(state.wantsOutsideClickMonitor)
        #expect(state.handle(.pin) == [])
        state.handle(.hoverEnter)
        #expect(state.handle(.hoverExit) == [.cancelIntent])
        #expect(state.handle(.graceElapsed) == [])
        #expect(state.isPinned)
        #expect(state.handle(.escape) == [.cancelIntent, .cancelGrace, .collapse])

        var peeking = State(trigger: trigger)
        peeking.handle(.peekStart)
        #expect(peeking.handle(.pin) == [.cancelGrace])
        #expect(peeking.isPinned)
        #expect(!peeking.isPeeking)
        #expect(peeking.handle(.peekEnd) == [])
        #expect(peeking.isPinned)

        var dragging = State(trigger: trigger)
        dragging.handle(.dragBegan)
        #expect(dragging.handle(.pin) == [])
        #expect(dragging.phase == .collapsed)
    }

    @Test("Switching to hover unpins an open deck and closes it once the pointer is away")
    func triggerChange() {
        var state = State(trigger: .click)
        state.handle(.click)
        #expect(state.handle(.triggerChanged(.hover)) == [.startGrace])
        #expect(state.phase == .expanded(pinned: false))
        #expect(state.trigger == .hover)
        #expect(state.handle(.graceElapsed) == [.collapse])
    }

    @Test("An expansion that could not happen leaves the state collapsed")
    func unavailable() {
        var state = State(trigger: .click)
        state.handle(.click)
        #expect(state.handle(.expansionUnavailable) == [.releasePrewarm])
        #expect(state.phase == .collapsed)
        #expect(!state.wantsOutsideClickMonitor)
    }

    @Test("Triggers say what hover and click do")
    func triggers() {
        #expect(IslandOpenTrigger.hover.opensOnHover && !IslandOpenTrigger.hover.pinsOnClick)
        #expect(!IslandOpenTrigger.click.opensOnHover && IslandOpenTrigger.click.pinsOnClick)
        #expect(IslandOpenTrigger.hoverOrClick.opensOnHover && IslandOpenTrigger.hoverOrClick.pinsOnClick)
    }

    @MainActor
    @Test("Without a controller the model handles its own requests")
    func modelRequests() {
        let model = IslandModel(layout: IslandLayout(edge: .top, anchor: .top, style: .attached, metrics: IslandMetrics(scale: 1)))
        model.request(.openAttention)
        #expect(model.isExpanded)
        #expect(model.deckFocus == .attentionQueue)
        model.request(.headerClick)
        #expect(!model.isExpanded)

        var received: [IslandRequest] = []
        model.onRequest = { received.append($0) }
        model.request(.headerClick)
        #expect(received == [.headerClick])
    }
}

@Suite("Rail")
struct RailTests {
    @Test("Labels show the headline percentage, a countdown while blocked, a dash without data")
    func labels() throws {
        let now = UIFixture.now
        #expect(RailLabel(headline: nil, now: now, l10n: .testRussian) == .unknown)

        let normal = HeadlineWindows(reading: try UIFixture.reading([
            try UIFixture.bucket("main", [try UIFixture.window("session", .session, used: 57)]),
        ]))
        #expect(RailLabel(headline: normal, now: now, l10n: .testRussian) == .percent("57%", value: 57))

        let blocked = HeadlineWindows(reading: try UIFixture.reading([
            try UIFixture.bucket("main", [
                try UIFixture.window("session", .session, used: 40, resetsIn: 600),
                try UIFixture.window("week", .weekly(model: nil), used: 100, duration: .oneWeek, resetsIn: 2 * 3_600 + 14 * 60),
            ]),
        ]))
        #expect(RailLabel(headline: blocked, now: now, l10n: .testRussian) == .countdown("2:14"))
        #expect(RailLabel(headline: blocked, now: now.addingTimeInterval(3 * 3_600), l10n: .testRussian) == .percent("40%", value: 40))
    }

    @Test("Labels reserve the widest text they can show", arguments: [0.75, 1.0, 1.5])
    func labelWidths(scale: Double) {
        let size = IslandMetrics(scale: scale).textSize(TextSize.footnote)
        let percentWidth = Self.width(RailLabel.percentTemplate, size: size)
        let percents = (0...100).map { "\($0)%" } + ["<1%", RailLabel.unknownText]
        for text in percents {
            #expect(Self.width(text, size: size) <= percentWidth + 0.01, "\(text)")
        }
        let countdownWidth = Self.width(RailLabel.countdownTemplate, size: size)
        let seconds: [TimeInterval] = [1, 59, 60 * 9, 60 * 59, 3_600, 3_600 * 9 + 59 * 60, 3_600 * 10, 3_600 * 23 + 59 * 60, 86_400 * 2, 86_400 * 7, 86_400 * 31]
        // The template is the same in both languages, so it must hold the widest countdown of each.
        for l10n in [Localizer.testEnglish, .testRussian] {
            for value in seconds {
                let text = UsageFormat.railCountdown(value, l10n: l10n)
                #expect(Self.width(text, size: size) <= countdownWidth + 0.01, "\(text)")
            }
        }
    }

    @Test("The lock beside a countdown keeps its proportion to the digits and stays legible", arguments: [0.75, 0.85, 1.0, 1.5])
    func lockGlyph(scale: Double) {
        let metrics = IslandMetrics(scale: scale)
        let size = RailLabelView.lockGlyphSize(metrics: metrics)
        let digits = metrics.textSize(TextSize.footnote)
        #expect(size >= 7.5)
        #expect(size == size.rounded())
        #expect(abs(size / digits - 0.68) < 0.06)
    }

    @Test("Hairlines go between accounts of different groups")
    func separators() {
        let work = AccountGroupID()
        let home = AccountGroupID()
        #expect(RailView.separatorIndices(groups: []) == [])
        #expect(RailView.separatorIndices(groups: [work, work, nil]) == [2])
        #expect(RailView.separatorIndices(groups: [nil, work, work, home, nil]) == [1, 3, 4])
        #expect(RailView.separatorIndices(groups: [home, home]) == [])
    }

    @MainActor
    @Test("A rail dial reads as its account with usage, or how long it stays blocked, in words")
    func dialAccessibility() throws {
        let now = UIFixture.now
        let work = try UIFixture.group("Work")
        let reading = try UIFixture.reading([
            try UIFixture.bucket("main", [
                try UIFixture.window("session", .session, used: 57, resetsIn: 600),
            ]),
        ])
        var status = AccountStatus(profile: try UIFixture.profile("Claude", group: work), reading: reading)
        status.sessions = [try UIFixture.session("web", .working)]
        let normal = AccountPresentation(status: status, appearance: AppearanceSettings(), now: now, l10n: .testEnglish)
        #expect(RailView.dialAccessibilityValue(presentation: normal, now: now, l10n: .testEnglish) == "57% used, Working")
        #expect(RailView.dialAccessibilityValue(presentation: normal, now: now, l10n: .testRussian) == "использовано 57\u{00A0}%, работает")

        let blockedReading = try UIFixture.reading([
            try UIFixture.bucket("main", [
                try UIFixture.window("session", .session, used: 40, resetsIn: 600),
                try UIFixture.window("week", .weekly(model: nil), used: 100, duration: .oneWeek, resetsIn: 2 * 3_600 + 14 * 60),
            ]),
        ])
        let blocked = AccountPresentation(
            status: AccountStatus(profile: try UIFixture.profile("Codex", provider: .codex), reading: blockedReading),
            appearance: AppearanceSettings(),
            now: now,
            l10n: .testEnglish
        )
        #expect(RailView.dialAccessibilityValue(presentation: blocked, now: now, l10n: .testEnglish) == "Limit reached, available again in 2 hours 14 minutes")
        #expect(RailView.dialAccessibilityValue(presentation: blocked, now: now, l10n: .testRussian) == "Лимит исчерпан, снова доступен через 2 часа 14 минут")

        let empty = AccountPresentation(status: AccountStatus(profile: try UIFixture.profile("New")), appearance: AppearanceSettings(), now: now, l10n: .testEnglish)
        #expect(RailView.dialAccessibilityValue(presentation: empty, now: now, l10n: .testEnglish) == "No data")
        #expect(RingGauge.accessibilityDetails(presentation: empty, l10n: .testRussian) == ["Нет данных"])
    }

    @Test("The attention count never exceeds two digits")
    func attentionCount() {
        #expect(AttentionTab.countText(3) == "3")
        #expect(AttentionTab.countText(250) == "99")
        #expect(AttentionTab.countText(-1) == "0")
    }

    /// Width of rail label text: rounded, semibold, monospaced digits, like `IslandMetrics.digits`.
    private static func width(_ text: String, size: CGFloat) -> CGFloat {
        let base = NSFont.systemFont(ofSize: size, weight: .semibold)
        let rounded = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
        let monospaced = rounded.addingAttributes([
            .featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
            ]],
        ])
        let font = NSFont(descriptor: monospaced, size: size) ?? base
        return (text as NSString).size(withAttributes: [.font: font]).width
    }
}

@Suite("Text formatting")
struct UsageFormatTests {
    @Test("Percentages never show a used window as 0 %")
    func percent() throws {
        #expect(UsageFormat.percent(try Percentage(validating: 0.3), l10n: .testRussian) == "<1%")
        #expect(UsageFormat.percent(try Percentage(validating: 0), l10n: .testRussian) == "0%")
        #expect(UsageFormat.percent(try Percentage(validating: 57.5), l10n: .testRussian) == "58%")
    }

    private static let durationCases: [(TimeInterval, String)] = [
        (30, "1\u{00A0}мин"),
        (3_540, "59\u{00A0}мин"),
        (8_040, "2\u{00A0}ч 14\u{00A0}мин"),
        (273_600, "3\u{00A0}дн 4\u{00A0}ч"),
        (0, "<1\u{00A0}мин"),
    ]

    @Test("Compact durations", arguments: durationCases)
    func durations(seconds: TimeInterval, expected: String) {
        #expect(UsageFormat.compactDuration(seconds, l10n: .testRussian) == expected)
    }

    @Test("Window titles come from scope and duration")
    func windowTitles() throws {
        let used = try Percentage(validating: 10)
        #expect(UsageFormat.windowTitle(try LimitWindow(id: "session", scope: .session, used: used, duration: .fiveHours, resetsAt: nil), l10n: .testRussian) == "Сессия · 5\u{00A0}ч")
        #expect(UsageFormat.windowTitle(try LimitWindow(id: "week.fable", scope: .weekly(model: "Fable"), used: used, duration: .oneWeek, resetsAt: nil), l10n: .testRussian) == "Неделя · Fable")
        #expect(UsageFormat.windowTitle(try LimitWindow(id: "primary", scope: .rolling, used: used, duration: .oneWeek, resetsAt: nil), l10n: .testRussian) == "Неделя")
        #expect(UsageFormat.windowTitle(try LimitWindow(id: "primary", scope: .rolling, used: used, duration: .fiveHours, resetsAt: nil), l10n: .testRussian) == "5\u{00A0}ч")
    }

    @Test("Waiting reasons are translated")
    func activityText() {
        #expect(UsageFormat.activity(.waiting, detail: "permission prompt", l10n: .testRussian) == "ждёт подтверждения")
        #expect(UsageFormat.activity(.waiting, detail: "Permission", l10n: .testRussian) == "ждёт подтверждения")
        #expect(UsageFormat.activity(.waiting, detail: "input needed", l10n: .testRussian) == "ждёт ввода")
        #expect(UsageFormat.activity(.waiting, detail: nil, l10n: .testRussian) == "ждёт вас")
        #expect(UsageFormat.activity(.working, detail: nil, l10n: .testRussian) == "работает")
    }

    @Test("A long Codex permission prompt hedges: an approved command looks the same in its log")
    func codexPromptHedge() throws {
        let now = UIFixture.now
        func session(_ activity: AgentActivity, detail: String?, waitingFor seconds: TimeInterval) throws -> AgentSession {
            try AgentSession(id: "s", title: "s", projectPath: nil, activity: activity, detail: detail, activitySince: now.addingTimeInterval(-seconds), processID: nil)
        }
        let hedged = "ждёт подтверждения или выполняет команду"
        #expect(UsageFormat.activity(of: try session(.waiting, detail: "permission prompt", waitingFor: 59), provider: .codex, now: now, l10n: .testRussian) == "ждёт подтверждения")
        #expect(UsageFormat.activity(of: try session(.waiting, detail: "permission prompt", waitingFor: 60), provider: .codex, now: now, l10n: .testRussian) == hedged)
        #expect(UsageFormat.activity(of: try session(.waiting, detail: "permission prompt", waitingFor: 3_600), provider: .codex, now: now, l10n: .testRussian) == hedged)
        // Claude reports real prompts; questions and other waits keep their wording.
        #expect(UsageFormat.activity(of: try session(.waiting, detail: "permission prompt", waitingFor: 600), provider: .claude, now: now, l10n: .testRussian) == "ждёт подтверждения")
        #expect(UsageFormat.activity(of: try session(.waiting, detail: "input needed", waitingFor: 600), provider: .codex, now: now, l10n: .testRussian) == "ждёт ввода")
        #expect(UsageFormat.activity(of: try session(.working, detail: nil, waitingFor: 600), provider: .codex, now: now, l10n: .testRussian) == "работает")
        #expect(UsageFormat.codexPromptHedgeDelay == 60)
    }
}

@MainActor
@Suite("Island deck measurement")
struct IslandDeckMeasurementTests {
    private func makeStore() throws -> TrackerStore {
        let work = try UIFixture.group("Работа")
        let home = try UIFixture.group("Личное")
        let claude = try UIFixture.profile("Claude", group: work)
        let codex = try UIFixture.profile("Codex", provider: .codex, group: home)
        let settings = try AppSettings(accounts: [claude, codex], groups: [work, home])
        let state = TrackerState(accounts: [
            AccountStatus(
                profile: claude,
                reading: try UIFixture.reading([try UIFixture.bucket("claude", [
                    try UIFixture.window("session", .session, used: 57),
                    try UIFixture.window("week", .weekly(model: nil), used: 38, duration: .oneWeek, resetsIn: 4 * 86_400),
                ])]),
                sessions: [try UIFixture.session("claude-1", .waiting), try UIFixture.session("claude-2", .working)]
            ),
            AccountStatus(
                profile: codex,
                reading: try UIFixture.reading([try UIFixture.bucket("codex", [try UIFixture.window("primary", used: 12)])])
            ),
        ])
        return TrackerStore(state: state, settings: settings, now: UIFixture.now, actions: UIFixture.actions())
    }

    private func measure(_ store: TrackerStore, _ model: IslandModel, maxHeight: CGFloat = .infinity) -> CGSize {
        let deck = DeckContent(store: store, model: model, accounts: store.presentations, context: .island, maxHeight: maxHeight)
            .fixedSize()
            .environment(\.liveEffectsEnabled, false)
            .environment(\.introAnimationsEnabled, false)
        return NSHostingView(rootView: deck).fittingSize
    }

    @Test("A capped deck is exactly as tall as its cap, so the natural measurement can simply be clamped", arguments: [ScreenEdge.top, .right])
    func cappedDeck(edge: ScreenEdge) throws {
        let store = try makeStore()
        let anchor: IslandAnchor = edge == .top ? .top : .trailing
        let model = IslandModel(layout: IslandLayout(edge: edge, anchor: anchor, style: .attached, metrics: IslandMetrics(scale: 1), edgeInset: edge == .top ? 32 : 0))
        let natural = measure(store, model)
        #expect(natural.height > 300)
        for maximum in [300, (natural.height * 0.8).rounded(.down)] {
            let cap = IslandRootView.deckHeightCap(natural: natural.height.rounded(.up), maximum: maximum)
            #expect(cap == maximum)
            let capped = measure(store, model, maxHeight: cap)
            #expect(abs(capped.height - maximum) < 1, "\(maximum)")
            #expect(abs(capped.width - natural.width) < 1)
        }
        // A room the deck fits in adds no cap at all, so no scroll view is ever built for it.
        #expect(IslandRootView.deckHeightCap(natural: natural.height.rounded(.up), maximum: natural.height + 200) == .infinity)
    }

    @Test("The Timeline page keeps one height with or without data, and the deck measures it with the other pages")
    func timelinePageHeight() async throws {
        let empty = try makeStore()
        let accountID = try #require(empty.presentations.first?.id)
        let actions = UIFixture.actions(
            loadTimeline: { account, interval in
                let segment = try? SessionSegment(
                    accountID: account,
                    sessionID: "claude-1",
                    title: "Codometer",
                    project: "/Users/me/Codometer",
                    activity: .working,
                    start: interval.end.addingTimeInterval(-3_600),
                    end: nil
                )
                return TimelineSnapshot(
                    accountID: account,
                    interval: interval,
                    segments: segment.map { [$0] } ?? [],
                    usage: nil,
                    coverageStart: interval.end.addingTimeInterval(-7_200)
                )
            },
            loadAttribution: { _, interval, _ in
                let shares = (0..<6).compactMap { index in
                    try? AttributionShare(id: "p\(index)", subject: .project("Проект \(index)"), weightedTokens: 1_000, share: 1 / 6, estimatedPoints: 2.5)
                }
                return AttributionReport(interval: interval, windowTitleSource: nil, usedPoints: 15, shares: shares, totalWeightedTokens: 6_000, coverageStart: interval.end)
            }
        )
        let loaded = TrackerStore(state: empty.state, settings: empty.settings, now: UIFixture.now, actions: actions)
        loaded.analytics.requestTimeline(account: accountID, range: .fiveHours)
        loaded.analytics.requestAttribution(account: accountID, range: .fiveHours, grouping: .project)
        await loaded.analytics.settle()
        #expect(loaded.analytics.timeline(account: accountID, range: .fiveHours)?.segments.count == 1)
        #expect(loaded.analytics.attribution(account: accountID, range: .fiveHours, grouping: .project)?.shares.count == 6)

        func page(_ store: TrackerStore) throws -> CGSize {
            let presentation = try #require(store.presentations.first { $0.id == accountID })
            let metrics = IslandMetrics(scale: 0.85)
            let view = DeckTimelinePage(presentation: presentation, store: store, isSelected: true, metrics: metrics)
                .frame(width: metrics.deckWidth - metrics.deckPadding * 2)
                .fixedSize()
            return NSHostingView(rootView: view).fittingSize
        }
        #expect(try page(loaded) == page(empty))

        #expect(DeckLayout.availablePages.contains(.timeline))
        let model = IslandModel(layout: IslandLayout(edge: .top, anchor: .top, style: .attached, metrics: IslandMetrics(scale: 1)))
        #expect(measure(loaded, model) == measure(empty, model))
    }

    @Test("The deck has every account, so the group filter never changes its size")
    func filterKeepsSize() throws {
        let store = try makeStore()
        let model = IslandModel(layout: IslandLayout(edge: .top, anchor: .top, style: .attached, metrics: IslandMetrics(scale: 1)))
        let all = measure(store, model, maxHeight: 900)
        for group in store.settings.groups {
            store.updateSettings { (settings: inout AppSettings) throws(ValidationError) in
                settings.appearance.railGroupFilter = group.id
            }
            #expect(store.visiblePresentations.count == 1)
            #expect(measure(store, model, maxHeight: 900) == all)
        }
    }
}

@Suite("Rail design")
struct RailDesignTests {
    @Test("Percentages split into digits and a separate percent sign")
    func percentParts() {
        #expect(RailLabel.percentParts("57%") == ("57", "%"))
        #expect(RailLabel.percentParts("<1%") == ("<1", "%"))
        #expect(RailLabel.percentParts(RailLabel.percentTemplate) == ("100", "%"))
        #expect(RailLabel.percentParts("2:14") == ("2:14", ""))
        #expect(RailLabel.percentParts("%") == ("%", ""))
        #expect(RailLabel.percentParts(RailLabel.unknownText) == (RailLabel.unknownText, ""))
        #expect(RailLabelView.percentSignScale < 1)
    }

    @Test("Digits take a band colour only past the ample band")
    func tintedDigits() {
        #expect(RailLabelView.tintedBand(nil) == nil)
        #expect(RailLabelView.tintedBand(.ample) == nil)
        #expect(RailLabelView.tintedBand(.watch) == .watch)
        #expect(RailLabelView.tintedBand(.exhausted) == .exhausted)
    }

    @Test("Ring halos warm up with usage and stay faint, fainter on light surfaces")
    func halos() {
        let bands = UsageBand.allCases
        for dark in [false, true] {
            let opacities = bands.map { RingHalo.opacity(for: $0, dark: dark) }
            #expect(opacities == opacities.sorted())
            #expect(opacities.allSatisfy { $0 > 0 && $0 <= 0.3 })
        }
        for band in bands {
            #expect(RingHalo.opacity(for: band, dark: false) < RingHalo.opacity(for: band, dark: true))
        }
    }

    @Test("The sheen plays on a new percentage or kind of label, never on a countdown ticking down")
    func sheenTrigger() {
        func percent(_ value: Double) -> RailLabel {
            .percent("\(Int(value))%", value: value)
        }
        let before = RailView.sheenTrigger(labels: [percent(7), percent(81)])
        #expect(RailView.sheenTrigger(labels: [percent(7), percent(81)]) == before)
        #expect(RailView.sheenTrigger(labels: [percent(8), percent(81)]) != before)
        #expect(RailView.sheenTrigger(labels: [percent(81), percent(7)]) != before)
        #expect(RailView.sheenTrigger(labels: [percent(7)]) != before)
        let blocked = RailView.sheenTrigger(labels: [percent(7), .countdown("2:14")])
        #expect(blocked != before)
        #expect(RailView.sheenTrigger(labels: [percent(7), .countdown("2:13")]) == blocked)
        #expect(RailView.sheenTrigger(labels: [percent(7), .unknown]) != blocked)
    }

    @Test("The sheen band is a little under half the rail and never tiny")
    func sheenBand() {
        #expect(SheenSweepView.bandLength(for: 40) == 36)
        #expect(SheenSweepView.bandLength(for: 300) == 135)
        #expect(SheenSweepView.peakOpacity <= 0.2)
    }

    @Test("Glint and lift: faint on the system glass, which lights itself")
    func surfaceLight() {
        #expect(IslandGlass.liftOpacity(for: .glass) == 0)
        #expect(IslandGlass.liftOpacity(for: .solid) > 0)
        #expect(IslandGlass.liftOpacity(for: .solid) <= 0.08)
        #expect(IslandGlass.glintOpacity(for: .glass) < IslandGlass.glintOpacity(for: .solid))
        #expect(IslandGlass.glintOpacity(for: .glass) < IslandGlass.glintOpacity(for: .darkGlass))
        let stage = CGSize(width: 400, height: 700)
        #expect(abs(IslandGlass.glintRadius(edge: .top, island: CGRect(x: 100, y: 0, width: 200, height: 40), in: stage) - 68) < 0.001)
        #expect(abs(IslandGlass.glintRadius(edge: .right, island: CGRect(x: 340, y: 260, width: 60, height: 180), in: stage) - 61.2) < 0.001)
        #expect(IslandGlass.glintRadius(edge: .top, island: CGRect(x: 0, y: 0, width: 30, height: 20), in: stage) == 24)
        #expect(abs(IslandGlass.glintRadius(edge: .left, island: nil, in: stage) - 238) < 0.001)
    }
}

@Suite("Liquid island")
@MainActor
struct LiquidIslandTests {
    @Test("The wobble stays well inside the panel's margin", arguments: [0.75, 1.0, 1.5])
    func metrics(scale: Double) {
        let metrics = IslandMetrics(scale: scale)
        #expect(metrics.liquidWobble > 0)
        #expect(metrics.liquidWobble * 2 <= metrics.windowMargin)
    }

    @Test("The island's outline follows its layout, state and hover", arguments: [IslandStyle.attached, .floating])
    func outlineFromLayout(style: IslandStyle) {
        let metrics = IslandMetrics(scale: 1)
        let layout = IslandLayout(edge: .right, anchor: .trailing, style: style, metrics: metrics)
        let stage = IslandMorphLayout.anchored(rail: CGSize(width: 60, height: 180), deck: CGSize(width: 412, height: 700), anchor: .trailing)
        let rest = IslandRootView.liquidShape(layout: layout, stage: stage, expanded: false, swells: false, liquid: true).morph
        #expect(rest.progress == 0)
        #expect(rest.swell == 0)
        #expect(rest.edge == .right)
        #expect(rest.attachment == (style == .attached ? 1 : 0))
        #expect(rest.rail == stage.rail)
        #expect(rest.deck == stage.deck)
        #expect(rest.wobble == metrics.liquidWobble)
        #expect(rest.deckCorner == metrics.deckCorner)
        if style == .attached {
            #expect(rest.railCorner == metrics.railCorner)
        } else {
            // A capsule: the outline clamps the radius to half the rail's short side.
            #expect(rest.railCorner >= stage.rail.width / 2)
        }
        let open = IslandRootView.liquidShape(layout: layout, stage: stage, expanded: true, swells: true, liquid: false).morph
        #expect(open.progress == 1)
        #expect(open.swell == 1)
        #expect(!open.isLiquid)
    }

    @Test("A new model is not hovered")
    func hover() {
        let model = IslandModel(layout: IslandLayout(edge: .top, anchor: .top, style: .attached, metrics: IslandMetrics(scale: 1)))
        #expect(!model.isHovered)
    }
}

/// The fused rail's own geometry: centred on the camera notch whatever the saved offset, with the deck growing
/// straight down out of it.
@Suite("Fused island geometry")
struct FusedIslandGeometryTests {
    private let attachedArea = IslandGeometry.area(edge: .top, style: .attached, screen: screen, visible: area)
    private let fusedRail = CGSize(width: 620, height: 32)

    private func notch(offsetFromCentre: CGFloat = 0) -> NotchGeometry {
        let width: CGFloat = 197
        let aux = (screen.width - width) / 2 + offsetFromCentre
        guard let notch = NotchGeometry.make(
            screen: screen,
            safeTop: 32,
            auxLeft: CGRect(x: 0, y: screen.maxY - 32, width: aux, height: 32),
            auxRight: CGRect(x: aux + width, y: screen.maxY - 32, width: screen.width - aux - width, height: 32)
        ) else {
            preconditionFailure("the fixture must produce a notch")
        }
        return notch
    }

    @Test("The fused rail is centred on the notch, whatever the saved offset", arguments: [0.0, 0.25, 0.5, 0.75, 1.0])
    func centredOnNotch(offset: Double) {
        let notch = notch()
        let rail = IslandGeometry.railFrame(size: fusedRail, edge: .top, offset: offset, style: .attached, in: attachedArea, fusedNotch: notch)
        #expect(abs(rail.midX - notch.rect.midX) <= 1)
        #expect(rail.maxY == attachedArea.maxY)
        #expect(rail.maxY == screen.maxY)
    }

    @Test("A notch that is not in the middle of the screen still carries the rail")
    func offCentreNotch() {
        let notch = notch(offsetFromCentre: -160)
        let rail = IslandGeometry.railFrame(size: fusedRail, edge: .top, offset: 0.5, style: .attached, in: attachedArea, fusedNotch: notch)
        #expect(abs(rail.midX - notch.rect.midX) <= 1)
        #expect(rail.minX >= attachedArea.minX)
        #expect(rail.maxX <= attachedArea.maxX)
    }

    @Test("A rail wider than the screen is clamped instead of hanging off it")
    func clamped() {
        let huge = CGSize(width: screen.width + 400, height: 32)
        let rail = IslandGeometry.railFrame(size: huge, edge: .top, offset: 0.5, style: .attached, in: attachedArea, fusedNotch: notch())
        #expect(rail.minX == attachedArea.minX)
    }

    @Test("The deck grows downwards, centred on the notch, and keeps its own width")
    func deckUnderNotch() {
        let notch = notch()
        let frames = IslandGeometry.frames(sizes: IslandSizes(rail: fusedRail, deck: deck), edge: .top, offset: 0.1, style: .attached, in: attachedArea, fusedNotch: notch)
        #expect(abs(frames.deck.midX - notch.rect.midX) <= 1)
        #expect(frames.deck.maxY == frames.rail.maxY)
        #expect(frames.deck.maxY == screen.maxY)
        #expect(frames.deck.minY >= attachedArea.minY)
        // The rail is wide because it reaches around the notch; the deck is not stretched to match.
        #expect(frames.deck.width == deck.width)
        #expect(frames.rail.width > frames.deck.width)
    }

    @Test("Without a fused notch the rail follows the offset as before")
    func unfused() {
        let plain = IslandGeometry.railFrame(size: fusedRail, edge: .top, offset: 0, style: .attached, in: attachedArea)
        #expect(plain.minX == attachedArea.minX)
    }

    @Test("A fused layout drops the rail's top inset but keeps the deck's")
    func insets() {
        let notch = notch()
        var appearance = AppearanceSettings()
        appearance.edge = .top
        appearance.style = .attached
        appearance.offset = .center
        appearance.notchFusion = .automatic
        let layout = IslandLayout(appearance: appearance, edgeInset: 32, notch: notch)
        #expect(layout.isNotchFused)
        #expect(layout.anchor == .top)
        #expect(layout.shoulderInsets.top == 0)
        #expect(layout.shoulderInsets.leading == 0)
        #expect(layout.deckInsets.top == 32 + IslandLayout.attachedEdgeCompensation)
        #expect(layout.notchDialDiameter == NotchFusion.dialDiameter(railDial: layout.metrics.railDial, menuBarHeight: 32, orbitMargin: layout.metrics.orbitMargin))

        appearance.notchFusion = .off
        let off = IslandLayout(appearance: appearance, edgeInset: 32, notch: notch)
        #expect(!off.isNotchFused)
        #expect(off.shoulderInsets.top == 32 + IslandLayout.attachedEdgeCompensation)
        #expect(off.notchDialDiameter == nil)
    }

    @MainActor
    @Test("The fused outline uses the notch's own corner and a narrow shoulder")
    func fusedOutline() {
        let notch = notch()
        var appearance = AppearanceSettings()
        appearance.edge = .top
        appearance.style = .attached
        appearance.offset = .center
        let layout = IslandLayout(appearance: appearance, edgeInset: 32, notch: notch)
        let corner = IslandRootView.fusedRailCorner(layout: layout)
        #expect(corner == min(layout.metrics.railCorner, 32 * 0.3))
        #expect(IslandRootView.fusedShoulder(metrics: layout.metrics) == 6 * layout.metrics.scale)
        #expect(IslandRootView.fusedRailCorner(layout: IslandLayout(edge: .top, anchor: .top, style: .attached, metrics: layout.metrics)) == nil)
    }
}

/// Placing the island on a chosen display, and the bounds a carry may cover.
@Suite("Island displays")
struct IslandDisplayGeometryTests {
    private func display(_ id: String, frame: CGRect, isMain: Bool = false, name: String = "Display") -> DisplayDescriptor {
        DisplayDescriptor(
            id: (try? DisplayID(id)) ?? DisplayID.fallback,
            name: name,
            frame: frame,
            visibleFrame: frame.insetBy(dx: 0, dy: 20),
            isMain: isMain,
            isBuiltIn: isMain,
            notch: nil
        )
    }

    private var main: DisplayDescriptor {
        display("11111111-1111-4111-8111-111111111111", frame: CGRect(x: 0, y: 0, width: 1_512, height: 982), isMain: true, name: "Built-in")
    }

    /// A display left of and below the main one, so its origin is negative on both axes.
    private var secondary: DisplayDescriptor {
        display("22222222-2222-4222-8222-222222222222", frame: CGRect(x: -1_920, y: -200, width: 1_920, height: 1_080), name: "LG UltraFine")
    }

    @Test("An island on a display with a negative origin is placed in that display's own coordinates")
    func negativeOrigin() {
        let secondary = self.secondary
        let area = IslandGeometry.area(edge: .top, style: .attached, screen: secondary.frame, visible: secondary.visibleFrame)
        let rail = IslandGeometry.railFrame(size: railH, edge: .top, offset: 0.5, style: .attached, in: area)
        #expect(rail.maxY == secondary.frame.maxY)
        #expect(rail.minX < 0)
        #expect(abs(rail.midX - secondary.frame.midX) <= 1)
        let frames = IslandGeometry.frames(sizes: IslandSizes(rail: railH, deck: deck), edge: .top, offset: 0.5, style: .attached, in: area)
        #expect(frames.deck.minY >= area.minY)
        #expect(frames.deck.minX >= area.minX)
    }

    @Test("A drag may cover every display, and falls back to the island's own screen without a catalog")
    func dragBounds() {
        let union = IslandGeometry.dragBounds(displays: [main, secondary], fallback: main.frame)
        #expect(union == main.frame.union(secondary.frame))
        #expect(union.minX == -1_920)
        #expect(union.minY == -200)
        #expect(IslandGeometry.dragBounds(displays: [], fallback: main.frame) == main.frame)
    }

    @Test("\"Move to Display\" lists every connected display and checks the current one")
    func menuItems() {
        let l10n = Localizer.testEnglish
        let displays = [main, secondary]
        #expect(IslandMenuPlan.showsDisplaySubmenu(displays: displays))
        #expect(!IslandMenuPlan.showsDisplaySubmenu(displays: [main]))
        let items = IslandMenuPlan.displayItems(displays: displays, current: main.id, l10n: l10n)
        #expect(items.map(\.title) == ["Built-in", "LG UltraFine"])
        #expect(items.map(\.isChecked) == [true, false])
    }

    @Test("A display macOS gives no name for gets a placeholder, in both languages")
    func unnamedDisplay() {
        let unnamed = display("33333333-3333-4333-8333-333333333333", frame: CGRect(x: 0, y: 0, width: 800, height: 600), name: "")
        let english = IslandMenuPlan.displayItems(displays: [unnamed], current: nil, l10n: .testEnglish)
        let russian = IslandMenuPlan.displayItems(displays: [unnamed], current: nil, l10n: .testRussian)
        #expect(english.first?.title == "Unnamed display")
        #expect(russian.first?.title == "Экран без имени")
    }

    @Test("The island menu's new items read naturally in both languages")
    func menuTitles() {
        #expect(IslandMenuPlan.switchStyleTitle(l10n: .testEnglish) == "Switch to Floating Card")
        #expect(IslandMenuPlan.switchStyleTitle(l10n: .testRussian) == "Переключиться на плавающую карточку")
        #expect(IslandMenuPlan.moveToDisplayTitle(l10n: .testEnglish) == "Move to Display")
        #expect(IslandMenuPlan.moveToDisplayTitle(l10n: .testRussian) == "Переместить на экран")
        // Menu items are Title Case in English.
        for title in [IslandMenuPlan.switchStyleTitle(l10n: .testEnglish), IslandMenuPlan.moveToDisplayTitle(l10n: .testEnglish)] {
            let words = title.split(separator: " ").map(String.init)
            let small: Set<String> = ["to", "a", "an", "the", "of", "on", "in"]
            for (index, word) in words.enumerated() where !small.contains(word) {
                #expect(word.first?.isUppercase == true, "\(title): word \(index) is not Title Case")
            }
        }
    }

    @Test("The Presentation pane shows the display picker only when it is useful")
    func displayPickerVisibility() {
        let main = self.main
        let secondary = self.secondary
        #expect(!PlacementPane.showsDisplayPicker(displays: [main], policy: .whereLeft, remembered: nil))
        #expect(PlacementPane.showsDisplayPicker(displays: [main, secondary], policy: .whereLeft, remembered: nil))
        // A specific display is saved: the picker stays, so the choice can be seen and changed back.
        #expect(PlacementPane.showsDisplayPicker(displays: [main], policy: .display(secondary.id), remembered: nil))
        #expect(PlacementPane.showsDisplayPicker(displays: [main], policy: .whereLeft, remembered: secondary.remembered))
    }

    @Test("A saved display that is not plugged in is offered as \"(not connected)\", in both languages")
    func notConnectedOption() {
        let main = self.main
        let secondary = self.secondary
        for (l10n, expected) in [(Localizer.testEnglish, "LG UltraFine (not connected)"), (.testRussian, "LG UltraFine (не подключён)")] {
            let options = PlacementPane.displayOptions(
                displays: [main],
                policy: .display(secondary.id),
                remembered: secondary.remembered,
                l10n: l10n
            )
            #expect(options.map(\.title) == ["Built-in", expected])
        }
        // Everything connected: no "(not connected)" entry.
        let connected = PlacementPane.displayOptions(displays: [main, secondary], policy: .whereLeft, remembered: nil, l10n: .testEnglish)
        #expect(connected.map(\.title) == ["Built-in", "LG UltraFine"])
    }

    @Test("The picker's selection mirrors the stored policy")
    func pickerSelection() {
        #expect(PlacementPane.selection(policy: .whereLeft) == .whereLeft)
        #expect(PlacementPane.selection(policy: .main) == .main)
        #expect(PlacementPane.selection(policy: .display(secondary.id)) == .display(secondary.id))
    }
}

extension DisplayID {
    /// A valid id for fixtures whose literal cannot fail to parse.
    fileprivate static let fallback: DisplayID = {
        guard let id = try? DisplayID("00000000-0000-4000-8000-000000000000") else {
            preconditionFailure("the fallback id must be valid")
        }
        return id
    }()
}

/// The Presentation pane's new copy, measured in the real fonts: nothing may clip or push the pane around when the
/// style picker switches.
///
/// Layout facts, read off the pane renders: the detail column is 550 pt at its narrowest, a grouped section sits
/// 20 pt in from each side and its rows another 10 pt; the two style tiles share that width with 10 pt between them
/// and 10 pt of padding inside each; a row label's icon tile and spacing take 34 pt.
@MainActor
@Suite("Presentation pane copy")
struct PresentationPaneCopyTests {
    private static let languages: [Localizer] = [.testEnglish, .testRussian]
    private static let narrowestDetailWidth: CGFloat = 550
    private static let subheadline = NSFont.systemFont(ofSize: 11)
    private static let callout = NSFont.systemFont(ofSize: 12)

    private static func rowWidth(_ detail: CGFloat) -> CGFloat { detail - 2 * 20 - 2 * 10 }
    private static func tileWidth(_ detail: CGFloat) -> CGFloat { (rowWidth(detail) - 10) / 2 - 2 * 10 }

    private static func lines(_ text: String, _ font: NSFont, width: CGFloat) -> Int {
        let height = (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        ).height
        return Int((height / NSLayoutManager().defaultLineHeight(for: font)).rounded(.up))
    }

    @Test("Both style tiles describe themselves in the two lines they reserve")
    func tileDescriptions() {
        let width = Self.tileWidth(Self.narrowestDetailWidth)
        for l10n in Self.languages {
            for text in [l10n.presentationStyle.islandDescription, l10n.presentationStyle.floatingCardDescription] {
                #expect(Self.lines(text, Self.subheadline, width: width) <= 2, "\(l10n.language): \(text)")
            }
            // The titles sit beside an icon on one line.
            for title in [l10n.presentationStyle.island, l10n.presentationStyle.floatingCard] {
                #expect(Self.lines(title, NSFont.boldSystemFont(ofSize: 13), width: width - 24) == 1, "\(l10n.language): \(title)")
            }
        }
    }

    @Test("Both pane subtitles take the same number of lines, so switching styles never moves the pane")
    func paneSubtitles() {
        // The header's text sits beside a 46 pt symbol with 14 pt of spacing.
        let width = Self.narrowestDetailWidth - 2 * 20 - 2 * 10 - 46 - 14
        for l10n in Self.languages {
            let island = Self.lines(l10n.placement.paneSubtitle, Self.callout, width: width)
            let card = Self.lines(l10n.placement.cardPaneSubtitle, Self.callout, width: width)
            #expect(island == card, "\(l10n.language): island \(island) lines, card \(card)")
            #expect(island <= 2)
        }
    }

    @Test("The snapping and notch captions fit their rows at the narrowest width")
    func rowCaptions() {
        let width = Self.rowWidth(Self.narrowestDetailWidth) - 34 - 60
        for l10n in Self.languages {
            for text in [l10n.snapping.snapCaption, l10n.snapping.hapticsCaption, l10n.notch.blendCaption] {
                #expect(Self.lines(text, Self.subheadline, width: width) <= 3, "\(l10n.language): \(text)")
            }
            for title in [l10n.snapping.snapWhileDragging, l10n.snapping.haptics, l10n.notch.blendWithNotch, l10n.displays.display] {
                #expect(Self.lines(title, NSFont.systemFont(ofSize: 13), width: width) == 1, "\(l10n.language): \(title)")
            }
        }
    }

    @Test("Every display-picker option fits the picker's row in both languages")
    func displayOptions() {
        let width = Self.rowWidth(Self.narrowestDetailWidth) - 34 - 40
        for l10n in Self.languages {
            let longest = l10n.displays.notConnected("DELL UltraSharp U2723QE")
            for text in [l10n.displays.whereLeft, l10n.displays.mainDisplay, l10n.displays.unnamedDisplay, longest] {
                #expect(Self.lines(text, NSFont.systemFont(ofSize: 13), width: width) == 1, "\(l10n.language): \(text)")
            }
        }
    }

    @Test("The \"+N\" chip keeps a 24 pt hit target and never grows into a wing slot")
    func overflowChip() {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        for l10n in Self.languages {
            for count in [1, 9, 12, 99] {
                let text = l10n.notch.overflow(count)
                // The chip is the text plus 5 pt of padding on each side, floored at the 24 pt minimum target.
                let width = max(24, ceil((text as NSString).size(withAttributes: [.font: font]).width) + 10)
                #expect(width >= 24, "\(l10n.language): \(text) is \(width) pt wide")
                #expect(width <= 40, "\(l10n.language): \(text) is \(width) pt wide")
            }
            // VoiceOver says it in words, with the right plural form.
            #expect(!l10n.notch.overflowA11y(1).isEmpty)
            #expect(!l10n.notch.overflowA11y(5).isEmpty)
        }
        #expect(Localizer.testEnglish.notch.overflowA11y(1) == "1 more account")
        #expect(Localizer.testEnglish.notch.overflowA11y(3) == "3 more accounts")
        #expect(Localizer.testRussian.notch.overflowA11y(1) == "ещё 1 аккаунт")
        #expect(Localizer.testRussian.notch.overflowA11y(3) == "ещё 3 аккаунта")
        #expect(Localizer.testRussian.notch.overflowA11y(7) == "ещё 7 аккаунтов")
    }
}
