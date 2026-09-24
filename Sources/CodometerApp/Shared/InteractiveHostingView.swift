import AppKit
import CodometerPlatform
import os
import SwiftUI

/// Hosts a movable surface (the island, the floating card) and turns raw mouse input into hover, click, drag,
/// double-click and context-menu callbacks.
///
/// The view covers the surface's whole canvas, but only `interactiveRect` (the surface's current shape frame)
/// tracks hover and takes clicks; everywhere else hit testing returns `nil`, so clicks on the transparent margin reach
/// the windows below. Hover uses a tracking area, which works while the app is inactive and costs nothing while the
/// pointer is elsewhere: no global event monitors and no polling. Drags use AppKit's own deltas after
/// `dragThreshold`, never a SwiftUI gesture.
final class InteractiveHostingView<Content: View>: NSHostingView<Content> {
    /// Pointer travel, in points, before a press becomes a drag.
    static var dragThreshold: CGFloat { 5 }

    var onHover: ((Bool) -> Void)?
    /// The pointer entered or left the margin around the surface (only while `approachMargin` is positive).
    var onApproach: ((Bool) -> Void)?
    /// A left mouse press started on the surface.
    var onPress: (() -> Void)?
    /// A single press and release that never became a drag. Sent after SwiftUI has seen the release.
    var onClick: (() -> Void)?
    /// A drag started: where the press began and where the pointer is now, in screen coordinates.
    var onDragBegan: ((NSPoint, NSPoint) -> Void)?
    var onDragMoved: ((NSPoint) -> Void)?
    var onDragEnded: ((NSPoint) -> Void)?
    var onDoubleClick: (() -> Void)?
    var contextMenu: (() -> NSMenu)?

    /// The surface's current shape frame in this view's coordinates.
    var interactiveRect: CGRect = .zero {
        didSet {
            guard interactiveRect != oldValue else { return }
            updateTrackingAreas()
            setNeedsPointerRefresh()
        }
    }

    /// How far around `interactiveRect` the approach area reaches; 0 installs none.
    ///
    /// The margin is the panel's own transparent room, so clicks in it still pass through to the windows below
    /// (`hitTest` is unchanged) and the only thing the area does is tell the controller the pointer is on its way.
    var approachMargin: CGFloat = 0 {
        didSet {
            guard approachMargin != oldValue else { return }
            updateTrackingAreas()
        }
    }

    /// Replaces the real pointer position for hover decisions while set (the debug harness uses it).
    var pointerOverride: Bool? {
        didSet { setNeedsPointerRefresh() }
    }

    private(set) var isPointerInside = false
    private(set) var isPointerNear = false

    /// Whether this view is inside its own layout pass. SwiftUI updates its views there and runs some callbacks
    /// from inside that update (animation completions, geometry actions), where calling `layoutSubtreeIfNeeded()`
    /// again is illegal (AppKit logs "not legal to call -layoutSubtreeIfNeeded on a view which is already being
    /// laid out").
    var isLayingOut: Bool { layoutDepth > 0 }

    private var layoutDepth = 0
    private var trackingArea: NSTrackingArea?
    private var approachArea: NSTrackingArea?
    private var pressLocation: NSPoint?
    private var isDragging = false
    private var pointerRefreshScheduled = false

    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Layout

    override func layout() {
        layoutDepth += 1
        defer { layoutDepth -= 1 }
        super.layout()
    }

    /// Applies pending SwiftUI changes now. Inside this view's own layout pass it does nothing, because that pass
    /// is already applying them; returns whether it laid out.
    @discardableResult
    func layoutSubtreeIfAllowed() -> Bool {
        guard !isLayingOut else { return false }
        layoutSubtreeIfNeeded()
        return true
    }

    // MARK: - Hit testing and hover

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = superview.map { convert(point, from: $0) } ?? point
        guard interactiveRect.contains(local) else { return nil }
        return super.hitTest(point)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
            self.trackingArea = nil
        }
        if let approachArea {
            removeTrackingArea(approachArea)
            self.approachArea = nil
        }
        guard !interactiveRect.isEmpty else { return }
        // The approach area is added first, so the surface's own area is the one AppKit reports for the inner rect.
        if approachMargin > 0 {
            let rect = approachRect
            if !rect.isEmpty {
                let area = NSTrackingArea(
                    rect: rect,
                    options: [.mouseEnteredAndExited, .activeAlways],
                    owner: self,
                    userInfo: nil
                )
                addTrackingArea(area)
                approachArea = area
            }
        }
        let area = NSTrackingArea(
            rect: interactiveRect,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    /// The surface's rect grown by `approachMargin`, clipped to the view.
    var approachRect: CGRect {
        guard approachMargin > 0, !interactiveRect.isEmpty else { return .zero }
        return interactiveRect.insetBy(dx: -approachMargin, dy: -approachMargin).intersection(bounds)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        guard pointerOverride == nil else { return }
        if event.trackingArea === approachArea {
            setPointerNear(true)
        } else if event.trackingArea === trackingArea {
            setPointerInside(true)
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        guard pointerOverride == nil else { return }
        if event.trackingArea === approachArea {
            setPointerNear(false)
        } else if event.trackingArea === trackingArea {
            setPointerInside(false)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setNeedsPointerRefresh()
    }

    /// Re-reads whether the pointer is over the surface on the next turn: moving or resizing the window, or
    /// the surface's frame changing under a still pointer, produces no entered/exited events by itself.
    func setNeedsPointerRefresh() {
        guard !pointerRefreshScheduled else { return }
        pointerRefreshScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            pointerRefreshScheduled = false
            refreshPointerInside()
        }
    }

    private func refreshPointerInside() {
        if let pointerOverride {
            setPointerInside(pointerOverride)
            if pointerOverride { setPointerNear(true) }
            return
        }
        guard let window, window.isVisible, !isDragging else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        setPointerInside(interactiveRect.contains(point))
        setPointerNear(approachMargin > 0 && approachRect.contains(point))
    }

    private func setPointerInside(_ inside: Bool) {
        guard inside != isPointerInside else { return }
        isPointerInside = inside
        onHover?(inside)
    }

    private func setPointerNear(_ near: Bool) {
        guard near != isPointerNear else { return }
        isPointerNear = near
        onApproach?(near)
    }

    // MARK: - Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    /// Where `event` happened, in screen coordinates: the event's own location, not the pointer's position now.
    private func screenLocation(of event: NSEvent) -> NSPoint {
        guard let window = event.window ?? window else { return NSEvent.mouseLocation }
        return window.convertPoint(toScreen: event.locationInWindow)
    }

    override func mouseDown(with event: NSEvent) {
        pressLocation = screenLocation(of: event)
        isDragging = false
        AppLog.interface.debug("surface press at \(self.pressLocation.debugDescription, privacy: .public)")
        onPress?()
        if event.clickCount == 2 {
            onDoubleClick?()
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if !continueDrag(event) {
            super.mouseDragged(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else {
            let wasPressed = pressLocation != nil
            pressLocation = nil
            // SwiftUI sees the release first, so a button or header click is handled before the surface's own click.
            super.mouseUp(with: event)
            if wasPressed, event.clickCount <= 1 {
                onClick?()
            }
            return
        }
        finishDrag(at: screenLocation(of: event))
    }

    /// Drag detection at the window, ahead of hit testing, the first-click rules of a window that is not key and
    /// SwiftUI's own gesture handling, any of which can keep a press from ever reaching this view's `mouseDown`.
    /// A window that offers its left-button events here first gets drags that begin anywhere on the surface.
    /// Returns whether the event belonged to a drag and must not be dispatched any further.
    func interceptDragEvent(_ event: NSEvent) -> Bool {
        switch event.type {
        case .leftMouseDown:
            let local = convert(event.locationInWindow, from: nil)
            if interactiveRect.contains(local) {
                pressLocation = screenLocation(of: event)
                isDragging = false
            } else {
                pressLocation = nil
            }
            return false
        case .leftMouseDragged:
            return continueDrag(event)
        case .leftMouseUp:
            guard isDragging else { return false }
            finishDrag(at: screenLocation(of: event))
            return true
        default:
            return false
        }
    }

    /// Forgets a press or drag whose release never arrived, so the next press starts clean.
    func resetDragTracking() {
        pressLocation = nil
        isDragging = false
    }

    /// Begins or continues a drag for a dragged event; `false` when the event is not part of one (yet).
    private func continueDrag(_ event: NSEvent) -> Bool {
        guard let start = pressLocation else { return false }
        let point = screenLocation(of: event)
        guard isDragging else {
            guard hypot(point.x - start.x, point.y - start.y) >= Self.dragThreshold else { return false }
            isDragging = true
            AppLog.interface.debug("surface drag begins at \(point.debugDescription, privacy: .public)")
            cancelSwiftUIPress(like: event)
            // The controller moves the surface to `point` as part of beginning the drag.
            onDragBegan?(start, point)
            return true
        }
        onDragMoved?(point)
        return true
    }

    private func finishDrag(at point: NSPoint) {
        pressLocation = nil
        isDragging = false
        AppLog.interface.debug("surface drag ends at \(point.debugDescription, privacy: .public)")
        onDragEnded?(point)
        setNeedsPointerRefresh()
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = contextMenu?() else {
            super.rightMouseDown(with: event)
            return
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    /// Releases the press SwiftUI saw on mouse-down far outside the view, so a drag never
    /// ends up triggering the button or dial that was under the pointer when it started.
    private func cancelSwiftUIPress(like event: NSEvent) {
        guard let release = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: NSPoint(x: -10_000, y: -10_000),
            modifierFlags: [],
            timestamp: event.timestamp,
            windowNumber: event.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        ) else { return }
        super.mouseUp(with: release)
    }
}
