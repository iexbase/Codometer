import Foundation

/// A window as it stands at a timeline entry's date.
///
/// The snapshot is only rewritten while the app runs, so the widget projects it forward: once a window's reset
/// has passed its usage restarts at zero and the reset moves on by whole window lengths. Such a window is marked
/// `hasResetSinceCapture`, because its real usage is unknown until the app reads it again.
public struct WidgetWindowState: Hashable, Sendable, Identifiable {
    public let source: WidgetWindow
    /// The window with usage and reset time projected to `date`.
    public let window: LimitWindow
    public let hasResetSinceCapture: Bool
    public let band: UsageBand
    public let progress: WindowProgress
    /// Where usage lands by the reset at the average pace since the window started, worked out at the entry's date
    /// from the projected window. `nil` whenever there is nothing worth drawing (`UsageForecast`), which includes
    /// every window that has reset since the app last read it, because its usage is back at zero — and whenever the
    /// user turned "Forecast at reset" off, so the ring and what VoiceOver says can never disagree.
    public let forecast: UsageForecast?

    public init(source: WidgetWindow, date: Date, thresholds: BandThresholds, showsForecast: Bool = true) {
        self.source = source
        let projected = Self.project(source.window, to: date)
        window = projected
        hasResetSinceCapture = source.window.hasReset(at: date)
        band = UsageBand(used: projected.used, thresholds: thresholds)
        progress = WindowProgress(window: projected, now: date)
        forecast = showsForecast ? UsageForecast(window: projected, now: date, thresholds: thresholds) : nil
    }

    public var id: String { source.id }
    public var title: String { source.title }
    public var isExhausted: Bool { window.used.isExhausted }

    static func project(_ window: LimitWindow, to date: Date) -> LimitWindow {
        guard let resetsAt = window.resetsAt, resetsAt <= date else { return window }
        var nextReset: Date?
        if let length = window.duration?.timeInterval, length > 0 {
            let periods = (date.timeIntervalSince(resetsAt) / length).rounded(.down) + 1
            nextReset = resetsAt.addingTimeInterval(periods * length)
        }
        return (try? LimitWindow(
            id: window.id,
            scope: window.scope,
            used: .zero,
            duration: window.duration,
            resetsAt: nextReset,
            label: window.label
        )) ?? window
    }
}

/// An account as the widget draws it at one timeline entry.
public struct WidgetAccountState: Hashable, Sendable, Identifiable {
    /// A reading older than this looks stale in the widget. Twice the island's rule: WidgetKit reloads a widget only
    /// a few dozen times a day, so the app publishes routine changes every `WidgetExportPolicy.routineGap` and flags
    /// really stale readings itself (`WidgetAccount.isStale`); this age check covers an app that stopped running.
    public static let staleAfter = 2 * AccountStatus.defaultStaleAfter

    public let account: WidgetAccount
    public let date: Date
    public let windows: [WidgetWindowState]
    /// The main-bucket window with the highest usage (ties go to the shorter window): what the ring shows.
    public let binding: WidgetWindowState?
    /// The exhausted main-bucket window that resets last — the one keeping the account blocked.
    public let blocking: WidgetWindowState?
    public let isBlocked: Bool
    public let isStale: Bool

    public init(account: WidgetAccount, date: Date, thresholds: BandThresholds, showsForecast: Bool = true) {
        self.account = account
        self.date = date
        let windows = account.windows.map {
            WidgetWindowState(source: $0, date: date, thresholds: thresholds, showsForecast: showsForecast)
        }
        self.windows = windows
        let main = windows.filter(\.source.isMainBucket)
        binding = Self.binding(in: main)
        let blocking = Self.blocking(in: main)
        self.blocking = blocking
        let anyReset = windows.contains(where: \.hasResetSinceCapture)
        isBlocked = blocking != nil || (account.isLimitReached && !main.contains(where: \.hasResetSinceCapture))
        let isOld = account.capturedAt.map { date.timeIntervalSince($0) > Self.staleAfter } ?? false
        isStale = account.hasReading && (account.isStale || isOld || anyReset)
    }

    public var id: AccountID { account.id }
    public var hasReading: Bool { account.hasReading }

    /// The worst band over the main bucket; a provider-reported limit counts as exhausted.
    public var worstBand: UsageBand? {
        guard hasReading else { return nil }
        if isBlocked { return .exhausted }
        return windows.filter(\.source.isMainBucket).map(\.band).max()
    }

    /// The reset that matters most: the blocking window's while blocked, otherwise the ring window's.
    public var headlineReset: Date? {
        (blocking ?? binding)?.window.resetsAt
    }

    /// Up to `limit` windows in display order. The ring's window always makes the cut, replacing the last
    /// one shown, so the number next to the ring is never missing from the list.
    public func windowsForDisplay(limit: Int) -> [WidgetWindowState] {
        guard limit > 0 else { return [] }
        var shown = Array(windows.prefix(limit))
        if let binding, !shown.contains(where: { $0.id == binding.id }) {
            shown[shown.count - 1] = binding
        }
        return shown
    }

    static func binding(in windows: [WidgetWindowState]) -> WidgetWindowState? {
        var best: WidgetWindowState?
        for window in windows {
            guard let current = best else {
                best = window
                continue
            }
            if window.window.used > current.window.used
                || (window.window.used == current.window.used && durationRank(window) < durationRank(current)) {
                best = window
            }
        }
        return best
    }

    /// Unknown resets count as the latest, so the account never looks available earlier than it is.
    static func blocking(in windows: [WidgetWindowState]) -> WidgetWindowState? {
        windows.filter(\.isExhausted).max { lhs, rhs in
            switch (lhs.window.resetsAt, rhs.window.resetsAt) {
            case let (left?, right?): left < right
            case (.some, nil): true
            case (nil, _): false
            }
        }
    }

    private static func durationRank(_ window: WidgetWindowState) -> Int {
        window.window.duration?.minutes ?? .max
    }
}

extension WidgetSnapshot {
    /// The longest a timeline looks ahead; the app reloads timelines whenever the numbers change.
    public static let timelineHorizon: TimeInterval = 12 * 60 * 60
    public static let maximumTimelineEntries = 24

    public func states(at date: Date) -> [WidgetAccountState] {
        accounts.map {
            WidgetAccountState(account: $0, date: date, thresholds: bands, showsForecast: showsForecast)
        }
    }

    /// Entry dates: `now`, every reset (projected across whole windows), the moment each countdown switches to
    /// minutes (`WidgetCountdown.minutesThreshold` before the reset) and every moment a reading turns stale within
    /// the horizon, sorted, at most `maximumTimelineEntries`.
    public func timelineDates(from now: Date, horizon: TimeInterval = timelineHorizon) -> [Date] {
        let end = now.addingTimeInterval(max(0, horizon))
        var moments: [Date] = []
        for account in accounts {
            if let capturedAt = account.capturedAt, !account.isStale {
                moments.append(capturedAt.addingTimeInterval(WidgetAccountState.staleAfter + 1))
            }
            for item in account.windows {
                guard let resetsAt = item.window.resetsAt else { continue }
                var reset = resetsAt
                let length = item.window.duration?.timeInterval ?? 0
                if reset <= now, length > 0 {
                    reset = WidgetWindowState.project(item.window, to: now).resetsAt ?? reset
                }
                while reset.addingTimeInterval(-WidgetCountdown.minutesThreshold) <= end, moments.count < 256 {
                    moments.append(reset.addingTimeInterval(-WidgetCountdown.minutesThreshold))
                    moments.append(reset)
                    guard length > 0 else { break }
                    reset = reset.addingTimeInterval(length)
                }
            }
        }
        var dates = [now]
        for moment in moments.sorted() where moment > now && moment <= end {
            if let last = dates.last, moment.timeIntervalSince(last) < 1 { continue }
            dates.append(moment)
            if dates.count == Self.maximumTimelineEntries { break }
        }
        return dates
    }
}

/// How a reset countdown is written at a timeline entry.
///
/// `Text(date, style: .relative)` reads "2 hr, 13 min" but ticks seconds within the last hour ("47 min, 11 sec"), which
/// is restless on the desktop. So within `minutesThreshold` of the reset the widget switches to a minutes-only
/// countdown; the timeline has an entry at that moment.
public enum WidgetCountdown: Hashable, Sendable {
    /// Hours and days, abbreviated.
    case hoursAndDays
    /// Whole minutes, then seconds in the last minute.
    case minutes

    public static let minutesThreshold: TimeInterval = 60 * 60

    public static func style(until reset: Date, at date: Date) -> WidgetCountdown {
        reset.timeIntervalSince(date) > minutesThreshold ? .hoursAndDays : .minutes
    }
}

/// Which accounts the small and medium widgets feature.
public enum WidgetSelection {
    /// The most constrained account: blocked first, then the highest ring usage; accounts without a reading last.
    /// Ties keep settings order.
    public static func mostConstrained(_ states: [WidgetAccountState]) -> WidgetAccountState? {
        ranked(states).first
    }

    /// The `limit` most constrained accounts, returned in settings order so the layout does not shuffle.
    public static func featured(_ states: [WidgetAccountState], limit: Int) -> [WidgetAccountState] {
        guard limit > 0 else { return [] }
        guard states.count > limit else { return states }
        let chosen = Set(ranked(states).prefix(limit).map(\.id))
        return states.filter { chosen.contains($0.id) }
    }

    /// Indices of `states`, most constrained first.
    public static func priorityOrder(_ states: [WidgetAccountState]) -> [Int] {
        rankedIndices(states)
    }

    static func ranked(_ states: [WidgetAccountState]) -> [WidgetAccountState] {
        rankedIndices(states).map { states[$0] }
    }

    private static func rankedIndices(_ states: [WidgetAccountState]) -> [Int] {
        states.indices.sorted { left, right in
            let lhs = states[left]
            let rhs = states[right]
            if lhs.hasReading != rhs.hasReading { return lhs.hasReading }
            if lhs.isBlocked != rhs.isBlocked { return lhs.isBlocked }
            let leftUsed = lhs.binding?.window.used.value ?? 0
            let rightUsed = rhs.binding?.window.used.value ?? 0
            if leftUsed != rightUsed { return leftUsed > rightUsed }
            return left < right
        }
    }
}
