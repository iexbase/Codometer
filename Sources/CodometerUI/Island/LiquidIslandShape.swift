import CodometerCore
import SwiftUI

/// A shape the island's surface, clip and rim can share: the outline itself, the part of it that catches rim
/// light, and where the island sits inside the view it is drawn in.
protocol IslandOutlinedShape: Shape {
    associatedtype RimOutline: Shape
    /// The outline without the side along the screen edge (attached) or the whole outline (floating).
    var rimOutline: RimOutline { get }
    var edge: ScreenEdge { get }
    var isFloating: Bool { get }
    /// The island's rect inside the view the shape is drawn in; `nil` fills the view.
    var envelope: CGRect? { get }
}

extension IslandSilhouette: IslandOutlinedShape {
    var rimOutline: IslandSilhouetteOutline { outline }
    var isFloating: Bool { style == .floating }
    var envelope: CGRect? { islandFrame }
}

/// The island's animatable outline: `LiquidMorph` driven by SwiftUI animations.
///
/// Progress, swell, attachment, radii and both frames animate together in one transaction, so a fold interrupted
/// by an unfold, a size change or a style change simply retargets the same outline.
public struct LiquidIslandShape: Shape, IslandOutlinedShape {
    public var morph: LiquidMorph

    public init(morph: LiquidMorph) {
        self.morph = morph
    }

    public var animatableData: LiquidMorphVector {
        get { LiquidMorphVector(morph) }
        set { newValue.apply(to: &morph) }
    }

    public func path(in rect: CGRect) -> Path {
        morph.path(in: rect)
    }

    var rimOutline: LiquidIslandOutline {
        LiquidIslandOutline(morph: morph)
    }

    var edge: ScreenEdge { morph.edge }
    var isFloating: Bool { morph.attachment < 0.5 }
    var envelope: CGRect? { morph.envelope() }
}

/// `LiquidIslandShape` without its screen side, for rim light.
public struct LiquidIslandOutline: Shape {
    public var morph: LiquidMorph

    public var animatableData: LiquidMorphVector {
        get { LiquidMorphVector(morph) }
        set { newValue.apply(to: &morph) }
    }

    public func path(in rect: CGRect) -> Path {
        morph.outlinePath(in: rect)
    }
}

/// The animatable numbers of a `LiquidMorph` as one vector.
public struct LiquidMorphVector: VectorArithmetic, Sendable {
    var storage: SIMD16<Double>

    init(storage: SIMD16<Double>) {
        self.storage = storage
    }

    init(_ morph: LiquidMorph) {
        storage = SIMD16(
            Double(morph.progress), Double(morph.swell), Double(morph.attachment), Double(morph.shoulder),
            Double(morph.railCorner), Double(morph.deckCorner), Double(morph.rail.minX), Double(morph.rail.minY),
            Double(morph.rail.width), Double(morph.rail.height), Double(morph.deck.minX), Double(morph.deck.minY),
            Double(morph.deck.width), Double(morph.deck.height), 0, 0
        )
    }

    func apply(to morph: inout LiquidMorph) {
        morph.progress = CGFloat(storage[0])
        morph.swell = CGFloat(storage[1])
        morph.attachment = CGFloat(storage[2])
        morph.shoulder = CGFloat(storage[3])
        morph.railCorner = CGFloat(storage[4])
        morph.deckCorner = CGFloat(storage[5])
        morph.rail = CGRect(x: storage[6], y: storage[7], width: storage[8], height: storage[9])
        morph.deck = CGRect(x: storage[10], y: storage[11], width: storage[12], height: storage[13])
    }

    public static var zero: LiquidMorphVector {
        LiquidMorphVector(storage: .zero)
    }

    public static func + (lhs: LiquidMorphVector, rhs: LiquidMorphVector) -> LiquidMorphVector {
        LiquidMorphVector(storage: lhs.storage + rhs.storage)
    }

    public static func - (lhs: LiquidMorphVector, rhs: LiquidMorphVector) -> LiquidMorphVector {
        LiquidMorphVector(storage: lhs.storage - rhs.storage)
    }

    public mutating func scale(by rhs: Double) {
        storage *= rhs
    }

    public var magnitudeSquared: Double {
        (storage * storage).sum()
    }
}
