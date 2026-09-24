import Foundation

// MARK: - Sound

/// The sound an alert deserves. At most one sound plays per burst: the most important one.
///
/// Ordered by importance: `reset < finished < threshold < waiting < exhausted`.
public enum AlertSound: Int, Sendable, CaseIterable, Comparable {
    case reset
    case finished
    case threshold
    case waiting
    case exhausted

    /// The system sound to play; the same three sounds the alerts settings pane previews
    /// (finished: Glass, attention: Funk, threshold: Tink).
    public var systemSoundName: String {
        switch self {
        case .exhausted, .waiting: "Funk"
        case .threshold: "Tink"
        case .finished, .reset: "Glass"
        }
    }

    public static func < (lhs: AlertSound, rhs: AlertSound) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

extension TrackerAlert {
    /// The alert's sound class; `nil` for silent alerts.
    public var sound: AlertSound? {
        switch self {
        case let .thresholdReached(context, threshold):
            threshold.isExhausted || context.window.used.isExhausted ? .exhausted : .threshold
        case .limitReset:
            .reset
        case .sessionFinished:
            .finished
        case .sessionNeedsAttention:
            .waiting
        case .sessionAttentionResolved:
            nil
        }
    }

    /// A session blocked on the user is posted at once, never held back to be coalesced.
    public var bypassesBurstBuffer: Bool {
        if case .sessionNeedsAttention = self { return true }
        return false
    }
}

// MARK: - Deliveries

/// One notification to post: a single alert or a summary of a burst.
public enum AlertDelivery: Hashable, Sendable {
    case single(TrackerAlert)
    case summary(AlertSummary)

    /// Bursts of at least this many alerts are delivered as one summary.
    public static let summaryMinimumCount = 3

    /// Plans the delivery of one buffered burst.
    ///
    /// Silent alerts are dropped, and alerts about the same thing (equal `notificationIdentifier`) collapse into
    /// the latest one, at its position. Fewer than `summaryMinimumCount` alerts are delivered one by one in arrival
    /// order; more become one summary.
    public static func plan(_ buffered: [TrackerAlert]) -> [AlertDelivery] {
        let alerts = latestPerIdentifier(buffered.filter { !$0.isSilent })
        guard alerts.count >= summaryMinimumCount, let summary = AlertSummary(alerts: alerts) else {
            return alerts.map(AlertDelivery.single)
        }
        return [.summary(summary)]
    }

    /// Keeps the last alert for each identifier, in the order of those last occurrences.
    static func latestPerIdentifier(_ alerts: [TrackerAlert]) -> [TrackerAlert] {
        var seen = Set<String>()
        var reversed: [TrackerAlert] = []
        for alert in alerts.reversed() where seen.insert(alert.notificationIdentifier).inserted {
            reversed.append(alert)
        }
        return reversed.reversed()
    }

    public var identifier: String {
        switch self {
        case .single(let alert): alert.notificationIdentifier
        case .summary(let summary): summary.identifier
        }
    }

    public var threadIdentifier: String {
        switch self {
        case .single(let alert): alert.threadIdentifier
        case .summary(let summary): summary.threadIdentifier
        }
    }

    /// The account a click on the notification opens.
    public var accountID: AccountID {
        switch self {
        case .single(let alert): alert.accountID
        case .summary(let summary): summary.accountID
        }
    }

    public var sound: AlertSound? {
        switch self {
        case .single(let alert): alert.sound
        case .summary(let summary): summary.sound
        }
    }

    /// A «ждёт» notification: marked in its user info, so a later launch can still withdraw it once resolved.
    public var isAttention: Bool {
        if case .single(let alert) = self { return alert.bypassesBurstBuffer }
        return false
    }
}

/// Several alerts delivered as one notification: a counted title ("3 alerts") over a few fragments ("Work — agent
/// finished (Codometer), Home — 80% (Weekly · All models), …"). The presenter renders both with `AlertSummaryContent`.
public struct AlertSummary: Hashable, Sendable {
    public static let identifierPrefix = "summary."
    /// The thread of a summary whose alerts belong to different accounts.
    public static let mixedThreadIdentifier = "summary"
    /// The body lists this many alerts, then an ellipsis.
    public static let maximumFragments = 3

    /// Non-silent alerts with distinct identifiers, most important first; equally important ones keep arrival order.
    public let alerts: [TrackerAlert]
    /// Derived from the summarised alerts' identifiers only, so it is the same for the same alerts in any order and
    /// across launches: an identical summary replaces the delivered one.
    public let identifier: String
    /// The account's thread when every alert belongs to one account, else `mixedThreadIdentifier`.
    public let threadIdentifier: String
    /// The account of the most important alert.
    public let accountID: AccountID
    public let sound: AlertSound?

    /// Summarises the non-silent alerts (the latest per identifier); `nil` when none is left.
    public init?(alerts: [TrackerAlert]) {
        let unique = AlertDelivery.latestPerIdentifier(alerts.filter { !$0.isSilent })
        let ordered = unique.enumerated()
            .sorted { lhs, rhs in
                let left = lhs.element.sound ?? .reset
                let right = rhs.element.sound ?? .reset
                return left != right ? left > right : lhs.offset < rhs.offset
            }
            .map(\.element)
        guard let first = ordered.first else { return nil }
        self.alerts = ordered
        identifier = Self.identifier(for: ordered.map(\.notificationIdentifier))
        let accounts = Set(ordered.map(\.accountID))
        threadIdentifier = accounts.count == 1 ? first.threadIdentifier : Self.mixedThreadIdentifier
        accountID = first.accountID
        sound = ordered.compactMap(\.sound).max()
    }

    /// Identifiers of the notifications this summary supersedes; they are withdrawn when it is posted.
    public var replacedIdentifiers: [String] { alerts.map(\.notificationIdentifier) }

    /// `summary.<16 hex digits>`: a 64-bit FNV-1a hash of the sorted, distinct identifiers joined by newlines.
    /// Unlike `Hasher`, FNV-1a is not seeded per process, so the identifier survives relaunches.
    public static func identifier(for notificationIdentifiers: [String]) -> String {
        let text = Set(notificationIdentifiers).sorted().joined(separator: "\n")
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let hex = String(hash, radix: 16)
        return identifierPrefix + String(repeating: "0", count: 16 - hex.count) + hex
    }

    /// What the notification says, from the rendered fragments of `alerts` (empty ones are skipped): the count for
    /// the plural title and the first `maximumFragments` fragments for the body.
    public static func content(fragments: [String]) -> AlertSummaryContent {
        let visible = fragments.filter { !$0.isEmpty }
        return AlertSummaryContent(count: visible.count, fragments: Array(visible.prefix(maximumFragments)))
    }
}

/// A summary notification as data: `l10n.alertSummary.title(count:)` and `body(fragments:isTruncated:)` put it into
/// words in the language of the moment it is posted.
public struct AlertSummaryContent: Hashable, Sendable {
    /// How many alerts the summary covers.
    public let count: Int
    /// The fragments the body lists, at most `AlertSummary.maximumFragments`.
    public let fragments: [String]

    public init(count: Int, fragments: [String]) {
        self.count = max(0, count)
        self.fragments = fragments
    }

    /// Some alerts are counted but not listed, so the body ends with an ellipsis.
    public var isTruncated: Bool { count > fragments.count }
}

// MARK: - Planner

/// What the presenter does after the planner saw new alerts or a burst ended.
public struct AlertDeliveryStep: Hashable, Sendable {
    /// Notifications to remove before posting: withdrawn «ждёт» notifications and ones a summary supersedes.
    public let withdrawals: [String]
    /// Resolved sessions whose notification this planner did not deliver as «ждёт» (for example one posted before
    /// a relaunch): the presenter removes such a delivered notification only when its user info marks it as «ждёт»
    /// (`AlertUserInfo.isAttention`), so a «закончил» notification sharing the identifier stays.
    public let withdrawalsIfAttention: [String]
    /// Notifications to post, in order.
    public let deliveries: [AlertDelivery]
    /// The one sound to play for this step, already filtered by the sound setting and sound spacing.
    public let sound: AlertSound?
    /// While alerts are buffered: when the presenter should call `flush`.
    public let flushAt: Date?

    public init(
        withdrawals: [String],
        withdrawalsIfAttention: [String] = [],
        deliveries: [AlertDelivery],
        sound: AlertSound?,
        flushAt: Date?
    ) {
        self.withdrawals = withdrawals
        self.withdrawalsIfAttention = withdrawalsIfAttention
        self.deliveries = deliveries
        self.sound = sound
        self.flushAt = flushAt
    }

    public var isEmpty: Bool {
        withdrawals.isEmpty && withdrawalsIfAttention.isEmpty && deliveries.isEmpty && sound == nil && flushAt == nil
    }
}

/// Decides which notifications to post, replace, coalesce and withdraw. Pure state: the presenter owns the timer
/// and the notification center.
///
/// - «Ждёт» alerts post at once; any buffered alert about the same session is dropped, so an older alert never
///   replaces the newer notification later.
/// - With `coalescesBursts`, other alerts wait `burstWindow` from the first buffered one, then go out through
///   `AlertDelivery.plan`: one summary for `summaryMinimumCount` or more, else one by one. Without it they post at once.
/// - A resolved alert withdraws its session's notification at once while that notification is a «ждёт» one this
///   planner delivered. Otherwise the identifier goes to `withdrawalsIfAttention`: the presenter removes the
///   delivered notification only if it is marked as «ждёт» (posted before a relaunch), so a «закончил» notification
///   that shares the identifier is never removed.
/// - A step plays at most one sound, its most important one; a sound that is not more important than one played
///   less than `soundSpacing` ago is skipped, so a burst flushed after an immediate «ждёт» stays quiet.
public struct AlertDeliveryPlanner: Sendable {
    public static let burstWindow: TimeInterval = 1.5
    /// Longer than `burstWindow`, so the flush of a burst never repeats the sound of its own start.
    public static let soundSpacing: TimeInterval = 3
    /// The oldest buffered alerts are dropped beyond this.
    public static let maximumPendingAlerts = 64
    /// The oldest remembered «ждёт» notifications are forgotten beyond this.
    public static let maximumTrackedAttention = 256

    private struct PlayedSound: Hashable, Sendable {
        let sound: AlertSound
        let at: Date
    }

    /// Alerts waiting for the current burst to end, oldest first.
    public private(set) var pending: [TrackerAlert] = []
    /// When the current burst ends; `nil` while nothing is buffered.
    public private(set) var burstDeadline: Date?
    /// Identifiers whose delivered notification is a «ждёт» one, oldest first.
    private var attentionIdentifiers: [String] = []
    private var lastSound: PlayedSound?

    public init() {}

    /// Whether the notification with this identifier was delivered as a «ждёт» alert and not yet replaced or withdrawn.
    public func isShowingAttention(_ identifier: String) -> Bool {
        attentionIdentifiers.contains(identifier)
    }

    /// Takes the alerts of one engine update.
    public mutating func receive(_ alerts: [TrackerAlert], settings: AlertSettings, now: Date) -> AlertDeliveryStep {
        var withdrawals: [String] = []
        var withdrawalsIfAttention: [String] = []
        var immediate: [TrackerAlert] = []
        for alert in alerts {
            let identifier = alert.notificationIdentifier
            if alert.isSilent {
                guard settings.withdrawsResolvedAlerts else { continue }
                // A «ждёт» alert resolved within the same update is simply never posted.
                immediate.removeAll { $0.bypassesBurstBuffer && $0.notificationIdentifier == identifier }
                if untrackAttention(identifier) {
                    if !withdrawals.contains(identifier) { withdrawals.append(identifier) }
                } else if !withdrawalsIfAttention.contains(identifier) {
                    withdrawalsIfAttention.append(identifier)
                }
            } else if alert.bypassesBurstBuffer || !settings.coalescesBursts {
                removePending(identifier)
                immediate.removeAll { $0.notificationIdentifier == identifier }
                immediate.append(alert)
            } else {
                enqueue(alert, now: now)
            }
        }
        var deliveries: [AlertDelivery] = []
        if !settings.coalescesBursts {
            // Coalescing was just turned off: what is still buffered is older than this update.
            deliveries = drainPending()
        }
        deliveries += immediate.map(AlertDelivery.single)
        // A notification posted by this step replaces the delivered one; nothing is left to check.
        let posted = Set(deliveries.map(\.identifier))
        return finish(
            withdrawals: withdrawals,
            withdrawalsIfAttention: withdrawalsIfAttention.filter { !posted.contains($0) },
            deliveries: deliveries,
            settings: settings,
            now: now
        )
    }

    /// Ends the current burst. Calling it with nothing buffered returns an empty step.
    public mutating func flush(settings: AlertSettings, now: Date) -> AlertDeliveryStep {
        finish(withdrawals: [], withdrawalsIfAttention: [], deliveries: drainPending(), settings: settings, now: now)
    }

    /// Drops a buffered alert superseded by one posted at once; an emptied burst ends, so the next buffered alert
    /// starts a full `burstWindow` of its own.
    private mutating func removePending(_ identifier: String) {
        pending.removeAll { $0.notificationIdentifier == identifier }
        if pending.isEmpty {
            burstDeadline = nil
        }
    }

    private mutating func enqueue(_ alert: TrackerAlert, now: Date) {
        pending.removeAll { $0.notificationIdentifier == alert.notificationIdentifier }
        pending.append(alert)
        if pending.count > Self.maximumPendingAlerts {
            pending.removeFirst(pending.count - Self.maximumPendingAlerts)
        }
        if burstDeadline == nil {
            burstDeadline = now.addingTimeInterval(Self.burstWindow)
        }
    }

    private mutating func drainPending() -> [AlertDelivery] {
        let buffered = pending
        pending = []
        burstDeadline = nil
        return AlertDelivery.plan(buffered)
    }

    private mutating func finish(
        withdrawals: [String],
        withdrawalsIfAttention: [String],
        deliveries: [AlertDelivery],
        settings: AlertSettings,
        now: Date
    ) -> AlertDeliveryStep {
        var withdrawals = withdrawals
        for delivery in deliveries {
            switch delivery {
            case .single(let alert):
                if alert.bypassesBurstBuffer {
                    trackAttention(alert.notificationIdentifier)
                } else {
                    untrackAttention(alert.notificationIdentifier)
                }
            case .summary(let summary):
                for identifier in summary.replacedIdentifiers {
                    untrackAttention(identifier)
                    if !withdrawals.contains(identifier) {
                        withdrawals.append(identifier)
                    }
                }
            }
        }
        let loudest = settings.playsSounds ? deliveries.compactMap(\.sound).max() : nil
        return AlertDeliveryStep(
            withdrawals: withdrawals,
            withdrawalsIfAttention: withdrawalsIfAttention.filter { !withdrawals.contains($0) },
            deliveries: deliveries,
            sound: loudest.flatMap { admitSound($0, now: now) },
            flushAt: pending.isEmpty ? nil : burstDeadline
        )
    }

    private mutating func admitSound(_ sound: AlertSound, now: Date) -> AlertSound? {
        if let lastSound {
            let elapsed = now.timeIntervalSince(lastSound.at)
            if elapsed >= 0, elapsed < Self.soundSpacing, sound <= lastSound.sound {
                return nil
            }
        }
        lastSound = PlayedSound(sound: sound, at: now)
        return sound
    }

    private mutating func trackAttention(_ identifier: String) {
        attentionIdentifiers.removeAll { $0 == identifier }
        attentionIdentifiers.append(identifier)
        if attentionIdentifiers.count > Self.maximumTrackedAttention {
            attentionIdentifiers.removeFirst(attentionIdentifiers.count - Self.maximumTrackedAttention)
        }
    }

    @discardableResult
    private mutating func untrackAttention(_ identifier: String) -> Bool {
        guard let index = attentionIdentifiers.firstIndex(of: identifier) else { return false }
        attentionIdentifiers.remove(at: index)
        return true
    }
}

// MARK: - User info

/// What a notification's `userInfo` carries: the account id, so a click can open that account, and whether it is
/// a «ждёт» notification, so a resolution can withdraw it even after a relaunch.
///
/// Only the canonical uppercase UUID string and the exact kind written by `encode` are accepted back; anything else
/// is ignored.
public enum AlertUserInfo {
    public static let accountKey = "accountID"
    public static let kindKey = "kind"
    public static let attentionKind = "attention"
    /// `UUID.uuidString` is always 36 characters.
    static let uuidStringLength = 36

    public static func encode(_ accountID: AccountID, isAttention: Bool = false) -> [String: String] {
        var userInfo = [accountKey: accountID.rawValue.uuidString]
        if isAttention {
            userInfo[kindKey] = attentionKind
        }
        return userInfo
    }

    /// Whether a delivered notification was posted as a «ждёт» notification.
    public static func isAttention(_ userInfo: [AnyHashable: Any]) -> Bool {
        (userInfo[AnyHashable(kindKey)] as? String) == attentionKind
    }

    /// The account id of a delivered notification, or `nil` when missing or not a canonical UUID string.
    public static func accountID(from userInfo: [AnyHashable: Any]) -> AccountID? {
        guard let raw = userInfo[AnyHashable(accountKey)] as? String else { return nil }
        return accountID(fromString: raw)
    }

    public static func accountID(fromString raw: String) -> AccountID? {
        guard raw.utf8.count == uuidStringLength, let uuid = UUID(uuidString: raw), uuid.uuidString == raw else {
            return nil
        }
        return AccountID(rawValue: uuid)
    }
}
