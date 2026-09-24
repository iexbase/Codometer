@testable import CodometerUI
import Foundation
import Testing

/// The floating card's automaton: every event in every state, and the effects the controller has to run.
@Suite("Card interaction")
struct CardInteractionTests {
    private func state(_ phase: CardInteractionState.Phase) -> CardInteractionState {
        CardInteractionState(phase: phase)
    }

    @Test("A hidden card only reacts to being shown")
    func hiddenIgnoresEverything() {
        let events: [CardInteractionState.Event] = [
            .minimize, .expand, .toggle, .click, .doubleClick, .openPinned, .peekStart, .peekElapsed, .touched,
            .dragBegan, .dragEnded, .hide,
        ]
        for event in events {
            var card = state(.hidden)
            #expect(card.handle(event).isEmpty, "\(event)")
            #expect(card.phase == .hidden, "\(event)")
        }
        var card = state(.hidden)
        #expect(card.handle(.show(minimized: false)).isEmpty)
        #expect(card.phase == .expanded)
        var minimized = state(.hidden)
        #expect(minimized.handle(.show(minimized: true)).isEmpty)
        #expect(minimized.phase == .minimized)
    }

    @Test("Minimize, double-click, Esc and the shortcut all fold an expanded card and remember it")
    func minimizing() {
        for event in [CardInteractionState.Event.minimize, .doubleClick, .toggle] {
            var card = state(.expanded)
            let effects = card.handle(event)
            #expect(card.phase == .minimized, "\(event)")
            #expect(effects.contains(.persistMinimized(true)), "\(event)")
            #expect(effects.contains(.endKeyboardEngagement), "\(event)")
        }
    }

    @Test("A click on the pill, the shortcut and a notification all restore the card")
    func restoring() {
        for event in [CardInteractionState.Event.click, .toggle, .expand, .openPinned] {
            var card = state(.minimized)
            let effects = card.handle(event)
            #expect(card.phase == .expanded, "\(event)")
            #expect(effects.contains(.persistMinimized(false)), "\(event)")
        }
    }

    @Test("A second click on the pill is ignored: the first one already restored the card")
    func doubleClickOnPillIsIgnored() {
        var card = state(.minimized)
        _ = card.handle(.click)
        #expect(card.phase == .expanded)
        // The double-click arrives after the first click restored the card; it would otherwise fold it again.
        var pill = state(.minimized)
        #expect(pill.handle(.doubleClick).isEmpty)
        #expect(pill.phase == .minimized)
    }

    @Test("A single click on the expanded card changes nothing about its state")
    func clickOnCardKeepsItOpen() {
        var card = state(.expanded)
        #expect(card.handle(.click).isEmpty)
        #expect(card.phase == .expanded)
    }

    @Test("An alert peek shows the card for a while and folds it again, without touching the settings")
    func peekReturnsToTheMinimizedState() {
        var card = state(.minimized)
        let start = card.handle(.peekStart)
        #expect(card.phase == .peeking)
        #expect(start.contains(.startPeekTimer))
        #expect(!start.contains(.persistMinimized(false)))
        let end = card.handle(.peekElapsed)
        #expect(card.phase == .minimized)
        #expect(end.isEmpty)
    }

    @Test("Touching a peeking card keeps it open and remembers that")
    func touchDuringPeekPins() {
        var card = state(.peeking)
        let effects = card.handle(.touched)
        #expect(card.phase == .expanded)
        #expect(effects.contains(.cancelPeekTimer))
        #expect(effects.contains(.persistMinimized(false)))
    }

    @Test("Another alert during a peek restarts its clock instead of stacking")
    func peekRestarts() {
        var card = state(.peeking)
        let effects = card.handle(.peekStart)
        #expect(card.phase == .peeking)
        #expect(effects == [.startPeekTimer])
    }

    @Test("A drag cancels a peek and keeps the form it started in")
    func dragCancelsPeek() {
        var peeking = state(.peeking)
        let effects = peeking.handle(.dragBegan)
        #expect(peeking.phase == .dragging(.card))
        #expect(effects.contains(.cancelPeekTimer))
        #expect(effects.contains(.persistMinimized(false)))
        _ = peeking.handle(.dragEnded)
        #expect(peeking.phase == .expanded)

        var minimized = state(.minimized)
        _ = minimized.handle(.dragBegan)
        #expect(minimized.phase == .dragging(.pill))
        _ = minimized.handle(.dragEnded)
        #expect(minimized.phase == .minimized)
    }

    @Test("Nothing moves the card while it is being carried")
    func draggingIgnoresOtherEvents() {
        for form in CardInteractionState.Form.allCases {
            for event in [CardInteractionState.Event.minimize, .expand, .toggle, .click, .doubleClick, .peekStart, .openPinned] {
                var card = state(.dragging(form))
                #expect(card.handle(event).isEmpty, "\(form) \(event)")
                #expect(card.phase == .dragging(form), "\(form) \(event)")
            }
        }
    }

    @Test("Hiding cancels a running peek")
    func hidingCancelsThePeek() {
        var card = state(.peeking)
        #expect(card.handle(.hide) == [.cancelPeekTimer])
        #expect(card.phase == .hidden)
        var expanded = state(.expanded)
        #expect(expanded.handle(.hide).isEmpty)
        #expect(expanded.phase == .hidden)
    }

    @Test("The form on screen follows the phase")
    func formFollowsPhase() {
        #expect(state(.expanded).form == .card)
        #expect(state(.peeking).form == .card)
        #expect(state(.minimized).form == .pill)
        #expect(state(.dragging(.pill)).form == .pill)
        #expect(state(.hidden).form == nil)
        #expect(state(.dragging(.card)).isDragging)
        #expect(state(.peeking).isPeeking)
        #expect(state(.hidden).isHidden)
    }

    @Test("Every event in every state leaves the automaton in a state it knows")
    func totality() {
        let phases: [CardInteractionState.Phase] = [.expanded, .minimized, .peeking, .dragging(.card), .dragging(.pill), .hidden]
        let events: [CardInteractionState.Event] = [
            .show(minimized: false), .show(minimized: true), .hide, .minimize, .expand, .toggle, .click, .doubleClick,
            .openPinned, .peekStart, .peekElapsed, .touched, .dragBegan, .dragEnded,
        ]
        for phase in phases {
            for event in events {
                var card = state(phase)
                _ = card.handle(event)
                #expect(phases.contains(card.phase), "\(phase) + \(event) → \(card.phase)")
            }
        }
    }
}
