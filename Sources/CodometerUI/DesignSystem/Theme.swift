import CodometerCore
import AppKit
import SwiftUI

/// Colours. Surfaces are Liquid Glass, so text uses semantic `.primary`/`.secondary` and adapts
/// to whatever is behind the glass; only data colours are fixed.
///
/// One colour, one meaning: band colours only describe usage, `attention` only a waiting agent,
/// provider accents only identity (never inside rings or bars).
public enum Theme {
    /// Two-stop gradient per usage band, light to deep along the arc.
    public static func colors(for band: UsageBand) -> [Color] {
        let stops = Palette.bandGradient(band)
        return [color(stops.start), color(stops.end)]
    }

    /// The band's deep colour, for fills and glows.
    public static func tint(for band: UsageBand) -> Color {
        color(Palette.bandGradient(band).end)
    }

    /// Identity only: plan chips and the account's badge, never data.
    public static func accent(for provider: ProviderKind) -> Color {
        color(Palette.accent(provider))
    }

    /// An account's own colour, for its badge wash and its identity dot.
    ///
    /// Identity only, like `accent(for:)`: it says *which account*, never how much is left. Arcs, bars, rims and the
    /// glass keep their band colours (`PaletteConstraintTests` holds `colors(for:)` to that).
    public static func accountTint(for tint: AccountTint) -> Color {
        color(Palette.accountTint(tint))
    }

    /// An account's colour for its monogram and small labels, readable on light and dark glass.
    public static func accountTintText(for tint: AccountTint) -> Color {
        accountTintTexts[tint] ?? accountTintTexts[.graphite] ?? .secondary
    }

    private static let accountTintTexts: [AccountTint: Color] = Dictionary(
        uniqueKeysWithValues: AccountTint.allCases.map { ($0, dynamic(Palette.accountTintText($0))) }
    )

    /// Band colour for text: deeper in light appearance and lighter in dark appearance, so small
    /// percentages stay readable on glass in both.
    public static func bandText(for band: UsageBand) -> Color {
        switch band {
        case .ample: ampleText
        case .watch: watchText
        case .critical: criticalText
        case .exhausted: exhaustedText
        }
    }

    private static let ampleText = dynamic(Palette.bandText(.ample))
    private static let watchText = dynamic(Palette.bandText(.watch))
    private static let criticalText = dynamic(Palette.bandText(.critical))
    private static let exhaustedText = dynamic(Palette.bandText(.exhausted))

    /// A faint wash of the band colour for the island's glass as usage rises; `nil` while usage is ample.
    public static func glassTint(for band: UsageBand?) -> Color? {
        switch band {
        case nil, .ample: nil
        case .watch: tint(for: .watch).opacity(0.06)
        case .critical: tint(for: .critical).opacity(0.09)
        case .exhausted: tint(for: .exhausted).opacity(0.12)
        }
    }

    /// The thin rim light along the island's outline: the attention colour while an agent waits,
    /// otherwise the band colour once usage leaves the ample band; `nil` when nothing needs a rim.
    public static func rim(for band: UsageBand?, waiting: Bool) -> Color? {
        if waiting { return attention.opacity(0.75) }
        return switch band {
        case nil, .ample: nil
        case .watch: tint(for: .watch).opacity(0.35)
        case .critical: tint(for: .critical).opacity(0.5)
        case .exhausted: tint(for: .exhausted).opacity(0.65)
        }
    }

    /// "Waiting on you" is violet-magenta: never confused with a usage band or a provider accent.
    public static let attention = color(Palette.attention)
    /// The attention colour for text, contrast-safe in light and dark appearance.
    public static let attentionText = dynamic(Palette.attentionText)
    public static let success = Color(red: 0.19, green: 0.78, blue: 0.47)
    public static let warning = Color(red: 1.00, green: 0.60, blue: 0.10)
    public static let track = Color.primary.opacity(0.10)
    public static let subtleFill = Color.primary.opacity(0.06)
    /// Inner cards on glass: a whisper of fill, never another layer of glass.
    public static let cardFill = Color.primary.opacity(0.05)
    /// A selected or hovered item inside a card.
    public static let selectionFill = Color.primary.opacity(0.09)
    /// Arcs and bars of data too old to trust: a calm grey that still shows the value.
    public static let staleData = Color.primary.opacity(0.32)
    /// Hairline dividers and card outlines.
    public static let hairline = Color.primary.opacity(0.09)

    static func color(_ rgb: Palette.RGB) -> Color {
        Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    private static func dynamic(_ adaptive: Palette.Adaptive) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let rgb = isDark ? adaptive.dark : adaptive.light
            return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        })
    }
}

public enum Motion {
    @MainActor
    public static var reducesMotion: Bool {
        #if DEBUG
        if let reducesMotionOverride { return reducesMotionOverride }
        #endif
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    #if DEBUG
    /// Replaces the system's Reduce Motion setting for the island's motion while set; only the debug scenario harness
    /// sets it, so the plain (non-liquid) path can be verified without touching system settings.
    @MainActor public static var reducesMotionOverride: Bool?
    #endif

    /// The island unfolding and folding. Critically damped like `geometry`: the island reaches its
    /// final layout in one motion, with no overshoot to settle afterwards.
    @MainActor
    public static var island: Animation? {
        reducesMotion ? nil : .spring(response: 0.42, dampingFraction: 1.0)
    }

    @MainActor
    public static var snappy: Animation? {
        reducesMotion ? nil : .spring(response: 0.3, dampingFraction: 0.86)
    }

    /// Arcs and bars moving to a new value. Used only when a value changes, never on appear.
    @MainActor
    public static var gauge: Animation? {
        reducesMotion ? nil : .smooth(duration: 0.9)
    }

    @MainActor
    public static var content: Animation? {
        reducesMotion ? nil : .smooth(duration: 0.28)
    }

    @MainActor
    public static var quickFade: Animation? {
        reducesMotion ? nil : .easeOut(duration: 0.12)
    }

    /// Every size and frame change of the island: critically damped, so geometry never overshoots
    /// and the island reaches its final layout in one motion.
    @MainActor
    public static var geometry: Animation? {
        reducesMotion ? nil : .spring(response: 0.42, dampingFraction: 1.0)
    }

    /// Content appearing once geometry is under way. Callers add a small delay.
    @MainActor
    public static var reveal: Animation? {
        reducesMotion ? nil : .smooth(duration: 0.24)
    }

    // MARK: Liquid island

    /// The island opening as a droplet. Nearly critically damped: the outline reaches the deck in one motion (visually
    /// within about 0.35 s, settled by about 0.39 s, a little quicker than the plain `geometry` unfold it replaces) and
    /// overshoots by less than 0.05 %, far too little for the outline's bounded wobble to show. With Reduce Motion, a
    /// short plain resize and crossfade instead.
    @MainActor
    public static var liquidOpen: Animation {
        reducesMotion ? .easeInOut(duration: 0.2) : .spring(response: Self.liquidOpenResponse, dampingFraction: Self.liquidOpenDamping)
    }

    /// The deck folding back into the rail: critically damped; the droplet is absorbed within about 0.34 s.
    @MainActor
    public static var liquidFold: Animation {
        reducesMotion ? .easeInOut(duration: 0.18) : .spring(response: Self.liquidFoldResponse, dampingFraction: Self.liquidFoldDamping)
    }

    /// Spring parameters of the liquid morph, shared with the timing tests and renders. The outline eases progress
    /// (`LiquidMorph.Tuning.progressEase`), so the fold's spring is slower than the open's for about the same pace.
    public static let liquidOpenResponse: Double = 0.4
    public static let liquidOpenDamping: Double = 0.93
    public static let liquidFoldResponse: Double = 0.55
    public static let liquidFoldDamping: Double = 1.0
    /// The deck's content waits this long into an opening, while the droplet forms, and is in place by about 0.37 s.
    public static let deckRevealDelay: Double = 0.11
    public static let deckRevealDuration: Double = 0.22
    /// The rail's content waits this long into a fold, until the droplet is mostly absorbed.
    public static let railRevealDelay: Double = 0.16
    public static let railRevealDuration: Double = 0.2

    /// The morph for a change of `isExpanded`.
    @MainActor
    public static func liquid(expanding: Bool) -> Animation {
        expanding ? liquidOpen : liquidFold
    }

    /// The rail's hover swell. Critically damped like every geometry change: when it retargets an animation already
    /// moving the island's frames (a glide after a drop, a size change), those frames still never overshoot.
    @MainActor
    public static var liquidSwell: Animation? {
        reducesMotion ? nil : .spring(response: 0.3, dampingFraction: 1.0)
    }

    /// The deck's content fades in while the droplet forms and is half there once the droplet has passed about 60 %.
    @MainActor
    public static var deckReveal: Animation {
        reducesMotion ? .easeOut(duration: 0.16) : .smooth(duration: deckRevealDuration).delay(deckRevealDelay)
    }

    /// The deck's content leaves at once, before the droplet contracts.
    @MainActor
    public static var deckConceal: Animation {
        .easeOut(duration: reducesMotion ? 0.12 : 0.09)
    }

    /// The rail's content fades out as the droplet leaves it…
    @MainActor
    public static var railConceal: Animation {
        .easeOut(duration: reducesMotion ? 0.12 : 0.08)
    }

    /// …and back in once the droplet has been absorbed.
    @MainActor
    public static var railReveal: Animation {
        reducesMotion ? .easeOut(duration: 0.14) : .smooth(duration: railRevealDuration).delay(railRevealDelay)
    }

    /// The one-shot sheen across the rail when its numbers change.
    public static let sheenDuration: CFTimeInterval = 1.1
}

/// Design sizes for text, before `IslandMetrics` scales them. Small text is deliberately generous:
/// at the smallest island scale captions still render at 11 pt or more.
public enum TextSize {
    /// Plan chips and tiny badges.
    public static let badge: CGFloat = 11
    /// Secondary lines, reset texts, timestamps.
    public static let caption: CGFloat = 11.5
    /// Section titles, footers, chips.
    public static let footnote: CGFloat = 12
    /// Status lines under a title.
    public static let callout: CGFloat = 12.5
    /// Row titles and body text.
    public static let body: CGFloat = 13
    /// Account names and card titles.
    public static let headline: CGFloat = 14.5
    /// Dial percentages.
    public static let dialValue: CGFloat = 15
    /// The deck's title.
    public static let title: CGFloat = 17
    /// Tile numerals.
    public static let tileValue: CGFloat = 21
    /// The hero numeral.
    public static let hero: CGFloat = 34
}

/// Every size in the island, derived from one scale factor.
public struct IslandMetrics: Equatable, Sendable {
    public let scale: CGFloat

    public init(scale: CGFloat) {
        self.scale = scale
    }

    public var railDial: CGFloat { 28 * scale }
    public var railSpacing: CGFloat { 9 * scale }
    /// Ring diameter of a deck dial, without its orbit margin.
    public var deckDial: CGFloat { 58 * scale }
    public var deckWidth: CGFloat { 412 * scale }
    public var deckCorner: CGFloat { 30 * scale }
    public var deckPadding: CGFloat { 16 * scale }
    /// The deck's top and bottom padding: a little more than the sides, so the header and the last tile stay clear
    /// of the rounded ends when the deck opens.
    public var deckVerticalPadding: CGFloat { 20 * scale }
    /// Vertical space between the deck's sections.
    public var sectionSpacing: CGFloat { 12 * scale }
    /// Small cards: attention cards, session groups, banners.
    public var cardCorner: CGFloat { 14 * scale }
    /// Window tiles and the hero card.
    public var tileCorner: CGFloat { 16 * scale }
    /// Inner padding of cards and tiles.
    public var cardPadding: CGFloat { 12 * scale }
    /// Space between tiles in the grid.
    public var tileSpacing: CGFloat { 8 * scale }
    /// Radius of the free-side corners of a collapsed attached island.
    public var railCorner: CGFloat { 16 * scale }
    /// Width of the concave shoulders where an attached island meets the screen edge.
    public var shoulder: CGFloat { 12 * scale }
    /// Padding reserved around a ring for its activity orbit, so an orbit appearing never resizes anything.
    public var orbitMargin: CGFloat { 4 * scale }
    /// Transparent space around the island inside its panel, so rim light and shadow are never clipped.
    public var windowMargin: CGFloat { 20 * scale }
    /// The furthest the free side of the liquid island wobbles outwards when it settles: well inside `windowMargin`.
    public var liquidWobble: CGFloat { 5 * scale }
    /// Side of the deck header's round buttons.
    public var headerButton: CGFloat { 28 * scale }

    /// Text never renders below this, whatever the scale.
    public static let minimumTextSize: CGFloat = 10.5

    public func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: textSize(size), weight: weight, design: .rounded)
    }

    public func digits(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: textSize(size), weight: weight, design: .rounded).monospacedDigit()
    }

    /// The point size `font` and `digits` render a design size at.
    public func textSize(_ size: CGFloat) -> CGFloat {
        Self.textSize(size, scale: scale)
    }

    /// Scales a design size with floors, so small text stays legible at small scales:
    /// at least `size + 0.5` for sizes under 12 pt, at least 95 % of larger sizes, and never under 10.5 pt.
    public static func textSize(_ size: CGFloat, scale: CGFloat) -> CGFloat {
        let floor = size < 12 ? size + 0.5 : size * 0.95
        return max(size * scale, floor, minimumTextSize)
    }
}

extension EnvironmentValues {
    /// Whether gauges and bars animate to new values. Off for static renders and hidden measurement
    /// copies. Values never sweep in on appear, so an opening deck is complete in its first frame.
    @Entry public var introAnimationsEnabled = true

    /// Whether this deck is on screen for the user, as opposed to a hidden measurement copy or a preview.
    /// Only a visible deck requests history. The island root sets it on its visible deck; the menu bar
    /// popover sets it too.
    @Entry public var isDeckVisible = false
}
