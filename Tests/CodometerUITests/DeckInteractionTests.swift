import CodometerCore
import CoreGraphics
import Testing
@testable import CodometerUI

@Suite("Deck dial hover")
@MainActor
struct DeckInteractionTests {
    @Test("A deck that opens under a still pointer does not select by hover")
    func stillPointerNeverSelects() {
        let tracking = DialHoverTracking()
        let location = CGPoint(x: 120, y: 80)
        #expect(!tracking.pointerMoved(to: location))
        // The same location again (the dial moved under the pointer, or hover re-fired) is still no movement.
        #expect(!tracking.pointerMoved(to: location))
        #expect(!tracking.pointerMoved(to: CGPoint(x: 121, y: 80.5)))
        #expect(!tracking.hasMoved)
    }

    @Test("Hover selection starts after a real movement and then follows the pointer")
    func movementEnablesSelection() {
        let tracking = DialHoverTracking()
        #expect(!tracking.pointerMoved(to: CGPoint(x: 10, y: 10)))
        #expect(tracking.pointerMoved(to: CGPoint(x: 10, y: 10 + DialHoverTracking.threshold)))
        #expect(tracking.hasMoved)
        // Once moved, any later location counts, including going back.
        #expect(tracking.pointerMoved(to: CGPoint(x: 10, y: 10)))
    }
}

/// The click-open latency work (L1): the deck is built while the pointer approaches or presses, and a quick move
/// in and out never throws it away.
@Suite("Click-open preparation")
struct ClickOpenPreparationTests {
    private typealias State = IslandInteractionState

    @Test("In click modes a press builds the deck once, and nothing is released before the release")
    func pressPrepares() {
        for trigger in [IslandOpenTrigger.click, .hoverOrClick] {
            var state = State(trigger: trigger)
            let onArrival = state.handle(.hoverEnter)
            #expect(onArrival.contains(.prepare))
            #expect(state.handle(.press) == [.prepare])
            #expect(state.handle(.click).contains(.expand))
            // Already open: a second press changes nothing.
            #expect(state.handle(.press) == [])
        }
    }

    @Test("In hover mode a press does nothing new: the hover intent already prepared")
    func pressInHoverMode() {
        var state = State(trigger: .hover)
        state.handle(.hoverEnter)
        #expect(state.handle(.press) == [])
    }

    @Test("The approach margin prepares only where a click can open the deck")
    func approachOnlyInClickModes() {
        for trigger in [IslandOpenTrigger.click, .hoverOrClick] {
            var state = State(trigger: trigger)
            #expect(state.handle(.approach) == [.prepare])
        }
        var hover = State(trigger: .hover)
        #expect(hover.handle(.approach) == [])
        #expect(hover.handle(.approachExit) == [.releasePrewarm])
    }

    @Test("Leaving the margin releases the deck; an open or hovered island keeps it")
    func approachExit() {
        var state = State(trigger: .click)
        state.handle(.approach)
        #expect(state.handle(.approachExit) == [.releasePrewarm])

        // The pointer is on the island itself: the margin's exit must not release anything.
        state.handle(.hoverEnter)
        #expect(state.handle(.approachExit) == [])

        // Expanded: nothing to release.
        state.handle(.click)
        #expect(state.isExpanded)
        #expect(state.handle(.approachExit) == [])
    }

    @Test("A drag that starts from a press releases the prewarmed deck")
    func dragReleases() {
        var state = State(trigger: .click)
        state.handle(.approach)
        state.handle(.press)
        #expect(state.handle(.dragBegan) == [.cancelIntent, .cancelGrace, .releasePrewarm])
        #expect(!state.isExpanded)
    }

    @Test("Cancelling the hover intent no longer throws the deck away")
    func cancelIntentKeepsPrewarm() {
        var state = State(trigger: .hoverOrClick)
        state.handle(.hoverEnter)
        // Leaving cancels the timer and schedules a release, but the click path in between never releases.
        #expect(state.handle(.hoverExit) == [.cancelIntent, .releasePrewarm])
        state.handle(.hoverEnter)
        #expect(state.handle(.click) == [.cancelIntent, .cancelGrace, .prepare, .expand])
    }
}

/// Esc reaches Codometer while another app is active only for a deck the user explicitly pinned open (L4).
@Suite("Escape hot key")
struct EscapeHotKeyTests {
    private typealias State = IslandInteractionState

    @Test("Only a pinned deck arms the hot key")
    func pinnedOnly() {
        var state = State(trigger: .click)
        #expect(!state.wantsEscapeHotKey)
        state.handle(.hoverEnter)
        state.handle(.click)
        #expect(state.isPinned)
        #expect(state.wantsEscapeHotKey)
        state.handle(.escape)
        #expect(!state.wantsEscapeHotKey)
    }

    @Test("A deck opened by hover or by a peek never arms it")
    func hoverAndPeekNeverArm() {
        var hover = State(trigger: .hover)
        hover.handle(.hoverEnter)
        hover.handle(.intentElapsed)
        #expect(hover.isExpanded)
        #expect(!hover.wantsEscapeHotKey)
        // The local monitor still closes it while Codometer is active.
        #expect(hover.wantsEscapeMonitor)

        var peek = State(trigger: .click)
        peek.handle(.peekStart)
        #expect(peek.isExpanded)
        #expect(!peek.wantsEscapeHotKey)
    }

    @Test("The shortcut, a notification and a header click all pin, so all of them arm it")
    func pinningPaths() {
        var shortcut = State(trigger: .hover)
        shortcut.handle(.toggle)
        #expect(shortcut.wantsEscapeHotKey)

        var notification = State(trigger: .hover)
        notification.handle(.pin)
        #expect(notification.wantsEscapeHotKey)

        var header = State(trigger: .hoverOrClick)
        header.handle(.hoverEnter)
        header.handle(.intentElapsed)
        #expect(!header.wantsEscapeHotKey)
        header.handle(.headerClick)
        #expect(header.wantsEscapeHotKey)
    }

    @Test("A drag disarms it")
    func draggingDisarms() {
        var state = State(trigger: .click)
        state.handle(.click)
        #expect(state.wantsEscapeHotKey)
        state.handle(.dragBegan)
        #expect(!state.wantsEscapeHotKey)
    }
}
