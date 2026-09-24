import CodometerCore
import CodometerL10n
@testable import CodometerUI
import AppKit
import Foundation
import SwiftUI
import Testing

/// Renders the floating card to PNG files for visual review, in English and Russian. Runs only when
/// `CODOMETER_SNAPSHOT_DIR` is set, e.g.
/// `CODOMETER_SNAPSHOT_DIR=/tmp/shots Scripts/test.sh --filter "Card snapshots"`.
///
/// `ImageRenderer` draws no Liquid Glass, so the glass theme is drawn with its own legibility scrim, which is exactly
/// the surface the contrast tests measure.
@MainActor
@Suite("Card snapshots", .enabled(if: ProcessInfo.processInfo.environment["CODOMETER_SNAPSHOT_DIR"] != nil))
struct CardSnapshotTests {
    private let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODOMETER_SNAPSHOT_DIR"] ?? "/tmp", isDirectory: true)
    private let now = UIFixture.now

    @Test("Every theme and size, with one account and with three, in both languages and both appearances")
    func renderCards() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for language in [LanguagePreference.english, .russian] {
            let single = try makeStore(accounts: 1, language: language)
            let several = try makeStore(accounts: 3, language: language)
            let code = single.localizer.language.rawValue
            for scheme in [ColorScheme.dark, .light] {
                let appearance = scheme == .dark ? "dark" : "light"
                for theme in CardTheme.allCases {
                    for size in CardSize.allCases {
                        for (store, count) in [(single, 1), (several, 3)] {
                            let model = model(store: store, theme: theme, size: size, scheme: scheme, expanded: true)
                            try render(
                                store: store,
                                model: model,
                                name: "card-\(theme.rawValue)-\(size.rawValue)-\(count)acc-\(appearance)-\(code)",
                                scheme: scheme
                            )
                        }
                    }
                    // The minimized pill, with one account and with three.
                    for (store, count) in [(single, 1), (several, 3)] {
                        let model = model(store: store, theme: theme, size: .regular, scheme: scheme, expanded: false)
                        try render(
                            store: store,
                            model: model,
                            name: "card-pill-\(theme.rawValue)-\(count)acc-\(appearance)-\(code)",
                            scheme: scheme
                        )
                    }
                }
            }
        }
    }

    @Test("The states that change the card's words: a limit reached, agents waiting, a vendor outage, stale data")
    func renderStates() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for language in [LanguagePreference.english, .russian] {
            let store = try makeStore(accounts: 3, language: language, variant: true)
            let code = store.localizer.language.rawValue
            var board = ServiceStatusBoard.empty
            board.statuses[.codex] = ServiceStatus(provider: .codex, level: .partialOutage, affectedComponents: ["CLI"], checkedAt: now)
            store.setServiceStatus(board)
            for (index, account) in store.visiblePresentations.enumerated() {
                let model = model(store: store, theme: .graphite, size: .regular, scheme: .dark, expanded: true)
                model.selectedAccountID = account.id
                try render(store: store, model: model, name: "card-state\(index)-\(code)", scheme: .dark)
            }
            // The widest third tile and the coach mark, at the smallest and the largest scale.
            for scale in [0.75, 1.5] {
                store.updateSettings { settings in
                    settings.appearance.scale = (try? IslandScale(scale)) ?? .standard
                    settings.appearance.floatingCard.thirdTile = .agents
                }
                let model = model(store: store, theme: .midnight, size: .regular, scheme: .dark, expanded: true)
                model.showsCoachMark = scale == 1.5
                try render(store: store, model: model, name: "card-scale\(Int(scale * 100))-\(code)", scheme: .dark)
            }
            store.updateSettings { $0.appearance.scale = .standard }
        }
    }

    @Test("The strip in every scope, with one account and with three, at every scale, in both languages")
    func renderStrip() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for language in [LanguagePreference.english, .russian] {
            let single = try makeStore(accounts: 1, language: language)
            let several = try makeStore(accounts: 3, language: language, variant: true)
            let code = single.localizer.language.rawValue
            for scope in CardStripScope.allCases {
                for (store, count) in [(single, 1), (several, 3)] {
                    store.updateSettings { $0.appearance.floatingCard.stripScope = scope }
                    let model = model(store: store, theme: .graphite, size: .strip, scheme: .dark, expanded: true)
                    try render(store: store, model: model, name: "strip-\(scope.rawValue)-\(count)acc-\(code)", scheme: .dark)
                }
            }
            for theme in CardTheme.allCases where theme != .graphite {
                several.updateSettings { $0.appearance.floatingCard.stripScope = .allAccounts }
                let scheme: ColorScheme = theme == .light ? .light : .dark
                let model = model(store: several, theme: theme, size: .strip, scheme: scheme, expanded: true)
                try render(store: several, model: model, name: "strip-\(theme.rawValue)-\(code)", scheme: scheme)
            }
            for scale in [0.75, 1.5] {
                several.updateSettings { settings in
                    settings.appearance.scale = (try? IslandScale(scale)) ?? .standard
                    settings.appearance.floatingCard.stripScope = .claude
                }
                let model = model(store: several, theme: .graphite, size: .strip, scheme: .dark, expanded: true)
                try render(store: several, model: model, name: "strip-scale\(Int(scale * 100))-\(code)", scheme: .dark)
            }
            several.updateSettings { $0.appearance.scale = .standard }
        }
    }

    @Test("The card's settings rows and its stage preview, at the Settings window's default and narrowest widths")
    func renderSettings() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (language, region) in [(LanguagePreference.english, "en_US"), (.russian, "ru_RU")] {
            let store = try makeStore(accounts: 3, language: language, region: Locale(identifier: region))
            let code = store.localizer.language.rawValue
            for (width, suffix) in [(710.0 as CGFloat, ""), (550.0 as CGFloat, "-narrow")] {
                try await renderForm(
                    store: store,
                    width: width,
                    name: "settings-card-rows\(suffix)-\(code)"
                ) {
                    Form {
                        CardSettingsSection(store: store)
                    }
                    .formStyle(.grouped)
                }
                try await renderForm(store: store, width: width, name: "settings-card-stage\(suffix)-\(code)") {
                    CardStage(store: store)
                }
            }
            // The strip swaps the third-tile row for its scope picker, and the stage shows the strip itself.
            store.updateSettings { $0.appearance.floatingCard.size = .strip }
            try await renderForm(store: store, width: 710, name: "settings-card-rows-strip-\(code)") {
                Form {
                    CardSettingsSection(store: store)
                }
                .formStyle(.grouped)
            }
            try await renderForm(store: store, width: 710, name: "settings-card-stage-strip-\(code)") {
                CardStage(store: store)
            }
        }
    }

    /// Forms and the stage lay out over a few runloop turns and `ImageRenderer` cannot draw a `Form`, so they are
    /// hosted off screen and drawn with `cacheDisplay`, like the other settings renders.
    private func renderForm(
        store: TrackerStore,
        width: CGFloat,
        name: String,
        @ViewBuilder content: () -> some View
    ) async throws {
        let size = NSSize(width: width, height: 620)
        let root = content()
            .environment(\.l10n, store.localizer)
            .environment(\.locale, store.localizer.locale)
            .environment(\.liveEffectsEnabled, false)
            .environment(\.rendersGlass, false)
            .frame(width: size.width, height: size.height)
        let host = NSHostingView(rootView: root)
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

    // MARK: - Helpers

    private func model(
        store: TrackerStore,
        theme: CardTheme,
        size: CardSize,
        scheme: ColorScheme,
        expanded: Bool
    ) -> FloatingCardModel {
        let metrics = CardMetrics(store.settings.appearance.scale)
        let model = FloatingCardModel()
        model.metrics = metrics
        model.size = size
        model.anchor = .topTrailing
        model.thirdTile = store.settings.appearance.floatingCard.thirdTile
        model.stripScope = store.settings.appearance.floatingCard.stripScope
        model.isExpanded = expanded
        model.theme = CardThemeTokens.resolve(theme: theme, scheme: scheme, reducesTransparency: false, increasesContrast: false)
        model.selectedAccountID = CardAccountSelector.mostUrgent(store.visiblePresentations)?.id
        let card = CGRect(origin: CGPoint(x: metrics.windowMargin, y: metrics.windowMargin), size: metrics.cardSize(size))
        let pillSize = metrics.pillSize(accounts: store.visiblePresentations.count, templates: CardPillTemplates.everyLanguage)
        model.cardFrame = card
        // Both forms share the top-trailing corner, in the view's own top-left coordinates.
        model.pillFrame = CGRect(x: card.maxX - pillSize.width, y: card.minY, width: pillSize.width, height: pillSize.height)
        return model
    }

    private func render(store: TrackerStore, model: FloatingCardModel, name: String, scheme: ColorScheme) throws {
        let margin = model.metrics.windowMargin
        let canvas = CGSize(width: model.cardFrame.width + margin * 2, height: model.cardFrame.height + margin * 2)
        let content = FloatingCardRootView(store: store, model: model)
            .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
            .background(backdrop(scheme: scheme))
            .environment(\.colorScheme, scheme)
            .environment(\.l10n, store.localizer)
            .environment(\.locale, store.localizer.locale)
            .environment(\.introAnimationsEnabled, false)
            .environment(\.liveEffectsEnabled, false)
            .environment(\.rendersGlass, false)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try #require(renderer.cgImage, "\(name) did not render")
        let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }

    /// A busy desktop under the card, so a theme that is too transparent shows up at once.
    private func backdrop(scheme: ColorScheme) -> some View {
        LinearGradient(
            colors: scheme == .dark
                ? [Color(red: 0.10, green: 0.12, blue: 0.22), Color(red: 0.42, green: 0.18, blue: 0.30)]
                : [Color(red: 0.98, green: 0.86, blue: 0.62), Color(red: 0.52, green: 0.78, blue: 0.94)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func makeStore(
        accounts count: Int,
        language: LanguagePreference,
        variant: Bool = false,
        region: Locale? = nil
    ) throws -> TrackerStore {
        let labels = ["Work", "Personal", "Side project"]
        let providers: [ProviderKind] = [.claude, .claude, .codex]
        var profiles: [AccountProfile] = []
        var statuses: [AccountStatus] = []
        for index in 0..<count {
            let profile = try AccountProfile(
                id: UIFixture.accountID("card/\(index)"),
                provider: providers[index % providers.count],
                label: try AccountLabel(validating: labels[index % labels.count]),
                directory: try ProfileDirectory(validating: "/Users/example/.profile-\(index)"),
                tint: [AccountTint.teal, .pink, .sky][index % 3],
                monogram: try AccountMonogram(validating: String(labels[index % labels.count].prefix(1)))
            )
            profiles.append(profile)
            statuses.append(try status(profile: profile, index: index, variant: variant))
        }
        var settings = try AppSettings(accounts: profiles)
        settings.general.language = language
        let store = TrackerStore(
            state: TrackerState(accounts: statuses),
            settings: settings,
            now: now,
            actions: UIFixture.actions(),
            region: { region ?? (language == .russian ? Locale(identifier: "ru_RU") : Locale(identifier: "en_US")) }
        )
        store.refreshLocale()
        return store
    }

    private func status(profile: AccountProfile, index: Int, variant: Bool) throws -> AccountStatus {
        // 0: healthy, 1: waiting agents, 2: blocked and stale — the three states the card's pill has to tell apart.
        let blocked = variant && index == 2
        let windows: [LimitWindow] = profile.provider == .claude
            ? [
                try UIFixture.window("session", .session, used: 42 + Double(index) * 7, duration: .fiveHours, resetsIn: 7_200),
                try UIFixture.window("week", .weekly(model: nil), used: blocked ? 100 : 64 - Double(index) * 9, duration: .oneWeek, resetsIn: 5 * 86_400 + 16 * 3_600),
                try UIFixture.window("week.opus", .weekly(model: "Opus"), used: 51, duration: .oneWeek, resetsIn: 5 * 86_400),
            ]
            : [
                try UIFixture.window("primary", .rolling, used: blocked ? 100 : 34, duration: .fiveHours, resetsIn: 2 * 3_600 + 5 * 60),
                try UIFixture.window("secondary", .rolling, used: 57, duration: .oneWeek, resetsIn: 2 * 86_400),
            ]
        let sessions = variant && index == 1
            ? [try UIFixture.session("a", .waiting), try UIFixture.session("b", .working)]
            : []
        return AccountStatus(
            profile: profile,
            identity: AccountIdentity(email: "user\(index)@example.com", organization: nil, plan: profile.provider == .claude ? "max_20x" : "plus"),
            reading: try UIFixture.reading(
                [try UIFixture.bucket("main", windows, limitReached: blocked)],
                capturedAgo: blocked ? 3_600 : 60
            ),
            sessions: sessions
        )
    }
}
