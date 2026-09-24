import CodometerCore
import CodometerL10n
import AppKit
import Foundation
import SwiftUI
import Testing

/// Builders for the delivery tests, independent of the shared fixtures.
private enum Delivery {
    static let now = Date(timeIntervalSince1970: 1_789_700_000)

    static func session(_ activity: AgentActivity, id: String) throws -> AgentSession {
        try AgentSession(
            id: id,
            title: "Codometer",
            projectPath: "/tmp/Codometer",
            activity: activity,
            detail: activity == .waiting ? "permission prompt" : nil,
            activitySince: now,
            processID: nil
        )
    }

    static func context(_ account: AccountID, window id: String = "primary", used: Double) throws -> AlertWindowContext {
        let window = try LimitWindow(
            id: id,
            scope: .rolling,
            used: try Percentage(validating: used),
            duration: try WindowDuration(minutes: 300),
            resetsAt: now.addingTimeInterval(3_600)
        )
        return AlertWindowContext(accountID: account, bucketID: "main", bucketTitle: nil, window: window)
    }

    static func threshold(
        _ account: AccountID,
        window: String = "primary",
        used: Double = 82,
        threshold: Double = 80
    ) throws -> TrackerAlert {
        .thresholdReached(try context(account, window: window, used: used), threshold: try Percentage(validating: threshold))
    }

    static func reset(_ account: AccountID, window: String = "primary") throws -> TrackerAlert {
        .limitReset(try context(account, window: window, used: 2))
    }

    static func finished(_ account: AccountID, _ session: String = "s1") throws -> TrackerAlert {
        .sessionFinished(accountID: account, session: try self.session(.idle, id: session))
    }

    static func waiting(_ account: AccountID, _ session: String = "s1") throws -> TrackerAlert {
        .sessionNeedsAttention(accountID: account, session: try self.session(.waiting, id: session))
    }

    static func resolved(_ account: AccountID, _ session: String = "s1") throws -> TrackerAlert {
        .sessionAttentionResolved(accountID: account, session: try self.session(.working, id: session))
    }

    static func settings(
        coalesces: Bool = true,
        withdraws: Bool = true,
        sounds: Bool = true
    ) -> AlertSettings {
        AlertSettings(playsSounds: sounds, withdrawsResolvedAlerts: withdraws, coalescesBursts: coalesces)
    }

    static func singles(_ step: AlertDeliveryStep) -> [TrackerAlert] {
        step.deliveries.compactMap { delivery in
            if case .single(let alert) = delivery { return alert }
            return nil
        }
    }

    static func summaries(_ step: AlertDeliveryStep) -> [AlertSummary] {
        step.deliveries.compactMap { delivery in
            if case .summary(let summary) = delivery { return summary }
            return nil
        }
    }
}

@Suite("Alert sound priority")
struct AlertSoundPriorityTests {
    @Test("Exhausted outranks waiting, then threshold, finished and reset")
    func order() {
        #expect(AlertSound.allCases.sorted() == [.reset, .finished, .threshold, .waiting, .exhausted])
        #expect(AlertSound.exhausted > .waiting)
        #expect(AlertSound.waiting > .threshold)
        #expect(AlertSound.threshold > .finished)
        #expect(AlertSound.finished > .reset)
    }

    @Test("Every alert maps to its sound class; resolved alerts are silent")
    func mapping() throws {
        let account = AccountID()
        #expect(try Delivery.threshold(account, used: 82, threshold: 80).sound == .threshold)
        #expect(try Delivery.threshold(account, used: 100, threshold: 100).sound == .exhausted)
        #expect(try Delivery.threshold(account, used: 100, threshold: 90).sound == .exhausted)
        #expect(try Delivery.reset(account).sound == .reset)
        #expect(try Delivery.finished(account).sound == .finished)
        #expect(try Delivery.waiting(account).sound == .waiting)
        #expect(try Delivery.resolved(account).sound == nil)
    }

    @Test("System sounds match the settings previews")
    func systemSounds() {
        #expect(AlertSound.exhausted.systemSoundName == "Funk")
        #expect(AlertSound.waiting.systemSoundName == "Funk")
        #expect(AlertSound.threshold.systemSoundName == "Tink")
        #expect(AlertSound.finished.systemSoundName == "Glass")
        #expect(AlertSound.reset.systemSoundName == "Glass")
    }

    @Test("Only waiting alerts bypass the burst buffer")
    func bypass() throws {
        let account = AccountID()
        #expect(try Delivery.waiting(account).bypassesBurstBuffer)
        for alert in [
            try Delivery.threshold(account),
            try Delivery.reset(account),
            try Delivery.finished(account),
            try Delivery.resolved(account),
        ] {
            #expect(!alert.bypassesBurstBuffer)
        }
    }
}

@Suite("Burst planning")
struct BurstPlanningTests {
    @Test("Fewer than three alerts are delivered one by one, in arrival order")
    func individually() throws {
        let account = AccountID()
        let alerts = [try Delivery.reset(account), try Delivery.finished(account)]
        #expect(AlertDelivery.plan(alerts) == alerts.map(AlertDelivery.single))
        #expect(AlertDelivery.plan([]).isEmpty)
        #expect(AlertDelivery.plan([try Delivery.resolved(account)]).isEmpty)
    }

    @Test("Three or more alerts become one summary, most important first")
    func summary() throws {
        let claude = AccountID()
        let codex = AccountID()
        let finished = try Delivery.finished(claude)
        let reset = try Delivery.reset(codex, window: "secondary")
        let threshold = try Delivery.threshold(codex)
        let exhausted = try Delivery.threshold(claude, window: "session", used: 100, threshold: 100)
        let resolved = try Delivery.resolved(claude, "s9")

        let plan = AlertDelivery.plan([finished, reset, resolved, threshold, exhausted])
        #expect(plan.count == 1)
        guard case .summary(let summary) = try #require(plan.first) else {
            Issue.record("expected a summary")
            return
        }
        #expect(summary.alerts == [exhausted, threshold, finished, reset])
        #expect(summary.sound == .exhausted)
        #expect(summary.accountID == claude)
        #expect(summary.threadIdentifier == AlertSummary.mixedThreadIdentifier)
        #expect(Localizer.testRussian.alertSummary.title(count: summary.alerts.count) == "4 события")
        #expect(Localizer.testEnglish.alertSummary.title(count: summary.alerts.count) == "4 alerts")
        #expect(summary.replacedIdentifiers == [exhausted, threshold, finished, reset].map(\.notificationIdentifier))
        #expect(plan.first?.identifier == summary.identifier)
        #expect(plan.first?.accountID == claude)
        #expect(plan.first?.sound == .exhausted)
    }

    @Test("A summary for one account uses that account's thread; equal priorities keep arrival order")
    func singleAccountThread() throws {
        let account = AccountID()
        let first = try Delivery.finished(account, "a")
        let second = try Delivery.finished(account, "b")
        let third = try Delivery.finished(account, "c")
        let summary = try #require(AlertSummary(alerts: [first, second, third]))
        #expect(summary.threadIdentifier == account.description)
        #expect(summary.alerts == [first, second, third])
        #expect(summary.sound == .finished)
        #expect(AlertSummary(alerts: []) == nil)
        #expect(AlertSummary(alerts: [try Delivery.resolved(account)]) == nil)
    }

    @Test("Alerts about the same thing collapse into the latest before counting")
    func latestPerIdentifier() throws {
        let account = AccountID()
        let at80 = try Delivery.threshold(account, used: 81, threshold: 80)
        let finished = try Delivery.finished(account)
        let at90 = try Delivery.threshold(account, used: 91, threshold: 90)
        #expect(AlertDelivery.plan([at80, finished, at90]) == [.single(finished), .single(at90)])
    }

    @Test("The summary identifier ignores order and duplicates and is a stable FNV-1a hash")
    func stableIdentifier() throws {
        #expect(AlertSummary.identifier(for: []) == "summary.cbf29ce484222325")
        #expect(AlertSummary.identifier(for: ["a"]) == "summary.af63dc4c8601ec8c")
        #expect(AlertSummary.identifier(for: ["a", "a"]) == AlertSummary.identifier(for: ["a"]))
        #expect(AlertSummary.identifier(for: ["x", "y", "z"]) == AlertSummary.identifier(for: ["z", "x", "y"]))
        #expect(AlertSummary.identifier(for: ["x", "y"]) != AlertSummary.identifier(for: ["x", "y", "z"]))

        let account = AccountID()
        let alerts = [try Delivery.finished(account, "a"), try Delivery.reset(account), try Delivery.threshold(account, window: "w")]
        let forward = try #require(AlertSummary(alerts: alerts))
        let backward = try #require(AlertSummary(alerts: alerts.reversed()))
        #expect(forward.identifier == backward.identifier)
        #expect(forward.identifier.hasPrefix(AlertSummary.identifierPrefix))
        let hex = forward.identifier.dropFirst(AlertSummary.identifierPrefix.count)
        #expect(hex.count == 16)
        #expect(hex.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    @Test(
        "Titles use the Russian plural",
        arguments: [
            (0, "0 событий"), (1, "1 событие"), (2, "2 события"), (4, "4 события"), (5, "5 событий"),
            (11, "11 событий"), (12, "12 событий"), (14, "14 событий"), (21, "21 событие"), (22, "22 события"),
            (25, "25 событий"), (101, "101 событие"), (111, "111 событий"), (-3, "0 событий"),
        ]
    )
    func titles(count: Int, expected: String) {
        let content = AlertSummaryContent(count: count, fragments: [])
        #expect(Localizer.testRussian.alertSummary.title(count: content.count) == expected)
    }

    @Test("Titles in English", arguments: [(1, "1 alert"), (3, "3 alerts"), (21, "21 alerts"), (-3, "0 alerts")])
    func englishTitles(count: Int, expected: String) {
        let content = AlertSummaryContent(count: count, fragments: [])
        #expect(Localizer.testEnglish.alertSummary.title(count: content.count) == expected)
    }

    @Test("The body lists three fragments, then an ellipsis")
    func body() {
        func body(_ fragments: [String]) -> String {
            let content = AlertSummary.content(fragments: fragments)
            return Localizer.testRussian.alertSummary.body(fragments: content.fragments, isTruncated: content.isTruncated)
        }
        #expect(body([]) == "")
        #expect(body(["A", "B", "C"]) == "A, B, C")
        #expect(body(["A", "", "B", "C", "D"]) == "A, B, C, …")
        let content = AlertSummary.content(fragments: ["A", "", "B", "C", "D"])
        #expect(content.count == 4)
        #expect(content.fragments == ["A", "B", "C"])
        #expect(content.isTruncated)
        #expect(!AlertSummary.content(fragments: ["A", "B", "C"]).isTruncated)
    }
}

@Suite("Alert delivery planner")
struct AlertDeliveryPlannerTests {
    private let now = Delivery.now

    @Test("Waiting alerts post at once even while coalescing")
    func waitingBypasses() throws {
        var planner = AlertDeliveryPlanner()
        let waiting = try Delivery.waiting(AccountID())
        let step = planner.receive([waiting], settings: Delivery.settings(), now: now)
        #expect(step.deliveries == [.single(waiting)])
        #expect(step.sound == .waiting)
        #expect(step.flushAt == nil)
        #expect(step.withdrawals.isEmpty)
        #expect(planner.pending.isEmpty)
        #expect(planner.isShowingAttention(waiting.notificationIdentifier))
    }

    @Test("Other alerts wait for the burst to end; the deadline is fixed by the first one")
    func buffering() throws {
        var planner = AlertDeliveryPlanner()
        let account = AccountID()
        let finished = try Delivery.finished(account)
        let reset = try Delivery.reset(account)

        let first = planner.receive([finished], settings: Delivery.settings(), now: now)
        #expect(first.deliveries.isEmpty)
        #expect(first.sound == nil)
        #expect(first.flushAt == now.addingTimeInterval(AlertDeliveryPlanner.burstWindow))

        let second = planner.receive([reset], settings: Delivery.settings(), now: now.addingTimeInterval(1))
        #expect(second.deliveries.isEmpty)
        #expect(second.flushAt == now.addingTimeInterval(AlertDeliveryPlanner.burstWindow))
        #expect(planner.pending == [finished, reset])

        let flushed = planner.flush(settings: Delivery.settings(), now: now.addingTimeInterval(1.5))
        #expect(flushed.deliveries == [.single(finished), .single(reset)])
        #expect(flushed.sound == .finished)
        #expect(flushed.flushAt == nil)
        #expect(flushed.withdrawals.isEmpty)
        #expect(planner.pending.isEmpty)
        #expect(planner.burstDeadline == nil)
        #expect(planner.flush(settings: Delivery.settings(), now: now.addingTimeInterval(2)).isEmpty)
    }

    @Test("A burst of three becomes one summary that withdraws the notifications it supersedes")
    func summaryFlush() throws {
        var planner = AlertDeliveryPlanner()
        let claude = AccountID()
        let codex = AccountID()
        let alerts = [try Delivery.finished(claude), try Delivery.threshold(codex), try Delivery.reset(codex, window: "week")]
        _ = planner.receive(alerts, settings: Delivery.settings(), now: now)

        let step = planner.flush(settings: Delivery.settings(), now: now.addingTimeInterval(1.5))
        let summary = try #require(Delivery.summaries(step).first)
        #expect(step.deliveries.count == 1)
        #expect(Localizer.testRussian.alertSummary.title(count: summary.alerts.count) == "3 события")
        #expect(Set(step.withdrawals) == Set(alerts.map(\.notificationIdentifier)))
        #expect(step.sound == .threshold)
    }

    @Test("Without coalescing every alert posts at once with one sound for the update")
    func notCoalescing() throws {
        var planner = AlertDeliveryPlanner()
        let account = AccountID()
        let alerts = [
            try Delivery.reset(account),
            try Delivery.threshold(account, window: "a"),
            try Delivery.finished(account),
            try Delivery.threshold(account, window: "b", used: 100, threshold: 100),
        ]
        let step = planner.receive(alerts, settings: Delivery.settings(coalesces: false), now: now)
        #expect(Delivery.singles(step) == alerts)
        #expect(step.sound == .exhausted)
        #expect(step.flushAt == nil)
        #expect(planner.pending.isEmpty)
    }

    @Test("Turning coalescing off delivers the buffered alerts first")
    func coalescingTurnedOff() throws {
        var planner = AlertDeliveryPlanner()
        let account = AccountID()
        let buffered = try Delivery.reset(account)
        let superseded = try Delivery.threshold(account, window: "w", used: 81, threshold: 80)
        let newer = try Delivery.threshold(account, window: "w", used: 91, threshold: 90)
        let finished = try Delivery.finished(account)
        _ = planner.receive([buffered, superseded], settings: Delivery.settings(), now: now)

        let step = planner.receive([finished, newer], settings: Delivery.settings(coalesces: false), now: now.addingTimeInterval(0.5))
        #expect(Delivery.singles(step) == [buffered, finished, newer])
        #expect(step.flushAt == nil)
        #expect(planner.pending.isEmpty)
    }

    @Test("A waiting alert drops a buffered alert about the same session")
    func waitingSupersedesBuffered() throws {
        var planner = AlertDeliveryPlanner()
        let account = AccountID()
        let finished = try Delivery.finished(account)
        let waiting = try Delivery.waiting(account)
        _ = planner.receive([finished], settings: Delivery.settings(), now: now)

        let step = planner.receive([waiting], settings: Delivery.settings(), now: now.addingTimeInterval(0.5))
        #expect(step.deliveries == [.single(waiting)])
        #expect(step.flushAt == nil)
        #expect(planner.pending.isEmpty)
        #expect(planner.burstDeadline == nil)
        #expect(planner.flush(settings: Delivery.settings(), now: now.addingTimeInterval(1.5)).deliveries.isEmpty)
        #expect(planner.isShowingAttention(waiting.notificationIdentifier))
    }

    @Test("A burst emptied by a waiting alert ends; the next buffered alert gets a full window")
    func emptiedBurstEnds() throws {
        var planner = AlertDeliveryPlanner()
        let account = AccountID()
        _ = planner.receive([try Delivery.finished(account)], settings: Delivery.settings(), now: now)
        _ = planner.receive([try Delivery.waiting(account)], settings: Delivery.settings(), now: now.addingTimeInterval(0.5))

        let later = now.addingTimeInterval(1)
        let step = planner.receive([try Delivery.reset(account)], settings: Delivery.settings(), now: later)
        #expect(step.deliveries.isEmpty)
        #expect(step.flushAt == later.addingTimeInterval(AlertDeliveryPlanner.burstWindow))
        #expect(planner.burstDeadline == later.addingTimeInterval(AlertDeliveryPlanner.burstWindow))
    }

    @Test("A resolved alert withdraws the waiting notification once")
    func withdrawal() throws {
        var planner = AlertDeliveryPlanner()
        let account = AccountID()
        let waiting = try Delivery.waiting(account)
        _ = planner.receive([waiting], settings: Delivery.settings(), now: now)

        let step = planner.receive([try Delivery.resolved(account)], settings: Delivery.settings(), now: now.addingTimeInterval(60))
        #expect(step.withdrawals == [waiting.notificationIdentifier])
        #expect(step.withdrawalsIfAttention.isEmpty)
        #expect(step.deliveries.isEmpty)
        #expect(step.sound == nil)
        #expect(step.flushAt == nil)
        #expect(!planner.isShowingAttention(waiting.notificationIdentifier))

        // No longer known as «ждёт»: only a delivered notification marked as «ждёт» would be removed.
        let again = planner.receive([try Delivery.resolved(account)], settings: Delivery.settings(), now: now.addingTimeInterval(61))
        #expect(again.withdrawals.isEmpty)
        #expect(again.withdrawalsIfAttention == [waiting.notificationIdentifier])
        #expect(again.deliveries.isEmpty)
        #expect(again.sound == nil)
    }

    @Test("A resolution this launch knows nothing about is checked against the delivered notification's marker")
    func resolvedFromEarlierLaunch() throws {
        var planner = AlertDeliveryPlanner()
        let account = AccountID()
        let resolved = try Delivery.resolved(account)
        let step = planner.receive([resolved, resolved], settings: Delivery.settings(), now: now)
        #expect(step.withdrawals.isEmpty)
        #expect(step.withdrawalsIfAttention == [resolved.notificationIdentifier])
        #expect(!step.isEmpty)

        let off = planner.receive([resolved], settings: Delivery.settings(withdraws: false), now: now)
        #expect(off.isEmpty)
    }

    @Test("A notification posted in the same step replaces the delivered one, so nothing is checked")
    func resolvedAndPostedTogether() throws {
        var planner = AlertDeliveryPlanner()
        let account = AccountID()
        let finished = try Delivery.finished(account)
        let step = planner.receive(
            [try Delivery.resolved(account), finished],
            settings: Delivery.settings(coalesces: false),
            now: now
        )
        #expect(step.deliveries == [.single(finished)])
        #expect(step.withdrawals.isEmpty)
        #expect(step.withdrawalsIfAttention.isEmpty)
    }

    @Test("A resolved alert never removes a finished notification that shares the identifier")
    func resolvedKeepsFinished() throws {
        var planner = AlertDeliveryPlanner()
        let account = AccountID()
        let settings = Delivery.settings(coalesces: false)
        _ = planner.receive([try Delivery.waiting(account)], settings: settings, now: now)
        let finished = try Delivery.finished(account)
        _ = planner.receive([finished], settings: settings, now: now.addingTimeInterval(30))
        #expect(!planner.isShowingAttention(finished.notificationIdentifier))

        let step = planner.receive([try Delivery.resolved(account)], settings: settings, now: now.addingTimeInterval(60))
        #expect(step.withdrawals.isEmpty)
        // The presenter keeps the delivered «закончил» notification: its user info is not marked as «ждёт».
        #expect(step.withdrawalsIfAttention == [finished.notificationIdentifier])
    }

    @Test("Nothing is withdrawn when withdrawing is off")
    func withdrawalOff() throws {
        var planner = AlertDeliveryPlanner()
        let account = AccountID()
        let settings = Delivery.settings(withdraws: false)
        let waiting = try Delivery.waiting(account)
        _ = planner.receive([waiting], settings: settings, now: now)
        let step = planner.receive([try Delivery.resolved(account)], settings: settings, now: now.addingTimeInterval(60))
        #expect(step.isEmpty)
        #expect(planner.isShowingAttention(waiting.notificationIdentifier))
    }

    @Test("A wait resolved within the same update is never posted")
    func resolvedInSameUpdate() throws {
        var planner = AlertDeliveryPlanner()
        let account = AccountID()
        let other = try Delivery.waiting(account, "s2")
        let step = planner.receive(
            [try Delivery.waiting(account), other, try Delivery.resolved(account)],
            settings: Delivery.settings(),
            now: now
        )
        #expect(step.deliveries == [.single(other)])
        #expect(step.withdrawals.isEmpty)
    }

    @Test("A summary forgets the waiting notifications it replaces")
    func summaryReplacesAttention() throws {
        var planner = AlertDeliveryPlanner()
        let account = AccountID()
        let waiting = try Delivery.waiting(account)
        _ = planner.receive([waiting], settings: Delivery.settings(), now: now)
        _ = planner.receive(
            [try Delivery.finished(account), try Delivery.reset(account), try Delivery.threshold(account, window: "w")],
            settings: Delivery.settings(),
            now: now.addingTimeInterval(10)
        )
        let step = planner.flush(settings: Delivery.settings(), now: now.addingTimeInterval(11.5))
        #expect(step.withdrawals.contains(waiting.notificationIdentifier))
        #expect(!planner.isShowingAttention(waiting.notificationIdentifier))
        #expect(step.withdrawalsIfAttention.isEmpty)
        // The later resolution has nothing left to withdraw at once.
        let resolved = planner.receive([try Delivery.resolved(account)], settings: Delivery.settings(), now: now.addingTimeInterval(20))
        #expect(resolved.withdrawals.isEmpty)
        #expect(resolved.deliveries.isEmpty)
    }

    @Test("A burst flushed right after an immediate waiting alert stays quiet; a louder sound still plays")
    func soundSpacing() throws {
        var planner = AlertDeliveryPlanner()
        let account = AccountID()
        let settings = Delivery.settings()
        let first = planner.receive([try Delivery.waiting(account), try Delivery.finished(account, "s2")], settings: settings, now: now)
        #expect(first.sound == .waiting)

        let flushed = planner.flush(settings: settings, now: now.addingTimeInterval(1.5))
        #expect(flushed.deliveries.count == 1)
        #expect(flushed.sound == nil)

        let louder = planner.receive(
            [try Delivery.threshold(account, used: 100, threshold: 100)],
            settings: Delivery.settings(coalesces: false),
            now: now.addingTimeInterval(2)
        )
        #expect(louder.sound == .exhausted)

        let later = planner.receive(
            [try Delivery.waiting(account, "s3")],
            settings: settings,
            now: now.addingTimeInterval(2 + AlertDeliveryPlanner.soundSpacing)
        )
        #expect(later.sound == .waiting)
    }

    @Test("Sounds off: deliveries without a sound")
    func soundsOff() throws {
        var planner = AlertDeliveryPlanner()
        let step = planner.receive([try Delivery.waiting(AccountID())], settings: Delivery.settings(sounds: false), now: now)
        #expect(step.deliveries.count == 1)
        #expect(step.sound == nil)
    }

    @Test("The buffer keeps the latest alert per identifier and at most the newest 64 alerts")
    func bounded() throws {
        var planner = AlertDeliveryPlanner()
        let account = AccountID()
        let at80 = try Delivery.threshold(account, used: 81, threshold: 80)
        let at90 = try Delivery.threshold(account, used: 91, threshold: 90)
        _ = planner.receive([at80, at90], settings: Delivery.settings(), now: now)
        #expect(planner.pending == [at90])

        let many = try (0..<70).map { try Delivery.finished(account, "s\($0)") }
        _ = planner.receive(many, settings: Delivery.settings(), now: now)
        #expect(planner.pending.count == AlertDeliveryPlanner.maximumPendingAlerts)
        #expect(planner.pending.first == many[6])
        #expect(planner.pending.last == many[69])
    }

    @Test("At most 256 waiting notifications are remembered")
    func attentionBounded() throws {
        var planner = AlertDeliveryPlanner()
        let account = AccountID()
        let alerts = try (0...AlertDeliveryPlanner.maximumTrackedAttention).map { try Delivery.waiting(account, "w\($0)") }
        _ = planner.receive(alerts, settings: Delivery.settings(sounds: false), now: now)
        #expect(!planner.isShowingAttention(alerts[0].notificationIdentifier))
        #expect(planner.isShowingAttention(alerts[1].notificationIdentifier))
        #expect(planner.isShowingAttention(alerts[AlertDeliveryPlanner.maximumTrackedAttention].notificationIdentifier))
    }
}

@Suite("Notification user info")
struct AlertUserInfoTests {
    @Test("The account id survives the round trip, also as a bridged NSString")
    func roundTrip() throws {
        let account = AccountID()
        let encoded = AlertUserInfo.encode(account)
        #expect(encoded == [AlertUserInfo.accountKey: account.rawValue.uuidString])
        let userInfo: [AnyHashable: Any] = encoded
        #expect(AlertUserInfo.accountID(from: userInfo) == account)
        let bridged: [AnyHashable: Any] = [AnyHashable(AlertUserInfo.accountKey): NSString(string: account.rawValue.uuidString)]
        #expect(AlertUserInfo.accountID(from: bridged) == account)
    }

    @Test("Only single waiting deliveries are marked as «ждёт», and only the exact marker is accepted back")
    func attentionMarker() throws {
        let account = AccountID()
        let waiting = AlertDelivery.single(try Delivery.waiting(account))
        #expect(waiting.isAttention)
        #expect(!AlertDelivery.single(try Delivery.finished(account)).isAttention)
        #expect(!AlertDelivery.single(try Delivery.threshold(account)).isAttention)
        let summary = try #require(
            AlertSummary(alerts: [try Delivery.finished(account), try Delivery.reset(account), try Delivery.threshold(account, window: "w")])
        )
        #expect(!AlertDelivery.summary(summary).isAttention)

        let marked = AlertUserInfo.encode(account, isAttention: true)
        #expect(marked == [AlertUserInfo.accountKey: account.rawValue.uuidString, AlertUserInfo.kindKey: AlertUserInfo.attentionKind])
        #expect(AlertUserInfo.isAttention(marked))
        #expect(AlertUserInfo.accountID(from: marked) == account)
        #expect(!AlertUserInfo.isAttention(AlertUserInfo.encode(account)))
        #expect(AlertUserInfo.encode(account)[AlertUserInfo.kindKey] == nil)
        #expect(AlertUserInfo.isAttention([AnyHashable(AlertUserInfo.kindKey): NSString(string: AlertUserInfo.attentionKind)]))
        for value: Any in ["Attention", "attention ", "", 1, true] {
            #expect(!AlertUserInfo.isAttention([AlertUserInfo.kindKey: value]))
        }
        #expect(!AlertUserInfo.isAttention([:]))
    }

    @Test("Anything but a canonical UUID string is rejected")
    func rejects() throws {
        let uuid = try #require(UUID(uuidString: "8C8E4A0E-3B1A-4C7B-9D5E-000000000001"))
        let canonical = uuid.uuidString
        #expect(AlertUserInfo.accountID(fromString: canonical) == AccountID(rawValue: uuid))
        for raw in [
            "",
            canonical.lowercased(),
            "{\(canonical)}",
            " \(canonical)",
            "\(canonical)\n",
            canonical.replacingOccurrences(of: "-", with: ""),
            String(canonical.dropLast()),
            canonical + "0",
            "not-a-uuid-at-all-not-a-uuid-at-all!",
        ] {
            #expect(AlertUserInfo.accountID(fromString: raw) == nil)
        }
        #expect(AlertUserInfo.accountID(from: [:]) == nil)
        #expect(AlertUserInfo.accountID(from: ["other": canonical]) == nil)
        #expect(AlertUserInfo.accountID(from: [AlertUserInfo.accountKey: 42]) == nil)
        #expect(AlertUserInfo.accountID(from: [AlertUserInfo.accountKey: uuid]) == nil)
    }
}

// MARK: - Notification and menu bar copy

/// The words `AlertPresenter` (notifications, the launch alert, the login item message) and the app shell's menus use.
@Suite("Notification phrases")
struct NotificationPhraseTests {
    @Test("Titles name the account, then what happened, lowercase after the colon")
    func titles() {
        let en = Localizer.testEnglish.notification
        let percent = Localizer.testEnglish.format.percent(80)
        #expect(en.thresholdReached(account: "Work", percent: percent) == "Work: 80% used")
        #expect(en.limitReached(account: "Work") == "Work: limit reached")
        #expect(en.limitReset(account: "Work") == "Work: limit reset")
        #expect(en.agentFinished(account: "Work") == "Work: agent finished")
        #expect(en.needsApproval(account: "Work") == "Work: needs approval")
        #expect(en.needsInput(account: "Work") == "Work: needs input")
        #expect(en.waitingForYou(account: "Work") == "Work: waiting for you")

        let ru = Localizer.testRussian.notification
        let percentRU = Localizer.testRussian.format.percent(80)
        #expect(ru.thresholdReached(account: "Работа", percent: percentRU) == "Работа: использовано 80\u{00A0}%")
        #expect(ru.limitReached(account: "Работа") == "Работа: лимит исчерпан")
        #expect(ru.limitReset(account: "Работа") == "Работа: лимит сброшен")
        #expect(ru.agentFinished(account: "Работа") == "Работа: агент закончил")
        #expect(ru.needsApproval(account: "Работа") == "Работа: ждёт подтверждения")
        #expect(ru.needsInput(account: "Работа") == "Работа: ждёт ввода")
        #expect(ru.waitingForYou(account: "Работа") == "Работа: ждёт вас")
    }

    @Test("Bodies read as sentences with the window's title")
    func bodies() {
        let en = Localizer.testEnglish
        let window = en.window.weeklyAllModels
        #expect(en.notification.windowUsage(window: window, percent: en.format.percent(82)) == "Weekly · All models is at 82%")
        #expect(en.notification.availableAgain(window: window) == "Weekly · All models is available again")
        #expect(en.usage.resetsIn(en.format.durationCompact(2 * 3_600 + 14 * 60)) == "Resets in 2h 14m")

        let ru = Localizer.testRussian
        let windowRU = ru.window.weeklyAllModels
        #expect(ru.notification.windowUsage(window: windowRU, percent: ru.format.percent(82)) == "Неделя · все модели — 82\u{00A0}%")
        #expect(ru.notification.availableAgain(window: windowRU) == "Неделя · все модели — лимит снова доступен")
    }

    @Test("A burst's summary lists one line per alert")
    func summaryLines() {
        let en = Localizer.testEnglish
        let lines = [
            en.notification.agentFinishedLine(account: "Claude", session: "codometer"),
            en.notification.usageLine(account: "Codex", percent: en.format.percent(82), window: en.window.weeklyAllModels),
            en.notification.limitResetLine(account: "Work", window: en.window.session(length: en.window.length(minutes: 300))),
        ]
        #expect(
            en.alertSummary.body(fragments: lines, isTruncated: true)
                == "Claude: agent finished (codometer), Codex: 82% used (Weekly · All models), Work: limit reset (Session · 5h), …"
        )
        #expect(en.notification.limitReachedLine(account: "Work", window: "Session · 5h") == "Work: limit reached (Session · 5h)")
        #expect(en.notification.needsApprovalLine(account: "Work", session: "api") == "Work: needs approval (api)")
        #expect(en.notification.needsInputLine(account: "Work", session: "api") == "Work: needs input (api)")
        #expect(en.notification.waitingForYouLine(account: "Work", session: "api") == "Work: waiting for you (api)")

        let ru = Localizer.testRussian
        #expect(ru.notification.agentFinishedLine(account: "Claude", session: "codometer") == "Claude: агент закончил (codometer)")
        #expect(
            ru.notification.usageLine(account: "Codex", percent: ru.format.percent(82), window: ru.window.weeklyAllModels)
                == "Codex: использовано 82\u{00A0}% (Неделя · все модели)"
        )
        #expect(ru.notification.limitReachedLine(account: "Работа", window: "Сессия · 5\u{00A0}ч") == "Работа: лимит исчерпан (Сессия · 5\u{00A0}ч)")
        #expect(ru.notification.limitResetLine(account: "Работа", window: "Неделя") == "Работа: лимит сброшен (Неделя)")
        #expect(ru.notification.needsApprovalLine(account: "Работа", session: "api") == "Работа: ждёт подтверждения (api)")
        #expect(ru.notification.needsInputLine(account: "Работа", session: "api") == "Работа: ждёт ввода (api)")
        #expect(ru.notification.waitingForYouLine(account: "Работа", session: "api") == "Работа: ждёт вас (api)")
    }

    @Test("The launch alert and the login item message keep the technical detail as it is")
    func appMessages() {
        let detail = "permission denied: ~/Library/Application Support/Codometer"
        let en = Localizer.testEnglish.notification
        #expect(en.launchFailedTitle == "Codometer can’t start")
        #expect(en.dataFolderFailedMessage(detail: detail) == "Codometer couldn’t create the folder where it keeps its settings and history.\n\n\(detail)")
        #expect(en.quit == "Quit")
        #expect(en.loginItemFailed(reason: "Operation not permitted.") == "Couldn’t change “Open at login”: Operation not permitted.")
        let ru = Localizer.testRussian.notification
        #expect(ru.launchFailedTitle == "Не удалось запустить Codometer")
        #expect(ru.dataFolderFailedMessage(detail: detail) == "Не удалось создать папку, в которой Codometer хранит настройки и историю.\n\n\(detail)")
        #expect(ru.quit == "Выйти")
        #expect(ru.loginItemFailed(reason: "Операция не разрешена.") == "Не удалось изменить «Открывать при входе в систему»: Операция не разрешена.")
    }

    /// `AlertPresenter` maps a waiting session onto its own title by comparing the island's own wording with
    /// `usage.needsApproval` and `usage.needsInput`. The mapping only works while those three phrases differ, so
    /// changing their text must not make any two of them equal.
    @Test("The waiting phrases the notification titles are matched against stay distinct", arguments: Language.allCases)
    func waitingPhrasesAreDistinct(language: Language) {
        let l10n = language == .en ? Localizer.testEnglish : .testRussian
        let phrases = [l10n.usage.needsApproval, l10n.usage.needsInput, l10n.usage.waitingForYou]
        #expect(Set(phrases).count == phrases.count, "\(phrases)")
        #expect(phrases.allSatisfy { !$0.isEmpty })
    }
}

@Suite("Menu bar item and island menu phrases")
struct ShellMenuPhraseTests {
    @Test("Menu items: Title Case in English, sentence case in Russian")
    func menus() {
        let en = Localizer.testEnglish
        #expect([en.menu.refreshAll, en.menu.settings, en.menu.hideIsland, en.menu.showIsland, en.menu.quit]
            == ["Refresh All", "Settings…", "Hide Island", "Show Island", "Quit Codometer"])
        #expect([en.islandMenu.show, en.islandMenu.allAccounts, en.islandMenu.expand, en.islandMenu.placement] == ["Show", "All Accounts", "Expand", "Placement"])
        #expect([en.islandMenu.onHover, en.islandMenu.onClick, en.islandMenu.onHoverOrClick] == ["On Hover", "On Click", "On Hover or Click"])
        #expect([en.islandMenu.top, en.islandMenu.bottom, en.islandMenu.left, en.islandMenu.right] == ["Top", "Bottom", "Left", "Right"])
        #expect([en.islandMenu.attachedToEdge, en.islandMenu.floating] == ["Attached to Edge", "Detached"])

        let ru = Localizer.testRussian
        #expect([ru.menu.refreshAll, ru.menu.settings, ru.menu.hideIsland, ru.menu.showIsland, ru.menu.quit]
            == ["Обновить всё", "Настройки…", "Скрыть остров", "Показать остров", "Выйти из Codometer"])
        #expect([ru.islandMenu.show, ru.islandMenu.allAccounts, ru.islandMenu.expand, ru.islandMenu.placement] == ["Показывать", "Все аккаунты", "Раскрывать", "Расположение"])
        #expect([ru.islandMenu.onHover, ru.islandMenu.onClick, ru.islandMenu.onHoverOrClick] == ["При наведении", "По клику", "При наведении или по клику"])
        #expect([ru.islandMenu.top, ru.islandMenu.bottom, ru.islandMenu.left, ru.islandMenu.right] == ["Сверху", "Снизу", "Слева", "Справа"])
        #expect([ru.islandMenu.attachedToEdge, ru.islandMenu.floating] == ["Прилегает к краю", "Парящий"])
    }

    @Test("The menu bar icon's tooltip and VoiceOver text")
    func statusItem() {
        let en = Localizer.testEnglish
        let percent = en.format.percent(64)
        #expect(en.statusItem.help == "Codometer: Claude and Codex limits")
        #expect(en.statusItem.iconA11y(percent: nil, waitingCount: 0) == "Codometer, no data")
        #expect(en.statusItem.iconA11y(percent: percent, waitingCount: 0) == "Codometer, 64% used")
        #expect(en.statusItem.iconA11y(percent: nil, waitingCount: 1) == "Codometer, 1 agent is waiting for you")
        #expect(en.statusItem.iconA11y(percent: percent, waitingCount: 2) == "Codometer, 64% used, 2 agents are waiting for you")

        let ru = Localizer.testRussian
        let percentRU = ru.format.percent(64)
        #expect(ru.statusItem.help == "Codometer — лимиты Claude и Codex")
        #expect(ru.statusItem.iconA11y(percent: nil, waitingCount: 0) == "Codometer, нет данных")
        #expect(ru.statusItem.iconA11y(percent: percentRU, waitingCount: 0) == "Codometer, использовано 64\u{00A0}%")
        #expect(ru.statusItem.iconA11y(percent: nil, waitingCount: 1) == "Codometer, вас ждёт 1 агент")
        #expect(ru.statusItem.iconA11y(percent: percentRU, waitingCount: 3) == "Codometer, использовано 64\u{00A0}%, вас ждут 3 агента")
        #expect(ru.statusItem.iconA11y(percent: percentRU, waitingCount: 5) == "Codometer, использовано 64\u{00A0}%, вас ждут 5 агентов")
        #expect(ru.statusItem.iconA11y(percent: nil, waitingCount: 21) == "Codometer, вас ждёт 21 агент")
    }
}


// MARK: - Copy previews

/// Draws the app shell's text — the menu bar and island menus, notifications and the launch alert — in English and
/// Russian, so the copy can be reviewed in something close to its real shape. AppKit menus, notification banners and
/// alerts cannot be captured off-screen, so these are mock-ups of macOS chrome around the real phrases; the
/// notification lines are composed exactly as `AlertPresenter` composes them.
///
/// Runs only when `CODOMETER_SNAPSHOT_DIR` is set.
@MainActor
@Suite("ShellCopyPreview", .enabled(if: ProcessInfo.processInfo.environment["CODOMETER_SNAPSHOT_DIR"] != nil))
struct ShellCopyPreviewTests {
    private let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODOMETER_SNAPSHOT_DIR"] ?? "/tmp", isDirectory: true)

    private struct MenuItem {
        let title: String
        var symbol: String?
        var key: String = ""
        var isChecked = false
        var hasSubmenu = false
        var isSeparator = false

        static let separator = MenuItem(title: "", isSeparator: true)
    }

    private struct MenuMock: View {
        let name: String
        let items: [MenuItem]

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    if item.isSeparator {
                        Divider().padding(.vertical, 4)
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: item.isChecked ? "checkmark" : "circle")
                                .font(.system(size: 10, weight: .semibold))
                                .opacity(item.isChecked ? 1 : 0)
                                .frame(width: 12)
                            if let symbol = item.symbol {
                                Image(systemName: symbol).font(.system(size: 11)).frame(width: 16)
                            }
                            Text(verbatim: item.title).font(.system(size: 13))
                            Spacer(minLength: 24)
                            if item.hasSubmenu {
                                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                            }
                            if !item.key.isEmpty {
                                Text(verbatim: item.key).font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
            .padding(10)
            .frame(width: 260, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.98)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.12)))
        }
    }

    private struct NotificationMock: View {
        let title: String
        let message: String

        var body: some View {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(colors: [.orange, .pink], startPoint: .top, endPoint: .bottom))
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "Codometer").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    Text(verbatim: title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(verbatim: message).font(.system(size: 13)).lineLimit(3).foregroundStyle(.primary.opacity(0.85))
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(width: 344, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(white: 0.97)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.black.opacity(0.1)))
        }
    }

    private struct AlertMock: View {
        let title: String
        let message: String
        let button: String

        var body: some View {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 30)).foregroundStyle(.orange)
                Text(verbatim: title).font(.system(size: 13, weight: .bold)).multilineTextAlignment(.center)
                Text(verbatim: message).font(.system(size: 11)).multilineTextAlignment(.center).foregroundStyle(.secondary)
                Text(verbatim: button)
                    .font(.system(size: 13))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.85)))
                    .foregroundStyle(.white)
            }
            .padding(18)
            .frame(width: 360)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.96)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.1)))
        }
    }

    @Test("Menus, notifications and the launch alert", arguments: Language.allCases)
    func shellCopy(language: Language) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let l10n = language == .en ? Localizer.testEnglish : .testRussian
        let menu = l10n.menu
        let island = l10n.islandMenu
        let hiddenIslandMenu = MenuMock(name: "Menu bar item, island hidden", items: [
            MenuItem(title: menu.refreshAll, symbol: "arrow.clockwise", key: "⌘R"),
            MenuItem(title: menu.settings, symbol: "gearshape", key: "⌘,"),
            MenuItem(title: menu.showIsland, symbol: "eye"),
            .separator,
            MenuItem(title: menu.quit, symbol: "power", key: "⌘Q"),
        ])
        let statusMenu = MenuMock(name: "Menu bar item", items: [
            MenuItem(title: menu.refreshAll, symbol: "arrow.clockwise", key: "⌘R"),
            MenuItem(title: menu.settings, symbol: "gearshape", key: "⌘,"),
            MenuItem(title: menu.hideIsland, symbol: "eye.slash"),
            .separator,
            MenuItem(title: menu.quit, symbol: "power", key: "⌘Q"),
        ])
        let contextMenu = MenuMock(name: "Island, right click", items: [
            MenuItem(title: menu.refreshAll, symbol: "arrow.clockwise"),
            MenuItem(title: menu.settings, symbol: "gearshape"),
            .separator,
            MenuItem(title: island.show, symbol: "person.2", hasSubmenu: true),
            MenuItem(title: island.expand, symbol: "cursorarrow.rays", hasSubmenu: true),
            MenuItem(title: island.placement, symbol: "rectangle.dashed", hasSubmenu: true),
            MenuItem(title: menu.hideIsland, symbol: "eye.slash"),
            .separator,
            MenuItem(title: menu.quit, symbol: "power"),
        ])
        let showSubmenu = MenuMock(name: "\(island.show) ▸", items: [
            MenuItem(title: island.allAccounts, isChecked: true),
            .separator,
            MenuItem(title: language == .en ? "Work" : "Работа"),
            MenuItem(title: language == .en ? "Personal" : "Личное"),
        ])
        let expandSubmenu = MenuMock(name: "\(island.expand) ▸", items: [
            MenuItem(title: island.onHover, isChecked: true),
            MenuItem(title: island.onClick),
            MenuItem(title: island.onHoverOrClick),
        ])
        let placementSubmenu = MenuMock(name: "\(island.placement) ▸", items: [
            MenuItem(title: island.top, isChecked: true),
            MenuItem(title: island.bottom),
            MenuItem(title: island.left),
            MenuItem(title: island.right),
            .separator,
            MenuItem(title: island.attachedToEdge, isChecked: true),
            MenuItem(title: island.floating),
        ])
        let menus = HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                statusMenu
                hiddenIslandMenu
                showSubmenu
            }
            VStack(alignment: .leading, spacing: 16) {
                contextMenu
                expandSubmenu
            }
            placementSubmenu
        }
        try render(menus, name: "shell-menus-\(language.rawValue)")

        let account = language == .en ? "Work" : "Работа"
        let notification = l10n.notification
        let window = l10n.window.weeklyAllModels
        let session = l10n.window.session(length: l10n.window.length(minutes: 300))
        let reset = l10n.usage.resetsIn(l10n.format.durationCompact(2 * 3_600 + 14 * 60))
        let clock = l10n.usage.resets(at: l10n.format.moment(Date(timeIntervalSince1970: 1_790_000_000), now: Date(timeIntervalSince1970: 1_789_600_000)))
        let turn = "codometer · " + [l10n.usage.turn(l10n.format.durationPrecise(252)), l10n.usage.firstToken(l10n.format.latency(2.8))].joined(separator: " · ")
        let banners = VStack(alignment: .leading, spacing: 12) {
            NotificationMock(
                title: notification.thresholdReached(account: account, percent: l10n.format.percent(80)),
                message: sentences([notification.windowUsage(window: window, percent: l10n.format.percent(82)), reset], l10n: l10n)
            )
            NotificationMock(
                title: notification.limitReached(account: account),
                message: sentences([notification.windowUsage(window: window, percent: l10n.format.percent(100)), clock], l10n: l10n)
            )
            NotificationMock(title: notification.limitReset(account: account), message: sentences([notification.availableAgain(window: session)], l10n: l10n))
            NotificationMock(title: notification.agentFinished(account: account), message: turn)
            NotificationMock(title: notification.needsApproval(account: account), message: "codometer")
            NotificationMock(
                title: l10n.alertSummary.title(count: 4),
                message: l10n.alertSummary.body(
                    fragments: [
                        notification.agentFinishedLine(account: "Claude", session: "codometer"),
                        notification.usageLine(account: "Codex", percent: l10n.format.percent(82), window: window),
                        notification.limitResetLine(account: account, window: session),
                    ],
                    isTruncated: true
                )
            )
        }
        try render(banners, name: "shell-notifications-\(language.rawValue)")

        let alert = AlertMock(
            title: notification.launchFailedTitle,
            message: notification.dataFolderFailedMessage(detail: "permission denied: ~/Library/Application Support/Codometer"),
            button: notification.quit
        )
        let loginItem = VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: l10n.statusItem.help).font(.system(size: 11)).padding(6)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color(white: 0.93)))
            Text(verbatim: notification.loginItemFailed(reason: "The operation couldn’t be completed."))
                .font(.system(size: 11)).foregroundStyle(.red)
            Text(verbatim: l10n.statusItem.iconA11y(percent: l10n.format.percent(64), waitingCount: 2))
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(width: 360, alignment: .leading)
        try render(VStack(alignment: .leading, spacing: 16) { alert; loginItem }, name: "shell-alerts-\(language.rawValue)")
    }

    /// Exactly what `AlertPresenter` does: a reset caption starts the sentence, so it is capitalised, and every
    /// sentence ends with a period.
    private func sentences(_ parts: [String], l10n: Localizer) -> String {
        parts
            .map { $0.prefix(1).uppercased(with: l10n.locale) + $0.dropFirst() }
            .map { $0.hasSuffix("…") || $0.hasSuffix(".") ? $0 : $0 + "." }
            .joined(separator: " ")
    }

    private func render(_ content: some View, name: String) throws {
        let renderer = ImageRenderer(content: content.padding(24).background(Color(white: 0.9)).environment(\.colorScheme, .light))
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }
}
