import CodometerCore
import SwiftUI
import WidgetKit

/// How the system renders the widget right now.
///
/// `.fullColor` is the normal desktop look. In `.accented` the system keeps only each layer's alpha and paints
/// accentable content in the accent colour and the rest in white; in `.vibrant` (monochrome desktop widgets) it
/// maps luminance onto a vibrant material. Colour must therefore never be the only carrier of meaning.
public enum WidgetStyle: Hashable, Sendable {
    case fullColor
    case accented
    case vibrant

    public init(_ mode: WidgetRenderingMode) {
        switch mode {
        case .accented: self = .accented
        case .vibrant: self = .vibrant
        default: self = .fullColor
        }
    }
}

/// Every colour the widget draws, resolved for one rendering style and colour scheme.
///
/// The widget mirrors the island's language: band colours mean usage and nothing else, "waiting for you" is violet-magenta,
/// provider marks are monochrome, and stale numbers turn a calm grey instead of fading out.
public struct WidgetPalette: Hashable, Sendable {
    public let style: WidgetStyle
    public let scheme: ColorScheme
    /// Renders do not run inside WidgetKit, so snapshot tests pass the colour the system would paint accentable
    /// content with; `nil` in the real widget, where the system applies the tint itself.
    public let accentPreview: Color?

    public init(style: WidgetStyle, scheme: ColorScheme, accentPreview: Color? = nil) {
        self.style = style
        self.scheme = scheme
        self.accentPreview = accentPreview
    }

    private var isDark: Bool { scheme == .dark }

    /// Main text.
    public var primary: Color {
        switch style {
        case .fullColor: isDark ? Color.white.opacity(0.96) : Color(red: 0.07, green: 0.08, blue: 0.11)
        case .accented, .vibrant: Color.primary
        }
    }

    /// Secondary text: titles, reset times, captions.
    public var secondary: Color {
        switch style {
        case .fullColor: isDark ? Color.white.opacity(0.62) : Color(red: 0.07, green: 0.08, blue: 0.11).opacity(0.58)
        case .accented, .vibrant: Color.primary.opacity(0.62)
        }
    }

    public var hairline: Color {
        primary.opacity(style == .fullColor ? (isDark ? 0.10 : 0.09) : 0.18)
    }

    public var track: Color {
        switch style {
        case .fullColor: isDark ? Color.white.opacity(0.13) : Color.black.opacity(0.08)
        case .accented, .vibrant: Color.primary.opacity(0.2)
        }
    }

    /// The accentable colour: tinted by the system in `.accented`, white in `.vibrant`.
    public var accent: Color {
        accentPreview ?? Color.primary
    }

    /// Two-stop arc gradient, light to deep along the arc.
    public func arc(_ band: UsageBand, isStale: Bool) -> [Color] {
        switch style {
        case .accented:
            return [accent, accent]
        case .vibrant:
            return [Color.primary, Color.primary]
        case .fullColor:
            if isStale {
                return isDark
                    ? [Color(white: 0.72), Color(white: 0.56)]
                    : [Color(white: 0.62), Color(white: 0.46)]
            }
            return Self.bandGradient(band)
        }
    }

    /// Usage numbers in the band colour, deeper in light and lighter in dark appearance so they stay legible.
    public func number(_ band: UsageBand, isStale: Bool) -> Color {
        switch style {
        case .accented, .vibrant:
            return Color.primary
        case .fullColor:
            if isStale { return secondary }
            let rgb: (Double, Double, Double) = switch (band, isDark) {
            case (.ample, false): (0.05, 0.50, 0.29)
            case (.ample, true): (0.42, 0.90, 0.66)
            case (.watch, false): (0.66, 0.40, 0.00)
            case (.watch, true): (1.00, 0.80, 0.30)
            case (.critical, false): (0.78, 0.28, 0.04)
            case (.critical, true): (1.00, 0.60, 0.38)
            case (.exhausted, false): (0.76, 0.08, 0.22)
            case (.exhausted, true): (1.00, 0.45, 0.50)
            }
            return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
        }
    }

    /// The glow along the part of an arc that runs ahead of time.
    public func overrunGlow(_ band: UsageBand) -> Color {
        style == .fullColor ? Self.bandGradient(band)[1].opacity(isDark ? 0.85 : 0.6) : .clear
    }

    /// "Waiting on you": violet-magenta, never a usage band or a provider accent.
    public var attention: Color {
        switch style {
        case .fullColor: isDark ? Color(red: 0.84, green: 0.52, blue: 1.00) : Color(red: 0.62, green: 0.20, blue: 0.86)
        case .accented: accent
        case .vibrant: Color.primary
        }
    }

    public var attentionFill: Color {
        switch style {
        case .fullColor: Color(red: 0.76, green: 0.35, blue: 0.96).opacity(isDark ? 0.24 : 0.14)
        case .accented, .vibrant: Color.primary.opacity(0.16)
        }
    }

    /// Identity only — a provider's mark in a header, never a ring, meter or number. Accentable content turns the
    /// system tint in `.accented` and white in `.vibrant`.
    public func providerTint(_ provider: ProviderKind) -> Color {
        switch style {
        case .accented: return accent
        case .vibrant: return Color.primary
        case .fullColor:
            let rgb: (Double, Double, Double) = switch (provider, isDark) {
            case (.claude, false): (0.84, 0.36, 0.20)
            case (.claude, true): (0.98, 0.56, 0.38)
            case (.codex, false): (0.24, 0.42, 0.96)
            case (.codex, true): (0.50, 0.64, 1.00)
            }
            return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
        }
    }

    /// The faint disc behind a header's provider mark.
    public func providerTintFill(_ provider: ProviderKind) -> Color {
        switch style {
        case .fullColor: providerTint(provider).opacity(isDark ? 0.20 : 0.13)
        case .accented, .vibrant: Color.primary.opacity(0.14)
        }
    }

    public var chipFill: Color {
        primary.opacity(style == .fullColor ? (isDark ? 0.10 : 0.07) : 0.14)
    }

    // MARK: Account identity

    /// Opacity of an account badge's fill over the widget's own background.
    static let accountFillOpacity = (light: 0.18, dark: 0.24)

    /// An account's identity colour: its monogram, and (faintly) the square behind it.
    ///
    /// Identity only. Account tints never colour an arc, a meter, a number or the background, where colour already
    /// means usage, waiting or provider. `WidgetAccountTint` keeps every tint at least 25° of hue away from both
    /// ends of every band gradient and from `attention`, so an identity mark is never mistaken for a state.
    public func accountTint(_ tint: AccountTint) -> Color {
        switch style {
        // The monogram is the accentable half of the badge, so in `.accented` it takes the system tint and in
        // `.vibrant` the material's own white.
        case .accented: return accent
        case .vibrant: return Color.primary
        case .fullColor:
            let rgb = WidgetAccountTint.components(tint, isDark: isDark)
            return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
        }
    }

    /// The soft square behind an account's monogram.
    public func accountTintFill(_ tint: AccountTint) -> Color {
        switch style {
        case .accented, .vibrant: return Color.primary.opacity(0.14)
        case .fullColor: return accountTint(tint).opacity(isDark ? Self.accountFillOpacity.dark : Self.accountFillOpacity.light)
        }
    }

    // MARK: Forecast

    /// The dashed ghost arc that shows where usage lands by the reset. Quiet on purpose: it is a hint, not a
    /// reading, and the dash pattern — not its colour — is what tells it apart from the used arc.
    public func forecast(_ band: UsageBand) -> Color {
        let opacity = isDark ? 0.42 : 0.34
        switch style {
        case .accented: return accent.opacity(opacity)
        case .vibrant: return Color.primary.opacity(opacity)
        case .fullColor: return Self.bandGradient(band)[1].opacity(opacity)
        }
    }

    static func bandGradient(_ band: UsageBand) -> [Color] {
        switch band {
        case .ample:
            [Color(red: 0.40, green: 0.90, blue: 0.72), Color(red: 0.13, green: 0.74, blue: 0.45)]
        case .watch:
            [Color(red: 1.00, green: 0.85, blue: 0.32), Color(red: 1.00, green: 0.58, blue: 0.12)]
        case .critical:
            [Color(red: 1.00, green: 0.56, blue: 0.30), Color(red: 0.96, green: 0.26, blue: 0.33)]
        case .exhausted:
            [Color(red: 0.98, green: 0.33, blue: 0.40), Color(red: 0.76, green: 0.09, blue: 0.30)]
        }
    }
}

/// The widget's account tints, as plain sRGB components so a test can check their hues and contrast.
///
/// One colour per tint and appearance: it paints the monogram, and the square behind it is the same colour at
/// `WidgetPalette.accountFillOpacity`. Light appearance gets deep colours (they sit on porcelain), dark appearance
/// light ones. `sand`, `slate` and `graphite` are deliberately low in chroma, so eight accounts stay tellable apart
/// without eight loud colours.
public enum WidgetAccountTint {
    public struct Components: Hashable, Sendable {
        public let red: Double
        public let green: Double
        public let blue: Double
    }

    public static func components(_ tint: AccountTint, isDark: Bool) -> Components {
        let rgb: (Double, Double, Double) = switch (tint, isDark) {
        case (.teal, false): (0.00, 0.36, 0.41)
        case (.teal, true): (0.36, 0.83, 0.90)
        case (.sky, false): (0.05, 0.28, 0.55)
        case (.sky, true): (0.52, 0.75, 1.00)
        case (.indigo, false): (0.24, 0.20, 0.66)
        case (.indigo, true): (0.74, 0.72, 1.00)
        case (.lime, false): (0.19, 0.38, 0.04)
        case (.lime, true): (0.60, 0.90, 0.38)
        case (.pink, false): (0.60, 0.12, 0.52)
        case (.pink, true): (1.00, 0.68, 0.96)
        case (.sand, false): (0.40, 0.34, 0.24)
        case (.sand, true): (0.83, 0.76, 0.66)
        case (.slate, false): (0.26, 0.32, 0.42)
        case (.slate, true): (0.68, 0.75, 0.86)
        // `.automatic` never reaches a snapshot; if one ever carried it, it reads as the neutral tint.
        case (.graphite, false), (.automatic, false): (0.30, 0.31, 0.33)
        case (.graphite, true), (.automatic, true): (0.76, 0.78, 0.82)
        }
        return Components(red: rgb.0, green: rgb.1, blue: rgb.2)
    }
}

/// SF Rounded throughout, with monospaced digits for anything that counts.
enum WidgetFont {
    static func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func digits(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}
