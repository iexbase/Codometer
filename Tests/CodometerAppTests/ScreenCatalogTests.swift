@testable import CodometerApp
import AppKit
import CodometerCore
import CodometerPlatform
import CoreGraphics
import Foundation
import Testing

/// The catalog that publishes the connected displays and answers where a surface belongs.
@MainActor
@Suite("Screen catalog")
struct ScreenCatalogTests {
    @Test("A fresh catalog is empty until it is refreshed")
    func startsEmpty() {
        let catalog = ScreenCatalog()
        #expect(catalog.displays.isEmpty)
        #expect(catalog.resolve(policy: .whereLeft, remembered: nil) == nil)
    }

    @Test("Refreshing reports a change only when the display list really changed")
    func refreshIsIdempotent() throws {
        let catalog = ScreenCatalog()
        try #require(!NSScreen.screens.isEmpty, "this Mac reports no display")
        #expect(catalog.refresh())
        #expect(!catalog.refresh())
        #expect(!catalog.displays.isEmpty)
        #expect(catalog.displays == DisplayIdentity.displays())
    }

    @Test("Every published display maps back to a screen")
    func screenLookup() throws {
        let catalog = ScreenCatalog()
        catalog.refresh()
        try #require(!catalog.displays.isEmpty)
        for display in catalog.displays {
            let screen = try #require(catalog.screen(for: display.id))
            #expect(screen.frame == display.frame)
        }
    }

    @Test("Every policy resolves to a connected display")
    func resolvePolicies() throws {
        let catalog = ScreenCatalog()
        catalog.refresh()
        let displays = catalog.displays
        try #require(!displays.isEmpty)
        let main = try #require(DisplaySelection.main(in: displays))

        #expect(catalog.resolve(policy: .main, remembered: nil)?.display.id == main.id)
        #expect(catalog.resolve(policy: .whereLeft, remembered: nil)?.display.id == main.id)
        for display in displays {
            #expect(catalog.resolve(policy: .display(display.id), remembered: nil)?.display.id == display.id)
            #expect(catalog.resolve(policy: .whereLeft, remembered: display.remembered)?.display.id == display.id)
        }
    }

    @Test("A saved display that is gone falls back to the main one")
    func disconnectedFallback() throws {
        let catalog = ScreenCatalog()
        catalog.refresh()
        let displays = catalog.displays
        try #require(!displays.isEmpty)
        let main = try #require(DisplaySelection.main(in: displays))
        let absent = try DisplayID("C0FFEE00-0000-4000-8000-000000000001")
        #expect(catalog.resolve(policy: .display(absent), remembered: nil)?.display.id == main.id)
        let remembered = RememberedDisplay(id: absent, name: "Nothing Here")
        #expect(catalog.resolve(policy: .whereLeft, remembered: remembered)?.display.id == main.id)
    }

    @Test("A drop lands under the pointer when the policy allows it, and on the pinned display otherwise")
    func dropTarget() throws {
        let catalog = ScreenCatalog()
        catalog.refresh()
        let displays = catalog.displays
        try #require(!displays.isEmpty)
        let main = try #require(DisplaySelection.main(in: displays))
        let point = CGPoint(x: main.frame.midX, y: main.frame.midY)

        #expect(catalog.dropTarget(at: point, policy: .whereLeft, remembered: nil)?.id == main.id)
        #expect(catalog.dropTarget(at: point, policy: .main, remembered: nil)?.id == main.id)
        // A point far outside every display still lands on the nearest one.
        let far = CGPoint(x: main.frame.maxX + 10_000, y: main.frame.midY)
        #expect(catalog.dropTarget(at: far, policy: .whereLeft, remembered: nil) != nil)
        // A pinned display wins over whatever is under the pointer.
        for display in displays where display.id != main.id {
            #expect(catalog.dropTarget(at: point, policy: .display(display.id), remembered: nil)?.id == display.id)
        }
    }

    @Test("A display re-adopted by name keeps its place after its UUID changed")
    func adoptByName() throws {
        let catalog = ScreenCatalog()
        catalog.refresh()
        let displays = catalog.displays
        let named = displays.first { !$0.name.isEmpty && displays.filter({ $0.name == $0.name }).count >= 1 }
        try #require(named != nil, "this Mac reports no named display")
        let renamed = RememberedDisplay(id: try DisplayID("C0FFEE00-0000-4000-8000-000000000002"), name: named?.name)
        let unique = displays.filter { $0.name == named?.name }.count == 1
        if unique {
            #expect(catalog.resolve(policy: .whereLeft, remembered: renamed)?.display.id == named?.id)
        }
    }
}
