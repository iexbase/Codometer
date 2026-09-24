import CodometerCore
import CodometerL10n
import SwiftUI

/// The island: a compact rail at rest that grows out of the screen edge into a deck like a droplet.
///
/// The view covers the island's whole canvas (the screen, in the app) and places the island at
/// `model.frames`, which the window controller computes from the measured sizes. Expanding only flips
/// `model.isExpanded`: one transaction (`Motion.liquid(expanding:)`) drives the liquid outline
/// (`LiquidIslandShape`: the rail's free side swells into a drop that pours into the deck), which clips the content
/// and carries the glass and the rim. The content never moves or re-lays out: the rail fades out as the drop leaves
/// it, and the deck, already laid out at its final place, fades and scales in while the drop pours. Frames never
/// change because of expanding, so an interrupted fold simply retargets the same animation.
/// Hidden copies of both states report their sizes before anything is shown.
public struct IslandRootView: View {
    let store: TrackerStore
    let model: IslandModel
    let onSizesChange: (IslandSizes) -> Void

    /// Natural sizes of the hidden copies (the deck never capped, so no scroll view is ever measured).
    @State private var measured = IslandSizes.zero
    /// The sizes the island uses and reports: `measured` with the deck clamped to its room on screen.
    @State private var sizes = IslandSizes.zero
    /// Live effects allowed by whoever hosts the island (e.g. off in a still settings preview).
    @Environment(\.liveEffectsEnabled) private var inheritedLiveEffects

    public init(store: TrackerStore, model: IslandModel, onSizesChange: @escaping (IslandSizes) -> Void) {
        self.store = store
        self.model = model
        self.onSizesChange = onSizesChange
    }

    public var body: some View {
        // The rail lists only the accounts of the chosen group; the deck gets every account and applies the group
        // filter to its dial row itself, so switching the filter never changes the deck's size.
        let accounts = IslandAccounts(rail: store.visiblePresentations, deck: store.presentations)
        let layout = model.layout
        let appearance = model.appearanceOverride ?? store.settings.appearance

        // One island, placed by the window controller's frames when it has them and anchored in whatever space it is
        // offered until then. Deliberately not two branches: switching between them would give the island a second
        // identity, rebuilding its dials and dropping the ring anchors the flight needs.
        let placed = model.frames
        let stage = placed.map(IslandMorphLayout.init(frames:))
            ?? .anchored(rail: sizes.rail, deck: sizes.deck, anchor: layout.anchor)
        let origin = placed?.union.origin ?? .zero
        ZStack(alignment: .topLeading) {
            if sizes.rail != .zero {
                island(accounts: accounts, layout: layout, appearance: appearance, stage: stage)
                    .offset(x: origin.x, y: origin.y)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: placed == nil ? layout.anchor.alignment : .topLeading
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(alignment: .topLeading) {
            measurements(accounts: accounts)
        }
        .onChange(of: model.maximumDeckHeight) { _, _ in
            publishSizes()
        }
        // The measured copies too, so sizes are measured in the language that is shown.
        .environment(\.l10n, store.localizer)
        .environment(\.locale, store.localizer.locale)
        // The energy policy can pause orbits and pulses; the hidden measurement copies keep theirs off regardless.
        .environment(\.liveEffectsEnabled, inheritedLiveEffects && store.allowsLiveEffects)
        .ignoresSafeArea()
    }

    /// The static silhouette of either state (no morph), for renders that draw one state on its own, such as the
    /// interface snapshots. The live island uses `liquidShape`.
    static func silhouette(layout: IslandLayout, expanded: Bool, frame: CGRect? = nil) -> IslandSilhouette {
        let metrics = layout.metrics
        switch layout.style {
        case .attached:
            return IslandSilhouette(
                edge: layout.edge,
                style: .attached,
                cornerRadius: expanded ? metrics.deckCorner : metrics.railCorner,
                shoulder: metrics.shoulder,
                islandFrame: frame
            )
        case .floating:
            // A capsule at rest: half the rail's short side, so the radius animates smoothly into the deck's.
            let capsule = frame.map { min($0.width, $0.height) / 2 } ?? 999
            return IslandSilhouette(
                edge: layout.edge,
                style: .floating,
                cornerRadius: expanded ? metrics.deckCorner : capsule,
                shoulder: 0,
                islandFrame: frame
            )
        }
    }

    /// The island's liquid outline for a stage: the rail when collapsed, the deck when expanded, swelling a little
    /// while the pointer rests on the rail. Without liquid motion (Reduce Motion) it is a plain rounded rectangle.
    static func liquidShape(layout: IslandLayout, stage: IslandMorphLayout, expanded: Bool, swells: Bool, liquid: Bool) -> LiquidIslandShape {
        let metrics = layout.metrics
        let attached = layout.style == .attached
        return LiquidIslandShape(morph: LiquidMorph(
            edge: layout.edge,
            attachment: attached ? 1 : 0,
            rail: stage.rail,
            deck: stage.deck,
            // A floating rail is a capsule: the outline clamps this radius to half the rail's short side.
            railCorner: attached ? fusedRailCorner(layout: layout) ?? metrics.railCorner : 999,
            deckCorner: metrics.deckCorner,
            shoulder: layout.isNotchFused ? Self.fusedShoulder(metrics: metrics) : metrics.shoulder,
            progress: expanded ? 1 : 0,
            swell: swells ? 1 : 0,
            wobble: metrics.liquidWobble,
            isLiquid: liquid
        ))
    }

    /// The free-side corner of a fused rail: close to the hardware notch's own bottom corners, so the island reads
    /// as part of it. `nil` when the island is not fused.
    static func fusedRailCorner(layout: IslandLayout) -> CGFloat? {
        guard layout.isNotchFused, let notch = layout.notch else { return nil }
        return min(layout.metrics.railCorner, notch.menuBarHeight * 0.3)
    }

    /// The notch's small top flare: much narrower shoulders than a normal attached island's.
    static func fusedShoulder(metrics: IslandMetrics) -> CGFloat {
        6 * metrics.scale
    }

    /// The deck appears from the anchor while the droplet pours: it fades in and grows from 96.5 %. Reduce Motion
    /// keeps only the crossfade.
    static func deckTransition(anchor: IslandAnchor, scales: Bool) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: DeckRevealModifier(revealed: false, anchor: anchor, scales: scales),
                identity: DeckRevealModifier(revealed: true, anchor: anchor, scales: scales)
            )
            .animation(Motion.deckReveal),
            removal: .opacity.animation(Motion.deckConceal)
        )
    }

    static var railTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(Motion.railReveal),
            removal: .opacity.animation(Motion.railConceal)
        )
    }

    /// The height cap the visible deck gets: none while its natural height fits the room (so no scroll view, and
    /// no scroller flashing as it opens), otherwise the room, inside which its body scrolls. Unknown or invalid
    /// room (previews) never caps it.
    nonisolated static func deckHeightCap(natural: CGFloat, maximum: CGFloat?) -> CGFloat {
        guard let maximum, maximum.isFinite, maximum > 0, natural > maximum else { return .infinity }
        return maximum
    }

    /// The sizes the island is placed with. A capped deck is exactly as tall as its cap (header, padding and
    /// shoulders included, the body scrolling in the rest), so the natural measurement is clamped here instead
    /// of measuring a second, capped copy.
    nonisolated static func islandSizes(measured: IslandSizes, maximumDeckHeight maximum: CGFloat?) -> IslandSizes {
        let cap = deckHeightCap(natural: measured.deck.height, maximum: maximum)
        guard cap.isFinite else { return measured }
        var sizes = measured
        sizes.deck.height = cap.rounded(.down)
        return sizes
    }

    /// Height of the band at the top of the deck where a click on empty space pins or closes the deck.
    static func headerBandHeight(layout: IslandLayout) -> CGFloat {
        layout.deckInsets.top + layout.metrics.deckVerticalPadding + 34 * layout.metrics.scale
    }

    /// The island inside its stage: content sits still at its final place while the liquid outline (clip, glass
    /// and rim) flows between the rail and the deck.
    private func island(
        accounts: IslandAccounts,
        layout: IslandLayout,
        appearance: AppearanceSettings,
        stage: IslandMorphLayout
    ) -> some View {
        let expanded = model.isExpanded
        let liquid = !Motion.reducesMotion
        let shape = Self.liquidShape(
            layout: layout,
            stage: stage,
            expanded: expanded,
            swells: model.isHovered && !model.isDragging,
            liquid: liquid
        )
        // Beside a black hardware notch, glass would look like a hole: a fused island is solid black whatever the
        // chosen surface, and both states use it so the morph never crossfades materials.
        let surface = layout.isNotchFused ? IslandSurface.solid : appearance.surface
        let glass = IslandGlass(
            glowsWithUrgency: appearance.glowsWithUrgency,
            urgency: store.urgency,
            waiting: store.hasWaiting,
            snapped: model.isSnapped,
            fused: layout.isNotchFused
        )
        // Whoever flips `isExpanded` with an animation (the window controller, the settings preview), the outline always
        // flows with the liquid timing; a change without animation stays instant.
        let morph = Motion.liquid(expanding: expanded)
        // A carried island folds with the carry's own critically damped timing, in step with its frames.
        let carried = model.isDragging
        return ZStack(alignment: .topLeading) {
            if expanded, appearance.openTrigger.pinsOnClick {
                headerCatcher(layout: layout, deck: stage.deck)
            }
            // A prewarmed deck is built (invisible, inert) while the hover intent runs, so the frame the unfold starts
            // in never has to create the whole deck and the first frames of the motion are not dropped.
            if expanded || model.prewarmsDeck {
                DeckContent(
                    store: store,
                    model: model,
                    accounts: accounts.deck,
                    context: .island,
                    maxHeight: Self.deckHeightCap(natural: measured.deck.height, maximum: model.maximumDeckHeight)
                )
                    .fixedSize()
                    .frame(width: stage.deck.width, height: stage.deck.height, alignment: layout.anchor.alignment)
                    // Counts as visible while prewarmed and folding too: flipping it invalidates the whole deck, which
                    // would cost frames at the start of the fold (history loads are cached and throttled).
                    .environment(\.isDeckVisible, true)
                    .animation(expanded ? Motion.deckReveal : Motion.deckConceal) { content in
                        // The same reveal as `deckTransition`, for a deck that was already there (prewarmed).
                        content.modifier(DeckRevealModifier(revealed: expanded, anchor: layout.anchor, scales: liquid))
                    }
                    .allowsHitTesting(expanded)
                    .accessibilityHidden(!expanded)
                    .transition(expanded ? Self.deckTransition(anchor: layout.anchor, scales: liquid) : .identity)
                    .padding(.leading, stage.deck.minX)
                    .padding(.top, stage.deck.minY)
            }
            if !expanded || model.prewarmsRail {
                rail(accounts: accounts.rail, layout: layout)
                    .fixedSize()
                    .frame(width: stage.rail.width, height: stage.rail.height, alignment: layout.anchor.alignment)
                    // A prewarmed rail waits invisible under the deck and fades in with the same timing as an inserted one.
                    .animation(expanded ? Motion.railConceal : Motion.railReveal) { content in
                        content.opacity(expanded ? 0 : 1)
                    }
                    .allowsHitTesting(!expanded)
                    .accessibilityHidden(expanded)
                    .transition(Self.railTransition)
                    .padding(.leading, stage.rail.minX)
                    .padding(.top, stage.rail.minY)
            }
            // Draw-only: flying copies of the rings on their way between the rail and the deck.
            if let flight = model.flight, !flight.isEmpty {
                RingFlightLayer(
                    pairs: flight,
                    progress: model.flightProgress,
                    edge: layout.edge,
                    accounts: Dictionary(accounts.deck.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
                    deckDiameter: layout.metrics.deckDial,
                    showsInnerRings: appearance.showsSecondaryRing
                )
                .frame(width: max(stage.size.width, 1), height: max(stage.size.height, 1), alignment: .topLeading)
            }
        }
        // The live rail and deck report their ring boxes here; hidden measurement copies never see a sink.
        .environment(\.ringAnchorSink, model.anchors)
        .environment(\.ringFlightHiddenAccounts, model.flightHiddenAccounts)
        .frame(width: max(stage.size.width, 1), height: max(stage.size.height, 1), alignment: .topLeading)
        .coordinateSpace(.named(RingAnchorSink.coordinateSpace))
        .clipShape(shape)
        .modifier(IslandSurfaceModifier(surface: surface, shape: shape, glass: glass, stageSize: stage.size))
        .contentShape(shape)
        .transaction(value: expanded) { transaction in
            // The window controller already animates with `morph`: leave its transaction (and the fold's completion
            // attached to it) untouched.
            guard let animation = transaction.animation, animation != morph, !transaction.disablesAnimations, !carried else { return }
            transaction.animation = morph
        }
    }

    /// The rail at rest: one strip, or two wings around the camera notch when the island is fused with it.
    @ViewBuilder
    private func rail(accounts: [AccountPresentation], layout: IslandLayout) -> some View {
        if layout.isNotchFused, let notch = layout.notch {
            NotchRailView(store: store, model: model, accounts: accounts, notch: notch)
        } else {
            RailView(store: store, model: model, accounts: accounts)
        }
    }

    /// Empty space in the header band toggles a click-pinned deck: it pins a deck opened by hover and closes a
    /// pinned one. It sits behind the deck, so buttons, dials and text keep their own clicks.
    private func headerCatcher(layout: IslandLayout, deck: CGRect) -> some View {
        Color.clear
            .frame(width: deck.width, height: min(deck.height, Self.headerBandHeight(layout: layout)))
            .contentShape(Rectangle())
            .onTapGesture {
                model.request(.headerClick)
            }
            .padding(.leading, deck.minX)
            .padding(.top, deck.minY)
            .accessibilityHidden(true)
    }

    private func measurements(accounts: IslandAccounts) -> some View {
        ZStack {
            rail(accounts: accounts.rail, layout: model.layout)
                .fixedSize()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                    report { $0.rail = size }
                }
            DeckContent(store: store, model: model, accounts: accounts.deck, context: .island)
                .fixedSize()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                    report { $0.deck = size }
                }
        }
        .environment(\.liveEffectsEnabled, false)
        .environment(\.introAnimationsEnabled, false)
        .environment(\.isDeckVisible, false)
        .hidden()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func report(_ change: (inout IslandSizes) -> Void) {
        var updated = measured
        change(&updated)
        updated.rail = CGSize(width: updated.rail.width.rounded(.up), height: updated.rail.height.rounded(.up))
        updated.deck = CGSize(width: updated.deck.width.rounded(.up), height: updated.deck.height.rounded(.up))
        guard updated != measured else { return }
        measured = updated
        publishSizes()
    }

    private func publishSizes() {
        let updated = Self.islandSizes(measured: measured, maximumDeckHeight: model.maximumDeckHeight)
        guard updated != sizes else { return }
        sizes = updated
        onSizesChange(updated)
    }
}

/// The deck's content revealed from the island's anchor: faded and scaled down while hidden.
///
/// Opacity and scale only. A blur would be cheap to animate, but SwiftUI hosts the deck's Core Animation views
/// (activity orbits, pulse rings) in a filter layer only while the radius is above zero, so they would be re-parented
/// at the start of every fold and at the end of every reveal, right after the interaction finished.
struct DeckRevealModifier: ViewModifier {
    let revealed: Bool
    let anchor: IslandAnchor
    /// `false` under Reduce Motion, which keeps a plain crossfade.
    let scales: Bool

    func body(content: Content) -> some View {
        content
            .opacity(revealed ? 1 : 0)
            .scaleEffect(revealed || !scales ? 1 : Self.hiddenScale, anchor: anchor.unitPoint)
    }

    nonisolated static let hiddenScale: CGFloat = 0.965
}

/// The accounts each state of the island shows.
private struct IslandAccounts {
    /// Visible accounts (the rail group filter applied).
    let rail: [AccountPresentation]
    /// Every enabled account; the deck filters its dial row by group itself.
    let deck: [AccountPresentation]
}

extension IslandLayout {
    /// Padding that keeps the rail clear of the attached silhouette's shoulders and of anything covering the
    /// attached edge (such as a camera housing).
    ///
    /// A rail fused with the notch drops all of it: its wings sit **beside** the notch, inside the menu bar, and
    /// `NotchRailView` adds the outer shoulders itself.
    var shoulderInsets: EdgeInsets {
        guard style == .attached, !isNotchFused else { return EdgeInsets() }
        return attachedInsets
    }

    /// The same padding for the deck, which always stays clear of the camera housing: even a fused island's deck
    /// hangs below the notch, not behind it.
    var deckInsets: EdgeInsets {
        guard style == .attached else { return EdgeInsets() }
        return attachedInsets
    }

    /// Half the silhouette's bleed: the attached side is drawn past the screen edge and is never seen, so content
    /// centred in the frame would sit that much above the middle of the part the user actually sees.
    static var attachedEdgeCompensation: CGFloat { IslandSilhouette.bleed / 2 }

    private var attachedInsets: EdgeInsets {
        let inset = metrics.shoulder
        let edgeSide = edgeInset + Self.attachedEdgeCompensation
        return switch edge {
        case .top: EdgeInsets(top: edgeSide, leading: inset, bottom: 0, trailing: inset)
        case .bottom: EdgeInsets(top: 0, leading: inset, bottom: edgeSide, trailing: inset)
        case .left: EdgeInsets(top: inset, leading: edgeSide, bottom: inset, trailing: 0)
        case .right: EdgeInsets(top: inset, leading: 0, bottom: inset, trailing: edgeSide)
        }
    }
}
