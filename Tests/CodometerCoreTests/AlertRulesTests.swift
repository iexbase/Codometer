import CodometerCore
import Foundation
import Testing

@Suite("Alert identity")
struct TrackerAlertIdentityTests {
    @Test("Identifiers are deterministic per session and per window")
    func identifiers() throws {
        let accountID = try #require(UUID(uuidString: "8C8E4A0E-3B1A-4C7B-9D5E-000000000001")).uuidString
        let account = AccountID(rawValue: try #require(UUID(uuidString: accountID)))
        let session = try Fixture.session(.waiting, id: "abc-123")
        let context = AlertWindowContext(
            accountID: account,
            bucketID: "codex",
            bucketTitle: nil,
            window: try Fixture.window("primary", used: 80)
        )

        let finished = TrackerAlert.sessionFinished(accountID: account, session: session)
        let waiting = TrackerAlert.sessionNeedsAttention(accountID: account, session: session)
        let resolved = TrackerAlert.sessionAttentionResolved(accountID: account, session: session)
        let threshold = TrackerAlert.thresholdReached(context, threshold: try Percentage(validating: 80))
        let reset = TrackerAlert.limitReset(context)

        for alert in [finished, waiting, resolved] {
            #expect(alert.notificationIdentifier == "session.\(accountID).abc-123")
        }
        for alert in [threshold, reset] {
            #expect(alert.notificationIdentifier == "limit.\(accountID).codex.primary")
        }
        for alert in [finished, waiting, resolved, threshold, reset] {
            #expect(alert.threadIdentifier == accountID)
            #expect(alert.accountID == account)
            #expect(alert.isSilent == (alert == resolved))
        }
    }
}

@Suite("Alert rules")
struct AlertRulesTests {
    private func status(
        _ profile: AccountProfile,
        _ reading: UsageReading? = nil,
        sessions: [AgentSession] = []
    ) -> AccountStatus {
        AccountStatus(profile: profile, reading: reading, sessions: sessions)
    }

    private func state(_ accounts: AccountStatus...) -> TrackerState {
        TrackerState(accounts: accounts)
    }

    // MARK: Usage

    @Test("Every window of every bucket is watched, not only the headline ones")
    func allWindowsAllBuckets() throws {
        let account = try Fixture.profile(.claude, path: "/tmp/.claude")
        let before = try Fixture.reading([
            try Fixture.bucket("main", [
                try Fixture.window("session", .session, used: 10),
                try Fixture.window("week", .weekly(model: nil), used: 38, minutes: 10_080),
                try Fixture.window("week.fable", .weekly(model: "Fable"), used: 70, minutes: 10_080),
            ]),
            try Fixture.bucket("extra", [try Fixture.window("primary", used: 95)]),
        ], at: Fixture.now)
        let after = try Fixture.reading([
            try Fixture.bucket("main", [
                try Fixture.window("session", .session, used: 12),
                try Fixture.window("week", .weekly(model: nil), used: 40, minutes: 10_080),
                try Fixture.window("week.fable", .weekly(model: "Fable"), used: 81, minutes: 10_080),
            ]),
            try Fixture.bucket("extra", [try Fixture.window("primary", used: 100)]),
        ], at: Fixture.now.addingTimeInterval(60))

        let alerts = AlertEvaluator(settings: AlertSettings()).alerts(
            from: state(status(account, before)),
            to: state(status(account, after))
        )
        #expect(alerts.count == 2)
        #expect(alerts.map(\.notificationIdentifier) == [
            "limit.\(account.id).main.week.fable",
            "limit.\(account.id).extra.primary",
        ])
        guard case let .thresholdReached(context, threshold) = alerts.last else {
            Issue.record("expected a threshold alert, got \(alerts)")
            return
        }
        #expect(context.bucketID == "extra")
        #expect(threshold.value == 100)
    }

    @Test("Resets are detected in model-scoped windows too")
    func resetInModelWindow() throws {
        let account = try Fixture.profile()
        let before = try Fixture.reading([
            try Fixture.window("session", .session, used: 10, resetsIn: 3_600),
            try Fixture.window("week.fable", .weekly(model: "Fable"), used: 90, minutes: 10_080, resetsIn: 60),
        ])
        let after = try Fixture.reading([
            try Fixture.window("session", .session, used: 11, resetsIn: 3_600),
            try Fixture.window("week.fable", .weekly(model: "Fable"), used: 1, minutes: 10_080, resetsIn: 604_800),
        ], at: Fixture.now.addingTimeInterval(120))
        let alerts = AlertEvaluator(settings: AlertSettings()).alerts(from: state(status(account, before)), to: state(status(account, after)))
        guard alerts.count == 1, case .limitReset(let context) = alerts[0] else {
            Issue.record("expected one reset alert, got \(alerts)")
            return
        }
        #expect(context.window.id == "week.fable")
    }

    @Test("Windows or buckets that did not exist before stay silent")
    func newWindowsSilent() throws {
        let account = try Fixture.profile()
        let before = try Fixture.reading([try Fixture.bucket("a", [try Fixture.window("primary", used: 10)])])
        let after = try Fixture.reading([
            try Fixture.bucket("a", [try Fixture.window("primary", used: 10), try Fixture.window("secondary", used: 100)]),
            try Fixture.bucket("b", [try Fixture.window("primary", used: 100)]),
        ], at: Fixture.now.addingTimeInterval(60))
        #expect(AlertEvaluator(settings: AlertSettings()).alerts(from: state(status(account, before)), to: state(status(account, after))).isEmpty)
    }

    // MARK: Short turns

    @Test("Short turns do not raise 'finished'; the fallback duration is the time between activity changes")
    func shortTurnFallback() throws {
        let account = try Fixture.profile()
        let evaluator = AlertEvaluator(settings: AlertSettings())
        let working = try Fixture.session(.working, since: Fixture.now)

        let quick = evaluator.alerts(
            from: state(status(account, sessions: [working])),
            to: state(status(account, sessions: [try Fixture.session(.idle, since: Fixture.now.addingTimeInterval(19))]))
        )
        #expect(quick.isEmpty)

        let long = evaluator.alerts(
            from: state(status(account, sessions: [working])),
            to: state(status(account, sessions: [try Fixture.session(.idle, since: Fixture.now.addingTimeInterval(20))]))
        )
        guard case .sessionFinished = long.first else {
            Issue.record("expected sessionFinished, got \(long)")
            return
        }

        var always = AlertSettings()
        always.minimumTurnForFinishedAlert = .always
        let instant = AlertEvaluator(settings: always).alerts(
            from: state(status(account, sessions: [working])),
            to: state(status(account, sessions: [try Fixture.session(.idle, since: Fixture.now)]))
        )
        #expect(instant.count == 1)
    }

    @Test("The session's own turn timing wins when it ended after the previous activity started")
    func shortTurnFromTiming() throws {
        let account = try Fixture.profile()
        let evaluator = AlertEvaluator(settings: AlertSettings())
        // Observed as working for 10 minutes (e.g. a poll was missed), but the turn itself took 5 s.
        let working = try Fixture.session(.working, since: Fixture.now)
        let quickTurn = try TurnTiming(
            startedAt: Fixture.now.addingTimeInterval(595),
            endedAt: Fixture.now.addingTimeInterval(600),
            duration: 5,
            firstTokenLatency: nil,
            wasAborted: false
        )
        let quick = try Fixture.session(.idle, since: Fixture.now.addingTimeInterval(600), lastTurn: quickTurn)
        #expect(evaluator.alerts(from: state(status(account, sessions: [working])), to: state(status(account, sessions: [quick]))).isEmpty)

        // Observed for 5 s, but the reported turn took 4 minutes.
        let longTurn = try TurnTiming(
            startedAt: Fixture.now.addingTimeInterval(-235),
            endedAt: Fixture.now.addingTimeInterval(5),
            duration: 240,
            firstTokenLatency: 2.8,
            wasAborted: false
        )
        let finished = try Fixture.session(.idle, since: Fixture.now.addingTimeInterval(5), lastTurn: longTurn)
        let alerts = evaluator.alerts(from: state(status(account, sessions: [working])), to: state(status(account, sessions: [finished])))
        guard case let .sessionFinished(_, session) = alerts.first else {
            Issue.record("expected sessionFinished, got \(alerts)")
            return
        }
        #expect(session.lastTurn == longTurn)

        // A stale turn from before the observed working period is ignored: 10 s observed → suppressed.
        let staleTurn = try TurnTiming(
            startedAt: Fixture.now.addingTimeInterval(-900),
            endedAt: Fixture.now.addingTimeInterval(-600),
            duration: 300,
            firstTokenLatency: nil,
            wasAborted: false
        )
        let stale = try Fixture.session(.idle, since: Fixture.now.addingTimeInterval(10), lastTurn: staleTurn)
        #expect(evaluator.alerts(from: state(status(account, sessions: [working])), to: state(status(account, sessions: [stale]))).isEmpty)
    }

    @Test("'Finished' drops a stale turn timing and keeps the timing of the turn that just ended")
    func finishedClearsStaleTurn() throws {
        let account = try Fixture.profile()
        let evaluator = AlertEvaluator(settings: AlertSettings())
        let working = try Fixture.session(.working, since: Fixture.now)

        // Observed working for 2 minutes; the only timing is from a turn that ended before this one started.
        let staleTurn = try TurnTiming(
            startedAt: Fixture.now.addingTimeInterval(-900),
            endedAt: Fixture.now.addingTimeInterval(-600),
            duration: 300,
            firstTokenLatency: 1.2,
            wasAborted: false
        )
        let stale = try Fixture.session(.idle, since: Fixture.now.addingTimeInterval(120), lastTurn: staleTurn)
        let staleAlerts = evaluator.alerts(from: state(status(account, sessions: [working])), to: state(status(account, sessions: [stale])))
        guard staleAlerts.count == 1, case let .sessionFinished(_, staleSession) = staleAlerts[0] else {
            Issue.record("expected one sessionFinished, got \(staleAlerts)")
            return
        }
        #expect(staleSession.lastTurn == nil)
        #expect(staleSession.id == stale.id)
        #expect(staleSession.activitySince == stale.activitySince)
        #expect(staleSession == stale.removingLastTurn())
        #expect(staleAlerts[0].notificationIdentifier == "session.\(account.id).\(stale.id)")

        // A turn that ended exactly when the previous activity started is not this turn either.
        let boundaryTurn = try TurnTiming(
            startedAt: Fixture.now.addingTimeInterval(-60),
            endedAt: Fixture.now,
            duration: 60,
            firstTokenLatency: nil,
            wasAborted: false
        )
        let boundary = try Fixture.session(.idle, since: Fixture.now.addingTimeInterval(120), lastTurn: boundaryTurn)
        let boundaryAlerts = evaluator.alerts(from: state(status(account, sessions: [working])), to: state(status(account, sessions: [boundary])))
        #expect(boundaryAlerts == [.sessionFinished(accountID: account.id, session: boundary.removingLastTurn())])

        // The current turn's timing stays on the alert.
        let currentTurn = try TurnTiming(
            startedAt: Fixture.now,
            endedAt: Fixture.now.addingTimeInterval(118),
            duration: 118,
            firstTokenLatency: 2.8,
            wasAborted: false
        )
        let finished = try Fixture.session(.idle, since: Fixture.now.addingTimeInterval(120), lastTurn: currentTurn)
        let alerts = evaluator.alerts(from: state(status(account, sessions: [working])), to: state(status(account, sessions: [finished])))
        #expect(alerts == [.sessionFinished(accountID: account.id, session: finished)])

        // Without timing there is nothing to remove.
        let plain = try Fixture.session(.idle, since: Fixture.now.addingTimeInterval(120))
        #expect(plain.removingLastTurn() == plain)
        let plainAlerts = evaluator.alerts(from: state(status(account, sessions: [working])), to: state(status(account, sessions: [plain])))
        #expect(plainAlerts == [.sessionFinished(accountID: account.id, session: plain)])
    }

    // MARK: Resolution

    @Test("Waiting that ends emits a silent resolved event")
    func resolvedOnTransition() throws {
        let account = try Fixture.profile()
        let evaluator = AlertEvaluator(settings: AlertSettings())
        let waiting = try Fixture.session(.waiting, since: Fixture.now)

        for next in [AgentActivity.working, .idle] {
            let resumed = try Fixture.session(next, since: Fixture.now.addingTimeInterval(300))
            let alerts = evaluator.alerts(
                from: state(status(account, sessions: [waiting])),
                to: state(status(account, sessions: [resumed]))
            )
            #expect(alerts == [.sessionAttentionResolved(accountID: account.id, session: resumed)])
            #expect(alerts.allSatisfy { $0.isSilent })
        }

        let stillWaiting = evaluator.alerts(
            from: state(status(account, sessions: [waiting])),
            to: state(status(account, sessions: [waiting]))
        )
        #expect(stillWaiting.isEmpty)
    }

    @Test("A waiting session that disappears, or whose account is removed, resolves too")
    func resolvedOnDisappearance() throws {
        let account = try Fixture.profile()
        let other = try Fixture.profile(.claude, path: "/tmp/.claude")
        let evaluator = AlertEvaluator(settings: AlertSettings())
        let waiting = try Fixture.session(.waiting, id: "gone", since: Fixture.now)
        let working = try Fixture.session(.working, id: "busy", since: Fixture.now)

        let vanished = evaluator.alerts(
            from: state(status(account, sessions: [waiting, working])),
            to: state(status(account, sessions: [working]))
        )
        #expect(vanished == [.sessionAttentionResolved(accountID: account.id, session: waiting)])

        let removed = evaluator.alerts(
            from: state(status(account, sessions: [waiting, working]), status(other)),
            to: state(status(other))
        )
        #expect(removed == [.sessionAttentionResolved(accountID: account.id, session: waiting)])
    }

    @Test("Resolved events can be turned off")
    func resolvedDisabled() throws {
        let account = try Fixture.profile()
        var settings = AlertSettings()
        settings.withdrawsResolvedAlerts = false
        let evaluator = AlertEvaluator(settings: settings)
        let waiting = try Fixture.session(.waiting, since: Fixture.now)
        #expect(evaluator.alerts(
            from: state(status(account, sessions: [waiting])),
            to: state(status(account, sessions: [try Fixture.session(.working, since: Fixture.now.addingTimeInterval(30))]))
        ).isEmpty)
        #expect(evaluator.alerts(from: state(status(account, sessions: [waiting])), to: state(status(account))).isEmpty)
    }

    // MARK: Group mutes

    @Test("Group mutes silence session or usage alerts of the group's accounts only")
    func groupMutes() throws {
        let quietSessions = try Fixture.group("Работа", mutesSessions: true)
        let quietUsage = try Fixture.group("Личное", mutesUsage: true)
        let work = try Fixture.profile(.claude, path: "/tmp/.claude-work", groupID: quietSessions.id)
        let personal = try Fixture.profile(.codex, path: "/tmp/.codex", groupID: quietUsage.id)
        let loose = try Fixture.profile(.claude, path: "/tmp/.claude")
        let settings = try AppSettings(accounts: [work, personal, loose], groups: [quietSessions, quietUsage])
        let evaluator = AlertEvaluator(appSettings: settings)
        #expect(evaluator.settings == settings.alerts)

        let low = try Fixture.reading([try Fixture.window("primary", used: 70)], at: Fixture.now)
        let high = try Fixture.reading([try Fixture.window("primary", used: 85)], at: Fixture.now.addingTimeInterval(60))
        let waiting = try Fixture.session(.waiting, id: "wait", since: Fixture.now)
        let working = try Fixture.session(.working, id: "work", since: Fixture.now)
        let before = [waiting, working]
        let after = [
            try Fixture.session(.working, id: "wait", since: Fixture.now.addingTimeInterval(60)),
            try Fixture.session(.waiting, id: "work", since: Fixture.now.addingTimeInterval(60)),
        ]

        let alerts = evaluator.alerts(
            from: state(status(work, low, sessions: before), status(personal, low, sessions: before), status(loose, low, sessions: before)),
            to: state(status(work, high, sessions: after), status(personal, high, sessions: after), status(loose, high, sessions: after))
        )

        func kinds(_ accountID: AccountID) -> [String] {
            alerts.filter { $0.accountID == accountID }.map { alert in
                switch alert {
                case .thresholdReached: "threshold"
                case .limitReset: "reset"
                case .sessionFinished: "finished"
                case .sessionNeedsAttention: "attention"
                case .sessionAttentionResolved: "resolved"
                }
            }
        }
        // Session mute: usage still alerts, resolved events still flow.
        #expect(kinds(work.id) == ["threshold", "resolved"])
        // Usage mute: session alerts still flow.
        #expect(kinds(personal.id) == ["resolved", "attention"])
        #expect(kinds(loose.id) == ["threshold", "resolved", "attention"])

        // Without groups nothing is muted.
        let unmuted = AlertEvaluator(settings: settings.alerts).alerts(
            from: state(status(work, low, sessions: before)),
            to: state(status(work, high, sessions: after))
        )
        #expect(unmuted.count == 3)
    }
}
