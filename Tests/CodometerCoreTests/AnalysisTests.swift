import CodometerCore
import Foundation
import Testing

private let now = Date(timeIntervalSince1970: 1_789_600_000)

private func window(
    _ id: String,
    _ scope: LimitWindowScope = .rolling,
    used: Double,
    minutes: Int? = 300,
    resetsIn seconds: TimeInterval? = 3_600
) throws -> LimitWindow {
    try LimitWindow(
        id: id,
        scope: scope,
        used: try Percentage(validating: used),
        duration: try minutes.map { try WindowDuration(minutes: $0) },
        resetsAt: seconds.map { now.addingTimeInterval($0) }
    )
}

private func reading(_ windows: [LimitWindow], bucket: String = "main", at date: Date = now) throws -> UsageReading {
    try UsageReading(
        capturedAt: date,
        source: .codexAppServer,
        buckets: [try LimitBucket(id: bucket, title: nil, windows: windows, isLimitReached: false)],
        credits: nil
    )
}

private func profile() throws -> AccountProfile {
    try AccountProfile(
        provider: .codex,
        label: try AccountLabel(validating: "Codex"),
        directory: try ProfileDirectory(validating: "/tmp/.codex")
    )
}

@Suite("Usage pace")
struct UsagePaceTests {
    @Test("Usage ahead of elapsed time projects exhaustion before the reset")
    func aheadProjectsExhaustion() throws {
        // 5 h window, 2.5 h elapsed (50 %), 80 % used.
        let pace = try #require(UsagePace(window: try window("w", used: 80, minutes: 300, resetsIn: 9_000), now: now))
        #expect(abs(pace.elapsedFraction - 0.5) < 0.0001)
        guard case .ahead(let points) = pace.verdict else {
            Issue.record("expected .ahead, got \(pace.verdict)")
            return
        }
        #expect(abs(points - 30) < 0.001)
        let exhaustion = try #require(pace.projectedExhaustion)
        // 80 % in 9000 s → remaining 20 % takes 2250 s.
        #expect(abs(exhaustion.timeIntervalSince(now) - 2_250) < 1)
    }

    @Test("Usage behind elapsed time leaves headroom")
    func behind() throws {
        let pace = try #require(UsagePace(window: try window("w", used: 10, minutes: 300, resetsIn: 3_600), now: now))
        guard case .behind = pace.verdict else {
            Issue.record("expected .behind, got \(pace.verdict)")
            return
        }
        #expect(pace.projectedExhaustion == nil)
    }

    @Test("No pace without a duration or once the reset has passed")
    func unavailable() throws {
        #expect(UsagePace(window: try window("w", used: 50, minutes: nil), now: now) == nil)
        #expect(UsagePace(window: try window("w", used: 50, resetsIn: -10), now: now) == nil)
        #expect(UsagePace(window: try window("w", used: 50, resetsIn: nil), now: now) == nil)
    }

    @Test("A reset further away than one window is clamped to the start of the window")
    func clockSkewClamped() throws {
        let pace = try #require(UsagePace(window: try window("w", used: 0, minutes: 60, resetsIn: 7_200), now: now))
        #expect(pace.elapsedFraction == 0)
    }
}

@Suite("Headline windows")
struct HeadlineWindowsTests {
    @Test("Claude: session is primary, all-models week is secondary")
    func claude() throws {
        let headline = HeadlineWindows(reading: try reading([
            try window("week.fable", .weekly(model: "Fable"), used: 61, minutes: 10_080),
            try window("week", .weekly(model: nil), used: 33, minutes: 10_080),
            try window("session", .session, used: 50, minutes: 300),
        ]))
        #expect(headline.primary.id == "session")
        #expect(headline.secondary?.id == "week")
    }

    @Test("Codex weekly-only bucket has no secondary window")
    func weeklyOnly() throws {
        let headline = HeadlineWindows(reading: try reading([try window("primary", used: 99, minutes: 10_080)]))
        #expect(headline.primary.id == "primary")
        #expect(headline.secondary == nil)
    }

    @Test("Without a session window the shortest window leads")
    func shortestLeads() throws {
        let headline = HeadlineWindows(reading: try reading([
            try window("secondary", used: 20, minutes: 10_080),
            try window("primary", used: 5, minutes: 300),
        ]))
        #expect(headline.primary.id == "primary")
        #expect(headline.secondary?.id == "secondary")
    }
}

@Suite("Alert evaluation")
struct AlertEvaluatorTests {
    private func state(_ profile: AccountProfile, _ reading: UsageReading?, sessions: [AgentSession] = []) -> TrackerState {
        TrackerState(accounts: [AccountStatus(profile: profile, reading: reading, sessions: sessions)])
    }

    private func session(_ activity: AgentActivity, id: String = "s1", since: Date = now) throws -> AgentSession {
        try AgentSession(
            id: id,
            title: "project",
            projectPath: "/tmp/project",
            activity: activity,
            detail: nil,
            activitySince: since,
            processID: nil
        )
    }

    @Test("Crossing thresholds raises one alert for the highest threshold")
    func thresholdCrossing() throws {
        let account = try profile()
        let before = state(account, try reading([try window("primary", used: 70)], at: now))
        let after = state(account, try reading([try window("primary", used: 100)], at: now.addingTimeInterval(60)))
        let alerts = AlertEvaluator(settings: AlertSettings()).alerts(from: before, to: after)
        #expect(alerts.count == 1)
        guard case .thresholdReached(let context, let threshold) = alerts.first else {
            Issue.record("expected a threshold alert, got \(alerts)")
            return
        }
        #expect(threshold.value == 100)
        #expect(context.window.id == "primary")
    }

    @Test("The first reading of an account never alerts")
    func firstReadingIsSilent() throws {
        let account = try profile()
        let before = state(account, nil)
        let after = state(account, try reading([try window("primary", used: 100)]))
        #expect(AlertEvaluator(settings: AlertSettings()).alerts(from: before, to: after).isEmpty)
    }

    @Test("A later reset time means the window was reset")
    func resetByResetTime() throws {
        let account = try profile()
        let before = state(account, try reading([try window("primary", used: 90, resetsIn: 60)], at: now))
        let after = state(account, try reading([try window("primary", used: 2, resetsIn: 18_000)], at: now.addingTimeInterval(120)))
        let alerts = AlertEvaluator(settings: AlertSettings()).alerts(from: before, to: after)
        guard case .limitReset = alerts.first else {
            Issue.record("expected a reset alert, got \(alerts)")
            return
        }
        var quiet = AlertSettings()
        quiet.notifiesOnReset = false
        #expect(AlertEvaluator(settings: quiet).alerts(from: before, to: after).isEmpty)
    }

    @Test("Minute-level differences in reset time are not resets")
    func resetTolerance() throws {
        let account = try profile()
        let before = state(account, try reading([try window("primary", used: 40, resetsIn: 3_600)], at: now))
        let after = state(account, try reading([try window("primary", used: 41, resetsIn: 3_660)], at: now.addingTimeInterval(30)))
        #expect(AlertEvaluator(settings: AlertSettings()).alerts(from: before, to: after).isEmpty)
    }

    @Test("Session transitions: working → idle finishes, anything → waiting needs attention")
    func sessionTransitions() throws {
        let account = try profile()
        let evaluator = AlertEvaluator(settings: AlertSettings())
        let finished = evaluator.alerts(
            from: state(account, nil, sessions: [try session(.working)]),
            // A two-minute turn is longer than the default 20 s minimum for "finished" alerts.
            to: state(account, nil, sessions: [try session(.idle, since: now.addingTimeInterval(120))])
        )
        guard case .sessionFinished = finished.first else {
            Issue.record("expected sessionFinished, got \(finished)")
            return
        }
        let waiting = evaluator.alerts(
            from: state(account, nil, sessions: [try session(.working)]),
            to: state(account, nil, sessions: [try session(.waiting)])
        )
        guard case .sessionNeedsAttention = waiting.first else {
            Issue.record("expected sessionNeedsAttention, got \(waiting)")
            return
        }
        let brandNew = evaluator.alerts(
            from: state(account, nil),
            to: state(account, nil, sessions: [try session(.waiting, id: "new")])
        )
        #expect(brandNew.isEmpty)
    }
}
