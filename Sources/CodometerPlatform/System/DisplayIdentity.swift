import AppKit
import CodometerCore
import CoreGraphics

/// Turns `NSScreen`s into the pure `DisplayDescriptor`s the island and the floating card place themselves with.
///
/// The identifier is the display's hardware UUID (`CGDisplayCreateUUIDFromDisplayID`), which survives relaunches,
/// sleep and re-plugging, unlike `CGDirectDisplayID`. It is a local hardware identifier stored in `settings.json`
/// and never leaves the Mac.
public enum DisplayIdentity {
    /// Every connected display, in `NSScreen.screens` order (the first one carries the menu bar).
    @MainActor
    public static func displays(screens: [NSScreen] = NSScreen.screens) -> [DisplayDescriptor] {
        let main = screens.first
        return screens.compactMap { screen in
            descriptor(for: screen, isMain: screen === main)
        }
    }

    /// The `NSScreen` for a display id, if it is connected.
    @MainActor
    public static func screen(for id: DisplayID, screens: [NSScreen] = NSScreen.screens) -> NSScreen? {
        screens.first { identifier(of: $0) == id }
    }

    /// One screen as a descriptor; `nil` when macOS gives no usable display number or UUID for it.
    @MainActor
    public static func descriptor(for screen: NSScreen, isMain: Bool) -> DisplayDescriptor? {
        guard let id = identifier(of: screen) else { return nil }
        return DisplayDescriptor(
            id: id,
            name: screen.localizedName,
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            isMain: isMain,
            isBuiltIn: displayNumber(of: screen).map { CGDisplayIsBuiltin($0) != 0 } ?? false,
            notch: notch(of: screen)
        )
    }

    /// The display's stable UUID as `DisplayID` (canonical uppercase, as `DisplayID` validates it).
    @MainActor
    public static func identifier(of screen: NSScreen) -> DisplayID? {
        guard let number = displayNumber(of: screen) else { return nil }
        return identifier(displayID: number)
    }

    /// The UUID of a `CGDirectDisplayID`.
    public static func identifier(displayID: CGDirectDisplayID) -> DisplayID? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        guard let string = CFUUIDCreateString(nil, uuid) as String? else { return nil }
        return try? DisplayID(string)
    }

    /// The camera notch of a built-in display, from the two auxiliary menu bar areas beside it.
    ///
    /// External displays and clamshell mode report no auxiliary areas, so they get `nil`.
    @MainActor
    public static func notch(of screen: NSScreen) -> NotchGeometry? {
        NotchGeometry.make(
            screen: screen.frame,
            safeTop: screen.safeAreaInsets.top,
            auxLeft: screen.auxiliaryTopLeftArea,
            auxRight: screen.auxiliaryTopRightArea
        )
    }

    @MainActor
    private static func displayNumber(of screen: NSScreen) -> CGDirectDisplayID? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        return CGDirectDisplayID(number.uint32Value)
    }
}
