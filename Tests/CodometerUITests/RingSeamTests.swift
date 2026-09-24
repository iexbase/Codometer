import CodometerCore
import CodometerL10n
@testable import CodometerUI
import CoreGraphics
import Foundation
import Testing

@MainActor
@Suite("Ring and settings seams")
struct RingSeamTests {
    @Test("The anchor sink keeps rail and deck boxes apart and ignores other surfaces")
    func anchorSink() {
        let sink = RingAnchorSink()
        let id = AccountID()
        let box = CGRect(x: 10, y: 4, width: 28, height: 28)
        sink.report(box, accountID: id, surface: .rail)
        sink.report(box.offsetBy(dx: 0, dy: 60), accountID: id, surface: .deck)
        sink.report(box, accountID: id, surface: .card)
        sink.report(box, accountID: id, surface: .popover)
        #expect(sink.rail == [id: box])
        #expect(sink.deck == [id: box.offsetBy(dx: 0, dy: 60)])

        sink.remove(accountID: id, surface: .rail)
        sink.remove(accountID: id, surface: .popover)
        #expect(sink.rail.isEmpty && sink.deck.count == 1)
        #expect(RingAnchorSink.coordinateSpace == "island.stage")
    }

    @Test("Settings has six panes; Presentation and Diagnostics are localized")
    func panes() {
        #expect(SettingsPane.allCases == [.accounts, .presentation, .appearance, .alerts, .general, .diagnostics])
        #expect(SettingsPane.presentation.title(.testEnglish) == "Presentation")
        #expect(SettingsPane.presentation.title(.testRussian) == "Отображение")
        #expect(SettingsPane.diagnostics.title(.testEnglish) == "Diagnostics")
        #expect(SettingsPane.diagnostics.title(.testRussian) == "Диагностика")
        #expect(SettingsPane(rawValue: "placement") == nil)
    }

    @Test("A notice's id names its kind")
    func noticeIDs() {
        #expect(AppNotice.settingsRecovered(backupFileName: "settings.invalid-1.json").id == "settingsRecovered")
        #expect(AppNotice.settingsReadOnly(version: 2).id == "settingsReadOnly")
        #expect(AppNotice.history(.ok).id == AppNotice.history(.writesPaused(reason: "full")).id)
    }

    @Test("Badge text scales with its side and never drops below the legible minimum")
    func badgeFont() {
        #expect(AccountBadge.fontSize(side: 30, characters: 1) == 15)
        #expect(abs(AccountBadge.fontSize(side: 30, characters: 2) - 12.6) < 0.0001)
        #expect(AccountBadge.fontSize(side: 20, characters: 1) == IslandMetrics.minimumTextSize)
        // Tiny badges keep the text inside the square rather than at the minimum size.
        #expect(abs(AccountBadge.fontSize(side: 14, characters: 1) - 8.4) < 0.0001)
        #expect(AccountBadge.color(for: .automatic) == AccountBadge.color(for: .graphite))
    }
}
