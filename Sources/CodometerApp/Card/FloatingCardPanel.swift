import AppKit
import SwiftUI

/// The floating card's window: borderless, non-activating, with its own shadow, and never in the way.
///
/// It becomes key only while the card is *keyboard-engaged* (the user clicked it), so Esc, the arrow keys, Space and
/// ⌘, work without taking focus from the app in front. `ignoresMouseEvents` is deliberately never set: while it is
/// untouched, the window server lets clicks on the fully transparent margin through to the windows below.
final class FloatingCardPanel: NSPanel {
    /// Set while the card takes key events. The panel never becomes key again once it is off, and the key status it
    /// already has ends the next time the user clicks elsewhere.
    var isKeyboardEngaged = false

    /// A key the card handles itself; the panel forwards it and gives up the event when the handler took it.
    var onKeyDown: ((NSEvent) -> Bool)?

    /// Sees every event before the panel dispatches it; `true` when a drag of the card consumed it. Drags are caught
    /// here rather than in a view: a press the window would not hand to a view (the first click of a window that is
    /// not key, a subview that refuses it, a gesture that holds the events) still carries the card.
    var dragInterceptor: ((NSEvent) -> Bool)?

    override func sendEvent(_ event: NSEvent) {
        if let dragInterceptor, dragInterceptor(event) { return }
        super.sendEvent(event)
    }

    /// Above normal windows while "Keep above other windows" is on, otherwise just above the desktop icons, where the
    /// card sits on the desktop and your windows cover it.
    static func level(keepsAboveWindows: Bool) -> NSWindow.Level {
        keepsAboveWindows ? .floating : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }

    /// The card is on every Space and never joins the window cycle; it follows a full-screen app only when the user
    /// has not asked for it to be hidden there.
    static func collectionBehavior(hidesInFullScreen: Bool) -> NSWindow.CollectionBehavior {
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        if !hidesInFullScreen {
            behavior.insert(.fullScreenAuxiliary)
        }
        return behavior
    }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        backgroundColor = .clear
        isOpaque = false
        // The card draws its own shadow, which follows the morphing contour.
        hasShadow = false
        hidesOnDeactivate = false
        // The controller moves the card; AppKit's own window dragging would fight the magnet.
        isMovable = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { isKeyboardEngaged }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        guard onKeyDown?(event) == true else {
            super.keyDown(with: event)
            return
        }
    }

    /// Esc reaches a borderless panel as `cancelOperation`, not as a plain key event.
    override func cancelOperation(_ sender: Any?) {
        if let event = NSApp.currentEvent, onKeyDown?(event) == true { return }
    }
}

/// The panel's content view: it holds the card's canvas, lets clicks on the transparent margin through, and turns
/// two-finger horizontal scrolling into account switches.
final class FloatingCardContainerView: NSView {
    /// A two-finger horizontal swipe crossed the threshold: `+1` is the next account, `-1` the previous one.
    var onSwipe: ((Int) -> Void)?

    private var swipe = CardSwipeAccumulator()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        autoresizesSubviews = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    override func scrollWheel(with event: NSEvent) {
        guard let direction = swipe.feed(
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY,
            phase: event.phase
        ) else {
            super.scrollWheel(with: event)
            return
        }
        onSwipe?(direction)
    }
}

/// Turns a stream of scroll samples into account switches: only clearly horizontal travel counts, and one swipe
/// switches once however far it goes.
struct CardSwipeAccumulator {
    /// How far a two-finger swipe has to travel before it switches accounts.
    static let threshold: CGFloat = 40

    private var offset: CGFloat = 0
    private var firedThisSwipe = false

    /// `+1` for the next account, `-1` for the previous one, `nil` when nothing has happened yet.
    mutating func feed(deltaX: CGFloat, deltaY: CGFloat, phase: NSEvent.Phase) -> Int? {
        if phase.contains(.began) {
            offset = 0
            firedThisSwipe = false
        }
        if phase.contains(.ended) || phase.contains(.cancelled) {
            offset = 0
            firedThisSwipe = false
            return nil
        }
        guard abs(deltaX) > abs(deltaY), !firedThisSwipe else { return nil }
        offset += deltaX
        guard abs(offset) >= Self.threshold else { return nil }
        firedThisSwipe = true
        let direction = offset < 0 ? 1 : -1
        offset = 0
        // A natural-direction swipe to the left (negative delta) moves forward through the accounts.
        return direction
    }
}
