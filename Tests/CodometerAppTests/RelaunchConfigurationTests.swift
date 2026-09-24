@testable import CodometerApp
import CodometerCore
import CodometerL10n
import CodometerUI
import AppKit
import Foundation
import SwiftUI
import Testing

/// What a relaunched instance is started with: the argument that names this process, and the environment it inherits.
@Suite("Relaunch configuration")
struct RelaunchConfigurationTests {
    private let isolated = [
        "CODOMETER_DATA_ROOT": "/tmp/codometer/data",
        "CODOMETER_HARNESS_LOCK": "/tmp/codometer/harness.lock",
        "CODOMETER_DEBUG_SCENARIO": "/tmp/scenario.json",
        "CODOMETER_DEBUG_OUT": "/tmp/out",
        "CODOMETER_DEBUG_CAPTURE": "view",
        "CODOMETER_DEBUG_STANDARD_ROOT": "1",
        "PATH": "/usr/bin",
        "HOME": "/Users/tester",
    ]

    @Test("The argument carries this process's id, so the new instance can wait for it")
    func arguments() {
        let configuration = RelaunchConfiguration.make(pid: 4_321, isIsolated: false, environment: [:])
        #expect(configuration.arguments == ["--relaunched-after", "4321"])
        #expect(RelaunchConfiguration.relaunchArgument == "--relaunched-after")
    }

    @Test("An isolated root carries its own variables on and drops every debug one")
    func isolatedEnvironment() {
        let configuration = RelaunchConfiguration.make(pid: 1, isIsolated: true, environment: isolated)
        #expect(configuration.environment["CODOMETER_DATA_ROOT"] == "/tmp/codometer/data")
        #expect(configuration.environment["CODOMETER_HARNESS_LOCK"] == "/tmp/codometer/harness.lock")
        #expect(configuration.environment["CODOMETER_DEBUG_SCENARIO"] == nil)
        #expect(configuration.environment["CODOMETER_DEBUG_OUT"] == nil)
        #expect(configuration.environment["CODOMETER_DEBUG_CAPTURE"] == nil)
        #expect(configuration.environment["CODOMETER_DEBUG_STANDARD_ROOT"] == nil)
        // Nothing that is not ours travels.
        #expect(configuration.environment["PATH"] == nil)
        #expect(configuration.environment["HOME"] == nil)
        #expect(configuration.environment.count == 2)
    }

    @Test("A standard root carries nothing, so the new instance reads the real settings as usual")
    func standardEnvironment() {
        let configuration = RelaunchConfiguration.make(pid: 1, isIsolated: false, environment: isolated)
        #expect(configuration.environment.isEmpty)
    }

    @Test("Other CODOMETER variables of an isolated run travel with it")
    func otherVariables() {
        let environment = ["CODOMETER_DATA_ROOT": "/tmp/root", "CODOMETER_L10N_PSEUDO": "1"]
        let configuration = RelaunchConfiguration.make(pid: 7, isIsolated: true, environment: environment)
        #expect(configuration.environment == environment)
    }
}

/// The export save panel's file name.
@MainActor
@Suite("Export file name")
struct ExportFileNameTests {
    private let noon = Date(timeIntervalSince1970: 1_789_590_000)

    @Test("JSON gets an extension, a CSV export is a folder", arguments: [Localizer.testEnglish, .testRussian])
    func names(l10n: Localizer) {
        let json = AppController.exportName(.json, l10n: l10n, now: noon)
        let folder = AppController.exportName(.csvFolder, l10n: l10n, now: noon)
        #expect(json.hasSuffix(".json"))
        #expect(!folder.contains("."))
        #expect(json.dropLast(5) == folder)
        // The fixture instant's calendar date in the test localizers' GMT time zone.
        #expect(folder.hasSuffix("2026-09-16"))
        #expect(folder.contains("Codometer"))
    }
}


/// The export save panel's accessory view, drawn in English and Russian, light and dark, for review. Runs only with
/// `CODOMETER_SNAPSHOT_DIR`; writes `export-accessory-<light|dark>-<en|ru>.png`.
///
/// The panel itself is AppKit's and cannot be captured by the debug harness (it is not one of the harness's named
/// windows), so its accessory is drawn here instead.
@MainActor
@Suite("Export accessory renders", .serialized, .enabled(if: ProcessInfo.processInfo.environment["CODOMETER_SNAPSHOT_DIR"] != nil))
struct ExportAccessorySnapshotTests {
    private let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODOMETER_SNAPSHOT_DIR"] ?? "/tmp", isDirectory: true)

    @Test("Both formats and the account-name toggle, in both languages and both appearances")
    func render() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for l10n in [Localizer.testEnglish, .testRussian] {
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let mode = appearance == .darkAqua ? "dark" : "light"
                let options = ExportPanelOptions()
                options.format = .csvFolder
                let size = NSSize(width: 440, height: 86)
                let host = NSHostingView(
                    rootView: ExportOptionsView(options: options) { _ in }
                        .environment(\.l10n, l10n)
                        .environment(\.locale, l10n.locale)
                        .frame(width: size.width, height: size.height)
                        .background(.background)
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
                for _ in 0..<10 {
                    try await Task.sleep(for: .milliseconds(40))
                    host.layoutSubtreeIfNeeded()
                }
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let png = try #require(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: directory.appendingPathComponent("export-accessory-\(mode)-\(l10n.language.rawValue).png"))
            }
        }
    }
}
