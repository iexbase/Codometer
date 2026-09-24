import CodometerCore
import CodometerL10n
@testable import CodometerUI
import AppKit
import Foundation
import SwiftUI
import Testing

/// The vendor status chip and the Network settings section: what they say, what they reserve, and what they show.
@MainActor
@Suite("Service status chip")
struct ServiceStatusChipTests {
    private let now = Date(timeIntervalSince1970: 1_789_590_000)

    @Test("The chip's template is at least as wide as every vendor and level, in both languages",
          arguments: [0.85, 1.0, 1.5], [Localizer.testEnglish, .testRussian])
    func chipTemplateFits(scale: Double, l10n: Localizer) {
        let size = IslandMetrics(scale: scale).textSize(TextSize.caption)
        let template = TextFit.width(l10n.serviceStatus.chipTemplate, size: size, weight: .medium, monospacedDigits: false)
        var widest = ""
        var widestWidth: CGFloat = 0
        for provider in ProviderKind.allCases {
            for level in ServiceStatusLevel.allCases {
                let text = l10n.serviceStatus.chip(
                    vendor: UsageFormat.providerName(provider),
                    level: ServiceStatusText.name(level, l10n: l10n)
                )
                let width = TextFit.width(text, size: size, weight: .medium, monospacedDigits: false)
                if width > widestWidth { (widest, widestWidth) = (text, width) }
            }
        }
        #expect(widestWidth <= template + 0.01, "\(l10n.language): “\(widest)” \(widestWidth) pt, template \(template) pt")
    }

    @Test("The header shows the worst trouble of a vendor the user actually tracks")
    func picksWorstTrackedVendor() throws {
        let claude = try account(.claude)
        let codex = try account(.codex)
        var board = ServiceStatusBoard.empty
        board.statuses[.claude] = status(.claude, .degraded)
        board.statuses[.codex] = status(.codex, .majorOutage)

        #expect(DeckStatus.current(board: board, accounts: [claude, codex], now: now)?.provider == .codex)
        // Codex is not tracked: its outage is none of the user's business.
        #expect(DeckStatus.current(board: board, accounts: [claude], now: now)?.provider == .claude)
        #expect(DeckStatus.current(board: board, accounts: [codex], now: now)?.provider == .codex)
        // A disabled account counts as untracked.
        let disabled = try claude.updated(isEnabled: false)
        #expect(DeckStatus.current(board: board, accounts: [disabled], now: now) == nil)
        #expect(DeckStatus.current(board: board, accounts: [], now: now) == nil)

        // Equally bad: Claude comes first, so the chip does not flip between vendors.
        board.statuses[.codex] = status(.codex, .degraded)
        #expect(DeckStatus.current(board: board, accounts: [claude, codex], now: now)?.provider == .claude)
    }

    @Test("Nothing shows for a healthy vendor or a reading older than half an hour")
    func hidesHealthyAndStale() throws {
        let claude = try account(.claude)
        var board = ServiceStatusBoard.empty
        board.statuses[.claude] = ServiceStatus(provider: .claude, level: nil, affectedComponents: [], checkedAt: now)
        #expect(DeckStatus.current(board: board, accounts: [claude], now: now) == nil)

        board.statuses[.claude] = status(.claude, .majorOutage, checkedAt: now.addingTimeInterval(-29 * 60))
        #expect(DeckStatus.current(board: board, accounts: [claude], now: now) != nil)
        board.statuses[.claude] = status(.claude, .majorOutage, checkedAt: now.addingTimeInterval(-31 * 60))
        #expect(DeckStatus.current(board: board, accounts: [claude], now: now) == nil)
    }

    @Test("The tooltip names the components, or the vendor when the page named none", arguments: [Localizer.testEnglish, .testRussian])
    func tooltipSubject(l10n: Localizer) {
        let named = ServiceStatus(provider: .claude, level: .partialOutage, affectedComponents: ["Claude Code", "Claude API"], checkedAt: now)
        let subject = DeckStatus.subject(of: named, l10n: l10n)
        #expect(subject.contains("Claude Code"))
        #expect(subject.contains("Claude API"))
        let anonymous = ServiceStatus(provider: .codex, level: .degraded, affectedComponents: [], checkedAt: now)
        #expect(DeckStatus.subject(of: anonymous, l10n: l10n) == "Codex")

        let tooltip = l10n.serviceStatus.tooltip(
            components: subject,
            level: ServiceStatusText.inSentence(.partialOutage, l10n: l10n),
            host: VendorStatusFeed.host(for: .claude),
            ago: l10n.format.ago(now.addingTimeInterval(-180), now: now)
        )
        #expect(tooltip.contains("status.claude.com"))
        #expect(tooltip.contains("Claude Code"))
        switch l10n.language {
        case .en: #expect(tooltip == "Claude Code and Claude API: partial outage — from status.claude.com, checked 3 min ago")
        case .ru: #expect(tooltip == "Claude Code и Claude API: частичный сбой — по данным status.claude.com, проверено 3\u{00A0}мин назад")
        }
    }

    @Test("Every level has its own words in both languages, standalone and inside a sentence")
    func levelWords() {
        for l10n in [Localizer.testEnglish, .testRussian] {
            let names = ServiceStatusLevel.allCases.map { ServiceStatusText.name($0, l10n: l10n) }
            let inSentence = ServiceStatusLevel.allCases.map { ServiceStatusText.inSentence($0, l10n: l10n) }
            #expect(Set(names).count == ServiceStatusLevel.allCases.count)
            #expect(Set(inSentence).count == ServiceStatusLevel.allCases.count)
            #expect(names.allSatisfy { !$0.isEmpty })
            // Sentence case on its own, lower case inside a sentence.
            for (name, inside) in zip(names, inSentence) {
                #expect(name.first?.isUppercase == true, "\(l10n.language): \(name)")
                #expect(inside.first?.isLowercase == true, "\(l10n.language): \(inside)")
                #expect(name.lowercased() == inside.lowercased())
            }
        }
        #expect(ServiceStatusText.name(.majorOutage, l10n: .testEnglish) == "Major outage")
        #expect(ServiceStatusText.name(.majorOutage, l10n: .testRussian) == "Серьёзный сбой")
    }

    @Test("The Network section names both hosts in both languages")
    func networkDisclosure() {
        for l10n in [Localizer.testEnglish, .testRussian] {
            let hosts = NetworkSection.hostList(l10n: l10n)
            #expect(hosts.contains("status.claude.com"))
            #expect(hosts.contains("status.openai.com"))
            let disclosure = l10n.network.disclosure(hosts: hosts)
            #expect(disclosure.contains("status.claude.com"))
            #expect(disclosure.contains("status.openai.com"))
            // The honest part: the sites see an address, and nothing else leaves the Mac.
            #expect(disclosure.contains(l10n.pick(en: "IP address", ru: "IP-адрес")))
            #expect(disclosure.contains("10"))
        }
    }

    // MARK: - Fixtures

    private func account(_ provider: ProviderKind) throws -> AccountProfile {
        try AccountProfile(
            id: UIFixture.accountID("status/\(provider.rawValue)"),
            provider: provider,
            label: try AccountLabel(validating: provider == .claude ? "Work" : "Personal"),
            directory: try ProfileDirectory(validating: provider == .claude ? "/Users/me/.claude" : "/Users/me/.codex")
        )
    }

    private func status(_ provider: ProviderKind, _ level: ServiceStatusLevel, checkedAt: Date? = nil) -> ServiceStatus {
        ServiceStatus(
            provider: provider,
            level: level,
            affectedComponents: provider == .claude ? ["Claude Code"] : ["CLI"],
            checkedAt: checkedAt ?? now.addingTimeInterval(-180)
        )
    }
}

/// Renders the chip in the deck header and the Network settings section in English and Russian, for review.
/// Runs only with `CODOMETER_SNAPSHOT_DIR`.
@MainActor
@Suite("Service status snapshots", .enabled(if: ProcessInfo.processInfo.environment["CODOMETER_SNAPSHOT_DIR"] != nil))
struct StatusChipSnapshotTests {
    private let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODOMETER_SNAPSHOT_DIR"] ?? "/tmp", isDirectory: true)
    private let now = Date(timeIntervalSince1970: 1_789_590_000)

    @Test("The deck header with every status level, and with the setting on but nothing wrong",
          arguments: [LanguagePreference.english, .russian])
    func renderHeader(language: LanguagePreference) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cases: [(String, ServiceStatusBoard)] = [
            ("none", .empty),
            ("degraded", board(.codex, .degraded, components: ["CLI"])),
            ("partial", board(.claude, .partialOutage, components: ["Claude Code"])),
            ("major", board(.claude, .majorOutage, components: ["Claude Code", "Claude API (api.anthropic.com)"])),
            ("maintenance", board(.codex, .maintenance, components: ["Codex API"])),
        ]
        for scheme in [ColorScheme.light, .dark] {
            for (name, board) in cases {
                let store = try makeStore(language: language)
                store.setServiceStatus(board)
                let suffix = "\(scheme == .dark ? "dark" : "light")-\(store.localizer.language.rawValue)"
                try render(
                    header(store: store),
                    name: "status-chip-\(name)-\(suffix)",
                    scheme: scheme,
                    l10n: store.localizer
                )
            }
        }
        // The whole expanded deck with a chip, so the header's balance can be judged in context.
        let store = try makeStore(language: language)
        store.setServiceStatus(board(.claude, .partialOutage, components: ["Claude Code"]))
        let model = IslandModel(layout: IslandLayout(edge: .top, anchor: .top, style: .floating, metrics: IslandMetrics(scale: 1)))
        try render(
            DeckContent(store: store, model: model, accounts: store.presentations, context: .island)
                .background(RoundedRectangle(cornerRadius: model.layout.metrics.deckCorner, style: .continuous).fill(.regularMaterial)),
            name: "status-deck-partial-light-\(store.localizer.language.rawValue)",
            scheme: .light,
            l10n: store.localizer
        )
    }

    @Test("The Network section, off and on, in both languages", arguments: [LanguagePreference.english, .russian])
    func renderNetworkSection(language: LanguagePreference) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for isOn in [false, true] {
            let store = try makeStore(language: language)
            store.updateSettings { $0.general.showsVendorStatus = isOn }
            let name = "settings-network-\(isOn ? "on" : "off")-\(store.localizer.language.rawValue)"
            try await renderForm(store: store, name: name)
        }
    }

    // MARK: - Helpers

    private func header(store: TrackerStore) -> some View {
        let metrics = IslandMetrics(scale: 1)
        return DeckHeader(store: store, accounts: store.presentations, context: .island, metrics: metrics)
            .padding(metrics.deckPadding)
            .frame(width: metrics.deckWidth, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: metrics.deckCorner, style: .continuous).fill(.regularMaterial))
    }

    private func board(_ provider: ProviderKind, _ level: ServiceStatusLevel, components: [String]) -> ServiceStatusBoard {
        var board = ServiceStatusBoard.empty
        board.statuses[provider] = ServiceStatus(
            provider: provider,
            level: level,
            affectedComponents: components,
            checkedAt: now.addingTimeInterval(-180)
        )
        return board
    }

    private func render(_ view: some View, name: String, scheme: ColorScheme, l10n: Localizer) throws {
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
        let image = try #require(renderer.cgImage)
        let bitmap = NSBitmapImageRep(cgImage: image)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }

    /// `ImageRenderer` cannot draw a `Form`, so the section is hosted off screen and cached, like the Settings panes.
    private func renderForm(store: TrackerStore, name: String) async throws {
        let size = NSSize(width: 710, height: 420)
        let content = Form {
            NetworkSection(store: store)
        }
        .formStyle(.grouped)
        .environment(\.l10n, store.localizer)
        .environment(\.locale, store.localizer.locale)
        .frame(width: size.width, height: size.height)
        let host = NSHostingView(rootView: content)
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

    private func makeStore(language: LanguagePreference) throws -> TrackerStore {
        let claude = try AccountProfile(
            id: UIFixture.accountID("status-deck/claude"),
            provider: .claude,
            label: try AccountLabel(validating: "Work"),
            directory: try ProfileDirectory(validating: "/Users/me/.claude")
        )
        let codex = try AccountProfile(
            id: UIFixture.accountID("status-deck/codex"),
            provider: .codex,
            label: try AccountLabel(validating: "Personal"),
            directory: try ProfileDirectory(validating: "/Users/me/.codex")
        )
        var settings = try AppSettings(accounts: [claude, codex])
        settings.general.language = language
        settings.general.showsVendorStatus = true
        settings.appearance.surface = .solid
        let reading = try UsageReading(
            capturedAt: now.addingTimeInterval(-120),
            source: .claudeUsageCommand,
            buckets: [try LimitBucket(id: "claude", title: nil, windows: [
                try LimitWindow(id: "session", scope: .session, used: try Percentage(validating: 64), duration: .fiveHours, resetsAt: now.addingTimeInterval(8_040)),
            ], isLimitReached: false)],
            credits: nil
        )
        let codexReading = try UsageReading(
            capturedAt: now.addingTimeInterval(-60),
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
            region: { Locale(identifier: language == .russian ? "ru_RU" : "en_US") }
        )
    }
}
