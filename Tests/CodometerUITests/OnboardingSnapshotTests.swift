import CodometerCore
import CodometerL10n
@testable import CodometerUI
import AppKit
import Foundation
import SwiftUI
import Testing

/// Every step of the welcome flow at the real window size, in English and Russian, light and dark. Runs only with
/// `CODOMETER_SNAPSHOT_DIR`; writes `onboarding-<step>-<light|dark>-<en|ru>.png`.
///
/// Readiness is synthetic, so no real profile or plan name is ever drawn.
@MainActor
@Suite("Onboarding renders", .serialized, .enabled(if: ProcessInfo.processInfo.environment["CODOMETER_SNAPSHOT_DIR"] != nil))
struct OnboardingSnapshotTests {
    private let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODOMETER_SNAPSHOT_DIR"] ?? "/tmp", isDirectory: true)
    private let home = "/Users/tester"

    /// One picture: which step, how far into the wizard, and which synthetic readiness it needs.
    private struct Shot {
        let name: String
        let step: OnboardingStep
        var readiness: (@MainActor (String) -> [ProfileReadiness])?
        var wizard: (@MainActor (OnboardingModel) -> Void)?
    }

    /// The fixture with the second Claude folder already signed in, for the wizard's last stage.
    @MainActor
    private static func signedInWork(home: String) -> [ProfileReadiness] {
        OnboardingModel.fixtureReadiness(home: home).map { entry in
            guard entry.directory.lastComponent == ".claude-work" else { return entry }
            return ProfileReadiness(
                provider: entry.provider,
                directory: entry.directory,
                state: .signedIn(plan: "Max"),
                cli: nil
            )
        }
    }

    private var shots: [Shot] {
        [
            Shot(name: "welcome", step: .welcome),
            Shot(name: "found", step: .found),
            Shot(name: "presentation", step: .presentation),
            Shot(name: "second-account", step: .secondAccount),
            Shot(name: "second-account-service", step: .secondAccount, wizard: { model in
                model.startWizard()
            }),
            Shot(name: "second-account-name", step: .secondAccount, wizard: { model in
                model.startWizard()
                model.chooseService(.claude)
            }),
            // A folder the fixture does not know: the wizard shows the commands.
            Shot(name: "second-account-sign-in", step: .secondAccount, wizard: { model in
                model.startWizard()
                model.chooseService(.claude)
                model.setSuffixText("night")
                model.confirmProfileName()
            }),
            // A folder that exists but has no sign-in yet: the wizard waits instead.
            Shot(name: "second-account-waiting", step: .secondAccount, wizard: { model in
                model.startWizard()
                model.chooseService(.claude)
                model.setSuffixText("work")
                model.confirmProfileName()
            }),
            Shot(name: "second-account-detected", step: .secondAccount, readiness: Self.signedInWork, wizard: { model in
                model.startWizard()
                model.chooseService(.claude)
                model.setSuffixText("work")
                model.confirmProfileName()
            }),
            Shot(name: "notifications", step: .notifications),
            Shot(name: "done", step: .done),
        ]
    }

    @Test("Every step and wizard stage, in both languages and both appearances")
    func render() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (preference, suffix, region) in [(LanguagePreference.english, "en", "en_US"), (.russian, "ru", "ru_RU")] {
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let mode = appearance == .darkAqua ? "dark" : "light"
                for shot in shots {
                    let store = try makeStore(language: preference, region: Locale(identifier: region))
                    #expect(store.localizer.language.rawValue == suffix)
                    let model = OnboardingModel(store: store, homePath: home)
                    model.installFixtureReadiness(shot.readiness?(home))
                    model.go(to: shot.step)
                    shot.wizard?(model)
                    try await render(model: model, appearance: appearance, name: "onboarding-\(shot.name)-\(mode)-\(suffix)")
                }
            }
        }
    }

    private func render(model: OnboardingModel, appearance: NSAppearance.Name, name: String) async throws {
        let l10n = model.store.localizer
        let size = NSSize(width: OnboardingView.Layout.windowWidth, height: OnboardingView.Layout.windowHeight)
        let host = NSHostingView(
            rootView: OnboardingView(model: model)
                .environment(\.l10n, l10n)
                .environment(\.locale, l10n.locale)
                .frame(width: size.width, height: size.height)
        )
        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: -30_000, y: -30_000), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        for _ in 0..<12 {
            try await Task.sleep(for: .milliseconds(40))
            host.layoutSubtreeIfNeeded()
        }
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }

    /// One tracked Claude account, so the "Found on this Mac" step shows both a tracked row and untracked folders.
    private func makeStore(language: LanguagePreference, region: Locale) throws -> TrackerStore {
        let claude = try AccountProfile(
            id: UIFixture.accountID("onboarding/claude"),
            provider: .claude,
            label: try AccountLabel(validating: "Claude"),
            directory: try ProfileDirectory(validating: home + "/.claude")
        )
        var settings = try AppSettings(accounts: [claude])
        settings.general.language = language
        settings.appearance.surface = .solid
        return TrackerStore(
            state: .empty,
            settings: settings,
            now: Date(timeIntervalSince1970: 1_789_590_000),
            actions: UIFixture.actions(),
            preferredLanguages: { ["en-US"] },
            region: { region }
        )
    }
}
