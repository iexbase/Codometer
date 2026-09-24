import CodometerCore
import CodometerEngine
import CodometerPlatform
import CodometerUI
import AppKit
import Darwin
import Foundation
import UniformTypeIdentifiers
import os

/// State of the Diagnostics pane's app-level checks.
@MainActor
final class DiagnosticsCoordinator {
    init() {}

    /// The last "Check System" result, so "Export Diagnostics…" saves exactly what the pane shows.
    var lastReport: SystemCheckReport?

    #if DEBUG
    /// Synthetic diagnostics and check results a debug scenario installed; nothing real is collected while it is set.
    var fixture: DiagnosticsFixture?
    #endif
}

/// The Diagnostics pane: engine diagnostics, "Check System" (with the items only the app can answer) and the support
/// report.
extension AppController {
    func loadDiagnostics() async -> EngineDiagnostics? {
        #if DEBUG
        if let fixture = diagnosticsCoordinator.fixture {
            let accounts = store.settings.accounts.map { (id: $0.id, provider: $0.provider) }
            return fixture.diagnostics(accounts: accounts, now: Date())
        }
        #endif
        return await engine.diagnostics()
    }

    /// Runs the engine's checks and adds the items only the app can answer: notification permission, the login item,
    /// the global shortcut, the widget snapshot, the displays, where the app runs from, crash reports and the vendor
    /// status check.
    func runSystemCheck() async -> SystemCheckReport? {
        #if DEBUG
        if let fixture = diagnosticsCoordinator.fixture {
            let fake = fixture.report(now: Date())
            diagnosticsCoordinator.lastReport = fake
            return fake
        }
        #endif
        let inputs = await appCheckInputs()
        let engineReport = await engine.checkSystem(directories: directories)
        let report = SystemCheckMerge.merged(
            engine: engineReport,
            appItems: SystemCheckMerge.appItems(inputs),
            ranAt: engineReport.ranAt
        )
        diagnosticsCoordinator.lastReport = report
        return report
    }

    /// Copies the English support report; account labels only when `includeAccountNames`.
    func copyDiagnosticsReport(_ report: SystemCheckReport, includeAccountNames: Bool) {
        diagnosticsCoordinator.lastReport = report
        copyToPasteboard(report.text(includeAccountNames: includeAccountNames, labels: accountLabels))
    }

    /// Saves the support text through a save panel, as a sheet on the Settings window when it is open.
    ///
    /// `includeAccountNames` is the pane's box, read at the moment the button is pressed, so the file agrees with
    /// what a "Copy Report" would put on the pasteboard and nothing is ever remembered from an earlier press.
    /// Everything else the report could name — e-mails, project and session names, the home folder path — is
    /// redacted either way, and with the box off the file carries no account labels at all.
    func exportDiagnostics(includeAccountNames: Bool = false) {
        guard let report = diagnosticsCoordinator.lastReport else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = DiagnosticsExport.fileName(for: Date())
        panel.allowedContentTypes = [.plainText]
        panel.isExtensionHidden = false
        let text = DiagnosticsExport.text(report, includeAccountNames: includeAccountNames, labels: accountLabels)
        let write: @MainActor (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try Data(text.utf8).write(to: url, options: [.atomic])
            } catch {
                AppLog.interface.error("diagnostics export failed: \(String(describing: error), privacy: .public)")
            }
        }
        // The button that starts this lives in the Settings window, which is key while it is clicked.
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: write)
        } else {
            write(panel.runModal())
        }
    }

    /// The label of every account, for the report's redaction table.
    private var accountLabels: [AccountID: String] {
        Dictionary(store.settings.accounts.map { ($0.id, $0.label.value) }, uniquingKeysWith: { first, _ in first })
    }

    /// Everything the app itself knows, gathered once per check.
    private func appCheckInputs() async -> AppCheckInputs {
        AppCheckInputs(
            notifications: await notificationAuthorization(),
            loginItem: loginItemStatus(),
            shortcut: store.shortcutStatus,
            widget: widgetSnapshotState(),
            displayCount: store.displays.count,
            location: appBuildInfo().locationKind,
            crashReports: recentCrashReports().count,
            statusEnabled: store.settings.general.showsVendorStatus,
            statusFailures: store.serviceStatus.lastFailureAt.count,
            now: Date()
        )
    }

    /// Age and permissions of the widget's snapshot file, read without following a symbolic link.
    private func widgetSnapshotState() -> WidgetSnapshotState {
        let url = widgetExporter.fileURL
        var info = stat()
        guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            return WidgetSnapshotState(isEnabled: widgetExporter.isEnabled, modifiedAt: nil, mode: nil)
        }
        let modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
        return WidgetSnapshotState(
            isEnabled: widgetExporter.isEnabled,
            modifiedAt: modified,
            mode: UInt16(info.st_mode & 0o7777)
        )
    }
}

/// What the app contributes to a system check. A plain value, so the merge is tested without a running app.
struct AppCheckInputs: Sendable {
    var notifications: NotificationAuthorization
    var loginItem: LoginItemStatus
    var shortcut: ShortcutStatus
    var widget: WidgetSnapshotState
    var displayCount: Int
    var location: AppLocationKind
    var crashReports: Int
    var statusEnabled: Bool
    /// Vendors whose last status check failed.
    var statusFailures: Int
    var now: Date
}

/// The widget's snapshot file as the check sees it.
struct WidgetSnapshotState: Hashable, Sendable {
    /// A snapshot older than this, while exporting is on, is worth a note.
    static let staleAfter: TimeInterval = 3_600
    static let expectedMode: UInt16 = 0o600

    var isEnabled: Bool
    var modifiedAt: Date?
    /// Permission bits, `nil` when the file is missing or not a regular file.
    var mode: UInt16?
}

/// Builds the app's own check items and merges them with the engine's.
enum SystemCheckMerge {
    /// The items in `SystemCheckItemKind` order; `SystemCheckReport` sorts them again, so this order is only for
    /// readability.
    static func appItems(_ inputs: AppCheckInputs) -> [SystemCheckReport.Item] {
        [
            notificationsItem(inputs.notifications),
            loginItemItem(inputs.loginItem),
            shortcutItem(inputs.shortcut),
            widgetItem(inputs.widget, now: inputs.now),
            displaysItem(inputs.displayCount),
            locationItem(inputs.location),
            crashItem(inputs.crashReports),
            statusItem(enabled: inputs.statusEnabled, failures: inputs.statusFailures),
        ]
    }

    /// The engine's items plus the app's, in one report. Ids are unique across the two sets (the app's are the kind
    /// names, which the engine uses only for its own kinds), and an app item wins over an engine item with the same
    /// id, so the two never produce a duplicate row.
    static func merged(engine: SystemCheckReport?, appItems: [SystemCheckReport.Item], ranAt: Date) -> SystemCheckReport {
        var byID: [String: SystemCheckReport.Item] = [:]
        var order: [String] = []
        for item in (engine?.items ?? []) + appItems {
            if byID[item.id] == nil { order.append(item.id) }
            byID[item.id] = item
        }
        return SystemCheckReport(ranAt: engine?.ranAt ?? ranAt, items: order.compactMap { byID[$0] })
    }

    // MARK: - The app's items

    static func notificationsItem(_ authorization: NotificationAuthorization) -> SystemCheckReport.Item {
        let kind = SystemCheckItemKind.notifications
        return switch authorization {
        case .authorized:
            item(kind, .ok, "allowed") // l10n-ignore: support report
        case .provisional:
            item(kind, .note, "allowed quietly; alerts appear in Notification Center only") // l10n-ignore: support report
        case .denied:
            item(kind, .warning, "not allowed; alerts will not appear") // l10n-ignore: support report
        case .notDetermined:
            item(kind, .note, "not asked for yet") // l10n-ignore: support report
        }
    }

    static func loginItemItem(_ status: LoginItemStatus) -> SystemCheckReport.Item {
        let kind = SystemCheckItemKind.loginItem
        return switch status {
        case .enabled: item(kind, .ok, "registered") // l10n-ignore: support report
        case .disabled: item(kind, .ok, "off") // l10n-ignore: support report
        case .requiresApproval: item(kind, .warning, "waiting for approval in System Settings") // l10n-ignore: support report
        case .notFound: item(kind, .note, "the system does not know this copy of the app") // l10n-ignore: support report
        case .unavailable: item(kind, .note, "not available in this instance") // l10n-ignore: support report
        }
    }

    static func shortcutItem(_ status: ShortcutStatus) -> SystemCheckReport.Item {
        let kind = SystemCheckItemKind.shortcut
        switch status {
        case .off:
            return item(kind, .ok, "off") // l10n-ignore: support report
        case .active:
            return item(kind, .ok, "registered") // l10n-ignore: support report
        case .unavailable(_, let reason, let alternatives):
            let free = alternatives.isEmpty
                ? ""
                : ", \(alternatives.count) free \(alternatives.count == 1 ? "alternative" : "alternatives")" // l10n-ignore: support report
            return switch reason {
            case .usedByMacOS: item(kind, .warning, "used by a macOS shortcut\(free)") // l10n-ignore: support report
            case .usedByAnotherApp: item(kind, .warning, "held exclusively by another app\(free)") // l10n-ignore: support report
            case .failed(let code): item(kind, .warning, "registration failed (\(code))\(free)") // l10n-ignore: support report
            }
        }
    }

    static func widgetItem(_ state: WidgetSnapshotState, now: Date) -> SystemCheckReport.Item {
        let kind = SystemCheckItemKind.widgetSnapshot
        guard state.isEnabled else {
            return item(kind, .ok, "sharing with the widget is off") // l10n-ignore: support report
        }
        guard let modifiedAt = state.modifiedAt, let mode = state.mode else {
            return item(kind, .note, "no snapshot written yet") // l10n-ignore: support report
        }
        let age = Int(max(0, now.timeIntervalSince(modifiedAt)) / 60)
        guard mode == WidgetSnapshotState.expectedMode else {
            let text = String(format: "%04o", Int(mode)) // l10n-ignore: support report
            return item(kind, .warning, "mode \(text), expected 0600") // l10n-ignore: support report
        }
        return age > Int(WidgetSnapshotState.staleAfter / 60)
            ? item(kind, .note, "last written \(age) min ago") // l10n-ignore: support report
            : item(kind, .ok, "last written \(age) min ago") // l10n-ignore: support report
    }

    static func displaysItem(_ count: Int) -> SystemCheckReport.Item {
        let kind = SystemCheckItemKind.displays
        return count > 0
            ? item(kind, .ok, "\(count) connected") // l10n-ignore: support report
            : item(kind, .note, "none reported") // l10n-ignore: support report
    }

    static func locationItem(_ location: AppLocationKind) -> SystemCheckReport.Item {
        let kind = SystemCheckItemKind.appLocation
        return switch location {
        case .applications: item(kind, .ok, "Applications") // l10n-ignore: support report
        case .userApplications: item(kind, .ok, "the home folder’s Applications") // l10n-ignore: support report
        case .other: item(kind, .note, "not in an Applications folder") // l10n-ignore: support report
        case .translocated: item(kind, .warning, "running translocated; move it to Applications") // l10n-ignore: support report
        case .diskImage: item(kind, .warning, "running from a disk image; move it to Applications") // l10n-ignore: support report
        case .readOnlyVolume: item(kind, .warning, "running from a read-only volume; move it to Applications") // l10n-ignore: support report
        }
    }

    static func crashItem(_ count: Int) -> SystemCheckReport.Item {
        let kind = SystemCheckItemKind.crashReports
        return count == 0
            ? item(kind, .ok, "none stored") // l10n-ignore: support report
            : item(kind, .note, "\(count) stored on this Mac") // l10n-ignore: support report
    }

    static func statusItem(enabled: Bool, failures: Int) -> SystemCheckReport.Item {
        let kind = SystemCheckItemKind.serviceStatus
        guard enabled else {
            return item(kind, .ok, "off, so nothing is requested") // l10n-ignore: support report
        }
        return failures == 0
            ? item(kind, .ok, "on") // l10n-ignore: support report
            : item(kind, .note, "on, \(failures) vendor \(failures == 1 ? "check" : "checks") failed last time") // l10n-ignore: support report
    }

    private static func item(
        _ kind: SystemCheckItemKind,
        _ status: SystemCheckReport.Item.Status,
        _ detail: String
    ) -> SystemCheckReport.Item {
        SystemCheckReport.Item(id: kind.rawValue, status: status, kind: kind, detail: detail)
    }
}

/// What a saved support file is called and what it carries.
enum DiagnosticsExport {
    /// The text written to disk. Redacted by default: a caller that says nothing gets a file without account
    /// names. See `AppController.exportDiagnostics(includeAccountNames:)`.
    static func text(_ report: SystemCheckReport, includeAccountNames: Bool = false, labels: [AccountID: String]) -> String {
        report.text(includeAccountNames: includeAccountNames, labels: labels)
    }

    /// "Codometer-diagnostics-2026-09-18.txt": no account, profile or host name.
    static func fileName(for date: Date) -> String {
        let day = date.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        return "Codometer-diagnostics-\(day).txt"
    }
}
