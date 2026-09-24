import CodometerCore
import CodometerL10n
@testable import CodometerUI
import Foundation
import Testing

@MainActor
@Suite("Account presentation style and forecast")
struct AccountPresentationStyleTests {
    private func profile(_ label: String, provider: ProviderKind = .claude, tint: AccountTint = .automatic, monogram: String? = nil) throws -> AccountProfile {
        try AccountProfile(
            provider: provider,
            label: try AccountLabel(validating: label),
            directory: try ProfileDirectory(validating: "/Users/example/.\(provider.rawValue)-\(label.lowercased())"),
            tint: tint,
            monogram: try monogram.map { try AccountMonogram(validating: $0) }
        )
    }

    @Test("The store resolves styles over every account, whatever the group filter shows")
    func storeStyles() throws {
        let group = AccountGroup(name: try AccountLabel(validating: "Home"))
        let work = try profile("Work", tint: .teal, monogram: "W")
        let personal = try AccountProfile(
            provider: .claude,
            label: try AccountLabel(validating: "Personal"),
            directory: try ProfileDirectory(validating: "/Users/example/.claude-personal"),
            groupID: group.id
        )
        let side = try profile("Side project", provider: .codex)
        var appearance = AppearanceSettings()
        appearance.railGroupFilter = group.id
        let settings = try AppSettings(accounts: [work, personal, side], groups: [group], appearance: appearance)
        let state = TrackerState(accounts: [work, personal, side].map { AccountStatus(profile: $0) })
        let store = TrackerStore(state: state, settings: settings, now: UIFixture.now, actions: UIFixture.actions())

        let expected = AccountStyleResolver.styles(for: settings.accounts)
        for presentation in store.presentations {
            #expect(presentation.style == expected[presentation.id])
        }
        let visible = try #require(store.visiblePresentations.first)
        #expect(store.visiblePresentations.count == 1)
        #expect(visible.style == expected[personal.id])
        let workStyle = try #require(store.presentations.first?.style)
        #expect(workStyle.tint == .teal && workStyle.monogram.value == "W" && !workStyle.isAutomaticTint)
    }

    @Test("Without a resolved style an account is resolved on its own")
    func ownStyle() throws {
        let work = try profile("Work account")
        let presentation = AccountPresentation(
            status: AccountStatus(profile: work),
            settings: try AppSettings(accounts: [work]),
            now: UIFixture.now,
            l10n: .testEnglish
        )
        #expect(presentation.style == AccountStyleResolver.styles(for: [work])[work.id])
        #expect(presentation.style.monogram.value == "WA")
    }

    @Test("Window forecasts appear only while forecasts are on")
    func forecastSetting() throws {
        // 40 % used with 3 of 5 hours left: 2 hours (40 %) elapsed, so the average pace reaches 100 % by the reset.
        let window = try UIFixture.window("session", .session, used: 40, duration: .fiveHours, resetsIn: 3 * 3_600)
        var appearance = AppearanceSettings()
        let on = WindowPresentation(bucketID: "main", bucketTitle: nil, isMainBucket: true, window: window, appearance: appearance, now: UIFixture.now, l10n: .testEnglish)
        let forecast = try #require(on.forecast)
        #expect(forecast == UsageForecast(window: window, now: UIFixture.now, thresholds: appearance.bands))
        #expect(forecast.reachesLimit)

        appearance.showsForecast = false
        let off = WindowPresentation(bucketID: "main", bucketTitle: nil, isMainBucket: true, window: window, appearance: appearance, now: UIFixture.now, l10n: .testEnglish)
        #expect(off.forecast == nil)
    }
}
