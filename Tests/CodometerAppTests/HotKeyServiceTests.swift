@testable import CodometerApp
import CodometerCore
import Carbon.HIToolbox
import Foundation
import Testing

/// The app's two Carbon hot keys: the global shortcut (id 1) and the scoped Esc that closes a pinned deck while
/// another app is active (id 2, L4), plus the conflict reporting of L3.
@MainActor
@Suite("Hot keys")
struct HotKeyServiceTests {
    @Test("A press is routed to the handler of the id that was registered")
    func idRouting() {
        let service = HotKeyService()
        defer { service.unregister() }
        var shortcutPresses = 0
        var escapePresses = 0
        service.onPress = { shortcutPresses += 1 }
        service.onEscape = { escapePresses += 1 }

        // Nothing is registered yet: a stray event reaches neither handler.
        service.pressed(id: .shortcut)
        service.pressed(id: .escape)
        #expect(shortcutPresses == 0)
        #expect(escapePresses == 0)

        service.apply(.controlOptionCommandU)
        service.pressed(id: .shortcut)
        service.pressed(id: .escape)
        #expect(shortcutPresses == 1)
        #expect(escapePresses == 0)

        service.setEscapeArmed(true)
        service.pressed(id: .escape)
        #expect(escapePresses == 1)
        #expect(shortcutPresses == 1)
    }

    @Test("The two registrations are independent")
    func independentRegistrations() {
        let service = HotKeyService()
        defer { service.unregister() }
        service.setEscapeArmed(true)
        #expect(service.isEscapeArmed)
        #expect(service.shortcut == .off)

        service.apply(.controlOptionCommandU)
        #expect(service.shortcut == .controlOptionCommandU)
        #expect(service.isEscapeArmed)

        service.setEscapeArmed(false)
        #expect(!service.isEscapeArmed)
        #expect(service.shortcut == .controlOptionCommandU)
    }

    @Test("Arming Esc twice, or disarming it twice, changes nothing")
    func escapeIsIdempotent() {
        let service = HotKeyService()
        defer { service.unregister() }
        #expect(service.setEscapeArmed(true) == .registered)
        #expect(service.setEscapeArmed(true) == .registered)
        #expect(service.setEscapeArmed(false) == .off)
        #expect(service.setEscapeArmed(false) == .off)
        #expect(!service.isEscapeArmed)
    }

    @Test("Applying the shortcut that is already registered reports it without re-registering")
    func repeatedApply() {
        let service = HotKeyService()
        defer { service.unregister() }
        #expect(service.apply(.controlOptionCommandU) == .registered)
        #expect(service.apply(.controlOptionCommandU) == .registered)
        #expect(service.apply(.off) == .off)
        #expect(service.shortcut == .off)
        #expect(service.apply(.off) == .off)
    }

    @Test("Probing leaves the chosen shortcut registered and reports only the others")
    func probeAlternatives() {
        let service = HotKeyService()
        defer { service.unregister() }
        service.apply(.controlOptionCommandU)
        let trials = service.probeAlternatives(excluding: .controlOptionCommandU)
        #expect(!trials.keys.contains(.controlOptionCommandU))
        #expect(!trials.keys.contains(.off))
        #expect(Set(trials.keys) == Set(GlobalShortcut.allCases.filter { $0 != .off && $0 != .controlOptionCommandU }))
        // The chosen shortcut still works after the trials borrowed the slot.
        var presses = 0
        service.onPress = { presses += 1 }
        service.pressed(id: .shortcut)
        #expect(presses == 1)
        #expect(service.shortcut == .controlOptionCommandU)
    }

    @Test("macOS's own shortcuts are read as Carbon combinations")
    func symbolicHotKeys() {
        let service = HotKeyService()
        defer { service.unregister() }
        let keys = service.symbolicHotKeys()
        // `CopySymbolicHotKeys` may fail on a bare CI machine; whatever it returns has to be well formed.
        for key in keys {
            let unknownBits = key.carbonModifiers & ~(
                ShortcutConflictResolver.commandMask
                    | ShortcutConflictResolver.shiftMask
                    | ShortcutConflictResolver.optionMask
                    | ShortcutConflictResolver.controlMask
            )
            #expect(unknownBits == 0)
        }
    }

    @Test("Esc is registered with the Carbon key code the system uses")
    func escapeKeyCode() {
        #expect(HotKeyService.escapeKeyCode == UInt32(kVK_Escape))
    }

    @Test("Unregistering releases both ids")
    func unregisterAll() {
        let service = HotKeyService()
        service.apply(.controlOptionCommandU)
        service.setEscapeArmed(true)
        service.unregister()
        #expect(service.shortcut == .off)
        #expect(!service.isEscapeArmed)
        var presses = 0
        service.onPress = { presses += 1 }
        service.onEscape = { presses += 1 }
        service.pressed(id: .shortcut)
        service.pressed(id: .escape)
        #expect(presses == 0)
    }
}
