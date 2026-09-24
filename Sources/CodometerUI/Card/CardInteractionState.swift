import Foundation

/// The floating card's states and the events that move between them, with no AppKit and no timers of its own.
///
/// The controller owns the window and the clocks; this type owns the rules, so every transition is testable. It
/// mirrors `IslandInteractionState` for the island.
///
/// There is no hover peek: the card peeks only when an alert asks it to.
public struct CardInteractionState: Equatable, Sendable {
    /// What is on screen.
    public enum Form: String, Equatable, Sendable, CaseIterable {
        case card
        case pill
    }

    public enum Phase: Equatable, Sendable {
        /// The card, until something minimizes it.
        case expanded
        /// The pill.
        case minimized
        /// The card for a few seconds after an alert, then the pill again.
        case peeking
        /// Being carried; the form underneath is remembered.
        case dragging(Form)
        /// Off screen: the style is not selected, or the island is hidden.
        case hidden
    }

    public enum Event: Equatable, Sendable {
        /// The surface appears, in the form the settings remember.
        case show(minimized: Bool)
        case hide
        /// The minimize button, the context menu, Esc or a VoiceOver action.
        case minimize
        /// The context menu or a VoiceOver action.
        case expand
        /// The global shortcut.
        case toggle
        /// A click that was not a drag: on the pill it restores, on the card it does nothing to the state.
        case click
        /// A double click on a non-interactive part of the card.
        case doubleClick
        /// A notification click: the card expands and stays.
        case openPinned
        /// An alert asked for a peek.
        case peekStart
        /// The peek's time is up.
        case peekElapsed
        /// The user touched the card during a peek, so it stays.
        case touched
        case dragBegan
        case dragEnded
    }

    public enum Effect: Equatable, Sendable {
        /// Remember the new minimized state in the settings (debounced by the controller).
        case persistMinimized(Bool)
        case startPeekTimer
        case cancelPeekTimer
        case orderFront
        /// Keyboard engagement ends on a minimize and on a drag.
        case endKeyboardEngagement
    }

    public private(set) var phase: Phase

    public init(phase: Phase = .hidden) {
        self.phase = phase
    }

    /// The form on screen right now; `nil` while hidden.
    public var form: Form? {
        switch phase {
        case .expanded, .peeking: .card
        case .minimized: .pill
        case .dragging(let form): form
        case .hidden: nil
        }
    }

    public var isExpanded: Bool { form == .card }
    public var isDragging: Bool {
        if case .dragging = phase { return true }
        return false
    }
    public var isHidden: Bool { phase == .hidden }
    /// A peek is running, so its timer may still fire.
    public var isPeeking: Bool { phase == .peeking }

    /// Applies one event and returns what the controller has to do.
    public mutating func handle(_ event: Event) -> [Effect] {
        switch event {
        case .show(let minimized):
            guard phase == .hidden else { return [] }
            phase = minimized ? .minimized : .expanded
            return []
        case .hide:
            guard phase != .hidden else { return [] }
            let wasPeeking = isPeeking
            phase = .hidden
            return wasPeeking ? [.cancelPeekTimer] : []
        case .minimize:
            switch phase {
            case .expanded, .peeking:
                let wasPeeking = isPeeking
                phase = .minimized
                // A peek that ends by itself leaves the settings alone; a minimize the user asked for is remembered.
                return (wasPeeking ? [.cancelPeekTimer] : [.persistMinimized(true)]) + [.endKeyboardEngagement]
            default:
                return []
            }
        case .expand:
            switch phase {
            case .minimized:
                phase = .expanded
                return [.persistMinimized(false), .orderFront]
            case .peeking:
                phase = .expanded
                return [.cancelPeekTimer, .persistMinimized(false)]
            default:
                return []
            }
        case .toggle:
            switch phase {
            case .expanded:
                phase = .minimized
                return [.persistMinimized(true), .endKeyboardEngagement, .orderFront]
            case .minimized:
                phase = .expanded
                return [.persistMinimized(false), .orderFront]
            case .peeking:
                phase = .expanded
                return [.cancelPeekTimer, .persistMinimized(false), .orderFront]
            case .dragging, .hidden:
                return []
            }
        case .click:
            switch phase {
            case .minimized:
                phase = .expanded
                return [.persistMinimized(false), .orderFront]
            case .peeking:
                phase = .expanded
                return [.cancelPeekTimer, .persistMinimized(false)]
            default:
                return []
            }
        case .doubleClick:
            switch phase {
            case .expanded:
                phase = .minimized
                return [.persistMinimized(true), .endKeyboardEngagement]
            case .peeking:
                phase = .minimized
                return [.cancelPeekTimer]
            default:
                // The pill's second click is ignored: the first one already restored the card.
                return []
            }
        case .openPinned:
            switch phase {
            case .minimized:
                phase = .expanded
                return [.persistMinimized(false), .orderFront]
            case .peeking:
                phase = .expanded
                return [.cancelPeekTimer, .persistMinimized(false), .orderFront]
            case .expanded:
                return [.orderFront]
            case .dragging, .hidden:
                return []
            }
        case .peekStart:
            switch phase {
            case .minimized:
                phase = .peeking
                return [.startPeekTimer, .orderFront]
            case .peeking:
                // Another alert during a peek restarts its clock.
                return [.startPeekTimer]
            default:
                return []
            }
        case .peekElapsed:
            guard phase == .peeking else { return [] }
            phase = .minimized
            return []
        case .touched:
            guard phase == .peeking else { return [] }
            phase = .expanded
            return [.cancelPeekTimer, .persistMinimized(false)]
        case .dragBegan:
            switch phase {
            case .expanded:
                phase = .dragging(.card)
                return [.endKeyboardEngagement]
            case .minimized:
                phase = .dragging(.pill)
                return [.endKeyboardEngagement]
            case .peeking:
                // A drag cancels the peek: the card stays the way the user is carrying it.
                phase = .dragging(.card)
                return [.cancelPeekTimer, .persistMinimized(false), .endKeyboardEngagement]
            case .dragging, .hidden:
                return []
            }
        case .dragEnded:
            guard case .dragging(let form) = phase else { return [] }
            phase = form == .card ? .expanded : .minimized
            return []
        }
    }
}
