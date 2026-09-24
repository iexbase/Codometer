import CodometerCore
import CodometerL10n
@testable import CodometerUI
import Foundation
import SwiftUI
import Testing

/// The one rule the palette lives by: colour means exactly one thing. Band colours describe usage, violet-magenta a
/// waiting agent, provider accents a provider — and an account tint says only *which account*.
@MainActor
@Suite("Account tint palette")
struct PaletteConstraintTests {
    @Test("A saturated tint is never close in hue to a colour that means data", arguments: AccountTint.palette)
    func hueDistance(tint: AccountTint) {
        let colour = Palette.accountTint(tint)
        guard colour.chroma >= Palette.lowChroma else { return }
        for data in Palette.dataColors {
            let distance = colour.hueDistance(to: data)
            #expect(
                distance >= Palette.minimumTintHueDistance,
                "\(tint) is \(Int(distance))° from a data colour; at least \(Int(Palette.minimumTintHueDistance))° is needed"
            )
        }
    }

    @Test("A quiet tint really is quiet: the three greys stay under the chroma that would give them a hue")
    func lowChromaTints() {
        for tint in [AccountTint.sand, .slate, .graphite] {
            #expect(Palette.accountTint(tint).chroma < Palette.lowChroma, "\(tint) is too saturated to be exempt from the hue rule")
        }
        // Everything else is saturated enough for the hue rule to mean something.
        for tint in [AccountTint.teal, .sky, .indigo, .lime, .pink] {
            #expect(Palette.accountTint(tint).chroma >= Palette.lowChroma)
        }
    }

    @Test("Tint text is readable on light and on dark glass", arguments: AccountTint.allCases)
    func textContrast(tint: AccountTint) {
        let text = Palette.accountTintText(tint)
        #expect(text.light.contrast(with: Palette.lightGlass) >= 4.5, "\(tint) on light glass")
        #expect(text.dark.contrast(with: Palette.darkGlass) >= 4.5, "\(tint) on dark glass")
    }

    @Test("Every tint is a different colour, so two accounts never look the same")
    func distinct() {
        let colours = AccountTint.palette.map(Palette.accountTint)
        #expect(Set(colours).count == AccountTint.palette.count)
    }

    @Test("Automatic has no colour of its own: it reads as the neutral tint until the resolver picks one")
    func automaticIsNeutral() {
        #expect(Palette.accountTint(.automatic) == Palette.accountTint(.graphite))
        #expect(Palette.accountTintText(.automatic) == Palette.accountTintText(.graphite))
        #expect(AccountBadge.color(for: .automatic) == AccountBadge.color(for: .graphite))
    }

    @MainActor
    @Test("A band never draws in an account's colour")
    func bandsAreNotTints() {
        let tints = Set(AccountTint.allCases.map { Theme.accountTint(for: $0) })
        for band in UsageBand.allCases {
            for colour in Theme.colors(for: band) {
                #expect(!tints.contains(colour), "\(band) draws in an account tint")
            }
            #expect(!tints.contains(Theme.tint(for: band)))
        }
        #expect(!tints.contains(Theme.attention))
    }

    @Test("Every tint has a name in both languages, and they are all different")
    func names() {
        for l10n in [Localizer.testEnglish, .testRussian] {
            let names = AccountTint.allCases.map { TintSwatches.name(of: $0, l10n: l10n) }
            #expect(names.allSatisfy { !$0.isEmpty })
            #expect(Set(names).count == names.count)
        }
        #expect(TintSwatches.name(of: .teal, l10n: .testEnglish) == "Teal")
        #expect(TintSwatches.name(of: .teal, l10n: .testRussian) == "Бирюзовый")
        #expect(TintSwatches.name(of: .automatic, l10n: .testEnglish) == "Automatic")
        #expect(TintSwatches.name(of: .automatic, l10n: .testRussian) == "Авто")
    }

    @Test("The ghost arc stays a hint in both appearances")
    func ghostOpacity() {
        #expect(RingGeometry.ghostOpacity(dark: true) < 0.5)
        #expect(RingGeometry.ghostOpacity(dark: false) < RingGeometry.ghostOpacity(dark: true))
    }
}
