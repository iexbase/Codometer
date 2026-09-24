import CodometerCore
import CodometerL10n
@testable import CodometerUI
import Foundation
import Observation
import Testing

@MainActor
@Suite("Store localizer")
struct StoreLocalizerTests {
    private final class Languages {
        var preferred: [String]
        init(_ preferred: [String]) { self.preferred = preferred }
    }

    @MainActor
    private final class Counter {
        var count = 0
    }

    private func store(language: LanguagePreference, system: Languages) throws -> TrackerStore {
        var general = GeneralSettings()
        general.language = language
        let settings = try AppSettings(accounts: [], general: general)
        return TrackerStore(
            state: .empty,
            settings: settings,
            now: UIFixture.now,
            actions: UIFixture.actions(),
            preferredLanguages: { system.preferred },
            region: { Locale(identifier: "ru_RU") }
        )
    }

    /// Counts every observed change of `localizer`, re-registering after each one.
    private static func observe(_ store: TrackerStore, _ counter: Counter) {
        withObservationTracking {
            _ = store.localizer
        } onChange: {
            MainActor.assumeIsolated {
                counter.count += 1
                observe(store, counter)
            }
        }
    }

    @Test("English by default; the region supplies number and clock conventions")
    func defaults() throws {
        let store = try store(language: .english, system: Languages(["ru-RU"]))
        #expect(store.localizer.language == .en)
        #expect(store.localizer.locale.region == .russia)
    }

    @Test("Changing the language setting changes the localizer once, and the store's presentations with it")
    func switching() throws {
        let profile = try UIFixture.profile("Claude")
        var general = GeneralSettings()
        general.language = .english
        let settings = try AppSettings(accounts: [profile], general: general)
        let reading = try UIFixture.reading([try UIFixture.bucket("claude", [try UIFixture.window("session", .session, used: 7)])])
        let store = TrackerStore(
            state: TrackerState(accounts: [AccountStatus(profile: profile, reading: reading)]),
            settings: settings,
            now: UIFixture.now,
            actions: UIFixture.actions(),
            preferredLanguages: { ["en-US"] }
        )
        let counter = Counter()
        Self.observe(store, counter)
        #expect(store.presentations.first?.windows.first?.title == "Session · 5h")

        store.updateSettings { $0.general.language = .russian }
        #expect(store.localizer.language == .ru)
        #expect(counter.count == 1)
        #expect(store.presentations.first?.windows.first?.title == "Сессия · 5\u{00A0}ч")

        // Another setting leaves the localizer alone.
        store.updateSettings { $0.appearance.showsPace = false }
        #expect(counter.count == 1)

        store.updateSettings { $0.general.language = .english }
        #expect(store.localizer.language == .en)
        #expect(counter.count == 2)
    }

    @Test("System follows the injected language order and refreshes when it changes")
    func system() throws {
        let languages = Languages(["de-DE", "ru-RU"])
        let store = try store(language: .system, system: languages)
        #expect(store.localizer.language == .ru)
        let counter = Counter()
        Self.observe(store, counter)

        store.refreshLocale()
        #expect(counter.count == 0)

        languages.preferred = ["en-GB", "ru-RU"]
        store.refreshLocale()
        #expect(store.localizer.language == .en)
        #expect(counter.count == 1)

        languages.preferred = ["uk-UA"]
        store.refreshLocale()
        #expect(store.localizer.language == .en)
        #expect(counter.count == 1)
    }

    @Test("An explicit choice ignores the system language order")
    func explicit() throws {
        let languages = Languages(["en-US"])
        let store = try store(language: .russian, system: languages)
        #expect(store.localizer.language == .ru)
        languages.preferred = ["de-DE"]
        store.refreshLocale()
        #expect(store.localizer.language == .ru)
    }
}
