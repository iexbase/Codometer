import CodometerCore
import CodometerL10n
import SwiftUI

/// An honest preview of the floating card: the real `FloatingCardRootView` with the user's accounts, on a mock
/// display, at the place the card is actually kept.
///
/// Dragging it here uses the same magnet as the desktop, and the drop is remembered exactly as a drop on the desktop
/// is, so the preview and the real card never disagree.
struct CardStage: View {
    /// The mock display's logical size, in island points.
    static let virtualScreen = CGSize(width: 1_440, height: 900)
    static let displayHeight: CGFloat = 300
    static let bezelWidth: CGFloat = 8
    /// Room the mock menu bar and Dock take out of the usable area.
    static let menuBarHeight: CGFloat = 24

    let store: TrackerStore
    var backdrop: StageBackdrop = .colorful

    @State private var model = FloatingCardModel()
    @State private var dragStart: CGRect?
    /// Where the card is while it is carried, before the drop is remembered. Settings are written once, on the drop:
    /// a write per drag sample would save the file, re-export the widget and re-apply the surfaces sixty times a
    /// second.
    @State private var carried: CarriedCard?
    @Environment(\.l10n) private var l10n
    @Environment(\.colorScheme) private var colorScheme

    private var settings: FloatingCardSettings { store.settings.appearance.floatingCard }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            display
                .frame(height: Self.displayHeight)
            Text(l10n.card.stageHint)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .onAppear { sync() }
        .onChange(of: settings) { sync() }
        .onChange(of: store.settings.appearance.scale) { sync() }
        .onChange(of: colorScheme) { sync() }
    }

    private var display: some View {
        GeometryReader { proxy in
            let inset = Self.bezelWidth
            let available = CGSize(
                width: max(1, proxy.size.width - inset * 2),
                height: max(1, proxy.size.height - inset * 2)
            )
            let scale = min(available.width / Self.virtualScreen.width, available.height / Self.virtualScreen.height)
            // The mock display keeps the virtual screen's shape and is centred in whatever room the pane gives it.
            // A wider bezel than the screen it shows would put the card's top-right corner in the middle of the
            // wallpaper, which is exactly where the real card never is.
            let size = CGSize(width: Self.virtualScreen.width * scale, height: Self.virtualScreen.height * scale)
            ZStack(alignment: .topLeading) {
                StageBezel()
                ZStack(alignment: .topLeading) {
                    StageWallpaper(backdrop: backdrop)
                    virtualScreen
                        .frame(width: Self.virtualScreen.width, height: Self.virtualScreen.height, alignment: .topLeading)
                        .scaleEffect(scale, anchor: .topLeading)
                        .frame(width: size.width, height: size.height, alignment: .topLeading)
                }
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .offset(x: inset, y: inset)
            }
            .frame(width: size.width + inset * 2, height: size.height + inset * 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var virtualScreen: some View {
        ZStack(alignment: .topLeading) {
            StageMenuBar(backdrop: backdrop, width: Self.virtualScreen.width)
            StageDock()
                .frame(width: Self.virtualScreen.width)
                .offset(y: Self.virtualScreen.height - SettingsStageGeometry.dockGap - SettingsStageGeometry.dockHeight)
            FloatingCardRootView(store: store, model: model)
                .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
                .offset(x: canvasOrigin.x, y: canvasOrigin.y)
                .contentShape(Rectangle())
                // High priority: the card is full of buttons (chip, pill, dots, minimize) and a plain `.gesture`
                // would lose the drag to whichever of them the pointer went down on — the card then never moved.
                // A press that does not travel still fails this gesture and reaches the button as a click.
                .highPriorityGesture(drag)
                .accessibilityHidden(true)
        }
        .frame(width: Self.virtualScreen.width, height: Self.virtualScreen.height, alignment: .topLeading)
    }

    // MARK: - Geometry

    /// The mock display as `FloatingCardGeometry` sees it: y upwards, menu bar and Dock removed.
    private var stage: CGRect {
        let visible = CGRect(
            x: 0,
            y: SettingsStageGeometry.dockReserve,
            width: Self.virtualScreen.width,
            height: Self.virtualScreen.height - SettingsStageGeometry.dockReserve - Self.menuBarHeight
        )
        return visible.insetBy(dx: CardMetrics.screenInset, dy: CardMetrics.screenInset)
    }

    private var metrics: CardMetrics { CardMetrics(store.settings.appearance.scale) }

    private var cardFrameOnStage: CGRect {
        if let carried { return carried.frame }
        let size = metrics.cardSize(metrics.fittingSize(settings.size, in: stage) ?? .compact)
        guard let placement = placement else {
            return FloatingCardGeometry.frame(size: size, anchor: .topTrailing, at: FloatingCardGeometry.targetPoint(.topTrailing, in: stage))
        }
        return FloatingCardGeometry.frame(for: placement, size: size, in: stage)
    }

    /// The anchor the preview pins right now: the one being carried, else the remembered one.
    private var stageAnchor: CardAnchor {
        carried?.anchor ?? placement?.anchor ?? .topTrailing
    }

    /// The placement the preview shows: the one remembered for the current display, else the default.
    private var placement: CardPlacement? {
        if let current = settings.placements.current, let saved = settings.placements.placement(for: current) {
            return saved
        }
        return settings.placements.byDisplay.first
    }

    private var canvasSize: CGSize {
        CGSize(
            width: model.cardFrame.width + metrics.windowMargin * 2,
            height: model.cardFrame.height + metrics.windowMargin * 2
        )
    }

    /// The canvas's top-left corner in the virtual screen's view coordinates.
    private var canvasOrigin: CGPoint {
        let card = cardFrameOnStage
        let local = IslandGeometry.local(card, in: CGRect(origin: .zero, size: Self.virtualScreen))
        return CGPoint(x: local.minX - metrics.windowMargin, y: local.minY - metrics.windowMargin)
    }

    private func sync() {
        let card = cardFrameOnStage
        let anchor = stageAnchor
        let pillSize = metrics.pillSize(accounts: store.visiblePresentations.count, templates: CardPillTemplates.everyLanguage)
        let canvas = card.insetBy(dx: -metrics.windowMargin, dy: -metrics.windowMargin)
        let pill = FloatingCardGeometry.aligned(size: pillSize, in: card, anchor: anchor)
        model.metrics = metrics
        model.size = metrics.fittingSize(settings.size, in: stage) ?? .compact
        model.thirdTile = settings.thirdTile
        model.stripScope = settings.stripScope
        model.anchor = anchor
        model.cardFrame = IslandGeometry.local(card, in: canvas)
        model.pillFrame = IslandGeometry.local(pill, in: canvas)
        model.isExpanded = !settings.isMinimized
        model.theme = CardThemeTokens.resolve(
            theme: settings.theme,
            scheme: colorScheme,
            reducesTransparency: false,
            increasesContrast: false
        )
        if model.selectedAccountID == nil {
            model.selectedAccountID = CardAccountSelector.mostUrgent(store.visiblePresentations)?.id
        }
    }

    // MARK: - Drag

    private var drag: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                let start = dragStart ?? cardFrameOnStage
                dragStart = start
                carried = carry(start: start, translation: value.translation)
                sync()
            }
            .onEnded { value in
                let dropped = carry(start: dragStart ?? cardFrameOnStage, translation: value.translation)
                dragStart = nil
                carried = dropped
                remember(dropped)
                carried = nil
                sync()
            }
    }

    /// Where the magnet puts the card for one pointer sample. The same pure geometry the desktop card uses, so the
    /// preview and the real card never disagree.
    private func carry(start: CGRect, translation: CGSize) -> CarriedCard {
        // The stage's y runs downwards; the geometry's runs upwards.
        let free = start.offsetBy(dx: translation.width, dy: -translation.height)
        let resolution = FloatingCardGeometry.resolve(
            free: free,
            in: stage,
            radius: MagnetLaw.radius,
            snaps: store.settings.appearance.snapsWhileDragging
        )
        let frame = FloatingCardGeometry.clamp(resolution.frame, in: stage)
        return CarriedCard(
            frame: frame,
            anchor: resolution.snappedAnchor ?? FloatingCardGeometry.gravity(of: frame, in: stage),
            snapped: resolution.snappedAnchor != nil
        )
    }

    /// Writes the drop, once. Without a known display the preview only moves: there is nothing to remember it under.
    private func remember(_ dropped: CarriedCard) {
        guard let displayID = settings.placements.current ?? store.displays.first?.id else {
            model.anchor = dropped.anchor
            return
        }
        let point = FloatingCardGeometry.anchorPoint(of: dropped.frame, anchor: dropped.anchor)
        let placement = CardPlacement(
            displayID: displayID,
            anchor: dropped.anchor,
            snapped: dropped.snapped,
            x: UnitInterval.clamped((point.x - stage.minX) / stage.width),
            y: UnitInterval.clamped((stage.maxY - point.y) / stage.height)
        )
        store.updateSettings { settings in
            var placements = settings.appearance.floatingCard.placements
            placements.remember(placement)
            placements.current = displayID
            settings.appearance.floatingCard.placements = placements
        }
    }

    /// The card while the pointer carries it: drawn, but not yet written to the settings.
    struct CarriedCard: Equatable {
        let frame: CGRect
        let anchor: CardAnchor
        let snapped: Bool
    }
}

