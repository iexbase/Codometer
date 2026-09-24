import CodometerCore
import SwiftUI

/// The colours of one floating-card theme, resolved for the current appearance and accessibility settings.
///
/// Named `CardThemeTokens` because `CardTheme` is the Core enum the user picks; this is what that choice means on
/// screen. Every colour is kept as plain sRGB numbers as well, so the contrast rules are checked by tests without a
/// renderer (`CardThemeContrastTests`).
public struct CardThemeTokens: Equatable, Sendable {
    /// The theme actually drawn: Liquid Glass falls back to Graphite with Reduce Transparency or Increase Contrast.
    public let theme: CardTheme
    /// Draws real glass behind the scrim.
    public let isGlass: Bool
    /// Light text on a dark surface.
    public let isDark: Bool

    /// The opaque surface, or — for glass — the scrim over the darkest wallpaper.
    public let surface: Palette.RGB
    /// For glass: the scrim over the lightest wallpaper. The same as `surface` for opaque themes.
    public let surfaceOverLight: Palette.RGB
    public let tileFill: Palette.RGB
    public let hairline: Palette.RGB
    public let primaryText: Palette.RGB
    public let secondaryText: Palette.RGB
    /// The unused part of a ring or bar.
    public let track: Palette.RGB
    public let focusRing: Palette.RGB
    public let pillFill: Palette.RGB
    public let pillStroke: Palette.RGB
    /// Hairlines are twice as thick with Increase Contrast.
    public let hairlineWidth: CGFloat
    public let shadowOpacity: Double
    public let shadowRadius: CGFloat

    /// How opaque the legibility scrim over Liquid Glass is.
    ///
    /// The card floats over whatever is on the desktop, so its glass needs a scrim strong enough that every text and
    /// band colour keeps its contrast over both a white and a black wallpaper. One dark scrim in both
    /// appearances is what makes that possible; a light scrim could not keep band text legible over a dark desktop.
    public static let glassScrim = 0.78

    /// The two backgrounds a contrast rule has to hold against: one for an opaque theme, two for glass.
    public var contrastBackgrounds: [Palette.RGB] {
        surface == surfaceOverLight ? [surface] : [surface, surfaceOverLight]
    }

    /// The band colour for text in this theme, from the palette's light or dark variant.
    public func bandText(_ band: UsageBand) -> Palette.RGB {
        let adaptive = Palette.bandText(band)
        return isDark ? adaptive.dark : adaptive.light
    }

    /// The card's colours for `theme`.
    ///
    /// - Parameters:
    ///   - scheme: The system appearance; only Liquid Glass and the fallbacks follow it.
    ///   - reducesTransparency: Replaces glass with an opaque theme.
    ///   - increasesContrast: Doubles hairlines, drops glass and draws secondary text at full strength.
    public static func resolve(
        theme: CardTheme,
        scheme: ColorScheme,
        reducesTransparency: Bool,
        increasesContrast: Bool
    ) -> CardThemeTokens {
        var drawn = theme
        var glass = theme == .liquidGlass
        if glass, reducesTransparency || increasesContrast {
            drawn = scheme == .light ? .light : .graphite
            glass = false
        }
        var tokens = base(drawn, glass: glass)
        if increasesContrast {
            tokens = tokens.withIncreasedContrast()
        }
        return tokens
    }

    private static func base(_ theme: CardTheme, glass: Bool) -> CardThemeTokens {
        switch theme {
        case .graphite:
            CardThemeTokens(
                theme: .graphite,
                isGlass: false,
                isDark: true,
                surface: RGB(0.09, 0.09, 0.10),
                surfaceOverLight: RGB(0.09, 0.09, 0.10),
                tileFill: RGB(0.16, 0.16, 0.18),
                hairline: RGB(0.32, 0.32, 0.35),
                primaryText: RGB(1, 1, 1),
                secondaryText: RGB(0.72, 0.72, 0.75),
                track: RGB(0.44, 0.44, 0.47),
                focusRing: RGB(0.40, 0.68, 1.00),
                pillFill: RGB(0.09, 0.09, 0.10),
                pillStroke: RGB(0.32, 0.32, 0.35),
                hairlineWidth: 1,
                shadowOpacity: 0.38,
                shadowRadius: 18
            )
        case .midnight:
            CardThemeTokens(
                theme: .midnight,
                isGlass: false,
                isDark: true,
                surface: RGB(0.055, 0.065, 0.125),
                surfaceOverLight: RGB(0.055, 0.065, 0.125),
                tileFill: RGB(0.11, 0.13, 0.21),
                hairline: RGB(0.28, 0.31, 0.44),
                primaryText: RGB(1, 1, 1),
                secondaryText: RGB(0.74, 0.76, 0.86),
                track: RGB(0.44, 0.46, 0.57),
                focusRing: RGB(0.46, 0.70, 1.00),
                pillFill: RGB(0.055, 0.065, 0.125),
                pillStroke: RGB(0.28, 0.31, 0.44),
                hairlineWidth: 1,
                shadowOpacity: 0.42,
                shadowRadius: 18
            )
        case .light:
            CardThemeTokens(
                theme: .light,
                isGlass: false,
                isDark: false,
                surface: RGB(0.975, 0.968, 0.955),
                surfaceOverLight: RGB(0.975, 0.968, 0.955),
                tileFill: RGB(0.925, 0.917, 0.902),
                hairline: RGB(0.70, 0.69, 0.68),
                primaryText: RGB(0.10, 0.10, 0.11),
                secondaryText: RGB(0.35, 0.35, 0.36),
                track: RGB(0.52, 0.515, 0.505),
                focusRing: RGB(0.10, 0.42, 0.90),
                pillFill: RGB(0.975, 0.968, 0.955),
                pillStroke: RGB(0.70, 0.69, 0.68),
                hairlineWidth: 1,
                shadowOpacity: 0.22,
                shadowRadius: 16
            )
        case .liquidGlass:
            CardThemeTokens(
                theme: .liquidGlass,
                isGlass: glass,
                isDark: true,
                // The scrim over black and over white: the two worst wallpapers the card can sit on.
                surface: scrim(over: RGB(0, 0, 0)),
                surfaceOverLight: scrim(over: RGB(1, 1, 1)),
                // Lighter than the scrim over either wallpaper, and still dark enough for white text: a light tile
                // here would make its value and label unreadable, because the scrim makes glass a dark theme.
                tileFill: RGB(0.22, 0.23, 0.27),
                hairline: RGB(0.62, 0.63, 0.68),
                primaryText: RGB(1, 1, 1),
                secondaryText: RGB(0.82, 0.83, 0.86),
                track: RGB(0.66, 0.67, 0.71),
                focusRing: RGB(0.46, 0.72, 1.00),
                pillFill: RGB(0, 0, 0),
                pillStroke: RGB(0.62, 0.63, 0.68),
                hairlineWidth: 1,
                shadowOpacity: 0.34,
                shadowRadius: 20
            )
        }
    }

    /// The Liquid Glass scrim (black at `glassScrim`) composited over one background.
    static func scrim(over background: Palette.RGB) -> Palette.RGB {
        let keep = 1 - glassScrim
        return RGB(background.red * keep, background.green * keep, background.blue * keep)
    }

    private func withIncreasedContrast() -> CardThemeTokens {
        CardThemeTokens(
            theme: theme,
            isGlass: false,
            isDark: isDark,
            surface: surface,
            surfaceOverLight: surfaceOverLight,
            tileFill: tileFill,
            hairline: hairline,
            primaryText: primaryText,
            // Secondary text reads at full strength, so nothing depends on a faint tone.
            secondaryText: primaryText,
            track: track,
            focusRing: focusRing,
            pillFill: pillFill,
            pillStroke: pillStroke,
            hairlineWidth: hairlineWidth * 2,
            shadowOpacity: shadowOpacity,
            shadowRadius: shadowRadius
        )
    }

    private static func RGB(_ r: Double, _ g: Double, _ b: Double) -> Palette.RGB {
        Palette.RGB(r, g, b)
    }
}

extension CardThemeTokens {
    public var surfaceColor: Color { Self.color(surface) }
    public var tileFillColor: Color { Self.color(tileFill) }
    public var hairlineColor: Color { Self.color(hairline) }
    public var primaryTextColor: Color { Self.color(primaryText) }
    public var secondaryTextColor: Color { Self.color(secondaryText) }

    public func bandTextColor(_ band: UsageBand) -> Color { Self.color(bandText(band)) }

    /// The tone's colour on this theme's surface.
    public func color(for tone: CardContentPlan.Tone) -> Color {
        switch tone {
        case .primary: primaryTextColor
        case .secondary: secondaryTextColor
        case .band(let band): bandTextColor(band)
        case .success: Self.color(isDark ? Palette.bandText(.ample).dark : Palette.bandText(.ample).light)
        case .attention: Self.color(isDark ? Palette.attentionText.dark : Palette.attentionText.light)
        }
    }

    static func color(_ rgb: Palette.RGB) -> Color {
        Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
