import CodometerCore
import Foundation

/// A presentation style on screen: the island or the floating card. Exactly one is shown at a time; the menu bar item
/// and its popover always stay.
///
/// `AppController` routes notification clicks, peeks and the global shortcut to the active surface and falls back to
/// the popover when the surface cannot handle them.
@MainActor
protocol PresentationSurface: AnyObject {
    /// Whether the surface's window is on screen.
    var isOnScreen: Bool { get }
    /// Re-reads settings; shows itself only when it is the selected style and visibility is `.always`, else hides.
    func applyAppearance()
    /// Opens on one account and stays open (e.g. after a notification click). `false` when it cannot (hidden, not
    /// ready): the caller opens the popover instead.
    @discardableResult func openPinned(accountID: AccountID) -> Bool
    /// Draws attention to one account for a few seconds, then returns to how it was.
    func peek(accountID: AccountID, seconds: Int)
    /// The global shortcut: toggles open and closed. `preferAttention` shows the agents waiting first. `false` when the
    /// surface cannot handle it: the caller opens the popover instead.
    func toggleFromShortcut(preferAttention: Bool) -> Bool
    /// Leaves the screen now (e.g. when the other style is selected).
    func hide()
}

/// What the launch checks decided before any data is touched.
enum LaunchPreflight {
    /// Go on; `lock` is whatever keeps the single-instance lock held (kept for the process lifetime).
    case proceed(lock: AnyObject?)
    /// Stop the launch (the check already told the user or the other instance).
    case quit
}

/// The routing rules between the surfaces and the popover, free of AppKit so tests can drive them with fakes.
@MainActor
enum PresentationRouting {
    /// The card when it is the selected style and exists, otherwise the island.
    static func activeSurface(
        style: PresentationStyle,
        island: any PresentationSurface,
        card: (any PresentationSurface)?
    ) -> any PresentationSurface {
        if style == .floatingCard, let card {
            return card
        }
        return island
    }

    /// A notification click: the active surface opens pinned on the account, or the popover shows it.
    static func openPinned(accountID: AccountID, on surface: any PresentationSurface, fallback: () -> Void) {
        if !surface.openPinned(accountID: accountID) {
            fallback()
        }
    }

    /// The global shortcut: the active surface toggles, or the popover toggles.
    static func toggleFromShortcut(on surface: any PresentationSurface, preferAttention: Bool, fallback: () -> Void) {
        if !surface.toggleFromShortcut(preferAttention: preferAttention) {
            fallback()
        }
    }
}
