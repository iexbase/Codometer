import CodometerL10n
import Foundation

/// The parts of a snapshot whose change the widget must show at once.
public struct WidgetSignificance: Hashable, Sendable {
    public struct Account: Hashable, Sendable {
        public let id: AccountID
        /// Label, plan, e-mail, notice, tint and monogram: renaming an account, hiding its e-mail or giving it a new
        /// identity mark must reach the widget at once.
        public let identity: [String?]
        public let hasReading: Bool
        public let isBlocked: Bool
        /// Whether the account already looks stale (grey) in the widget.
        public let isStale: Bool
        /// Window ids in snapshot order, each with its band.
        public let windowBands: [WindowBand]
    }

    public struct WindowBand: Hashable, Sendable {
        public let windowID: String
        public let band: UsageBand
    }

    public let attentionCount: Int
    public let accounts: [Account]
    /// A language change rewrites every text the widget shows.
    public let language: Language
    /// Turning the forecast off takes a ghost arc off every ring, which the user expects to see straight away.
    public let showsForecast: Bool
    /// Switching between rings and the strip redraws the whole widget; the user is looking at it when they do.
    public let layout: WidgetLayout
}

extension WidgetSnapshot {
    /// Attention count, the account and window sets, each account's texts, every window's band, each account's
    /// blocked and stale state, and the language, evaluated when the snapshot was made.
    public var significance: WidgetSignificance {
        WidgetSignificance(
            attentionCount: attentionCount,
            accounts: states(at: generatedAt).map { state in
                WidgetSignificance.Account(
                    id: state.id,
                    identity: [
                        state.account.label,
                        state.account.plan,
                        state.account.email,
                        state.account.notice,
                        state.account.tint?.rawValue,
                        state.account.monogram?.value,
                    ],
                    hasReading: state.hasReading,
                    isBlocked: state.isBlocked,
                    isStale: state.isStale,
                    windowBands: state.windows.map { WidgetSignificance.WindowBand(windowID: $0.id, band: $0.band) }
                )
            },
            language: language,
            showsForecast: showsForecast,
            layout: layout
        )
    }

    /// Whether any window present in both snapshots moved by at least `points` percentage points.
    public func usageMoved(from other: WidgetSnapshot, byAtLeast points: Double) -> Bool {
        var previous: [String: Double] = [:]
        for account in other.accounts {
            for item in account.windows {
                previous["\(account.id.rawValue.uuidString)/\(item.id)"] = item.window.used.value
            }
        }
        return accounts.contains { account in
            account.windows.contains { item in
                guard let old = previous["\(account.id.rawValue.uuidString)/\(item.id)"] else { return false }
                return abs(item.window.used.value - old) >= points
            }
        }
    }
}

/// Decides when the app publishes the widget snapshot: writes the file and asks WidgetKit to reload.
///
/// WidgetKit gives a widget a small daily reload budget (a few dozen), and a reload the budget refuses leaves the
/// widget frozen for hours. So identical content is never published, significant changes (attention count, a band,
/// a blocked or stale state, the account or window set, an account's label, plan, e-mail, notice, tint or monogram,
/// the language, the forecast setting, the layout, usage moving by
/// `significantUsageStep` points) are published at most every `significantGap`, everything else — creeping
/// percentages, counts, newer capture times — at most every `routineGap`, and never more than
/// `maximumPublishesPerHour` times in any hour. A change that has to wait is published when its time comes with
/// whatever the newest snapshot is then.
public struct WidgetExportPolicy: Sendable {
    public static let significantGap: TimeInterval = 60
    /// Shorter than `WidgetAccountState.staleAfter` by more than the longest default poll interval, so a running
    /// app keeps the widget from turning grey.
    public static let routineGap: TimeInterval = 15 * 60
    public static let maximumPublishesPerHour = 12
    public static let significantUsageStep = 10.0

    public enum Decision: Equatable, Sendable {
        case publish
        case skipIdentical
        /// Publish at that moment unless a newer snapshot decides otherwise.
        case wait(until: Date)
    }

    public private(set) var lastPublished: WidgetSnapshot?
    public private(set) var lastPublishedAt: Date?
    /// Publish moments of the last hour, oldest first.
    public private(set) var recentPublishes: [Date] = []
    private var lastSignificance: WidgetSignificance?

    public init() {}

    public func decision(for snapshot: WidgetSnapshot, now: Date) -> Decision {
        guard let lastPublished, let lastPublishedAt else { return .publish }
        if snapshot.hasSameContent(as: lastPublished) { return .skipIdentical }
        // A clock that moved backwards must not hold publishing back until it catches up.
        guard lastPublishedAt <= now else { return .publish }

        let isSignificant = snapshot.significance != lastSignificance
            || snapshot.usageMoved(from: lastPublished, byAtLeast: Self.significantUsageStep)
        var due = lastPublishedAt.addingTimeInterval(isSignificant ? Self.significantGap : Self.routineGap)
        let lastHour = recentPublishes.filter { $0 > now.addingTimeInterval(-3_600) && $0 <= now }
        if lastHour.count >= Self.maximumPublishesPerHour {
            due = max(due, lastHour[lastHour.count - Self.maximumPublishesPerHour].addingTimeInterval(3_600))
        }
        return due <= now ? .publish : .wait(until: due)
    }

    public mutating func recordPublish(_ snapshot: WidgetSnapshot, at date: Date) {
        lastPublished = snapshot
        lastSignificance = snapshot.significance
        lastPublishedAt = date
        recentPublishes = Array((recentPublishes.filter { $0 > date.addingTimeInterval(-3_600) && $0 <= date } + [date])
            .suffix(Self.maximumPublishesPerHour))
    }

    /// Forgets every publish, e.g. after the file was deleted, so the next snapshot is published at once.
    public mutating func reset() {
        self = WidgetExportPolicy()
    }
}
