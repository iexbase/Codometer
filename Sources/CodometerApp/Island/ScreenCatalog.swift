import AppKit
import CodometerCore
import CodometerPlatform

/// The connected displays as `DisplayDescriptor`s, kept current for `store.displays`, the island and the card.
///
/// Refreshed only on `NSApplication.didChangeScreenParametersNotification` (which `AppController` already observes),
/// so it costs nothing while nothing is plugged in or out.
@MainActor
final class ScreenCatalog {
    private(set) var displays: [DisplayDescriptor] = []
    private var screens: [DisplayID: NSScreen] = [:]

    init() {}

    /// Re-reads `NSScreen.screens`; returns whether the list changed.
    @discardableResult
    func refresh(screens list: [NSScreen] = NSScreen.screens) -> Bool {
        let descriptors = DisplayIdentity.displays(screens: list)
        var map: [DisplayID: NSScreen] = [:]
        for screen in list {
            guard let id = DisplayIdentity.identifier(of: screen) else { continue }
            if map[id] == nil { map[id] = screen }
        }
        screens = map
        guard descriptors != displays else { return false }
        displays = descriptors
        return true
    }

    /// The `NSScreen` behind a descriptor, while it is connected.
    func screen(for id: DisplayID) -> NSScreen? {
        screens[id]
    }

    /// The descriptor a policy resolves to, and the screen it belongs to.
    func resolve(policy: DisplayPolicy, remembered: RememberedDisplay?) -> (display: DisplayDescriptor, screen: NSScreen)? {
        guard let display = DisplaySelection.resolve(policy: policy, remembered: remembered, displays: displays),
              let screen = screens[display.id]
        else { return nil }
        return (display, screen)
    }

    /// The display under a point, allowed by `policy` (a policy that pins a display answers that display instead).
    func dropTarget(at point: CGPoint, policy: DisplayPolicy, remembered: RememberedDisplay?) -> DisplayDescriptor? {
        guard let under = DisplaySelection.display(at: point, in: displays) else { return nil }
        if DisplaySelection.allowsDrop(on: under, policy: policy, displays: displays) { return under }
        return DisplaySelection.resolve(policy: policy, remembered: remembered, displays: displays)
    }
}
