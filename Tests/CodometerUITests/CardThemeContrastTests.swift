import CodometerCore
@testable import CodometerUI
import SwiftUI
import Testing

/// Every card theme has to stay legible on its own surface, and Liquid Glass has to stay legible over the darkest and
/// the lightest wallpaper a desktop can show.
@Suite("Card theme contrast")
struct CardThemeContrastTests {
    /// WCAG for text.
    static let textMinimum = 4.5
    /// WCAG for graphical objects: rings, tracks, hairlines.
    static let objectMinimum = 3.0

    private static func tokens(_ theme: CardTheme, scheme: ColorScheme = .dark, contrast: Bool = false, transparency: Bool = false) -> CardThemeTokens {
        CardThemeTokens.resolve(theme: theme, scheme: scheme, reducesTransparency: transparency, increasesContrast: contrast)
    }

    @Test("Primary and secondary text stay above 4.5:1 in every theme", arguments: CardTheme.allCases)
    func textContrast(theme: CardTheme) {
        for scheme in [ColorScheme.light, .dark] {
            let tokens = Self.tokens(theme, scheme: scheme)
            for background in tokens.contrastBackgrounds {
                let primary = tokens.primaryText.contrast(with: background)
                let secondary = tokens.secondaryText.contrast(with: background)
                #expect(primary >= Self.textMinimum, "\(theme)/\(scheme) primary \(primary)")
                #expect(secondary >= Self.textMinimum, "\(theme)/\(scheme) secondary \(secondary)")
            }
        }
    }

    @Test("Text on a tile stays above 4.5:1 in every theme", arguments: CardTheme.allCases)
    func tileTextContrast(theme: CardTheme) {
        for scheme in [ColorScheme.light, .dark] {
            let tokens = Self.tokens(theme, scheme: scheme)
            // Tiles are filled opaquely, so their own fill is the background the value and the label sit on.
            let primary = tokens.primaryText.contrast(with: tokens.tileFill)
            let secondary = tokens.secondaryText.contrast(with: tokens.tileFill)
            #expect(primary >= Self.textMinimum, "\(theme)/\(scheme) primary on tile \(primary)")
            #expect(secondary >= Self.textMinimum, "\(theme)/\(scheme) secondary on tile \(secondary)")
            for band in UsageBand.allCases {
                let ratio = tokens.bandText(band).contrast(with: tokens.tileFill)
                #expect(ratio >= Self.textMinimum, "\(theme)/\(scheme) \(band) on tile \(ratio)")
            }
            // A tile has to be visible against the card around it, without being a second surface.
            #expect(tokens.tileFill.contrast(with: tokens.surface) < Self.textMinimum, "\(theme)/\(scheme) tile is too loud")
        }
    }

    @Test("Band text stays above 4.5:1 in every theme", arguments: CardTheme.allCases)
    func bandTextContrast(theme: CardTheme) {
        for scheme in [ColorScheme.light, .dark] {
            let tokens = Self.tokens(theme, scheme: scheme)
            for background in tokens.contrastBackgrounds {
                for band in UsageBand.allCases {
                    let ratio = tokens.bandText(band).contrast(with: background)
                    #expect(ratio >= Self.textMinimum, "\(theme)/\(scheme) \(band) \(ratio)")
                }
            }
        }
    }

    @Test("The attention colour, which the waiting pill uses, stays readable", arguments: CardTheme.allCases)
    func attentionContrast(theme: CardTheme) {
        for scheme in [ColorScheme.light, .dark] {
            let tokens = Self.tokens(theme, scheme: scheme)
            let attention = tokens.isDark ? Palette.attentionText.dark : Palette.attentionText.light
            for background in tokens.contrastBackgrounds {
                let ratio = attention.contrast(with: background)
                #expect(ratio >= Self.textMinimum, "\(theme)/\(scheme) attention \(ratio)")
            }
        }
    }

    @Test("The ring track stays above 3:1, so an empty ring is still visible", arguments: CardTheme.allCases)
    func trackContrast(theme: CardTheme) {
        for scheme in [ColorScheme.light, .dark] {
            let tokens = Self.tokens(theme, scheme: scheme)
            for background in tokens.contrastBackgrounds {
                let ratio = tokens.track.contrast(with: background)
                #expect(ratio >= Self.objectMinimum, "\(theme)/\(scheme) track \(ratio)")
            }
        }
    }

    @Test("Liquid Glass is measured over both a black and a white desktop")
    func glassHasTwoWorstCases() {
        let glass = Self.tokens(.liquidGlass)
        #expect(glass.contrastBackgrounds.count == 2)
        #expect(glass.isGlass)
        // The scrim keeps even the lightest wallpaper dark enough for white text.
        #expect(glass.surfaceOverLight.luminance < 0.1)
        for theme in [CardTheme.graphite, .midnight, .light] {
            #expect(Self.tokens(theme).contrastBackgrounds.count == 1)
        }
    }

    @Test("Reduce Transparency replaces glass with an opaque theme that follows the appearance")
    func reduceTransparency() {
        #expect(Self.tokens(.liquidGlass, scheme: .dark, transparency: true).theme == .graphite)
        #expect(Self.tokens(.liquidGlass, scheme: .light, transparency: true).theme == .light)
        #expect(!Self.tokens(.liquidGlass, scheme: .dark, transparency: true).isGlass)
        // An opaque theme is unchanged.
        #expect(Self.tokens(.midnight, transparency: true).theme == .midnight)
    }

    @Test("Increase Contrast doubles hairlines, drops glass and lifts secondary text to full strength")
    func increaseContrast() {
        let plain = Self.tokens(.graphite)
        let strong = Self.tokens(.graphite, contrast: true)
        #expect(strong.hairlineWidth == plain.hairlineWidth * 2)
        #expect(strong.secondaryText == strong.primaryText)
        #expect(!Self.tokens(.liquidGlass, contrast: true).isGlass)
    }

    @Test("Tones never rely on colour alone: each one resolves to its own colour")
    func tonesAreDistinct() {
        let tokens = Self.tokens(.graphite)
        let tones: [CardContentPlan.Tone] = [.primary, .secondary, .band(.exhausted), .success, .attention]
        let colors = tones.map { String(describing: tokens.color(for: $0)) }
        #expect(Set(colors).count == tones.count)
    }
}
