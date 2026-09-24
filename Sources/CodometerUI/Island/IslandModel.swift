import CodometerCore
import CodometerL10n
import Foundation
import Observation
import SwiftUI

/// Which side (or centre) of the rail the deck keeps in place while it grows away from the screen edge.
public enum IslandAnchor: Equatable, Sendable {
    case topLeading, top, topTrailing
    /// Centred vertically on a rail at the left edge.
    case leading
    /// Centred vertically on a rail at the right edge.
    case trailing
    case bottomLeading, bottom, bottomTrailing

    public var alignment: Alignment {
        switch self {
        case .topLeading: .topLeading
        case .top: .top
        case .topTrailing: .topTrailing
        case .leading: .leading
        case .trailing: .trailing
        case .bottomLeading: .bottomLeading
        case .bottom: .bottom
        case .bottomTrailing: .bottomTrailing
        }
    }

    /// The same point as a unit point, e.g. for scaling content in from the anchor.
    public var unitPoint: UnitPoint {
        switch self {
        case .topLeading: .topLeading
        case .top: .top
        case .topTrailing: .topTrailing
        case .leading: .leading
        case .trailing: .trailing
        case .bottomLeading: .bottomLeading
        case .bottom: .bottom
        case .bottomTrailing: .bottomTrailing
        }
    }
}

public struct IslandLayout: Equatable, Sendable {
    public let edge: ScreenEdge
    public let anchor: IslandAnchor
    public let style: IslandStyle
    public let metrics: IslandMetrics
    /// Extra room on the attached side, e.g. the height of a display's camera housing, so content hanging from the
    /// top edge is never hidden behind it. The deck always keeps it; a rail fused with the notch sits **beside**
    /// the notch instead and drops it (`shoulderInsets`).
    public let edgeInset: CGFloat
    /// The camera notch of the display the island is on, when it has one.
    public let notch: NotchGeometry?
    /// The island is drawn split around the notch (`NotchFusion.isFused`).
    public let isNotchFused: Bool

    public init(
        edge: ScreenEdge,
        anchor: IslandAnchor,
        style: IslandStyle,
        metrics: IslandMetrics,
        edgeInset: CGFloat = 0,
        notch: NotchGeometry? = nil,
        isNotchFused: Bool = false
    ) {
        self.edge = edge
        self.anchor = anchor
        self.style = style
        self.metrics = metrics
        self.edgeInset = edgeInset
        self.notch = notch
        self.isNotchFused = isNotchFused
    }

    /// The layout for the user's appearance settings on a display described by `edgeInset` and `notch`.
    ///
    /// A fused island is always centred on the notch, so its anchor is `.top` whatever the saved offset.
    public init(appearance: AppearanceSettings, edgeInset: CGFloat = 0, notch: NotchGeometry? = nil, isDragging: Bool = false) {
        let fused = NotchFusion.isFused(
            mode: appearance.notchFusion,
            edge: appearance.edge,
            style: appearance.style,
            offset: appearance.offset.value,
            notch: notch,
            dragging: isDragging
        )
        self.init(
            edge: appearance.edge,
            anchor: fused ? .top : IslandGeometry.anchor(edge: appearance.edge, offset: appearance.offset.value),
            style: appearance.style,
            metrics: IslandMetrics(scale: appearance.scale.value),
            edgeInset: appearance.edge == .top && appearance.style == .attached ? edgeInset : 0,
            notch: notch,
            isNotchFused: fused
        )
    }

    /// The fused rail's dial diameter, which has to fit inside the menu bar.
    public var notchDialDiameter: CGFloat? {
        guard isNotchFused, let notch else { return nil }
        return NotchFusion.dialDiameter(
            railDial: metrics.railDial,
            menuBarHeight: notch.menuBarHeight,
            orbitMargin: metrics.orbitMargin
        )
    }
}

/// What the deck should bring into view when it opens.
public enum IslandDeckFocus: Equatable, Sendable {
    case overview
    /// Opened from the attention tab or the global shortcut while agents wait: show «Ждут вас» first.
    case attentionQueue
}

/// Something inside the island asks the window controller to act.
public enum IslandRequest: Equatable, Sendable {
    /// The attention tab on the rail was clicked.
    case openAttention
    /// An empty part of the deck header was clicked.
    case headerClick
}

/// Interaction state shared by the AppKit controller and the SwiftUI island.
@MainActor
@Observable
public final class IslandModel {
    public var isExpanded = false
    public var isDragging = false
    /// The carried island is locked onto a snap target: its rim lights up until it is dropped or pulled away.
    public var isSnapped = false
    /// The pointer rests on the island. The collapsed rail swells slightly, the first stage of its droplet. It is one of
    /// the outline's animated numbers, so whoever sets it animates it with the morph under way: `Motion.liquidSwell` at
    /// rest, `Motion.liquidOpen` while open, and not at all during a fold (set it once the fold has finished).
    public var isHovered = false
    public var selectedAccountID: AccountID?
    /// Briefly set when an event opens the island, to draw attention to one account.
    public var highlightedAccountID: AccountID?
    public var layout: IslandLayout
    /// Where the rail and the deck sit inside the island's canvas view (top-left coordinates). `nil` lays the
    /// island out from `layout.anchor` inside whatever space the view is offered, e.g. in previews.
    public var frames: IslandFrames?
    /// Appearance the island renders with instead of the store's settings; only the debug harness sets it.
    public var appearanceOverride: AppearanceSettings?
    /// Keeps a hidden, inert deck built while the island is about to open (hover intent, click) and until it has
    /// folded, so unfolding only reveals it; the window controller sets and clears it.
    public var prewarmsDeck = false
    /// Keeps the rail built (invisible, inert) under the open deck from the moment a fold is about to start until the
    /// fold has finished, so creating the rail (its rings, orbit layers and text) is never part of the fold's first
    /// frames; the window controller sets and clears it.
    public var prewarmsRail = false
    /// What the deck should reveal first; reset to `.overview` once the deck has folded.
    public var deckFocus: IslandDeckFocus = .overview
    /// The tallest the deck may be (shoulder and edge insets included) in its current place on screen; a taller
    /// deck must scroll its body inside this height. `nil` when unknown, e.g. in previews.
    public var maximumDeckHeight: CGFloat?
    /// The rings flying between the rail and the deck, or `nil` when nothing flies (Reduce Motion, a drag, or no
    /// account measured on both sides). Set without animation; only `flightProgress` animates.
    public var flight: [RingFlightPair]?
    /// 0 = the rings sit on the rail, 1 = on the deck. The window controller drives it inside the open and fold
    /// transactions, so the flight is one animated number.
    public var flightProgress: CGFloat = 0
    /// Where the live dials are. A plain class nobody observes: writing to it never invalidates a view.
    @ObservationIgnored public let anchors = RingAnchorSink()
    /// Receives requests from inside the island; without a handler the model toggles itself.
    @ObservationIgnored public var onRequest: (@MainActor (IslandRequest) -> Void)?

    public init(layout: IslandLayout) {
        self.layout = layout
    }

    /// The accounts whose real rings are hidden because a flying copy has taken their place.
    public var flightHiddenAccounts: Set<AccountID> {
        guard let flight else { return [] }
        return Set(flight.map(\.id))
    }

    public func request(_ request: IslandRequest) {
        if let onRequest {
            onRequest(request)
            return
        }
        switch request {
        case .openAttention:
            deckFocus = .attentionQueue
            isExpanded = true
        case .headerClick:
            isExpanded = false
        }
    }
}

/// Sizes the island reports so the window can be fitted before an animation starts.
public struct IslandSizes: Equatable, Sendable {
    public var rail: CGSize
    public var deck: CGSize

    public init(rail: CGSize, deck: CGSize) {
        self.rail = rail
        self.deck = deck
    }

    public static let zero = IslandSizes(rail: .zero, deck: .zero)
}

extension IslandOpenTrigger {
    /// Hovering over the rail opens the deck.
    public var opensOnHover: Bool { self != .click }
    /// A click keeps the deck open until an outside click, Esc or a click on its header.
    public var pinsOnClick: Bool { self != .hover }
}

/// Hover, click, drag, peek and shortcut input reduced to one decision: is the deck open, and does it stay
/// open when the pointer leaves (pinned)? Pure, so every rule is testable without windows or timers;
/// the controller turns the returned effects into timers, window changes and animations.
public struct IslandInteractionState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case collapsed
        case expanded(pinned: Bool)
    }

    public enum Event: Equatable, Sendable {
        case hoverEnter
        case hoverExit
        /// The hover-intent delay passed while the pointer stayed on the rail.
        case intentElapsed
        /// The collapse grace period passed after the pointer left.
        case graceElapsed
        /// The left button went down on the island. In click modes it starts building the deck, so the geometry
        /// changes in the first frame after the release instead of about 80 ms later (L1).
        case press
        /// The pointer entered the margin around the island (click modes only): start building the deck.
        case approach
        /// The pointer left that margin.
        case approachExit
        /// A press and release on the island that never became a drag.
        case click
        /// A click on an empty part of the deck header: closes a pinned deck, pins one opened by hover or peek.
        case headerClick
        case outsideClick
        case escape
        /// The global shortcut.
        case toggle
        /// Open and stay open whatever the trigger, e.g. after a click on a notification about an account.
        case pin
        case dragBegan
        case dragEnded(pointerInside: Bool)
        case peekStart
        case peekEnd
        case triggerChanged(IslandOpenTrigger)
        /// The controller could not open the deck (nothing measured yet).
        case expansionUnavailable
    }

    public enum Effect: Equatable, Sendable {
        /// Bring time-dependent text up to date and measure it before the deck may open.
        case prepare
        case startIntent
        /// Cancel the hover-intent timer. It no longer drops the prewarmed deck: a quick move in and out of the
        /// island must not throw away a build the next click needs (L1).
        case cancelIntent
        case startGrace
        case cancelGrace
        /// Let the hidden deck go, after the controller's release grace.
        case releasePrewarm
        case expand
        case collapse
    }

    public private(set) var phase: Phase = .collapsed
    public private(set) var isHovering = false
    public private(set) var isPeeking = false
    public private(set) var isDragging = false
    public private(set) var trigger: IslandOpenTrigger

    public init(trigger: IslandOpenTrigger) {
        self.trigger = trigger
    }

    public var isExpanded: Bool { phase != .collapsed }

    public var isPinned: Bool { phase == .expanded(pinned: true) }

    /// A click anywhere else closes a pinned deck, so the monitor exists only then.
    public var wantsOutsideClickMonitor: Bool { isPinned && !isDragging }

    /// Esc closes an open deck. Used while Codometer is active, where a local key monitor sees the key.
    public var wantsEscapeMonitor: Bool { isExpanded && !isDragging }

    /// Esc is armed as a scoped hot key only for a deck the user explicitly asked to stay open (a click, the
    /// shortcut, a notification or a header click). A hover-opened deck closes when the pointer leaves, so it never
    /// swallows an Esc meant for the app the user is typing in (L4).
    public var wantsEscapeHotKey: Bool { isPinned && !isDragging }

    @discardableResult
    public mutating func handle(_ event: Event) -> [Effect] {
        switch event {
        case .hoverEnter:
            isHovering = true
            guard !isDragging else { return [.cancelGrace] }
            guard phase == .collapsed else { return [.cancelGrace] }
            return trigger.opensOnHover ? [.cancelGrace, .prepare, .startIntent] : [.cancelGrace, .prepare]

        case .hoverExit:
            isHovering = false
            guard !isDragging, phase == .expanded(pinned: false), !isPeeking else {
                // Collapsed: the deck built for an opening that never came is let go after the release grace.
                return phase == .collapsed ? [.cancelIntent, .releasePrewarm] : [.cancelIntent]
            }
            return [.cancelIntent, .startGrace]

        case .press:
            // A click is 80–120 ms from down to up: building the deck now finishes before the release.
            guard !isDragging, phase == .collapsed, trigger.pinsOnClick else { return [] }
            return [.prepare]

        case .approach:
            guard !isDragging, phase == .collapsed, trigger.pinsOnClick else { return [] }
            return [.prepare]

        case .approachExit:
            guard !isDragging, phase == .collapsed, !isHovering else { return [] }
            return [.releasePrewarm]

        case .intentElapsed:
            guard phase == .collapsed, isHovering, !isDragging, trigger.opensOnHover else { return [] }
            phase = .expanded(pinned: false)
            return [.expand]

        case .graceElapsed:
            guard phase == .expanded(pinned: false), !isHovering, !isPeeking, !isDragging else { return [] }
            phase = .collapsed
            return [.collapse]

        case .click:
            guard !isDragging else { return [] }
            switch phase {
            case .collapsed:
                phase = .expanded(pinned: trigger.pinsOnClick)
                return [.cancelIntent, .cancelGrace, .prepare, .expand]
            case .expanded(pinned: false):
                guard trigger.pinsOnClick else { return [] }
                phase = .expanded(pinned: true)
                return [.cancelGrace]
            case .expanded(pinned: true):
                return []
            }

        case .headerClick:
            guard !isDragging, isExpanded, trigger.pinsOnClick else { return [] }
            // The header toggles: a deck opened by hover or peek gets pinned like any click; a pinned one closes.
            guard isPinned else { return handle(.click) }
            phase = .collapsed
            isPeeking = false
            return [.cancelIntent, .cancelGrace, .collapse]

        case .outsideClick, .escape:
            guard !isDragging, isExpanded else { return [] }
            phase = .collapsed
            isPeeking = false
            return [.cancelIntent, .cancelGrace, .collapse]

        case .toggle:
            guard !isDragging else { return [] }
            if isExpanded {
                phase = .collapsed
                isPeeking = false
                return [.cancelIntent, .cancelGrace, .collapse]
            }
            phase = .expanded(pinned: true)
            return [.cancelIntent, .cancelGrace, .prepare, .expand]

        case .pin:
            guard !isDragging else { return [] }
            // A deck the user asked for outlives a peek that happens to be running.
            isPeeking = false
            switch phase {
            case .collapsed:
                phase = .expanded(pinned: true)
                return [.cancelIntent, .cancelGrace, .prepare, .expand]
            case .expanded(pinned: false):
                phase = .expanded(pinned: true)
                return [.cancelGrace]
            case .expanded(pinned: true):
                return []
            }

        case .dragBegan:
            isDragging = true
            isPeeking = false
            guard isExpanded else { return [.cancelIntent, .cancelGrace, .releasePrewarm] }
            phase = .collapsed
            return [.cancelIntent, .cancelGrace, .releasePrewarm, .collapse]

        case .dragEnded(let pointerInside):
            // A drop never opens the deck by itself: the pointer has to leave and come back.
            isDragging = false
            isHovering = pointerInside
            return []

        case .peekStart:
            guard !isDragging else { return [] }
            isPeeking = true
            guard phase == .collapsed else { return [.cancelGrace] }
            phase = .expanded(pinned: false)
            return [.cancelGrace, .prepare, .expand]

        case .peekEnd:
            guard isPeeking else { return [] }
            isPeeking = false
            guard phase == .expanded(pinned: false), !isHovering, !isDragging else { return [] }
            phase = .collapsed
            return [.collapse]

        case .triggerChanged(let newTrigger):
            trigger = newTrigger
            guard phase == .expanded(pinned: true), !newTrigger.pinsOnClick else { return [] }
            phase = .expanded(pinned: false)
            return isHovering || isPeeking ? [] : [.startGrace]

        case .expansionUnavailable:
            guard isExpanded else { return [.releasePrewarm] }
            phase = .collapsed
            return [.releasePrewarm]
        }
    }
}

/// The parts of the island's context menu that depend on the presentation style and the connected displays,
/// as plain titles and check marks. Pure, so the menu's text is testable in both languages (`NSMenu` itself is
/// not reachable from the debug harness).
public enum IslandMenuPlan {
    /// One display in the "Move to Display ▸" submenu.
    public struct DisplayItem: Equatable, Sendable, Identifiable {
        public let id: DisplayID
        public let title: String
        /// The island is on this display now.
        public let isChecked: Bool

        public init(id: DisplayID, title: String, isChecked: Bool) {
            self.id = id
            self.title = title
            self.isChecked = isChecked
        }
    }

    /// "Switch to Floating Card" — the island's menu only ever offers the other style.
    public static func switchStyleTitle(l10n: Localizer) -> String {
        l10n.islandMenu.switchToFloatingCard
    }

    /// "Move to Display" — the submenu's own title.
    public static func moveToDisplayTitle(l10n: Localizer) -> String {
        l10n.displays.moveToDisplay
    }

    /// The submenu is offered only with more than one display connected.
    public static func showsDisplaySubmenu(displays: [DisplayDescriptor]) -> Bool {
        displays.count > 1
    }

    /// One item per connected display, in the order macOS reports them; a display without a name gets a placeholder.
    public static func displayItems(displays: [DisplayDescriptor], current: DisplayID?, l10n: Localizer) -> [DisplayItem] {
        displays.map { display in
            DisplayItem(
                id: display.id,
                title: display.name.isEmpty ? l10n.displays.unnamedDisplay : display.name,
                isChecked: display.id == current
            )
        }
    }
}
