import CodometerCore
import CodometerL10n
import SwiftUI

/// Preview choices shared by the panes that show the stage, kept while the settings window is open.
struct IslandStageOptions: Equatable {
    var backdrop: StageBackdrop = .colorful
    var showsExpanded = false
}

/// An honest preview: the real `IslandRootView` with the user's accounts on a mock display.
///
/// The island is laid out on a virtual screen in true island points, with the frame the island
/// controller would give its window (rail at rest, deck frame while open or folding), and the whole
/// screen is drawn at about 0.8×. It opens with the chosen trigger (hover, click or both), follows the
/// same intent and grace delays, and can be dragged to another edge, which updates the settings.
struct IslandStage: View {
    /// The display's height never changes, so nothing below it moves when the island opens.
    static let displayHeight: CGFloat = 460
    static let bezelWidth: CGFloat = 8
    private static let space = "IslandStage.virtualScreen"
    private static let hoverIntentDelay: Duration = .milliseconds(130)
    private static let collapseGrace: Duration = .milliseconds(320)
    private static let foldFallback: Duration = .milliseconds(900)

    let store: TrackerStore
    @Binding var options: IslandStageOptions

    @State private var model: IslandModel
    @State private var sizes = IslandSizes.zero
    /// The window stays deck-sized until the fold has finished, exactly like the island controller.
    @State private var holdsDeckFrame = false
    /// Pointer position (virtual AppKit coordinates) while the island is carried.
    @State private var dragPoint: CGPoint?
    @State private var interaction = StageInteraction()
    /// The virtual screen the island is laid out on, kept so the layout (and its notch) can be built outside
    /// the geometry reader.
    @State private var virtualScreen: SettingsStageGeometry.Screen?
    /// Magnetic snapping, exactly as the island controller resolves it — without haptics: a settings window is
    /// usually dragged with a mouse.
    @State private var snapState = EdgeSnapState()
    @State private var pendingDrop: (edge: ScreenEdge, offset: Double)?
    @Environment(\.l10n) private var l10n

    init(store: TrackerStore, options: Binding<IslandStageOptions>) {
        self.store = store
        _options = options
        _model = State(initialValue: IslandModel(layout: IslandLayout(appearance: store.settings.appearance)))
    }

    private var trigger: IslandOpenTrigger { store.settings.appearance.openTrigger }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            toolbar
            display
                .frame(height: Self.displayHeight)
            hint
        }
        .padding(14)
        .onAppear {
            syncLayout(animated: false)
            model.onRequest = { request in handle(request) }
        }
        .onDisappear {
            interaction.cancelTimers()
            model.onRequest = nil
        }
        .onChange(of: store.settings.appearance) { _, _ in syncLayout(animated: true) }
        .onChange(of: options.showsExpanded) { _, showsExpanded in
            if showsExpanded {
                expand()
            } else {
                interaction.isPinned = false
                if !(interaction.isHovering && trigger != .click) { collapse() }
            }
        }
        .onChange(of: model.isExpanded) { _, isExpanded in
            expansionChanged(isExpanded)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(l10n.stage.previewA11y)
    }

    /// The hint for the chosen trigger, over hidden copies of every hint so switching never changes the height.
    private var hint: some View {
        ZStack(alignment: .topLeading) {
            ForEach(IslandOpenTrigger.allCases) { candidate in
                hintLabel(candidate)
                    .hidden()
                    .accessibilityHidden(true)
            }
            hintLabel(trigger)
        }
    }

    private func hintLabel(_ trigger: IslandOpenTrigger) -> some View {
        Label(Self.hint(trigger, l10n: l10n), systemImage: trigger == .click ? "cursorarrow.click" : "cursorarrow.rays")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The hint under the stage for a trigger; each fits one line at the settings window's minimum width.
    static func hint(_ trigger: IslandOpenTrigger, l10n: Localizer) -> String {
        switch trigger {
        case .hover: l10n.stage.hoverHint
        case .click: l10n.stage.clickHint
        case .hoverOrClick: l10n.stage.hoverOrClickHint
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(StageBackdrop.allCases) { backdrop in
                        Button {
                            withAnimation(Motion.content) { options.backdrop = backdrop }
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(backdrop.swatch)
                                    .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1))
                                    .frame(width: 13, height: 13)
                                Text(backdrop.title(l10n))
                                    .lineLimit(1)
                            }
                            .fixedSize()
                        }
                        .buttonStyle(AnyPrimitiveButtonStyle.glass(selected: options.backdrop == backdrop))
                        .help(backdrop.help(l10n))
                        .accessibilityLabel(backdrop.help(l10n))
                        .accessibilityAddTraits(options.backdrop == backdrop ? .isSelected : [])
                    }
                }
            }
            .fixedSize()
            Spacer(minLength: 12)
            Text(l10n.stage.showExpanded)
                .lineLimit(1)
                .fixedSize()
                .accessibilityHidden(true)
            Toggle(l10n.stage.showExpanded, isOn: $options.showsExpanded)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    // MARK: - Display

    private var display: some View {
        GeometryReader { proxy in
            let inset = Self.bezelWidth
            let screenSize = CGSize(width: max(1, proxy.size.width - inset * 2), height: max(1, proxy.size.height - inset * 2))
            let scale = SettingsStageGeometry.displayScale(display: screenSize, deck: sizes.deck)
            let screen = SettingsStageGeometry.screen(display: screenSize, scale: scale)

            ZStack(alignment: .topLeading) {
                StageBezel()
                ZStack(alignment: .topLeading) {
                    StageWallpaper(backdrop: options.backdrop)
                        .contentShape(Rectangle())
                        .onTapGesture { outsideClicked() }
                    stage(screen)
                        .frame(width: screen.frame.width, height: screen.frame.height, alignment: .topLeading)
                        .scaleEffect(scale, anchor: .topLeading)
                        .frame(width: screenSize.width, height: screenSize.height, alignment: .topLeading)
                        .animation(Motion.content, value: scale)
                        .onChange(of: screen) { _, newScreen in
                            virtualScreen = newScreen
                            syncLayout(animated: false)
                        }
                        .onAppear {
                            virtualScreen = screen
                            syncLayout(animated: false)
                        }
                }
                .frame(width: screenSize.width, height: screenSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .offset(x: inset, y: inset)
            }
        }
    }

    private func stage(_ screen: SettingsStageGeometry.Screen) -> some View {
        let frame = islandFrame(in: screen)
        return ZStack(alignment: .topLeading) {
            StageMenuBar(backdrop: options.backdrop, width: screen.frame.width)
            if let notch = SettingsStageGeometry.notch(in: screen), hasNotchedDisplay {
                StageNotch(notch: notch, screenWidth: screen.frame.width)
            }
            StageDock()
                .frame(width: screen.frame.width)
                .offset(y: screen.frame.height - SettingsStageGeometry.dockGap - SettingsStageGeometry.dockHeight)
            IslandRootView(store: store, model: model) { newSizes in
                sizesChanged(newSizes)
            }
            .frame(width: frame.width, height: frame.height)
            // Like the island's window, the whole frame takes the pointer: without this only drawn pixels
            // (ring strokes, text) would, and glass between them would ignore hover, clicks and drags.
            .contentShape(Rectangle())
            .onHover { inside in hoverChanged(inside) }
            .onTapGesture { islandClicked() }
            .gesture(dragGesture(in: screen))
            .offset(x: frame.minX, y: frame.minY)
        }
        .coordinateSpace(.named(Self.space))
    }

    /// The island's "window" in view coordinates: carried, open, or at rest; the whole screen until measured.
    private func islandFrame(in screen: SettingsStageGeometry.Screen) -> CGRect {
        if let dragPoint, sizes.rail != .zero {
            let carried = SettingsStageGeometry.dragFrame(center: dragPoint, rail: sizes.rail, in: screen)
            return SettingsStageGeometry.viewRect(carried, in: screen)
        }
        guard let window = SettingsStageGeometry.windowFrame(
            rail: sizes.rail,
            deck: sizes.deck,
            layout: model.layout,
            offset: store.settings.appearance.offset.value,
            showsDeck: model.isExpanded || holdsDeckFrame,
            in: screen
        ) else {
            return screen.frame
        }
        return SettingsStageGeometry.viewRect(window, in: screen)
    }

    // MARK: - Sizes and layout

    private func sizesChanged(_ newSizes: IslandSizes) {
        // The rail and the deck report one after the other when the stage appears. Neither first value may
        // animate, or the whole mock display would visibly zoom to its fitted scale.
        let isFirstMeasurement = sizes.rail == .zero || sizes.deck == .zero
        if isFirstMeasurement || model.isDragging {
            withoutAnimation { sizes = newSizes }
        } else {
            // A new orientation or scale glides into place instead of snapping.
            withAnimation(Motion.geometry) { sizes = newSizes }
        }
        if options.showsExpanded, !model.isExpanded, !model.isDragging {
            expand()
        }
    }

    /// Whether a connected display has a camera notch: only then does the preview draw one and offer fusion.
    private var hasNotchedDisplay: Bool {
        store.displays.contains { $0.notch != nil }
    }

    /// The notch the preview lays the island out with, in virtual screen points.
    private var stageNotch: NotchGeometry? {
        guard hasNotchedDisplay, let virtualScreen else { return nil }
        return SettingsStageGeometry.notch(in: virtualScreen)
    }

    private func syncLayout(animated: Bool) {
        guard !model.isDragging else { return }
        let layout = IslandLayout(appearance: store.settings.appearance, notch: stageNotch)
        guard layout != model.layout else { return }
        if animated {
            withAnimation(Motion.geometry) { model.layout = layout }
        } else {
            withoutAnimation { model.layout = layout }
        }
    }

    // MARK: - Opening and closing

    private func hoverChanged(_ inside: Bool) {
        interaction.isHovering = inside
        // The rail swells under the pointer in every trigger mode, like the real island.
        defer { updateSwell() }
        guard !model.isDragging, trigger != .click else { return }
        if inside {
            interaction.collapseTask?.cancel()
            guard !model.isExpanded else { return }
            // Refresh time-dependent text before measuring starts, so the deck never re-adjusts after opening.
            store.tick(Date())
            interaction.hoverTask?.cancel()
            interaction.hoverTask = Task {
                try? await Task.sleep(for: Self.hoverIntentDelay)
                guard !Task.isCancelled, interaction.isHovering else { return }
                expand()
            }
        } else {
            interaction.hoverTask?.cancel()
            guard model.isExpanded, !interaction.isPinned, !options.showsExpanded else { return }
            interaction.collapseTask?.cancel()
            interaction.collapseTask = Task {
                try? await Task.sleep(for: Self.collapseGrace)
                guard !Task.isCancelled, !interaction.isHovering, !interaction.isPinned else { return }
                collapse()
            }
        }
    }

    private func islandClicked() {
        guard !model.isDragging else { return }
        switch trigger {
        case .hover:
            return
        case .click:
            guard !model.isExpanded else { return }
            store.tick(Date())
            expand()
        case .hoverOrClick:
            interaction.hoverTask?.cancel()
            interaction.collapseTask?.cancel()
            interaction.isPinned = true
            guard !model.isExpanded else { return }
            store.tick(Date())
            expand()
        }
    }

    /// Clicks inside the island (attention tab, deck header) handled like the island controller does: the tab
    /// opens the deck on its queue; the header pins a deck opened by hover and closes a pinned one.
    private func handle(_ request: IslandRequest) {
        guard !model.isDragging else { return }
        switch request {
        case .openAttention:
            if !store.attentionQueue.isEmpty {
                model.deckFocus = .attentionQueue
            }
            interaction.hoverTask?.cancel()
            interaction.collapseTask?.cancel()
            if trigger.pinsOnClick {
                interaction.isPinned = true
            }
            guard !model.isExpanded else { return }
            store.tick(Date())
            expand()
        case .headerClick:
            guard model.isExpanded, trigger.pinsOnClick else { return }
            if trigger == .click || interaction.isPinned || options.showsExpanded {
                interaction.isPinned = false
                if options.showsExpanded { options.showsExpanded = false }
                collapse()
            } else {
                interaction.collapseTask?.cancel()
                interaction.isPinned = true
            }
        }
    }

    private func outsideClicked() {
        interaction.isPinned = false
        collapse()
    }

    private func expand() {
        guard !model.isExpanded, !model.isDragging, sizes.deck != .zero else { return }
        interaction.foldGeneration += 1
        interaction.foldTask?.cancel()
        interaction.isFolding = false
        // The window takes the deck frame first; the rail keeps its place because it is anchored in it.
        withoutAnimation { holdsDeckFrame = true }
        // The same droplet timing as the island controller; `IslandRootView` leaves an animation it recognises as the
        // morph's untouched.
        withAnimation(Motion.liquidOpen) { model.isExpanded = true }
        updateSwell()
    }

    private func collapse() {
        guard model.isExpanded, !options.showsExpanded else { return }
        interaction.foldGeneration += 1
        let generation = interaction.foldGeneration
        interaction.isFolding = true
        withAnimation(Motion.liquidFold, completionCriteria: .logicallyComplete) {
            model.isExpanded = false
        } completion: {
            finishFold(generation: generation)
        }
        scheduleFoldFallback(generation: generation)
    }

    /// Keeps the frame honest when something inside the island opens or closes it by itself (for example a
    /// click on the deck header or on the attention tab), not through `expand()` or `collapse()`.
    private func expansionChanged(_ isExpanded: Bool) {
        guard !model.isDragging else { return }
        if isExpanded {
            guard !holdsDeckFrame else { return }
            interaction.foldGeneration += 1
            interaction.foldTask?.cancel()
            interaction.isFolding = false
            withoutAnimation { holdsDeckFrame = true }
            return
        }
        guard holdsDeckFrame, !interaction.isFolding else { return }
        interaction.foldGeneration += 1
        interaction.isFolding = true
        interaction.isPinned = false
        if options.showsExpanded { options.showsExpanded = false }
        scheduleFoldFallback(generation: interaction.foldGeneration)
    }

    private func scheduleFoldFallback(generation: Int) {
        interaction.foldTask?.cancel()
        interaction.foldTask = Task {
            try? await Task.sleep(for: Self.foldFallback)
            guard !Task.isCancelled else { return }
            finishFold(generation: generation)
        }
    }

    private func finishFold(generation: Int) {
        guard generation == interaction.foldGeneration, !model.isExpanded, holdsDeckFrame else { return }
        interaction.isFolding = false
        withoutAnimation { holdsDeckFrame = false }
        if model.deckFocus != .overview {
            model.deckFocus = .overview
        }
        // The pointer may have come or gone during the fold.
        updateSwell()
    }

    /// Brings the rail's hover swell in line with the pointer, with the rules of `IslandModel.isHovered`: a soft
    /// spring at rest, the opening's own spring while open, and not at all during a fold (so the fold keeps its course
    /// and its completion; `finishFold` catches up).
    private func updateSwell() {
        let swells = interaction.isHovering && !model.isDragging
        guard model.isHovered != swells else { return }
        if model.isExpanded {
            withAnimation(Motion.liquidOpen) { model.isHovered = swells }
        } else if !holdsDeckFrame {
            withAnimation(Motion.liquidSwell) { model.isHovered = swells }
        }
    }

    // MARK: - Dragging

    private func dragGesture(in screen: SettingsStageGeometry.Screen) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named(Self.space))
            .onChanged { value in dragMoved(to: value.location, in: screen) }
            .onEnded { value in dragEnded(at: value.location, in: screen) }
    }

    private func dragMoved(to location: CGPoint, in screen: SettingsStageGeometry.Screen) {
        guard sizes.rail != .zero else { return }
        if !model.isDragging {
            interaction.cancelTimers()
            interaction.foldGeneration += 1
            interaction.isPinned = false
            interaction.isFolding = false
            withoutAnimation {
                holdsDeckFrame = false
                model.isExpanded = false
                model.isHovered = false
                model.isDragging = true
            }
        }
        let point = SettingsStageGeometry.screenPoint(location, in: screen)
        let placement = SettingsStageGeometry.dropPlacement(at: point, rail: sizes.rail, style: store.settings.appearance.style, in: screen)
        let resolution = resolveSnapping(pointer: point, placement: placement, in: screen)
        pendingDrop = (placement.edge, resolution.dropOffset)
        // While carried, the island is a free capsule that turns to match the edge it will land on.
        let layout = IslandLayout(
            edge: placement.edge,
            anchor: IslandGeometry.anchor(edge: placement.edge, offset: resolution.dropOffset),
            style: .floating,
            metrics: model.layout.metrics,
            notch: stageNotch
        )
        if layout != model.layout {
            withAnimation(Motion.snappy) { model.layout = layout }
        }
        let snapped = resolution.locked != nil
        if model.isSnapped != snapped {
            withAnimation(Motion.content) { model.isSnapped = snapped }
        }
        // The magnet pulls the drawn capsule; the pointer itself is never moved.
        withoutAnimation {
            dragPoint = CGPoint(x: point.x + resolution.displayShift.dx, y: point.y + resolution.displayShift.dy)
        }
    }

    /// The same `EdgeSnapping` the island controller runs, in virtual screen coordinates and without haptics.
    private func resolveSnapping(
        pointer: CGPoint,
        placement: (edge: ScreenEdge, offset: Double),
        in screen: SettingsStageGeometry.Screen
    ) -> EdgeSnapResolution {
        let appearance = store.settings.appearance
        let area = IslandGeometry.area(edge: placement.edge, style: appearance.style, screen: screen.frame, visible: screen.visible)
        let railLength = max(sizes.rail.width, sizes.rail.height)
        guard appearance.snapsWhileDragging else {
            snapState = EdgeSnapState()
            return EdgeSnapResolution(displayShift: .zero, dropOffset: placement.offset, state: snapState, haptic: nil, locked: nil)
        }
        let targets = EdgeSnapping.targets(
            edge: placement.edge,
            railLength: railLength,
            area: area,
            style: appearance.style,
            notch: appearance.notchFusion == .automatic ? stageNotch : nil,
            scale: appearance.scale.value
        )
        let resolution = EdgeSnapping.resolve(
            pointer: pointer,
            placement: placement,
            targets: targets,
            area: area,
            railLength: railLength,
            style: appearance.style,
            state: snapState,
            now: ProcessInfo.processInfo.systemUptime,
            bypass: false
        )
        snapState = resolution.state
        return resolution
    }

    private func dragEnded(at location: CGPoint, in screen: SettingsStageGeometry.Screen) {
        guard model.isDragging else { return }
        let point = SettingsStageGeometry.screenPoint(location, in: screen)
        let free = SettingsStageGeometry.dropPlacement(at: point, rail: sizes.rail, style: store.settings.appearance.style, in: screen)
        let placement = pendingDrop?.edge == free.edge ? (edge: free.edge, offset: pendingDrop?.offset ?? free.offset) : free
        pendingDrop = nil
        snapState = EdgeSnapState()
        withAnimation(Motion.geometry) {
            dragPoint = nil
            model.isDragging = false
            model.isSnapped = false
        }
        store.updateSettings { settings in
            settings.appearance.edge = placement.edge
            settings.appearance.offset = EdgeOffset.clamped(placement.offset)
        }
        syncLayout(animated: true)
        if options.showsExpanded { expand() }
    }

    private func withoutAnimation(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }
}

/// Timers and pointer state of the stage that never affect rendering by themselves.
@MainActor
private final class StageInteraction {
    var isHovering = false
    var isPinned = false
    /// A fold started and the deck frame is still held until it finishes.
    var isFolding = false
    var foldGeneration = 0
    var hoverTask: Task<Void, Never>?
    var collapseTask: Task<Void, Never>?
    var foldTask: Task<Void, Never>?

    func cancelTimers() {
        hoverTask?.cancel()
        collapseTask?.cancel()
        foldTask?.cancel()
    }
}
