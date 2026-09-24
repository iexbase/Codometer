import CodometerCore
import CodometerL10n
@testable import CodometerUI
import AppKit
import Foundation
import SwiftUI
import Testing

/// The ring visuals drawn to PNGs for review, in English and Russian: forecast ghosts, account badges and dots, a rail
/// where two accounts share a provider, and the still activity glyphs. Runs only with `CODOMETER_SNAPSHOT_DIR`.
///
/// Ceremonies and the finishing sequence are Core Animation, which `ImageRenderer` never draws: the harness captures
/// those live. What these renders do prove is that a still frame shows no trace of them.
@MainActor
@Suite("Ring visuals", .enabled(if: ProcessInfo.processInfo.environment["CODOMETER_SNAPSHOT_DIR"] != nil))
struct VisualsSnapshotTests {
    private let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODOMETER_SNAPSHOT_DIR"] ?? "/tmp", isDirectory: true)
    private static let now = Date(timeIntervalSince1970: 1_789_590_000)

    @Test("Forecast ghosts on dials and the hero bar, light and dark, in both languages", arguments: [LanguagePreference.english, .russian])
    func renderForecasts(language: LanguagePreference) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let l10n = Self.localizer(language)
        let calm = try Self.presentation(label: "Calm", used: 40, elapsed: 0.5)
        let reaching = try Self.presentation(label: "Reaching", used: 60, elapsed: 0.4)
        let stale = try Self.presentation(label: "Stale", used: 60, elapsed: 0.4, capturedAgo: 3 * 3_600)
        let off = try Self.presentation(label: "Off", used: 60, elapsed: 0.4, showsForecast: false)
        for scheme in [ColorScheme.light, .dark] {
            let suffix = "\(scheme == .dark ? "dark" : "light")-\(l10n.language.rawValue)"
            let dials = VStack(alignment: .leading, spacing: 16) {
                Self.row("deck · always", [calm, reaching, stale, off], diameter: 58, policy: .always)
                Self.row("rail · warnings only", [calm, reaching, stale, off], diameter: 28, policy: .warningsOnly)
                Self.row("settings · never", [calm, reaching], diameter: 46, policy: .never)
                Self.bars([calm, reaching, stale])
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.regularMaterial))
            try render(dials, name: "visuals-forecast-\(suffix)", scheme: scheme, l10n: l10n)
        }
    }

    @Test("Every account tint as a badge and a dot, light and dark, in both languages", arguments: [LanguagePreference.english, .russian])
    func renderBadges(language: LanguagePreference) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let l10n = Self.localizer(language)
        for scheme in [ColorScheme.light, .dark] {
            let suffix = "\(scheme == .dark ? "dark" : "light")-\(l10n.language.rawValue)"
            let rows = try AccountTint.allCases.map { tint in
                (tint, try Self.style(tint: tint, monogram: "W"), try Self.style(tint: tint, monogram: "WA"), try Self.style(tint: tint, monogram: "🚀"))
            }
            let swatches = VStack(alignment: .leading, spacing: 12) {
                ForEach(rows, id: \.0) { tint, single, double, emoji in
                    HStack(spacing: 12) {
                        AccountBadge(style: single, provider: .claude, size: 30)
                        AccountBadge(style: double, provider: nil, size: 30)
                        AccountBadge(style: emoji, provider: nil, size: 20)
                        AccountBadge.Dot(tint: tint, diameter: 6)
                        Text(verbatim: TintSwatches.name(of: tint, l10n: l10n))
                            .font(.callout)
                            .foregroundStyle(Theme.accountTintText(for: tint))
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(width: 320, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.regularMaterial))
            try render(swatches, name: "visuals-tints-\(suffix)", scheme: scheme, l10n: l10n)
        }
    }

    @Test("A rail and deck dials where two accounts share a provider, in both languages", arguments: [LanguagePreference.english, .russian])
    func renderIdentity(language: LanguagePreference) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let l10n = Self.localizer(language)
        let store = try Self.sharedProviderStore(language: language)
        let model = IslandModel(layout: IslandLayout(edge: .top, anchor: .top, style: .floating, metrics: IslandMetrics(scale: 1)))
        for scheme in [ColorScheme.light, .dark] {
            let suffix = "\(scheme == .dark ? "dark" : "light")-\(l10n.language.rawValue)"
            try render(
                RailView(store: store, model: model, accounts: store.presentations)
                    .background(Capsule().fill(.regularMaterial)),
                name: "visuals-rail-shared-provider-\(suffix)",
                scheme: scheme,
                l10n: store.localizer
            )
            let dials = HStack(spacing: 6) {
                ForEach(store.presentations) { account in
                    DeckDial(
                        presentation: account,
                        isSelected: account.id == store.presentations.first?.id,
                        isHovered: false,
                        isHighlighted: false,
                        showsInnerRings: true,
                        now: store.now,
                        metrics: model.layout.metrics
                    )
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.regularMaterial))
            try render(dials, name: "visuals-deck-dials-\(suffix)", scheme: scheme, l10n: store.localizer)
        }
    }

    @Test("The still activity glyphs, in both languages", arguments: [LanguagePreference.english, .russian])
    func renderGlyphs(language: LanguagePreference) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let l10n = Self.localizer(language)
        let glyphs = HStack(spacing: 18) {
            ForEach(AgentActivity.allCases, id: \.self) { activity in
                VStack(spacing: 6) {
                    ActivityGlyph(activity: activity, size: 22)
                    ActivityGlyph(activity: activity, size: 44)
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.regularMaterial))
        try render(glyphs, name: "visuals-glyphs-light-\(l10n.language.rawValue)", scheme: .light, l10n: l10n)
    }

    @Test("A still frame shows no trace of a ceremony, whatever the board says")
    func ceremoniesAreNeverStill() throws {
        let account = try Self.presentation(label: "Work", used: 3, elapsed: 0.05)
        let plain = try image(
            RingGauge(presentation: account, diameter: 58, showsSecondary: true, ceremonySurface: .rail),
            scheme: .light,
            l10n: .testEnglish
        )
        var board = CeremonyBoard()
        board.insert(
            [try WindowResetEvent(
                accountID: account.id,
                bucketID: "claude",
                windowID: "session",
                previousUsed: try Percentage(validating: 64),
                newUsed: try Percentage(validating: 3),
                detectedAt: Self.now
            )],
            previousFractions: [:],
            now: Self.now
        )
        let stage = CeremonyStage(surface: .rail, board: board, now: Self.now) { _, _ in }
        let celebrating = try image(
            RingGauge(presentation: account, diameter: 58, showsSecondary: true, ceremonySurface: .rail)
                .environment(\.ceremonyStage, stage),
            scheme: .light,
            l10n: .testEnglish
        )
        #expect(plain == celebrating, "a static render drew part of a ceremony")
    }

    // MARK: - Fixtures

    private static func localizer(_ language: LanguagePreference) -> Localizer {
        language == .russian ? .testRussian : .testEnglish
    }

    private static func style(tint: AccountTint, monogram: String) throws -> AccountStyle {
        try AccountStyle(
            tint: tint == .automatic ? .graphite : tint,
            monogram: try AccountMonogram(validating: monogram),
            isAutomaticTint: tint == .automatic,
            isAutomaticMonogram: false
        )
    }

    /// One Claude account whose five-hour window is `used` per cent through with `elapsed` of it gone.
    private static func presentation(
        label: String,
        used: Double,
        elapsed: Double,
        capturedAgo: TimeInterval = 60,
        showsForecast: Bool = true,
        tint: AccountTint = .automatic
    ) throws -> AccountPresentation {
        let length = WindowDuration.fiveHours.timeInterval
        let profile = try AccountProfile(
            id: UIFixture.accountID("visuals/\(label)"),
            provider: .claude,
            label: try AccountLabel(validating: label),
            directory: try ProfileDirectory(validating: "/Users/me/.claude-\(label.lowercased())"),
            tint: tint
        )
        let reading = try UsageReading(
            capturedAt: now.addingTimeInterval(-capturedAgo),
            source: .claudeUsageCommand,
            buckets: [try LimitBucket(id: "claude", title: nil, windows: [
                try LimitWindow(
                    id: "session",
                    scope: .session,
                    used: try Percentage(validating: used),
                    duration: .fiveHours,
                    resetsAt: now.addingTimeInterval(length * (1 - elapsed))
                ),
                try LimitWindow(
                    id: "week",
                    scope: .weekly(model: nil),
                    used: try Percentage(validating: 38),
                    duration: .oneWeek,
                    resetsAt: now.addingTimeInterval(4 * 86_400)
                ),
            ], isLimitReached: false)],
            credits: nil
        )
        var appearance = AppearanceSettings()
        appearance.showsForecast = showsForecast
        return AccountPresentation(
            status: AccountStatus(profile: profile, reading: reading),
            appearance: appearance,
            now: now,
            l10n: .testEnglish
        )
    }

    private static func row(_ title: String, _ accounts: [AccountPresentation], diameter: CGFloat, policy: RingForecastPolicy) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 14) {
                ForEach(accounts) { account in
                    RingGauge(presentation: account, diameter: diameter, showsSecondary: diameter >= 42, forecastPolicy: policy)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private static func bars(_ accounts: [AccountPresentation]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "hero bar")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(accounts) { account in
                let window = account.windows.first { $0.isMainBucket }
                UsageBar(
                    fraction: window?.progress.used ?? 0,
                    band: window?.band ?? .ample,
                    height: 6,
                    elapsed: window?.progress.elapsed,
                    isStale: account.isStale,
                    forecast: RingForecastPolicy.always.arcEnd(used: window?.progress.used ?? 0, forecast: account.isStale ? nil : window?.forecast),
                    forecastBand: window?.forecast?.band
                )
                .frame(width: 320)
            }
        }
    }

    /// Two Claude accounts and one Codex account, so the rail shows monograms and identity dots.
    private static func sharedProviderStore(language: LanguagePreference) throws -> TrackerStore {
        let work = try AccountProfile(
            id: UIFixture.accountID("visuals/work"),
            provider: .claude,
            label: try AccountLabel(validating: "Work"),
            directory: try ProfileDirectory(validating: "/Users/me/.claude"),
            tint: .teal,
            monogram: try AccountMonogram(validating: "W")
        )
        let personal = try AccountProfile(
            id: UIFixture.accountID("visuals/personal"),
            provider: .claude,
            label: try AccountLabel(validating: "Personal"),
            directory: try ProfileDirectory(validating: "/Users/me/.claude-personal"),
            tint: .pink
        )
        let side = try AccountProfile(
            id: UIFixture.accountID("visuals/side"),
            provider: .codex,
            label: try AccountLabel(validating: "Side project"),
            directory: try ProfileDirectory(validating: "/Users/me/.codex")
        )
        var settings = try AppSettings(accounts: [work, personal, side])
        settings.general.language = language
        func claudeReading(session: Double, elapsed: Double) throws -> UsageReading {
            let length = WindowDuration.fiveHours.timeInterval
            return try UsageReading(
                capturedAt: now.addingTimeInterval(-60),
                source: .claudeUsageCommand,
                buckets: [try LimitBucket(id: "claude", title: nil, windows: [
                    try LimitWindow(id: "session", scope: .session, used: try Percentage(validating: session), duration: .fiveHours, resetsAt: now.addingTimeInterval(length * (1 - elapsed))),
                    try LimitWindow(id: "week", scope: .weekly(model: nil), used: try Percentage(validating: 38), duration: .oneWeek, resetsAt: now.addingTimeInterval(4 * 86_400)),
                ], isLimitReached: false)],
                credits: nil
            )
        }
        let codexReading = try UsageReading(
            capturedAt: now.addingTimeInterval(-30),
            source: .codexAppServer,
            buckets: [try LimitBucket(id: "codex", title: nil, windows: [
                try LimitWindow(id: "primary", scope: .rolling, used: try Percentage(validating: 34), duration: .fiveHours, resetsAt: now.addingTimeInterval(2 * 3_600)),
            ], isLimitReached: false)],
            credits: nil
        )
        let state = TrackerState(accounts: [
            AccountStatus(profile: work, reading: try claudeReading(session: 60, elapsed: 0.4), nextRefreshAt: now.addingTimeInterval(180)),
            AccountStatus(profile: personal, reading: try claudeReading(session: 12, elapsed: 0.5), nextRefreshAt: now.addingTimeInterval(240)),
            AccountStatus(profile: side, reading: codexReading, nextRefreshAt: now.addingTimeInterval(120)),
        ])
        return TrackerStore(
            state: state,
            settings: settings,
            now: now,
            actions: UIFixture.actions(),
            preferredLanguages: { ["en-US"] },
            region: { Locale(identifier: language == .russian ? "ru_RU" : "en_US") }
        )
    }

    // MARK: - Rendering

    private func render(_ view: some View, name: String, scheme: ColorScheme, l10n: Localizer) throws {
        let png = try image(view, scheme: scheme, l10n: l10n)
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }

    private func image(_ view: some View, scheme: ColorScheme, l10n: Localizer) throws -> Data {
        let content = view
            .padding(28)
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
            .environment(\.l10n, l10n)
            .environment(\.locale, l10n.locale)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let cgImage = try #require(renderer.cgImage)
        return try #require(NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]))
    }
}
