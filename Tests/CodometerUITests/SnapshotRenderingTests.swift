import CodometerCore
import CodometerL10n
@testable import CodometerUI
import AppKit
import Foundation
import SwiftUI
import Testing

/// Renders the island's views with realistic data to PNG files for visual review, in English and Russian (`…-en.png`,
/// `…-ru.png`). Runs only when `CODOMETER_SNAPSHOT_DIR` is set, e.g.
/// `CODOMETER_SNAPSHOT_DIR=/tmp/shots Scripts/test.sh --filter Snapshot`.
///
/// `ImageRenderer` draws neither Liquid Glass nor scroll views, so surfaces get a material fallback here.
@MainActor
@Suite("Snapshots", .enabled(if: ProcessInfo.processInfo.environment["CODOMETER_SNAPSHOT_DIR"] != nil))
struct SnapshotRenderingTests {
    private let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODOMETER_SNAPSHOT_DIR"] ?? "/tmp", isDirectory: true)
    private let now = Date(timeIntervalSince1970: 1_789_590_000)

    @Test("Deck overview, rails and popover in light and dark appearance, in both languages", arguments: [LanguagePreference.english, .russian])
    func renderIsland(language: LanguagePreference) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try await makeStore(language: language)
        for scheme in [ColorScheme.light, .dark] {
            let suffix = "\(scheme == .dark ? "dark" : "light")-\(store.localizer.language.rawValue)"
            let horizontal = model(edge: .top, anchor: .top, style: .floating)
            let vertical = model(edge: .right, anchor: .topTrailing, style: .floating)
            let deck = model(edge: .top, anchor: .top, style: .floating)

            try render(
                RailView(store: store, model: horizontal, accounts: store.presentations)
                    .background(Capsule().fill(.regularMaterial)),
                name: "rail-horizontal-\(suffix)",
                scheme: scheme,
                l10n: store.localizer
            )
            try render(
                RailView(store: store, model: vertical, accounts: store.presentations)
                    .background(Capsule().fill(.regularMaterial)),
                name: "rail-vertical-\(suffix)",
                scheme: scheme,
                l10n: store.localizer
            )
            try render(deckView(store: store, model: deck), name: "deck-claude-\(suffix)", scheme: scheme, l10n: store.localizer)

            let attached = model(edge: .top, anchor: .top, style: .attached)
            try render(
                RailView(store: store, model: attached, accounts: store.presentations)
                    .modifier(IslandSurfaceModifier(surface: .solid, shape: IslandRootView.silhouette(layout: attached.layout, expanded: false))),
                name: "rail-attached-solid-\(suffix)",
                scheme: scheme,
                l10n: store.localizer
            )
            try render(
                DeckContent(store: store, model: attached, accounts: store.presentations, context: .island)
                    .background(IslandRootView.silhouette(layout: attached.layout, expanded: true).fill(Color.black.opacity(0.72)))
                    .environment(\.colorScheme, .dark),
                name: "deck-attached-dark-\(suffix)",
                scheme: scheme,
                l10n: store.localizer
            )

            deck.selectedAccountID = store.presentations.last?.id
            try render(deckView(store: store, model: deck), name: "deck-codex-\(suffix)", scheme: scheme, l10n: store.localizer)

            try render(
                // Uncapped: `ImageRenderer` cannot draw the scroll view a screen-height cap adds.
                StatusPopoverView(store: store, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.regularMaterial)),
                name: "popover-\(suffix)",
                scheme: scheme,
                l10n: store.localizer
            )

            let small = model(edge: .top, anchor: .top, style: .floating, scale: 0.85)
            try render(deckView(store: store, model: small), name: "deck-scale085-\(suffix)", scheme: scheme, l10n: store.localizer)
        }
    }

    @Test("Deck with groups, a masked e-mail, stale and blocked accounts, in both languages", arguments: [LanguagePreference.english, .russian])
    func renderVariants(language: LanguagePreference) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try await makeStore(variant: true, language: language)
        for scheme in [ColorScheme.light, .dark] {
            let suffix = "\(scheme == .dark ? "dark" : "light")-\(store.localizer.language.rawValue)"
            let deck = model(edge: .top, anchor: .top, style: .floating)
            try render(deckView(store: store, model: deck), name: "deck-groups-\(suffix)", scheme: scheme, l10n: store.localizer)
            deck.selectedAccountID = store.presentations.last?.id
            try render(deckView(store: store, model: deck), name: "deck-blocked-\(suffix)", scheme: scheme, l10n: store.localizer)
        }
    }

    @Test("The widest deck texts: a pace pill with a date, the Codex hedge, overflows and a limit-reached bucket, in both languages", arguments: [LanguagePreference.english, .russian])
    func renderExtremes(language: LanguagePreference) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try makeExtremesStore(language: language)
        let suffix = "light-\(store.localizer.language.rawValue)"
        let deck = model(edge: .top, anchor: .top, style: .floating)
        deck.selectedAccountID = store.presentations.first?.id
        try render(deckView(store: store, model: deck), name: "deck-extremes-\(suffix)", scheme: .light, l10n: store.localizer)
        // The smallest common scale: the shorter pace and status wordings take over.
        let small = model(edge: .top, anchor: .top, style: .floating, scale: 0.85)
        small.selectedAccountID = store.presentations.first?.id
        try render(deckView(store: store, model: small), name: "deck-extremes-scale085-\(suffix)", scheme: .light, l10n: store.localizer)
        deck.selectedAccountID = store.presentations.last?.id
        try render(deckView(store: store, model: deck), name: "deck-extremes-blocked-\(suffix)", scheme: .light, l10n: store.localizer)
        let rail = model(edge: .top, anchor: .top, style: .floating)
        try render(
            RailView(store: store, model: rail, accounts: store.presentations)
                .background(Capsule().fill(.regularMaterial)),
            name: "rail-extremes-\(suffix)",
            scheme: .light,
            l10n: store.localizer
        )
    }

    /// Codex runs out tomorrow at this pace, cannot find its CLI, has a limit-reached model bucket, six sessions and five
    /// agents waiting (long Codex prompts among them); a second account is blocked without a known reset.
    private func makeExtremesStore(language: LanguagePreference) throws -> TrackerStore {
        let codex = try AccountProfile(
            id: UIFixture.accountID("extremes/codex"),
            provider: .codex,
            label: try AccountLabel(validating: "Personal side projects"),
            directory: try ProfileDirectory(validating: "/Users/me/.codex")
        )
        let claude = try AccountProfile(
            id: UIFixture.accountID("extremes/claude"),
            provider: .claude,
            label: try AccountLabel(validating: "Work"),
            directory: try ProfileDirectory(validating: "/Users/me/.claude")
        )
        var settings = try AppSettings(accounts: [codex, claude])
        settings.general.language = language
        let codexReading = try UsageReading(
            capturedAt: now.addingTimeInterval(-30),
            source: .codexAppServer,
            buckets: [
                try LimitBucket(id: "codex", title: nil, windows: [
                    try window("primary", .rolling, 73.5, .oneWeek, resetsIn: 4 * 86_400),
                ], isLimitReached: false),
                try LimitBucket(id: "codex_bengalfox", title: "GPT-5.3-Codex-Spark", windows: [
                    try window("primary", .rolling, 100, .fiveHours, resetsIn: 3 * 3_600),
                    try window("secondary", .rolling, 100, .oneWeek, resetsIn: 5 * 86_400),
                ], isLimitReached: true),
            ],
            credits: CreditsInfo(hasCredits: true, isUnlimited: false, balance: 1_250)
        )
        let claudeReading = try UsageReading(
            capturedAt: now.addingTimeInterval(-50 * 60),
            source: .claudeUsageCommand,
            buckets: [try LimitBucket(id: "claude", title: nil, windows: [
                try LimitWindow(id: "session", scope: .session, used: try Percentage(validating: 100), duration: .fiveHours, resetsAt: nil),
            ], isLimitReached: true)],
            credits: nil
        )
        let turn = try TurnTiming(startedAt: now.addingTimeInterval(-4_000), endedAt: now.addingTimeInterval(-100), duration: 3_899, firstTokenLatency: 12.3, wasAborted: true)
        var sessions: [AgentSession] = []
        for index in 0..<6 {
            let waits = index < 4
            let since: TimeInterval = 23 * 3_600 + 59 * 60 + Double(index)
            sessions.append(try AgentSession(
                id: "s\(index)",
                title: "service-with-a-long-name-\(index)",
                projectPath: "/Users/me/service-\(index)",
                activity: waits ? .waiting : .working,
                detail: waits ? "permission prompt" : nil,
                activitySince: now.addingTimeInterval(-since),
                processID: Int32(index + 1),
                lastTurn: turn
            ))
        }
        let claudeWaiting = try AgentSession(
            id: "w", title: "docs", projectPath: "/Users/me/docs", activity: .waiting, detail: "input needed",
            activitySince: now.addingTimeInterval(-600), processID: 9
        )
        let state = TrackerState(accounts: [
            AccountStatus(
                profile: codex,
                identity: AccountIdentity(email: "a.very.long.address@example-company.com", organization: nil, plan: "Pro"),
                reading: codexReading,
                // The longest issue title there is.
                issue: TrackerIssue(kind: .executableMissing, detail: "codex: no such file or directory", occurredAt: now.addingTimeInterval(-60)),
                nextRefreshAt: now.addingTimeInterval(59 * 60),
                sessions: sessions
            ),
            AccountStatus(
                profile: claude,
                identity: AccountIdentity(email: "me@example.com", organization: nil, plan: "Max 20x"),
                reading: claudeReading,
                nextRefreshAt: now.addingTimeInterval(150),
                sessions: [claudeWaiting]
            ),
        ])
        let region = Locale(identifier: language == .russian ? "ru_RU" : "en_US")
        return TrackerStore(state: state, settings: settings, now: now, actions: UIFixture.actions(), preferredLanguages: { ["en-US"] }, region: { region })
    }

    @Test("Ring grammar at rail, settings and deck sizes")
    func renderRings() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try await makeStore()
        let accounts = store.presentations
        for scheme in [ColorScheme.light, .dark] {
            let suffix = scheme == .dark ? "dark" : "light"
            let row = HStack(spacing: 18) {
                ForEach(accounts) { account in
                    RingGauge(presentation: account, diameter: 28, showsSecondary: false)
                    RingGauge(presentation: account, diameter: 46, showsSecondary: true)
                    RingGauge(presentation: account, diameter: 58, showsSecondary: true, orbitMargin: 4)
                    RingGauge(presentation: account, diameter: 116, showsSecondary: true, orbitMargin: 8)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.regularMaterial))
            try render(row, name: "rings-\(suffix)", scheme: scheme)
        }
    }

    @Test("Core Animation orbit layers at rest")
    func renderOrbitLayers() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let side: CGFloat = 132
        let working = ActivityLayerView(frame: CGRect(x: 0, y: 0, width: side, height: side))
        working.apply(activity: .working, style: .orbit, contractedRadius: side / 2)
        let waiting = ActivityLayerView(frame: CGRect(x: 0, y: 0, width: side, height: side))
        waiting.apply(activity: .waiting, style: .orbit, contractedRadius: side / 2)
        let views: [LiveLayerView] = [working, waiting]
        let context = try #require(CGContext(
            data: nil,
            width: Int(side) * 2 * views.count,
            height: Int(side) * 2,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(srgbRed: 0.93, green: 0.92, blue: 0.96, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
        context.scaleBy(x: 2, y: 2)
        for (index, view) in views.enumerated() {
            view.appearance = NSAppearance(named: .aqua)
            view.configure(radius: 58, lineWidth: 8)
            view.layout()
            let layer = try #require(view.layer)
            context.saveGState()
            context.translateBy(x: CGFloat(index) * side, y: 0)
            layer.render(in: context)
            context.restoreGState()
        }
        let image = try #require(context.makeImage())
        let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("orbit-layers.png"))
    }

    // MARK: - Rendering

    private func model(edge: ScreenEdge, anchor: IslandAnchor, style: IslandStyle, scale: CGFloat = 1) -> IslandModel {
        IslandModel(layout: IslandLayout(edge: edge, anchor: anchor, style: style, metrics: IslandMetrics(scale: scale)))
    }

    private func deckView(store: TrackerStore, model: IslandModel) -> some View {
        DeckContent(store: store, model: model, accounts: store.presentations, context: .island)
            .background(RoundedRectangle(cornerRadius: model.layout.metrics.deckCorner, style: .continuous).fill(.regularMaterial))
    }

    private func render(_ view: some View, name: String, scheme: ColorScheme, l10n: Localizer = .testEnglish) throws {
        let content = view
            .padding(36)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.98, green: 0.55, blue: 0.40), Color(red: 0.55, green: 0.33, blue: 0.86), Color(red: 0.16, green: 0.50, blue: 0.92)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .environment(\.colorScheme, scheme)
            .environment(\.introAnimationsEnabled, false)
            .environment(\.liveEffectsEnabled, false)
            .environment(\.rendersGlass, false)
            // What `IslandRootView` and `StatusPopoverView` inject in the app.
            .environment(\.l10n, l10n)
            .environment(\.locale, l10n.locale)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let bitmap = NSBitmapImageRep(cgImage: image)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }

    // MARK: - Fixtures

    /// - Parameter language: The store's language, with a region that speaks it (en_US, ru_RU).
    private func makeStore(variant: Bool = false, language: LanguagePreference = .english) async throws -> TrackerStore {
        let work = AccountGroup(name: try AccountLabel(validating: "Работа"))
        let personal = AccountGroup(name: try AccountLabel(validating: "Личное"))
        let claude = try AccountProfile(
            id: UIFixture.accountID("render/claude"),
            provider: .claude,
            label: try AccountLabel(validating: "Claude"),
            directory: try ProfileDirectory(validating: "/Users/me/.claude"),
            groupID: variant ? work.id : nil
        )
        let codex = try AccountProfile(
            id: UIFixture.accountID("render/codex"),
            provider: .codex,
            label: try AccountLabel(validating: "Codex"),
            directory: try ProfileDirectory(validating: "/Users/me/.codex"),
            groupID: variant ? personal.id : nil
        )
        var settings = try AppSettings(accounts: [claude, codex], groups: variant ? [work, personal] : [])
        settings.general.language = language
        if variant {
            settings.appearance.emailVisibility = .masked
        }

        let claudeReading = try UsageReading(
            capturedAt: now.addingTimeInterval(variant ? -40 * 60 : -120),
            source: .claudeUsageCommand,
            buckets: [try LimitBucket(id: "claude", title: nil, windows: [
                try window("session", .session, 7, .fiveHours, resetsIn: 4 * 3_600 + 10 * 60),
                try window("week", .weekly(model: nil), 38, .oneWeek, resetsIn: 4 * 86_400 + 3 * 3_600),
                try window("week.fable", .weekly(model: "Fable"), 63, .oneWeek, resetsIn: 4 * 86_400 + 3 * 3_600),
            ], isLimitReached: false)],
            credits: nil
        )
        let codexReading = try UsageReading(
            capturedAt: now.addingTimeInterval(-30),
            source: .codexAppServer,
            buckets: [
                // The variant looks like a real Codex account: a 5-hour window and an exhausted week.
                try LimitBucket(id: "codex", title: nil, windows: variant ? [
                    try window("primary", .rolling, 34, .fiveHours, resetsIn: 2 * 3_600 + 5 * 60),
                    try window("secondary", .rolling, 100, .oneWeek, resetsIn: 2 * 86_400 + 12 * 3_600),
                ] : [
                    try window("primary", .rolling, 99, .oneWeek, resetsIn: 2 * 86_400 + 12 * 3_600),
                ], isLimitReached: variant),
                try LimitBucket(id: "codex_bengalfox", title: "GPT-5.3-Codex-Spark", windows: [
                    try window("primary", .rolling, 12, .fiveHours, resetsIn: 3 * 3_600),
                    try window("secondary", .rolling, 3, .oneWeek, resetsIn: 5 * 86_400),
                ], isLimitReached: false),
            ],
            credits: CreditsInfo(hasCredits: true, isUnlimited: false, balance: 125)
        )
        let turn = try TurnTiming(
            startedAt: now.addingTimeInterval(-900),
            endedAt: now.addingTimeInterval(-648),
            duration: 252,
            firstTokenLatency: 2.8,
            wasAborted: false
        )
        let working = try AgentSession(
            id: "a",
            title: "Codometer",
            projectPath: "/Users/me/Codometer",
            activity: .working,
            detail: nil,
            activitySince: now.addingTimeInterval(-420),
            processID: 1,
            origin: .terminal,
            lastTurn: turn,
            lastEventAt: now.addingTimeInterval(-20)
        )
        let waiting = try AgentSession(
            id: "b",
            title: "exchanger-api",
            projectPath: "/Users/me/api",
            activity: .waiting,
            detail: "permission prompt",
            activitySince: now.addingTimeInterval(-65),
            processID: 2
        )
        let codexWorking = try AgentSession(
            id: "c",
            title: "wallet-service",
            projectPath: "/Users/me/wallet",
            activity: .working,
            detail: nil,
            activitySince: now.addingTimeInterval(-31 * 60),
            processID: 3,
            lastEventAt: now.addingTimeInterval(-9 * 60)
        )

        let state = TrackerState(accounts: [
            AccountStatus(
                profile: claude,
                identity: AccountIdentity(email: "example@test.com", organization: nil, plan: "Max 20x"),
                reading: claudeReading,
                // The stale variant also shows why: the last refresh timed out.
                issue: variant ? TrackerIssue(kind: .timedOut, detail: "claude /usage did not respond within 60 s", occurredAt: now.addingTimeInterval(-60)) : nil,
                nextRefreshAt: now.addingTimeInterval(180),
                sessions: [working, waiting]
            ),
            AccountStatus(
                profile: codex,
                identity: AccountIdentity(email: "me@example.com", organization: nil, plan: "Pro"),
                reading: codexReading,
                nextRefreshAt: now.addingTimeInterval(150),
                sessions: variant ? [codexWorking] : []
            ),
        ])
        let now = now
        let actions = TrackerActions(
            refresh: { _ in },
            persistSettings: { _ in },
            discoverProfiles: { [] },
            revealDataFolder: {},
            setLaunchAtLogin: { _ in nil },
            openSettings: {},
            quit: {},
            loadWindowHistory: { account, bucket, window, since in
                let used = state.account(account)?.reading?.bucket(id: bucket)?.window(id: window)?.used.value
                return used.flatMap { Self.history(account: account, bucket: bucket, window: window, final: $0, since: since, now: now) }
            }
        )
        let region = Locale(identifier: language == .russian ? "ru_RU" : "en_US")
        let store = TrackerStore(state: state, settings: settings, now: now, actions: actions, preferredLanguages: { ["en-US"] }, region: { region })
        await loadHeroHistory(into: store)
        return store
    }

    /// A plausible usage curve for the hero windows: slow, then a burst of work.
    private static func history(account: AccountID, bucket: String, window: String, final: Double, since: Date, now: Date) -> HistorySeries {
        let span = now.timeIntervalSince(since)
        let points = (0...24).compactMap { step -> UsagePoint? in
            let progress = Double(step) / 24
            let shaped = pow(progress, 1.8) * 0.85 + progress * 0.15
            return try? UsagePoint(at: since.addingTimeInterval(span * progress), used: final * shaped)
        }
        return HistorySeries(accountID: account, bucketID: bucket, windowID: window, points: points, resets: [])
    }

    /// Requests and waits for every account's hero history, as a visible deck would.
    private func loadHeroHistory(into store: TrackerStore) async {
        for account in store.presentations {
            guard let hero = DeckLayout.windowSections(windows: account.windows, primaryWindowID: account.headline?.primary.id).hero,
                  let since = DeckLayout.historySince(window: hero.window, now: now)
            else { continue }
            store.analytics.requestSeries(account: account.id, bucket: hero.bucketID, window: hero.window.id, since: since)
        }
        await store.analytics.settle()
    }

    private func window(_ id: String, _ scope: LimitWindowScope, _ used: Double, _ duration: WindowDuration, resetsIn: TimeInterval) throws -> LimitWindow {
        try LimitWindow(id: id, scope: scope, used: try Percentage(validating: used), duration: duration, resetsAt: now.addingTimeInterval(resetsIn))
    }
}

// MARK: - Pure layout and design-system helpers (always run)

@Suite("Palette")
struct PaletteTests {
    @Test("Band text colours stay readable on light and dark glass", arguments: UsageBand.allCases)
    func bandTextContrast(band: UsageBand) {
        let colour = Palette.bandText(band)
        #expect(colour.light.contrast(with: Palette.lightGlass) >= 4.5)
        #expect(colour.dark.contrast(with: Palette.darkGlass) >= 4.5)
    }

    @Test("Attention text is readable and the attention colour means only one thing")
    func attentionIsDistinct() {
        #expect(Palette.attentionText.light.contrast(with: Palette.lightGlass) >= 4.5)
        #expect(Palette.attentionText.dark.contrast(with: Palette.darkGlass) >= 4.5)
        for band in UsageBand.allCases {
            let stops = Palette.bandGradient(band)
            #expect(Palette.attention.hueDistance(to: stops.end) >= 40, "attention too close to \(band)")
        }
        #expect(Palette.attention.hueDistance(to: Palette.accent(.codex)) >= 40)
        #expect(Palette.attention.hueDistance(to: Palette.accent(.claude)) >= 40)
    }

    @Test("Colour maths")
    func colourMaths() {
        let white = Palette.RGB(1, 1, 1)
        let black = Palette.RGB(0, 0, 0)
        #expect(abs(white.contrast(with: black) - 21) < 0.01)
        #expect(abs(white.contrast(with: white) - 1) < 0.001)
        #expect(Palette.RGB(2, -1, 0.5) == Palette.RGB(1, 0, 0.5))
        #expect(abs(Palette.RGB(1, 0, 0).hue) < 0.001)
        #expect(abs(Palette.RGB(0, 1, 0).hue - 120) < 0.001)
        #expect(abs(Palette.RGB(0, 0, 1).hue - 240) < 0.001)
        #expect(abs(Palette.RGB(1, 0, 0).hueDistance(to: Palette.RGB(1, 0, 0.1)) - 6) < 0.001)
    }

    @Test("Small text sizes keep their floors at the smallest scale")
    func textFloors() {
        let smallest = IslandMetrics(scale: CGFloat(IslandScale.allowedRange.lowerBound))
        #expect(smallest.textSize(TextSize.badge) >= 11)
        #expect(smallest.textSize(TextSize.caption) >= 11.5)
        #expect(smallest.textSize(TextSize.body) >= 12)
        #expect(IslandMetrics(scale: 1).textSize(TextSize.hero) == 34)
        let metrics = IslandMetrics(scale: 1.5)
        #expect(metrics.cardCorner == 21)
        #expect(metrics.tileCorner == 24)
    }
}

@MainActor
@Suite("Deck layout")
struct DeckLayoutTests {
    private let now = UIFixture.now

    private func presentation(_ windows: [(String, String?, Bool, LimitWindow)]) -> [WindowPresentation] {
        windows.map { bucket, title, isMain, window in
            WindowPresentation(bucketID: bucket, bucketTitle: title, isMainBucket: isMain, window: window, appearance: AppearanceSettings(), now: now, l10n: .testRussian)
        }
    }

    @Test("Hero is the headline primary window; tiles hold every other reported window")
    func sections() throws {
        let claude = presentation([
            ("claude", nil, true, try UIFixture.window("session", .session, used: 7)),
            ("claude", nil, true, try UIFixture.window("week", .weekly(model: nil), used: 38, duration: .oneWeek)),
            ("claude", nil, true, try UIFixture.window("week.fable", .weekly(model: "Fable"), used: 63, duration: .oneWeek)),
        ])
        let layout = DeckLayout.windowSections(windows: claude, primaryWindowID: "session")
        #expect(layout.hero?.window.id == "session")
        #expect(layout.sections.count == 1)
        #expect(layout.sections[0].title == nil)
        #expect(layout.sections[0].tiles.map(\.title) == ["Неделя · все модели", "Неделя · Fable"])

        let codex = presentation([
            ("codex", nil, true, try UIFixture.window("primary", used: 99, duration: .oneWeek)),
            ("spark", "GPT-5.3-Codex-Spark", false, try UIFixture.window("primary", used: 12)),
            ("spark", "GPT-5.3-Codex-Spark", false, try UIFixture.window("secondary", used: 3, duration: .oneWeek)),
            ("mini", nil, false, try UIFixture.window("primary", used: 1)),
        ])
        let codexLayout = DeckLayout.windowSections(windows: codex, primaryWindowID: "primary", limitReachedBuckets: ["spark"])
        #expect(codexLayout.hero?.id == "codex/primary")
        #expect(codexLayout.sections.map(\.id) == ["spark", "mini"])
        #expect(codexLayout.sections[0].title == "GPT-5.3-Codex-Spark")
        #expect(codexLayout.sections[0].isLimitReached)
        #expect(codexLayout.sections[0].tiles.count == 2)
        #expect(codexLayout.sections[1].title == "mini")

        let empty = DeckLayout.windowSections(windows: [], primaryWindowID: nil)
        #expect(empty.hero == nil && empty.sections.isEmpty)
    }

    @Test("Rows of two")
    func rows() {
        #expect(DeckLayout.rows([1, 2, 3]) == [[1, 2], [3]])
        #expect(DeckLayout.rows([1, 2]) == [[1, 2]])
        #expect(DeckLayout.rows([Int]()).isEmpty)
        #expect(DeckLayout.rows([1, 2, 3], columns: 0) == [[1], [2], [3]])
    }

    @Test("Numbers and dial captions")
    func numbers() throws {
        #expect(DeckLayout.remainingPercent(try Percentage(validating: 37.6)) == 62)
        #expect(DeckLayout.remainingPercent(try Percentage(validating: 120)) == 0)
        let exhausted = try UIFixture.window("session", .session, used: 100, resetsIn: 2 * 3_600 + 14 * 60)
        #expect(DeckLayout.dialCaption(primary: exhausted, blocking: exhausted, now: now, l10n: .testRussian) == ("2:14", true))
        let unknownReset = try UIFixture.window("session", .session, used: 100, resetsIn: nil)
        #expect(DeckLayout.dialCaption(primary: unknownReset, blocking: unknownReset, now: now, l10n: .testRussian) == ("100%", false))
        let session = try UIFixture.window("s", used: 7)
        #expect(DeckLayout.dialCaption(primary: session, blocking: nil, now: now, l10n: .testRussian) == ("7%", false))
        // Blocked by the week while the session window is fine: the countdown still wins.
        let week = try UIFixture.window("week", .weekly(model: nil), used: 100, duration: .oneWeek, resetsIn: 40 * 60)
        #expect(DeckLayout.dialCaption(primary: session, blocking: week, now: now, l10n: .testRussian) == ("40м", true))
        #expect(DeckLayout.dialCaption(primary: nil, blocking: nil, now: now, l10n: .testRussian) == ("—", false))
    }

    @Test("History starts at the window start, or a stable rounded time")
    func historySince() throws {
        let known = try UIFixture.window("session", .session, used: 7, duration: .fiveHours, resetsIn: 3_600)
        #expect(DeckLayout.historySince(window: known, now: now) == now.addingTimeInterval(3_600 - 5 * 3_600))
        let noReset = try UIFixture.window("session", .session, used: 7, duration: .fiveHours, resetsIn: nil)
        let first = try #require(DeckLayout.historySince(window: noReset, now: now))
        #expect(first <= now.addingTimeInterval(-5 * 3_600))
        #expect(first > now.addingTimeInterval(-5 * 3_600 - DeckLayout.historyRoundingStep))
        #expect(first.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: DeckLayout.historyRoundingStep) == 0)
        // A clock tick within the same step does not move the request.
        let start = first.addingTimeInterval(5 * 3_600)
        #expect(DeckLayout.historySince(window: noReset, now: start.addingTimeInterval(1)) == first)
        #expect(DeckLayout.historySince(window: noReset, now: start.addingTimeInterval(DeckLayout.historyRoundingStep - 1)) == first)
        let noDuration = try UIFixture.window("x", used: 7, duration: nil, resetsIn: nil)
        #expect(DeckLayout.historySince(window: noDuration, now: now) == nil)
    }

    @Test("Group filter options, filtering and selection")
    func groups() throws {
        let work = try UIFixture.group("Работа")
        let home = try UIFixture.group("Личное")
        #expect(DeckLayout.filterOptions(groups: [], l10n: .testRussian).isEmpty)
        #expect(DeckLayout.filterOptions(groups: [work, home], l10n: .testRussian).map(\.title) == ["Все", "Работа", "Личное"])
        // Group names are the user's own and stay as typed in every language.
        #expect(DeckLayout.filterOptions(groups: [work, home], l10n: .testEnglish).map(\.title) == ["All", "Работа", "Личное"])
        #expect(DeckLayout.filterOptions(groups: [work, home], l10n: .testRussian).map(\.id) == [nil, work.id, home.id])

        let a = AccountPresentation(status: AccountStatus(profile: try UIFixture.profile("A", group: work)), appearance: AppearanceSettings(), now: now, l10n: .testRussian)
        let b = AccountPresentation(status: AccountStatus(profile: try UIFixture.profile("B", group: home)), appearance: AppearanceSettings(), now: now, l10n: .testRussian)
        let c = AccountPresentation(status: AccountStatus(profile: try UIFixture.profile("C")), appearance: AppearanceSettings(), now: now, l10n: .testRussian)
        let all = [a, b, c]
        #expect(DeckLayout.filtered(all, filter: nil, groups: [work, home]).map(\.id) == [a.id, b.id, c.id])
        #expect(DeckLayout.filtered(all, filter: work.id, groups: [work, home]).map(\.id) == [a.id])
        #expect(DeckLayout.filtered(all, filter: AccountGroupID(), groups: [work, home]).count == 3)

        #expect(DeckLayout.selection(preferred: b.id, shown: [a.id, b.id], all: [a.id, b.id, c.id]) == b.id)
        #expect(DeckLayout.selection(preferred: c.id, shown: [a.id], all: [a.id, b.id, c.id]) == a.id)
        #expect(DeckLayout.selection(preferred: nil, shown: [], all: [c.id]) == c.id)
        #expect(DeckLayout.selection(preferred: nil, shown: [], all: []) == nil)

        #expect(DeckLayout.dialsFit(count: 4, itemWidth: 84, spacing: 6, available: 380))
        #expect(!DeckLayout.dialsFit(count: 5, itemWidth: 84, spacing: 6, available: 380))
        #expect(DeckLayout.dialsFit(count: 0, itemWidth: 84, spacing: 6, available: 0))
    }

    @Test("Header, identity and footer texts")
    func texts() throws {
        let profile = try UIFixture.profile("A")
        let reading = try UIFixture.reading([try UIFixture.bucket("claude", [try UIFixture.window("session", .session, used: 7)])], capturedAgo: 120)
        var fresh = AccountStatus(profile: profile, reading: reading, nextRefreshAt: now.addingTimeInterval(180))
        #expect(DeckLayout.headerSubtitle(accounts: [fresh], now: now, l10n: .testRussian) == "обновлено 2\u{00A0}мин назад")
        #expect(DeckLayout.refreshText(status: fresh, now: now, l10n: .testRussian) == "обновление через 3\u{00A0}мин")
        // The header never names a next refresh, so it cannot contradict the selected account's footer.
        let other = AccountStatus(profile: try UIFixture.profile("B"), reading: reading, nextRefreshAt: now.addingTimeInterval(60))
        #expect(DeckLayout.headerSubtitle(accounts: [fresh, other], now: now, l10n: .testRussian) == "обновлено 2\u{00A0}мин назад")
        #expect(DeckLayout.refreshText(status: other, now: now, l10n: .testRussian) == "обновление через 1\u{00A0}мин")
        fresh.isRefreshing = true
        #expect(DeckLayout.headerSubtitle(accounts: [fresh], now: now, l10n: .testRussian) == "обновлено 2\u{00A0}мин назад")
        #expect(DeckLayout.refreshText(status: fresh, now: now, l10n: .testRussian) == "обновляется…")
        #expect(DeckLayout.headerSubtitle(accounts: [AccountStatus(profile: profile, isRefreshing: true)], now: now, l10n: .testRussian) == "загрузка лимитов…")
        #expect(DeckLayout.headerSubtitle(accounts: [AccountStatus(profile: profile)], now: now, l10n: .testRussian) == "ожидание данных")
        #expect(DeckLayout.headerSubtitle(accounts: [], now: now, l10n: .testRussian) == "ожидание данных")
        #expect(DeckLayout.refreshText(status: AccountStatus(profile: profile), now: now, l10n: .testRussian) == nil)

        #expect(DeckLayout.identityLine(email: "a@b.c", freshness: .fresh, capturedAt: now.addingTimeInterval(-120), provider: .claude, now: now, l10n: .testRussian) == "a@b.c · 2\u{00A0}мин назад")
        #expect(DeckLayout.identityLine(email: nil, freshness: .stale(since: now.addingTimeInterval(-1_200)), capturedAt: nil, provider: .codex, now: now, l10n: .testRussian) == "обновлено 20\u{00A0}мин назад")
        #expect(DeckLayout.identityLine(email: nil, freshness: .missing, capturedAt: nil, provider: .codex, now: now, l10n: .testRussian) == "Codex")
    }

    @Test("Header, identity and footer texts in English, and in words for VoiceOver")
    func englishTexts() throws {
        let en = Localizer.testEnglish
        let profile = try UIFixture.profile("A")
        let reading = try UIFixture.reading([try UIFixture.bucket("claude", [try UIFixture.window("session", .session, used: 7)])], capturedAgo: 120)
        var fresh = AccountStatus(profile: profile, reading: reading, nextRefreshAt: now.addingTimeInterval(180))
        #expect(DeckLayout.headerSubtitle(accounts: [fresh], now: now, l10n: en) == "Updated 2 min ago")
        #expect(DeckLayout.headerSubtitleA11y(accounts: [fresh], now: now, l10n: en) == "Updated 2 minutes ago")
        #expect(DeckLayout.headerSubtitleA11y(accounts: [fresh], now: now, l10n: .testRussian) == "обновлено 2 минуты назад")
        #expect(DeckLayout.refreshText(status: fresh, now: now, l10n: en) == "Next refresh in 3 min")
        #expect(DeckLayout.refreshTextA11y(status: fresh, now: now, l10n: en) == "Next refresh in 3 minutes")
        #expect(DeckLayout.headerSubtitle(accounts: [AccountStatus(profile: profile, isRefreshing: true)], now: now, l10n: en) == "Loading limits…")
        #expect(DeckLayout.headerSubtitle(accounts: [], now: now, l10n: en) == "Waiting for data")
        #expect(DeckLayout.headerSubtitleA11y(accounts: [], now: now, l10n: en) == "Waiting for data")
        fresh.isRefreshing = true
        #expect(DeckLayout.refreshText(status: fresh, now: now, l10n: en) == "Refreshing…")
        #expect(DeckLayout.refreshTextA11y(status: fresh, now: now, l10n: en) == "Refreshing…")

        #expect(DeckLayout.identityLine(email: "a@b.c", freshness: .fresh, capturedAt: now.addingTimeInterval(-120), provider: .claude, now: now, l10n: en) == "a@b.c · 2 min ago")
        #expect(DeckLayout.identityLine(email: "a@b.c", freshness: .fresh, capturedAt: now.addingTimeInterval(-20), provider: .claude, now: now, l10n: en) == "a@b.c · just now")
        #expect(DeckLayout.identityLine(email: nil, freshness: .stale(since: now.addingTimeInterval(-1_200)), capturedAt: nil, provider: .codex, now: now, l10n: en) == "Updated 20 min ago")
        #expect(
            DeckLayout.identityLineA11y(email: "a@b.c", freshness: .stale(since: now.addingTimeInterval(-3_900)), capturedAt: nil, provider: .codex, now: now, l10n: en)
                == "a@b.c, Updated 1 hour 5 minutes ago, data is out of date"
        )
        #expect(
            DeckLayout.identityLineA11y(email: nil, freshness: .stale(since: now.addingTimeInterval(-1_200)), capturedAt: nil, provider: .codex, now: now, l10n: .testRussian)
                == "обновлено 20 минут назад, данные устарели"
        )
        #expect(DeckLayout.identityLineA11y(email: nil, freshness: .missing, capturedAt: nil, provider: .codex, now: now, l10n: en) == "Codex")

        #expect(DeckPage.overview.title(l10n: en) == "Overview" && DeckPage.timeline.title(l10n: en) == "Timeline")
        #expect(DeckPage.overview.title(l10n: .testRussian) == "Обзор" && DeckPage.timeline.title(l10n: .testRussian) == "Хронология")
    }

    @Test("Resets read in words for VoiceOver; clock times and the reset in progress stay as shown")
    func resetA11y() throws {
        let en = Localizer.testEnglish
        let soon = try UIFixture.window("session", .session, used: 40, resetsIn: 2 * 3_600 + 14 * 60)
        #expect(DeckLayout.resetTextA11y(for: soon, now: now, style: .countdown, l10n: en) == "Resets in 2 hours 14 minutes")
        #expect(DeckLayout.resetTextA11y(for: soon, now: now, style: .countdown, l10n: .testRussian) == "сброс через 2 часа 14 минут")
        #expect(DeckLayout.resetTextA11y(for: soon, now: now, style: .clockTime, l10n: en) == UsageFormat.resetText(for: soon, now: now, style: .clockTime, l10n: en))
        let passed = try UIFixture.window("session", .session, used: 40, resetsIn: -60)
        #expect(DeckLayout.resetTextA11y(for: passed, now: now, style: .countdown, l10n: en) == "Resetting…")
        let unknown = try UIFixture.window("session", .session, used: 40, resetsIn: nil)
        #expect(DeckLayout.resetTextA11y(for: unknown, now: now, style: .countdown, l10n: en) == nil)
    }

    @Test("Sessions read in words for VoiceOver")
    func sessionA11y() throws {
        let working = try AgentSession(
            id: "a", title: "web", projectPath: "/Users/me/web", activity: .working, detail: nil,
            activitySince: now.addingTimeInterval(-420), processID: nil,
            lastTurn: try UIFixture.turn(duration: 252, firstToken: 2.8), lastEventAt: now.addingTimeInterval(-20)
        )
        #expect(
            SessionList.valueA11y(working, provider: .claude, now: now, l10n: .testEnglish)
                == "Working, 7 minutes, last turn 4 minutes 12 seconds, first token in 2.8 seconds"
        )
        #expect(
            SessionList.valueA11y(working, provider: .claude, now: now, l10n: .testRussian)
                == "работает, 7 минут, последний ход 4 минуты 12 секунд, первый токен через 2,8 секунды"
        )
        let interrupted = try AgentSession(
            id: "b", title: "api", projectPath: nil, activity: .idle, detail: nil,
            activitySince: now.addingTimeInterval(-30), processID: nil,
            lastTurn: try UIFixture.turn(duration: 38, firstToken: 0.01, aborted: true)
        )
        #expect(
            SessionList.valueA11y(interrupted, provider: .codex, now: now, l10n: .testEnglish)
                == "Ready, 1 minute, last turn 38 seconds, first token in less than 0.1 seconds, interrupted"
        )
        let session = Localizer.testEnglish.session
        #expect(session.spokenPrecise(3_900) == "1 hour 5 minutes")
        #expect(session.spokenPrecise(61) == "1 minute 1 second")
        #expect(session.spokenLatency(1) == "1 second")
        #expect(session.spokenLatency(12.3) == "12 seconds")
        #expect(Localizer.testRussian.session.spokenPrecise(21) == "21 секунда")
    }

    @Test("Counted phrases agree in both languages")
    func plurals() {
        let en = Localizer.testEnglish
        let ru = Localizer.testRussian
        #expect(en.session.more(1) == "1 more session")
        #expect(en.session.more(3) == "3 more sessions")
        #expect(ru.session.more(1) == "и ещё 1 сессия")
        #expect(ru.session.more(3) == "и ещё 3 сессии")
        #expect(ru.session.more(11) == "и ещё 11 сессий")
        #expect(ru.session.more(21) == "и ещё 21 сессия")
        #expect(en.deck.moreWaiting(1) == "1 more agent waiting")
        #expect(en.deck.moreWaiting(2) == "2 more agents waiting")
        #expect(ru.deck.moreWaiting(2) == "и ещё 2 агента")
        #expect(ru.deck.moreWaiting(5) == "и ещё 5 агентов")
        #expect(en.rail.waiting(1) == "1 agent is waiting for you")
        #expect(en.rail.waiting(3) == "3 agents are waiting for you")
        #expect(ru.rail.waiting(1) == "Вас ждёт 1 агент")
        #expect(ru.rail.waiting(3) == "Вас ждут 3 агента")
        #expect(ru.rail.waiting(21) == "Вас ждёт 21 агент")
        #expect(ru.rail.waiting(25) == "Вас ждут 25 агентов")
    }

    @Test("The elapsed-time template is at least as wide as every elapsed time, in both languages", arguments: [0.85, 1.0, 1.5], [Localizer.testEnglish, .testRussian])
    func elapsedTemplateFits(scale: Double, l10n: Localizer) {
        let size = IslandMetrics(scale: scale).textSize(TextSize.caption)
        let template = TextFit.width(DeckLayout.elapsedTemplate(l10n: l10n), size: size, weight: .medium, monospacedDigits: true)
        // Every minute of the first two days, then every hour up to 99 days.
        let minutes: [TimeInterval] = Array(stride(from: 0.0, through: 172_800, by: 60))
        let hours: [TimeInterval] = Array(stride(from: 172_800.0, through: 8_553_600, by: 3_600))
        let seconds = minutes + hours
        var widest = ""
        var widestWidth: CGFloat = 0
        for value in Set(seconds.map { UsageFormat.elapsed(since: now.addingTimeInterval(-$0), now: now, l10n: l10n) }) {
            let width = TextFit.width(value, size: size, weight: .medium, monospacedDigits: true)
            if width > widestWidth { (widest, widestWidth) = (value, width) }
        }
        #expect(widestWidth <= template + 0.01, "\(l10n.language): “\(widest)” \(widestWidth) pt, template \(template) pt")
    }

    @Test("An attention card keeps one height with a long account name and the Codex hedge, in both languages", arguments: [Localizer.testEnglish, .testRussian])
    func attentionCardHeight(l10n: Localizer) throws {
        let metrics = IslandMetrics(scale: 1)
        let inner = metrics.deckWidth - metrics.deckPadding * 2
        func height(label: String, detail: String, waited: TimeInterval) throws -> CGFloat {
            let session = try AgentSession(
                id: "s", title: "service-with-a-long-name", projectPath: nil, activity: .waiting, detail: detail,
                activitySince: now.addingTimeInterval(-waited), processID: nil
            )
            let account = AccountID()
            let section = AttentionSection(
                items: [AttentionItem(accountID: account, session: session)],
                labels: [account: label],
                providers: [account: .codex],
                now: now,
                metrics: metrics
            ) { _ in }
            return NSHostingView(rootView: section.frame(width: inner).fixedSize().environment(\.l10n, l10n)).fittingSize.height
        }
        let short = try height(label: "Work", detail: "input needed", waited: 30)
        #expect(try height(label: "Personal side projects", detail: "permission prompt", waited: 3 * 86_400) == short)
        #expect(try height(label: "Personal side projects with a very long name", detail: "permission prompt", waited: 23 * 3_600 + 59 * 60) == short)
    }

    @Test("The hero's “left” caption and the pace pill fit beside the widest numeral, in both languages", arguments: [Localizer.testEnglish, .testRussian])
    func heroCaptionFits(l10n: Localizer) {
        let metrics = IslandMetrics(scale: 1)
        let inner = metrics.deckWidth - metrics.deckPadding * 2 - metrics.cardPadding * 2
        let numeral = TextFit.width("100%", size: metrics.textSize(TextSize.hero), weight: .bold, monospacedDigits: true)
        let column = inner - numeral - 12
        let left = TextFit.width(l10n.deck.percentLeft(l10n.format.percent(100)), size: metrics.textSize(TextSize.callout), weight: .medium, monospacedDigits: true)
        #expect(left <= column)
        #expect(TextFit.width(l10n.deck.limitReachedTag, size: metrics.textSize(TextSize.badge), weight: .semibold, monospacedDigits: false) <= 120)
    }

    @Test("A long pace wording gives way to a shorter one, and only for “runs out”")
    func compactPace() throws {
        // 3 h into a 5 h window at 90 %: runs out in 20 minutes, before the reset.
        let hot = try #require(UsagePace(window: try UIFixture.window("session", .session, used: 90, resetsIn: 2 * 3_600), now: now))
        let moment = UsageFormat.clockText(try #require(hot.projectedExhaustion), now: now, l10n: .testEnglish)
        #expect(UsageFormat.pace(hot, now: now, l10n: .testEnglish).text == "At this pace, runs out \(moment)")
        #expect(DeckLayout.compactPaceText(hot, now: now, l10n: .testEnglish) == "Runs out \(moment)")
        let ruMoment = UsageFormat.clockText(try #require(hot.projectedExhaustion), now: now, l10n: .testRussian)
        #expect(DeckLayout.compactPaceText(hot, now: now, l10n: .testRussian) == "закончится \(ruMoment)")
        let calm = try #require(UsagePace(window: try UIFixture.window("session", .session, used: 10, resetsIn: 2 * 3_600), now: now))
        #expect(DeckLayout.compactPaceText(calm, now: now, l10n: .testEnglish) == nil)

        #expect(DeckLayout.compactStatus(Localizer.testEnglish.usage.approvalOrRunning, l10n: .testEnglish) == "Waiting or running a command")
        #expect(DeckLayout.compactStatus(Localizer.testRussian.usage.approvalOrRunning, l10n: .testRussian) == "ждёт или выполняет команду")
        #expect(DeckLayout.compactStatus(Localizer.testEnglish.usage.needsApproval, l10n: .testEnglish) == nil)
    }

    @Test(
        "The pace pill's “runs out” wording fits beside the numeral for every moment in the next week, in both languages",
        arguments: [0.85, 1.0, 1.5], [Localizer.testEnglish, .testRussian]
    )
    func pacePillFits(scale: Double, l10n: Localizer) throws {
        let metrics = IslandMetrics(scale: scale)
        let inner = metrics.deckWidth - metrics.deckPadding * 2 - metrics.cardPadding * 2
        // Usage runs ahead, so the numeral is below 100 %.
        let numeral = TextFit.width("99%", size: metrics.textSize(TextSize.hero), weight: .bold, monospacedDigits: true)
        let flame = try #require(NSImage(systemSymbolName: "flame.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: metrics.textSize(TextSize.badge), weight: .semibold))).size.width
        let room = inner - numeral - 12 * scale - 14 * scale - flame - 4 * scale
        var widest = ""
        var widestWidth: CGFloat = 0
        // Every ten minutes of the next eight days: today, tomorrow, weekdays and dates, 12- and 24-hour clocks.
        for step in 1...(8 * 24 * 6) {
            let moment = UsageFormat.clockText(now.addingTimeInterval(Double(step) * 600), now: now, l10n: l10n)
            let text = l10n.deck.runsOutCompact(at: moment)
            let width = TextFit.width(text, size: metrics.textSize(TextSize.caption), weight: .medium, monospacedDigits: false)
            if width > widestWidth { (widest, widestWidth) = (text, width) }
        }
        #expect(widestWidth <= room, "\(l10n.language) scale \(scale): “\(widest)” \(widestWidth) pt, room \(room) pt")
    }

    @Test(
        "An attention card's status fits beside the waiting time, in shorter words if needed, in both languages",
        arguments: [0.85, 1.0, 1.5], [Localizer.testEnglish, .testRussian]
    )
    func attentionStatusFits(scale: Double, l10n: Localizer) {
        let metrics = IslandMetrics(scale: scale)
        let size = metrics.textSize(TextSize.caption)
        let inner = metrics.deckWidth - metrics.deckPadding * 2
        let template = TextFit.width(DeckLayout.elapsedTemplate(l10n: l10n), size: size, weight: .medium, monospacedDigits: true)
        // Card paddings, the glyph, three gaps and the spacer's minimum.
        let room = inner - (8 + 12 + 24 + 3 * 10 + 6) * scale - template
        let usage = l10n.usage
        for status in [usage.needsApproval, usage.needsInput, usage.waitingForYou, usage.approvalOrRunning] {
            let shown = DeckLayout.compactStatus(status, l10n: l10n) ?? status
            let width = min(
                TextFit.width(status, size: size, weight: .medium, monospacedDigits: false),
                TextFit.width(shown, size: size, weight: .medium, monospacedDigits: false)
            )
            #expect(width <= room, "\(l10n.language) scale \(scale): “\(shown)” \(width) pt, room \(room) pt")
        }
    }

    @Test("Sessions: waiting first, at most four, hedged status")
    func sessions() throws {
        let idle = try UIFixture.session("idle", .idle)
        let workA = try UIFixture.session("work-a", .working, since: 300)
        let waitShort = try UIFixture.session("wait-short", .waiting, since: 30)
        let workB = try UIFixture.session("work-b", .working, since: 100)
        let waitLong = try UIFixture.session("wait-long", .waiting, since: 900)
        let list = DeckLayout.sessions([idle, workA, waitShort, workB, waitLong])
        #expect(list.shown.map(\.id) == ["wait-long", "wait-short", "work-a", "work-b"])
        #expect(list.hidden == 1)
        #expect(DeckLayout.sessions([idle], limit: 4).hidden == 0)

        #expect(DeckLayout.sessionStatus(workA, provider: .claude, now: now, l10n: .testRussian) == "работает")
        let quiet = try AgentSession(id: "q", title: "q", projectPath: nil, activity: .working, detail: nil, activitySince: now.addingTimeInterval(-600), processID: nil, lastEventAt: now.addingTimeInterval(-8 * 60))
        #expect(DeckLayout.sessionStatus(quiet, provider: .codex, now: now, l10n: .testRussian) == "нет активности 8\u{00A0}мин")
        let prompt = try AgentSession(id: "p", title: "p", projectPath: nil, activity: .waiting, detail: "permission prompt", activitySince: now.addingTimeInterval(-20 * 60), processID: nil)
        #expect(DeckLayout.sessionStatus(prompt, provider: .claude, now: now, l10n: .testRussian) == "ждёт подтверждения")
        #expect(DeckLayout.sessionStatus(prompt, provider: .codex, now: now, l10n: .testRussian) == "ждёт подтверждения или выполняет команду")
        #expect(DeckLayout.sessionStatus(idle, provider: .codex, now: now, l10n: .testRussian) == "готово")

        let items = try (0..<5).map { AttentionItem(accountID: AccountID(), session: try UIFixture.session("w\($0)", .waiting)) }
        let queue = DeckLayout.attention(items)
        #expect(queue.shown.count == 3 && queue.hidden == 2)
    }

    @Test("A capped deck sizes to its content and scrolls only beyond the cap")
    func cappedStackSizing() {
        func height(maxHeight: CGFloat, content: CGFloat) -> CGFloat {
            let view = DeckStackLayout(spacing: 10, maxHeight: maxHeight) {
                Color.red.frame(height: 40)
                ScrollView { Color.blue.frame(height: content) }
            }
            .frame(width: 200)
            .fixedSize()
            return NSHostingView(rootView: view).fittingSize.height
        }
        #expect(height(maxHeight: 300, content: 500) == 300)
        #expect(height(maxHeight: 300, content: 100) == 150)
        #expect(height(maxHeight: .infinity, content: 500) == 550)
    }

    @Test("Pages share the tallest page's height")
    func pageStackSizing() {
        let view = PageStackLayout {
            Color.red.frame(width: 100, height: 40)
            VStack(spacing: 0) {
                Color.blue.frame(width: 100, height: 20)
                Spacer(minLength: 0)
            }
            Color.green.frame(width: 60, height: 120)
        }
        .fixedSize()
        #expect(NSHostingView(rootView: view).fittingSize == CGSize(width: 100, height: 120))
    }

    @Test("Deck body height is capped below the header")
    func stackHeights() {
        #expect(DeckStackLayout.heights(ideal: [40, 600], spacing: 12, maxHeight: .infinity) == [40, 600])
        #expect(DeckStackLayout.heights(ideal: [40, 600], spacing: 12, maxHeight: 400) == [40, 348])
        #expect(DeckStackLayout.heights(ideal: [40, 100], spacing: 12, maxHeight: 400) == [40, 100])
        #expect(DeckStackLayout.heights(ideal: [40, 600], spacing: 12, maxHeight: 20) == [40, 0])
        #expect(DeckStackLayout.heights(ideal: [], spacing: 12, maxHeight: 20).isEmpty)
        #expect(WindowVisibilityReader.isOnScreen(isVisible: true, occlusion: .visible))
        #expect(!WindowVisibilityReader.isOnScreen(isVisible: true, occlusion: []))
        #expect(!WindowVisibilityReader.isOnScreen(isVisible: false, occlusion: .visible))
        #expect(DeckPage.available(showsTimeline: false) == [.overview])
        #expect(DeckPage.available(showsTimeline: true) == [.overview, .timeline])
        #expect(DeckFeatures.showsTimelinePage)
        #expect(DeckLayout.availablePages == [.overview, .timeline])
    }
}
