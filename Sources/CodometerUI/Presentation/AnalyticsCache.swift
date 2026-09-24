import CodometerCore
import CodometerL10n
import Foundation
import Observation

/// A period the analytics views summarise, always ending now.
public enum AnalyticsRange: String, Sendable, CaseIterable, Identifiable {
    case fiveHours
    case day
    case week

    public var id: String { rawValue }

    /// The range chip: "5h", "24h", "7d" | «5 ч», «24 ч», «7 дн».
    public func title(l10n: Localizer) -> String {
        switch self {
        case .fiveHours: l10n.analyticsFormat.fiveHours
        case .day: l10n.analyticsFormat.day
        case .week: l10n.analyticsFormat.week
        }
    }

    public var duration: TimeInterval {
        switch self {
        case .fiveHours: 5 * 3_600
        case .day: 24 * 3_600
        case .week: 7 * 86_400
        }
    }

    /// The range as an interval ending at `now`.
    public func interval(endingAt now: Date) -> DateInterval {
        DateInterval(start: now.addingTimeInterval(-duration), duration: duration)
    }
}

/// Usage history, timelines and attribution for the analytics views, loaded on demand through `TrackerActions`.
///
/// Nothing is loaded until a view asks: getters only return what is cached, and `request…` methods start a load.
/// Requests are cheap to repeat, so views may call them on appear and whenever the data they show changes:
/// - a load already in flight for the same key is not started again;
/// - a key is reloaded at most once per `minimumReloadInterval`, and only after it was invalidated;
/// - a key invalidates when its account's reading (`capturedAt`) or sessions change (see `TrackerStore.receive`).
///
/// A request for an invalidated key that arrives inside the throttle interval is remembered and runs once the
/// interval passes, so the last change is never lost. Invalidation alone never starts work.
@MainActor
@Observable
public final class AnalyticsCache {
    public static let minimumReloadInterval: TimeInterval = 60

    private var seriesValues: [SeriesKey: HistorySeries] = [:]
    private var timelineValues: [TimelineKey: TimelineSnapshot] = [:]
    private var attributionValues: [AttributionKey: AttributionReport] = [:]

    @ObservationIgnored private let actions: TrackerActions
    @ObservationIgnored private let reloadInterval: TimeInterval
    @ObservationIgnored private let clock: @MainActor () -> Date
    @ObservationIgnored private var entries: [Key: Entry] = [:]
    @ObservationIgnored private var lastToken = 0

    public init(
        actions: TrackerActions,
        minimumReloadInterval: TimeInterval = AnalyticsCache.minimumReloadInterval,
        clock: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.actions = actions
        reloadInterval = max(0, minimumReloadInterval)
        self.clock = clock
    }

    // MARK: - Cached values

    public func series(account: AccountID, bucket: String, window: String) -> HistorySeries? {
        seriesValues[SeriesKey(account: account, bucket: bucket, window: window)]
    }

    public func timeline(account: AccountID, range: AnalyticsRange) -> TimelineSnapshot? {
        timelineValues[TimelineKey(account: account, range: range)]
    }

    public func attribution(account: AccountID, range: AnalyticsRange, grouping: AttributionGrouping) -> AttributionReport? {
        attributionValues[AttributionKey(account: account, range: range, grouping: grouping)]
    }

    // MARK: - Requests

    /// Loads one window's usage since `since` (usually the window's start). A different `since` than the last
    /// load's counts as a change and reloads under the usual throttle.
    public func requestSeries(account: AccountID, bucket: String, window: String, since: Date) {
        request(.series(SeriesKey(account: account, bucket: bucket, window: window)), since: since)
    }

    /// Loads the account's timeline over `range`, ending when the load starts.
    public func requestTimeline(account: AccountID, range: AnalyticsRange) {
        request(.timeline(TimelineKey(account: account, range: range)))
    }

    /// Loads how the account's usage over `range` splits by `grouping`, ending when the load starts.
    public func requestAttribution(account: AccountID, range: AnalyticsRange, grouping: AttributionGrouping) {
        request(.attribution(AttributionKey(account: account, range: range, grouping: grouping)))
    }

    // MARK: - Invalidation

    /// Marks everything cached for the account as out of date. Cached values stay visible until reloaded.
    public func invalidate(account: AccountID) {
        for (key, var entry) in entries where key.accountID == account && !entry.isDirty {
            entry.isDirty = true
            entries[key] = entry
        }
    }

    /// Forgets the account entirely, cancelling its loads.
    public func remove(account: AccountID) {
        for (key, entry) in entries where key.accountID == account {
            entry.task?.cancel()
            entry.deferred?.cancel()
            entries[key] = nil
        }
        if seriesValues.keys.contains(where: { $0.account == account }) {
            seriesValues = seriesValues.filter { $0.key.account != account }
        }
        if timelineValues.keys.contains(where: { $0.account == account }) {
            timelineValues = timelineValues.filter { $0.key.account != account }
        }
        if attributionValues.keys.contains(where: { $0.account == account }) {
            attributionValues = attributionValues.filter { $0.key.account != account }
        }
    }

    /// Applies a state update: removed accounts are forgotten, accounts whose data changed are invalidated.
    func stateChanged(from old: TrackerState, to new: TrackerState) {
        let changes = Self.changes(from: old, to: new)
        for account in changes.removed {
            remove(account: account)
        }
        for account in changes.changed {
            invalidate(account: account)
        }
    }

    /// Accounts that disappeared, and accounts whose reading time or sessions differ between two states.
    nonisolated static func changes(from old: TrackerState, to new: TrackerState) -> (changed: Set<AccountID>, removed: Set<AccountID>) {
        let previous = Dictionary(old.accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let current = Set(new.accounts.map(\.id))
        var changed = Set<AccountID>()
        for account in new.accounts {
            guard let before = previous[account.id] else { continue }
            if before.reading?.capturedAt != account.reading?.capturedAt || before.sessions != account.sessions {
                changed.insert(account.id)
            }
        }
        return (changed, Set(previous.keys).subtracting(current))
    }

    // MARK: - Loading

    private func request(_ key: Key, since: Date? = nil) {
        var entry = entries[key] ?? Entry()
        if let since, since != entry.since {
            if entry.since != nil { entry.isDirty = true }
            entry.since = since
        }
        if entry.task != nil {
            // Deduplicated; a changed key reloads after this load, within the throttle.
            if entry.isDirty { entry.wantsReload = true }
            entries[key] = entry
            return
        }
        entries[key] = entry
        guard let lastStarted = entry.lastStarted else {
            start(key)
            return
        }
        guard entry.isDirty else { return }
        reload(key, lastStarted: lastStarted)
    }

    /// Starts a reload now if the throttle allows, otherwise once it does.
    private func reload(_ key: Key, lastStarted: Date) {
        let wait = lastStarted.addingTimeInterval(reloadInterval).timeIntervalSince(clock())
        if wait <= 0 {
            start(key)
        } else {
            scheduleDeferred(key, after: wait)
        }
    }

    private func start(_ key: Key) {
        guard var entry = entries[key] else { return }
        entry.deferred?.cancel()
        entry.deferred = nil
        entry.isDirty = false
        entry.wantsReload = false
        let startedAt = clock()
        entry.lastStarted = startedAt
        lastToken += 1
        let token = lastToken
        entry.token = token

        let actions = actions
        let since = entry.since ?? .distantPast
        entry.task = Task { [weak self] in
            switch key {
            case .series(let series):
                let value = await actions.loadWindowHistory(series.account, series.bucket, series.window, since)
                self?.complete(key, token: token) { $0.seriesValues[series] = value }
            case .timeline(let timeline):
                let interval = timeline.range.interval(endingAt: startedAt)
                let value = await actions.loadTimeline(timeline.account, interval)
                self?.complete(key, token: token) { $0.timelineValues[timeline] = value }
            case .attribution(let attribution):
                let interval = attribution.range.interval(endingAt: startedAt)
                let value = await actions.loadAttribution(attribution.account, interval, attribution.grouping)
                self?.complete(key, token: token) { $0.attributionValues[attribution] = value }
            }
        }
        entries[key] = entry
    }

    private func complete(_ key: Key, token: Int, store: (AnalyticsCache) -> Void) {
        // A removed account or a superseded load drops its result.
        guard var entry = entries[key], entry.token == token else { return }
        store(self)
        entry.task = nil
        entries[key] = entry
        if entry.isDirty, entry.wantsReload, let lastStarted = entry.lastStarted {
            reload(key, lastStarted: lastStarted)
        }
    }

    private func scheduleDeferred(_ key: Key, after delay: TimeInterval) {
        guard var entry = entries[key], entry.deferred == nil else { return }
        entry.deferred = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay), tolerance: .seconds(min(1, delay * 0.1)))
            guard !Task.isCancelled else { return }
            self?.runDeferred(key)
        }
        entries[key] = entry
    }

    private func runDeferred(_ key: Key) {
        guard var entry = entries[key] else { return }
        entry.deferred = nil
        entries[key] = entry
        guard entry.task == nil, entry.isDirty else { return }
        start(key)
    }

    // MARK: - Test support

    /// Whether a load for the key is in flight or scheduled.
    func isBusy(series account: AccountID, bucket: String, window: String) -> Bool {
        entries[.series(SeriesKey(account: account, bucket: bucket, window: window))].map { $0.task != nil || $0.deferred != nil } ?? false
    }

    /// Waits until no load is in flight (scheduled reloads are not awaited).
    func settle() async {
        while let task = entries.values.lazy.compactMap(\.task).first {
            await task.value
        }
    }

    // MARK: - Keys

    private struct SeriesKey: Hashable {
        let account: AccountID
        let bucket: String
        let window: String
    }

    private struct TimelineKey: Hashable {
        let account: AccountID
        let range: AnalyticsRange
    }

    private struct AttributionKey: Hashable {
        let account: AccountID
        let range: AnalyticsRange
        let grouping: AttributionGrouping
    }

    private enum Key: Hashable {
        case series(SeriesKey)
        case timeline(TimelineKey)
        case attribution(AttributionKey)

        var accountID: AccountID {
            switch self {
            case .series(let key): key.account
            case .timeline(let key): key.account
            case .attribution(let key): key.account
            }
        }
    }

    private struct Entry {
        var lastStarted: Date?
        /// Invalidated since the latest load started.
        var isDirty = false
        /// A request arrived for a dirty key while it was loading.
        var wantsReload = false
        /// The `since` of series requests.
        var since: Date?
        var token = 0
        var task: Task<Void, Never>?
        var deferred: Task<Void, Never>?
    }
}
