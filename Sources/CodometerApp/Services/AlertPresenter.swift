import CodometerCore
import CodometerL10n
import CodometerPlatform
import CodometerUI
import AppKit
import UserNotifications
import os

/// Turns tracker alerts into system notifications and sounds, without junk.
///
/// `AlertDeliveryPlanner` decides what happens; this class renders the text and talks to the notification center:
/// - every notification uses the alert's deterministic identifier, so a newer alert about the same session or
///   window replaces the delivered one, and the alert's account thread;
/// - "waiting" notifications are withdrawn once the session stops waiting (when the setting is on), also ones posted
///   before a relaunch, which their user info marks as waiting;
/// - bursts are buffered for `AlertDeliveryPlanner.burstWindow` and three or more alerts become one summary
///   (waiting alerts are never held back);
/// - one sound per burst, the most important one;
/// - titles name the account by its label, never by e-mail;
/// - text is written in the language of the latest update's `Localizer` when the notification is posted.
@MainActor
final class AlertPresenter: NSObject, UNUserNotificationCenterDelegate {
    /// Called with the account of a notification the user clicked.
    var onOpen: ((AccountID) -> Void)?

    /// Notifications kept while the first authorization request is pending.
    private static let maximumAwaitingAuthorization = 32
    /// At most this many identifiers are checked for an earlier launch's waiting notification at a time.
    private static let maximumAttentionChecks = 128
    /// A burst timer firing this close to the deadline flushes instead of sleeping again.
    private static let flushSlack: TimeInterval = 0.05

    private enum Authorization {
        case notRequested
        case requesting
        case settled
    }

    /// Everything a notification request needs, as Sendable values.
    private struct Payload: Sendable {
        let identifier: String
        let thread: String
        let title: String
        let body: String
        let userInfo: [String: String]
        /// The sound this notification carries; at most one payload per burst gets anything but `.silent`.
        var sound: AlertSoundPolicy.Decision = .silent
    }

    private struct NotificationText {
        let title: String
        let body: String
    }

    private let center: UNUserNotificationCenter?
    /// `false` for an isolated data root: deliveries are logged, never posted or sounded.
    private let postsNotifications: Bool
    private var authorization = Authorization.notRequested
    private var awaitingAuthorization: [Payload] = []
    private var planner = AlertDeliveryPlanner()
    private var flushTask: Task<Void, Never>?
    /// Identifiers whose delivered notifications are being checked for a waiting one from an earlier launch; `true`
    /// once a notification with that identifier was posted during the check, which cancels its removal.
    private var attentionChecks: [String: Bool] = [:]
    /// The state, settings and language of the latest update, used to render a burst when it ends.
    private var state = TrackerState.empty
    private var settings = AppSettings.empty
    private var localizer = Localizer(language: .en)
    /// What the notification centre currently allows, refreshed at launch, when the app becomes active and after the
    /// authorization request settles. Never polled.
    private var deliverySettings = NotificationDelivery.unknown
    /// Which named system sounds exist, looked up once per name.
    private var soundAvailability: [String: Bool] = [:]

    init(postsNotifications: Bool = true) {
        self.postsNotifications = postsNotifications
        // UNUserNotificationCenter requires a bundled app; `swift run` builds have no bundle identifier. An isolated
        // instance never touches the notification center (nor the delivered notifications of the same bundle id).
        center = Bundle.main.bundleIdentifier == nil || !postsNotifications ? nil : UNUserNotificationCenter.current()
        super.init()
        center?.delegate = self
    }

    /// Text is rendered with `localizer` when a notification is posted, also for a burst that ends later.
    func present(_ alerts: [TrackerAlert], state: TrackerState, settings: AppSettings, localizer: Localizer) {
        self.state = state
        self.settings = settings
        self.localizer = localizer
        // Alerts about accounts that are no longer tracked are dropped; resolutions still withdraw.
        let relevant = alerts.filter { $0.isSilent || state.account($0.accountID) != nil }
        apply(planner.receive(relevant, settings: settings.alerts, now: Date()))
    }

    /// Asks for notification permission now (onboarding's "Allow Notifications") instead of at the first delivery.
    /// Returns whether notifications are allowed; `false` without a notification center (isolated or unbundled runs).
    /// A request that already settled is not repeated: macOS asks only once.
    func requestAuthorization() async -> Bool {
        guard center != nil else { return false }
        if case .notRequested = authorization {
            authorization = .requesting
            // Sound is asked for together with the banner: a later request for it would be refused silently, and
            // Codometer would have to fall back to playing sounds itself.
            let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
            authorizationSettled(granted: granted)
            await refreshDeliverySettings()
            return granted
        }
        await refreshDeliverySettings()
        return deliverySettings.allowsNotifications
    }

    /// Notification permission as the system reports it, for Diagnostics and the Notifications pane.
    func currentAuthorization() async -> NotificationAuthorization {
        guard center != nil else { return .denied }
        await refreshDeliverySettings()
        return deliverySettings.authorization
    }

    /// Re-reads what the notification centre allows. Called at launch, when the app becomes active and after an
    /// authorization request; nothing polls.
    func refreshDeliverySettings() async {
        guard center != nil else { return }
        deliverySettings = await withCheckedContinuation { (continuation: CheckedContinuation<NotificationDelivery, Never>) in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: NotificationDelivery(settings))
            }
        }
    }

    // MARK: - Planning

    private func apply(_ step: AlertDeliveryStep) {
        withdraw(step.withdrawals)
        withdrawIfAttention(step.withdrawalsIfAttention)
        guard postsNotifications else {
            // Identifiers only: the rendered text names accounts and projects.
            for delivery in step.deliveries {
                AppLog.interface.notice("isolated data root: notification not posted (\(delivery.identifier, privacy: .private))")
            }
            if let flushAt = step.flushAt {
                scheduleFlush(at: flushAt)
            }
            return
        }
        // The burst's one sound rides along with its first notification, so macOS honours Focus, the per-app sound
        // switch and Do Not Disturb. Codometer never plays a sound itself.
        var sound = AlertSoundPolicy.decision(
            sound: step.sound,
            settings: deliverySettings,
            isAvailable: { [weak self] name in self?.soundExists(name) ?? false }
        )
        for delivery in step.deliveries {
            guard var payload = payload(for: delivery) else { continue }
            payload.sound = sound
            sound = .silent
            post(payload)
        }
        if let flushAt = step.flushAt {
            scheduleFlush(at: flushAt)
        }
    }

    private func scheduleFlush(at deadline: Date) {
        guard flushTask == nil else { return }
        // Clamped, so a wall clock set back never holds a burst for longer than its window.
        let delay = min(max(0, deadline.timeIntervalSinceNow), AlertDeliveryPlanner.burstWindow)
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay), tolerance: .milliseconds(100))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    private func flush() {
        flushTask = nil
        // A timer left over from a burst that was already delivered must not cut a later burst short. A deadline
        // further away than a whole window means the wall clock was set back: that burst is due now.
        if let deadline = planner.burstDeadline {
            let remaining = deadline.timeIntervalSinceNow
            if remaining > Self.flushSlack, remaining <= AlertDeliveryPlanner.burstWindow {
                scheduleFlush(at: deadline)
                return
            }
        }
        apply(planner.flush(settings: settings.alerts, now: Date()))
    }

    // MARK: - Text

    private func payload(for delivery: AlertDelivery) -> Payload? {
        let text: NotificationText
        switch delivery {
        case .single(let alert):
            guard let single = self.text(for: alert) else { return nil }
            text = single
        case .summary(let summary):
            let content = AlertSummary.content(fragments: summary.alerts.compactMap(fragment(for:)))
            guard content.count > 0 else { return nil }
            text = NotificationText(
                title: localizer.alertSummary.title(count: content.count),
                body: localizer.alertSummary.body(fragments: content.fragments, isTruncated: content.isTruncated)
            )
        }
        return Payload(
            identifier: delivery.identifier,
            thread: delivery.threadIdentifier,
            title: text.title,
            body: text.body,
            userInfo: AlertUserInfo.encode(delivery.accountID, isAttention: delivery.isAttention)
        )
    }

    /// The account's label: notifications never show e-mail addresses.
    private func label(_ accountID: AccountID) -> String? {
        state.account(accountID)?.profile.label.value
    }

    private func text(for alert: TrackerAlert) -> NotificationText? {
        guard let label = label(alert.accountID) else { return nil }
        let strings = localizer.notification
        switch alert {
        case let .thresholdReached(context, threshold):
            // "Work: 80% used" / "Weekly · All models is at 82%. Resets in 2h 14m."
            let title = alert.sound == .exhausted
                ? strings.limitReached(account: label)
                : strings.thresholdReached(account: label, percent: localizer.format.percent(threshold.value))
            let usage = strings.windowUsage(window: windowName(context), percent: localizer.format.percent(context.window.used.value))
            return NotificationText(title: title, body: sentences([usage, resetSentence(context.window)]))
        case .limitReset(let context):
            return NotificationText(title: strings.limitReset(account: label), body: sentences([strings.availableAgain(window: windowName(context))]))
        case let .sessionFinished(_, session):
            // "codometer · 4m 12s turn · first token in 2.8s": a language-neutral metadata run.
            var body = sessionName(session)
            if let turn = session.lastTurn {
                body += " · " + UsageFormat.turn(turn, l10n: localizer)
            }
            return NotificationText(title: strings.agentFinished(account: label), body: body)
        case let .sessionNeedsAttention(_, session):
            let title = switch attentionNeed(of: session) {
            case .approval: strings.needsApproval(account: label)
            case .input: strings.needsInput(account: label)
            case .waiting: strings.waitingForYou(account: label)
            }
            return NotificationText(title: title, body: sessionName(session))
        case .sessionAttentionResolved:
            return nil
        }
    }

    /// One summary line: "Claude: agent finished (codometer)", "Codex: 82% used (Weekly · All models)".
    private func fragment(for alert: TrackerAlert) -> String? {
        guard let label = label(alert.accountID) else { return nil }
        let strings = localizer.notification
        switch alert {
        case .thresholdReached(let context, _):
            let window = windowName(context)
            return alert.sound == .exhausted
                ? strings.limitReachedLine(account: label, window: window)
                : strings.usageLine(account: label, percent: localizer.format.percent(context.window.used.value), window: window)
        case .limitReset(let context):
            return strings.limitResetLine(account: label, window: windowName(context))
        case let .sessionFinished(_, session):
            return strings.agentFinishedLine(account: label, session: sessionName(session))
        case let .sessionNeedsAttention(_, session):
            let name = sessionName(session)
            return switch attentionNeed(of: session) {
            case .approval: strings.needsApprovalLine(account: label, session: name)
            case .input: strings.needsInputLine(account: label, session: name)
            case .waiting: strings.waitingForYouLine(account: label, session: name)
            }
        case .sessionAttentionResolved:
            return nil
        }
    }

    /// What a waiting session needs from the user.
    private enum AttentionNeed {
        case approval, input, waiting
    }

    /// Classified exactly as the island words it: `UsageFormat.activity` decides, and its phrase tells which need it
    /// found. Notifications then use their own phrases, which read naturally after "Work:".
    private func attentionNeed(of session: AgentSession) -> AttentionNeed {
        let words = localizer.usage
        let activity = UsageFormat.activity(session.activity, detail: session.detail, l10n: localizer)
        if activity == words.needsApproval { return .approval }
        if activity == words.needsInput { return .input }
        return .waiting
    }

    /// The session's project folder, never its own title: Claude names sessions after the conversation, and macOS
    /// keeps delivered notification text in its own database.
    private func sessionName(_ session: AgentSession) -> String {
        UsageFormat.sessionLabel(SessionLabel.parts(sessionID: session.id, projectFolder: session.projectPath), includesID: false, l10n: localizer)
    }

    /// "Weekly · All models", followed by the bucket's own title when the provider named it ("Weekly · GPT-5-Codex-Mini").
    private func windowName(_ context: AlertWindowContext) -> String {
        let title = UsageFormat.windowTitle(context.window, l10n: localizer)
        guard let bucket = context.bucketTitle, !bucket.isEmpty, bucket != title else { return title }
        return "\(title) · \(bucket)"
    }

    /// "Resets in 2h 14m" as a sentence, so its first letter is capitalised (Russian captions start lowercase); `nil`
    /// when the reset time is unknown.
    private func resetSentence(_ window: LimitWindow) -> String? {
        guard let text = UsageFormat.resetText(for: window, now: Date(), style: settings.appearance.resetTextStyle, l10n: localizer) else {
            return nil
        }
        return text.prefix(1).uppercased(with: localizer.locale) + text.dropFirst()
    }

    /// Joins sentences with periods, without doubling a trailing "…" or period.
    private func sentences(_ parts: [String?]) -> String {
        parts.compactMap { $0 }
            .map { $0.hasSuffix("…") || $0.hasSuffix(".") ? $0 : $0 + "." }
            .joined(separator: " ")
    }

    // MARK: - Notification center

    private func withdraw(_ identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        awaitingAuthorization.removeAll { identifiers.contains($0.identifier) }
        center?.removeDeliveredNotifications(withIdentifiers: identifiers)
        center?.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    /// Removes delivered notifications with these identifiers only when their user info marks them as waiting.
    private func withdrawIfAttention(_ identifiers: [String]) {
        guard let center, !identifiers.isEmpty else { return }
        let wanted = Set(identifiers.prefix(max(0, Self.maximumAttentionChecks - attentionChecks.count)))
        guard !wanted.isEmpty else { return }
        for identifier in wanted where attentionChecks[identifier] == nil {
            attentionChecks[identifier] = false
        }
        center.getDeliveredNotifications { [weak self] notifications in
            // Only identifiers leave this callback; the notifications' content stays here.
            let stale = notifications.compactMap { notification -> String? in
                let request = notification.request
                guard wanted.contains(request.identifier), AlertUserInfo.isAttention(request.content.userInfo) else {
                    return nil
                }
                return request.identifier
            }
            Task { @MainActor in
                self?.finishAttentionCheck(of: wanted, stale: stale)
            }
        }
    }

    private func finishAttentionCheck(of identifiers: Set<String>, stale: [String]) {
        // A notification posted while the check ran replaced the stale one and stays.
        let removable = stale.filter { attentionChecks[$0] == false }
        for identifier in identifiers {
            attentionChecks[identifier] = nil
        }
        guard !removable.isEmpty else { return }
        center?.removeDeliveredNotifications(withIdentifiers: removable)
    }

    private func post(_ payload: Payload) {
        guard center != nil else { return }
        if attentionChecks[payload.identifier] != nil {
            attentionChecks[payload.identifier] = true
        }
        switch authorization {
        case .settled:
            Self.deliver(payload)
        case .requesting:
            enqueueForAuthorization(payload)
        case .notRequested:
            authorization = .requesting
            enqueueForAuthorization(payload)
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
                Task { @MainActor in
                    self?.authorizationSettled(granted: granted)
                }
            }
        }
    }

    private func enqueueForAuthorization(_ payload: Payload) {
        awaitingAuthorization.removeAll { $0.identifier == payload.identifier }
        awaitingAuthorization.append(payload)
        if awaitingAuthorization.count > Self.maximumAwaitingAuthorization {
            awaitingAuthorization.removeFirst(awaitingAuthorization.count - Self.maximumAwaitingAuthorization)
        }
    }

    private func authorizationSettled(granted: Bool) {
        authorization = .settled
        let queued = awaitingAuthorization
        awaitingAuthorization = []
        // The very first burst goes out before the refreshed settings arrive, so it is silent; every later one
        // carries the sound the policy allows.
        Task { [weak self] in await self?.refreshDeliverySettings() }
        guard granted else { return }
        queued.forEach(Self.deliver)
    }

    /// Adding a request with an identifier that is already delivered replaces that notification.
    private static func deliver(_ payload: Payload) {
        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.body = payload.body
        content.threadIdentifier = payload.thread
        content.userInfo = payload.userInfo
        switch payload.sound {
        case .silent:
            break
        case .named(let name):
            content.sound = UNNotificationSound(named: UNNotificationSoundName(name))
        case .systemDefault:
            content.sound = .default
        }
        let request = UNNotificationRequest(identifier: payload.identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Whether macOS can find a named sound. Looked up once per name; the answer cannot change while the app runs.
    private func soundExists(_ name: String) -> Bool {
        if let known = soundAvailability[name] { return known }
        let found = AlertSoundPolicy.soundDirectories.contains { directory in
            FileManager.default.fileExists(atPath: directory + "/" + name)
        }
        soundAvailability[name] = found
        return found
    }

    private func open(_ accountID: AccountID) {
        onOpen?(accountID)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        // Only the Sendable account id leaves this callback.
        guard
            response.actionIdentifier == UNNotificationDefaultActionIdentifier,
            let accountID = AlertUserInfo.accountID(from: response.notification.request.content.userInfo)
        else { return }
        await open(accountID)
    }
}


/// What the notification centre currently allows, as the app needs it.
struct NotificationDelivery: Equatable, Sendable {
    /// Before the first `getNotificationSettings`: nothing is assumed, so no sound is attached.
    static let unknown = NotificationDelivery(authorization: .notDetermined, soundEnabled: false)

    let authorization: NotificationAuthorization
    /// Whether the user left sound on for Codometer in System Settings.
    let soundEnabled: Bool

    init(authorization: NotificationAuthorization, soundEnabled: Bool) {
        self.authorization = authorization
        self.soundEnabled = soundEnabled
    }

    init(_ settings: UNNotificationSettings) {
        authorization = switch settings.authorizationStatus {
        case .authorized: .authorized
        case .provisional: .provisional
        case .denied: .denied
        default: .notDetermined
        }
        soundEnabled = settings.soundSetting == .enabled
    }

    var allowsNotifications: Bool {
        authorization == .authorized || authorization == .provisional
    }
}

/// Whether a delivered notification carries a sound, and which one.
///
/// Codometer never plays a sound itself: a sound attached to the notification is silenced by Focus, by Do Not
/// Disturb and by the per-app sound switch, and it never plays while notifications are denied.
enum AlertSoundPolicy {
    enum Decision: Equatable, Sendable {
        case silent
        /// A named sound file, e.g. `Glass.aiff`.
        case named(String)
        /// The system's own notification sound, when the named file is not installed.
        case systemDefault
    }

    /// Where macOS keeps the sounds `UNNotificationSound(named:)` can find.
    static let soundDirectories = ["/System/Library/Sounds", "/Library/Sounds"]
    static let fileExtension = ".aiff"

    /// - Parameters:
    ///   - sound: The burst's sound as the planner decided it (already `nil` when "Play sounds" is off).
    ///   - settings: What the notification centre allows right now.
    ///   - isAvailable: Whether a named sound file exists.
    static func decision(
        sound: AlertSound?,
        settings: NotificationDelivery,
        isAvailable: (String) -> Bool
    ) -> Decision {
        guard let sound, settings.allowsNotifications, settings.soundEnabled else { return .silent }
        let file = sound.systemSoundName + fileExtension
        return isAvailable(file) ? .named(file) : .systemDefault
    }
}
