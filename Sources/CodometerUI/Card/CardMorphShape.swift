import CodometerCore
import CoreGraphics
import SwiftUI

/// The one contour that carries the floating card between its two forms: a rounded rectangle when expanded, a capsule
/// when minimized, with a droplet forming on the free sides while it travels.
///
/// The maths is the island's `LiquidMorph`, read only: the card is drawn in a canonical frame whose "screen edge" is
/// the side the anchor pins, so the form grows and shrinks toward the anchor and the belly of the droplet forms on the
/// free sides. Nothing here animates by itself — `progress` is the animated number, and the outline can bow outwards
/// by at most `wobble`, which stays inside the panel's transparent margin, so no frame ever overshoots.
public struct CardMorphShape: Shape, Animatable {
    /// 0 is the pill, 1 is the card.
    public var progress: CGFloat
    /// The point the two forms share.
    public let anchor: CardAnchor
    /// The pill's rect inside the shape's bounds.
    public let pill: CGRect
    /// The card's rect inside the shape's bounds.
    public let card: CGRect
    public let pillCorner: CGFloat
    public let cardCorner: CGFloat
    public let wobble: CGFloat
    /// `false` morphs as a plain rounded rectangle (Reduce Motion): no droplet, no wobble.
    public let isLiquid: Bool

    public init(
        progress: CGFloat,
        anchor: CardAnchor,
        pill: CGRect,
        card: CGRect,
        pillCorner: CGFloat,
        cardCorner: CGFloat,
        wobble: CGFloat,
        isLiquid: Bool
    ) {
        self.progress = progress
        self.anchor = anchor
        self.pill = pill
        self.card = card
        self.pillCorner = pillCorner
        self.cardCorner = cardCorner
        self.wobble = wobble
        self.isLiquid = isLiquid
    }

    public var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    /// The canonical "screen edge" for an anchor: the side of the card the anchor pins, which is the side that stays
    /// put while the other sides travel.
    public static func edge(for anchor: CardAnchor) -> ScreenEdge {
        switch FloatingCardGeometry.axes(of: anchor).y {
        case .end: .top
        case .start: .bottom
        // A card pinned by its middle grows evenly: the contour is built from the top, which looks the same either way.
        case .middle: .top
        }
    }

    public func path(in rect: CGRect) -> Path {
        guard pill.width > 0, pill.height > 0, card.width > 0, card.height > 0 else { return Path() }
        return morph.path(in: CGRect(origin: rect.origin, size: rect.size))
    }

    /// The outline for rim light: the whole contour, because the card never touches a screen edge.
    public func outlinePath(in rect: CGRect) -> Path {
        morph.outlinePath(in: CGRect(origin: rect.origin, size: rect.size))
    }

    var morph: LiquidMorph {
        LiquidMorph(
            edge: Self.edge(for: anchor),
            // Always floating: the card is an object on the desktop, never fused to a screen edge.
            attachment: 0,
            rail: pill,
            deck: card,
            railCorner: pillCorner,
            deckCorner: cardCorner,
            shoulder: 0,
            progress: progress,
            swell: 0,
            wobble: isLiquid ? wobble : 0,
            isLiquid: isLiquid
        )
    }
}
