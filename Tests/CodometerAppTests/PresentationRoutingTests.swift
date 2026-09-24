@testable import CodometerApp
import CodometerCore
import CodometerPlatform
import CodometerUI
import Foundation
import Testing

/// A surface that records what the router asked of it.
@MainActor
private final class FakeSurface: PresentationSurface {
    var isOnScreen: Bool
    var accepts: Bool
    private(set) var calls: [String] = []

    init(onScreen: Bool = true, accepts: Bool = true) {
        isOnScreen = onScreen
        self.accepts = accepts
    }

    func applyAppearance() { calls.append("apply") }

    func openPinned(accountID: AccountID) -> Bool {
        calls.append("openPinned")
        return accepts
    }

    func peek(accountID: AccountID, seconds: Int) { calls.append("peek:\(seconds)") }

    func toggleFromShortcut(preferAttention: Bool) -> Bool {
        calls.append("toggle:\(preferAttention)")
        return accepts
    }

    func hide() { calls.append("hide") }
}

@MainActor
@Suite("Presentation routing")
struct PresentationRoutingTests {
    @Test("The card is active only when it is the selected style and exists")
    func activeSurface() {
        let island = FakeSurface()
        let card = FakeSurface()
        #expect(PresentationRouting.activeSurface(style: .island, island: island, card: card) === island)
        #expect(PresentationRouting.activeSurface(style: .floatingCard, island: island, card: card) === card)
        #expect(PresentationRouting.activeSurface(style: .floatingCard, island: island, card: nil) === island)
        #expect(PresentationRouting.activeSurface(style: .island, island: island, card: nil) === island)
    }

    @Test("A notification click opens the active surface, or the popover when it cannot")
    func notificationClick() {
        let accepting = FakeSurface()
        var fallbacks = 0
        PresentationRouting.openPinned(accountID: AccountID(), on: accepting) { fallbacks += 1 }
        #expect(accepting.calls == ["openPinned"] && fallbacks == 0)

        let hidden = FakeSurface(onScreen: false, accepts: false)
        PresentationRouting.openPinned(accountID: AccountID(), on: hidden) { fallbacks += 1 }
        #expect(hidden.calls == ["openPinned"] && fallbacks == 1)
    }

    @Test("The shortcut toggles the active surface, or the popover when it cannot")
    func shortcut() {
        let accepting = FakeSurface()
        var fallbacks = 0
        PresentationRouting.toggleFromShortcut(on: accepting, preferAttention: true) { fallbacks += 1 }
        #expect(accepting.calls == ["toggle:true"] && fallbacks == 0)

        let hidden = FakeSurface(onScreen: false, accepts: false)
        PresentationRouting.toggleFromShortcut(on: hidden, preferAttention: false) { fallbacks += 1 }
        #expect(hidden.calls == ["toggle:false"] && fallbacks == 1)
    }

    @Test("Turning the shortcut off registers nothing and reports it as off")
    func shortcutOff() {
        let service = HotKeyService()
        #expect(service.apply(.off) == .off)
        #expect(service.shortcut == .off)
        #expect(ShortcutConflictResolver.status(for: .off, registration: service.apply(.off), symbolic: [], trials: [:]) == .off)
    }

}
