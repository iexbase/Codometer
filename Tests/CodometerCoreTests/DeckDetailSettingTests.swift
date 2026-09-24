import CodometerCore
import Foundation
import Testing

@Suite("Deck detail setting")
struct DeckDetailSettingTests {
    @Test("The essentials are the default and the key round-trips")
    func defaultAndRoundTrip() throws {
        #expect(AppearanceSettings().deckDetail == .essentials)
        var settings = try AppSettings(accounts: [])
        settings.appearance.deckDetail = .full
        let data = try JSONEncoder().encode(settings)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let appearance = try #require(root["appearance"] as? [String: Any])
        #expect(appearance["deckDetail"] as? String == "full")
        let reloaded = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(reloaded.appearance.deckDetail == .full)
    }

    @Test("A missing or unknown value falls back to the essentials")
    func lenient() throws {
        let missing = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"schemaVersion":1,"appearance":{}}"#.utf8))
        #expect(missing.appearance.deckDetail == .essentials)
        let unknown = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"schemaVersion":1,"appearance":{"deckDetail":"lots"}}"#.utf8))
        #expect(unknown.appearance.deckDetail == .essentials)
    }
}
