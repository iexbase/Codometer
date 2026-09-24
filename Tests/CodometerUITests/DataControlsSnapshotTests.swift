import CodometerCore
import CodometerL10n
@testable import CodometerUI
import AppKit
import Foundation
import SwiftUI
import Testing

/// The History & Data section and the erase sheet, drawn in English and Russian, light and dark. Runs only with
/// `CODOMETER_SNAPSHOT_DIR`; writes `data-<name>-<light|dark>-<en|ru>.png`.
///
/// `ImageRenderer` cannot draw a `Form`, so each surface is hosted in an off-screen window and drawn with
/// `cacheDisplay`, like the other settings renders.
@MainActor
@Suite("Data controls renders", .serialized, .enabled(if: ProcessInfo.processInfo.environment["CODOMETER_SNAPSHOT_DIR"] != nil))
struct DataControlsSnapshotTests {
    private let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODOMETER_SNAPSHOT_DIR"] ?? "/tmp", isDirectory: true)
    private let destination = URL(fileURLWithPath: "/Users/tester/Documents/Codometer History 2026-09-17.json")

    @Test("The section in every export state, and the erase sheet's two steps")
    func render() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let states: [(String, DataControls.Export, Int)] = [
            ("idle", .idle, 35),
            ("custom", .idle, 42),
            ("exporting", .running, 35),
            ("exported", .finished(rows: 12_480, destination: destination), 35),
            ("failed", .failed(.writeFailed("disk full")), 35),
        ]
        for (preference, suffix, region) in [(LanguagePreference.english, "en", "en_US"), (.russian, "ru", "ru_RU")] {
            for scheme in [NSAppearance.Name.aqua, .darkAqua] {
                let mode = scheme == .darkAqua ? "dark" : "light"
                for (name, export, days) in states {
                    let store = try makeStore(language: preference, region: Locale(identifier: region), retentionDays: days)
                    install(export)
                    try await render(
                        Form { DataSection(store: store) }.formStyle(.grouped),
                        l10n: store.localizer,
                        size: NSSize(width: 710, height: 420),
                        appearance: scheme,
                        name: "data-section-\(name)-\(mode)-\(suffix)"
                    )
                }
                install(.idle)
                for step in EraseDataSheet.Step.allCases {
                    let store = try makeStore(language: preference, region: Locale(identifier: region), retentionDays: 35)
                    try await render(
                        EraseDataSheet(initialStep: step, exportFirst: {}, erase: { _ in }, cancel: {}),
                        l10n: store.localizer,
                        size: NSSize(width: EraseDataSheet.width, height: EraseDataSheet.contentHeight),
                        appearance: scheme,
                        name: "data-erase-\(step == .review ? "review" : "confirm")-\(mode)-\(suffix)"
                    )
                }
            }
        }
    }

    private func install(_ export: DataControls.Export) {
        let controls = DataControls.shared
        switch export {
        case .idle: controls.exportIdle()
        case .running: controls.exportStarted()
        case let .finished(rows, destination): controls.exportFinished(rows: rows, destination: destination)
        case .failed(let error): controls.exportFailed(error)
        }
    }

    private func render(
        _ view: some View,
        l10n: Localizer,
        size: NSSize,
        appearance: NSAppearance.Name,
        name: String
    ) async throws {
        let host = NSHostingView(
            rootView: view
                .environment(\.l10n, l10n)
                .environment(\.locale, l10n.locale)
                .frame(width: size.width, height: size.height)
        )
        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: -30_000, y: -30_000), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        for _ in 0..<12 {
            try await Task.sleep(for: .milliseconds(40))
            host.layoutSubtreeIfNeeded()
        }
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }

    private func makeStore(language: LanguagePreference, region: Locale, retentionDays: Int) throws -> TrackerStore {
        let claude = try AccountProfile(
            id: UIFixture.accountID("data/claude"),
            provider: .claude,
            label: try AccountLabel(validating: "Work"),
            directory: try ProfileDirectory(validating: "/Users/tester/.claude")
        )
        var settings = try AppSettings(accounts: [claude])
        settings.general.language = language
        settings.general.historyRetention = try HistoryRetention(days: retentionDays)
        return TrackerStore(
            state: .empty,
            settings: settings,
            now: Date(timeIntervalSince1970: 1_789_590_000),
            actions: UIFixture.actions(),
            preferredLanguages: { ["en-US"] },
            region: { region }
        )
    }
}

/// The data controls' copy: what the picker names each retention, how a finished export reads, and whether the
/// reserved template is really the widest line.
@MainActor
@Suite("Data controls copy")
struct DataControlsCopyTests {
    nonisolated static let languages = [Localizer.testEnglish, .testRussian]
    private let callout = NSFont.preferredFont(forTextStyle: .callout)

    private func width(_ text: String, _ font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
    }

    @Test("The four offered periods are named as periods, a hand-edited value as days")
    func retentionTitles() throws {
        let en = Localizer.testEnglish
        #expect(RetentionCopy.title(try HistoryRetention(days: 7), l10n: en) == "1 week")
        #expect(RetentionCopy.title(try HistoryRetention(days: 14), l10n: en) == "2 weeks")
        #expect(RetentionCopy.title(try HistoryRetention(days: 35), l10n: en) == "5 weeks")
        #expect(RetentionCopy.title(try HistoryRetention(days: 90), l10n: en) == "3 months")
        #expect(RetentionCopy.title(try HistoryRetention(days: 42), l10n: en) == "42 days")

        let ru = Localizer.testRussian
        #expect(RetentionCopy.title(try HistoryRetention(days: 7), l10n: ru) == "1 неделя")
        #expect(RetentionCopy.title(try HistoryRetention(days: 14), l10n: ru) == "2 недели")
        #expect(RetentionCopy.title(try HistoryRetention(days: 35), l10n: ru) == "5 недель")
        #expect(RetentionCopy.title(try HistoryRetention(days: 90), l10n: ru) == "3 месяца")
        #expect(RetentionCopy.title(try HistoryRetention(days: 42), l10n: ru) == "42 дня")
    }

    @Test("Russian plurals agree with the number in every form")
    func russianPlurals() {
        let ru = Localizer.testRussian
        #expect(ru.dataControls.days(1) == "1 день")
        #expect(ru.dataControls.days(3) == "3 дня")
        #expect(ru.dataControls.days(11) == "11 дней")
        #expect(ru.dataControls.days(21) == "21 день")
        #expect(ru.dataControls.months(1) == "1 месяц")
        #expect(ru.dataControls.months(5) == "5 месяцев")
    }

    @Test("A hand-edited retention joins the picker in order and the four choices stay")
    func customChoice() throws {
        let custom = try HistoryRetention(days: 42)
        let choices = RetentionCopy.choices(including: custom)
        #expect(choices.map(\.days) == [7, 14, 35, 42, 90])
        #expect(RetentionCopy.choices(including: .standard).map(\.days) == [7, 14, 35, 90])
    }

    @Test("The export result reads with a grouped number in both languages")
    func exportedRows() {
        #expect(DataControls.exportedRows(1, l10n: .testEnglish) == "Exported 1 row")
        #expect(DataControls.exportedRows(12_480, l10n: .testEnglish) == "Exported 12,480 rows")
        #expect(DataControls.exportedRows(1, l10n: .testRussian) == "Экспортирована 1 строка")
        #expect(DataControls.exportedRows(3, l10n: .testRussian).hasSuffix("строки"))
        #expect(DataControls.exportedRows(12_480, l10n: .testRussian).hasSuffix("строк"))
    }

    @Test("Every export failure has words, and a cancelled export never becomes one")
    func failureMessages() {
        for l10n in Self.languages {
            let errors: [HistoryExportError] = [.historyUnavailable, .destinationExists, .writeFailed("x")]
            let messages = errors.map { DataControls.message(for: $0, l10n: l10n) }
            #expect(messages.allSatisfy { !$0.isEmpty })
            #expect(Set(messages).count == messages.count)
        }
        let controls = DataControls()
        controls.exportFailed(.cancelled)
        #expect(controls.export == .idle)
        controls.exportFailed(.writeFailed("x"))
        #expect(controls.export == .failed(.writeFailed("x")))
    }

    @Test("The reserved result line is at least as wide as a real result", arguments: languages)
    func resultTemplate(l10n: Localizer) {
        let template = width(l10n.dataControls.exportResultTemplate, callout)
        // The widest realistic line: a six-figure row count plus the Finder link.
        let real = width(DataControls.exportedRows(999_999, l10n: l10n), callout)
            + width(" · ", callout)
            + width(l10n.dataControls.showInFinder, callout)
        #expect(real <= template, "\(real) pt > \(template) pt in \(l10n.language)")
    }

    @Test("The CSV readme names every file, stays in one language and carries no personal data", arguments: languages)
    func csvReadme(l10n: Localizer) {
        let text = l10n.dataControls.csvReadme(appVersion: "1.0.0", exportedAt: "2026-09-17T14:32:00+03:00", retentionDays: 35)
        for file in ["limits.csv", "sessions.csv", "tokens.csv", "collection-runs.csv"] {
            #expect(text.contains(file), "\(file)")
        }
        #expect(text.contains("1.0.0"))
        #expect(!text.contains("@"))
        #expect(!text.contains("/Users/"))
        #expect(text.split(separator: "\n").count >= 10)
    }

    @Test("The erase sheet lists what goes and what stays, with no repeated line", arguments: languages)
    func eraseSheetItems(l10n: Localizer) {
        let removed = [
            l10n.dataControls.eraseRemovedHistory,
            l10n.dataControls.eraseRemovedSettings,
            l10n.dataControls.eraseRemovedWidget,
            l10n.dataControls.eraseRemovedNotifications,
        ]
        let kept = [
            l10n.dataControls.eraseKeptProfiles,
            l10n.dataControls.eraseKeptExports,
            l10n.dataControls.eraseKeptApp,
        ]
        #expect(Set(removed + kept).count == removed.count + kept.count)
        #expect((removed + kept).allSatisfy { !$0.isEmpty })
        // Each column is 233 pt wide inside the 520 pt sheet; two lines are the budget.
        for item in removed + kept {
            let height = (item as NSString).boundingRect(
                with: NSSize(width: 233, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: callout]
            ).height
            let lines = Int((height / NSLayoutManager().defaultLineHeight(for: callout)).rounded(.up))
            #expect(lines <= 3, "\(item): \(lines) lines")
        }
    }
}
