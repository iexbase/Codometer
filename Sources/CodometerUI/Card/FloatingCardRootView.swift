import CodometerCore
import CodometerL10n
import SwiftUI

/// Everything inside the floating card's window: one contour that carries the card and the pill, the content of both
/// forms, and the coach mark shown once.
///
/// The view fills the panel's canvas and places both forms at the frames the controller computed, so moving or
/// resizing the window never moves anything on screen. It loads no history and asks for no analytics: the card is
/// glanceable, and `isDeckVisible` stays false for it.
public struct FloatingCardRootView: View {
    let store: TrackerStore
    let model: FloatingCardModel

    /// Off in offscreen renders, where `ImageRenderer` draws no glass: the scrim stands in for it, which is exactly
    /// what the contrast rules are measured against.
    @Environment(\.rendersGlass) private var rendersGlass
    /// Off in offscreen renders and wherever the host asks for a still card; the card narrows it further, never widens
    /// it, exactly like `IslandRootView`.
    @Environment(\.liveEffectsEnabled) private var inheritedLiveEffects

    public init(store: TrackerStore, model: FloatingCardModel) {
        self.store = store
        self.model = model
    }

    /// The card's own words. Taken from the store, not from the environment: the root *injects* `\.l10n` for its
    /// children, so reading the inherited value here would leave the coach mark and the accessibility labels in
    /// whatever language the host happened to carry.
    private var l10n: Localizer { store.localizer }

    /// Live Core Animation layers run only when the host allows them and the energy policy does.
    private var liveEffects: Bool { inheritedLiveEffects && store.allowsLiveEffects }

    private var accounts: [AccountPresentation] {
        store.visiblePresentations
    }

    /// The contour, in the canvas's own coordinates, so the shape that fills, outlines and clips is the same one
    /// wherever the canvas sits inside the panel.
    private var shape: CardMorphShape {
        CardMorphShape(
            progress: model.morphProgress,
            anchor: model.anchor,
            pill: model.pillFrame,
            card: model.cardFrame,
            pillCorner: model.metrics.pillCorner,
            cardCorner: model.metrics.cardCorner,
            wobble: model.metrics.wobble,
            isLiquid: !Motion.reducesMotion
        )
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            surface
            forms
            coachMark
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.cardTheme, model.theme)
        .environment(\.cardMetrics, model.metrics)
        .environment(\.l10n, store.localizer)
        .environment(\.locale, store.localizer.locale)
        .environment(\.liveEffectsEnabled, liveEffects)
        // The card's own rings celebrate a reset; the form that is not on screen carries `liveEffectsEnabled == false`
        // and never plays one, so the card and its pill share the single `.card` turn between them.
        .environment(\.ceremonyStage, ceremonyStage)
        .environment(\.isDeckVisible, false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(l10n.card.cardA11y)
        .accessibilityActions { customActions }
    }

    // MARK: - Reset ceremonies

    /// The stage the card's rings celebrate resets on, or `nil` when they must not.
    private var ceremonyStage: CeremonyStage? {
        Self.ceremonyStage(store: store, liveEffects: liveEffects)
    }

    /// Whether the card celebrates, and on which board.
    ///
    /// A ceremony is spent the first time a surface plays it, so a card that cannot be seen must not take its turn:
    /// the settings preview and the offscreen renders run without live effects, and so does whichever of the two
    /// forms is only prewarmed. `CardFaceView` and `CardPillView` both report `.card` to the ring gauge, so the two
    /// forms share one turn, exactly as `RailView` and the deck each have theirs.
    static func ceremonyStage(store: TrackerStore, liveEffects: Bool) -> CeremonyStage? {
        guard liveEffects, store.settings.appearance.celebratesResets else { return nil }
        return CeremonyStage(surface: .card, board: store.ceremonies, now: store.now) { [store] id, surface in
            store.markCeremonyPlayed(id, on: surface)
        }
    }

    // MARK: - Surface

    private var surface: some View {
        let theme = model.theme
        return ZStack {
            if theme.isGlass, rendersGlass {
                Color.clear
                    .glassEffect(Glass.regular, in: shape)
                shape.fill(Color.black.opacity(CardThemeTokens.glassScrim))
            } else {
                // The glass theme's stand-in is its own scrim over the darkest desktop, the worst case the contrast
                // tests measure.
                shape.fill(theme.surfaceColor)
            }
            shape.stroke(theme.hairlineColor.opacity(0.55), lineWidth: theme.hairlineWidth)
        }
        .compositingGroup()
        // The shadow steps aside while the contour travels, so no shadow path is rebuilt per frame.
        .shadow(
            color: .black.opacity(model.isMorphing || model.isDragging ? 0 : theme.shadowOpacity),
            radius: theme.shadowRadius,
            y: theme.shadowRadius * 0.25
        )
        .animation(Motion.quickFade, value: model.isMorphing)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Forms

    private var forms: some View {
        ZStack(alignment: .topLeading) {
            if model.isExpanded || model.prewarmsCard {
                CardFaceView(store: store, model: model, accounts: accounts)
                    .offset(x: model.cardFrame.minX, y: model.cardFrame.minY)
                    .opacity(model.isExpanded ? 1 : 0)
                    .allowsHitTesting(model.isExpanded)
                    .accessibilityHidden(!model.isExpanded)
                    // A hidden copy never runs orbits or pulses.
                    .environment(\.liveEffectsEnabled, model.isExpanded && liveEffects)
                    .animation(Motion.deckReveal, value: model.isExpanded)
            }
            if !model.isExpanded || model.prewarmsPill {
                CardPillView(store: store, model: model, accounts: accounts)
                    .offset(x: model.pillFrame.minX, y: model.pillFrame.minY)
                    .opacity(model.isExpanded ? 0 : 1)
                    .allowsHitTesting(!model.isExpanded)
                    .accessibilityHidden(model.isExpanded)
                    .environment(\.liveEffectsEnabled, !model.isExpanded && liveEffects)
                    .animation(Motion.railReveal, value: model.isExpanded)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipShape(shape)
    }

    // MARK: - Coach mark

    @ViewBuilder
    private var coachMark: some View {
        if model.showsCoachMark {
            let metrics = model.metrics
            let y = model.coachMarkBelow
                ? model.cardFrame.maxY + metrics.coachMarkGap
                : model.cardFrame.minY - metrics.coachMarkGap - metrics.coachMarkHeight
            Text(l10n.card.coachMark)
                .font(metrics.font(.footer))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: metrics.coachMarkHeight)
                .background(Capsule().fill(Color.black.opacity(0.78)))
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: model.cardFrame.minX, y: y)
                .transition(.opacity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Accessibility

    @ViewBuilder
    private var customActions: some View {
        let card = l10n.card
        Button(model.isExpanded ? card.minimize : card.expand) {
            model.send(model.isExpanded ? .minimize : .expand)
        }
        if accounts.count > 1 {
            Button(card.nextAccount) { model.send(.nextAccount) }
            Button(card.previousAccount) { model.send(.previousAccount) }
        }
        Button(l10n.menu.refreshAll) { model.send(.refresh) }
        Button(card.topLeft) { model.send(.move(.topLeading)) }
        Button(card.topRight) { model.send(.move(.topTrailing)) }
        Button(card.bottomLeft) { model.send(.move(.bottomLeading)) }
        Button(card.bottomRight) { model.send(.move(.bottomTrailing)) }
        Button(card.center) { model.send(.move(.center)) }
        Button(l10n.menu.settings) { model.send(.openSettings) }
    }
}
