#if DEBUG
import CodometerCore
import CodometerUI
import Foundation

/// Ring visual steps: reset ceremonies and the finishing checkmark.
///
/// `{"reset": true}` drops every account's headline window to a few per cent and celebrates the reset, so the arc
/// unwinds, the glint rides it and the green ring flashes. `{"reset": {"account": 1}}` does it for one account only
/// (its index in the fixture, 0-based).
///
/// `{"finishTurn": true}` turns every working session idle, which seals the comet's circle and draws the check mark;
/// `{"finishTurn": {"account": 0, "activity": "working"}}` sets one account's sessions to a state instead, so a
/// scenario can start work, wait, and then finish it.
///
/// Both steps rewrite the installed fixture's state in memory and need a `fixture` step first: every image
/// used for review comes from synthetic data.
extension DebugScenario {
    static func handleVisualsStep(_ key: String, _ value: Any, _ context: DebugContext) async throws -> Bool {
        switch key {
        case "reset":
            try reset(value, context)
            return true
        case "finishTurn":
            try finishTurn(value, context)
            return true
        default:
            return false
        }
    }

    // MARK: Reset

    private static func reset(_ value: Any, _ context: DebugContext) throws {
        let fixture = try installedFixture(step: "reset", context)
        let selection = try accountSelection(value, step: "reset", keys: ["account"], fixture: fixture)
        let now = fixture.now
        var accounts = fixture.state.accounts
        var events: [WindowResetEvent] = []
        for index in selection {
            guard let reading = accounts[index].reading else { continue }
            let headline = HeadlineWindows(reading: reading)
            let window = headline.primary
            guard let fresh = try? freshWindow(window, now: now) else { continue }
            let bucket = headline.bucket
            guard
                let newBucket = try? LimitBucket(
                    id: bucket.id,
                    title: bucket.title,
                    windows: bucket.windows.map { $0.id == window.id ? fresh : $0 },
                    isLimitReached: false
                ),
                let newReading = try? UsageReading(
                    capturedAt: now,
                    source: reading.source,
                    buckets: reading.buckets.map { $0.id == bucket.id ? newBucket : $0 },
                    credits: reading.credits
                ),
                let event = try? WindowResetEvent(
                    accountID: accounts[index].id,
                    bucketID: bucket.id,
                    windowID: window.id,
                    previousUsed: window.used,
                    newUsed: fresh.used,
                    detectedAt: now
                )
            else { continue }
            accounts[index].reading = newReading
            events.append(event)
        }
        guard !events.isEmpty else {
            throw DebugScenarioError(description: "reset: no account has a headline window to reset")
        }
        install(fixture, accounts: accounts, resets: events, context)
        context.log(["action": "reset", "accounts": events.count])
    }

    /// The same window at the start of a new period: a few per cent used and a reset one full window away.
    private static func freshWindow(_ window: LimitWindow, now: Date) throws(ValidationError) -> LimitWindow {
        try LimitWindow(
            id: window.id,
            scope: window.scope,
            used: try Percentage(validating: Self.usageAfterReset),
            duration: window.duration,
            resetsAt: window.duration.map { now.addingTimeInterval($0.timeInterval) } ?? window.resetsAt,
            label: window.label
        )
    }

    /// What a window shows right after a reset: not zero, so the arc has somewhere to land.
    private static let usageAfterReset = 3.0

    // MARK: Finishing turn

    private static func finishTurn(_ value: Any, _ context: DebugContext) throws {
        let fixture = try installedFixture(step: "finishTurn", context)
        let selection = try accountSelection(value, step: "finishTurn", keys: ["account", "activity"], fixture: fixture)
        var activity = AgentActivity.idle
        if let object = DebugValue.object(value), let raw = object["activity"] {
            guard let name = DebugValue.string(raw), let parsed = AgentActivity(rawValue: name) else {
                throw DebugScenarioError(description: "finishTurn: activity must be one of \(AgentActivity.allCases.map(\.rawValue))")
            }
            activity = parsed
        }
        let now = fixture.now
        var accounts = fixture.state.accounts
        var changed = 0
        for index in selection {
            let sessions = accounts[index].sessions.map { session -> AgentSession in
                guard session.activity != activity else { return session }
                changed += 1
                return (try? AgentSession(
                    id: session.id,
                    title: session.title,
                    projectPath: session.projectPath,
                    activity: activity,
                    detail: activity == .waiting ? session.detail : nil,
                    activitySince: now,
                    processID: session.processID,
                    origin: session.origin,
                    model: session.model,
                    lastTurn: session.lastTurn,
                    lastEventAt: now
                )) ?? session
            }
            accounts[index].sessions = sessions
        }
        install(fixture, accounts: accounts, resets: [], context)
        context.log(["action": "finishTurn", "activity": activity.rawValue, "sessions": changed])
    }

    // MARK: Shared

    private static func installedFixture(step: String, _ context: DebugContext) throws -> DebugFixture {
        guard let fixture = context.controller.debugFixture else {
            throw DebugScenarioError(description: "\(step): needs a {\"fixture\": …} step first")
        }
        return fixture
    }

    /// `true` selects every account; `{"account": n}` selects one.
    private static func accountSelection(
        _ value: Any,
        step: String,
        keys: [String],
        fixture: DebugFixture
    ) throws -> [Int] {
        let all = Array(fixture.state.accounts.indices)
        if DebugValue.bool(value) == true { return all }
        guard let object = DebugValue.object(value), Set(object.keys).isSubset(of: Set(keys)) else {
            throw DebugScenarioError(description: "\(step): expected true or {\(keys.joined(separator: ", "))}")
        }
        guard let raw = object["account"] else { return all }
        guard let number = DebugValue.number(raw), let index = Int(exactly: number.rounded()), all.indices.contains(index) else {
            throw DebugScenarioError(description: "\(step): account must be an index in 0…\(max(0, all.count - 1))")
        }
        return [index]
    }

    /// Replaces the fixture's state in memory, keeping its name and clock.
    ///
    /// The settings come from the store, not from the fixture: `language` and `settings` steps that ran after the
    /// fixture was installed would otherwise be undone by every reset.
    private static func install(_ fixture: DebugFixture, accounts: [AccountStatus], resets: [WindowResetEvent], _ context: DebugContext) {
        context.controller.debugInstallFixture(DebugFixture(
            name: fixture.name,
            now: fixture.now,
            settings: context.store.settings,
            state: TrackerState(accounts: accounts),
            resets: resets
        ))
    }

    /// Fields this domain adds to `capture` and `trace` lines: what is still waiting to be celebrated on each
    /// surface, and what the accounts' agents are doing.
    static func visualsTraceFields(_ context: DebugContext) -> [String: Any] {
        var fields: [String: Any] = [:]
        let board = context.store.ceremonies
        let now = context.store.now
        let pending = CeremonySurface.allCases.compactMap { surface -> String? in
            let count = board.unplayed(on: surface, now: now).count
            return count > 0 ? "\(surface)=\(count)" : nil
        }
        if !pending.isEmpty {
            fields["ceremonies"] = pending.joined(separator: ",")
        }
        let activities = context.store.state.accounts.compactMap { $0.dominantActivity?.rawValue }
        if !activities.isEmpty {
            fields["activity"] = activities.joined(separator: ",")
        }
        return fields
    }
}
#endif
