import CodometerCore
import CodometerL10n
import Foundation
import Observation

/// Commands the UI can issue. Implemented by the app shell, so the UI never talks to the engine directly.
@MainActor
public struct TrackerActions {
    public var refresh: (AccountID?) -> Void
    public var persistSettings: (AppSettings) -> Void
    public var discoverProfiles: () -> [DiscoveredAccount]
    public var revealDataFolder: () -> Void
    public var setLaunchAtLogin: (Bool) -> String?
    public var openSettings: () -> Void
    public var quit: () -> Void
    /// Recorded usage of one window (account, bucket id, window id) since a date; `nil` when unavailable.
    public var loadWindowHistory: @MainActor (AccountID, String, String, Date) async -> HistorySeries?
    /// One account's session timeline over an interval; `nil` when unavailable.
    public var loadTimeline: @MainActor (AccountID, DateInterval) async -> TimelineSnapshot?
    /// How one account's usage over an interval splits by project or session; `nil` without token data.
    public var loadAttribution: @MainActor (AccountID, DateInterval, AttributionGrouping) async -> AttributionReport?

    // MARK: Diagnostics and About

    /// The engine's diagnostics right now; `nil` when unavailable.
    public var loadDiagnostics: @MainActor () async -> EngineDiagnostics?
    /// Runs "Check System"; `nil` when unavailable.
    public var runSystemCheck: @MainActor () async -> SystemCheckReport?
    /// Copies the report's support text; the flag includes account names.
    public var copyDiagnosticsReport: @MainActor (SystemCheckReport, Bool) -> Void
    /// Saves the support text through a save panel; the flag includes account names, as in `copyDiagnosticsReport`.
    public var exportDiagnostics: @MainActor (Bool) -> Void
    public var appBuildInfo: @MainActor () -> AppBuildInfo
    /// Locally stored crash and hang reports, newest first.
    public var recentCrashReports: @MainActor () -> [CrashReportSummary]
    public var loginItemStatus: @MainActor () -> LoginItemStatus
    public var openLoginItemsSettings: @MainActor () -> Void
    public var notificationAuthorization: @MainActor () async -> NotificationAuthorization
    public var openNotificationSettings: @MainActor () -> Void
    /// Shows a file or folder in Finder (never follows a symbolic link).
    public var revealInFinder: @MainActor (URL) -> Void
    public var copyToPasteboard: @MainActor (String) -> Void

    // MARK: Data controls and onboarding

    public var exportHistory: @MainActor () -> Void
    /// Erases every file the app created, then quits or (`relaunch`) starts over.
    public var eraseAllData: @MainActor (_ relaunch: Bool) -> Void
    public var relaunch: @MainActor () -> Void
    public var showOnboarding: @MainActor () -> Void
    /// Closes onboarding and saves it as completed; `startTracking` starts the engine.
    public var finishOnboarding: @MainActor (_ startTracking: Bool) -> Void
    /// Readiness of the profile folders onboarding offers.
    public var inspectProfiles: @MainActor () async -> [ProfileReadiness]
    /// Asks for notification permission; `true` when granted.
    public var requestNotificationPermission: @MainActor () async -> Bool

    // MARK: Presentation, displays, shortcut and status

    public var switchPresentationStyle: @MainActor (PresentationStyle) -> Void
    public var resetCardPosition: @MainActor () -> Void
    public var moveIslandToDisplay: @MainActor (DisplayID) -> Void
    /// Registers the shortcut again and refreshes `TrackerStore.shortcutStatus`.
    public var refreshShortcutStatus: @MainActor () -> Void
    /// Opens the vendor's public status page in the browser.
    public var openStatusPage: @MainActor (ProviderKind) -> Void

    /// Every closure after `loadAttribution` defaults to doing nothing (or returning an empty or unavailable value), so
    /// callers that do not need a feature leave it out.
    public init(
        refresh: @escaping (AccountID?) -> Void,
        persistSettings: @escaping (AppSettings) -> Void,
        discoverProfiles: @escaping () -> [DiscoveredAccount],
        revealDataFolder: @escaping () -> Void,
        setLaunchAtLogin: @escaping (Bool) -> String?,
        openSettings: @escaping () -> Void,
        quit: @escaping () -> Void,
        loadWindowHistory: @escaping @MainActor (AccountID, String, String, Date) async -> HistorySeries? = { _, _, _, _ in nil },
        loadTimeline: @escaping @MainActor (AccountID, DateInterval) async -> TimelineSnapshot? = { _, _ in nil },
        loadAttribution: @escaping @MainActor (AccountID, DateInterval, AttributionGrouping) async -> AttributionReport? = { _, _, _ in nil },
        loadDiagnostics: @escaping @MainActor () async -> EngineDiagnostics? = { nil },
        runSystemCheck: @escaping @MainActor () async -> SystemCheckReport? = { nil },
        copyDiagnosticsReport: @escaping @MainActor (SystemCheckReport, Bool) -> Void = { _, _ in },
        exportDiagnostics: @escaping @MainActor (Bool) -> Void = { _ in },
        appBuildInfo: @escaping @MainActor () -> AppBuildInfo = { AppBuildInfo(version: "", build: "", locationKind: .other, licenseName: nil) },
        recentCrashReports: @escaping @MainActor () -> [CrashReportSummary] = { [] },
        loginItemStatus: @escaping @MainActor () -> LoginItemStatus = { .unavailable },
        openLoginItemsSettings: @escaping @MainActor () -> Void = {},
        notificationAuthorization: @escaping @MainActor () async -> NotificationAuthorization = { .notDetermined },
        openNotificationSettings: @escaping @MainActor () -> Void = {},
        revealInFinder: @escaping @MainActor (URL) -> Void = { _ in },
        copyToPasteboard: @escaping @MainActor (String) -> Void = { _ in },
        exportHistory: @escaping @MainActor () -> Void = {},
        eraseAllData: @escaping @MainActor (_ relaunch: Bool) -> Void = { _ in },
        relaunch: @escaping @MainActor () -> Void = {},
        showOnboarding: @escaping @MainActor () -> Void = {},
        finishOnboarding: @escaping @MainActor (_ startTracking: Bool) -> Void = { _ in },
        inspectProfiles: @escaping @MainActor () async -> [ProfileReadiness] = { [] },
        requestNotificationPermission: @escaping @MainActor () async -> Bool = { false },
        switchPresentationStyle: @escaping @MainActor (PresentationStyle) -> Void = { _ in },
        resetCardPosition: @escaping @MainActor () -> Void = {},
        moveIslandToDisplay: @escaping @MainActor (DisplayID) -> Void = { _ in },
        refreshShortcutStatus: @escaping @MainActor () -> Void = {},
        openStatusPage: @escaping @MainActor (ProviderKind) -> Void = { _ in }
    ) {
        self.refresh = refresh
        self.persistSettings = persistSettings
        self.discoverProfiles = discoverProfiles
        self.revealDataFolder = revealDataFolder
        self.setLaunchAtLogin = setLaunchAtLogin
        self.openSettings = openSettings
        self.quit = quit
        self.loadWindowHistory = loadWindowHistory
        self.loadTimeline = loadTimeline
        self.loadAttribution = loadAttribution
        self.loadDiagnostics = loadDiagnostics
        self.runSystemCheck = runSystemCheck
        self.copyDiagnosticsReport = copyDiagnosticsReport
        self.exportDiagnostics = exportDiagnostics
        self.appBuildInfo = appBuildInfo
        self.recentCrashReports = recentCrashReports
        self.loginItemStatus = loginItemStatus
        self.openLoginItemsSettings = openLoginItemsSettings
        self.notificationAuthorization = notificationAuthorization
        self.openNotificationSettings = openNotificationSettings
        self.revealInFinder = revealInFinder
        self.copyToPasteboard = copyToPasteboard
        self.exportHistory = exportHistory
        self.eraseAllData = eraseAllData
        self.relaunch = relaunch
        self.showOnboarding = showOnboarding
        self.finishOnboarding = finishOnboarding
        self.inspectProfiles = inspectProfiles
        self.requestNotificationPermission = requestNotificationPermission
        self.switchPresentationStyle = switchPresentationStyle
        self.resetCardPosition = resetCardPosition
        self.moveIslandToDisplay = moveIslandToDisplay
        self.refreshShortcutStatus = refreshShortcutStatus
        self.openStatusPage = openStatusPage
    }
}

/// A surface that shows the vendor service status (the deck header chip or the card pill). Status checks run only
/// while at least one of them is visible.
public enum StatusSurface: Hashable, Sendable {
    case islandDeck
    case popover
    case card
}

/// A profile found on disk that is not tracked yet.
public struct DiscoveredAccount: Hashable, Sendable, Identifiable {
    public let provider: ProviderKind
    public let directory: ProfileDirectory
    public let suggestedLabel: String

    public init(provider: ProviderKind, directory: ProfileDirectory, suggestedLabel: String) {
        self.provider = provider
        self.directory = directory
        self.suggestedLabel = suggestedLabel
    }

    public var id: String { "\(provider.rawValue):\(directory.path)" }
}

/// The single source of truth for SwiftUI views.
@MainActor
@Observable
public final class TrackerStore {
    public private(set) var state: TrackerState
    public private(set) var settings: AppSettings
    public private(set) var now: Date
    /// The interface language (`settings.general.language`, `.system` resolved) with the user's region. Changes only
    /// when the language setting, the system language order or the region changes, so views re-render once.
    public private(set) var localizer: Localizer
    /// Limit resets waiting to be celebrated on the rings; entries expire on their own (one sleeping task).
    public private(set) var ceremonies = CeremonyBoard()
    /// Whether the global shortcut is registered, off, or unavailable with alternatives.
    public private(set) var shortcutStatus: ShortcutStatus = .off
    /// Connected displays, in the order the app lists them.
    public private(set) var displays: [DisplayDescriptor] = []
    /// How refreshes and live effects currently adapt to power conditions.
    public private(set) var energy: EnergyDecision = .normal
    /// Vendor service status, in memory only.
    public private(set) var serviceStatus: ServiceStatusBoard = .empty
    /// Notices about the app's own data (settings recovered or read-only, history problems), until dismissed.
    public private(set) var notices: [AppNotice] = []
    /// The settings come from a newer Codometer: edits apply for this session only and are never saved.
    public private(set) var isSettingsReadOnly = false
    /// The status surfaces on screen right now.
    public private(set) var statusDemand: Set<StatusSurface> = []

    /// Never-ending effects (orbits, pulses) may run; off while the energy policy pauses them.
    public var allowsLiveEffects: Bool { !energy.pausesLiveEffects }

    /// Called whenever `statusDemand` changes, so the status service starts or stops checking.
    @ObservationIgnored public var onStatusDemandChange: (@MainActor (Set<StatusSurface>) -> Void)?

    @ObservationIgnored public let actions: TrackerActions
    /// Usage history, timelines and attribution, loaded only when a view requests them.
    @ObservationIgnored public let analytics: AnalyticsCache
    /// The macOS language order `.system` follows. The app reads the global setting, which its own `AppleLanguages`
    /// override does not hide.
    @ObservationIgnored private let preferredLanguages: @MainActor () -> [String]
    /// Supplies the region, hour cycle and first weekday.
    @ObservationIgnored private let region: @MainActor () -> Locale
    /// Sleeps until the next ceremony expires, then prunes the board.
    @ObservationIgnored private var ceremonyExpiryTask: Task<Void, Never>?

    /// `tick` ignores dates closer than this to the current `now`, so several prepares in one interaction never
    /// re-render time-dependent text again.
    public static let minimumTickInterval: TimeInterval = 1

    public init(
        state: TrackerState,
        settings: AppSettings,
        now: Date,
        actions: TrackerActions,
        preferredLanguages: @escaping @MainActor () -> [String] = { Locale.preferredLanguages },
        region: @escaping @MainActor () -> Locale = { .autoupdatingCurrent }
    ) {
        self.state = state
        self.settings = settings
        self.now = now
        self.actions = actions
        self.preferredLanguages = preferredLanguages
        self.region = region
        localizer = Self.makeLocalizer(settings.general.language, preferredLanguages: preferredLanguages(), region: region())
        analytics = AnalyticsCache(actions: actions)
    }

    /// Rebuilds the localizer after the system language order or the region changed
    /// (`NSLocale.currentLocaleDidChangeNotification`). Does nothing when the result is the same.
    public func refreshLocale() {
        updateLocalizer()
    }

    private func updateLocalizer() {
        let updated = Self.makeLocalizer(settings.general.language, preferredLanguages: preferredLanguages(), region: region())
        guard updated != localizer else { return }
        localizer = updated
    }

    nonisolated static func makeLocalizer(_ preference: LanguagePreference, preferredLanguages: [String], region: Locale) -> Localizer {
        Localizer(language: Language.resolve(preference, preferredLanguages: preferredLanguages), region: region)
    }

    public func receive(_ newState: TrackerState) {
        #if DEBUG
        guard !isDebugFixtureActive else { return }
        #endif
        guard newState != state else { return }
        let previous = state
        state = newState
        analytics.stateChanged(from: previous, to: newState)
    }

    /// Moves the clock time-dependent text reads. Changes of less than `minimumTickInterval` are ignored.
    public func tick(_ date: Date) {
        #if DEBUG
        guard !isDebugFixtureActive else { return }
        #endif
        guard abs(date.timeIntervalSince(now)) >= Self.minimumTickInterval else { return }
        now = date
    }

    // MARK: - Reset ceremonies

    /// Stores ceremonies for resets the engine detected, when the user celebrates resets. `now` is on the store's
    /// clock (normally `Date()`).
    public func celebrate(_ events: [WindowResetEvent], now: Date) {
        guard settings.appearance.celebratesResets, !events.isEmpty else { return }
        let fractions = Dictionary(events.map { ($0.id, $0.previousUsed.value / 100) }, uniquingKeysWith: { first, _ in first })
        var board = ceremonies
        board.insert(events, previousFractions: fractions, now: now)
        guard board != ceremonies else { return }
        ceremonies = board
        scheduleCeremonyExpiry(reference: now)
    }

    /// A surface played a ceremony; call it outside a view update (e.g. on the next main-actor turn).
    public func markCeremonyPlayed(_ id: UUID, on surface: CeremonySurface) {
        var board = ceremonies
        board.markPlayed(id, on: surface)
        guard board != ceremonies else { return }
        ceremonies = board
    }

    /// One sleeping task until the earliest expiry. `reference` maps the board's clock onto the wall clock, so a board
    /// filled with a fixed test date still expires after its real lifetime.
    private func scheduleCeremonyExpiry(reference: Date) {
        ceremonyExpiryTask?.cancel()
        ceremonyExpiryTask = nil
        guard let expiry = ceremonies.nextExpiry else { return }
        let offset = reference.timeIntervalSinceNow
        let delay = max(0, expiry.timeIntervalSince(reference))
        ceremonyExpiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay), tolerance: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            let boardNow = Date().addingTimeInterval(offset)
            var board = ceremonies
            board.prune(now: boardNow)
            if board != ceremonies {
                ceremonies = board
            }
            scheduleCeremonyExpiry(reference: boardNow)
        }
    }

    // MARK: - App state

    public func setShortcutStatus(_ status: ShortcutStatus) {
        guard status != shortcutStatus else { return }
        shortcutStatus = status
    }

    public func setDisplays(_ newDisplays: [DisplayDescriptor]) {
        guard newDisplays != displays else { return }
        displays = newDisplays
    }

    public func setEnergy(_ decision: EnergyDecision) {
        guard decision != energy else { return }
        energy = decision
    }

    public func setServiceStatus(_ board: ServiceStatusBoard) {
        guard board != serviceStatus else { return }
        serviceStatus = board
    }

    public func setNotices(_ newNotices: [AppNotice]) {
        guard newNotices != notices else { return }
        notices = newNotices
    }

    public func dismissNotice(_ id: AppNotice.ID) {
        guard notices.contains(where: { $0.id == id }) else { return }
        notices.removeAll { $0.id == id }
    }

    public func setSettingsReadOnly(_ readOnly: Bool) {
        guard readOnly != isSettingsReadOnly else { return }
        isSettingsReadOnly = readOnly
    }

    /// A status surface appeared or disappeared; `onStatusDemandChange` hears about every change.
    public func setStatusSurface(_ surface: StatusSurface, visible: Bool) {
        var demand = statusDemand
        if visible {
            demand.insert(surface)
        } else {
            demand.remove(surface)
        }
        guard demand != statusDemand else { return }
        statusDemand = demand
        onStatusDemandChange?(demand)
    }

    /// Every enabled account, in settings order.
    public var presentations: [AccountPresentation] {
        presentations(of: state.accounts.filter(\.profile.isEnabled))
    }

    /// The enabled accounts the island shows: all of them, or only the group `railGroupFilter` names.
    public var visiblePresentations: [AccountPresentation] {
        presentations(of: visibleAccounts)
    }

    /// Waiting sessions of enabled accounts (whatever the group filter), longest wait first.
    public var attentionQueue: [AttentionItem] {
        state.attentionQueue
    }

    /// Whether any session of an enabled account waits for the user.
    public var hasWaiting: Bool {
        state.accounts.contains { account in
            account.profile.isEnabled && account.sessions.contains { $0.activity == .waiting }
        }
    }

    /// The worst band over the visible accounts' main-bucket windows; `nil` when no visible account has a reading.
    public var urgency: UsageBand? {
        visibleAccounts
            .compactMap { AccountPresentation.worstBand(of: $0.reading, thresholds: settings.appearance.bands) }
            .max()
    }

    private var visibleAccounts: [AccountStatus] {
        let filter = settings.appearance.railGroupFilter
        return state.accounts.filter { account in
            account.profile.isEnabled && (filter == nil || account.profile.groupID == filter)
        }
    }

    /// Styles are resolved once per call over every account in settings, so automatic tints never depend on filters.
    private func presentations(of accounts: [AccountStatus]) -> [AccountPresentation] {
        let styles = AccountStyleResolver.styles(for: settings.accounts)
        return accounts.map { AccountPresentation(status: $0, settings: settings, now: now, l10n: localizer, style: styles[$0.id]) }
    }

    public func refresh(_ accountID: AccountID? = nil) {
        actions.refresh(accountID)
    }

    #if DEBUG
    /// A debug fixture replaced the state: engine updates and clock ticks are ignored until the app quits.
    @ObservationIgnored public private(set) var isDebugFixtureActive = false

    /// Replaces state, settings and the clock with synthetic data in memory (debug harness `fixture` step). Nothing is
    /// persisted; engine updates are ignored from now on.
    public func debugInstallFixture(state newState: TrackerState, settings newSettings: AppSettings, now fixtureNow: Date) {
        isDebugFixtureActive = true
        let previous = state
        state = newState
        settings = newSettings
        now = fixtureNow
        ceremonies = CeremonyBoard()
        ceremonyExpiryTask?.cancel()
        ceremonyExpiryTask = nil
        updateLocalizer()
        analytics.stateChanged(from: previous, to: newState)
    }

    /// Changes settings in memory only, never persisted. Only the debug scenario harness calls it, e.g. to show an
    /// empty group without touching `settings.json`.
    public func debugOverrideSettings(_ change: (inout AppSettings) -> Void) {
        var copy = settings
        change(&copy)
        guard copy != settings else { return }
        settings = copy
        updateLocalizer()
    }
    #endif

    /// Applies a change to a copy, validates it, and persists it only if it is valid and different.
    @discardableResult
    public func updateSettings(_ change: (inout AppSettings) throws(ValidationError) -> Void) -> ValidationError? {
        var copy = settings
        do throws(ValidationError) {
            try change(&copy)
        } catch {
            return error
        }
        guard copy != settings else { return nil }
        settings = copy
        updateLocalizer()
        actions.persistSettings(copy)
        return nil
    }

    @discardableResult
    public func replaceAccount(_ account: AccountProfile) -> ValidationError? {
        updateSettings { (settings: inout AppSettings) throws(ValidationError) in
            let accounts = settings.accounts.map { $0.id == account.id ? account : $0 }
            settings = try settings.replacingAccounts(accounts)
        }
    }

    @discardableResult
    public func addAccount(_ account: AccountProfile) -> ValidationError? {
        updateSettings { (settings: inout AppSettings) throws(ValidationError) in
            settings = try settings.replacingAccounts(settings.accounts + [account])
        }
    }

    public func removeAccount(_ id: AccountID) {
        updateSettings { (settings: inout AppSettings) throws(ValidationError) in
            settings = try settings.replacingAccounts(settings.accounts.filter { $0.id != id })
        }
    }

    public func moveAccount(_ id: AccountID, by offset: Int) {
        updateSettings { (settings: inout AppSettings) throws(ValidationError) in
            var accounts = settings.accounts
            guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
            let target = index + offset
            guard accounts.indices.contains(target) else { return }
            accounts.swapAt(index, target)
            settings = try settings.replacingAccounts(accounts)
        }
    }
}
