import CodometerCore
import CodometerL10n
@testable import CodometerUI
import AppKit
import Foundation
import SwiftUI
import Testing

/// Measuring helpers shared by the General and Diagnostics suites: text is measured with `NSString` in the real fonts,
/// at the two widths the Settings detail column can have.
@MainActor
enum C6Measure {
    /// The detail column when the window opens (920 pt wide, 210 pt sidebar) and at its narrowest (800 pt, 250 pt).
    static let defaultDetailWidth: CGFloat = 710
    static let narrowestDetailWidth: CGFloat = 550

    static let body = NSFont.systemFont(ofSize: 13)
    static let callout = NSFont.systemFont(ofSize: 12)
    static let subheadline = NSFont.systemFont(ofSize: 11)

    /// A row's content width inside a grouped section (20 pt section inset, 10 pt row inset on each side).
    static func rowWidth(_ detail: CGFloat) -> CGFloat { detail - 2 * 20 - 2 * 10 }

    static func width(_ text: String, _ font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    /// Lines `text` takes when wrapped to `width`.
    static func lines(_ text: String, _ font: NSFont, width: CGFloat) -> Int {
        let height = (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        ).height
        let line = NSLayoutManager().defaultLineHeight(for: font)
        return Int((height / line).rounded(.up))
    }

    /// The height `text` needs, wrapped to `width`.
    static func height(_ text: String, _ font: NSFont, width: CGFloat) -> CGFloat {
        CGFloat(lines(text, font, width: width)) * NSLayoutManager().defaultLineHeight(for: font)
    }

    static let languages: [Localizer] = [.testEnglish, .testRussian]
}

/// Hosts one Settings pane off screen and writes a PNG of it, the way `SettingsPanesRenderTests` does, with the
/// appearance as a parameter so every surface is reviewed in light and dark.
@MainActor
enum SettingsPaneRenderer {
    static func render(store: TrackerStore, pane: SettingsPane, width: CGFloat, dark: Bool, to url: URL) async throws {
        let size = NSSize(width: width, height: 2_400)
        let host = NSHostingView(rootView: SettingsPaneCaptureView(store: store, pane: pane).frame(width: size.width, height: size.height))
        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: -30_000, y: -30_000), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        // Forms lay out their rows over a few runloop turns, and the pane loads its data in a task.
        for _ in 0..<14 {
            try await Task.sleep(for: .milliseconds(50))
            host.layoutSubtreeIfNeeded()
        }
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: url)
    }

    /// `<name>-<language>[-dark][-narrow].png` in `CODOMETER_SNAPSHOT_DIR`.
    static func fileName(_ name: String, language: Language, dark: Bool, narrow: Bool) -> String {
        "\(name)-\(language.rawValue)\(dark ? "-dark" : "")\(narrow ? "-narrow" : "").png"
    }
}

/// A store for the settings renders: two accounts, synthetic labels, no real profile anywhere.
@MainActor
enum C6Store {
    static let now = Date(timeIntervalSince1970: 1_789_590_000)

    static func make(
        language: LanguagePreference,
        region: Locale,
        accounts: Int = 2,
        loadDiagnostics: @escaping @MainActor () async -> EngineDiagnostics? = { nil },
        runSystemCheck: @escaping @MainActor () async -> SystemCheckReport? = { nil },
        crashReports: [CrashReportSummary] = [],
        loginItem: LoginItemStatus = .enabled,
        build: AppBuildInfo = AppBuildInfo(version: "1.0.0", build: "1790000000", locationKind: .applications, licenseName: nil),
        change: (inout AppSettings) throws(ValidationError) -> Void = { _ in }
    ) throws -> TrackerStore {
        let claude = try AccountProfile(
            id: UIFixture.accountID("c6/claude"),
            provider: .claude,
            label: try AccountLabel(validating: "Work"),
            directory: try ProfileDirectory(validating: "/Users/me/.claude")
        )
        let codex = try AccountProfile(
            id: UIFixture.accountID("c6/codex"),
            provider: .codex,
            label: try AccountLabel(validating: "Personal"),
            directory: try ProfileDirectory(validating: "/Users/me/.codex")
        )
        let profiles = Array([claude, codex].prefix(accounts))
        var settings = try AppSettings(accounts: profiles)
        settings.general.language = language
        settings.appearance.surface = .solid
        let reading = try UsageReading(
            capturedAt: now.addingTimeInterval(-60),
            source: .claudeUsageCommand,
            buckets: [try LimitBucket(id: "claude", title: nil, windows: [
                try LimitWindow(id: "session", scope: .session, used: try Percentage(validating: 64), duration: .fiveHours, resetsAt: now.addingTimeInterval(8_040)),
            ], isLimitReached: false)],
            credits: nil
        )
        let state = TrackerState(accounts: profiles.map {
            AccountStatus(profile: $0, reading: reading, nextRefreshAt: now.addingTimeInterval(180))
        })
        let store = TrackerStore(
            state: state,
            settings: settings,
            now: now,
            actions: TrackerActions(
                refresh: { _ in },
                persistSettings: { _ in },
                discoverProfiles: { [] },
                revealDataFolder: {},
                setLaunchAtLogin: { _ in nil },
                openSettings: {},
                quit: {},
                loadDiagnostics: loadDiagnostics,
                runSystemCheck: runSystemCheck,
                appBuildInfo: { build },
                recentCrashReports: { crashReports },
                loginItemStatus: { loginItem }
            ),
            preferredLanguages: { ["en-US"] },
            region: { region }
        )
        store.updateSettings(change)
        return store
    }
}

/// The General pane drawn whole, in English and Russian, light and dark, with the shortcut working and with a
/// conflict. Runs only with `CODOMETER_SNAPSHOT_DIR`.
@MainActor
@Suite("General pane renders", .enabled(if: ProcessInfo.processInfo.environment["CODOMETER_SNAPSHOT_DIR"] != nil))
struct GeneralSnapshotTests {
    private let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODOMETER_SNAPSHOT_DIR"] ?? "/tmp", isDirectory: true)

    @Test("General in both languages, light and dark, working and in conflict")
    func renderGeneral() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (preference, region) in [(LanguagePreference.english, "en_US"), (.russian, "ru_RU")] {
            for dark in [false, true] {
                let active = try C6Store.make(language: preference, region: Locale(identifier: region))
                active.setShortcutStatus(.active(.controlOptionCommandU))
                try await render(active, name: "settings-general-active", dark: dark, narrow: false)

                let conflict = try C6Store.make(
                    language: preference,
                    region: Locale(identifier: region),
                    loginItem: .requiresApproval,
                    build: AppBuildInfo(version: "1.0.0", build: "1790000000", locationKind: .applications, licenseName: "MIT"),
                    change: { $0.general.globalShortcut = .controlOptionSpace }
                )
                conflict.setShortcutStatus(.unavailable(
                    .controlOptionSpace,
                    reason: .usedByMacOS,
                    alternatives: [.controlOptionCommandU, .controlOptionCommandL]
                ))
                conflict.setEnergy(EnergyPolicy.decide(
                    PowerSnapshot(lowPowerMode: true, onBattery: true, batteryPercent: try Percentage(validating: 22), thermal: .nominal),
                    mode: .automatic
                ))
                try await render(conflict, name: "settings-general-conflict", dark: dark, narrow: false)
            }
            // The narrowest column, where truncation shows first.
            let narrow = try C6Store.make(
                language: preference,
                region: Locale(identifier: region),
                change: { $0.general.globalShortcut = .controlOptionSpace }
            )
            narrow.setShortcutStatus(.unavailable(.controlOptionSpace, reason: .usedByAnotherApp, alternatives: [.controlOptionCommandU, .controlOptionCommandL]))
            try await render(narrow, name: "settings-general-conflict", dark: false, narrow: true)
        }
    }

    private func render(_ store: TrackerStore, name: String, dark: Bool, narrow: Bool) async throws {
        let file = SettingsPaneRenderer.fileName(name, language: store.localizer.language, dark: dark, narrow: narrow)
        try await SettingsPaneRenderer.render(
            store: store,
            pane: .general,
            width: narrow ? C6Measure.narrowestDetailWidth : C6Measure.defaultDetailWidth,
            dark: dark,
            to: directory.appendingPathComponent(file)
        )
    }
}

/// Text of the General pane's new rows in both languages, and whether each one fits the room reserved for it.
@MainActor
@Suite("General pane copy")
struct GeneralCopyTests {
    /// The caption sits next to a `Label` icon, which takes about 20 pt at the callout size.
    static let captionWidth = C6Measure.rowWidth(C6Measure.narrowestDetailWidth) - 20

    @Test("Every energy state line fits the two lines the section reserves")
    func energyStates() {
        for l10n in C6Measure.languages {
            for reason in EnergyDecision.Reason.allCases {
                let decision = EnergyDecision(factor: .normal, urgentCapFactor: .normal, reason: reason, pausesLiveEffects: false)
                let text = EnergySection.state(decision, l10n: l10n)
                let height = C6Measure.height(text, C6Measure.callout, width: Self.captionWidth)
                #expect(height <= EnergySection.stateHeight, "\(l10n.language) \(reason): \(text)")
            }
        }
    }

    @Test("The energy modes fit a segmented control at the narrowest width")
    func energyModes() {
        for l10n in C6Measure.languages {
            let widest = EnergyMode.allCases.map { C6Measure.width(EnergySection.title($0, l10n: l10n), C6Measure.body) }.max() ?? 0
            // A segmented control makes every segment as wide as the widest title plus 20 pt of padding.
            let needed = (widest + 20) * CGFloat(EnergyMode.allCases.count)
            #expect(needed <= C6Measure.rowWidth(C6Measure.narrowestDetailWidth), "\(l10n.language): \(needed)")
        }
    }

    @Test("Every shortcut caption fits the two lines reserved under the key caps")
    func shortcutCaptions() {
        for l10n in C6Measure.languages {
            var statuses: [ShortcutStatus] = [.off, .active(.controlOptionCommandU), .active(.controlOptionSpace)]
            for shortcut in SettingsCopy.shortcutChoices where shortcut != .off {
                statuses.append(.unavailable(shortcut, reason: .usedByMacOS, alternatives: []))
                statuses.append(.unavailable(shortcut, reason: .usedByAnotherApp, alternatives: []))
                statuses.append(.unavailable(shortcut, reason: .failed(code: -9878), alternatives: []))
            }
            for status in statuses {
                let text = ShortcutKeys.caption(status, l10n: l10n)
                let height = C6Measure.height(text, C6Measure.callout, width: Self.captionWidth)
                #expect(height <= SettingsMetrics.shortcutCaption, "\(l10n.language): \(text)")
            }
        }
    }

    @Test("Key caps, “Try:” and every alternative fit one row at the narrowest width")
    func alternativesRow() {
        for l10n in C6Measure.languages {
            // The worst case: the widest shortcut plus the other three offered as alternatives.
            let caps = ShortcutKeys.keys(.controlOptionSpace, l10n: l10n)
            let capsWidth = caps.reduce(CGFloat(0)) { total, key in
                total + max(28, C6Measure.width(key.cap, C6Measure.body) + 18) + 6
            }
            let alternatives: [GlobalShortcut] = [.controlOptionCommandU, .controlOptionCommandL]
            let buttons = alternatives.reduce(CGFloat(0)) { total, shortcut in
                total + C6Measure.width(ShortcutKeys.title(shortcut, l10n: l10n), C6Measure.body) + 28 + 6
            }
            let total = capsWidth + C6Measure.width(l10n.shortcut.tryInstead, C6Measure.callout) + 12 + buttons
            #expect(total <= C6Measure.rowWidth(C6Measure.narrowestDetailWidth), "\(l10n.language): \(total)")
        }
    }

    @Test("The login-item approval row leaves room for its button")
    func loginApprovalRow() {
        for l10n in C6Measure.languages {
            let button = C6Measure.width(l10n.general.allowInSystemSettings, C6Measure.body) + 28
            let text = C6Measure.rowWidth(C6Measure.narrowestDetailWidth) - button - 18
            #expect(text > 120, "\(l10n.language): only \(text) pt left for the explanation")
            #expect(C6Measure.lines(l10n.general.loginItemNeedsApproval, C6Measure.callout, width: text) <= 2, "\(l10n.language)")
        }
    }

    @Test("The version row and its Copy button fit one line")
    func aboutRow() {
        for l10n in C6Measure.languages {
            let version = l10n.general.versionAndBuild(version: "1.0.0", build: "1790000000")
            let row = C6Measure.width(l10n.general.versionTitle, C6Measure.body) + 34
                + C6Measure.width(version, C6Measure.body)
                + C6Measure.width(l10n.common.copy, C6Measure.body) + 28 + 20
            #expect(row <= C6Measure.rowWidth(C6Measure.narrowestDetailWidth), "\(l10n.language): \(row)")
            #expect(!version.contains("Codometer"))
        }
    }

    @Test("The language section names both languages in their own language, and offers a relaunch")
    func languageSection() {
        #expect(Localizer.testRussian.languageSettings.nativeName(.en) == "English")
        #expect(Localizer.testEnglish.languageSettings.nativeName(.ru) == "Русский")
        #expect(Localizer.testEnglish.languageSettings.relaunch == "Relaunch Codometer")
        #expect(Localizer.testRussian.languageSettings.relaunch.contains("Codometer"))
    }

    @Test("A status left over from another combination never blames the chosen keys")
    func statusRule() {
        let reported = ShortcutStatus.unavailable(.controlOptionSpace, reason: .usedByMacOS, alternatives: [.controlOptionCommandU])
        #expect(GeneralPane.status(reported, for: .controlOptionSpace) == reported)
        #expect(GeneralPane.status(reported, for: .controlOptionCommandL) == .active(.controlOptionCommandL))
        #expect(GeneralPane.status(reported, for: .off) == .off)
        #expect(GeneralPane.status(.off, for: .controlOptionCommandU) == .active(.controlOptionCommandU))
        #expect(GeneralPane.status(.active(.controlOptionCommandU), for: .controlOptionCommandU) == .active(.controlOptionCommandU))
    }

    @Test("English copy avoids the traps of a literal translation")
    func englishTone() {
        let en = Localizer.testEnglish
        #expect(en.energy.modeAlwaysFresh == "Always fresh")
        #expect(en.energy.modeSaveBattery == "Save battery")
        #expect(en.general.showWelcomeGuide == "Show Welcome Guide…")
        #expect(en.general.aboutTitle == "About")
        #expect(en.energy.stateBattery.hasSuffix("."))
    }

    @Test("Every caption under the key caps is a sentence, in both languages")
    func captionsAreSentences() {
        // The slot holds a conflict explanation, the ⌃⌥Space caution or "Works from any app.": one shape for all
        // three, so the row never mixes a fragment with a sentence.
        for l10n in C6Measure.languages {
            let statuses: [ShortcutStatus] = [
                .off,
                .active(.controlOptionCommandU),
                .active(.controlOptionSpace),
                .unavailable(.controlOptionSpace, reason: .usedByMacOS, alternatives: [.controlOptionCommandU]),
            ]
            for status in statuses {
                // A sentence, not a fragment. ("macOS often uses…" opens with a brand name, so only the full stop
                // can be checked mechanically.)
                let caption = ShortcutKeys.caption(status, l10n: l10n)
                #expect(caption.hasSuffix("."), "\(l10n.language): \(caption)")
            }
        }
    }

    @Test("Russian copy keeps «вы», ё and the infinitive")
    func russianTone() {
        let ru = Localizer.testRussian
        #expect(ru.energy.title == "Энергопотребление")
        #expect(ru.general.showWelcomeGuide.hasSuffix("…"))
        #expect(ru.general.allowInSystemSettings.hasPrefix("Разрешить"))
        #expect(ru.shortcut.tryInstead == "Попробуйте:")
        #expect(!ru.energy.stateLowPower.contains("Вы "))
    }
}
