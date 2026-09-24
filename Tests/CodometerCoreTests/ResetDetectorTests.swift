import CodometerCore
import Foundation
import Testing

@Suite("Reset detector")
struct ResetDetectorTests {
    private func status(_ profile: AccountProfile, _ reading: UsageReading?) -> AccountStatus {
        AccountStatus(profile: profile, reading: reading)
    }

    private func state(_ accounts: AccountStatus...) -> TrackerState {
        TrackerState(accounts: accounts)
    }

    private let later = Fixture.now.addingTimeInterval(60)

    @Test("A reset moved by more than 30 minutes with a real drop is a ceremony")
    func shiftWithDrop() throws {
        let profile = try Fixture.profile()
        let before = state(status(profile, try Fixture.reading([try Fixture.window("primary", used: 64, resetsIn: 600)])))
        let after = state(status(profile, try Fixture.reading([try Fixture.window("primary", used: 3, resetsIn: 600 + 5 * 3_600)], at: later)))
        let events = ResetDetector.resets(from: before, to: after, at: later)
        #expect(events.count == 1)
        let event = try #require(events.first)
        #expect(event.accountID == profile.id)
        #expect(event.bucketID == "main" && event.windowID == "primary")
        #expect(event.previousUsed.value == 64 && event.newUsed.value == 3)
        #expect(event.detectedAt == later)
        #expect(event.id == "\(profile.id)/main/primary/\(Int(later.timeIntervalSince1970))")
    }

    @Test("Without reset times, a drop of 20 points is a reset")
    func dropWithoutResetTimes() throws {
        let profile = try Fixture.profile()
        let before = state(status(profile, try Fixture.reading([try Fixture.window("primary", used: 45, resetsIn: nil)])))
        let dropped = state(status(profile, try Fixture.reading([try Fixture.window("primary", used: 25, resetsIn: nil)], at: later)))
        let small = state(status(profile, try Fixture.reading([try Fixture.window("primary", used: 26, resetsIn: nil)], at: later)))
        #expect(ResetDetector.resets(from: before, to: dropped, at: later).count == 1)
        #expect(ResetDetector.resets(from: before, to: small, at: later).isEmpty)
    }

    @Test("No ceremony: jitter without a drop, nearly unused windows, stale readings, new or removed accounts")
    func negatives() throws {
        let profile = try Fixture.profile()
        let other = try Fixture.profile(.claude, path: "/tmp/.claude", label: "Claude")
        let base = try Fixture.reading([try Fixture.window("primary", used: 40, resetsIn: 600)])
        let before = state(status(profile, base))

        let jitter = state(status(profile, try Fixture.reading([try Fixture.window("primary", used: 40, resetsIn: 600 + 3_600)], at: later)))
        #expect(ResetDetector.resets(from: before, to: jitter, at: later).isEmpty)
        let smallDrop = state(status(profile, try Fixture.reading([try Fixture.window("primary", used: 36, resetsIn: 600 + 3_600)], at: later)))
        #expect(ResetDetector.resets(from: before, to: smallDrop, at: later).isEmpty)

        let barelyUsed = state(status(profile, try Fixture.reading([try Fixture.window("primary", used: 4.9, resetsIn: 600)])))
        let fromBarely = state(status(profile, try Fixture.reading([try Fixture.window("primary", used: 0, resetsIn: 600 + 3_600)], at: later)))
        #expect(ResetDetector.resets(from: barelyUsed, to: fromBarely, at: later).isEmpty)

        let reset = try Fixture.reading([try Fixture.window("primary", used: 0, resetsIn: 600 + 3_600)], at: Fixture.now)
        #expect(ResetDetector.resets(from: before, to: state(status(profile, reset)), at: later).isEmpty)

        let newAccount = state(status(profile, base), status(other, reset))
        #expect(ResetDetector.resets(from: before, to: newAccount, at: later).isEmpty)
        #expect(ResetDetector.resets(from: newAccount, to: state(), at: later).isEmpty)
        #expect(ResetDetector.resets(from: before, to: state(status(profile, nil)), at: later).isEmpty)
        let windowAppeared = state(status(profile, try Fixture.reading([
            try Fixture.window("primary", used: 40, resetsIn: 600),
            try Fixture.window("secondary", used: 1, resetsIn: 90_000),
        ], at: later)))
        #expect(ResetDetector.resets(from: before, to: windowAppeared, at: later).isEmpty)
    }

    @Test("Independent of alert settings and group mutes")
    func independence() throws {
        let group = try Fixture.group("Muted", mutesSessions: true, mutesUsage: true)
        let profile = try Fixture.profile(groupID: group.id)
        let before = state(status(profile, try Fixture.reading([try Fixture.window("primary", used: 80, resetsIn: 600)])))
        let after = state(status(profile, try Fixture.reading([try Fixture.window("primary", used: 0, resetsIn: 600 + 5 * 3_600)], at: later)))
        var settings = try AppSettings(accounts: [profile], groups: [group])
        settings.alerts.notifiesOnReset = false
        #expect(AlertEvaluator(appSettings: settings).alerts(from: before, to: after).isEmpty)
        #expect(ResetDetector.resets(from: before, to: after, at: later).count == 1)
    }

    @Test("Every bucket and window that reset is reported")
    func severalWindows() throws {
        let profile = try Fixture.profile()
        let before = state(status(profile, try Fixture.reading([
            try Fixture.bucket("main", [
                try Fixture.window("primary", used: 70, resetsIn: 600),
                try Fixture.window("secondary", used: 50, resetsIn: 86_400),
            ]),
            try Fixture.bucket("model", [try Fixture.window("weekly", used: 30, resetsIn: 600)]),
        ])))
        let after = state(status(profile, try Fixture.reading([
            try Fixture.bucket("main", [
                try Fixture.window("primary", used: 2, resetsIn: 600 + 5 * 3_600),
                try Fixture.window("secondary", used: 51, resetsIn: 86_400),
            ]),
            try Fixture.bucket("model", [try Fixture.window("weekly", used: 0, resetsIn: 600 + 7 * 86_400)]),
        ], at: later)))
        let events = ResetDetector.resets(from: before, to: after, at: later)
        #expect(events.map { "\($0.bucketID)/\($0.windowID)" } == ["main/primary", "model/weekly"])
    }

    @Test("The rule shared with notifications")
    func sharedRule() throws {
        let old = try Fixture.window("primary", used: 30, resetsIn: 600)
        #expect(ResetDetector.isReset(from: old, to: try Fixture.window("primary", used: 30, resetsIn: 600 + 1_801)))
        #expect(!ResetDetector.isReset(from: old, to: try Fixture.window("primary", used: 0, resetsIn: 600 + 1_800)))
        #expect(AlertEvaluator.resetShiftTolerance == ResetDetector.resetShiftTolerance)
        #expect(AlertEvaluator.resetDropPoints == ResetDetector.resetDropPoints)
        #expect(throws: ValidationError.self) {
            try WindowResetEvent(accountID: AccountID(), bucketID: "bad id", windowID: "w", previousUsed: .full, newUsed: .zero, detectedAt: Fixture.now)
        }
    }
}
