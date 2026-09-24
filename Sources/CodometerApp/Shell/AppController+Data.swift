import CodometerCore
import CodometerEngine
import CodometerL10n
import CodometerPlatform
import CodometerUI
import AppKit
import Darwin
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications
import Foundation
import os

/// State of the data controls: the export panel's choices and the erase that is under way.
@MainActor
final class DataCoordinator {
    /// Kept between openings, so the next export starts from the last format.
    let exportOptions = ExportPanelOptions()
    var isExporting = false

    init() {}
}

/// What the export save panel's accessory view holds.
@MainActor
@Observable
final class ExportPanelOptions {
    var format: HistoryExportFormat = .json
    var includeAccountNames = true

    init() {}
}

/// Data controls: history export, erasing all data and relaunching.
extension AppController {
    // MARK: - Export

    /// Asks where to export history and writes it there.
    ///
    /// The panel is a sheet on the window that started it (Settings), with a format picker and the account-name
    /// toggle. When the user approves replacing something, that item goes to the Trash first, because the engine
    /// refuses to write over anything.
    func exportHistory() {
        guard !isErasing, !dataCoordinator.isExporting else { return }
        let l10n = store.localizer
        let options = dataCoordinator.exportOptions
        let panel = NSSavePanel()
        panel.prompt = l10n.dataControls.exportPrompt
        panel.message = l10n.dataControls.exportPanelMessage
        panel.canCreateDirectories = true
        panel.showsTagField = false
        panel.nameFieldStringValue = Self.exportName(options.format, l10n: l10n, now: Date())
        panel.allowedContentTypes = options.format == .json ? [.json] : []
        let accessory = NSHostingView(
            rootView: ExportOptionsView(options: options) { [weak panel] format in
                guard let panel else { return }
                panel.allowedContentTypes = format == .json ? [.json] : []
                panel.nameFieldStringValue = Self.exportName(format, l10n: l10n, now: Date())
            }
            .environment(\.l10n, l10n)
            .environment(\.locale, l10n.locale)
        )
        accessory.frame = NSRect(x: 0, y: 0, width: 440, height: 86)
        panel.accessoryView = accessory

        let host = NSApp.keyWindow
        let finish: @MainActor (NSApplication.ModalResponse) -> Void = { [weak self, weak panel] response in
            guard let self, let panel, response == .OK, let url = panel.url else { return }
            self.runExport(to: url, options: options)
        }
        if let host {
            panel.beginSheetModal(for: host) { response in
                MainActor.assumeIsolated { finish(response) }
            }
        } else {
            panel.begin { response in
                MainActor.assumeIsolated { finish(response) }
            }
        }
    }

    /// "Codometer History 2026-09-17", with `.json` for the single-file format.
    ///
    /// The date is the calendar date in the user's time zone, written ISO 8601 so it needs no locale and sorts in a
    /// folder listing.
    static func exportName(_ format: HistoryExportFormat, l10n: Localizer, now: Date) -> String {
        let day = now.formatted(
            Date.ISO8601FormatStyle(dateSeparator: .dash, timeZone: l10n.calendar.timeZone).year().month().day()
        )
        let base = l10n.dataControls.exportFileName(day: day)
        return format == .json ? base + ".json" : base
    }

    private func runExport(to url: URL, options: ExportPanelOptions) {
        let l10n = store.localizer
        let settings = store.settings
        let request = HistoryExportRequest(
            format: options.format,
            includeAccountNames: options.includeAccountNames,
            labels: options.includeAccountNames
                ? Dictionary(settings.accounts.map { ($0.id, $0.label.value) }, uniquingKeysWith: { first, _ in first })
                : [:],
            appVersion: appBuildInfo().version,
            retentionDays: settings.general.historyRetention.days,
            readmeText: l10n.dataControls.csvReadme(
                appVersion: appBuildInfo().version,
                exportedAt: Date().formatted(.iso8601),
                retentionDays: settings.general.historyRetention.days
            )
        )
        let destination: URL
        switch ExportDestination.prepare(url) {
        case .ready(let prepared):
            destination = prepared
        case .failed:
            DataControls.shared.exportFailed(.destinationExists)
            return
        }
        dataCoordinator.isExporting = true
        DataControls.shared.exportStarted()
        let engine = engine
        Task { [weak self] in
            do throws(HistoryExportError) {
                let summary = try await engine.export(request, to: destination)
                DataControls.shared.exportFinished(rows: summary.rowCount, destination: summary.destination)
            } catch {
                AppLog.storage.error("history export failed: \(String(describing: error), privacy: .public)")
                DataControls.shared.exportFailed(error)
            }
            self?.dataCoordinator.isExporting = false
        }
    }

    // MARK: - Erase

    /// Erases every file the app created, then quits or relaunches into the welcome flow.
    func eraseAllData(relaunch: Bool) {
        guard !isErasing else { return }
        Task { [weak self] in
            guard let self else { return }
            let summary = await AppController.runErase(eraseOperations())
            AppLog.storage.notice(
                "erase removed \(summary.removedItems, privacy: .public) item(s), refused \(summary.refusedSymlinks, privacy: .public) symlink(s), \(summary.failures, privacy: .public) failure(s)"
            )
            if relaunch {
                self.relaunch()
            } else {
                NSApp.terminate(nil)
            }
        }
    }

    /// The erase, step by step, so the order can be tested with fakes.
    ///
    /// The freeze comes first: `persist`, the clock task and the widget exporter all stop, so nothing is written
    /// after it. The widget snapshot is dropped next, which also cancels a publish that would otherwise recreate
    /// `Widget/` between the freeze and the erase. Only then does the database close and the data root go.
    struct EraseOperations {
        var freeze: @MainActor () -> Void
        var stopWidgetExport: @MainActor () -> Void
        var closeEngine: @MainActor () async -> Void
        var eraseDataRoot: @MainActor () -> EraseSummary
        var unregisterLoginItem: @MainActor () -> Void
        var removeNotifications: @MainActor () -> Void
        var removeDefaults: @MainActor () -> Void
        var removeSupportFiles: @MainActor () -> Int
    }

    /// Runs the operations in their fixed order and returns what was removed.
    static func runErase(_ operations: EraseOperations) async -> EraseSummary {
        operations.freeze()
        operations.stopWidgetExport()
        await operations.closeEngine()
        let summary = operations.eraseDataRoot()
        operations.unregisterLoginItem()
        operations.removeNotifications()
        operations.removeDefaults()
        let extra = operations.removeSupportFiles()
        return EraseSummary(
            removedItems: summary.removedItems + extra,
            refusedSymlinks: summary.refusedSymlinks,
            failures: summary.failures
        )
    }

    private func eraseOperations() -> EraseOperations {
        let directories = directories
        let bundleIdentifier = Bundle.main.bundleIdentifier
        let isIsolated = directories.isIsolated
        let l10n = store.localizer
        return EraseOperations(
            freeze: { [weak self] in self?.isErasing = true },
            stopWidgetExport: { [weak self] in self?.widgetExporter.removeSnapshotForErase() },
            closeEngine: { [weak self] in
                guard let engine = self?.engine else { return }
                await engine.prepareForErase()
            },
            eraseDataRoot: {
                do throws(FileAccessError) {
                    return try directories.eraseAll(bundleIdentifier: bundleIdentifier)
                } catch {
                    AppLog.storage.error("data root not erased: \(error.summary, privacy: .public)")
                    return EraseSummary(removedItems: 0, refusedSymlinks: 0, failures: 1)
                }
            },
            unregisterLoginItem: {
                // The login item belongs to the installed app; an isolated instance never touches it.
                guard !isIsolated else { return }
                _ = LoginItemService.setEnabled(false, l10n: l10n)
            },
            removeNotifications: {
                guard !isIsolated, Bundle.main.bundleIdentifier != nil else { return }
                let center = UNUserNotificationCenter.current()
                center.removeAllDeliveredNotifications()
                center.removeAllPendingNotificationRequests()
            },
            removeDefaults: {
                guard !isIsolated, let bundleIdentifier else { return }
                NSWindow.removeFrame(usingName: Self.settingsFrameAutosaveName)
                UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
            },
            removeSupportFiles: {
                guard !isIsolated, let bundleIdentifier else { return 0 }
                return AppSupportLeftovers.remove(bundleIdentifier: bundleIdentifier, home: NSHomeDirectory())
            }
        )
    }

    /// The Settings window's saved frame, removed with the rest of the preferences.
    static let settingsFrameAutosaveName = "CodometerSettings"

    // MARK: - Relaunch

    /// Starts a fresh instance and quits this one.
    ///
    /// An isolated instance passes its own `CODOMETER_*` variables on (minus the debug ones), so a relaunch started
    /// by a test can never open the real data folder or migrate real data.
    func relaunch() {
        let configuration = RelaunchConfiguration.make(
            pid: ProcessInfo.processInfo.processIdentifier,
            isIsolated: directories.isIsolated,
            environment: ProcessInfo.processInfo.environment
        )
        let open = NSWorkspace.OpenConfiguration()
        open.createsNewApplicationInstance = true
        open.arguments = configuration.arguments
        if !configuration.environment.isEmpty {
            open.environment = configuration.environment
        }
        AppLog.interface.notice("relaunching")
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: open) { _, error in
            if let error {
                AppLog.interface.error("relaunch failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        NSApp.terminate(nil)
    }
}

/// How a new instance is started: the argument that lets it wait for this process, and the environment it inherits.
struct RelaunchConfiguration: Equatable {
    /// The instance lock waits for this pid before treating the lock as busy.
    static let relaunchArgument = "--relaunched-after"
    /// Variables of an isolated run, minus the debug scenario ones: a relaunched instance runs without a scenario.
    static let variablePrefix = "CODOMETER_"
    static let debugVariablePrefix = "CODOMETER_DEBUG"

    let arguments: [String]
    let environment: [String: String]

    static func make(pid: Int32, isIsolated: Bool, environment: [String: String]) -> RelaunchConfiguration {
        let arguments = [relaunchArgument, String(pid)]
        guard isIsolated else { return RelaunchConfiguration(arguments: arguments, environment: [:]) }
        let carried = environment.filter { key, _ in
            key.hasPrefix(variablePrefix) && !key.hasPrefix(debugVariablePrefix)
        }
        return RelaunchConfiguration(arguments: arguments, environment: carried)
    }
}

/// Whether an export destination is free, after trashing an item the user agreed to replace.
enum ExportDestination {
    case ready(URL)
    case failed

    /// The save panel already asked about replacing; the engine refuses to write over anything, so the old item goes
    /// to the Trash (never deleted). A name that is still taken gets " 2", " 3", … up to " 9".
    static func prepare(_ url: URL) -> ExportDestination {
        guard exists(url) else { return .ready(url) }
        if (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil, !exists(url) {
            return .ready(url)
        }
        for suffix in 2...9 {
            let candidate = uniqued(url, suffix: suffix)
            if !exists(candidate) { return .ready(candidate) }
        }
        return .failed
    }

    /// `Codometer History 2026-09-17 2.json`.
    static func uniqued(_ url: URL, suffix: Int) -> URL {
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        let name = "\(base) \(suffix)"
        let directory = url.deletingLastPathComponent()
        return ext.isEmpty
            ? directory.appendingPathComponent(name, isDirectory: true)
            : directory.appendingPathComponent(name, isDirectory: false).appendingPathExtension(ext)
    }

    /// `lstat`, so a symbolic link counts as something that is there and is never followed.
    private static func exists(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }
}

/// The app's own leftovers outside the data root: its caches and its HTTP storage folder.
enum AppSupportLeftovers {
    /// Folders macOS creates for a bundle id, all under the user's Library, removed by exact name only. An identifier
    /// that is not a plain reverse-DNS name yields nothing: an empty one or `..` would name the parent folder itself.
    static func paths(bundleIdentifier: String, home: String) -> [String] {
        guard isPlainIdentifier(bundleIdentifier) else { return [] }
        return ["Library/Caches", "Library/HTTPStorages"].map { folder in
            ((home as NSString).appendingPathComponent(folder) as NSString).appendingPathComponent(bundleIdentifier)
        }
    }

    /// Letters, digits, `-` and `.`, at least two non-empty parts: `com.codometer.Codometer`.
    static func isPlainIdentifier(_ identifier: String) -> Bool {
        let parts = identifier.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count >= 2 && parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
    }

    /// Removes each folder that exists and is a real directory; a symbolic link is left alone. Returns how many went.
    static func remove(bundleIdentifier: String, home: String) -> Int {
        var removed = 0
        for path in paths(bundleIdentifier: bundleIdentifier, home: home) {
            var info = stat()
            guard lstat(path, &info) == 0 else { continue }
            guard (info.st_mode & S_IFMT) == S_IFDIR else {
                AppLog.storage.notice("erase skipped a leftover that is not a directory")
                continue
            }
            do {
                try FileManager.default.removeItem(atPath: path)
                removed += 1
            } catch {
                AppLog.storage.error("leftover not removed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return removed
    }
}

/// The save panel's accessory: the file layout and whether account names travel with the data.
struct ExportOptionsView: View {
    @Bindable var options: ExportPanelOptions
    let formatChanged: (HistoryExportFormat) -> Void

    @Environment(\.l10n) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(selection: $options.format) {
                Text(l10n.dataControls.formatJSON).tag(HistoryExportFormat.json)
                Text(l10n.dataControls.formatCSV).tag(HistoryExportFormat.csvFolder)
            } label: {
                Text(l10n.dataControls.format)
            }
            .pickerStyle(.radioGroup)
            .accessibilityLabel(l10n.dataControls.format)
            .onChange(of: options.format) { _, format in formatChanged(format) }
            Toggle(isOn: $options.includeAccountNames) {
                Text(l10n.dataControls.includeAccountNames)
            }
            .accessibilityLabel(l10n.dataControls.includeAccountNames)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
