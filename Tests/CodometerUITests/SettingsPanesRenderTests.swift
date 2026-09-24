import CodometerCore
import CodometerL10n
@testable import CodometerUI
import AppKit
import Foundation
import SwiftUI
import Testing

/// General, Notifications, Appearance and Presentation drawn whole, in English and Russian, at the default width of the
/// Settings detail column and at the narrowest one. Runs only with `CODOMETER_SNAPSHOT_DIR`; writes
/// `settings-<pane>[-variant][-narrow]-en.png` and `…-ru.png`.
///
/// `ImageRenderer` cannot draw a `Form`, so each pane is hosted in an off-screen window and drawn with `cacheDisplay`,
/// like the debug harness's Settings stand-in, but tall enough for the whole pane.
@MainActor
@Suite("Settings pane renders", .enabled(if: ProcessInfo.processInfo.environment["CODOMETER_SNAPSHOT_DIR"] != nil))
struct SettingsPanesRenderTests {
    private let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODOMETER_SNAPSHOT_DIR"] ?? "/tmp", isDirectory: true)
    private let now = Date(timeIntervalSince1970: 1_789_590_000)

    /// A variant of the settings that shows text the defaults hide.
    private struct Variant {
        let pane: SettingsPane
        let name: String
        let change: (inout AppSettings) throws(ValidationError) -> Void
    }

    @Test("Panes in both languages, at the default and the narrowest width")
    func renderPanes() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let variants = [
            Variant(pane: .general, name: "general", change: { _ in }),
            // The ⌃⌥Space warning under the key caps.
            Variant(pane: .general, name: "general-space", change: { $0.general.globalShortcut = .controlOptionSpace }),
            Variant(pane: .general, name: "general-off", change: { $0.general.globalShortcut = .off }),
            Variant(pane: .alerts, name: "alerts", change: { _ in }),
            Variant(pane: .appearance, name: "appearance", change: { _ in }),
            // Hidden is the default; the masked example shows an address in the preview capsule.
            Variant(pane: .appearance, name: "appearance-masked", change: { $0.appearance.emailVisibility = .masked }),
            Variant(pane: .presentation, name: "presentation", change: { _ in }),
            // The longest trigger explanation and hint.
            Variant(pane: .presentation, name: "presentation-hover-or-click", change: { $0.appearance.openTrigger = .hoverOrClick }),
        ]
        for (preference, suffix, region) in [(LanguagePreference.english, "en", "en_US"), (.russian, "ru", "ru_RU")] {
            for variant in variants {
                let store = try makeStore(language: preference, region: Locale(identifier: region))
                store.updateSettings(variant.change)
                #expect(store.localizer.language.rawValue == suffix)
                let isBase = variant.name == variant.pane.rawValue
                try await render(
                    store: store,
                    pane: variant.pane,
                    width: Self.defaultDetailWidth,
                    name: "settings-\(variant.name)-\(suffix)"
                )
                if isBase {
                    try await render(store: store, pane: variant.pane, width: Self.narrowestDetailWidth, name: "settings-\(variant.name)-narrow-\(suffix)")
                }
            }
        }
    }

    /// The Settings window opens 920 pt wide with a 210 pt sidebar.
    static let defaultDetailWidth: CGFloat = 710
    /// The Settings window is at least 800 pt wide and its sidebar at most 250 pt.
    static let narrowestDetailWidth: CGFloat = 550

    private func render(store: TrackerStore, pane: SettingsPane, width: CGFloat, name: String) async throws {
        let size = NSSize(width: width, height: 2_000)
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
        // Forms lay out their rows over a few runloop turns.
        for _ in 0..<12 {
            try await Task.sleep(for: .milliseconds(50))
            host.layoutSubtreeIfNeeded()
        }
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }

    private func makeStore(language: LanguagePreference, region: Locale) throws -> TrackerStore {
        let claude = try AccountProfile(
            id: UIFixture.accountID("panes/claude"),
            provider: .claude,
            label: try AccountLabel(validating: "Work"),
            directory: try ProfileDirectory(validating: "/Users/me/.claude")
        )
        let codex = try AccountProfile(
            id: UIFixture.accountID("panes/codex"),
            provider: .codex,
            label: try AccountLabel(validating: "Personal"),
            directory: try ProfileDirectory(validating: "/Users/me/.codex")
        )
        var settings = try AppSettings(accounts: [claude, codex])
        settings.general.language = language
        // Solid, so the stage's island draws in an off-screen capture (glass comes out empty).
        settings.appearance.surface = .solid
        let reading = try UsageReading(
            capturedAt: now.addingTimeInterval(-60),
            source: .claudeUsageCommand,
            buckets: [try LimitBucket(id: "claude", title: nil, windows: [
                try LimitWindow(id: "session", scope: .session, used: try Percentage(validating: 64), duration: .fiveHours, resetsAt: now.addingTimeInterval(8_040)),
            ], isLimitReached: false)],
            credits: nil
        )
        let codexReading = try UsageReading(
            capturedAt: now.addingTimeInterval(-30),
            source: .codexAppServer,
            buckets: [try LimitBucket(id: "codex", title: nil, windows: [
                try LimitWindow(id: "primary", scope: .rolling, used: try Percentage(validating: 32), duration: .fiveHours, resetsAt: now.addingTimeInterval(3_600)),
            ], isLimitReached: false)],
            credits: nil
        )
        let state = TrackerState(accounts: [
            AccountStatus(profile: claude, reading: reading, nextRefreshAt: now.addingTimeInterval(180)),
            AccountStatus(profile: codex, reading: codexReading, nextRefreshAt: now.addingTimeInterval(150)),
        ])
        return TrackerStore(
            state: state,
            settings: settings,
            now: now,
            actions: UIFixture.actions(),
            preferredLanguages: { ["en-US"] },
            region: { region }
        )
    }
}
