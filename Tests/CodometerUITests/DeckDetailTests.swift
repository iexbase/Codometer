import CodometerCore
import CodometerL10n
@testable import CodometerUI
import Foundation
import Testing

@Suite("Deck detail levels")
struct DeckDetailTests {
    @Test("The essentials keep the overview only; everything keeps every page")
    func pages() {
        #expect(DeckLayout.availablePages(detail: .essentials) == [.overview])
        #expect(DeckLayout.availablePages(detail: .full) == DeckLayout.availablePages)
    }

    @Test("The essentials list every window as a tile, the primary first and alone")
    func essentialSections() throws {
        let main = try UIFixture.bucket("claude", [
            try UIFixture.window("session", .session, used: 7, resetsIn: 2.5 * 3_600),
            try UIFixture.window("week", .weekly(model: nil), used: 38, duration: .oneWeek, resetsIn: 3 * 86_400),
            try UIFixture.window("week.fable", .weekly(model: "Fable"), used: 63, duration: .oneWeek, resetsIn: 3 * 86_400),
        ])
        let spark = try UIFixture.bucket("spark", title: "GPT-5.3-Codex-Spark", [
            try UIFixture.window("primary", used: 12),
        ])
        let status = AccountStatus(profile: try UIFixture.profile("Claude"), reading: try UIFixture.reading([main, spark]))
        let presentation = AccountPresentation(status: status, appearance: AppearanceSettings(), now: UIFixture.now, l10n: .testEnglish)
        let sections = DeckLayout.essentialSections(
            windows: presentation.windows,
            primaryWindowID: presentation.headline?.primary.id
        )
        let full = DeckLayout.windowSections(windows: presentation.windows, primaryWindowID: presentation.headline?.primary.id)
        let hero = try #require(full.hero)
        #expect(sections.first?.tiles.map(\.id) == [hero.id])
        #expect(sections.first?.title == nil)
        #expect(sections.dropFirst().map(\.id) == full.sections.map(\.id))
        let tiles = sections.flatMap(\.tiles).map(\.id)
        #expect(Set(tiles) == Set(presentation.windows.map(\.id)))
        #expect(tiles.count == presentation.windows.count)
    }

    @Test("Without a primary window there is nothing to promote")
    func noWindows() {
        #expect(DeckLayout.essentialSections(windows: [], primaryWindowID: nil).isEmpty)
    }
}
