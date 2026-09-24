import CodometerCore
import CodometerL10n
@testable import CodometerUI
import AppKit
import Foundation
import SwiftUI
import Testing

/// Renders the island's placement work for visual review, in English and Russian (`…-en.png`, `…-ru.png`):
/// the rail fused with the camera notch, the rings mid-flight, and the Presentation pane with each style selected.
/// Runs only with `CODOMETER_SNAPSHOT_DIR`.
@MainActor
@Suite("Island placement snapshots", .enabled(if: ProcessInfo.processInfo.environment["CODOMETER_SNAPSHOT_DIR"] != nil))
struct IslandSnapshotTests {
    private let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODOMETER_SNAPSHOT_DIR"] ?? "/tmp", isDirectory: true)
    private let now = Date(timeIntervalSince1970: 1_789_590_000)

    // MARK: - Fused rail

    @Test("The fused rail with 1, 2 and 5 accounts, at two scales, in both languages")
    func renderFusedRail() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for language in [LanguagePreference.english, .russian] {
            let store = try makeStore(accounts: 5, language: language)
            let suffix = store.localizer.language.rawValue
            for count in [1, 2, 5] {
                for scale in [CGFloat(0.85), 1.25] {
                    let notch = try #require(Self.notch(scale: scale))
                    let model = IslandModel(layout: IslandLayout(
                        edge: .top,
                        anchor: .top,
                        style: .attached,
                        metrics: IslandMetrics(scale: scale),
                        edgeInset: notch.menuBarHeight,
                        notch: notch,
                        isNotchFused: true
                    ))
                    let accounts = Array(store.presentations.prefix(count))
                    try render(
                        NotchRailView(store: store, model: model, accounts: accounts, notch: notch)
                            .background(Color.black),
                        name: "island-notch-\(count)accounts-scale\(Int(scale * 100))-\(suffix)",
                        l10n: store.localizer
                    )
                }
            }
        }
    }

    // MARK: - Ring flight

    @Test("Rings halfway between the rail and the deck, on every edge, in both languages")
    func renderFlight() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for language in [LanguagePreference.english, .russian] {
            let store = try makeStore(accounts: 3, language: language)
            let suffix = store.localizer.language.rawValue
            for edge in [ScreenEdge.top, .bottom] {
                let metrics = IslandMetrics(scale: 1)
                let pairs = Self.pairs(for: store.presentations, edge: edge, metrics: metrics)
                let accounts = Dictionary(store.presentations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                try render(
                    RingFlightLayer(
                        pairs: pairs,
                        progress: 0.5,
                        edge: edge,
                        accounts: accounts,
                        deckDiameter: metrics.deckDial,
                        showsInnerRings: true
                    )
                    .frame(width: Self.flightStage.width, height: Self.flightStage.height)
                    .background(Color.black.opacity(0.82)),
                    name: "island-flight-\(edge.rawValue)-\(suffix)",
                    l10n: store.localizer
                )
            }
        }
    }

    // MARK: - Presentation pane

    @Test("The Presentation pane with the island and with the floating card selected, in both languages")
    func renderPresentationPane() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for language in [LanguagePreference.english, .russian] {
            for style in [PresentationStyle.island, .floatingCard] {
                let store = try makeStore(accounts: 2, language: language)
                store.updateSettings { $0.appearance.presentationStyle = style }
                let suffix = store.localizer.language.rawValue
                let name = style == .island ? "settings-presentation-island" : "settings-presentation-card"
                try await renderPane(store: store, name: "\(name)-\(suffix)")
            }
        }
    }

    // MARK: - Fixtures

    /// The stage the flight is drawn on: a rail row at the top and a deck dial row below it.
    private static let flightStage = CGSize(width: 412, height: 320)

    /// A notch for the rendered rail: a 14-inch MacBook Pro's, in the rail's own points.
    private static func notch(scale: CGFloat) -> NotchGeometry? {
        let width: CGFloat = 1_512
        let top = (32 * scale).rounded()
        let notchWidth: CGFloat = 197
        let aux = (width - notchWidth) / 2
        let screen = CGRect(x: 0, y: 0, width: width, height: 982)
        return NotchGeometry.make(
            screen: screen,
            safeTop: top,
            auxLeft: CGRect(x: 0, y: screen.maxY - top, width: aux, height: top),
            auxRight: CGRect(x: aux + notchWidth, y: screen.maxY - top, width: aux, height: top)
        )
    }

    /// Rail boxes in a row at the top of the stage, deck boxes in a row below: the real geometry's shape, without
    /// having to lay a live island out inside `ImageRenderer`.
    private static func pairs(for accounts: [AccountPresentation], edge: ScreenEdge, metrics: IslandMetrics) -> [RingFlightPair] {
        let railDial = metrics.railDial
        let deckDial = metrics.deckDial
        let count = CGFloat(accounts.count)
        let railSpacing = railDial + 46 * metrics.scale
        let deckSpacing = 84 * metrics.scale
        let railStart = (flightStage.width - railSpacing * count) / 2
        let deckStart = (flightStage.width - deckSpacing * count) / 2
        let railY: CGFloat = edge == .top ? 14 : flightStage.height - 14 - railDial
        let deckY: CGFloat = edge == .top ? flightStage.height - 90 : 40
        return accounts.enumerated().map { index, account in
            RingFlightPair(
                id: account.id,
                rail: CGRect(x: railStart + railSpacing * CGFloat(index), y: railY, width: railDial, height: railDial),
                deck: CGRect(
                    x: deckStart + deckSpacing * CGFloat(index) + (deckSpacing - deckDial) / 2,
                    y: deckY,
                    width: deckDial,
                    height: deckDial
                )
            )
        }
    }

    private func render(_ view: some View, name: String, l10n: Localizer) throws {
        let content = view
            .padding(24)
            .background(Color(red: 0.07, green: 0.07, blue: 0.09))
            .environment(\.colorScheme, .dark)
            .environment(\.introAnimationsEnabled, false)
            .environment(\.liveEffectsEnabled, false)
            .environment(\.rendersGlass, false)
            .environment(\.l10n, l10n)
            .environment(\.locale, l10n.locale)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let bitmap = NSBitmapImageRep(cgImage: image)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }

    /// A `Form` cannot be drawn by `ImageRenderer`: the pane is hosted off screen and cached, like the harness does.
    private func renderPane(store: TrackerStore, name: String) async throws {
        let size = NSSize(width: 710, height: 2_200)
        let host = NSHostingView(rootView: SettingsPaneCaptureView(store: store, pane: .presentation).frame(width: size.width, height: size.height))
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
        for _ in 0..<12 {
            try await Task.sleep(for: .milliseconds(50))
            host.layoutSubtreeIfNeeded()
        }
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }

    /// Synthetic accounts with realistic numbers; no real profile ever appears in a render.
    private func makeStore(accounts count: Int, language: LanguagePreference) throws -> TrackerStore {
        let labels = ["Work", "Personal", "Side project", "Research", "Docs"]
        let providers: [ProviderKind] = [.claude, .codex, .claude, .codex, .claude]
        var profiles: [AccountProfile] = []
        for index in 0..<count {
            profiles.append(try AccountProfile(
                id: UIFixture.accountID("island/\(index)"),
                provider: providers[index % providers.count],
                label: try AccountLabel(validating: labels[index % labels.count]),
                directory: try ProfileDirectory(validating: "/Users/me/.profile-\(index)")
            ))
        }
        var settings = try AppSettings(accounts: profiles)
        settings.general.language = language
        settings.appearance.surface = .solid
        settings.appearance.notchFusion = .automatic

        let used: [Double] = [64, 32, 88, 12, 51]
        var statuses: [AccountStatus] = []
        for (index, profile) in profiles.enumerated() {
            let reading = try UsageReading(
                capturedAt: now.addingTimeInterval(-60),
                source: profile.provider == .claude ? .claudeUsageCommand : .codexAppServer,
                buckets: [try LimitBucket(id: "main", title: nil, windows: [
                    try LimitWindow(
                        id: "session",
                        scope: .session,
                        used: try Percentage(validating: used[index % used.count]),
                        duration: .fiveHours,
                        resetsAt: now.addingTimeInterval(8_040)
                    ),
                    try LimitWindow(
                        id: "weekly",
                        scope: .rolling,
                        used: try Percentage(validating: used[(index + 1) % used.count]),
                        duration: .oneWeek,
                        resetsAt: now.addingTimeInterval(240_000)
                    ),
                ], isLimitReached: false)],
                credits: nil
            )
            statuses.append(AccountStatus(profile: profile, reading: reading, nextRefreshAt: now.addingTimeInterval(180)))
        }
        return TrackerStore(
            state: TrackerState(accounts: statuses),
            settings: settings,
            now: now,
            actions: UIFixture.actions(),
            preferredLanguages: { [language == .russian ? "ru-RU" : "en-US"] },
            region: { Locale(identifier: language == .russian ? "ru_RU" : "en_US") }
        )
    }
}
