import AppKit
import SwiftUI

/// A borderless, non-activating panel: the island never takes focus from the app you are working in.
final class IslandPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        isReleasedWhenClosed = false
        // `ignoresMouseEvents` is deliberately never set: while it is untouched, the window server lets clicks
        // on fully transparent pixels (the margin around the island) through to the windows below.
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The panel's content view: a plain container whose only child, the hosting view, is positioned by the
/// island controller so the canvas stays put on screen while the panel around it changes.
final class IslandContainerView: NSView {
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
}
