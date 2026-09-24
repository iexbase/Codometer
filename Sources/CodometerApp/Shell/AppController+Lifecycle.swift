import CodometerCore
import CodometerL10n
import CodometerPlatform
import CodometerStorage
import CodometerUI
import AppKit
import Foundation
import UserNotifications
import os

/// State of the app lifecycle services: instance lock, crash capture, login item reconciliation, version bookkeeping.
@MainActor
final class LifecycleServices {
    /// Stores and lists MetricKit payloads; created once the data root is known.
    var crashCapture: CrashCapture?
    var crashStore: CrashPayloadStore?
    /// Notification and distributed-notification observers this file owns (the controller's own list is private).
    var observers: [any NSObjectProtocol] = []
    var distributedObservers: [any NSObjectProtocol] = []
    /// Where the running bundle lives, decided once at launch.
    var locationKind: AppLocationKind = .other
    /// The login item as the system last reported it; refreshed at launch and whenever Settings opens.
    var loginItem: LoginItemStatus = .unavailable
    /// Whether this is the first launch of a new app version (the rename counts), for the login-item reconciliation.
    var isFirstLaunchOfVersion = false

    init() {}
}

/// Launch safety and app lifecycle: where the app runs from, one instance per data root, the main menu, crash reports,
/// the login item and notification permission.
extension AppController {
    // MARK: - Launch preflight

    /// Stops a launch from a disk image, a translocated path or a read-only volume: a critical alert in the system
    /// language, then quit — before the lock, the engine or any write.
    ///
    /// DEBUG builds only log where they run from, so `swift run` and workspace builds keep working. The check does
    /// apply with `CODOMETER_DATA_ROOT`, which is how it is tested from a mounted image.
    static func checkLocation() -> LaunchPreflight {
        let kind = AppLocationCheck.current(
            bundleURL: Bundle.main.bundleURL,
            homeDirectory: URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        )
        guard AppLocationCheck.blocksLaunch(kind) else { return .proceed(lock: nil) }
        #if DEBUG
        AppLog.interface.notice("debug build started from \(kind.rawValue, privacy: .public): the location check only warns")
        return .proceed(lock: nil)
        #else
        AppLog.interface.error("refusing to run from \(kind.rawValue, privacy: .public)")
        let text = AppLocationAlertText(kind: kind, l10n: Localizer(language: Language.resolve(.system)))
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = text.title
        alert.informativeText = text.message
        alert.addButton(withTitle: text.button)
        NSApp.activate()
        alert.runModal()
        return .quit
        #endif
    }

    /// Takes the single-instance lock on `directories.instanceLockFile`; a second copy tells the first to open
    /// Settings and quits.
    ///
    /// Called after `prepare()`, so the lock file always lands in an existing data root.
    static func acquireInstanceLock(directories: AppDirectories) -> LaunchPreflight {
        let file = directories.instanceLockFile
        let predecessor = RelaunchArguments.predecessorPID(in: ProcessInfo.processInfo.arguments)
        let result = InstanceGate.acquire(
            predecessor: predecessor,
            attempt: { InstanceLock.acquire(at: file) },
            waitForExit: InstanceGate.waitForProcessExit
        )
        switch result.outcome {
        case .acquired:
            return .proceed(lock: result.lock)
        case .unlocked(let reason):
            // Better to run than to refuse to start; Diagnostics shows nothing about it, the log does.
            AppLog.interface.notice("no instance lock: \(reason, privacy: .public)")
            return .proceed(lock: nil)
        case .busy:
            AppLog.interface.notice("another copy already uses this data folder: asking it to open Settings")
            let name = InstanceLock.openSettingsNotificationName(dataRoot: directories.root)
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name(name),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            return .quit
        }
    }

    // MARK: - Main menu

    /// Installs the app menu, the Edit menu and the Window menu, and rebuilds them when the language changes.
    func installMainMenu() {
        NSApp.mainMenu = MainMenu.make(l10n: store.localizer)
        observeMenuLanguage()
    }

    /// Observation fires once per language change and re-registers, so nothing runs while the language stands still.
    private func observeMenuLanguage() {
        withObservationTracking {
            _ = store.localizer
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.observeMenuLanguage()
                NSApp.mainMenu = MainMenu.make(l10n: self.store.localizer)
            }
        }
    }

    /// The standard About panel, with credits in the current language and a repository link only when the build was
    /// given one (`CodometerRepositoryURL`, injected from `Packaging/identity.env`).
    ///
    /// No activation-policy change: the panel is an ordinary window, and activating the app is enough to bring it
    /// forward from an accessory app.
    func showAboutPanel() {
        let options: [NSApplication.AboutPanelOptionKey: Any] = [
            .credits: AboutPanelText.credits(l10n: store.localizer, repository: AboutPanelText.repositoryURL(from: Bundle.main)),
        ]
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: options)
    }

    // MARK: - Lifecycle services

    /// Crash capture, login item reconciliation, version bookkeeping and the system observers this file owns.
    func startLifecycleServices() {
        lifecycle.locationKind = AppLocationCheck.current(bundleURL: Bundle.main.bundleURL, homeDirectory: homeDirectory)
        if lifecycle.locationKind != .applications {
            AppLog.interface.notice("running from \(self.lifecycle.locationKind.rawValue, privacy: .public)")
        }

        let crashStore = CrashPayloadStore(directory: directories.diagnosticsDirectory)
        lifecycle.crashStore = crashStore
        let capture = CrashCapture(store: crashStore)
        lifecycle.crashCapture = capture
        capture.start()

        applyVersionBookkeeping()
        reconcileLoginItem()
        settingsWindow.onShow = { [weak self] in self?.reconcileLoginItem() }
        statusItem.onAbout = { [weak self] in self?.showAboutPanel() }
        observeSystemAppearance()
        observeSecondInstance()
        refreshNotificationDelivery()
    }

    /// A new app version: the settings file is copied aside before it is first written, and WidgetKit reloads every
    /// kind (the rename gave the widgets new kinds).
    private func applyVersionBookkeeping() {
        let current = (try? AppVersion(appBuildInfo().version))
        let action = VersionBookkeeping.plan(stored: store.settings.general.lastLaunchedVersion, current: current)
        switch action {
        case .none:
            return
        case .upgrade(let from, let to):
            lifecycle.isFirstLaunchOfVersion = true
            if !store.isSettingsReadOnly {
                do throws(SettingsStoreError) {
                    let backup = try settingsStore.backup(tag: from.description)
                    AppLog.storage.notice("settings backed up before the first write of \(to.description, privacy: .public) (\(backup.lastPathComponent, privacy: .public))")
                } catch {
                    AppLog.storage.notice("pre-upgrade settings backup skipped: \(error.summary, privacy: .public)")
                }
            }
            widgetExporter.forceReload()
            record(version: to)
        case .record(let version):
            lifecycle.isFirstLaunchOfVersion = true
            record(version: version)
        }
    }

    private func record(version: AppVersion) {
        store.updateSettings { $0.general.lastLaunchedVersion = version }
    }

    /// Brings the "Open at login" setting and `SMAppService.mainApp.status` back into step. Called at launch and
    /// whenever the Settings window opens.
    func reconcileLoginItem() {
        guard !directories.isIsolated else {
            lifecycle.loginItem = .unavailable
            return
        }
        let status = LoginItemService.status()
        lifecycle.loginItem = status
        switch LoginItemReconcile.action(
            intent: store.settings.general.launchesAtLogin,
            status: status,
            versionChanged: lifecycle.isFirstLaunchOfVersion
        ) {
        case .none, .needsApproval:
            break
        case .register:
            if let failure = LoginItemService.setEnabled(true, l10n: store.localizer) {
                AppLog.interface.notice("login item not re-registered after the update: \(failure, privacy: .private)")
                store.updateSettings { $0.general.launchesAtLogin = false }
            } else {
                lifecycle.loginItem = LoginItemService.status()
            }
        case .turnSettingOff:
            AppLog.interface.notice("login item is gone: turning the setting off")
            store.updateSettings { $0.general.launchesAtLogin = false }
        case .turnSettingOn:
            AppLog.interface.notice("login item is registered: turning the setting on")
            store.updateSettings { $0.general.launchesAtLogin = true }
        }
    }

    /// Reduce Motion, Reduce Transparency and Increase Contrast changed while the app runs: the surfaces re-read them
    /// at once instead of at the next redraw. Also stops the services that outlive a quit.
    private func observeSystemAppearance() {
        let workspace = NSWorkspace.shared.notificationCenter
        lifecycle.observers.append(workspace.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applySurfaces()
                self?.statusItem.update()
            }
        })
        lifecycle.observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshNotificationDelivery()
            }
        })
        lifecycle.observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stopLifecycleServices()
            }
        })
    }

    /// A second copy asked this one to come forward. The name is scoped to this data root, so an isolated test
    /// instance never reaches the user's app.
    private func observeSecondInstance() {
        let name = Notification.Name(InstanceLock.openSettingsNotificationName(dataRoot: directories.root))
        lifecycle.distributedObservers.append(DistributedNotificationCenter.default().addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                AppLog.interface.notice("a second copy asked this one to open Settings")
                self?.openSettings()
            }
        })
    }

    /// Releases what would otherwise outlive the process: the IOKit power source (which retains itself while its
    /// run-loop source is installed) and the MetricKit subscription.
    func stopLifecycleServices() {
        lifecycle.crashCapture?.stop()
        lifecycle.crashCapture = nil
        energyCoordinator.monitor.stop()
        lifecycle.observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        lifecycle.observers.forEach { NotificationCenter.default.removeObserver($0) }
        lifecycle.observers.removeAll()
        lifecycle.distributedObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        lifecycle.distributedObservers.removeAll()
    }

    /// Asks the notification centre what it may deliver, so alert sounds follow the system instead of playing
    /// regardless. Event-driven: at launch and when the app becomes active.
    private func refreshNotificationDelivery() {
        let alerts = alerts
        Task { @MainActor in
            await alerts.refreshDeliverySettings()
        }
    }

    // MARK: - Reported to the UI

    /// Version and build from the bundle, with the location this launch classified.
    func appBuildInfo() -> AppBuildInfo {
        let info = Bundle.main.infoDictionary ?? [:]
        return AppBuildInfo(
            version: info["CFBundleShortVersionString"] as? String ?? "",
            build: info["CFBundleVersion"] as? String ?? "",
            locationKind: lifecycle.locationKind,
            licenseName: info["CodometerLicenseName"] as? String
        )
    }

    /// Locally stored crash and hang reports, newest first.
    func recentCrashReports() -> [CrashReportSummary] {
        lifecycle.crashStore?.summaries() ?? []
    }

    /// The login item as the system reports it; `.unavailable` for an isolated instance, which never touches it.
    func loginItemStatus() -> LoginItemStatus {
        guard !directories.isIsolated else { return .unavailable }
        let status = LoginItemService.status()
        lifecycle.loginItem = status
        return status
    }

    /// Notification permission as the system reports it.
    func notificationAuthorization() async -> NotificationAuthorization {
        await alerts.currentAuthorization()
    }
}

/// What a launch does about `general.lastLaunchedVersion`.
enum VersionBookkeeping: Equatable {
    /// Nothing to do: the same version as last time, or no version at all (an unbundled build).
    case none
    /// First launch ever (or the first that records a version): store it, nothing to back up.
    case record(AppVersion)
    /// A different version than last time: back the settings up under the old version, reload widgets, store the new one.
    case upgrade(from: AppVersion, to: AppVersion)

    static func plan(stored: AppVersion?, current: AppVersion?) -> VersionBookkeeping {
        guard let current else { return .none }
        guard let stored else { return .record(current) }
        return stored == current ? .none : .upgrade(from: stored, to: current)
    }
}

/// The About panel's credits, and the repository link the build may carry.
enum AboutPanelText {
    /// The Info.plist key `Scripts/build-app.sh` fills from `identity.env`'s `CODOMETER_REPOSITORY`; the app never reads `identity.env`.
    static let repositoryKey = "CodometerRepositoryURL"

    /// A `https://github.com/<owner>/<repo>` URL, or `nil` when the value is missing or not exactly that shape.
    static func repositoryURL(from bundle: Bundle) -> URL? {
        guard let raw = bundle.object(forInfoDictionaryKey: repositoryKey) as? String else { return nil }
        return validatedRepositoryURL(raw)
    }

    /// Exactly `https://github.com/<owner>/<repo>`: no other host, no port, no query, no extra path.
    static func validatedRepositoryURL(_ raw: String) -> URL? {
        guard raw.count <= 200, let components = URLComponents(string: raw) else { return nil }
        guard components.scheme == "https", components.host == "github.com", components.port == nil else { return nil }
        guard components.query == nil, components.fragment == nil, components.user == nil, components.password == nil else { return nil }
        let parts = components.path.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
        guard parts.count == 2 else { return nil }
        let allowed = { (part: Substring) in
            !part.isEmpty && part.count <= 100 && part.allSatisfy { $0.isLetter && $0.isASCII || $0.isNumber && $0.isASCII || $0 == "." || $0 == "_" || $0 == "-" }
        }
        guard parts.allSatisfy(allowed) else { return nil }
        return components.url
    }

    /// One sentence about the app, plus the repository as a link when the build has one.
    static func credits(l10n: Localizer, repository: URL?) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ]
        let text = NSMutableAttributedString(string: l10n.lifecycle.aboutCredits, attributes: base)
        guard let repository else { return text }
        text.append(NSAttributedString(string: "\n", attributes: base))
        var link = base
        link[.link] = repository
        // The URL is shown as itself: a project address is not translated.
        text.append(NSAttributedString(string: repository.absoluteString, attributes: link))
        return text
    }
}
