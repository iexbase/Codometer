import AppKit
import CodometerCore
@testable import CodometerPlatform
import CoreGraphics
import Foundation
import Testing

/// Reading the connected displays: their stable UUID, their frames and their camera notch.
///
/// Anything that needs real hardware is asserted as an invariant over whatever displays this Mac has, so the suite
/// is honest on a laptop, on a desktop with three screens, and on a headless CI runner.
@MainActor
@Suite("Display identity")
struct DisplayIdentityTests {
    @Test("A display id is a canonical uppercase UUID")
    func identifierFormat() throws {
        let displays = DisplayIdentity.displays()
        try #require(!displays.isEmpty, "this Mac reports no display")
        for display in displays {
            let raw = display.id.rawValue
            #expect(raw.count == 36)
            #expect(raw == raw.uppercased())
            #expect(UUID(uuidString: raw) != nil)
            // Re-validating the stored form is a no-op.
            #expect(try DisplayID(raw) == display.id)
        }
    }

    @Test("Ids are unique and the first screen is the main one")
    func uniqueAndMain() throws {
        let displays = DisplayIdentity.displays()
        try #require(!displays.isEmpty)
        #expect(Set(displays.map(\.id)).count == displays.count)
        #expect(displays.first?.isMain == true)
        #expect(displays.dropFirst().allSatisfy { !$0.isMain })
    }

    @Test("Every descriptor carries usable frames, and the visible frame is inside the full one")
    func frames() throws {
        let displays = DisplayIdentity.displays()
        try #require(!displays.isEmpty)
        for display in displays {
            #expect(display.frame.width > 0 && display.frame.height > 0)
            #expect(display.frame.insetBy(dx: -1, dy: -1).contains(display.visibleFrame))
            #expect(display.name.count <= DisplayDescriptor.maximumNameLength)
        }
    }

    @Test("A descriptor round-trips to the screen it came from")
    func screenLookup() throws {
        let displays = DisplayIdentity.displays()
        try #require(!displays.isEmpty)
        for display in displays {
            let screen = try #require(DisplayIdentity.screen(for: display.id))
            #expect(screen.frame == display.frame)
        }
    }

    @Test("A notch is reported only for a built-in display, and it sits at the top of it")
    func notch() {
        for display in DisplayIdentity.displays() {
            guard let notch = display.notch else { continue }
            #expect(display.isBuiltIn)
            #expect(abs(notch.rect.maxY - display.frame.maxY) < 0.001)
            #expect(notch.rect.width >= NotchGeometry.minimumWidth)
            #expect(notch.rect.width <= display.frame.width * NotchGeometry.maximumWidthFraction)
            #expect(notch.menuBarHeight > 0)
        }
    }

    @Test("The main display's number resolves to the id its descriptor carries")
    func mainDisplayNumber() throws {
        let displays = DisplayIdentity.displays()
        try #require(!displays.isEmpty)
        let main = try #require(DisplaySelection.main(in: displays))
        #expect(DisplayIdentity.identifier(displayID: CGMainDisplayID()) == main.id)
    }

    @Test("A display number nothing is plugged into has no identity")
    func unknownDisplayNumber() {
        #expect(DisplayIdentity.identifier(displayID: CGDirectDisplayID.max) == nil)
    }

    @Test("Screens without a display number are skipped instead of crashing")
    func emptyScreenList() {
        #expect(DisplayIdentity.displays(screens: []).isEmpty)
    }
}
