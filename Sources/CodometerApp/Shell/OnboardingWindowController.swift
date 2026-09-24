import CodometerL10n
import CodometerUI
import AppKit
import SwiftUI

/// The welcome window: 680 × 540, titled, not resizable, centred.
///
/// The app is an agent, so it becomes a regular app while this window is open, through the same reference-counted
/// `ActivationPolicy` the Settings window uses. Closing the window counts as Skip: the flow reports its outcome
/// once, whether the user finished it, skipped it, or clicked the close button.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let activationReason = "onboarding"

    let model: OnboardingModel
    private var window: NSWindow?
    private var retainsActivation = false
    /// Called with the flow's outcome exactly once, then cleared.
    private var onComplete: ((OnboardingFlow.Outcome) -> Void)?

    init(store: TrackerStore, isFirstRun: Bool, onComplete: @escaping (OnboardingFlow.Outcome) -> Void) {
        model = OnboardingModel(store: store, isFirstRun: isFirstRun)
        self.onComplete = onComplete
        super.init()
        model.onComplete = { [weak self] outcome in self?.complete(outcome) }
    }

    var isOpen: Bool { window?.isVisible ?? false }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
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

    /// Closes the window without reporting an outcome (the flow already reported one).
    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        releaseActivation()
        // A click on the close button is a Skip; a window closed by `complete` has already reported.
        complete(.skipped)
    }

    private func complete(_ outcome: OnboardingFlow.Outcome) {
        guard let handler = onComplete else { return }
        onComplete = nil
        handler(outcome)
    }

    private func releaseActivation() {
        guard retainsActivation else { return }
        retainsActivation = false
        ActivationPolicy.release(Self.activationReason)
    }

    private func makeWindow() -> NSWindow {
        let size = NSSize(width: OnboardingMetrics.width, height: OnboardingMetrics.height)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = model.store.localizer.onboarding.windowTitle
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.contentViewController = NSHostingController(rootView: OnboardingRootView(model: model) { [weak self] title in
            self?.window?.title = title
        })
        window.setContentSize(size)
        window.center()
        window.delegate = self
        #if DEBUG
        DebugWindows.register(window, name: DebugWindows.onboarding)
        #endif
        return window
    }
}

/// The window's fixed size.
enum OnboardingMetrics {
    static let width: CGFloat = 680
    static let height: CGFloat = 540
}

/// Injects the localizer the same way every other root does, so the flow switches language at once; the window's
/// own title follows through `retitle`, because AppKit draws it.
private struct OnboardingRootView: View {
    let model: OnboardingModel
    let retitle: @MainActor (String) -> Void

    var body: some View {
        let l10n = model.store.localizer
        OnboardingView(model: model)
            .environment(\.l10n, l10n)
            .environment(\.locale, l10n.locale)
            .onChange(of: l10n.language, initial: true) { _, _ in retitle(l10n.onboarding.windowTitle) }
    }
}
