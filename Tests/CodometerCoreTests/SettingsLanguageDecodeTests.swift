import CodometerCore
import CodometerL10n
import Foundation
import Testing

@Suite("Settings language")
struct SettingsLanguageDecodeTests {
    private func general(_ json: String) throws -> GeneralSettings {
        try JSONDecoder().decode(GeneralSettings.self, from: Data(json.utf8))
    }

    @Test("English is the default, also for a settings file written before the key existed")
    func missingIsEnglish() throws {
        #expect(GeneralSettings().language == .english)
        #expect(try general(#"{"launchesAtLogin": true}"#).language == .english)
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"schemaVersion": 1, "accounts": [], "general": {"launchesAtLogin": false}}"#.utf8))
        #expect(settings.general.language == .english)
    }

    @Test("Unknown, null and mistyped values fall back to English without failing the file", arguments: [
        #"{"language": "de"}"#, #"{"language": null}"#, #"{"language": 3}"#, #"{"language": ["ru"]}"#, #"{"language": "RU"}"#,
    ])
    func lenient(json: String) throws {
        let decoded = try general(json)
        #expect(decoded.language == .english)
        #expect(decoded.globalShortcut == GeneralSettings().globalShortcut)
    }

    @Test("Every choice round-trips and is always written", arguments: LanguagePreference.allCases)
    func roundTrip(preference: LanguagePreference) throws {
        let settings = GeneralSettings(language: preference)
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(GeneralSettings.self, from: data) == settings)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["language"] as? String == preference.rawValue)
        #expect(try general(#"{"language": "\#(preference.rawValue)"}"#).language == preference)
    }
}
