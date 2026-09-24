import CodometerUI
import AppKit
import SwiftUI

/// The settings window. The app is an agent (no Dock icon), so while this window is open the app
/// temporarily becomes a regular app (`ActivationPolicy`); otherwise macOS may refuse to bring the window to the front.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let activationReason = "settings"

    private let store: TrackerStore
    /// Called every time the window is shown: the lifecycle services use it to re-read the login item's real status.
    var onShow: (() -> Void)?
    private var window: NSWindow?
    /// Whether this window holds an `ActivationPolicy` retain (from showing until it closes).
    private var retainsActivation = false

    init(store: TrackerStore) {
        self.store = store
    }

    /// Whether the window is open (possibly behind other windows).
    var isOpen: Bool { window?.isVisible ?? false }

    /// Opens the window and brings it forward; `pane` selects that pane (also in an open window).
    func show(pane: SettingsPane? = nil) {
        onShow?()
        let window: NSWindow
        if let existing = self.window {
            window = existing
            if let pane {
                select(pane, in: existing)
            }
        } else {
            window = makeWindow(pane: pane ?? .accounts)
            self.window = window
        }
        if !retainsActivation {
            retainsActivation = true
            ActivationPolicy.retain(Self.activationReason)
        }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate()
        // Activation is asynchronous; bring the window forward again once the app is active.
        Task { @MainActor [window] in
            await Task.yield()
            window.makeKeyAndOrderFront(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard retainsActivation else { return }
        retainsActivation = false
        ActivationPolicy.release(Self.activationReason)
    }

    private func makeWindow(pane: SettingsPane) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Codometer"
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.contentViewController = NSHostingController(rootView: SettingsRootView(store: store, initialPane: pane))
        window.setContentSize(NSSize(width: 920, height: 660))
        window.contentMinSize = NSSize(width: 800, height: 580)
        window.center()
        window.setFrameAutosaveName("CodometerSettings")
        window.delegate = self
        #if DEBUG
        DebugWindows.register(window, name: DebugWindows.settings)
        #endif
        return window
    }

    /// Shows another pane in the open window: a fresh root on that pane, in the same frame.
    private func select(_ pane: SettingsPane, in window: NSWindow) {
        let frame = window.frame
        window.contentViewController = NSHostingController(rootView: SettingsRootView(store: store, initialPane: pane))
        window.setFrame(frame, display: true)
    }
}
