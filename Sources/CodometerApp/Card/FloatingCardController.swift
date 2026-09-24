import CodometerCore
import CodometerL10n
import CodometerPlatform
import CodometerUI
import AppKit
import SwiftUI
import os

/// Owns the floating card's window: shows it when the card is the selected style, morphs it between the card and the
/// pill, carries it with the magnet, remembers where it was left per display, and routes notifications, peeks and the
/// global shortcut to it.
///
/// How the card avoids ever jumping:
/// - the card's screen rect is the single source of truth; the panel is only a window onto a canvas around it, so
///   growing or shrinking the panel never moves anything on screen;
/// - the panel grows once before an expand and shrinks once after a fold has finished, and never with
///   `setFrame(_:display:animate:)`;
/// - while the card is carried only `setFrameOrigin` runs: SwiftUI sees no state change except `isDragging`;
/// - the magnet is a pure function of the pointer (`FloatingCardGeometry.resolve`), so it cannot overshoot;
/// - both forms share one anchor point, so minimize → restore lands on exactly the same pixels.
@MainActor
final class FloatingCardController {
    /// Upper bound for the fold animation, in case its completion callback never arrives.
    static let foldFallback: Duration = .milliseconds(900)
    /// How long keyboard engagement survives after the pointer has left.
    static let engagementGrace: Duration = .seconds(3)
    /// The coach mark's time on screen, the first time the card appears.
    static let coachMarkDuration: Duration = .seconds(6)
    /// Placements are written at most this often, and never during a drag.
    static let placementDebounce: Duration = .milliseconds(500)
    /// How long a manual account switch keeps auto-selection away.
    static let autoFollowHold = CardAccountSelector.manualHold

    let model = FloatingCardModel()

    private let store: TrackerStore
    private let panel = FloatingCardPanel()
    private let container = FloatingCardContainerView(frame: .zero)
    private let hostingView: InteractiveHostingView<FloatingCardRootView>
    private let haptics: any HapticPerforming
    private var contextMenu: NSMenu?
    private var accountMenu: NSMenu?

    private var interaction = CardInteractionState()
    /// The card's rect in screen coordinates: everything else follows from it.
    private var cardScreenFrame: CGRect = .zero
    private var pillScreenFrame: CGRect = .zero
    /// The display the card is on now.
    private var currentDisplay: DisplayDescriptor?
    private var stage: CGRect = .zero
    /// The panel stays card-sized until the fold animation has finished.
    private var holdsCardFrame = false
    private var foldGeneration = 0
    private var hasAppeared = false

    private var dragAnchor: DragAnchor?
    private var arming = MagnetArming()

    private var foldTask: Task<Void, Never>?
    private var peekTask: Task<Void, Never>?
    private var engagementTask: Task<Void, Never>?
    private var coachTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    /// When the user last chose an account by hand.
    private var manualSwitchAt: Date?
    /// Set when SwiftUI handled a press (a button, the header chip), so the same press is not also a card click.
    private var requestHandledDuringPress = false

    #if DEBUG
    private var debugAppearance: AppearanceSettings?
    /// A scripted drag holds ⌘; real drags read the modifier from the event state.
    private var debugCommandBypass = false
    #endif

    /// Whether ⌘ suspends snapping for this drag. Read from the current modifier state, never from a monitor.
    private var commandHeld: Bool {
        #if DEBUG
        if debugCommandBypass { return true }
        #endif
        return NSEvent.modifierFlags.contains(.command)
    }

    /// A debug drag drives the card with no mouse button down; it must not look abandoned.
    private var isSyntheticDrag = false

    private struct DragAnchor {
        /// Where the press began, in screen coordinates.
        let press: NSPoint
        /// The card's origin when the press began.
        let cardOrigin: CGPoint
        let panelOrigin: CGPoint
    }

    init(store: TrackerStore, haptics: (any HapticPerforming)? = nil) {
        self.store = store
        self.haptics = haptics ?? TrackpadHaptics(isEnabled: { [weak store] in store?.settings.appearance.playsHaptics ?? false })
        hostingView = InteractiveHostingView(rootView: FloatingCardRootView(store: store, model: model))
        hostingView.sizingOptions = []
        hostingView.safeAreaRegions = []
        hostingView.autoresizingMask = []

        model.onRequest = { [weak self] request in self?.handle(request) }
        hostingView.onHover = { [weak self] inside in self?.hoverChanged(inside) }
        hostingView.onPress = { [weak self] in self?.requestHandledDuringPress = false }
        hostingView.onClick = { [weak self] in self?.clicked() }
        hostingView.onDoubleClick = { [weak self] in self?.doubleClicked() }
        hostingView.onDragBegan = { [weak self] press, pointer in self?.dragBegan(pressedAt: press, pointer: pointer) }
        hostingView.onDragMoved = { [weak self] point in self?.dragMoved(to: point) }
        hostingView.onDragEnded = { [weak self] point in self?.dragEnded(at: point) }
        hostingView.contextMenu = { [weak self] in self?.makeContextMenu() ?? NSMenu() }
        container.onSwipe = { [weak self] direction in self?.switchAccount(by: direction) }
        panel.onKeyDown = { [weak self] event in self?.handleKey(event) ?? false }
        panel.dragInterceptor = { [weak hostingView] event in hostingView?.interceptDragEvent(event) ?? false }

        container.addSubview(hostingView)
        panel.contentView = container
        #if DEBUG
        DebugWindows.register(panel, name: DebugWindows.card)
        #endif
        observeStore()
    }

    // MARK: - Settings

    private var appearance: AppearanceSettings {
        #if DEBUG
        if let debugAppearance { return debugAppearance }
        #endif
        return store.settings.appearance
    }

    private var settings: FloatingCardSettings { appearance.floatingCard }

    /// The card is the selected presentation style and the user shows it.
    private var isShown: Bool {
        appearance.visibility == .always && appearance.presentationStyle == .floatingCard
    }

    private var metrics: CardMetrics { CardMetrics(appearance.scale) }

    private var accounts: [AccountPresentation] { store.visiblePresentations }

    // MARK: - Displays

    /// The connected displays. `store.displays` is the app's own catalogue; until it is filled the card builds the
    /// list from `NSScreen` itself, so it works on its own.
    private func displays() -> [DisplayDescriptor] {
        let published = store.displays
        guard published.isEmpty else { return published }
        return NSScreen.screens.enumerated().compactMap { index, screen in
            guard let id = Self.displayID(of: screen, fallbackIndex: index) else { return nil }
            return DisplayDescriptor(
                id: id,
                name: screen.localizedName,
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                isMain: index == 0,
                isBuiltIn: screen.safeAreaInsets.top > 0,
                notch: NotchGeometry.make(
                    screen: screen.frame,
                    safeTop: screen.safeAreaInsets.top,
                    auxLeft: screen.auxiliaryTopLeftArea,
                    auxRight: screen.auxiliaryTopRightArea
                )
            )
        }
    }

    /// The display's stable UUID; a display without one (rare, e.g. a virtual screen) gets a deterministic id from its
    /// position in the list so placements still work for this session.
    private static func displayID(of screen: NSScreen, fallbackIndex: Int) -> DisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = screen.deviceDescription[key] as? NSNumber,
           let uuid = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(number.uint32Value))?.takeRetainedValue() {
            return try? DisplayID(CFUUIDCreateString(nil, uuid) as String)
        }
        return try? DisplayID(String(format: "00000000-0000-4000-8000-%012d", fallbackIndex))
    }

    // MARK: - PresentationSurface

    var isOnScreen: Bool { panel.isVisible }

    /// Re-reads the settings and shows the card, or hides it when it is not the selected style.
    func applyAppearance() {
        let behavior = FloatingCardPanel.collectionBehavior(hidesInFullScreen: appearance.hidesInFullScreen)
        panel.collectionBehavior = behavior
        panel.level = FloatingCardPanel.level(keepsAboveWindows: settings.keepsAboveWindows)

        guard isShown else {
            hide()
            return
        }
        endAbandonedDrag()
        guard !interaction.isDragging else { return }

        if interaction.isHidden {
            _ = interaction.handle(.show(minimized: settings.isMinimized))
            model.isExpanded = interaction.isExpanded
        } else if !interaction.isPeeking, interaction.isExpanded == settings.isMinimized {
            // The settings changed elsewhere (another window's menu, a restored file).
            send(settings.isMinimized ? .minimize : .expand)
        }

        model.metrics = metrics
        model.thirdTile = settings.thirdTile
        model.stripScope = settings.stripScope
        refreshTheme()
        refreshSelection()
        refreshFrames()
        panel.orderFrontRegardless()
        hostingView.setNeedsPointerRefresh()
        updateStatusSurface()
        showCoachMarkIfNeeded()
        hasAppeared = true
    }

    /// A notification click: the card expands on that account and holds auto-selection for a minute.
    @discardableResult
    func openPinned(accountID: AccountID) -> Bool {
        guard isShown, panel.isVisible else { return false }
        guard !interaction.isDragging else { return true }
        select(accountID, manual: true)
        send(.openPinned)
        return true
    }

    /// An alert peek: a minimized card shows itself for a few seconds; an expanded one just switches account.
    func peek(accountID: AccountID, seconds: Int) {
        guard seconds > 0, isShown, panel.isVisible, !interaction.isDragging else { return }
        select(accountID, manual: true)
        guard !interaction.isExpanded else { return }
        send(.peekStart)
        peekTask?.cancel()
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.send(.peekElapsed)
        }
    }

    /// The global shortcut toggles the card and brings it to the front.
    func toggleFromShortcut(preferAttention: Bool) -> Bool {
        guard isShown, panel.isVisible else { return false }
        if preferAttention, let waiting = accounts.first(where: { !$0.waitingSessions.isEmpty }) {
            select(waiting.id, manual: true)
        }
        send(.toggle)
        return true
    }

    func hide() {
        peekTask?.cancel()
        _ = interaction.handle(.hide)
        endKeyboardEngagement()
        store.setStatusSurface(.card, visible: false)
        panel.orderOut(nil)
    }

    // MARK: - Interaction

    private func send(_ event: CardInteractionState.Event) {
        let wasExpanded = interaction.isExpanded
        let effects = interaction.handle(event)
        for effect in effects {
            perform(effect)
        }
        if interaction.isExpanded != wasExpanded, !interaction.isHidden {
            setExpanded(interaction.isExpanded, animated: true)
        }
        if interaction.isHidden {
            panel.orderOut(nil)
        }
        updateStatusSurface()
    }

    private func perform(_ effect: CardInteractionState.Effect) {
        switch effect {
        case .persistMinimized(let minimized):
            updateCardSettings { $0.isMinimized = minimized }
        case .startPeekTimer:
            break
        case .cancelPeekTimer:
            peekTask?.cancel()
            peekTask = nil
        case .orderFront:
            panel.orderFrontRegardless()
        case .endKeyboardEngagement:
            endKeyboardEngagement()
        }
    }

    private func hoverChanged(_ inside: Bool) {
        guard model.isHovered != inside else { return }
        model.isHovered = inside
        if inside {
            engagementTask?.cancel()
            engagementTask = nil
        } else if model.isKeyboardEngaged {
            engagementTask?.cancel()
            engagementTask = Task { [weak self] in
                try? await Task.sleep(for: Self.engagementGrace)
                guard !Task.isCancelled else { return }
                self?.endKeyboardEngagement()
            }
        }
    }

    private func clicked() {
        Task { @MainActor [weak self] in
            guard let self, !requestHandledDuringPress else { return }
            beginKeyboardEngagement()
            send(interaction.isExpanded ? .touched : .click)
        }
    }

    private func doubleClicked() {
        requestHandledDuringPress = true
        send(.doubleClick)
    }

    private func handle(_ request: CardRequest) {
        requestHandledDuringPress = true
        beginKeyboardEngagement()
        switch request {
        case .minimize:
            send(.minimize)
        case .expand:
            send(.expand)
        case .accountMenu:
            showAccountMenu()
        case .selectAccount(let id):
            select(id, manual: true)
        case .nextAccount:
            switchAccount(by: 1)
        case .previousAccount:
            switchAccount(by: -1)
        case .openStatusPage(let provider):
            store.actions.openStatusPage(provider)
        case .refresh:
            store.refresh()
        case .openSettings:
            store.actions.openSettings()
        case .move(let anchor):
            move(to: anchor)
        }
    }

    // MARK: - Keyboard engagement

    private func beginKeyboardEngagement() {
        engagementTask?.cancel()
        engagementTask = nil
        guard !model.isKeyboardEngaged else { return }
        model.isKeyboardEngaged = true
        panel.isKeyboardEngaged = true
        // Non-activating: the app in front keeps its focus, and the card still receives keys.
        panel.makeKeyAndOrderFront(nil)
    }

    private func endKeyboardEngagement() {
        engagementTask?.cancel()
        engagementTask = nil
        guard model.isKeyboardEngaged else { return }
        model.isKeyboardEngaged = false
        panel.isKeyboardEngaged = false
    }

    /// Esc minimizes, ←/→ switch accounts, Space and Return toggle, ⌘, opens Settings. Only while engaged.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard model.isKeyboardEngaged else { return false }
        if event.modifierFlags.contains(.command) {
            guard event.charactersIgnoringModifiers == "," else { return false }
            store.actions.openSettings()
            return true
        }
        switch event.keyCode {
        case 53:
            send(.minimize)
            return true
        case 123:
            switchAccount(by: -1)
            return true
        case 124:
            switchAccount(by: 1)
            return true
        case 49, 36:
            send(.toggle)
            return true
        default:
            return false
        }
    }

    // MARK: - Accounts

    private func observeStore() {
        withObservationTracking {
            _ = store.state
            _ = store.settings.accounts
            _ = store.localizer
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                refreshSelection()
                refreshFrames()
                observeStore()
            }
        }
    }

    private func refreshSelection() {
        let list = accounts
        let selected = CardAccountSelector.select(
            presentations: list,
            current: model.selectedAccountID,
            selection: settings.accountSelection,
            pointerInside: model.isHovered,
            manualSwitchAt: manualSwitchAt,
            now: store.now
        )
        if model.selectedAccountID != selected {
            withAnimation(Motion.content) {
                model.selectedAccountID = selected
            }
        }
        let pinned: Bool = if case .fixed = settings.accountSelection {
            true
        } else if let manualSwitchAt {
            store.now.timeIntervalSince(manualSwitchAt) < Self.autoFollowHold
        } else {
            false
        }
        if model.isAccountPinned != pinned {
            model.isAccountPinned = pinned
        }
    }

    private func select(_ id: AccountID, manual: Bool) {
        guard accounts.contains(where: { $0.id == id }) else { return }
        if manual {
            manualSwitchAt = Date()
            model.isAccountPinned = true
        }
        guard model.selectedAccountID != id else { return }
        withAnimation(Motion.content) {
            model.selectedAccountID = id
        }
    }

    private func switchAccount(by offset: Int) {
        let list = accounts
        guard list.count > 1 else { return }
        let index = list.firstIndex { $0.id == model.selectedAccountID } ?? 0
        let next = ((index + offset) % list.count + list.count) % list.count
        select(list[next].id, manual: true)
    }

    // MARK: - Theme and frames

    private func refreshTheme() {
        let scheme: ColorScheme = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
        let workspace = NSWorkspace.shared
        let tokens = CardThemeTokens.resolve(
            theme: settings.theme,
            scheme: scheme,
            reducesTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
            increasesContrast: workspace.accessibilityDisplayShouldIncreaseContrast
        )
        if model.theme != tokens {
            withAnimation(Motion.content) {
                model.theme = tokens
            }
        }
    }

    /// Works out where the card sits now and fits the panel around it.
    private func refreshFrames() {
        endAbandonedDrag()
        guard isShown, !interaction.isDragging else { return }
        let connected = displays()
        guard let plan = FloatingCardGeometry.plan(
            policy: settings.displayPolicy,
            placements: settings.placements,
            displays: connected
        ) else { return }
        if let updated = plan.updatedPlacements {
            saveCardSettings { $0.placements = updated }
        }
        currentDisplay = plan.display
        let metrics = self.metrics
        model.metrics = metrics
        stage = FloatingCardGeometry.stage(of: plan.display)
        let size = metrics.fittingSize(settings.size, in: stage) ?? .compact
        if model.size != size {
            model.size = size
        }
        let cardSize = metrics.cardSize(size)
        let card = FloatingCardGeometry.frame(for: plan.placement, size: cardSize, in: stage)
        setFrames(card: card, anchor: plan.placement.anchor, animated: false)
    }

    /// Fixes the card's rect and derives the pill's rect, the model's canvas frames and the panel.
    private func setFrames(card: CGRect, anchor: CardAnchor, animated: Bool) {
        let metrics = self.metrics
        // Every language's templates, so the pill keeps its size when the language changes.
        let pillSize = metrics.pillSize(accounts: accounts.count, templates: CardPillTemplates.everyLanguage)
        let pill = FloatingCardGeometry.aligned(size: pillSize, in: card, anchor: anchor)
        cardScreenFrame = card
        pillScreenFrame = pill
        model.coachMarkBelow = FloatingCardGeometry.axes(of: anchor).y != .start
        let canvas = canvasRect(around: card)
        let cardLocal = IslandGeometry.local(card, in: canvas)
        let pillLocal = IslandGeometry.local(pill, in: canvas)
        if model.cardFrame != cardLocal || model.pillFrame != pillLocal || model.anchor != anchor {
            withTransaction(Self.plainTransaction) {
                model.cardFrame = cardLocal
                model.pillFrame = pillLocal
                model.anchor = anchor
            }
        }
        syncWindow()
    }

    /// The canvas around a card rect: the window margin on every side, plus room for the coach mark while it shows.
    ///
    /// The extra room is added on the coach mark's own side only, so the card itself never moves when it appears.
    private func canvasRect(around card: CGRect) -> CGRect {
        var canvas = card.insetBy(dx: -metrics.windowMargin, dy: -metrics.windowMargin)
        guard model.showsCoachMark else { return canvas }
        let reserve = metrics.coachMarkReserve
        if model.coachMarkBelow {
            canvas.origin.y -= reserve
        }
        canvas.size.height += reserve
        return canvas
    }

    /// The only place that fits the panel around the card's canvas.
    private func syncWindow() {
        guard cardScreenFrame.width > 0 else { return }
        let margin = metrics.windowMargin
        let form = (model.isExpanded || holdsCardFrame) ? cardScreenFrame : pillScreenFrame
        var frame = form.insetBy(dx: -margin, dy: -margin)
        if model.showsCoachMark {
            let reserve = metrics.coachMarkReserve
            if model.coachMarkBelow {
                frame.origin.y -= reserve
            }
            frame.size.height += reserve
        }
        frame = frame.integral
        let canvas = canvasRect(around: cardScreenFrame)
        let canvasInPanel = CGRect(
            x: canvas.minX - frame.minX,
            y: canvas.minY - frame.minY,
            width: canvas.width,
            height: canvas.height
        )
        if hostingView.frame != canvasInPanel {
            hostingView.frame = canvasInPanel
        }
        hostingView.layoutSubtreeIfAllowed()
        if panel.frame != frame {
            // Never `setFrame(_:display:animate:)`: the card's own morph owns every visible change.
            panel.setFrame(frame, display: true)
        }
        updateInteractiveRect()
    }

    private func updateInteractiveRect() {
        let canvas = canvasRect(around: cardScreenFrame)
        let shape = model.isExpanded ? cardScreenFrame : pillScreenFrame
        let local = IslandGeometry.local(shape, in: canvas)
        hostingView.interactiveRect = IslandGeometry.viewRect(
            local,
            boundsHeight: hostingView.bounds.height,
            isFlipped: hostingView.isFlipped
        )
    }

    private static var plainTransaction: Transaction {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        return transaction
    }

    // MARK: - Expand and minimize

    private func setExpanded(_ expanded: Bool, animated: Bool) {
        guard model.isExpanded != expanded else { return }
        foldGeneration += 1
        let generation = foldGeneration
        foldTask?.cancel()
        guard animated else {
            model.isExpanded = expanded
            model.prewarmsCard = false
            model.prewarmsPill = false
            holdsCardFrame = expanded
            syncWindow()
            return
        }
        // With Reduce Motion `Motion.liquidOpen`/`liquidFold` are a short crossfade and the contour is a plain
        // rounded rectangle (`CardMorphShape.isLiquid`), so the same path serves both.
        if expanded {
            // Build the card invisibly and grow the panel once, before anything moves.
            setPrewarms(card: true, pill: false)
            hostingView.layoutSubtreeIfAllowed()
            holdsCardFrame = true
            syncWindow()
            model.isMorphing = true
            withAnimation(Motion.liquidOpen, completionCriteria: .logicallyComplete) {
                model.isExpanded = true
            } completion: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.finishMorph(generation: generation, expanded: true)
                }
            }
        } else {
            setPrewarms(card: false, pill: true)
            hostingView.layoutSubtreeIfAllowed()
            // The panel keeps the card's size until the fold has finished, so the contour is never clipped.
            holdsCardFrame = true
            syncWindow()
            model.isMorphing = true
            withAnimation(Motion.liquidFold, completionCriteria: .logicallyComplete) {
                model.isExpanded = false
            } completion: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.finishMorph(generation: generation, expanded: false)
                }
            }
        }
        updateInteractiveRect()
        foldTask?.cancel()
        foldTask = Task { [weak self] in
            try? await Task.sleep(for: Self.foldFallback)
            guard !Task.isCancelled else { return }
            self?.finishMorph(generation: generation, expanded: expanded)
        }
    }

    private func finishMorph(generation: Int, expanded: Bool) {
        guard generation == foldGeneration, model.isExpanded == expanded else { return }
        foldTask?.cancel()
        foldTask = nil
        model.isMorphing = false
        holdsCardFrame = expanded
        setPrewarms(card: false, pill: false)
        syncWindow()
        updateStatusSurface()
    }

    private func setPrewarms(card: Bool, pill: Bool) {
        guard model.prewarmsCard != card || model.prewarmsPill != pill else { return }
        withTransaction(Self.plainTransaction) {
            model.prewarmsCard = card
            model.prewarmsPill = pill
        }
    }

    private func updateStatusSurface() {
        store.setStatusSurface(.card, visible: isShown && panel.isVisible && interaction.isExpanded)
    }

    // MARK: - Coach mark

    private func showCoachMarkIfNeeded() {
        guard !settings.hasShownCoachMark, !model.showsCoachMark else { return }
        updateCardSettings { $0.hasShownCoachMark = true }
        withAnimation(Motion.content) {
            model.showsCoachMark = true
        }
        // The canvas and the panel grow on the coach mark's side; the card itself does not move.
        setFrames(card: cardScreenFrame, anchor: model.anchor, animated: false)
        coachTask?.cancel()
        coachTask = Task { [weak self] in
            try? await Task.sleep(for: Self.coachMarkDuration)
            guard !Task.isCancelled, let self else { return }
            withAnimation(Motion.content) {
                model.showsCoachMark = false
            }
            setFrames(card: cardScreenFrame, anchor: model.anchor, animated: false)
        }
    }

    // MARK: - Dragging

    /// A drag whose release never arrived (the button is already up) would keep the card from applying any setting
    /// and from moving again: it is dropped where it is.
    private func endAbandonedDrag() {
        guard interaction.isDragging, !isSyntheticDrag, NSEvent.pressedMouseButtons & 1 == 0 else { return }
        AppLog.interface.notice("card drag had no release; dropping the card where it is")
        hostingView.resetDragTracking()
        dragEnded(at: NSEvent.mouseLocation)
    }

    private func dragBegan(pressedAt press: NSPoint, pointer: NSPoint) {
        peekTask?.cancel()
        send(.dragBegan)
        model.isDragging = true
        arming = MagnetArming()
        dragAnchor = DragAnchor(press: press, cardOrigin: cardScreenFrame.origin, panelOrigin: panel.frame.origin)
        dragMoved(to: pointer)
    }

    private func dragMoved(to point: NSPoint) {
        guard let anchor = dragAnchor else { return }
        let connected = displays()
        let target = DisplaySelection.display(at: point, in: connected)
            .flatMap { candidate in
                DisplaySelection.allowsDrop(on: candidate, policy: settings.displayPolicy, displays: connected)
                    ? candidate
                    : currentDisplay
            } ?? currentDisplay
        if let target, target.id != currentDisplay?.id {
            currentDisplay = target
            stage = FloatingCardGeometry.stage(of: target)
            haptics.perform(.displayChange)
        }
        let free = CGRect(
            x: anchor.cardOrigin.x + point.x - anchor.press.x,
            y: anchor.cardOrigin.y + point.y - anchor.press.y,
            width: cardScreenFrame.width,
            height: cardScreenFrame.height
        )
        let bypass = commandHeld
        let radius = MagnetLaw.radius * metrics.scale
        let resolution = FloatingCardGeometry.resolve(
            free: free,
            in: stage,
            radius: radius,
            snaps: appearance.snapsWhileDragging && !bypass
        )
        if arming.update(targetID: resolution.targetID, distance: resolution.distance, radius: radius, now: ProcessInfo.processInfo.systemUptime) {
            haptics.perform(.lock)
        }
        moveCard(to: resolution.frame.origin)
    }

    /// While the card is carried only the panel's origin changes: SwiftUI sees nothing but `isDragging`.
    private func moveCard(to origin: CGPoint) {
        let delta = CGPoint(x: origin.x - cardScreenFrame.minX, y: origin.y - cardScreenFrame.minY)
        guard delta != .zero else { return }
        cardScreenFrame.origin = origin
        pillScreenFrame.origin = CGPoint(x: pillScreenFrame.minX + delta.x, y: pillScreenFrame.minY + delta.y)
        panel.setFrameOrigin(CGPoint(x: panel.frame.minX + delta.x, y: panel.frame.minY + delta.y))
    }

    private func dragEnded(at point: NSPoint) {
        dragAnchor = nil
        model.isDragging = false
        send(.dragEnded)
        guard let display = currentDisplay else { return }
        let stage = FloatingCardGeometry.stage(of: display)
        self.stage = stage
        let radius = MagnetLaw.radius * metrics.scale
        let bypass = commandHeld
        // Bring the card back onto the display first: a card carried past an edge then lands *in* that corner, which
        // is where the magnet can still take it.
        let onScreen = FloatingCardGeometry.clamp(cardScreenFrame, in: stage)
        let resolution = FloatingCardGeometry.resolve(
            free: onScreen,
            in: stage,
            radius: radius,
            snaps: appearance.snapsWhileDragging && !bypass
        )
        let settled = FloatingCardGeometry.clamp(resolution.frame, in: stage)
        let anchor = resolution.snappedAnchor ?? FloatingCardGeometry.gravity(of: settled, in: stage)
        let placement = FloatingCardGeometry.placement(
            of: settled,
            on: display,
            stage: stage,
            snappedAnchor: resolution.snappedAnchor
        )
        settle(to: settled, anchor: anchor)
        saveCardSettings { settings in
            var placements = settings.placements
            placements.remember(placement)
            placements.current = display.id
            placements.displacedFrom = nil
            settings.placements = placements
        }
    }

    /// Eases the card onto its final place after a drop, keeping its size (the animatable key is `frame`).
    private func settle(to frame: CGRect, anchor: CardAnchor) {
        let target = frame
        guard target != cardScreenFrame else {
            setFrames(card: target, anchor: anchor, animated: false)
            return
        }
        let margin = metrics.windowMargin
        let form = (model.isExpanded || holdsCardFrame) ? target : FloatingCardGeometry.aligned(size: pillScreenFrame.size, in: target, anchor: anchor)
        let panelFrame = form.insetBy(dx: -margin, dy: -margin).integral
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = false
            panel.animator().setFrame(panelFrame, display: false)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.setFrames(card: target, anchor: anchor, animated: false)
            }
        }
        cardScreenFrame = target
        pillScreenFrame = FloatingCardGeometry.aligned(size: pillScreenFrame.size, in: target, anchor: anchor)
        withTransaction(Self.plainTransaction) {
            model.anchor = anchor
        }
    }

    /// The context menu's "Move To" and the VoiceOver actions.
    private func move(to anchor: CardAnchor) {
        guard let display = currentDisplay ?? DisplaySelection.main(in: displays()) else { return }
        let stage = FloatingCardGeometry.stage(of: display)
        let placement = CardPlacement(displayID: display.id, anchor: anchor, snapped: true, x: .zero, y: .zero)
        let frame = FloatingCardGeometry.frame(for: placement, size: cardScreenFrame.size, in: stage)
        currentDisplay = display
        self.stage = stage
        settle(to: frame, anchor: anchor)
        saveCardSettings { settings in
            var placements = settings.placements
            placements.remember(placement)
            placements.current = display.id
            placements.displacedFrom = nil
            settings.placements = placements
        }
    }

    private func move(to displayID: DisplayID) {
        let connected = displays()
        guard let display = connected.first(where: { $0.id == displayID }) else { return }
        currentDisplay = display
        stage = FloatingCardGeometry.stage(of: display)
        let placement = settings.placements.placement(for: displayID) ?? FloatingCardGeometry.defaultPlacement(on: display)
        let frame = FloatingCardGeometry.frame(for: placement, size: cardScreenFrame.size, in: stage)
        settle(to: frame, anchor: placement.anchor)
        saveCardSettings { settings in
            var placements = settings.placements
            placements.remember(placement)
            placements.current = displayID
            placements.displacedFrom = nil
            settings.placements = placements
        }
    }

    /// Puts the card back where a fresh install leaves it: top-trailing on the main display.
    func resetPosition() {
        guard let display = DisplaySelection.main(in: displays()) else { return }
        saveCardSettings { settings in
            settings.placements = FloatingCardPlacements(
                byDisplay: [FloatingCardGeometry.defaultPlacement(on: display)],
                current: display.id
            )
        }
        currentDisplay = display
        refreshFrames()
    }

    // MARK: - Settings

    /// Writes a card setting now (a user choice from the menu).
    private func updateCardSettings(_ change: @escaping (inout FloatingCardSettings) -> Void) {
        #if DEBUG
        if var overridden = debugAppearance {
            change(&overridden.floatingCard)
            debugAppearance = overridden
            return
        }
        #endif
        store.updateSettings { change(&$0.appearance.floatingCard) }
    }

    /// Writes a placement, debounced, so a drag never writes the settings file on every sample.
    private func saveCardSettings(_ change: @escaping (inout FloatingCardSettings) -> Void) {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.placementDebounce)
            guard !Task.isCancelled, let self, !interaction.isDragging else { return }
            updateCardSettings(change)
        }
    }

    // MARK: - Menus

    private var menuPlan: CardMenuPlan {
        let l10n = store.localizer
        let connected = displays()
        let others = connected
            .filter { $0.id != currentDisplay?.id }
            .map { CardMenuPlan.DisplayEntry(id: $0.id, name: $0.name.isEmpty ? $0.id.rawValue : $0.name) }
        return CardMenuPlan.make(
            isExpanded: interaction.isExpanded,
            settings: settings,
            snapsWhileDragging: appearance.snapsWhileDragging,
            accounts: accounts.map { account in
                CardMenuPlan.AccountEntry(
                    id: account.id,
                    label: account.status.profile.label.value,
                    provider: account.provider,
                    usage: account.headline.map { l10n.format.percentCompact($0.binding.used.value) }
                )
            },
            otherDisplays: others,
            l10n: l10n
        )
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        for item in menuPlan.items {
            menu.addItem(menuItem(item))
        }
        contextMenu = menu
        return menu
    }

    private func showAccountMenu() {
        guard let item = menuPlan.items.first(where: { $0.id == "account" }) else { return }
        let menu = NSMenu()
        for child in item.children {
            menu.addItem(menuItem(child))
        }
        accountMenu = menu
        let canvas = canvasRect(around: cardScreenFrame)
        let header = IslandGeometry.local(cardScreenFrame, in: canvas)
        let point = NSPoint(x: header.minX + metrics.padding, y: header.minY + metrics.padding * 2)
        menu.popUp(positioning: nil, at: hostingView.convert(point, from: nil), in: hostingView)
    }

    private func menuItem(_ item: CardMenuPlan.Item) -> NSMenuItem {
        guard !item.isSeparator else { return .separator() }
        if !item.children.isEmpty {
            let parent = NSMenuItem()
            parent.title = item.title
            if let systemImage = item.systemImage {
                parent.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
            }
            let submenu = NSMenu()
            for child in item.children {
                submenu.addItem(menuItem(child))
            }
            parent.submenu = submenu
            return parent
        }
        guard let action = item.action else {
            let plain = NSMenuItem()
            plain.title = item.title
            plain.isEnabled = false
            return plain
        }
        return ActionMenuItem(item.title, systemImage: item.systemImage, isChecked: item.isChecked) { [weak self] in
            self?.run(action)
        }
    }

    private func run(_ action: CardMenuPlan.Action) {
        switch action {
        case .minimize:
            send(.minimize)
        case .expand:
            send(.expand)
        case .selectAccount(let id):
            if let id {
                updateCardSettings { $0.accountSelection = .fixed(id) }
                select(id, manual: true)
            } else {
                updateCardSettings { $0.accountSelection = .mostUrgent }
                manualSwitchAt = nil
                refreshSelection()
            }
        case .stayOnAccount:
            if let id = model.selectedAccountID {
                updateCardSettings { $0.accountSelection = .fixed(id) }
            }
        case .size(let size):
            updateCardSettings { $0.size = size }
            applyAppearance()
        case .stripScope(let scope):
            updateCardSettings { $0.stripScope = scope }
            applyAppearance()
        case .theme(let theme):
            updateCardSettings { $0.theme = theme }
            refreshTheme()
        case .toggleKeepAbove:
            let keeps = settings.keepsAboveWindows
            updateCardSettings { $0.keepsAboveWindows = !keeps }
            applyAppearance()
        case .toggleSnapping:
            let snaps = appearance.snapsWhileDragging
            #if DEBUG
            if debugAppearance != nil {
                debugAppearance?.snapsWhileDragging = !snaps
                return
            }
            #endif
            store.updateSettings { $0.appearance.snapsWhileDragging = !snaps }
        case .move(let anchor):
            move(to: anchor)
        case .moveToDisplay(let id):
            move(to: id)
        case .refresh:
            store.refresh()
        case .switchToIsland:
            store.actions.switchPresentationStyle(.island)
        case .openSettings:
            store.actions.openSettings()
        }
    }
}

extension FloatingCardController: PresentationSurface {}

#if DEBUG
/// Hooks for `DebugScenario`: in-memory overrides and synthetic input, never persisted.
extension FloatingCardController {
    struct DebugGeometry {
        let panelFrame: CGRect
        let cardFrame: CGRect
        let pillFrame: CGRect
        let form: String
        let anchor: String
        let displayID: String?
        let theme: String
        let size: String
        let isDragging: Bool
        let snapLocked: Bool
        let windowNumber: Int
    }

    var debugPanel: NSPanel { panel }

    var debugGeometry: DebugGeometry {
        DebugGeometry(
            panelFrame: panel.frame,
            cardFrame: cardScreenFrame,
            pillFrame: pillScreenFrame,
            form: interaction.form.map(\.rawValue) ?? "hidden",
            anchor: model.anchor.rawValue,
            displayID: currentDisplay?.id.rawValue,
            theme: settings.theme.rawValue,
            size: model.size.rawValue,
            isDragging: interaction.isDragging,
            snapLocked: arming.lockedTargetID != nil,
            windowNumber: panel.windowNumber
        )
    }

    /// Replaces the appearance settings in memory only; `nil` returns to the stored ones.
    func debugApply(appearance: AppearanceSettings?) {
        debugAppearance = appearance
        applyAppearance()
    }

    var debugSettings: AppearanceSettings { appearance }

    func debugExpand() {
        send(.expand)
    }

    func debugMinimize() {
        send(.minimize)
    }

    func debugSelectAccount(_ offset: Int) {
        switchAccount(by: offset)
    }

    func debugSetTheme(_ theme: CardTheme) {
        updateCardSettings { $0.theme = theme }
        refreshTheme()
    }

    func debugSetSize(_ size: CardSize) {
        updateCardSettings { $0.size = size }
        applyAppearance()
    }

    /// Re-resolves the card's display and placement, as a display change would.
    func debugSimulateDisplayChange() {
        refreshFrames()
    }

    /// For a grid over the card: which view a click there reaches and whether that view takes the first click of a
    /// window that is not key. A view that refuses it swallows the press, so a drag started there never begins.
    func debugHitMap(columns: Int, rows: Int) -> [[String: Any]] {
        guard let content = panel.contentView else { return [] }
        let form = model.isExpanded ? cardScreenFrame : pillScreenFrame
        var entries: [[String: Any]] = []
        for row in 0..<rows {
            for column in 0..<columns {
                let unit = CGPoint(x: (Double(column) + 0.5) / Double(columns), y: (Double(row) + 0.5) / Double(rows))
                let screen = CGPoint(x: form.minX + form.width * unit.x, y: form.minY + form.height * unit.y)
                let inWindow = panel.convertPoint(fromScreen: screen)
                let inSuper = content.superview.map { $0.convert(inWindow, from: nil) } ?? inWindow
                let hit = content.hitTest(inSuper)
                let probe = NSEvent.mouseEvent(
                    with: .leftMouseDown, location: inWindow, modifierFlags: [], timestamp: 0,
                    windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
                )
                entries.append([
                    "unit": [unit.x, unit.y],
                    "view": hit.map { String(describing: type(of: $0)) } ?? "nil",
                    "isHost": hit === hostingView,
                    "firstMouse": hit?.acceptsFirstMouse(for: probe) ?? false,
                ])
            }
        }
        func json(_ r: CGRect) -> [Double] { [r.minX, r.minY, r.width, r.height] }
        entries.append([
            "panel": json(panel.frame),
            "host": json(hostingView.frame),
            "interactive": json(hostingView.interactiveRect),
            "flipped": hostingView.isFlipped,
            "card": json(cardScreenFrame),
            "pill": json(pillScreenFrame),
            "modelCard": json(model.cardFrame),
            "modelPill": json(model.pillFrame),
            "expanded": model.isExpanded,
        ])
        return entries
    }

    /// Drags the card with synthesized mouse events sent through the panel, so hit testing, the hosting view's
    /// threshold and the responder chain are exercised exactly as with a real mouse. `target` is in screen coordinates.
    func debugMouseDrag(to target: CGPoint, steps: Int, from grip: CGPoint? = nil) async {
        guard cardScreenFrame.width > 0, !interaction.isDragging else { return }
        isSyntheticDrag = true
        defer { isSyntheticDrag = false }
        let form = model.isExpanded ? cardScreenFrame : pillScreenFrame
        // `grip` is a unit point inside the form (0,0 bottom-left … 1,1 top-right); the centre when nil.
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

    /// Carries the card from its centre to `target` (screen coordinates) and drops it there, through the same path
    /// real mouse input takes after the drag threshold.
    func debugDrag(to target: CGPoint, duration: TimeInterval, command: Bool) async {
        guard cardScreenFrame.width > 0, !interaction.isDragging else { return }
        let form = model.isExpanded ? cardScreenFrame : pillScreenFrame
        let start = CGPoint(x: form.midX, y: form.midY)
        let steps = max(2, Int((duration * 60).rounded()))
        debugCommandBypass = command
        isSyntheticDrag = true
        defer { isSyntheticDrag = false }
        dragBegan(pressedAt: start, pointer: start)
        for step in 1...steps {
            try? await Task.sleep(for: .milliseconds(Int((duration * 1_000 / Double(steps)).rounded())))
            let progress = Double(step) / Double(steps)
            let eased = progress * progress * (3 - 2 * progress)
            dragMoved(to: CGPoint(x: start.x + (target.x - start.x) * eased, y: start.y + (target.y - start.y) * eased))
        }
        dragEnded(at: target)
        debugCommandBypass = false
    }
}
#endif
