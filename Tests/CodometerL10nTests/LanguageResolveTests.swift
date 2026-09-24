import CodometerL10n
import Foundation
import Testing

@Suite("Language resolution")
struct LanguageResolveTests {
    @Test("An explicit choice ignores the system languages")
    func explicit() {
        #expect(Language.resolve(.english, preferredLanguages: ["ru-RU"]) == .en)
        #expect(Language.resolve(.russian, preferredLanguages: ["en-US"]) == .ru)
    }

    private static let systemCases: [([String], Language)] = [
        (["ru-RU", "en-US"], .ru),
        (["de-DE", "ru-RU"], .ru),
        (["ru-UA", "en"], .ru),
        (["ru"], .ru),
        (["en-GB", "ru-RU"], .en),
        (["de-DE"], .en),
        (["uk-UA"], .en),
        ([], .en),
    ]

    @Test("System takes the first supported language, else English", arguments: systemCases)
    func system(preferred: [String], expected: Language) {
        #expect(Language.resolve(.system, preferredLanguages: preferred) == expected)
    }

    @Test("Preferences and languages keep their stored raw values; English is the default")
    func rawValues() {
        #expect(LanguagePreference.default == .english)
        #expect(LanguagePreference.allCases.map(\.rawValue) == ["en", "ru", "system"])
        #expect(LanguagePreference.allCases.map(\.id) == ["en", "ru", "system"])
        #expect(Language.allCases.map(\.rawValue) == ["en", "ru"])
    }

    @Test("An explicit choice pins the process language for system text; System removes the pin")
    func appleLanguages() {
        #expect(LanguagePreference.english.appleLanguages == ["en"])
        #expect(LanguagePreference.russian.appleLanguages == ["ru"])
        #expect(LanguagePreference.system.appleLanguages == nil)
    }
}

@Suite("Localizer")
struct LocalizerTests {
    @Test("Words follow the language, number and clock conventions the region")
    func regionConventions() throws {
        let region = Locale(identifier: "ru_RU")
        let english = Localizer(language: .en, region: region, timeZone: try #require(TimeZone(identifier: "GMT")))
        #expect(english.language == .en)
        #expect(english.locale.language.languageCode == .english)
        #expect(english.locale.region == .russia)
        #expect(english.locale.hourCycle == region.hourCycle)
        #expect(english.format.decimal(2.8) == "2,8")
        #expect(english.usage.working == "Working")
        #expect(english.calendar.identifier == .gregorian)
        #expect(english.calendar.timeZone.identifier == "GMT")
    }

    @Test("Test localizers are fixed: en_US 12-hour Sunday, ru_RU 24-hour Monday, GMT")
    func testLocalizers() {
        #expect(Localizer.testEnglish.locale.region == .unitedStates)
        #expect(Localizer.testEnglish.locale.hourCycle == .oneToTwelve)
        #expect(Localizer.testEnglish.calendar.firstWeekday == 1)
        #expect(Localizer.testRussian.locale.region == .russia)
        #expect(Localizer.testRussian.locale.hourCycle == .zeroToTwentyThree)
        #expect(Localizer.testRussian.calendar.firstWeekday == 2)
        #expect(Localizer.testEnglish.calendar.timeZone.secondsFromGMT() == 0)
        #expect(Localizer.testEnglish != Localizer.testRussian)
        #expect(Localizer.testEnglish == Localizer.testEnglish)
    }

    @Test("Only the chosen branch is evaluated")
    func pickIsLazy() {
        var evaluated: [String] = []
        func mark(_ name: String) -> String {
            evaluated.append(name)
            return name
        }
        #expect(Localizer.testRussian.pick(en: mark("en"), ru: mark("ru")) == "ru")
        #expect(evaluated == ["ru"])
    }

    @Test("Slots put a live text between a prefix and a suffix")
    func slots() {
        let english = Localizer.testEnglish.slot(en: ("Resets in ", ""), ru: ("", " до сброса"))
        #expect(english.prefix == "Resets in " && english.suffix.isEmpty)
        let russian = Localizer.testRussian.slot(en: ("Resets in ", ""), ru: ("", " до сброса"))
        #expect(russian.prefix.isEmpty && russian.suffix == " до сброса")
    }

    @Test("Pseudo-localization is off in tests and pads a phrase by about a third")
    func pseudo() {
        #expect(!PseudoLocalization.isEnabled)
        #expect(PseudoLocalization.expand("Resets in 2h") == "⟦Resets in 2h····⟧")
        #expect(PseudoLocalization.expand("") == "")
    }

    @Test("Language names are written in their own language")
    func nativeNames() {
        for l in [Localizer.testEnglish, .testRussian] {
            #expect(l.languageSettings.nativeName(.en) == "English")
            #expect(l.languageSettings.nativeName(.ru) == "Русский")
        }
        #expect(Localizer.testEnglish.languageSettings.systemLanguage == "System Language")
        #expect(Localizer.testRussian.languageSettings.systemLanguage == "Язык системы")
    }
}
