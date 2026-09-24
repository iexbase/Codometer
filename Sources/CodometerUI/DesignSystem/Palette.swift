import CodometerCore
import Foundation

extension Palette {
    /// An sRGB colour as plain numbers, so the palette's contrast can be checked without a renderer.
    public struct RGB: Hashable, Sendable {
        public let red: Double
        public let green: Double
        public let blue: Double

        public init(_ red: Double, _ green: Double, _ blue: Double) {
            self.red = min(max(red, 0), 1)
            self.green = min(max(green, 0), 1)
            self.blue = min(max(blue, 0), 1)
        }

        /// WCAG relative luminance, 0 (black) … 1 (white).
        public var luminance: Double {
            func linear(_ component: Double) -> Double {
                component <= 0.040_45 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }

        /// Hue angle in degrees, 0 ..< 360; 0 for greys.
        public var hue: Double {
            let high = max(red, green, blue)
            let low = min(red, green, blue)
            let chroma = high - low
            guard chroma > 0 else { return 0 }
            let sector: Double
            if high == red {
                sector = ((green - blue) / chroma).truncatingRemainder(dividingBy: 6)
            } else if high == green {
                sector = (blue - red) / chroma + 2
            } else {
                sector = (red - green) / chroma + 4
            }
            let degrees = sector * 60
            return degrees < 0 ? degrees + 360 : degrees
        }

        /// How far the colour is from grey, 0 (grey) … 1. Colours below `Palette.lowChroma` read as greys, so the
        /// hue they happen to have carries no meaning.
        public var chroma: Double {
            max(red, green, blue) - min(red, green, blue)
        }

        /// The shortest distance between two hues, 0 … 180 degrees.
        public func hueDistance(to other: RGB) -> Double {
            let difference = abs(hue - other.hue).truncatingRemainder(dividingBy: 360)
            return min(difference, 360 - difference)
        }

        /// WCAG contrast ratio with another colour, 1 … 21.
        public func contrast(with other: RGB) -> Double {
            let lighter = max(luminance, other.luminance)
            let darker = min(luminance, other.luminance)
            return (lighter + 0.05) / (darker + 0.05)
        }
    }

    /// A colour with separate values for light and dark appearance.
    public struct Adaptive: Hashable, Sendable {
        public let light: RGB
        public let dark: RGB

        public init(light: RGB, dark: RGB) {
            self.light = light
            self.dark = dark
        }
    }
}

/// The raw colour values behind `Theme`. Every colour has exactly one meaning:
/// band colours describe usage, the attention colour a waiting agent, provider accents identity only.
public enum Palette {
    /// Typical glass backgrounds the palette must stay legible on.
    public static let lightGlass = RGB(0.92, 0.92, 0.92)
    public static let darkGlass = RGB(0.17, 0.17, 0.18)

    /// Two stops per band, light to deep along an arc; saturated enough to hold up on glass.
    public static func bandGradient(_ band: UsageBand) -> (start: RGB, end: RGB) {
        switch band {
        case .ample: (RGB(0.30, 0.86, 0.62), RGB(0.05, 0.68, 0.46))
        case .watch: (RGB(1.00, 0.82, 0.26), RGB(0.98, 0.60, 0.05))
        case .critical: (RGB(1.00, 0.54, 0.24), RGB(0.93, 0.30, 0.12))
        case .exhausted: (RGB(0.99, 0.36, 0.45), RGB(0.84, 0.10, 0.32))
        }
    }

    /// Band colours for text: at least 4.5:1 against typical light and dark glass.
    public static func bandText(_ band: UsageBand) -> Adaptive {
        switch band {
        case .ample: Adaptive(light: RGB(0.00, 0.45, 0.29), dark: RGB(0.38, 0.88, 0.66))
        case .watch: Adaptive(light: RGB(0.62, 0.33, 0.00), dark: RGB(1.00, 0.78, 0.30))
        case .critical: Adaptive(light: RGB(0.72, 0.23, 0.00), dark: RGB(1.00, 0.62, 0.42))
        case .exhausted: Adaptive(light: RGB(0.74, 0.05, 0.20), dark: RGB(1.00, 0.52, 0.57))
        }
    }

    /// Violet-magenta: far from every band colour and from the Codex blue.
    public static let attention = RGB(0.76, 0.35, 0.96)
    public static let attentionText = Adaptive(light: RGB(0.58, 0.16, 0.78), dark: RGB(0.86, 0.58, 1.00))

    public static func accent(_ provider: ProviderKind) -> RGB {
        switch provider {
        case .claude: RGB(0.93, 0.45, 0.28)
        case .codex: RGB(0.36, 0.52, 1.00)
        }
    }

    // MARK: Account tints

    /// The mark colour of an account tint: the badge's wash and the small identity dot.
    ///
    /// Identity only — these never colour an arc, a bar, a rim or the glass. Saturated tints keep at least
    /// `minimumTintHueDistance` from every band colour and from `attention`, so a tint is never mistaken for usage or
    /// for a waiting agent; the three quiet tints stay under `lowChroma` instead (`PaletteConstraintTests`).
    public static func accountTint(_ tint: AccountTint) -> RGB {
        switch tint {
        case .teal: RGB(0.12, 0.64, 0.72)
        case .sky: RGB(0.10, 0.52, 0.82)
        case .indigo: RGB(0.30, 0.27, 0.83)
        case .lime: RGB(0.32, 0.58, 0.14)
        case .pink: RGB(0.83, 0.17, 0.70)
        case .sand: RGB(0.69, 0.61, 0.51)
        case .slate: RGB(0.46, 0.54, 0.64)
        // A resolved style never carries `.automatic`; a raw one reads as the neutral tint.
        case .graphite, .automatic: RGB(0.50, 0.50, 0.50)
        }
    }

    /// An account tint for text and glyphs: at least 4.5:1 against typical light and dark glass.
    public static func accountTintText(_ tint: AccountTint) -> Adaptive {
        switch tint {
        case .teal: Adaptive(light: RGB(0.01, 0.44, 0.51), dark: RGB(0.45, 0.81, 0.87))
        case .sky: Adaptive(light: RGB(0.02, 0.35, 0.58), dark: RGB(0.44, 0.72, 0.92))
        case .indigo: Adaptive(light: RGB(0.13, 0.11, 0.65), dark: RGB(0.56, 0.54, 0.94))
        case .lime: Adaptive(light: RGB(0.20, 0.46, 0.02), dark: RGB(0.59, 0.83, 0.41))
        case .pink: Adaptive(light: RGB(0.58, 0.06, 0.47), dark: RGB(0.92, 0.52, 0.84))
        case .sand: Adaptive(light: RGB(0.43, 0.32, 0.17), dark: RGB(0.80, 0.73, 0.64))
        case .slate: Adaptive(light: RGB(0.24, 0.31, 0.40), dark: RGB(0.66, 0.71, 0.78))
        case .graphite, .automatic: Adaptive(light: RGB(0.30, 0.30, 0.30), dark: RGB(0.72, 0.72, 0.72))
        }
    }

    /// How far a saturated account tint has to stay from every data colour, in degrees of hue.
    public static let minimumTintHueDistance: Double = 25
    /// Tints under this chroma read as greys and are exempt from the hue rule.
    public static let lowChroma: Double = 0.2

    /// Every colour that means data: the band gradient ends and the attention colour.
    public static var dataColors: [RGB] {
        UsageBand.allCases.flatMap { [bandGradient($0).start, bandGradient($0).end] } + [attention]
    }
}
