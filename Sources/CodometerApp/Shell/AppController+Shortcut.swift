import CodometerCore
import CodometerPlatform
import CodometerUI
import Foundation

/// State of the global shortcut: what macOS itself uses, and which alternatives are free.
@MainActor
final class ShortcutCoordinator {
    /// macOS's own shortcuts, read once per registration pass (`CopySymbolicHotKeys` walks a system list).
    var symbolic: [SymbolicHotKey] = []
    /// Trial registrations of the other choices, refreshed only when the chosen one is unavailable or when
    /// Settings asks. Empty otherwise, so a working shortcut costs one registration and nothing else.
    var trials: [GlobalShortcut: ShortcutRegistration] = [:]
    /// A debug scenario pinned the status in memory; real registration results are ignored while it is set.
    var statusOverride: ShortcutStatus?

    init() {}
}

/// The global shortcut: registration, its status in Settings, and routing presses to the active surface.
extension AppController {
    /// Registers the chosen shortcut (never in an isolated data root unless a debug scenario sets one) and publishes
    /// its status, alternatives included when it is unavailable.
    func applyShortcut(probesAlternatives: Bool = false) {
        var shortcut = directories.isIsolated ? GlobalShortcut.off : store.settings.general.globalShortcut
        #if DEBUG
        if let general = island.debugGeneralOverride {
            shortcut = general.globalShortcut
        }
        if let override = shortcuts.statusOverride {
            store.setShortcutStatus(override)
            return
        }
        #endif
        let registration = hotKeys.apply(shortcut)
        // An enabled macOS shortcut wins even when registration succeeds, so the system list is always consulted.
        shortcuts.symbolic = shortcut == .off ? [] : hotKeys.symbolicHotKeys()
        let clashes = registration != .registered
            || ShortcutConflictResolver.isUsedByMacOS(shortcut, symbolic: shortcuts.symbolic)
        if shortcut != .off, clashes || probesAlternatives {
            shortcuts.trials = hotKeys.probeAlternatives(excluding: shortcut)
        } else {
            shortcuts.trials = [:]
        }
        store.setShortcutStatus(ShortcutConflictResolver.status(
            for: shortcut,
            registration: registration,
            symbolic: shortcuts.symbolic,
            trials: shortcuts.trials
        ))
    }

    /// A press of the global shortcut: the active surface toggles, or the popover when that surface is hidden.
    func shortcutPressed() {
        PresentationRouting.toggleFromShortcut(on: activeSurface, preferAttention: !store.attentionQueue.isEmpty) {
            statusItem.togglePopover()
        }
    }

    /// Checks the shortcut again and probes the alternatives (Settings → General and Diagnostics ask for this).
    func refreshShortcutStatus() {
        applyShortcut(probesAlternatives: true)
    }
}
