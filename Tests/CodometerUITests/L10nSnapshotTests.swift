import CodometerCore
import CodometerL10n
@testable import CodometerUI
import AppKit
import Foundation
import SwiftUI
import Testing

/// The same island in English and Russian after switching `general.language` on one store: the rail's countdown, the
/// deck's header and cards, and the popover. Runs only with `CODOMETER_SNAPSHOT_DIR`; writes `…-en.png` and `…-ru.png`.
@MainActor
@Suite("Language snapshots", .enabled(if: ProcessInfo.processInfo.environment["CODOMETER_SNAPSHOT_DIR"] != nil))
struct L10nSnapshotTests {
    private let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODOMETER_SNAPSHOT_DIR"] ?? "/tmp", isDirectory: true)
    private let now = Date(timeIntervalSince1970: 1_789_590_000)

    @Test("Rail countdown, deck header and popover in both languages")
    func renderLanguages() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let region = RegionBox()
        let store = try makeStore(region: region)
        for (preference, suffix, regionIdentifier) in [(LanguagePreference.english, "en", "en_US"), (.russian, "ru", "ru_RU")] {
            region.locale = Locale(identifier: regionIdentifier)
            store.updateSettings { $0.general.language = preference }
            store.refreshLocale()
            #expect(store.localizer.language.rawValue == suffix)

            let rail = IslandModel(layout: IslandLayout(edge: .top, anchor: .top, style: .attached, metrics: IslandMetrics(scale: 1)))
            try render(
                RailView(store: store, model: rail, accounts: store.presentations)
                    .modifier(IslandSurfaceModifier(surface: .solid, shape: IslandRootView.silhouette(layout: rail.layout, expanded: false)))
                    .environment(\.colorScheme, .dark),
                store: store,
                name: "l10n-rail-countdown-\(suffix)"
            )
            let deck = IslandModel(layout: IslandLayout(edge: .top, anchor: .top, style: .floating, metrics: IslandMetrics(scale: 1)))
            try render(
                DeckContent(store: store, model: deck, accounts: store.presentations, context: .island)
                    .background(RoundedRectangle(cornerRadius: deck.layout.metrics.deckCorner, style: .continuous).fill(.regularMaterial)),
                store: store,
                name: "l10n-deck-\(suffix)"
            )
            try render(
                // Uncapped: `ImageRenderer` cannot draw the scroll view a screen-height cap adds.
                StatusPopoverView(store: store, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.regularMaterial)),
                store: store,
                name: "l10n-popover-\(suffix)"
            )
        }
    }

    /// The region the store's localizer takes, changed between languages so each image has its own conventions.
    private final class RegionBox {
        var locale = Locale(identifier: "en_US")
    }

    private func render(_ view: some View, store: TrackerStore, name: String) throws {
        let content = view
            .padding(28)
            .background(LinearGradient(
                colors: [Color(red: 0.98, green: 0.55, blue: 0.40), Color(red: 0.16, green: 0.50, blue: 0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            // What `IslandRootView` injects in the app.
            .environment(\.l10n, store.localizer)
            .environment(\.locale, store.localizer.locale)
            .environment(\.introAnimationsEnabled, false)
            .environment(\.liveEffectsEnabled, false)
            .environment(\.rendersGlass, false)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }

    private func makeStore(region: RegionBox) throws -> TrackerStore {
        let claude = try AccountProfile(
            id: UIFixture.accountID("l10n/claude"),
            provider: .claude,
            label: try AccountLabel(validating: "Work"),
            directory: try ProfileDirectory(validating: "/Users/me/.claude")
        )
        let codex = try AccountProfile(
            id: UIFixture.accountID("l10n/codex"),
            provider: .codex,
            label: try AccountLabel(validating: "Personal"),
            directory: try ProfileDirectory(validating: "/Users/me/.codex")
        )
        let settings = try AppSettings(accounts: [claude, codex])
        // Work is blocked by its session window for 47 minutes, so the rail shows a countdown with a unit.
        let claudeReading = try UsageReading(
            capturedAt: now.addingTimeInterval(-120),
            source: .claudeUsageCommand,
            buckets: [try LimitBucket(id: "claude", title: nil, windows: [
                try window("session", .session, 100, .fiveHours, resetsIn: 47 * 60),
                try window("week", .weekly(model: nil), 71, .oneWeek, resetsIn: 3 * 86_400 + 4 * 3_600),
            ], isLimitReached: false)],
            credits: nil
        )
        let codexReading = try UsageReading(
            capturedAt: now.addingTimeInterval(-30),
            source: .codexAppServer,
            buckets: [try LimitBucket(id: "codex", title: nil, windows: [
                try window("primary", .rolling, 42, .fiveHours, resetsIn: 3 * 3_600 + 5 * 60),
                try window("secondary", .rolling, 27, .oneWeek, resetsIn: 5 * 86_400),
            ], isLimitReached: false)],
            credits: nil
        )
        let waiting = try AgentSession(
            id: "b",
            title: "api",
            projectPath: "/Users/me/api",
            activity: .waiting,
            detail: "permission prompt",
            activitySince: now.addingTimeInterval(-65),
            processID: 2
        )
        let working = try AgentSession(
            id: "a",
            title: "web",
            projectPath: "/Users/me/web",
            activity: .working,
            detail: nil,
            activitySince: now.addingTimeInterval(-420),
            processID: 1,
            lastTurn: try TurnTiming(startedAt: now.addingTimeInterval(-900), endedAt: now.addingTimeInterval(-648), duration: 252, firstTokenLatency: 2.8, wasAborted: false),
            lastEventAt: now.addingTimeInterval(-20)
        )
        let state = TrackerState(accounts: [
            AccountStatus(profile: claude, reading: claudeReading, nextRefreshAt: now.addingTimeInterval(180), sessions: [working]),
            AccountStatus(profile: codex, reading: codexReading, nextRefreshAt: now.addingTimeInterval(150), sessions: [waiting]),
        ])
        return TrackerStore(
            state: state,
            settings: settings,
            now: now,
            actions: UIFixture.actions(),
            preferredLanguages: { ["en-US"] },
            region: { region.locale }
        )
    }

    private func window(_ id: String, _ scope: LimitWindowScope, _ used: Double, _ duration: WindowDuration, resetsIn: TimeInterval) throws -> LimitWindow {
        try LimitWindow(id: id, scope: scope, used: try Percentage(validating: used), duration: duration, resetsAt: now.addingTimeInterval(resetsIn))
    }
}
