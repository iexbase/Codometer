import CodometerCore
import CodometerL10n
@testable import CodometerWidgetsUI
import AppKit
import Foundation
import SwiftUI
import Testing
import WidgetKit

/// Renders the widget's account badges and the forecast ghost arc — in English and
/// Russian, so both can be looked at side by side (`…-en.png`, `…-ru.png`).
///
/// Runs only when `CODOMETER_SNAPSHOT_DIR` is set, e.g.
/// `CODOMETER_SNAPSHOT_DIR=/tmp/shots Scripts/test.sh --filter WidgetRenderL10n`.
/// The framing matches `WidgetRender`, so an image from either suite can be compared with the other.
@MainActor
@Suite("WidgetRenderL10n", .enabled(if: ProcessInfo.processInfo.environment["CODOMETER_SNAPSHOT_DIR"] != nil))
struct WidgetRenderL10nTests {
    private let directory = URL(
        fileURLWithPath: ProcessInfo.processInfo.environment["CODOMETER_SNAPSHOT_DIR"] ?? "/tmp",
        isDirectory: true
    )

    /// Fixed so the images do not move with the clock.
    private static let now = Date(timeIntervalSince1970: 1_789_600_000)

    private enum Look: String, CaseIterable {
        case light, dark, accented

        var scheme: ColorScheme { self == .light ? .light : .dark }
        var style: WidgetStyle { self == .accented ? .accented : .fullColor }
    }

    private static let families: [(WidgetFamily, String, CGSize)] = [
        (.systemSmall, "small", CGSize(width: 164, height: 164)),
        (.systemMedium, "medium", CGSize(width: 344, height: 164)),
        (.systemLarge, "large", CGSize(width: 344, height: 344)),
    ]

    private static func localizer(_ language: Language) -> Localizer {
        language == .en ? .testEnglish : .testRussian
    }

    // MARK: Cases

    @Test("Account badges and forecast ghosts in every family", arguments: Language.allCases)
    func renderAllAccounts(language: Language) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cases: [(String, WidgetSnapshot, [String], [Look])] = [
            ("marks", try Fixtures.marks(language), ["small", "medium", "large"], Look.allCases),
            ("forecast", try Fixtures.forecast(language), ["small", "medium", "large"], Look.allCases),
            ("forecast-off", try Fixtures.forecastOff(language), ["small", "medium", "large"], [.light, .dark]),
            ("single", try Fixtures.single(language), ["medium", "large"], [.light, .dark]),
            ("stale", try Fixtures.stale(language), ["small", "medium"], [.light, .dark]),
            ("legacy", try Fixtures.legacy(language), ["medium", "large"], [.light, .dark]),
        ]
        for (name, snapshot, families, looks) in cases {
            for (family, familyName, size) in Self.families where families.contains(familyName) {
                for look in looks {
                    let entry = LimitsEntry(date: Self.now, snapshot: snapshot)
                    try render(entry: entry, language: language, family: family, size: size, look: look, name: "c9-\(name)-\(familyName)-\(look.rawValue)")
                }
            }
        }
    }

    @Test("The provider widgets' badge header and their warnings-only ghost", arguments: Language.allCases)
    func renderProviders(language: Language) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cases: [(String, WidgetScope, WidgetSnapshot, [Look])] = [
            ("marks-claude", .provider(.claude), try Fixtures.marks(language), Look.allCases),
            ("marks-codex", .provider(.codex), try Fixtures.marks(language), [.light, .dark]),
            ("forecast-claude", .provider(.claude), try Fixtures.forecast(language), Look.allCases),
            ("forecast-codex", .provider(.codex), try Fixtures.forecast(language), [.light, .dark]),
            ("legacy-claude", .provider(.claude), try Fixtures.legacy(language), [.light, .dark]),
        ]
        for (name, scope, snapshot, looks) in cases {
            for (family, familyName, size) in Self.families where family != .systemLarge {
                for look in looks {
                    let entry = LimitsEntry(date: Self.now, snapshot: snapshot.scoped(to: scope), scope: scope)
                    try render(entry: entry, language: language, family: family, size: size, look: look, name: "c9-provider-\(name)-\(familyName)-\(look.rawValue)")
                }
            }
        }
    }

    // MARK: Rendering

    private func render(entry: LimitsEntry, language: Language, family: WidgetFamily, size: CGSize, look: Look, name: String) throws {
        let l10n = Self.localizer(language)
        let palette = WidgetPalette(
            style: look.style,
            scheme: look.scheme,
            accentPreview: look == .accented ? Color(red: 0.45, green: 0.72, blue: 1.0) : nil
        )
        let content = LimitsWidgetContent(entry: entry, family: family, palette: palette)
            .padding(16)
            .frame(width: size.width, height: size.height)
            .background { background(for: look, entry: entry) }
            .clipShape(RoundedRectangle(cornerRadius: 27.88, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 27.88, style: .continuous)
                    .strokeBorder(Color.white.opacity(look == .light ? 0.5 : 0.12), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
            .padding(28)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.36, green: 0.42, blue: 0.62),
                        Color(red: 0.62, green: 0.45, blue: 0.58),
                        Color(red: 0.93, green: 0.66, blue: 0.52),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .environment(\.colorScheme, look.scheme)
            .environment(\.widgetL10n, l10n)
            .environment(\.locale, l10n.locale)
            .environment(\.timeZone, l10n.calendar.timeZone)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("\(name)-\(language.rawValue).png"))
    }

    @ViewBuilder
    private func background(for look: Look, entry: LimitsEntry) -> some View {
        switch look {
        case .light, .dark:
            WidgetBackground(urgency: entry.urgency, hasAttention: entry.hasAttention, scheme: look.scheme)
        case .accented:
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.16, blue: 0.30), Color(red: 0.06, green: 0.09, blue: 0.18)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

// MARK: - Fixtures

/// Synthetic accounts only: no real label, e-mail or project name ever reaches an image.
private enum Fixtures {
    static let now = Date(timeIntervalSince1970: 1_789_600_000)

    static func window(
        _ id: String,
        _ scope: LimitWindowScope = .rolling,
        used: Double,
        minutes: Int,
        resetsIn seconds: TimeInterval,
        bucket: String,
        bucketTitle: String? = nil,
        isMain: Bool = true,
        language: Language
    ) throws -> WidgetWindow {
        try WidgetWindow(
            bucketID: bucket,
            bucketTitle: bucketTitle,
            isMainBucket: isMain,
            window: try LimitWindow(
                id: id,
                scope: scope,
                used: try Percentage(validating: used),
                duration: try WindowDuration(minutes: minutes),
                resetsAt: now.addingTimeInterval(seconds)
            ),
            language: language
        )
    }

    static func account(
        _ label: String,
        provider: ProviderKind,
        tint: AccountTint?,
        monogram: String?,
        plan: String? = nil,
        email: String? = nil,
        windows: [WidgetWindow],
        capturedAt: TimeInterval = -90,
        waiting: Int = 0,
        working: Int = 0
    ) throws -> WidgetAccount {
        try WidgetAccount(
            id: AccountID(),
            label: label,
            provider: provider,
            tint: tint,
            monogram: try monogram.map { try AccountMonogram(validating: $0) },
            plan: plan,
            email: email,
            windows: windows,
            capturedAt: now.addingTimeInterval(capturedAt),
            waitingCount: waiting,
            workingCount: working
        )
    }

    static func snapshot(_ accounts: [WidgetAccount], language: Language, showsForecast: Bool = true) -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: now,
            accounts: accounts,
            bands: .standard,
            attentionCount: accounts.reduce(0) { $0 + $1.waitingCount },
            workingCount: accounts.reduce(0) { $0 + $1.workingCount },
            language: language,
            showsForecast: showsForecast
        )
    }

    /// Claude windows with resets far enough out that nothing forecasts: badges without ghosts.
    private static func claudeWindows(_ language: Language, session: Double, week: Double, fable: Double) throws -> [WidgetWindow] {
        [
            try window("session", .session, used: session, minutes: 300, resetsIn: 4 * 3_600, bucket: "claude", language: language),
            try window("week", .weekly(model: nil), used: week, minutes: 10_080, resetsIn: 6 * 86_400, bucket: "claude", language: language),
            try window("week.fable", .weekly(model: "Fable"), used: fable, minutes: 10_080, resetsIn: 6 * 86_400, bucket: "claude", language: language),
        ]
    }

    private static func codexWindows(_ language: Language, primary: Double, secondary: Double) throws -> [WidgetWindow] {
        [
            try window("primary", used: primary, minutes: 300, resetsIn: 4 * 3_600 + 40 * 60, bucket: "codex", language: language),
            try window("secondary", used: secondary, minutes: 10_080, resetsIn: 6 * 86_400, bucket: "codex", language: language),
            try window("primary", used: 12, minutes: 300, resetsIn: 4 * 3_600, bucket: "codex_spark", bucketTitle: "GPT-5.3-Codex-Spark", isMain: false, language: language),
        ]
    }

    /// Four accounts with explicit tints and monograms: one letter, two letters, Cyrillic and an emoji.
    static func marks(_ language: Language) throws -> WidgetSnapshot {
        let work = language == .en ? "Work" : "Работа"
        let personal = language == .en ? "Personal" : "Личное"
        let lab = language == .en ? "Lab" : "Лаб"
        let review = language == .en ? "Review" : "Ревью"
        return snapshot([
            try account(
                "Claude · \(work)", provider: .claude, tint: .teal, monogram: language == .en ? "W" : "Р", plan: "Max",
                email: "e••••e@test.com",
                windows: try claudeWindows(language, session: 57, week: 38, fable: 63), waiting: 1
            ),
            try account(
                "Claude · \(lab)", provider: .claude, tint: .pink, monogram: "🚀", plan: "Pro",
                windows: try claudeWindows(language, session: 21, week: 12, fable: 8)
            ),
            try account(
                "Codex · \(personal)", provider: .codex, tint: .indigo, monogram: language == .en ? "P" : "Л", plan: "Pro",
                windows: try codexWindows(language, primary: 18, secondary: 84), working: 1
            ),
            try account(
                "Codex · \(review)", provider: .codex, tint: .sand, monogram: language == .en ? "RV" : "РВ",
                windows: try codexWindows(language, primary: 44, secondary: 31)
            ),
        ], language: language)
    }

    /// Two accounts whose windows forecast: one calm (medium and large only) and one that runs into the limit
    /// (drawn everywhere, small widgets included).
    static func forecast(_ language: Language) throws -> WidgetSnapshot {
        let calm = language == .en ? "Steady" : "Спокойный"
        let racing = language == .en ? "Sprint" : "Спринт"
        return snapshot([
            // 40 % spent at half the window: the ghost reaches about 80 %.
            try account(
                "Claude · \(calm)", provider: .claude, tint: .sky, monogram: language == .en ? "S" : "С", plan: "Max",
                windows: [
                    try window("session", .session, used: 40, minutes: 300, resetsIn: 150 * 60, bucket: "claude", language: language),
                    try window("week", .weekly(model: nil), used: 38, minutes: 10_080, resetsIn: 4 * 86_400, bucket: "claude", language: language),
                    try window("week.fable", .weekly(model: "Fable"), used: 22, minutes: 10_080, resetsIn: 4 * 86_400, bucket: "claude", language: language),
                ]
            ),
            // 60 % spent at 40 % of the window: the pace runs out before the reset.
            try account(
                "Codex · \(racing)", provider: .codex, tint: .lime, monogram: language == .en ? "SP" : "СП", plan: "Pro",
                windows: [
                    try window("primary", used: 60, minutes: 300, resetsIn: 180 * 60, bucket: "codex", language: language),
                    try window("secondary", used: 47, minutes: 10_080, resetsIn: 3 * 86_400, bucket: "codex", language: language),
                ],
                working: 1
            ),
        ], language: language)
    }

    /// The same two accounts with "Forecast at reset" turned off: the rings must look exactly as they do without a
    /// forecast, ghost-free, at every family.
    static func forecastOff(_ language: Language) throws -> WidgetSnapshot {
        let source = try forecast(language)
        return snapshot(source.accounts, language: language, showsForecast: false)
    }

    /// One account: the hero ring of the medium and large layouts, with its badge beside the name.
    static func single(_ language: Language) throws -> WidgetSnapshot {
        let work = language == .en ? "Work" : "Работа"
        return snapshot([
            try account(
                "Claude · \(work)", provider: .claude, tint: .slate, monogram: language == .en ? "W" : "Р", plan: "Max",
                email: "e••••e@test.com",
                windows: [
                    try window("session", .session, used: 42, minutes: 300, resetsIn: 150 * 60, bucket: "claude", language: language),
                    try window("week", .weekly(model: nil), used: 63, minutes: 10_080, resetsIn: 4 * 86_400, bucket: "claude", language: language),
                    try window("week.fable", .weekly(model: "Fable"), used: 30, minutes: 10_080, resetsIn: 4 * 86_400, bucket: "claude", language: language),
                ]
            ),
        ], language: language)
    }

    /// A reading old enough to look stale: badges stay, the ghost does not.
    static func stale(_ language: Language) throws -> WidgetSnapshot {
        let work = language == .en ? "Work" : "Работа"
        return snapshot([
            try account(
                "Claude · \(work)", provider: .claude, tint: .teal, monogram: language == .en ? "W" : "Р", plan: "Max",
                windows: [
                    try window("session", .session, used: 40, minutes: 300, resetsIn: 150 * 60, bucket: "claude", language: language),
                    try window("week", .weekly(model: nil), used: 38, minutes: 10_080, resetsIn: 4 * 86_400, bucket: "claude", language: language),
                ],
                capturedAt: -47 * 60
            ),
            try account(
                "Codex", provider: .codex, tint: .graphite, monogram: "1",
                windows: try codexWindows(language, primary: 40, secondary: 12),
                capturedAt: -47 * 60
            ),
        ], language: language)
    }

    /// A snapshot as an older build wrote it: no tint, no monogram. The provider mark comes back and
    /// the layout must not move.
    static func legacy(_ language: Language) throws -> WidgetSnapshot {
        let work = language == .en ? "Work" : "Работа"
        let personal = language == .en ? "Personal" : "Личное"
        return snapshot([
            try account(
                "Claude · \(work)", provider: .claude, tint: nil, monogram: nil, plan: "Max",
                email: "e••••e@test.com",
                windows: try claudeWindows(language, session: 57, week: 38, fable: 63), waiting: 1
            ),
            try account(
                "Codex · \(personal)", provider: .codex, tint: nil, monogram: nil, plan: "Pro",
                windows: try codexWindows(language, primary: 18, secondary: 84), working: 1
            ),
        ], language: language)
    }
}
