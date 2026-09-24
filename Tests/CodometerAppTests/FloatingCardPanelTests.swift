@testable import CodometerApp
import AppKit
import Foundation
import Testing

/// The floating card's window: it never activates the app, never takes clicks it should not, and only takes key
/// events while the user has engaged it.
@MainActor
@Suite("Floating card panel")
struct FloatingCardPanelTests {
    @Test("The panel is a borderless, non-activating panel with its own shadow")
    func construction() {
        let panel = FloatingCardPanel()
        #expect(panel.styleMask.contains(.borderless))
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.isFloatingPanel)
        #expect(!panel.isOpaque)
        // The card draws the shadow itself, following the morphing contour.
        #expect(!panel.hasShadow)
        #expect(!panel.hidesOnDeactivate)
        // The controller moves the card; AppKit's own dragging would fight the magnet.
        #expect(!panel.isMovable)
        #expect(panel.animationBehavior == .none)
        #expect(!panel.isReleasedWhenClosed)
        #expect(panel.backgroundColor == .clear)
    }

    @Test("The panel becomes key only while the card is keyboard-engaged, and never main")
    func keyEngagement() {
        let panel = FloatingCardPanel()
        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        panel.isKeyboardEngaged = true
        #expect(panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        panel.isKeyboardEngaged = false
        #expect(!panel.canBecomeKey)
    }

    @Test("“Keep above other windows” decides the level: floating, or just above the desktop icons")
    func level() {
        #expect(FloatingCardPanel.level(keepsAboveWindows: true) == .floating)
        let desktop = FloatingCardPanel.level(keepsAboveWindows: false)
        #expect(desktop.rawValue == Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        #expect(desktop.rawValue < NSWindow.Level.floating.rawValue)
        // Always below the island's own level and the menu bar, so a popover is never covered.
        #expect(desktop.rawValue < NSWindow.Level.statusBar.rawValue)
        #expect(FloatingCardPanel.level(keepsAboveWindows: true).rawValue < NSWindow.Level.statusBar.rawValue)
    }

    @Test("The card is on every Space, out of the window cycle, and follows full-screen apps only when allowed")
    func collectionBehavior() {
        let hidden = FloatingCardPanel.collectionBehavior(hidesInFullScreen: true)
        #expect(hidden.contains(.canJoinAllSpaces))
        #expect(hidden.contains(.stationary))
        #expect(hidden.contains(.ignoresCycle))
        #expect(!hidden.contains(.fullScreenAuxiliary))
        let shown = FloatingCardPanel.collectionBehavior(hidesInFullScreen: false)
        #expect(shown.contains(.fullScreenAuxiliary))
    }

    @Test("Clicks on the transparent margin fall through: the container never takes them itself")
    func containerLetsClicksThrough() {
        let container = FloatingCardContainerView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        #expect(container.hitTest(NSPoint(x: 10, y: 10)) == nil)
    }
}

/// Two-finger horizontal swipes on the card switch accounts; vertical scrolling is left alone.
@Suite("Card swipe")
struct CardSwipeAccumulatorTests {
    @Test("A horizontal swipe past the threshold switches once, in the natural direction")
    func swipeSwitchesOnce() {
        var swipe = CardSwipeAccumulator()
        #expect(swipe.feed(deltaX: -10, deltaY: 0, phase: .began) == nil)
        #expect(swipe.feed(deltaX: -20, deltaY: 0, phase: .changed) == nil)
        // Past 40 pt of travel to the left: the next account.
        #expect(swipe.feed(deltaX: -20, deltaY: 0, phase: .changed) == 1)
        // The rest of the same swipe changes nothing more.
        #expect(swipe.feed(deltaX: -60, deltaY: 0, phase: .changed) == nil)
        #expect(swipe.feed(deltaX: 0, deltaY: 0, phase: .ended) == nil)
        // The next swipe, to the right, goes back.
        #expect(swipe.feed(deltaX: 25, deltaY: 0, phase: .began) == nil)
        #expect(swipe.feed(deltaX: 25, deltaY: 0, phase: .changed) == -1)
    }

    @Test("Vertical scrolling is left to the rest of the app")
    func verticalIsIgnored() {
        var swipe = CardSwipeAccumulator()
        _ = swipe.feed(deltaX: 0, deltaY: -10, phase: .began)
        for _ in 0..<20 {
            #expect(swipe.feed(deltaX: 2, deltaY: -30, phase: .changed) == nil)
        }
    }

    @Test("A short flick never switches accounts")
    func shortSwipeDoesNothing() {
        var swipe = CardSwipeAccumulator()
        _ = swipe.feed(deltaX: -5, deltaY: 0, phase: .began)
        #expect(swipe.feed(deltaX: -10, deltaY: 0, phase: .changed) == nil)
        #expect(swipe.feed(deltaX: 0, deltaY: 0, phase: .ended) == nil)
    }

    @Test("A cancelled swipe starts the count again")
    func cancelResets() {
        var swipe = CardSwipeAccumulator()
        _ = swipe.feed(deltaX: -30, deltaY: 0, phase: .began)
        #expect(swipe.feed(deltaX: 0, deltaY: 0, phase: .cancelled) == nil)
        #expect(swipe.feed(deltaX: -30, deltaY: 0, phase: .changed) == nil)
    }
}
