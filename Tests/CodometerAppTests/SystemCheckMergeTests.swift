@testable import CodometerApp
import CodometerCore
import Foundation
import Testing

/// The app's own system-check items and how they merge with the engine's report.
@Suite("System check merge")
struct SystemCheckMergeTests {
    static let now = Date(timeIntervalSince1970: 1_789_600_000)

    static func inputs(
        notifications: NotificationAuthorization = .authorized,
        loginItem: LoginItemStatus = .enabled,
        shortcut: ShortcutStatus = .active(.controlOptionCommandU),
        widget: WidgetSnapshotState = WidgetSnapshotState(isEnabled: true, modifiedAt: now.addingTimeInterval(-120), mode: 0o600),
        displays: Int = 2,
        location: AppLocationKind = .applications,
        crashReports: Int = 0,
        statusEnabled: Bool = false,
        statusFailures: Int = 0
    ) -> AppCheckInputs {
        AppCheckInputs(
            notifications: notifications,
            loginItem: loginItem,
            shortcut: shortcut,
            widget: widget,
            displayCount: displays,
            location: location,
            crashReports: crashReports,
            statusEnabled: statusEnabled,
            statusFailures: statusFailures,
            now: now
        )
    }

    // MARK: - The merge

    @Test("The app adds exactly the eight kinds the engine cannot answer")
    func appKinds() {
        let kinds = SystemCheckMerge.appItems(Self.inputs()).map(\.kind)
        #expect(kinds == [.notifications, .loginItem, .shortcut, .widgetSnapshot, .displays, .appLocation, .crashReports, .serviceStatus])
        #expect(Set(kinds).count == kinds.count)
    }

    @Test("Merged items keep the check order and every id appears once")
    func ordering() {
        let engine = SystemCheckReport(ranAt: Self.now, items: [
            SystemCheckReport.Item(id: "historyDatabase", status: .ok, kind: .historyDatabase, detail: "integrity check passed"),
            SystemCheckReport.Item(id: "claudeExecutable", status: .ok, kind: .claudeExecutable, detail: nil),
            SystemCheckReport.Item(id: "claudeProfile.A", status: .ok, kind: .claudeProfile, detail: nil),
            SystemCheckReport.Item(id: "claudeProfile.B", status: .warning, kind: .claudeProfile, detail: nil),
        ])
        let merged = SystemCheckMerge.merged(engine: engine, appItems: SystemCheckMerge.appItems(Self.inputs()), ranAt: Self.now)
        let order = Dictionary(uniqueKeysWithValues: SystemCheckItemKind.allCases.enumerated().map { ($1, $0) })
        let ranks = merged.items.map { order[$0.kind] ?? -1 }
        #expect(ranks == ranks.sorted())
        #expect(Set(merged.items.map(\.id)).count == merged.items.count)
        #expect(merged.items.count == engine.items.count + 8)
        // Two accounts with the same kind stay in id order.
        let profiles = merged.items.filter { $0.kind == .claudeProfile }.map(\.id)
        #expect(profiles == ["claudeProfile.A", "claudeProfile.B"])
    }

    @Test("The engine's run time wins, and an app item replaces an engine item with the same id")
    func replacement() {
        let engineRan = Self.now.addingTimeInterval(-30)
        let engine = SystemCheckReport(ranAt: engineRan, items: [
            SystemCheckReport.Item(id: "network", status: .warning, kind: .network, detail: "offline"),
            SystemCheckReport.Item(id: "displays", status: .failure, kind: .displays, detail: "stale"),
        ])
        let merged = SystemCheckMerge.merged(engine: engine, appItems: SystemCheckMerge.appItems(Self.inputs()), ranAt: Self.now)
        #expect(merged.ranAt == engineRan)
        #expect(merged.items.filter { $0.kind == .displays }.count == 1)
        #expect(merged.items.first { $0.kind == .displays }?.status == .ok)
        // The engine keeps the kinds the app does not answer.
        #expect(merged.items.first { $0.kind == .network }?.status == .warning)
    }

    @Test("Without an engine report the app's items still form a report")
    func engineMissing() {
        let merged = SystemCheckMerge.merged(engine: nil, appItems: SystemCheckMerge.appItems(Self.inputs()), ranAt: Self.now)
        #expect(merged.ranAt == Self.now)
        #expect(merged.items.count == 8)
    }

    @Test("The overall status is the worst item")
    func overall() {
        let good = SystemCheckMerge.merged(engine: nil, appItems: SystemCheckMerge.appItems(Self.inputs()), ranAt: Self.now)
        #expect(good.overallStatus == .ok)
        let bad = SystemCheckMerge.merged(
            engine: nil,
            appItems: SystemCheckMerge.appItems(Self.inputs(notifications: .denied, location: .diskImage)),
            ranAt: Self.now
        )
        #expect(bad.overallStatus == .warning)
    }

    // MARK: - Each item

    @Test("Notification permission")
    func notifications() {
        #expect(SystemCheckMerge.notificationsItem(.authorized).status == .ok)
        #expect(SystemCheckMerge.notificationsItem(.provisional).status == .note)
        #expect(SystemCheckMerge.notificationsItem(.notDetermined).status == .note)
        #expect(SystemCheckMerge.notificationsItem(.denied).status == .warning)
    }

    @Test("Login item")
    func loginItem() {
        #expect(SystemCheckMerge.loginItemItem(.enabled).status == .ok)
        #expect(SystemCheckMerge.loginItemItem(.disabled).status == .ok)
        #expect(SystemCheckMerge.loginItemItem(.requiresApproval).status == .warning)
        #expect(SystemCheckMerge.loginItemItem(.notFound).status == .note)
        #expect(SystemCheckMerge.loginItemItem(.unavailable).status == .note)
    }

    @Test("Shortcut status, with the number of free alternatives")
    func shortcut() {
        #expect(SystemCheckMerge.shortcutItem(.off).status == .ok)
        #expect(SystemCheckMerge.shortcutItem(.active(.controlOptionCommandU)).status == .ok)
        let macOS = SystemCheckMerge.shortcutItem(.unavailable(.controlOptionSpace, reason: .usedByMacOS, alternatives: [.controlOptionCommandU, .controlOptionCommandL]))
        #expect(macOS.status == .warning)
        #expect(macOS.detail?.contains("macOS") == true)
        #expect(macOS.detail?.contains("2 free alternatives") == true)
        let one = SystemCheckMerge.shortcutItem(.unavailable(.controlOptionSpace, reason: .usedByMacOS, alternatives: [.controlOptionCommandU]))
        // The detail is shown in the pane as well as in the report, so it never says "alternative(s)".
        #expect(one.detail?.contains("1 free alternative") == true)
        #expect(one.detail?.contains("(s)") == false)
        let other = SystemCheckMerge.shortcutItem(.unavailable(.controlOptionCommandL, reason: .usedByAnotherApp, alternatives: []))
        #expect(other.status == .warning)
        #expect(other.detail?.contains("free") == false)
        let failed = SystemCheckMerge.shortcutItem(.unavailable(.controlOptionCommandL, reason: .failed(code: -9878), alternatives: []))
        #expect(failed.detail?.contains("-9878") == true)
    }

    @Test("Widget snapshot: off, missing, stale, wrong mode, fresh")
    func widget() {
        #expect(SystemCheckMerge.widgetItem(WidgetSnapshotState(isEnabled: false, modifiedAt: nil, mode: nil), now: Self.now).status == .ok)
        #expect(SystemCheckMerge.widgetItem(WidgetSnapshotState(isEnabled: true, modifiedAt: nil, mode: nil), now: Self.now).status == .note)
        let fresh = WidgetSnapshotState(isEnabled: true, modifiedAt: Self.now.addingTimeInterval(-120), mode: 0o600)
        #expect(SystemCheckMerge.widgetItem(fresh, now: Self.now).status == .ok)
        #expect(SystemCheckMerge.widgetItem(fresh, now: Self.now).detail == "last written 2 min ago")
        let stale = WidgetSnapshotState(isEnabled: true, modifiedAt: Self.now.addingTimeInterval(-7_200), mode: 0o600)
        #expect(SystemCheckMerge.widgetItem(stale, now: Self.now).status == .note)
        let loose = WidgetSnapshotState(isEnabled: true, modifiedAt: Self.now, mode: 0o644)
        #expect(SystemCheckMerge.widgetItem(loose, now: Self.now).status == .warning)
        #expect(SystemCheckMerge.widgetItem(loose, now: Self.now).detail == "mode 0644, expected 0600")
        // A clock that ran backwards never produces a negative age.
        let future = WidgetSnapshotState(isEnabled: true, modifiedAt: Self.now.addingTimeInterval(600), mode: 0o600)
        #expect(SystemCheckMerge.widgetItem(future, now: Self.now).detail == "last written 0 min ago")
    }

    @Test("Displays, app location, crash reports and the status check")
    func remaining() {
        #expect(SystemCheckMerge.displaysItem(0).status == .note)
        #expect(SystemCheckMerge.displaysItem(3).detail == "3 connected")
        #expect(SystemCheckMerge.locationItem(.applications).status == .ok)
        #expect(SystemCheckMerge.locationItem(.userApplications).status == .ok)
        #expect(SystemCheckMerge.locationItem(.other).status == .note)
        #expect(SystemCheckMerge.locationItem(.translocated).status == .warning)
        #expect(SystemCheckMerge.locationItem(.diskImage).status == .warning)
        #expect(SystemCheckMerge.locationItem(.readOnlyVolume).status == .warning)
        #expect(SystemCheckMerge.crashItem(0).status == .ok)
        #expect(SystemCheckMerge.crashItem(2).status == .note)
        #expect(SystemCheckMerge.statusItem(enabled: false, failures: 0).status == .ok)
        #expect(SystemCheckMerge.statusItem(enabled: true, failures: 0).status == .ok)
        #expect(SystemCheckMerge.statusItem(enabled: true, failures: 1).status == .note)
        #expect(SystemCheckMerge.statusItem(enabled: true, failures: 1).detail == "on, 1 vendor check failed last time")
        #expect(SystemCheckMerge.statusItem(enabled: true, failures: 2).detail == "on, 2 vendor checks failed last time")
        // Nothing the pane shows spells a plural with "(s)".
        for item in SystemCheckMerge.appItems(Self.inputs(crashReports: 1, statusEnabled: true, statusFailures: 1)) {
            #expect(item.detail?.contains("(s)") != true, "\(item.kind): \(item.detail ?? "")")
        }
    }

    // MARK: - Redaction of the merged report

    @Test("The support text of a merged report carries no personal data unless names are asked for")
    func redaction() throws {
        let work = AccountID()
        let personal = AccountID()
        let labels = [work: "Work · example@test.com", personal: "Личный"]
        let engine = SystemCheckReport(ranAt: Self.now, items: [
            SystemCheckReport.Item(
                id: "claudeProfile.\(work)",
                status: .warning,
                kind: .claudeProfile,
                detail: "readable, sign-in state unknown: /Users/testuser/.claude/.claude.json is unreadable"
            ),
            SystemCheckReport.Item(
                id: "codexProfile.\(personal)",
                status: .ok,
                kind: .codexProfile,
                detail: "readable, signed in"
            ),
            SystemCheckReport.Item(
                id: "claudeExecutable",
                status: .ok,
                kind: .claudeExecutable,
                detail: "/Users/testuser/.local/bin/claude, signed by Anthropic PBC (Q6L2SF6YDW), version 2.1.12"
            ),
        ])
        let merged = SystemCheckMerge.merged(engine: engine, appItems: SystemCheckMerge.appItems(Self.inputs()), ranAt: Self.now)

        let redacted = merged.text(includeAccountNames: false, labels: labels)
        #expect(!redacted.contains("@"))
        #expect(!redacted.contains("/Users/"))
        #expect(!redacted.contains("testuser"))
        #expect(!redacted.contains("example@test.com"))
        #expect(!redacted.contains("Work"))
        #expect(!redacted.contains("Личный"))
        #expect(redacted.contains("Account 1"))
        #expect(redacted.contains("Claude Code profile"))
        // The app's own items are in the text, with their English titles.
        #expect(redacted.contains("Notifications"))
        #expect(redacted.contains("App location"))
        #expect(redacted.contains("Widget snapshot"))

        let named = merged.text(includeAccountNames: true, labels: labels)
        #expect(named.contains("Личный"))
        #expect(!named.contains("@"))
        #expect(!named.contains("/Users/"))
    }

    @Test("A saved file is redacted whatever the copy box said")
    func exportedTextIsRedacted() {
        let work = AccountID()
        let labels = [work: "Work · example@test.com"]
        let report = SystemCheckReport(ranAt: Self.now, items: [
            SystemCheckReport.Item(id: "claudeProfile.\(work)", status: .ok, kind: .claudeProfile, detail: "readable, signed in"),
        ])
        // The pane's box can be off while an earlier "Copy Report" had it on; a file never carries the names.
        let saved = DiagnosticsExport.text(report, labels: labels)
        #expect(!saved.contains("Work"))
        #expect(!saved.contains("@"))
        #expect(!saved.contains("/Users/"))
        #expect(saved.contains("Account 1"))
        #expect(saved == report.text(includeAccountNames: false, labels: labels))
    }

    @Test("The export file name carries only the date")
    func exportName() {
        let name = DiagnosticsExport.fileName(for: Date(timeIntervalSince1970: 1_789_600_000))
        #expect(name.hasPrefix("Codometer-diagnostics-"))
        #expect(name.hasSuffix(".txt"))
        #expect(!name.contains("/"))
        #expect(name.count == "Codometer-diagnostics-2026-09-18.txt".count)
    }
}
