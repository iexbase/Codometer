import CodometerCore
import CodometerL10n
import CodometerPlatform
import CodometerUI
import AppKit
import SwiftUI
import os

/// Owns the island window: measures the SwiftUI content, opens and closes the deck on hover, click, shortcut
/// or peek, follows drags, snaps to edges, and fits the panel around the island.
///
/// How the island avoids ever jumping:
/// - The hosting view is a canvas the size of the screen that stays put while the panel around it changes;
///   SwiftUI places the island at `model.frames` in canvas coordinates. The panel is only a window onto the
///   canvas, so resizing it never moves anything on screen.
/// - Frames depend on the measured sizes and the placement, never on whether the deck is open, so expanding
///   and folding animate one pair of frames in one transaction and an interrupted fold simply retargets.
/// - Time-dependent text is refreshed and measured when the pointer arrives (hover-intent start) or right
///   before a click or shortcut opens the deck, synchronously, so the deck's size is final before it opens.
/// - The panel grows once before the deck opens and shrinks once after the fold has finished; any other frame
///   change keeps the previous frames covered until the animation between them is over.
@MainActor
final class IslandController {
    static let hoverIntentDelay: Duration = .milliseconds(130)
    static let collapseGrace: Duration = .milliseconds(320)
    /// Upper bound for the fold animation (`Motion.liquidFold`, visually about 0.35 s), in case its completion callback
    /// never arrives.
    static let foldFallback: Duration = .milliseconds(900)
    /// How long the panel keeps covering frames an animation is leaving.
    static let retainDuration: Duration = .milliseconds(750)
    /// How long a hidden, prewarmed deck is kept after the pointer left, so moving in and out of the island (or
    /// past it) never rebuilds it (L1).
    static let prewarmRelease: Duration = .milliseconds(1_500)

    /// Shape and size changes while the island is carried: quicker than `Motion.geometry` so it keeps up with the
    /// pointer, and critically damped like every geometry animation, so nothing overshoots its panel.
    static var carry: Animation? {
        Motion.reducesMotion ? nil : .spring(response: 0.3, dampingFraction: 1.0)
    }

    let model: IslandModel
    /// The connected displays, set by `AppController.refreshDisplays()`; without it the island uses the menu bar
    /// display, which is what a single-display Mac resolves to anyway.
    weak var screenCatalog: ScreenCatalog?

    private let store: TrackerStore
    private let panel = IslandPanel()
    private let hostingView: InteractiveHostingView<IslandRootView>
    /// Owned by `AppController`, which registers the global shortcut and routes it to the active surface.
    private let hotKeys: HotKeyService
    private var contextMenu: NSMenu?
    /// Snapping feedback; replaced by a recorder in tests.
    var haptics: (any HapticPerforming)?

    private var interaction: IslandInteractionState
    private var sizes = IslandSizes.zero
    private var hasPendingSizes = false
    /// The screen the canvas covers.
    private var screenFrame: CGRect = .zero
    /// How far the canvas is carried along with a drag.
    private var canvasShift: CGVector = .zero
    /// The placement `model.frames` was computed for.
    private var framesPlacement: Placement?
    /// Canvas rects the panel keeps covering until the animation leaving them has finished.
    private var retainedRect: CGRect?
    private var retainGeneration = 0
    /// The panel stays deck-sized until the fold animation has finished.
    private var holdsDeckFrame = false
    private var foldGeneration = 0
    private var dragAnchor: DragAnchor?
    /// Set when SwiftUI handled a press (attention tab, header), so the same press is not also an island click.
    private var requestHandledDuringPress = false

    /// Magnetic snapping while the island is carried.
    private var snapState = EdgeSnapState()
    /// What a drop would save: the snapped offset while a target is locked, the free offset otherwise.
    private var pendingDrop: (edge: ScreenEdge, offset: Double)?
    /// The display the carry is currently over.
    private var dragDisplay: DisplayID?
    /// Haptics played during the current carry, for the debug trace.
    private var dragHapticCount = 0

    private var intentTask: Task<Void, Never>?
    private var graceTask: Task<Void, Never>?
    private var foldTask: Task<Void, Never>?
    private var peekTask: Task<Void, Never>?
    private var retainTask: Task<Void, Never>?
    private var sizesTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var releaseTask: Task<Void, Never>?
    private var flightPlanTask: Task<Void, Never>?
    private var outsideClickMonitors: [Any] = []
    private var escapeMonitor: Any?
    private var activationObservers: [any NSObjectProtocol] = []

    #if DEBUG
    private var debugAppearance: AppearanceSettings?
    private var debugGeneral: GeneralSettings?
    /// A simulated camera notch, so the fused rail can be reviewed on a Mac without one.
    private var debugNotch: NotchGeometry?
    /// ⌘ held during a synthetic drag (bypasses snapping).
    private var debugCommandBypass = false
    #endif

    private struct Placement: Equatable {
        let edge: ScreenEdge
        let offset: EdgeOffset
        let style: IslandStyle
        let screen: CGRect
        let visible: CGRect
    }

    private struct DragAnchor {
        /// Where the press began, in screen coordinates.
        let press: NSPoint
        let shift: CGVector
    }

    init(store: TrackerStore, hotKeys: HotKeyService) {
        self.store = store
        self.hotKeys = hotKeys
        let appearance = store.settings.appearance
        model = IslandModel(layout: IslandLayout(
            appearance: appearance,
            edgeInset: Self.targetScreen()?.safeAreaInsets.top ?? 0
        ))
        interaction = IslandInteractionState(trigger: appearance.openTrigger)
        hostingView = InteractiveHostingView(rootView: IslandRootView(store: store, model: model) { _ in })

        haptics = TrackpadHaptics(isEnabled: { [weak store] in store?.settings.appearance.playsHaptics ?? false })
        hostingView.rootView = IslandRootView(store: store, model: model) { [weak self] sizes in
            self?.sizesChanged(sizes)
        }
        model.onRequest = { [weak self] request in self?.handle(request) }
        hostingView.onHover = { [weak self] inside in self?.hoverChanged(inside) }
        hostingView.onApproach = { [weak self] near in self?.approachChanged(near) }
        hostingView.onPress = { [weak self] in self?.pressed() }
        hostingView.onClick = { [weak self] in self?.clicked() }
        hostingView.onDragBegan = { [weak self] press, pointer in self?.dragBegan(pressedAt: press, pointer: pointer) }
        hostingView.onDragMoved = { [weak self] point in self?.dragMoved(to: point) }
        hostingView.onDragEnded = { [weak self] point in self?.dragEnded(at: point) }
        hostingView.onDoubleClick = { [weak self] in self?.store.actions.openSettings() }
        hostingView.contextMenu = { [weak self] in self?.makeContextMenu() ?? NSMenu() }
        // Only the controller sizes and places the canvas.
        hostingView.sizingOptions = []
        hostingView.safeAreaRegions = []
        hostingView.autoresizingMask = []

        let container = IslandContainerView(frame: .zero)
        container.addSubview(hostingView)
        panel.contentView = container
        #if DEBUG
        DebugWindows.register(panel, name: DebugWindows.island)
        #endif
    }

    private var appearance: AppearanceSettings {
        #if DEBUG
        if let debugAppearance { return debugAppearance }
        #endif
        return store.settings.appearance
    }

    private var general: GeneralSettings {
        #if DEBUG
        if let debugGeneral { return debugGeneral }
        #endif
        return store.settings.general
    }

    /// The island is the selected presentation style and the user shows it.
    private var isShown: Bool {
        let appearance = self.appearance
        return appearance.visibility == .always && appearance.presentationStyle == .island
    }

    private var canvas: CGRect {
        screenFrame.offsetBy(dx: canvasShift.dx, dy: canvasShift.dy)
    }

    /// Re-reads appearance and screen layout, then shows the island, or hides it when it is not the selected style or
    /// the user hid it.
    func applyAppearance() {
        let appearance = self.appearance
        if interaction.trigger != appearance.openTrigger {
            send(.triggerChanged(appearance.openTrigger))
        }

        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        if !appearance.hidesInFullScreen {
            behavior.insert(.fullScreenAuxiliary)
        }
        panel.collectionBehavior = behavior

        guard isShown, let screen = resolvedScreen else {
            hide()
            return
        }
        #if DEBUG
        if model.appearanceOverride != debugAppearance {
            model.appearanceOverride = debugAppearance
        }
        #endif
        guard !model.isDragging else { return }

        if screenFrame == .zero {
            screenFrame = screen.frame
            hostingView.frame = CGRect(origin: CGPoint(x: -screen.frame.width, y: -screen.frame.height), size: screen.frame.size)
        }
        let layout = IslandLayout(appearance: appearance, edgeInset: screen.safeAreaInsets.top, notch: notch(of: screen))
        // Turning the rail from a row into a column rebuilds its dials, and a dial that leaves the hierarchy clears
        // its anchor after the replacing one reported (see `RingAnchors.swift`): drop the
        // plan rather than fly from a stale box. The first fold after the move restores the anchors.
        if model.layout.edge.isHorizontal != layout.edge.isHorizontal {
            clearFlight()
        }
        if model.layout != layout {
            // Same edge: the shape morphs (e.g. attached ↔ floating). Another edge: the island just moves there.
            withAnimation(model.layout.edge == layout.edge ? Motion.geometry : nil) {
                model.layout = layout
            }
        }
        // Measure now (also the very first time, before the panel has any size), so the frames below use real sizes.
        // A setting changed from inside the island's own layout pass is measured by that pass instead, and its
        // sizes follow through `sizesChanged`.
        hostingView.layoutSubtreeIfAllowed()
        refreshFrames()
        panel.orderFrontRegardless()
        hostingView.setNeedsPointerRefresh()
    }

    /// Opens the deck on one account and keeps it open until an outside click, Esc or the header closes it, e.g.
    /// after a click on a notification. Returns `false` when the island cannot open: it is hidden, not on screen
    /// yet, or has nothing measured to open.
    @discardableResult
    func openPinned(accountID: AccountID) -> Bool {
        guard isShown, panel.isVisible else { return false }
        // The user is carrying the island: it cannot open now, and the popover must not pop up over the drag.
        guard !interaction.isDragging else { return true }
        model.selectedAccountID = accountID
        if !interaction.isExpanded, model.deckFocus != .overview {
            model.deckFocus = .overview
        }
        send(.pin)
        return interaction.isExpanded
    }

    /// Opens the island for a few seconds and draws attention to one account.
    func peek(accountID: AccountID, seconds: Int) {
        guard seconds > 0, isShown, !interaction.isDragging else { return }
        model.selectedAccountID = accountID
        withAnimation(Motion.snappy) {
            model.highlightedAccountID = accountID
        }
        send(.peekStart)
        peekTask?.cancel()
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            withAnimation(Motion.snappy) {
                model.highlightedAccountID = nil
            }
            send(.peekEnd)
        }
    }

    // MARK: - Interaction

    private func send(_ event: IslandInteractionState.Event) {
        let effects = interaction.handle(event)
        for effect in effects {
            perform(effect)
        }
        updateMonitors()
    }

    private func perform(_ effect: IslandInteractionState.Effect) {
        switch effect {
        case .prepare:
            prepare()
        case .startIntent:
            intentTask?.cancel()
            intentTask = Task { [weak self] in
                try? await Task.sleep(for: Self.hoverIntentDelay)
                guard !Task.isCancelled else { return }
                self?.send(.intentElapsed)
            }
        case .cancelIntent:
            // Only the timer: a quick move in and out never throws away a deck the next click needs (L1).
            intentTask?.cancel()
            intentTask = nil
        case .releasePrewarm:
            releasePrewarmAfterGrace()
        case .startGrace:
            graceTask?.cancel()
            graceTask = Task { [weak self] in
                try? await Task.sleep(for: Self.collapseGrace)
                guard !Task.isCancelled else { return }
                self?.send(.graceElapsed)
            }
        case .cancelGrace:
            graceTask?.cancel()
            graceTask = nil
        case .expand:
            expand()
        case .collapse:
            collapse()
        }
    }

    /// The interaction decides whether to open, then the rail swells a little under the pointer (the first stage of
    /// its droplet). The swell starts after `send`, whose prewarm lays the hidden deck out synchronously, so building
    /// the deck can never stall the swell's first frames.
    private func hoverChanged(_ inside: Bool) {
        send(inside ? .hoverEnter : .hoverExit)
        updateSwell()
    }

    /// The pointer entered or left the transparent margin around the island. In click modes that is the earliest
    /// honest sign the deck may be wanted, so it is built there instead of at mouse-up (L1).
    private func approachChanged(_ near: Bool) {
        send(near ? .approach : .approachExit)
    }

    /// The left button went down on the island: in click modes the deck is built during the 80–120 ms before the
    /// release, so the geometry changes in the first frame after it.
    private func pressed() {
        requestHandledDuringPress = false
        send(.press)
    }

    /// Brings the rail's hover swell in line with the pointer.
    ///
    /// The swell is one of the outline's animated numbers, and a new animation of the outline takes over every number
    /// of it that is still moving. So a resting rail swells with its own soft spring; while the deck is open or opening
    /// the swell (invisible there) changes with the opening's own spring, so the unfold keeps its exact course; and
    /// during a fold it waits until the fold has finished, so the fold keeps its course and its completion.
    private func updateSwell() {
        let swells = hostingView.isPointerInside && !interaction.isDragging && !model.isDragging
        guard model.isHovered != swells else { return }
        if model.isExpanded {
            withAnimation(Motion.liquidOpen) {
                model.isHovered = swells
            }
        } else if !holdsDeckFrame {
            withAnimation(Motion.liquidSwell) {
                model.isHovered = swells
            }
        }
    }

    private func clicked() {
        // SwiftUI may run a button's or the header's action after the release has been handled; give it that
        // turn first, so a press it handled (attention tab, header) is never also an island click.
        Task { @MainActor [weak self] in
            guard let self, !requestHandledDuringPress else { return }
            send(.click)
        }
    }

    private func handle(_ request: IslandRequest) {
        requestHandledDuringPress = true
        switch request {
        case .openAttention:
            if !store.attentionQueue.isEmpty {
                model.deckFocus = .attentionQueue
            }
            send(.click)
        case .headerClick:
            send(.headerClick)
        }
    }

    /// The global shortcut toggles the deck; `preferAttention` opens it on the agents waiting. `false` while the island
    /// is hidden, so the caller opens the popover instead.
    func toggleFromShortcut(preferAttention: Bool) -> Bool {
        guard isShown, panel.isVisible else { return false }
        if preferAttention, !interaction.isExpanded {
            model.deckFocus = .attentionQueue
        }
        send(.toggle)
        return true
    }

    /// Whether the island's panel is on screen.
    var isOnScreen: Bool {
        panel.isVisible
    }

    /// Folds an open deck and takes the island off screen.
    func hide() {
        peekTask?.cancel()
        releaseTask?.cancel()
        releaseTask = nil
        flightPlanTask?.cancel()
        flightPlanTask = nil
        if interaction.isExpanded {
            send(.escape)
        }
        hotKeys.setEscapeArmed(false)
        store.setStatusSurface(.islandDeck, visible: false)
        panel.orderOut(nil)
    }

    isolated deinit {
        activationObservers.forEach(NotificationCenter.default.removeObserver)
        outsideClickMonitors.forEach(NSEvent.removeMonitor)
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
    }

    /// Outside clicks close a pinned deck; Esc closes an open one. Monitors exist only while they matter.
    private func updateMonitors() {
        if interaction.wantsOutsideClickMonitor {
            if outsideClickMonitors.isEmpty {
                installOutsideClickMonitors()
            }
        } else if !outsideClickMonitors.isEmpty {
            outsideClickMonitors.forEach(NSEvent.removeMonitor)
            outsideClickMonitors.removeAll()
        }

        if interaction.wantsEscapeMonitor {
            if escapeMonitor == nil {
                // Key events reach a local monitor only while this app is active: the island's panel never
                // becomes key, so Esc works when Codometer is frontmost (e.g. after opening its settings).
                escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    let isEscape = event.keyCode == 53
                    guard isEscape else { return event }
                    let handled = MainActor.assumeIsolated { () -> Bool in
                        guard let self, self.interaction.isExpanded else { return false }
                        self.send(.escape)
                        return true
                    }
                    return handled ? nil : event
                }
            }
        } else if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
        updateEscapeHotKey()
    }

    /// Arms the scoped Esc hot key only while a **pinned** deck is open and Codometer is not the active app: the
    /// local monitor above already sees Esc while it is (L4).
    ///
    /// Carbon delivers only Esc and consumes it, so nothing else the user types is ever seen. A deck opened by
    /// hover is never armed, so an Esc meant for the app they are typing in is never swallowed.
    private func updateEscapeHotKey() {
        let wants = interaction.wantsEscapeHotKey && !NSApp.isActive && panel.isVisible
        guard wants != hotKeys.isEscapeArmed else {
            updateActivationObservers()
            return
        }
        if wants {
            hotKeys.onEscape = { [weak self] in
                guard let self, interaction.isExpanded else { return }
                hotKeys.setEscapeArmed(false)
                send(.escape)
            }
            hotKeys.setEscapeArmed(true)
        } else {
            hotKeys.setEscapeArmed(false)
        }
        updateActivationObservers()
    }

    /// Watches activation only while a pinned deck is open, so becoming active hands Esc back to the local monitor
    /// and resigning arms the hot key again.
    private func updateActivationObservers() {
        let wants = interaction.wantsEscapeHotKey
        guard wants != !activationObservers.isEmpty else { return }
        guard wants else {
            activationObservers.forEach(NotificationCenter.default.removeObserver)
            activationObservers.removeAll()
            return
        }
        let center = NotificationCenter.default
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            activationObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.updateEscapeHotKey()
                }
            })
        }
    }

    private func installOutsideClickMonitors() {
        // Clicks in other apps: mouse monitors need no Accessibility permission.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated {
                self?.send(.outsideClick)
            }
        }) {
            outsideClickMonitors.append(global)
        }
        // Clicks in this app's other windows (settings, the menu bar popover).
        let panelNumber = panel.windowNumber
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            let isElsewhere = event.windowNumber != panelNumber
            if isElsewhere {
                MainActor.assumeIsolated {
                    self?.send(.outsideClick)
                }
            }
            return event
        }) {
            outsideClickMonitors.append(local)
        }
    }

    // MARK: - Measuring and frames

    private func sizesChanged(_ newSizes: IslandSizes) {
        guard newSizes != sizes else { return }
        sizes = newSizes
        hasPendingSizes = true
        // Called during SwiftUI's layout: apply on the next turn unless someone flushes sooner.
        sizesTask?.cancel()
        sizesTask = Task { [weak self] in
            guard let self, !Task.isCancelled, hasPendingSizes else { return }
            refreshFrames()
        }
    }

    /// Lays out pending SwiftUI changes now and applies any sizes they produced. Inside the canvas's own layout pass
    /// that pass lays them out, and the sizes it produces arrive through `sizesChanged` on the next turn.
    private func flushLayout() {
        hostingView.layoutSubtreeIfAllowed()
        if hasPendingSizes {
            refreshFrames()
        }
    }

    /// Refreshes time-dependent text and measures it, so a deck about to open already has its final size.
    private func prepare() {
        releaseTask?.cancel()
        releaseTask = nil
        store.tick(Date())
        // Build the hidden deck now, while nothing moves, instead of in the first frame of the unfold.
        setPrewarmsDeck(true)
        flushLayout()
        // The prewarmed deck has just been laid out, so its ring boxes are fresh: build the flight's views now too,
        // invisible at progress 0, instead of in the unfold's first frame.
        planFlight()
        // A gauge reports its box through `onGeometryChange`, which SwiftUI delivers *after* the layout pass, so a
        // deck (or a rail on a new edge) laid out just now has not reported yet. Plan again on the next turn, well
        // before the click that opens the deck arrives.
        scheduleFlightPlan()
    }

    /// One coalesced re-plan on the next turn, for anchors that land after the layout pass.
    private func scheduleFlightPlan() {
        guard flightPlanTask == nil else { return }
        flightPlanTask = Task { [weak self] in
            guard let self else { return }
            flightPlanTask = nil
            guard !model.isExpanded, model.prewarmsDeck || model.prewarmsRail else { return }
            planFlight()
        }
    }

    /// Lets a hidden, prewarmed deck go — but only after a grace, so a pointer passing by the island does not make
    /// the next click rebuild it (L1).
    private func releasePrewarmAfterGrace() {
        guard model.prewarmsDeck || model.flight != nil else { return }
        releaseTask?.cancel()
        releaseTask = Task { [weak self] in
            try? await Task.sleep(for: Self.prewarmRelease)
            guard !Task.isCancelled, let self else { return }
            releaseTask = nil
            guard !model.isExpanded, !holdsDeckFrame, !interaction.isExpanded else { return }
            setPrewarmsDeck(false)
            clearFlight()
        }
    }

    // MARK: - Ring flight

    /// Ring flight is switched off for 1.0: the enlarged rings start from the rail's tightly packed positions, so the
    /// deck's big dials overlapped each other for a moment before settling — a visible glitch on every open.
    /// The planner and the layer stay in place for a later, reworked version.
    static let ringFlightEnabled = false

    /// Whether rings may fly at all: never with Reduce Motion (the design's rule), never while the island is carried.
    private var allowsFlight: Bool {
        Self.ringFlightEnabled
            && !Motion.reducesMotion && !model.isDragging && !interaction.isDragging && store.allowsLiveEffects
    }

    /// Recomputes the rail ↔ deck pairs from the anchors the live dials reported.
    ///
    /// Cheap: a dictionary lookup per visible account. Set without animation — only `flightProgress` animates.
    private func planFlight() {
        guard allowsFlight else {
            clearFlight()
            return
        }
        let anchors = model.anchors
        let pairs = RingFlightPlanner.pairs(
            rail: anchors.rail,
            deck: anchors.deck,
            deckViewport: anchors.deckViewport,
            order: store.visiblePresentations.map(\.id)
        )
        guard model.flight != pairs else { return }
        withoutAnimation {
            model.flight = pairs.isEmpty ? nil : pairs
        }
    }

    private func clearFlight() {
        guard model.flight != nil else { return }
        withoutAnimation {
            model.flight = nil
        }
    }

    private func setPrewarmsDeck(_ prewarms: Bool) {
        guard model.prewarmsDeck != prewarms else { return }
        withoutAnimation {
            model.prewarmsDeck = prewarms
        }
    }

    private func setPrewarmsRail(_ prewarms: Bool) {
        guard model.prewarmsRail != prewarms else { return }
        withoutAnimation {
            model.prewarmsRail = prewarms
        }
    }

    /// Recomputes where the rail and deck sit for the current sizes and placement.
    private func refreshFrames() {
        hasPendingSizes = false
        guard sizes.rail != .zero, let screen = resolvedScreen else { return }
        if model.isDragging {
            refreshDragFrames()
            return
        }
        let rebased = rebaseCanvas(onto: screen.frame)
        let appearance = self.appearance
        let placement = Placement(
            edge: appearance.edge,
            offset: appearance.offset,
            style: appearance.style,
            screen: screen.frame,
            visible: screen.visibleFrame
        )
        let area = IslandGeometry.area(edge: placement.edge, style: placement.style, screen: placement.screen, visible: placement.visible)
        let maximumDeckHeight = IslandGeometry.maximumDeckHeight(style: placement.style, in: area)
        if model.maximumDeckHeight != maximumDeckHeight {
            // Changes only with the screen or placement; the deck re-measures and the frames follow on the next pass.
            withoutAnimation {
                model.maximumDeckHeight = maximumDeckHeight
            }
        }
        let onScreen = IslandGeometry.frames(
            sizes: sizes,
            edge: placement.edge,
            offset: placement.offset.value,
            style: placement.style,
            in: area,
            fusedNotch: model.layout.isNotchFused ? model.layout.notch : nil
        )
        let canvas = self.canvas
        let frames = IslandFrames(
            rail: IslandGeometry.local(onScreen.rail, in: canvas),
            deck: IslandGeometry.local(onScreen.deck, in: canvas)
        )
        let previous = model.frames
        let samePlace = framesPlacement.map { $0.edge == placement.edge && $0.offset == placement.offset && $0.screen == placement.screen } ?? false
        framesPlacement = placement
        guard frames != previous else {
            syncWindow()
            return
        }
        if let previous, rebased || samePlace, Motion.geometry != nil {
            // Sizes changed in place, or the island glides from where it was dropped: animate, with the panel
            // covering both the old and the new frames until the animation is over.
            retain(visibleRects(of: previous))
            withAnimation(Motion.geometry) {
                model.frames = frames
            }
        } else {
            withoutAnimation {
                model.frames = frames
            }
        }
        syncWindow()
    }

    /// While carried, the rail keeps its centre and only changes size (e.g. when it turns to a side edge).
    private func refreshDragFrames() {
        guard let current = model.frames else { return }
        let center = CGPoint(x: current.rail.midX, y: current.rail.midY)
        let rail = IslandGeometry.rect(centeredAt: center, size: sizes.rail)
        let frames = IslandFrames(rail: rail, deck: rail)
        guard frames != current else { return }
        retain([current.rail])
        withAnimation(Self.carry) {
            model.frames = frames
        }
        syncWindow()
    }

    /// Moves the canvas back onto `screen` after a drag (or onto a changed screen), converting every frame so
    /// nothing moves on screen. Returns whether anything was converted.
    private func rebaseCanvas(onto screen: CGRect) -> Bool {
        let old = canvas
        screenFrame = screen
        canvasShift = .zero
        let new = canvas
        guard old != new else { return false }
        func convert(_ rect: CGRect) -> CGRect {
            IslandGeometry.local(IslandGeometry.screen(rect, in: old), in: new)
        }
        if let frames = model.frames {
            withoutAnimation {
                model.frames = IslandFrames(rail: convert(frames.rail), deck: convert(frames.deck))
            }
        }
        retainedRect = retainedRect.map(convert)
        syncWindow()
        return model.frames != nil
    }

    private func visibleRects(of frames: IslandFrames) -> [CGRect] {
        model.isExpanded || holdsDeckFrame ? [frames.rail, frames.deck] : [frames.rail]
    }

    private func retain(_ rects: [CGRect]) {
        guard let first = rects.first else { return }
        let union = rects.dropFirst().reduce(first) { $0.union($1) }
        retainedRect = retainedRect.map { $0.union(union) } ?? union
        retainGeneration += 1
        let generation = retainGeneration
        retainTask?.cancel()
        retainTask = Task { [weak self] in
            try? await Task.sleep(for: Self.retainDuration)
            guard !Task.isCancelled, let self, generation == retainGeneration else { return }
            retainedRect = nil
            syncWindow()
        }
    }

    /// The single place that fits the panel and the canvas inside it to the island's current state.
    private func syncWindow() {
        guard !hostingView.isLayingOut else {
            // Moving the canvas or the panel lays the canvas out again, which is illegal inside its own layout pass
            // (where SwiftUI runs some callbacks): fit it on the next turn, from the state at that time.
            syncWindowSoon()
            return
        }
        guard let frames = model.frames, screenFrame != .zero else { return }
        let canvas = self.canvas
        var rects = [frames.rail]
        if !model.isDragging, model.isExpanded || holdsDeckFrame {
            rects.append(frames.deck)
        }
        if let retainedRect {
            rects.append(retainedRect)
        }
        let layout = model.layout
        let reach = model.isDragging ? max(sizes.rail.width, sizes.rail.height) + layout.metrics.windowMargin : 0
        // A carried island may travel across every connected display, so the clamp is their union, not the display
        // it started on.
        let bounds = model.isDragging ? dragBounds : screenFrame
        let frame = IslandGeometry.panelFrame(
            containing: rects.map { IslandGeometry.screen($0, in: canvas) },
            edge: layout.edge,
            attached: layout.style == .attached && !model.isDragging,
            margin: layout.metrics.windowMargin,
            within: bounds.insetBy(dx: -reach, dy: -reach)
        )
        guard frame.width > 0, frame.height > 0 else { return }

        let canvasFrame = CGRect(x: canvas.minX - frame.minX, y: canvas.minY - frame.minY, width: canvas.width, height: canvas.height)
        if hostingView.frame != canvasFrame {
            hostingView.frame = canvasFrame
        }
        // Apply pending SwiftUI changes before the panel moves, so both land in the same frame (a layout pass already
        // in progress applies them itself).
        hostingView.layoutSubtreeIfAllowed()
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
            AppLog.interface.debug("island panel \(frame.debugDescription, privacy: .public) expanded=\(self.model.isExpanded, privacy: .public)")
        }
        updateInteractiveRect()
    }

    private func syncWindowSoon() {
        guard syncTask == nil else { return }
        syncTask = Task { [weak self] in
            guard let self else { return }
            syncTask = nil
            syncWindow()
        }
    }

    private func updateInteractiveRect() {
        guard let frames = model.frames else { return }
        let shape = model.isDragging ? frames.rail : frames.frame(expanded: model.isExpanded)
        hostingView.interactiveRect = IslandGeometry.viewRect(shape, boundsHeight: hostingView.bounds.height, isFlipped: hostingView.isFlipped)
        // The approach area lives in the panel's own transparent margin, only while a click could open the deck.
        let wantsApproach = !model.isExpanded && !model.isDragging && interaction.trigger.pinsOnClick
        hostingView.approachMargin = wantsApproach ? model.layout.metrics.windowMargin : 0
    }

    private func withoutAnimation(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }

    // MARK: - Expand and collapse

    private func expand() {
        // Anything measured since the pointer arrived is applied before the panel grows.
        flushLayout()
        guard !model.isExpanded, !model.isDragging, sizes.deck != .zero, model.frames != nil else {
            if !model.isExpanded {
                for effect in interaction.handle(.expansionUnavailable) {
                    perform(effect)
                }
                updateMonitors()
                // A shortcut or attention click asked for the queue; a later hover must open the overview.
                if model.deckFocus != .overview, !holdsDeckFrame {
                    model.deckFocus = .overview
                }
            }
            return
        }
        foldGeneration += 1
        let generation = foldGeneration
        foldTask?.cancel()
        releaseTask?.cancel()
        releaseTask = nil
        // Anchors may have moved since the prewarm (a data update): recompute before the transaction.
        planFlight()
        // Grow the panel once, before anything moves; the canvas keeps the rail where it is.
        holdsDeckFrame = true
        syncWindow()
        withAnimation(Motion.liquidOpen) {
            // A rail kept for an interrupted fold leaves with its own fade, like a rail that was never prewarmed.
            model.prewarmsRail = false
            model.isExpanded = true
            // One animated number carries every flying ring from the rail to the deck.
            model.flightProgress = 1
        } completion: { [weak self] in
            // Like the fold's completion, SwiftUI runs this inside the hosting view's layout pass. The criterion is
            // the default (`.removed`), not `.logicallyComplete`: a spring is logically done before its last frames,
            // and swapping the real rings in then would be a visible pop.
            Task { @MainActor [weak self] in
                self?.finishFlight(generation: generation)
            }
        }
        store.setStatusSurface(.islandDeck, visible: true)
        // A swell that waited for an interrupted fold follows the opening's spring.
        updateSwell()
        updateInteractiveRect()
    }

    private func collapse() {
        guard model.isExpanded, !interaction.isDragging else { return }
        foldGeneration += 1
        let generation = foldGeneration
        // Build the rail first, invisible under the deck and before anything moves (like the prewarmed deck before an
        // opening). Inserted in the fold's own transaction, creating it (rings, orbit layers, text) held the fold's first
        // frame back by about 35 ms in an optimized build; prewarmed, that frame takes about 12 ms, like an opening's.
        setPrewarmsRail(true)
        flushLayout()
        // The rail is laid out again, so its ring boxes are fresh: the rings fly back into it.
        planFlight()
        withAnimation(Motion.liquidFold, completionCriteria: .logicallyComplete) {
            model.isExpanded = false
            model.flightProgress = 0
        } completion: { [weak self] in
            // SwiftUI runs animation completions inside the hosting view's layout pass, where the panel must not be
            // refitted (that lays the view out again): finish on the next turn.
            Task { @MainActor [weak self] in
                self?.finishFold(generation: generation)
            }
        }
        updateInteractiveRect()
        foldTask?.cancel()
        foldTask = Task { [weak self] in
            try? await Task.sleep(for: Self.foldFallback)
            guard !Task.isCancelled else { return }
            self?.finishFold(generation: generation)
        }
    }

    /// Drops the flying rings once the open that started them has landed; the real deck dials take over at exactly
    /// the same boxes, so nothing moves.
    private func finishFlight(generation: Int) {
        guard generation == foldGeneration, model.isExpanded else { return }
        clearFlight()
    }

    /// Shrinks the panel back to the rail once the fold that started it has finished.
    private func finishFold(generation: Int) {
        guard generation == foldGeneration, !model.isExpanded, holdsDeckFrame else { return }
        holdsDeckFrame = false
        store.setStatusSurface(.islandDeck, visible: false)
        if model.deckFocus != .overview {
            model.deckFocus = .overview
        }
        setPrewarmsDeck(false)
        setPrewarmsRail(false)
        // The flying rings are back on the rail: swapping the real ones in at the same box is invisible.
        clearFlight()
        syncWindow()
        // The pointer may have come or gone during the fold.
        updateSwell()
    }

    // MARK: - Dragging

    private func dragBegan(pressedAt press: NSPoint, pointer: NSPoint) {
        peekTask?.cancel()
        let wasExpanded = model.isExpanded
        send(.dragBegan)
        guard let frames = model.frames, let screen = resolvedScreen else { return }
        _ = rebaseCanvas(onto: screen.frame)
        // A carried island is a free capsule: no flight, no snap lock, and the carry rewrites the frames anyway.
        snapState = EdgeSnapState()
        pendingDrop = nil
        dragHapticCount = 0
        dragDisplay = screenCatalog.flatMap { catalog in
            DisplaySelection.display(at: pointer, in: catalog.displays)?.id
        }
        clearFlight()
        withoutAnimation {
            model.flightProgress = 0
            model.isSnapped = false
        }
        let current = model.frames ?? frames
        dragAnchor = DragAnchor(press: press, shift: canvasShift)
        foldGeneration += 1
        foldTask?.cancel()

        // The rail stays under the pointer if it already is; a deck folds into a capsule at the pointer.
        let pressInCanvas = IslandGeometry.local(CGRect(origin: press, size: .zero), in: canvas).origin
        var rail = current.rail
        if wasExpanded || !rail.insetBy(dx: -2, dy: -2).contains(pressInCanvas) {
            rail = IslandGeometry.rect(centeredAt: pressInCanvas, size: sizes.rail)
        }
        retain(wasExpanded || holdsDeckFrame ? [current.rail, current.deck] : [current.rail])
        holdsDeckFrame = false
        store.setStatusSurface(.islandDeck, visible: false)
        // The fold this drag interrupts never finishes, so reset what its completion would have reset.
        if model.deckFocus != .overview {
            model.deckFocus = .overview
        }
        withAnimation(Self.carry) {
            model.highlightedAccountID = nil
            model.isExpanded = false
            model.isHovered = false
            model.prewarmsDeck = false
            model.prewarmsRail = false
            model.isDragging = true
            model.frames = IslandFrames(rail: rail, deck: rail)
        }
        dragMoved(to: pointer)
    }

    private func dragMoved(to point: NSPoint) {
        guard let anchor = dragAnchor else { return }
        let target = dropTarget(at: point)
        guard let screenFrame = target.frame, let visibleFrame = target.visibleFrame else { return }
        // The carried capsule stays under the pointer; the magnet only adds a pull on top of the pointer delta.
        let pointerShift = CGVector(dx: anchor.shift.dx + point.x - anchor.press.x, dy: anchor.shift.dy + point.y - anchor.press.y)
        let placement = IslandGeometry.placement(
            for: point,
            railSize: sizes.rail,
            style: appearance.style,
            screen: screenFrame,
            visible: visibleFrame
        )
        let previousEdge = model.layout.edge
        let resolution = resolveSnapping(
            pointer: point,
            placement: placement,
            screen: screenFrame,
            visible: visibleFrame,
            notch: target.notch
        )
        canvasShift = CGVector(dx: pointerShift.dx + resolution.displayShift.dx, dy: pointerShift.dy + resolution.displayShift.dy)
        pendingDrop = (placement.edge, resolution.dropOffset)

        if let display = target.display, display != dragDisplay {
            dragDisplay = display
            play(.displayChange)
        }
        if let haptic = resolution.haptic {
            play(haptic)
        } else if placement.edge != previousEdge {
            play(.edgeChange)
        }
        let snapped = resolution.locked != nil
        if model.isSnapped != snapped {
            withAnimation(Motion.content) {
                model.isSnapped = snapped
            }
        }

        // While carried, the island is a free capsule that turns to match the edge it will land on.
        let layout = IslandLayout(
            edge: placement.edge,
            anchor: IslandGeometry.anchor(edge: placement.edge, offset: resolution.dropOffset),
            style: .floating,
            metrics: model.layout.metrics,
            notch: target.notch
        )
        if layout != model.layout {
            withAnimation(Self.carry) {
                model.layout = layout
            }
            flushLayout()
        }
        syncWindow()
    }

    /// The snapping resolution for one pointer sample, or a free carry when the user turned snapping off or holds ⌘.
    private func resolveSnapping(
        pointer: NSPoint,
        placement: (edge: ScreenEdge, offset: Double),
        screen: CGRect,
        visible: CGRect,
        notch: NotchGeometry?
    ) -> EdgeSnapResolution {
        let appearance = self.appearance
        let style = appearance.style
        let area = IslandGeometry.area(edge: placement.edge, style: style, screen: screen, visible: visible)
        let railLength = max(sizes.rail.width, sizes.rail.height)
        guard appearance.snapsWhileDragging else {
            snapState = EdgeSnapState()
            return EdgeSnapResolution(displayShift: .zero, dropOffset: placement.offset, state: snapState, haptic: nil, locked: nil)
        }
        let targets = EdgeSnapping.targets(
            edge: placement.edge,
            railLength: railLength,
            area: area,
            style: style,
            notch: appearance.notchFusion == .automatic ? notch : nil,
            scale: appearance.scale.value
        )
        let resolution = EdgeSnapping.resolve(
            pointer: pointer,
            placement: placement,
            targets: targets,
            area: area,
            railLength: railLength,
            style: style,
            state: snapState,
            now: ProcessInfo.processInfo.systemUptime,
            bypass: bypassesSnapping
        )
        snapState = resolution.state
        return resolution
    }

    /// ⌘ held: the carry ignores the magnet completely. Read from the modifier flags at each sample, so no event
    /// monitor is needed.
    private var bypassesSnapping: Bool {
        #if DEBUG
        if debugCommandBypass { return true }
        #endif
        return NSEvent.modifierFlags.contains(.command)
    }

    /// Plays a haptic and counts it for the debug trace.
    private func play(_ haptic: SnapHaptic) {
        dragHapticCount += 1
        haptics?.perform(haptic)
    }

    /// The display a drop would land on, with the frames placement should use.
    private func dropTarget(at point: NSPoint) -> (display: DisplayID?, frame: CGRect?, visibleFrame: CGRect?, notch: NotchGeometry?) {
        let appearance = self.appearance
        if let screenCatalog,
           let target = screenCatalog.dropTarget(
               at: point,
               policy: appearance.islandDisplayPolicy,
               remembered: appearance.islandDisplay
           ) {
            #if DEBUG
            if let debugNotch {
                return (target.id, target.frame, target.visibleFrame, debugNotch)
            }
            #endif
            return (target.id, target.frame, target.visibleFrame, target.notch)
        }
        guard let screen = resolvedScreen else { return (nil, nil, nil, nil) }
        return (nil, screen.frame, screen.visibleFrame, notch(of: screen))
    }

    private func dragEnded(at point: NSPoint) {
        dragAnchor = nil
        let target = dropTarget(at: point)
        guard let screenFrame = target.frame, let visibleFrame = target.visibleFrame else {
            model.isDragging = false
            model.isSnapped = false
            send(.dragEnded(pointerInside: hostingView.isPointerInside))
            return
        }
        let free = IslandGeometry.placement(
            for: point,
            railSize: sizes.rail,
            style: appearance.style,
            screen: screenFrame,
            visible: visibleFrame
        )
        // Exactly 0, 0.5 or 1 while a target was locked; the free offset otherwise.
        let placement = pendingDrop?.edge == free.edge ? (edge: free.edge, offset: pendingDrop?.offset ?? free.offset) : free
        model.isDragging = false
        model.isSnapped = false
        pendingDrop = nil
        snapState = EdgeSnapState()
        send(.dragEnded(pointerInside: hostingView.isPointerInside))
        #if DEBUG
        if debugAppearance != nil {
            debugAppearance?.edge = placement.edge
            debugAppearance?.offset = EdgeOffset.clamped(placement.offset)
            applyAppearance()
            return
        }
        #endif
        let remembered = target.display.flatMap { id in screenCatalog?.displays.first { $0.id == id }?.remembered }
        store.updateSettings { settings in
            settings.appearance.edge = placement.edge
            settings.appearance.offset = EdgeOffset.clamped(placement.offset)
            // "Where I leave it" remembers the display it was dropped on, so a reconnect brings it back there.
            if settings.appearance.islandDisplayPolicy == .whereLeft, let remembered {
                settings.appearance.islandDisplay = remembered
            }
        }
        applyAppearance()
    }

    // MARK: - Context menu

    /// Built on every right click, so the titles follow the current language.
    private func makeContextMenu() -> NSMenu {
        let l10n = store.localizer
        let menu = NSMenu()
        menu.addItem(ActionMenuItem(l10n.menu.refreshAll, systemImage: "arrow.clockwise") { [weak self] in
            self?.store.refresh()
        })
        menu.addItem(ActionMenuItem(l10n.menu.settings, systemImage: "gearshape") { [weak self] in
            self?.store.actions.openSettings()
        })
        menu.addItem(.separator())

        let appearance = store.settings.appearance
        if !store.settings.groups.isEmpty {
            menu.addItem(submenuItem(l10n.islandMenu.show, systemImage: "person.2", items: showItems(appearance: appearance, l10n: l10n)))
        }
        menu.addItem(submenuItem(l10n.islandMenu.expand, systemImage: "cursorarrow.rays", items: openItems(appearance: appearance, l10n: l10n)))
        menu.addItem(submenuItem(l10n.islandMenu.placement, systemImage: "rectangle.dashed", items: placementItems(appearance: appearance, l10n: l10n)))
        if IslandMenuPlan.showsDisplaySubmenu(displays: store.displays) {
            menu.addItem(submenuItem(
                IslandMenuPlan.moveToDisplayTitle(l10n: l10n),
                systemImage: "display.2",
                items: displayItems(l10n: l10n)
            ))
        }
        menu.addItem(ActionMenuItem(IslandMenuPlan.switchStyleTitle(l10n: l10n), systemImage: "rectangle.on.rectangle") { [weak self] in
            self?.store.actions.switchPresentationStyle(.floatingCard)
        })

        menu.addItem(ActionMenuItem(l10n.menu.hideIsland, systemImage: "eye.slash") { [weak self] in
            self?.store.updateSettings { $0.appearance.visibility = .hidden }
        })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(l10n.menu.quit, systemImage: "power") { [weak self] in
            self?.store.actions.quit()
        })
        // Keep the menu (and the items that are their own targets) alive until the chosen action has run.
        contextMenu = menu
        return menu
    }

    private func submenuItem(_ title: String, systemImage: String, items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
        let submenu = NSMenu()
        items.forEach(submenu.addItem)
        item.submenu = submenu
        return item
    }

    /// "All Accounts", then every group by its own name (user data, never translated).
    private func showItems(appearance: AppearanceSettings, l10n: Localizer) -> [NSMenuItem] {
        var items: [NSMenuItem] = [
            ActionMenuItem(l10n.islandMenu.allAccounts, isChecked: appearance.railGroupFilter == nil) { [weak self] in
                self?.store.updateSettings { $0.appearance.railGroupFilter = nil }
            },
            .separator(),
        ]
        for group in store.settings.groups {
            let id = group.id
            items.append(ActionMenuItem(group.name.value, isChecked: appearance.railGroupFilter == id) { [weak self] in
                self?.store.updateSettings { $0.appearance.railGroupFilter = id }
            })
        }
        return items
    }

    private func openItems(appearance: AppearanceSettings, l10n: Localizer) -> [NSMenuItem] {
        let text = l10n.islandMenu
        let triggers: [(IslandOpenTrigger, String)] = [(.hover, text.onHover), (.click, text.onClick), (.hoverOrClick, text.onHoverOrClick)]
        return triggers.map { trigger, title in
            ActionMenuItem(title, isChecked: appearance.openTrigger == trigger) { [weak self] in
                self?.store.updateSettings { $0.appearance.openTrigger = trigger }
            }
        }
    }

    private func placementItems(appearance: AppearanceSettings, l10n: Localizer) -> [NSMenuItem] {
        let text = l10n.islandMenu
        let edges: [(ScreenEdge, String)] = [(.top, text.top), (.bottom, text.bottom), (.left, text.left), (.right, text.right)]
        var items: [NSMenuItem] = edges.map { edge, title in
            ActionMenuItem(title, isChecked: appearance.edge == edge) { [weak self] in
                self?.move(to: edge)
            }
        }
        items.append(.separator())
        items.append(ActionMenuItem(text.attachedToEdge, isChecked: appearance.style == .attached) { [weak self] in
            self?.store.updateSettings { $0.appearance.style = .attached }
        })
        items.append(ActionMenuItem(text.floating, isChecked: appearance.style == .floating) { [weak self] in
            self?.store.updateSettings { $0.appearance.style = .floating }
        })
        return items
    }

    /// "Move to Display ▸": every connected display, the current one checked.
    private func displayItems(l10n: Localizer) -> [NSMenuItem] {
        let current = resolvedScreen.flatMap { DisplayIdentity.identifier(of: $0) }
        return IslandMenuPlan.displayItems(displays: store.displays, current: current, l10n: l10n).map { item in
            ActionMenuItem(item.title, isChecked: item.isChecked) { [weak self] in
                self?.store.actions.moveIslandToDisplay(item.id)
            }
        }
    }

    private func move(to edge: ScreenEdge) {
        store.updateSettings { settings in
            settings.appearance.edge = edge
            settings.appearance.offset = .center
        }
    }

    // MARK: - Screen

    /// The display with the menu bar; the fallback before `AppController` has published its display catalog.
    private static func targetScreen() -> NSScreen? {
        NSScreen.screens.first
    }

    /// The display the island belongs on for the chosen display policy, falling back to the menu bar display when
    /// the saved display is gone or no catalog is available yet.
    private var resolvedScreen: NSScreen? {
        let appearance = self.appearance
        if let screenCatalog,
           let resolved = screenCatalog.resolve(policy: appearance.islandDisplayPolicy, remembered: appearance.islandDisplay) {
            return resolved.screen
        }
        return Self.targetScreen()
    }

    /// The camera notch of a screen, or the one a debug scenario simulates.
    private func notch(of screen: NSScreen) -> NotchGeometry? {
        #if DEBUG
        if let debugNotch { return debugNotch }
        #endif
        guard let screenCatalog, let id = DisplayIdentity.identifier(of: screen) else {
            return DisplayIdentity.notch(of: screen)
        }
        return screenCatalog.displays.first { $0.id == id }?.notch
    }

    /// The bounds a carried panel may cover: every connected display, so a drag can cross between them.
    private var dragBounds: CGRect {
        IslandGeometry.dragBounds(displays: screenCatalog?.displays ?? [], fallback: screenFrame)
    }
}

#if DEBUG
/// Hooks for `DebugScenario`: in-memory setting overrides and synthetic input. Never persisted.
extension IslandController {
    struct DebugGeometry {
        let panelFrame: CGRect
        /// The island's current target shape frame, in screen coordinates.
        let islandFrame: CGRect?
        let sizes: IslandSizes
        let isExpanded: Bool
        let isPinned: Bool
        /// The rail's hover swell is on.
        let isHovered: Bool
        /// The hidden deck is built for an opening.
        let prewarmsDeck: Bool
        let edge: ScreenEdge
        let anchor: IslandAnchor
        let style: IslandStyle
        let windowNumber: Int
        /// Where the island can be in either state, with the panel margin, in screen coordinates.
        let captureRegion: CGRect?
        /// 0 = rings on the rail, 1 = on the deck; `nil` when nothing flies.
        let flightProgress: Double?
        /// How many rings are flying.
        let flightCount: Int
        /// The snap target the carry is locked onto, if any.
        let snapTarget: String?
        /// Haptics played during the current carry.
        let hapticCount: Int
        let notchFused: Bool
        let displayID: String?
        /// Ring boxes the live rail and deck have reported, and whether the deck's dial row reported its viewport.
        let railAnchors: Int
        let deckAnchors: Int
        let hasDeckViewport: Bool
    }

    var debugPanel: NSPanel { panel }

    /// The settings the island currently runs with, overrides included.
    var debugSettings: (appearance: AppearanceSettings, general: GeneralSettings) {
        (appearance, general)
    }

    /// The general settings a debug scenario set in memory, if any (the shortcut registration follows them).
    var debugGeneralOverride: GeneralSettings? {
        debugGeneral
    }

    var debugGeometry: DebugGeometry {
        let island = model.frames.map { frames in
            IslandGeometry.screen(model.isDragging ? frames.rail : frames.frame(expanded: model.isExpanded), in: canvas)
        }
        return DebugGeometry(
            panelFrame: panel.frame,
            islandFrame: island,
            sizes: sizes,
            isExpanded: model.isExpanded,
            isPinned: interaction.isPinned,
            isHovered: model.isHovered,
            prewarmsDeck: model.prewarmsDeck,
            edge: model.layout.edge,
            anchor: model.layout.anchor,
            style: model.layout.style,
            windowNumber: panel.windowNumber,
            captureRegion: model.frames.map { frames in
                let margin = model.layout.metrics.windowMargin
                return IslandGeometry.screen(frames.rail.union(frames.deck), in: canvas)
                    .insetBy(dx: -margin, dy: -margin)
                    .intersection(screenFrame)
                    .integral
            },
            flightProgress: model.flight == nil ? nil : Double(model.flightProgress),
            flightCount: model.flight?.count ?? 0,
            snapTarget: snapState.locked?.rawValue,
            hapticCount: dragHapticCount,
            notchFused: model.layout.isNotchFused,
            displayID: resolvedScreen.flatMap { DisplayIdentity.identifier(of: $0)?.rawValue },
            railAnchors: model.anchors.rail.count,
            deckAnchors: model.anchors.deck.count,
            hasDeckViewport: model.anchors.deckViewport != nil
        )
    }

    /// Simulates a camera notch on the island's display, so the fused rail can be reviewed without the hardware.
    /// `nil` returns to the real geometry.
    func debugSetNotch(_ notch: NotchGeometry?) {
        debugNotch = notch
        applyAppearance()
    }

    /// Moves the island to the next connected display (`{"display": "next"}`).
    @discardableResult
    func debugMoveToNextDisplay() -> DisplayID? {
        guard let screenCatalog, screenCatalog.displays.count > 1 else { return nil }
        let current = resolvedScreen.flatMap { DisplayIdentity.identifier(of: $0) }
        let displays = screenCatalog.displays
        let index = displays.firstIndex { $0.id == current } ?? 0
        let next = displays[(index + 1) % displays.count]
        store.actions.moveIslandToDisplay(next.id)
        return next.id
    }

    /// The scoped Esc hot key, as if another app were active (the harness cannot deactivate this one).
    func debugPressEscapeHotKey() {
        guard interaction.wantsEscapeHotKey else { return }
        send(.escape)
    }

    /// Replaces appearance and general settings in memory only; `nil` returns to the stored settings.
    func debugApply(appearance: AppearanceSettings?, general: GeneralSettings?) {
        debugAppearance = appearance
        debugGeneral = general
        applyAppearance()
    }

    func debugExpand() {
        guard !interaction.isExpanded else { return }
        send(.toggle)
    }

    func debugCollapse() {
        send(.escape)
    }

    /// Simulates the pointer arriving on or leaving the island; the real pointer is ignored meanwhile.
    func debugHover(_ inside: Bool) {
        hostingView.pointerOverride = inside
    }

    func debugClick() {
        requestHandledDuringPress = false
        send(.click)
    }

    /// Mouse-down only, for measuring how much of the deck's build a click's own 80–120 ms absorbs (L1).
    func debugPress() {
        pressed()
    }

    /// A click outside the island, delivered only while the real outside-click monitor would be installed.
    func debugOutsideClick() {
        guard interaction.wantsOutsideClickMonitor else { return }
        send(.outsideClick)
    }

    /// Carries the island from its rail's centre to `target` (screen coordinates) and drops it there, through
    /// the same drag path real mouse input takes after the drag threshold.
    /// Drags the island with synthesized mouse events sent through the panel: hit testing, the hosting view's drag
    /// threshold and the responder chain run exactly as with a real mouse. `grip` is a unit point inside the rail
    /// (0,0 bottom-left … 1,1 top-right); the centre when nil.
    func debugMouseDrag(to target: CGPoint, steps: Int, from grip: CGPoint? = nil) async {
        guard let frames = model.frames, !model.isDragging else { return }
        let form = IslandGeometry.screen(model.isExpanded ? frames.deck : frames.rail, in: canvas)
        let start = grip.map { CGPoint(x: form.minX + form.width * $0.x, y: form.minY + form.height * $0.y) }
            ?? CGPoint(x: form.midX, y: form.midY)
        func send(_ type: NSEvent.EventType, _ screenPoint: CGPoint) {
            let local = panel.convertPoint(fromScreen: screenPoint)
            guard let event = NSEvent.mouseEvent(
                with: type,
                location: local,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: panel.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: type == .leftMouseUp ? 0 : 1
            ) else { return }
            panel.sendEvent(event)
        }
        send(.leftMouseDown, start)
        let count = max(2, steps)
        for step in 1...count {
            try? await Task.sleep(for: .milliseconds(16))
            let progress = Double(step) / Double(count)
            send(.leftMouseDragged, CGPoint(x: start.x + (target.x - start.x) * progress, y: start.y + (target.y - start.y) * progress))
        }
        send(.leftMouseUp, target)
    }

    func debugDrag(to target: CGPoint, duration: TimeInterval, command: Bool = false) async {
        guard let frames = model.frames, !model.isDragging else { return }
        let rail = IslandGeometry.screen(model.isExpanded ? frames.deck : frames.rail, in: canvas)
        let start = CGPoint(x: rail.midX, y: rail.midY)
        let steps = max(2, Int((duration * 60).rounded()))
        debugCommandBypass = command
        defer { debugCommandBypass = false }
        dragBegan(pressedAt: start, pointer: start)
        for step in 1...steps {
            try? await Task.sleep(for: .milliseconds(Int((duration * 1_000 / Double(steps)).rounded())))
            let progress = Double(step) / Double(steps)
            let eased = progress * progress * (3 - 2 * progress)
            dragMoved(to: CGPoint(x: start.x + (target.x - start.x) * eased, y: start.y + (target.y - start.y) * eased))
        }
        dragEnded(at: target)
    }
}
#endif

extension IslandController: PresentationSurface {}
