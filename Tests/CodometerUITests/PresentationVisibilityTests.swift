import CodometerCore
import CodometerL10n
@testable import CodometerUI
import AppKit
import Foundation
import SwiftUI
import Testing

/// The Presentation pane's Behavior section: the rows it shows for each style and what they are called.
///
/// `AppearanceSettings.visibility` hides whichever surface is the chosen style, but its row used to be inside the
/// pane's `if isIsland`, so a user who switched the card off from the menu bar item could not switch it back on
/// anywhere in Settings. The section is now built from `PlacementPane.behaviorRows(for:)`, and these tests read the
/// same list.
@MainActor
@Suite("Presentation visibility")
struct PresentationVisibilityTests {
    private static let languages: [Localizer] = [.testEnglish, .testRussian]

    @Test("Both styles offer the visibility switch; only the island offers hide-in-full-screen here")
    func rowsPerStyle() {
        #expect(PlacementPane.behaviorRows(for: .island) == [.visibility, .hideInFullScreen, .snapping, .haptics])
        #expect(PlacementPane.behaviorRows(for: .floatingCard) == [.visibility, .snapping, .haptics])
        for style in PresentationStyle.allCases {
            #expect(PlacementPane.behaviorRows(for: style).contains(.visibility), "\(style) cannot be switched off and on")
        }
        // The card's own hide-in-full-screen row lives with its other rows; it is never missing, only elsewhere.
        #expect(!PlacementPane.behaviorRows(for: .floatingCard).contains(.hideInFullScreen))
        // No row is listed twice, and the order never depends on the style.
        for style in PresentationStyle.allCases {
            let rows = PlacementPane.behaviorRows(for: style)
            #expect(Set(rows).count == rows.count)
            #expect(rows == PlacementPane.BehaviorRow.allCases.filter { rows.contains($0) })
        }
    }

    @Test("The visibility row is named after the surface it is about, in English and Russian")
    func visibilityCopy() {
        let en = Localizer.testEnglish
        let ru = Localizer.testRussian
        #expect(PlacementPane.title(.visibility, style: .island, l10n: en) == "Show the island")
        #expect(PlacementPane.title(.visibility, style: .floatingCard, l10n: en) == "Show the card")
        #expect(PlacementPane.title(.visibility, style: .island, l10n: ru) == "Показывать остров")
        #expect(PlacementPane.title(.visibility, style: .floatingCard, l10n: ru) == "Показывать карточку")
        // The line under it says what is left when the surface is off, and names no surface, so it fits both.
        for l10n in Self.languages {
            let note = PlacementPane.subtitle(.visibility, l10n: l10n)
            #expect(note == l10n.placement.showIslandSubtitle)
            #expect(note?.localizedCaseInsensitiveContains(l10n.placement.showIsland) == false)
            #expect(note?.localizedCaseInsensitiveContains(l10n.placement.showCard) == false)
        }
    }

    @Test("Every Behavior row has a title in both languages, and a symbol that exists")
    func everyRowIsNamedAndDrawn() {
        for l10n in Self.languages {
            for style in PresentationStyle.allCases {
                for row in PlacementPane.behaviorRows(for: style) {
                    let title = PlacementPane.title(row, style: style, l10n: l10n)
                    #expect(!title.isEmpty, "\(l10n.language) \(style) \(row) has no title")
                    #expect(title == title.trimmingCharacters(in: .whitespacesAndNewlines))
                    let symbol = PlacementPane.systemImage(row, style: style)
                    #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "\(symbol) is not a symbol")
                }
            }
        }
    }

    @Test("The two styles' titles differ only where the surface is named")
    func onlyVisibilityRenames() {
        for l10n in Self.languages {
            for row in PlacementPane.BehaviorRow.allCases {
                let island = PlacementPane.title(row, style: .island, l10n: l10n)
                let card = PlacementPane.title(row, style: .floatingCard, l10n: l10n)
                #expect((island == card) == (row != .visibility), "\(row) renamed unexpectedly in \(l10n.language)")
            }
        }
    }

    @Test("Switching the card off and on again goes through the same one setting", arguments: PresentationStyle.allCases)
    func oneSettingForBothStyles(style: PresentationStyle) throws {
        let scene = try CeremonyScene(language: .english)
        scene.store.updateSettings { $0.appearance.presentationStyle = style }
        #expect(scene.store.settings.appearance.visibility == .always)

        // What the menu bar item's "Hide" does, and what the row then has to be able to undo.
        scene.store.updateSettings { $0.appearance.visibility = .hidden }
        #expect(scene.store.settings.appearance.visibility == .hidden)
        #expect(PlacementPane.behaviorRows(for: style).contains(.visibility))

        scene.store.updateSettings { $0.appearance.visibility = .always }
        #expect(scene.store.settings.appearance.visibility == .always)
        // The style is untouched by the visibility change: the surface comes back as the one that was hidden.
        #expect(scene.store.settings.appearance.presentationStyle == style)
    }

    @Test("The row titles fit the pane's narrowest width in both languages")
    func titlesFit() {
        // The Settings window's narrowest detail column, minus the symbol and the switch beside the label.
        let room: CGFloat = 550 - 40 - 34 - 60
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        for l10n in Self.languages {
            for style in PresentationStyle.allCases {
                for row in PlacementPane.behaviorRows(for: style) {
                    let title = PlacementPane.title(row, style: style, l10n: l10n)
                    let width = (title as NSString).size(withAttributes: [.font: font]).width
                    #expect(width <= room, "\(l10n.language) \(style) \(row): \(title) takes \(width) pt of \(room)")
                }
            }
        }
    }
}
