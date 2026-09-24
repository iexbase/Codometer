@testable import CodometerApp
import CodometerCore
import CodometerL10n
@testable import CodometerUI
import AppKit
import Foundation
import SwiftUI
import Testing

/// The words of every notice, in both languages: no raw technical reason ever reaches the user, and no phrase is
/// shared between two different situations.
@MainActor
@Suite("Recovery notices")
struct AppNoticeTextTests {
    private let home = URL(fileURLWithPath: "/Users/person", isDirectory: true)

    private var everyNotice: [AppNotice] {
        [
            .settingsRecovered(backupFileName: "settings.invalid-20260916-202000.json"),
            .settingsRepaired(count: 1),
            .settingsRepaired(count: 3),
            .settingsReadOnly(version: 2),
            .history(.unavailable(reason: "SQLITE_CANTOPEN: unable to open database file /Users/person/x")),
            .history(.recoveredFromCorruption(backupFileName: "history.corrupt-20260916-202000.sqlite")),
            .history(.readOnlyNewerSchema(version: 5)),
            .history(.writesPaused(reason: "SQLITE_FULL: database or disk is full")),
        ]
    }

    @Test("Both languages, no empty text, no technical reason and no absolute path")
    func copy() {
        for l10n in [Localizer.testEnglish, .testRussian] {
            for notice in everyNotice {
                let text = AppNoticeText(notice, l10n: l10n, homeDirectory: home)
                #expect(!text.title.isEmpty)
                #expect(!text.body.isEmpty)
                #expect(!text.systemImage.isEmpty)
                let whole = text.title + " " + text.body
                #expect(!whole.contains("SQLITE"))
                #expect(!whole.contains("permission denied"))
                #expect(!whole.contains("/Users/"))
                // A home path is written as `~`, never spelled out.
                #expect(!whole.contains(NSHomeDirectory()))
            }
        }
    }

    @Test("English and Russian really differ, and each situation has its own words")
    func distinct() {
        let english = everyNotice.map { AppNoticeText($0, l10n: .testEnglish, homeDirectory: home) }
        let russian = everyNotice.map { AppNoticeText($0, l10n: .testRussian, homeDirectory: home) }
        for (en, ru) in zip(english, russian) {
            #expect(en.title != ru.title)
            #expect(en.systemImage == ru.systemImage)
        }
        // "1 value" and "3 values" share a title but not a body; every other pair differs in both.
        #expect(Set(english.map(\.body)).count == english.count)
        #expect(Set(russian.map(\.body)).count == russian.count)
    }

    @Test("“Show in Finder” opens the folder that actually holds what the notice names")
    func revealTarget() {
        for notice in everyNotice {
            let text = AppNoticeText(notice, l10n: .testEnglish, homeDirectory: home)
            switch notice {
            case .settingsRecovered, .settingsRepaired, .history(.recoveredFromCorruption):
                // The backup the notice names sits in Codometer's own data folder.
                #expect(text.reveal == .dataFolder)
            default:
                // Nothing was written aside, so there is nothing to show.
                #expect(text.reveal == nil)
            }
        }
    }

    @Test("A healthy history never shows a banner in practice, and reads as unavailable if it ever did")
    func healthyHistory() {
        let text = AppNoticeText(.history(.ok), l10n: .testEnglish, homeDirectory: home)
        #expect(text.title == Localizer.testEnglish.recovery.historyUnavailableTitle)
    }
}

/// Renders of the lifecycle surfaces, in English and Russian, from fixture data.
///
/// Runs only when `CODOMETER_SNAPSHOT_DIR` is set, e.g.
/// `CODOMETER_SNAPSHOT_DIR=/tmp/shots Scripts/test.sh --filter LifecycleRender`.
@MainActor
@Suite("LifecycleRender", .enabled(if: ProcessInfo.processInfo.environment["CODOMETER_SNAPSHOT_DIR"] != nil))
struct LifecycleRenderTests {
    private let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODOMETER_SNAPSHOT_DIR"] ?? "/tmp", isDirectory: true)
    /// The Settings window opens 920 pt wide with a 210 pt sidebar.
    private let detailWidth: CGFloat = 710
    /// The Settings window is at least 800 pt wide and its sidebar at most 250 pt.
    private let narrowDetailWidth: CGFloat = 550

    /// Every notice the banner can show. They never appear together in the app (one per kind, one history state at a
    /// time), so the render stacks one banner per notice rather than one banner with all of them.
    private let notices: [AppNotice] = [
        .settingsRecovered(backupFileName: "settings.invalid-20260916-202000.json"),
        .settingsRepaired(count: 3),
        .settingsReadOnly(version: 2),
        .history(.unavailable(reason: "SQLITE_CANTOPEN")),
        .history(.recoveredFromCorruption(backupFileName: "history.corrupt-20260916-202000.sqlite")),
        .history(.readOnlyNewerSchema(version: 5)),
        .history(.writesPaused(reason: "SQLITE_FULL")),
    ]

    @Test("Notice banners, the Notifications pane with permission denied, and the popover, in both languages")
    func renderSurfaces() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for language in [LanguagePreference.english, .russian] {
            let suffix = language == .russian ? "ru" : "en"

            // Every notice, each in its own banner, at the width of the Settings detail column.
            let stores = try notices.map { try makeStore(language: language, notices: [$0]) }
            try render(
                VStack(spacing: 0) {
                    ForEach(0..<stores.count, id: \.self) { index in
                        AppNoticeBanner(store: stores[index])
                    }
                }
                .frame(width: detailWidth),
                name: "lifecycle-notices-\(suffix)",
                l10n: stores[0].localizer
            )

            // One notice in the deck, the way the popover shows it.
            let single = try makeStore(language: language, notices: [notices[0]])
            let metrics = IslandMetrics(scale: 1)
            try render(
                AppNoticeBanner(store: single, placement: .deck(metrics))
                    .frame(width: metrics.deckWidth),
                name: "lifecycle-notice-deck-\(suffix)",
                l10n: single.localizer
            )
            try render(
                // Uncapped: `ImageRenderer` cannot draw the scroll view a screen-height cap adds.
                StatusPopoverView(store: single, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.regularMaterial)),
                name: "lifecycle-popover-notice-\(suffix)",
                l10n: single.localizer
            )

            // The Notifications pane while macOS shows none of Codometer's notifications.
            let denied = try makeStore(language: language, notices: [], authorization: .denied)
            try await renderPane(store: denied, pane: .alerts, width: detailWidth, name: "settings-alerts-denied-\(suffix)")
            let narrow = try makeStore(language: language, notices: [], authorization: .denied)
            try await renderPane(store: narrow, pane: .alerts, width: narrowDetailWidth, name: "settings-alerts-denied-narrow-\(suffix)")

            // The alert that stops a launch from a disk image.
            try renderLocationAlert(kind: .diskImage, l10n: denied.localizer, name: "lifecycle-location-alert-\(suffix)")
        }
    }

    // MARK: - Rendering

    private func render(_ view: some View, name: String, l10n: Localizer) throws {
        let content = view
            .padding(24)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .light)
            .environment(\.introAnimationsEnabled, false)
            .environment(\.liveEffectsEnabled, false)
            .environment(\.rendersGlass, false)
            .environment(\.l10n, l10n)
            .environment(\.locale, l10n.locale)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }

    /// `ImageRenderer` cannot draw a `Form`, so a whole pane is hosted off screen and drawn with `cacheDisplay`.
    private func renderPane(store: TrackerStore, pane: SettingsPane, width: CGFloat, name: String) async throws {
        let size = NSSize(width: width, height: 1_400)
        let host = NSHostingView(rootView: SettingsPaneCaptureView(store: store, pane: pane).frame(width: size.width, height: size.height))
        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: -30_000, y: -30_000), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        // Forms lay out their rows over a few runloop turns, and the permission banner waits for an async answer.
        for _ in 0..<14 {
            try await Task.sleep(for: .milliseconds(50))
            host.layoutSubtreeIfNeeded()
        }
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }

    /// The real `NSAlert`, drawn from its own window without ever running it modally.
    private func renderLocationAlert(kind: AppLocationKind, l10n: Localizer, name: String) throws {
        let text = AppLocationAlertText(kind: kind, l10n: l10n)
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = text.title
        alert.informativeText = text.message
        alert.addButton(withTitle: text.button)
        alert.showsSuppressionButton = false
        let window = alert.window
        window.appearance = NSAppearance(named: .aqua)
        // `layout()` is what `runModal()` calls before showing the panel; without it the window holds an unsized
        // template with placeholder buttons.
        alert.layout()
        guard let view = window.contentView else {
            Issue.record("the alert has no content view")
            return
        }
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }

    // MARK: - Fixture

    private func makeStore(
        language: LanguagePreference,
        notices: [AppNotice],
        authorization: NotificationAuthorization = .authorized
    ) throws -> TrackerStore {
        var base = AppSettings.empty
        base.general.language = language
        // Solid, so the deck draws in an off-screen capture (glass comes out empty).
        base.appearance.surface = .solid
        let fixture = try DebugFixtures.make(.standard, base: base)
        let store = TrackerStore(
            state: fixture.state,
            settings: fixture.settings,
            now: fixture.now,
            actions: TrackerActions(
                refresh: { _ in },
                persistSettings: { _ in },
                discoverProfiles: { [] },
                revealDataFolder: {},
                setLaunchAtLogin: { _ in nil },
                openSettings: {},
                quit: {},
                notificationAuthorization: { authorization }
            ),
            preferredLanguages: { ["en-US"] },
            region: { Locale(identifier: language == .russian ? "ru_RU" : "en_US") }
        )
        store.setNotices(notices)
        #expect(store.localizer.language.rawValue == (language == .russian ? "ru" : "en"))
        return store
    }
}
