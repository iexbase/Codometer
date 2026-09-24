import CodometerCore
import CodometerL10n
import CodometerEngine
import CodometerPlatform
import CodometerStorage
import CodometerUI
import AppKit
import Darwin
import ServiceManagement
import os

/// Composition root: builds every component once and wires them together.
///
/// Features live in extensions, one file per owner (`AppController+Lifecycle`, `+Presentation`, `+Shortcut`,
/// `+Displays`, `+Energy`, `+Diagnostics`, `+Data`, `+Onboarding`, `+Status`). Swift extensions cannot add stored
/// properties, so this file declares one holder object per extension (`lifecycle`, `presentation`, …); each holder's
/// class lives in its owner's file and keeps that feature's state.
@MainActor
final class AppController {
    let homeDirectory: URL
    let directories: AppDirectories
    let settingsStore: SettingsStore
    let engine: TrackerEngine
    let store: TrackerStore
    /// Owned here: `applyShortcut()` registers it, and presses reach the active surface through `shortcutPressed()`.
    let hotKeys: HotKeyService
    let island: IslandController
    /// The floating card, once `installPresentationSurfaces()` created it.
    var card: (any PresentationSurface)?
    let statusItem: StatusItemController
    let settingsWindow: SettingsWindowController
    let alerts: AlertPresenter
    /// Writes the desktop widget's snapshot file and asks WidgetKit to reload (throttled by its own policy).
    let widgetExporter: WidgetExporter
    /// Routes UI actions back to this controller. Held strongly: the store's action closures only keep a weak reference to it.
    let router: ActionRouter
    /// Keeps the single-instance lock held for the whole run (see `acquireInstanceLock(directories:)`).
    var launchLock: AnyObject?
    /// "Erase All Data" is under way: nothing is persisted, ticked or exported any more.
    var isErasing = false

    // Holders of the extensions' state (their classes live in the extension files).
    let lifecycle = LifecycleServices()
    let presentation = PresentationCoordinator()
    let shortcuts = ShortcutCoordinator()
    let screens = ScreenCatalog()
    let energyCoordinator = EnergyCoordinator()
    let diagnosticsCoordinator = DiagnosticsCoordinator()
    let dataCoordinator = DataCoordinator()
    let onboarding = OnboardingCoordinator()
    let statusCoordinator = StatusCoordinator()

    private var updatesTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var observers: [any NSObjectProtocol] = []
    private var isShutDown = false
    private var resetAnnouncements = ResetAnnouncementThrottle()
    #if DEBUG
    /// Synthetic data a debug scenario installed: analytics come from it, nothing is persisted, engine updates are ignored.
    var debugFixture: DebugFixture?
    #endif

    /// How long quitting waits for the engine to close open history segments and write pending history.
    static let shutdownTimeout: DispatchTimeInterval = .seconds(1)
    #if DEBUG
    /// Lets a debug build use the real data folder (`open --env CODOMETER_DEBUG_STANDARD_ROOT=1 build/Codometer.app`).
    static let debugStandardRootVariable = "CODOMETER_DEBUG_STANDARD_ROOT"
    #endif

    /// Launch order (binding): data root → location check → legacy migration → `prepare()` (creates the root) →
    /// instance lock (after the migration, so a lock file never makes the new root exist first) → history → settings.
    static func launch() -> AppController? {
        let homeDirectory = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let environment = ProcessInfo.processInfo.environment
        let directories: AppDirectories
        do throws(FileAccessError) {
            directories = try AppDirectories.standard(environment: environment)
        } catch {
            presentDataFolderFailure(error)
            return nil
        }
        #if DEBUG
        // A debug build opens the real data folder only when asked to. A crashed test instance that macOS reopens loses
        // its environment (CODOMETER_DATA_ROOT) and would otherwise start on the user's real data.
        guard directories.isIsolated || environment[Self.debugStandardRootVariable] == "1" else {
            AppLog.storage.error("debug build without \(AppDirectories.dataRootVariable, privacy: .public): quitting (set \(Self.debugStandardRootVariable, privacy: .public)=1 to use the real data folder)")
            return nil
        }
        #endif
        guard case .proceed = checkLocation() else { return nil }

        var notices: [AppNotice] = []
        do throws(FileAccessError) {
            try directories.prepare()
        } catch {
            presentDataFolderFailure(error)
            return nil
        }
        guard case .proceed(let lock) = acquireInstanceLock(directories: directories) else { return nil }
        if directories.isIsolated {
            AppLog.interface.notice("isolated data root: no widget export, notifications, login item changes or global shortcut")
        }

        var history: UsageHistoryStore?
        switch UsageHistoryStore.open(databaseURL: directories.historyDatabase) {
        case let .opened(store, health):
            history = store
            if health != .ok {
                notices.append(.history(health))
            }
        case .unavailable(let health):
            if case .unavailable(let reason) = health {
                AppLog.storage.error("history unavailable: \(reason, privacy: .public)")
            }
            notices.append(.history(health))
        }

        let settingsStore = SettingsStore(fileURL: directories.settingsFile)
        let loaded = loadSettings(
            from: settingsStore,
            homeDirectory: homeDirectory,
            discoversProfiles: discoversProfilesForInitialSettings(isIsolated: directories.isIsolated)
        )
        notices.append(contentsOf: loaded.notices)
        let settings = loaded.settings
        // Before any window exists; AppKit's own text follows it from the next launch.
        LanguageDefaults.apply(settings.general.language)

        let engine = TrackerEngine(dependencies: .live(homeDirectory: homeDirectory, directories: directories, history: history))
        let controller = AppController(
            homeDirectory: homeDirectory,
            directories: directories,
            settingsStore: settingsStore,
            settings: settings,
            engine: engine
        )
        controller.launchLock = lock
        controller.store.setSettingsReadOnly(loaded.isReadOnly)
        controller.store.setNotices(notices)
        controller.start(settings: settings)
        return controller
    }

    private init(
        homeDirectory: URL,
        directories: AppDirectories,
        settingsStore: SettingsStore,
        settings: AppSettings,
        engine: TrackerEngine
    ) {
        self.homeDirectory = homeDirectory
        self.directories = directories
        self.settingsStore = settingsStore
        self.engine = engine

        router = ActionRouter()
        store = TrackerStore(
            state: .empty,
            settings: settings,
            now: Date(),
            actions: router.actions,
            preferredLanguages: LanguageDefaults.systemPreferredLanguages
        )
        hotKeys = HotKeyService()
        island = IslandController(store: store, hotKeys: hotKeys)
        statusItem = StatusItemController(store: store)
        settingsWindow = SettingsWindowController(store: store)
        // An isolated data root (CODOMETER_DATA_ROOT) leaves the user's system untouched: no global shortcut unless
        // a debug scenario sets one, no notifications, no widget snapshot, no login item changes.
        widgetExporter = WidgetExporter(
            directory: directories.root.appendingPathComponent(WidgetSnapshot.directoryName, isDirectory: true),
            isEnabled: !directories.isIsolated
        )
        alerts = AlertPresenter(postsNotifications: !directories.isIsolated)
        // Set before anything else runs, so a notification click that launched the app is handled too.
        alerts.onOpen = { [weak self] accountID in self?.openDeck(for: accountID) }
        hotKeys.onPress = { [weak self] in self?.shortcutPressed() }
        router.controller = self
    }

    private func start(settings: AppSettings) {
        installMainMenu()
        installPresentationSurfaces()
        applyShortcut()
        refreshDisplays()
        applySurfaces()
        #if DEBUG
        DebugScenario.startIfRequested(controller: self)
        #endif
        statusItem.update()
        // Removes a snapshot left behind when the export is off; with it on, waits for the first complete state.
        updateWidget()

        let updates = engine.updates
        updatesTask = Task { [weak self] in
            for await update in updates {
                self?.handle(update)
            }
        }
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30), tolerance: .seconds(3))
                guard let self else { return }
                guard !isErasing else { continue }
                store.tick(Date())
                statusItem.update()
                // Notices readings going stale and resets passing when no new state arrives.
                updateWidget()
            }
        }
        observeSystemEvents()
        startEnergyMonitoring()
        startStatusService()
        startLifecycleServices()

        if !routeFirstRun(settings: settings) {
            startEngine(settings: settings)
            if settings.accounts.isEmpty {
                openSettings()
            }
        }
    }

    /// Starts the engine's monitors for `settings` (again after onboarding; the engine ignores a second start).
    func startEngine(settings: AppSettings) {
        let engine = engine
        Task {
            await engine.start(settings: settings)
        }
    }

    /// Stops observing and stops the engine, waiting at most `shutdownTimeout` for it, so open history segments
    /// close and pending history is written before the process exits. Only the first call does anything.
    ///
    /// The wait blocks the main thread on purpose. Quitting can start inside a main-queue callback (a SwiftUI action,
    /// a task), and while AppKit waits for a delayed `applicationShouldTerminate` reply it does not drain the main
    /// queue again, so a reply sent from a main-actor task would never arrive and the app would hang. The engine's
    /// stop needs nothing from the main actor.
    func shutdown() {
        guard !isShutDown else { return }
        isShutDown = true
        updatesTask?.cancel()
        clockTask?.cancel()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        let engine = engine
        let stopped = DispatchSemaphore(value: 0)
        Task.detached {
            await engine.stop()
            stopped.signal()
        }
        if stopped.wait(timeout: .now() + Self.shutdownTimeout) == .timedOut {
            AppLog.engine.notice("quitting before the engine stopped")
        }
    }

    func openSettings() {
        AppLog.interface.notice("opening settings")
        settingsWindow.show()
    }

    // MARK: - Surfaces

    /// The surface of the selected presentation style: the card when selected and installed, otherwise the island.
    var activeSurface: any PresentationSurface {
        PresentationRouting.activeSurface(style: store.settings.appearance.presentationStyle, island: island, card: card)
    }

    /// Every surface re-reads the settings; only the selected style shows itself.
    func applySurfaces() {
        island.applyAppearance()
        card?.applyAppearance()
    }

    // MARK: - Notifications

    /// A click on a notification: shows that account in the active surface and keeps it open, or, while that surface
    /// is hidden, in the menu bar popover. Notifications from an earlier run can name accounts that are no longer
    /// tracked; those clicks are ignored.
    private func openDeck(for accountID: AccountID) {
        let settings = store.settings
        guard let profile = settings.accounts.first(where: { $0.id == accountID }), profile.isEnabled else {
            AppLog.interface.notice("notification click for an account that is no longer tracked")
            return
        }
        // A group filter hiding the account would show another account instead; clear it, as the deck's
        // waiting-for-you cards do.
        if let filter = settings.appearance.railGroupFilter,
           settings.groups.contains(where: { $0.id == filter }),
           profile.groupID != filter {
            store.updateSettings { $0.appearance.railGroupFilter = nil }
        }
        PresentationRouting.openPinned(accountID: accountID, on: activeSurface) {
            statusItem.showPopover(selecting: accountID)
        }
    }

    // MARK: - Engine updates

    private func handle(_ update: EngineUpdate) {
        guard !isErasing else { return }
        #if DEBUG
        // A debug fixture shows synthetic data only.
        guard debugFixture == nil else { return }
        #endif
        switch update {
        case .state(let state):
            store.receive(state)
            statusItem.update()
            updateWidget()
        case .alerts(let newAlerts):
            let settings = store.settings
            alerts.present(newAlerts, state: store.state, settings: settings, localizer: store.localizer)
            if let accountID = newAlerts.lazy.compactMap(Self.peekAccount).first {
                activeSurface.peek(accountID: accountID, seconds: settings.alerts.peekDuration.seconds)
            }
        case .resets(let events):
            store.celebrate(events, now: Date())
            announceResets(events)
        }
    }

    /// One VoiceOver announcement per account whose limit reset, at most one per account every 30 seconds, and only
    /// while VoiceOver runs.
    private func announceResets(_ events: [WindowResetEvent]) {
        guard NSWorkspace.shared.isVoiceOverEnabled else { return }
        let now = Date()
        for accountID in resetAnnouncements.accountsToAnnounce(events.map(\.accountID), now: now) {
            guard let label = store.settings.account(accountID)?.label.value else { continue }
            NSAccessibility.post(
                element: NSApp as Any,
                notification: .announcementRequested,
                userInfo: [
                    .announcement: store.localizer.usage.limitResetAnnouncement(account: label),
                    .priority: NSAccessibilityPriorityLevel.medium.rawValue,
                ]
            )
        }
    }

    /// Cheap on every call: the exporter skips identical content and throttles publishing itself.
    func updateWidget() {
        guard !isErasing else { return }
        widgetExporter.update(state: store.state, settings: store.settings, language: store.localizer.language, now: Date())
    }

    private static func peekAccount(for alert: TrackerAlert) -> AccountID? {
        switch alert {
        case .sessionFinished(let accountID, _), .sessionNeedsAttention(let accountID, _):
            accountID
        case .thresholdReached(let context, _), .limitReset(let context):
            context.accountID
        case .sessionAttentionResolved:
            nil
        }
    }

    // MARK: - Actions

    /// Applies edited settings: saved to disk unless the file is read-only (a newer Codometer wrote it) or a debug
    /// fixture is shown, then applied in memory for this session. While erasing, nothing happens at all.
    fileprivate func persist(_ settings: AppSettings) {
        let plan = SettingsPersistence.plan(isReadOnly: store.isSettingsReadOnly, isErasing: isErasing, isDebugFixture: isShowingDebugFixture)
        guard plan != .skip else { return }
        if plan == .save {
            do throws(SettingsStoreError) {
                try settingsStore.save(settings)
            } catch {
                AppLog.storage.error("settings not saved: \(error.summary, privacy: .public) (\(error.description, privacy: .private))")
            }
            LanguageDefaults.apply(settings.general.language)
        }
        applyShortcut()
        applySurfaces()
        statusItem.update()
        widgetExporter.update(state: store.state, settings: settings, language: store.localizer.language, now: Date())
        // The engine is left alone until the welcome flow ends, so no CLI probe runs before it:
        // `apply(settings:)` starts a monitor for every enabled account.
        guard !isShowingDebugFixture, !defersEngineUpdates else { return }
        let engine = engine
        Task { await engine.apply(settings: settings) }
    }

    private var isShowingDebugFixture: Bool {
        #if DEBUG
        debugFixture != nil
        #else
        false
        #endif
    }

    fileprivate func refresh(_ accountID: AccountID?) {
        let engine = engine
        Task { await engine.refresh(accountID: accountID) }
    }

    fileprivate func discoverProfiles() -> [DiscoveredAccount] {
        ProfileDiscovery.initialAccounts(homeDirectory: homeDirectory).map { account in
            DiscoveredAccount(provider: account.provider, directory: account.directory, suggestedLabel: account.label.value)
        }
    }

    /// The login item belongs to the installed app: an isolated instance never registers or unregisters it.
    fileprivate func setLaunchAtLogin(_ enabled: Bool) -> String? {
        guard !directories.isIsolated else {
            AppLog.interface.notice("isolated data root: login item left unchanged")
            return nil
        }
        return LoginItemService.setEnabled(enabled, l10n: store.localizer)
    }

    fileprivate func revealDataFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([directories.root])
    }

    fileprivate func windowHistory(accountID: AccountID, bucketID: String, windowID: String, since: Date) async -> HistorySeries {
        #if DEBUG
        if let debugFixture {
            return debugFixture.windowHistory(accountID: accountID, bucketID: bucketID, windowID: windowID, since: since)
        }
        #endif
        return await engine.windowHistory(accountID: accountID, bucketID: bucketID, windowID: windowID, since: since)
    }

    fileprivate func timeline(accountID: AccountID, interval: DateInterval) async -> TimelineSnapshot {
        #if DEBUG
        if let debugFixture {
            return debugFixture.timeline(accountID: accountID, interval: interval)
        }
        #endif
        return await engine.timeline(accountID: accountID, interval: interval)
    }

    fileprivate func attribution(accountID: AccountID, interval: DateInterval, grouping: AttributionGrouping) async -> AttributionReport? {
        #if DEBUG
        if let debugFixture {
            return debugFixture.attribution(accountID: accountID, interval: interval, grouping: grouping)
        }
        #endif
        return await engine.attribution(accountID: accountID, interval: interval, grouping: grouping)
    }

    /// Shows a file or folder in Finder. A symbolic link (or anything that cannot be examined) is never revealed.
    func revealInFinder(_ url: URL) {
        var info = stat()
        guard url.isFileURL, lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) != S_IFLNK else {
            AppLog.interface.notice("reveal in Finder refused: missing item or symbolic link")
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// System Settings → Notifications.
    func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    private func observeSystemEvents() {
        let center = NSWorkspace.shared.notificationCenter
        let engine = engine
        // Only system sleep pauses the engine. With just the display asleep agents keep working, and their
        // sessions, tokens and limits must still be recorded (the timeline included).
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            Task { await engine.setPaused(true) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Task { await engine.setPaused(false) }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshDisplays()
                self?.applySurfaces()
            }
        })
        // The region (numbers, 12/24-hour clock) or, with the System language, the language order changed.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.localeChanged()
            }
        })
    }

    private func localeChanged() {
        store.refreshLocale()
        statusItem.update()
        updateWidget()
    }

    // MARK: - Startup helpers

    /// Settings as loaded, with the notices the load raised.
    struct LoadedSettings {
        let settings: AppSettings
        let notices: [AppNotice]
        /// Written by a newer Codometer: never saved over.
        let isReadOnly: Bool
    }

    /// Loads settings leniently. A missing or unreadable file starts fresh settings whose onboarding has not started
    /// (a recovered file lost its accounts, so the welcome flow finds the profiles again); loaded and read-only files
    /// keep their onboarding state.
    private static func loadSettings(from store: SettingsStore, homeDirectory: URL, discoversProfiles: Bool) -> LoadedSettings {
        switch store.load() {
        case let .loaded(settings, repairs):
            guard !repairs.isEmpty else { return LoadedSettings(settings: settings, notices: [], isReadOnly: false) }
            // Repair notes are coding paths only, never values.
            AppLog.storage.notice("settings repaired: \(repairs.count, privacy: .public) value(s) replaced by defaults (\(repairs.joined(separator: ", "), privacy: .public))")
            return LoadedSettings(settings: settings, notices: [.settingsRepaired(count: repairs.count)], isReadOnly: false)
        case let .readOnly(settings, version):
            AppLog.storage.notice("settings written by a newer Codometer (schema \(version, privacy: .public)): loaded read-only, never saved over")
            return LoadedSettings(settings: settings, notices: [.settingsReadOnly(version: version)], isReadOnly: true)
        case .missing:
            let settings = createInitialSettings(in: store, homeDirectory: homeDirectory, discoversProfiles: discoversProfiles)
            return LoadedSettings(settings: settings, notices: [], isReadOnly: false)
        case let .recovered(backupPath, reason):
            // The reason quotes the path or the offending values, so it stays private.
            AppLog.storage.error("settings invalid (\(reason, privacy: .private)); moved to \(backupPath, privacy: .private)")
            let settings = createInitialSettings(in: store, homeDirectory: homeDirectory, discoversProfiles: discoversProfiles)
            let backupName = URL(fileURLWithPath: backupPath).lastPathComponent
            return LoadedSettings(settings: settings, notices: [.settingsRecovered(backupFileName: backupName)], isReadOnly: false)
        }
    }

    private static func createInitialSettings(in store: SettingsStore, homeDirectory: URL, discoversProfiles: Bool) -> AppSettings {
        let accounts = discoversProfiles ? ProfileDiscovery.initialAccounts(homeDirectory: homeDirectory) : []
        let general = GeneralSettings(onboarding: .notStarted)
        let settings = (try? AppSettings(accounts: accounts, general: general))
            ?? (try? AppSettings(accounts: [], general: general))
            ?? .empty
        do throws(SettingsStoreError) {
            try store.save(settings)
        } catch {
            AppLog.storage.error("initial settings not saved: \(error.summary, privacy: .public) (\(error.description, privacy: .private))")
        }
        return settings
    }

    /// Fresh settings in an isolated data root, or in a DEBUG run with a scenario, never pick up the real
    /// `~/.claude*`/`~/.codex*` profiles, so test runs and captures show no real accounts.
    private static func discoversProfilesForInitialSettings(isIsolated: Bool) -> Bool {
        guard !isIsolated else { return false }
        #if DEBUG
        if ProcessInfo.processInfo.environment[DebugScenario.scenarioVariable] != nil {
            return false
        }
        #endif
        return true
    }

    /// The data folder cannot be created: say so and quit. Settings are not loaded yet, so the text follows the
    /// macOS language order (which includes the language Codometer last applied to itself). The technical detail is
    /// English on purpose, with the home folder shortened to `~` in case the alert is photographed for support.
    private static func presentDataFolderFailure(_ error: FileAccessError) {
        let l10n = Localizer(language: Language.resolve(.system))
        let detail = error.description.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        presentFatalError(
            title: l10n.notification.launchFailedTitle,
            detail: l10n.notification.dataFolderFailedMessage(detail: detail),
            button: l10n.notification.quit
        )
    }

    private static func presentFatalError(title: String, detail: String, button: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: button)
        alert.runModal()
    }
}

/// What `AppController.persist` does with edited settings.
enum SettingsPersistence: Equatable {
    /// Save to disk and apply.
    case save
    /// Apply for this session only (read-only settings, a debug fixture).
    case memoryOnly
    /// Nothing (erasing all data).
    case skip

    static func plan(isReadOnly: Bool, isErasing: Bool, isDebugFixture: Bool) -> SettingsPersistence {
        if isErasing { return .skip }
        return isReadOnly || isDebugFixture ? .memoryOnly : .save
    }
}

/// Rate limit for VoiceOver reset announcements: at most one per account every `interval`.
struct ResetAnnouncementThrottle {
    static let interval: TimeInterval = 30

    private var lastAnnounced: [AccountID: Date] = [:]

    /// The accounts to announce now, each once and in first-mention order; records them as announced.
    mutating func accountsToAnnounce(_ accounts: [AccountID], now: Date) -> [AccountID] {
        var announced: [AccountID] = []
        for account in accounts where !announced.contains(account) {
            if let last = lastAnnounced[account], now.timeIntervalSince(last) < Self.interval, now >= last {
                continue
            }
            lastAnnounced[account] = now
            announced.append(account)
        }
        return announced
    }
}

/// Lets the store's actions reach the controller without a retain cycle. Every `TrackerActions` closure is passed
/// explicitly (none is left to its default), each to exactly one controller method.
@MainActor
final class ActionRouter {
    weak var controller: AppController?

    var actions: TrackerActions {
        TrackerActions(
            refresh: { [weak self] id in self?.controller?.refresh(id) },
            persistSettings: { [weak self] settings in self?.controller?.persist(settings) },
            discoverProfiles: { [weak self] in self?.controller?.discoverProfiles() ?? [] },
            revealDataFolder: { [weak self] in self?.controller?.revealDataFolder() },
            setLaunchAtLogin: { [weak self] enabled in self?.controller?.setLaunchAtLogin(enabled) },
            openSettings: { [weak self] in self?.controller?.openSettings() },
            quit: { NSApp.terminate(nil) },
            loadWindowHistory: { [weak self] accountID, bucketID, windowID, since in
                await self?.controller?.windowHistory(accountID: accountID, bucketID: bucketID, windowID: windowID, since: since)
            },
            loadTimeline: { [weak self] accountID, interval in
                await self?.controller?.timeline(accountID: accountID, interval: interval)
            },
            loadAttribution: { [weak self] accountID, interval, grouping in
                await self?.controller?.attribution(accountID: accountID, interval: interval, grouping: grouping)
            },
            loadDiagnostics: { [weak self] in await self?.controller?.loadDiagnostics() },
            runSystemCheck: { [weak self] in await self?.controller?.runSystemCheck() },
            copyDiagnosticsReport: { [weak self] report, includeAccountNames in
                self?.controller?.copyDiagnosticsReport(report, includeAccountNames: includeAccountNames)
            },
            exportDiagnostics: { [weak self] includeAccountNames in
                self?.controller?.exportDiagnostics(includeAccountNames: includeAccountNames)
            },
            appBuildInfo: { [weak self] in
                self?.controller?.appBuildInfo() ?? AppBuildInfo(version: "", build: "", locationKind: .other, licenseName: nil)
            },
            recentCrashReports: { [weak self] in self?.controller?.recentCrashReports() ?? [] },
            loginItemStatus: { [weak self] in self?.controller?.loginItemStatus() ?? .unavailable },
            openLoginItemsSettings: { [weak self] in self?.controller?.openLoginItemsSettings() },
            notificationAuthorization: { [weak self] in await self?.controller?.notificationAuthorization() ?? .notDetermined },
            openNotificationSettings: { [weak self] in self?.controller?.openNotificationSettings() },
            revealInFinder: { [weak self] url in self?.controller?.revealInFinder(url) },
            copyToPasteboard: { [weak self] text in self?.controller?.copyToPasteboard(text) },
            exportHistory: { [weak self] in self?.controller?.exportHistory() },
            eraseAllData: { [weak self] relaunch in self?.controller?.eraseAllData(relaunch: relaunch) },
            relaunch: { [weak self] in self?.controller?.relaunch() },
            showOnboarding: { [weak self] in self?.controller?.showOnboarding() },
            finishOnboarding: { [weak self] startTracking in self?.controller?.finishOnboarding(startTracking: startTracking) },
            inspectProfiles: { [weak self] in await self?.controller?.inspectProfiles() ?? [] },
            requestNotificationPermission: { [weak self] in await self?.controller?.requestNotificationPermission() ?? false },
            switchPresentationStyle: { [weak self] style in self?.controller?.switchPresentationStyle(style) },
            resetCardPosition: { [weak self] in self?.controller?.resetCardPosition() },
            moveIslandToDisplay: { [weak self] display in self?.controller?.moveIslandToDisplay(display) },
            refreshShortcutStatus: { [weak self] in self?.controller?.refreshShortcutStatus() },
            openStatusPage: { [weak self] provider in self?.controller?.openStatusPage(provider) }
        )
    }
}
