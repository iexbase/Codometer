import AppKit

@main
@MainActor
enum CodometerMain {
    static func main() {
        // Before anything else: an uncaught AppKit exception becomes a crash report instead of a half-broken app
        //. Nothing is sent anywhere; MetricKit stores the payload locally.
        CrashCapture.enableCrashOnExceptions()
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        // An agent app: no Dock icon. It does get a main menu, so ⌘C, ⌘V, ⌘Z, ⌘W and ⌘Q work in its windows.
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = AppController.launch()
        if controller == nil {
            NSApp.terminate(nil)
        }
    }

    /// Quitting waits (at most `AppController.shutdownTimeout`) for the engine to stop, so open history segments
    /// close at quit time instead of at the next launch. The wait is synchronous (see `AppController.shutdown()`):
    /// a `.terminateLater` reply sent from a main-actor task never arrives when quitting starts on the main queue.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        controller?.shutdown()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Already done when `applicationShouldTerminate` ran; covers terminations that skip it.
        controller?.shutdown()
        controller?.stopLifecycleServices()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.openSettings()
        return false
    }

    // MARK: - Main menu

    // The app menu's items have no other target, so they travel up the responder chain and end here.

    @objc func openCodometerSettings(_ sender: Any?) {
        controller?.openSettings()
    }

    @objc func showCodometerAboutPanel(_ sender: Any?) {
        controller?.showAboutPanel()
    }
}
