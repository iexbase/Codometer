import AppKit
import SwiftUI

/// Reports whether the view's window is on screen, so work meant for a viewer (loading history) runs only while
/// someone can see it. A popover's hosting view outlives the popover, and keeps updating while it is closed.
///
/// Driven by window notifications only: no polling, and it never takes mouse events.
struct WindowVisibilityReader: NSViewRepresentable {
    let onChange: @MainActor (Bool) -> Void

    func makeNSView(context: Context) -> WindowVisibilityView {
        let view = WindowVisibilityView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: WindowVisibilityView, context: Context) {
        view.onChange = onChange
    }

    /// On screen: ordered in and at least partly unoccluded.
    nonisolated static func isOnScreen(isVisible: Bool, occlusion: NSWindow.OcclusionState) -> Bool {
        isVisible && occlusion.contains(.visible)
    }
}

final class WindowVisibilityView: NSView {
    var onChange: (@MainActor (Bool) -> Void)?

    private var reported: Bool?
    private weak var observedWindow: NSWindow?
    private static let notifications: [Notification.Name] = [
        NSWindow.didChangeOcclusionStateNotification,
        NSWindow.didBecomeKeyNotification,
        NSWindow.willCloseNotification,
    ]

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if let observedWindow {
            for name in Self.notifications {
                NotificationCenter.default.removeObserver(self, name: name, object: observedWindow)
            }
        }
        observedWindow = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            observedWindow = window
            for name in Self.notifications {
                NotificationCenter.default.addObserver(self, selector: #selector(windowChanged(_:)), name: name, object: window)
            }
        }
        report(closing: false)
    }

    @objc private func windowChanged(_ notification: Notification) {
        report(closing: notification.name == NSWindow.willCloseNotification)
    }

    private func report(closing: Bool) {
        let visible = !closing && window.map {
            WindowVisibilityReader.isOnScreen(isVisible: $0.isVisible, occlusion: $0.occlusionState)
        } ?? false
        guard visible != reported else { return }
        reported = visible
        // This can run inside a SwiftUI update (moving to a window); deliver the latest value afterwards.
        Task { @MainActor [weak self] in
            guard let self, let value = reported else { return }
            onChange?(value)
        }
    }
}
