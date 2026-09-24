#if DEBUG
import CodometerCore
import Foundation

/// A named set of synthetic data for the debug harness's `{"fixture": "<name>"}` step.
enum DebugFixtureName: String, CaseIterable, Sendable {
    /// One Claude account.
    case single
    /// One Claude and one Codex account.
    case standard
    /// Three accounts, two of them Claude with their own tints and monograms, a waiting and a working session.
    case multi
    /// One exhausted window and one window that just reset.
    case limits
    /// No accounts.
    case empty
}

/// Synthetic state, accounts and analytics that replace the real ones in memory, so captures used for review, docs and
/// screenshots never show a real account, e-mail, project or path.
///
/// Everything derives from `now`, which is fixed, so the same fixture is always the same data.
struct DebugFixture: Sendable {
    let name: DebugFixtureName
    let now: Date
    let settings: AppSettings
    let state: TrackerState
    /// Resets to celebrate right after installing (the `limits` fixture's just-reset window).
    let resets: [WindowResetEvent]

    /// A plausible usage curve for a window since `since`: calm first, then a burst, ending at the window's usage.
    func windowHistory(accountID: AccountID, bucketID: String, windowID: String, since: Date) -> HistorySeries {
        let final = state.account(accountID)?.reading?.bucket(id: bucketID)?.window(id: windowID)?.used.value ?? 0
        let start = min(since, now)
        let span = now.timeIntervalSince(start)
        let points = (0...24).compactMap { step -> UsagePoint? in
            let progress = Double(step) / 24
            let shaped = pow(progress, 1.8) * 0.85 + progress * 0.15
            return try? UsagePoint(at: start.addingTimeInterval(span * progress), used: final * shaped)
        }
        return HistorySeries(accountID: accountID, bucketID: bucketID, windowID: windowID, points: points, resets: [])
    }

    /// Sessions over the interval's length, ending at the fixture's `now`, with one stretch the Mac slept when the
    /// interval is a day or longer.
    func timeline(accountID: AccountID, interval: DateInterval) -> TimelineSnapshot {
        let range = DateInterval(start: now.addingTimeInterval(-interval.duration), end: now)
        guard let account = state.account(accountID) else {
            return TimelineSnapshot(accountID: accountID, interval: range, segments: [], usage: nil, coverageStart: range.start)
        }
        let projects = DebugFixtures.projects(for: account)
        let sleep = range.duration >= 86_400
            ? DateInterval(start: now.addingTimeInterval(-9 * 3_600), end: now.addingTimeInterval(-7 * 3_600))
            : nil
        var segments: [SessionSegment] = []
        let slots = 12
        for slot in 0..<slots {
            let start = range.start.addingTimeInterval(range.duration * (Double(slot) + 0.15) / Double(slots))
            let length = range.duration / Double(slots) * (slot.isMultiple(of: 3) ? 0.55 : 0.3)
            let end = start.addingTimeInterval(length)
            if let sleep, sleep.intersects(DateInterval(start: start, end: end)) { continue }
            let project = projects[slot % projects.count]
            let activity: AgentActivity = slot.isMultiple(of: 4) ? .waiting : .working
            if let segment = try? SessionSegment(
                accountID: accountID,
                sessionID: DebugFixtures.sessionID(slot % projects.count),
                title: nil,
                project: project,
                activity: activity,
                start: start,
                end: slot == slots - 1 ? nil : end
            ) {
                segments.append(segment)
            }
        }
        let usage = account.reading.map { reading in
            let headline = HeadlineWindows(reading: reading)
            return windowHistory(accountID: accountID, bucketID: headline.bucket.id, windowID: headline.primary.id, since: range.start)
        }
        return TimelineSnapshot(
            accountID: accountID,
            interval: range,
            segments: segments,
            usage: usage,
            coverageStart: range.start,
            gaps: sleep.map { [CollectionGap(interval: $0, reason: .macAsleep)] } ?? []
        )
    }

    /// Token usage split across the account's synthetic projects.
    func attribution(accountID: AccountID, interval: DateInterval, grouping: AttributionGrouping) -> AttributionReport? {
        guard let account = state.account(accountID), let reading = account.reading else { return nil }
        let range = DateInterval(start: now.addingTimeInterval(-interval.duration), end: now)
        let projects = DebugFixtures.projects(for: account)
        let weights: [Int64] = [620_000, 310_000, 140_000, 60_000]
        var samples: [TokenSample] = []
        for (index, project) in projects.enumerated() {
            for step in 0..<6 {
                // The first samples sit at the start, so the interval reads as fully covered.
                let at = range.start.addingTimeInterval(range.duration * Double(step) / 6)
                guard
                    let counts = try? TokenCounts(input: weights[index % weights.count] / 6, cachedInput: 0, cacheWrite: 0, output: weights[index % weights.count] / 40, reasoningOutput: 0),
                    let sample = try? TokenSample(accountID: accountID, sessionID: DebugFixtures.sessionID(index), project: project, model: nil, at: at, delta: counts)
                else { continue }
                samples.append(sample)
            }
        }
        let headline = HeadlineWindows(reading: reading)
        let usage = windowHistory(accountID: accountID, bucketID: headline.bucket.id, windowID: headline.primary.id, since: range.start)
        return UsageAttribution.report(
            samples: samples,
            provider: account.profile.provider,
            usage: usage,
            interval: range,
            grouping: grouping,
            reference: headline.primary
        )
    }
}

/// Builds the fixtures. Labels are "Work", "Personal" and "Side project"; e-mails are `name@example.com`; profile folders
/// and projects are made up.
enum DebugFixtures {
    /// Thursday, 17 September 2026, 11:32 UTC.
    static let referenceNow = Date(timeIntervalSince1970: 1_789_644_720)

    /// A fixture built on `base`: its appearance, alerts and general settings (language included) stay; accounts and
    /// groups are replaced.
    static func make(_ name: DebugFixtureName, base: AppSettings = .empty, now: Date = referenceNow) throws(ValidationError) -> DebugFixture {
        let builder = Builder(now: now)
        let accounts: [AccountStatus]
        var resets: [WindowResetEvent] = []
        switch name {
        case .single:
            accounts = [try builder.work(tint: .automatic, monogram: nil, sessions: [])]
        case .standard:
            accounts = [
                try builder.work(tint: .automatic, monogram: nil, sessions: [try builder.workingSession()]),
                try builder.sideProject(),
            ]
        case .multi:
            accounts = [
                try builder.work(tint: .teal, monogram: try AccountMonogram(validating: "W"), sessions: [
                    try builder.waitingSession(),
                    try builder.workingSession(),
                ]),
                try builder.personal(),
                try builder.sideProject(),
            ]
        case .limits:
            let (side, reset) = try builder.justResetSideProject()
            accounts = [try builder.exhaustedWork(), side]
            resets = [reset]
        case .empty:
            accounts = []
        }
        let settings = try AppSettings(
            accounts: accounts.map(\.profile),
            groups: [],
            appearance: base.appearance,
            alerts: base.alerts,
            general: base.general
        )
        return DebugFixture(name: name, now: now, settings: settings, state: TrackerState(accounts: accounts), resets: resets)
    }

    /// A session id shaped like the CLIs' own (hex), one per synthetic project.
    static func sessionID(_ index: Int) -> String {
        String(format: "5e3d%04lx-a1c2-4b7e-9f10-%012lx", index, 0x3F9A1C + index * 0x1B2D)
    }

    /// Project folder names the timeline and attribution use for an account.
    static func projects(for account: AccountStatus) -> [String] {
        switch account.profile.provider {
        case .claude: ["checkout-web", "api-gateway", "design-tokens"]
        case .codex: ["mobile-app", "data-pipeline"]
        }
    }

    private struct Builder {
        let now: Date

        private func id(_ number: Int) -> AccountID {
            AccountID(rawValue: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012ld", number)) ?? UUID())
        }

        private func window(
            _ id: String,
            _ scope: LimitWindowScope,
            used: Double,
            duration: WindowDuration,
            resetsIn seconds: TimeInterval
        ) throws(ValidationError) -> LimitWindow {
            try LimitWindow(id: id, scope: scope, used: try Percentage(validating: used), duration: duration, resetsAt: now.addingTimeInterval(seconds))
        }

        private func profile(
            _ number: Int,
            provider: ProviderKind,
            label: String,
            folder: String,
            tint: AccountTint = .automatic,
            monogram: AccountMonogram? = nil
        ) throws(ValidationError) -> AccountProfile {
            try AccountProfile(
                id: id(number),
                provider: provider,
                label: try AccountLabel(validating: label),
                directory: try ProfileDirectory(validating: "/Users/example/\(folder)"),
                tint: tint,
                monogram: monogram
            )
        }

        private func claudeReading(session: Double, week: Double, model: Double, limitReached: Bool = false) throws(ValidationError) -> UsageReading {
            try UsageReading(
                capturedAt: now.addingTimeInterval(-60),
                source: .claudeUsageCommand,
                buckets: [try LimitBucket(id: "claude", title: nil, windows: [
                    try window("session", .session, used: session, duration: .fiveHours, resetsIn: 2 * 3_600 + 14 * 60),
                    try window("week", .weekly(model: nil), used: week, duration: .oneWeek, resetsIn: limitReached ? 30 * 3_600 : 4 * 86_400 + 3 * 3_600),
                    try window("week.opus", .weekly(model: "Opus"), used: model, duration: .oneWeek, resetsIn: 4 * 86_400 + 3 * 3_600),
                ], isLimitReached: limitReached)],
                credits: nil
            )
        }

        func work(tint: AccountTint, monogram: AccountMonogram?, sessions: [AgentSession]) throws(ValidationError) -> AccountStatus {
            AccountStatus(
                profile: try profile(1, provider: .claude, label: "Work", folder: ".claude", tint: tint, monogram: monogram),
                identity: AccountIdentity(email: "work@example.com", organization: nil, plan: "Max 20x"),
                reading: try claudeReading(session: 42, week: 38, model: 63),
                nextRefreshAt: now.addingTimeInterval(150),
                sessions: sessions
            )
        }

        func exhaustedWork() throws(ValidationError) -> AccountStatus {
            AccountStatus(
                profile: try profile(1, provider: .claude, label: "Work", folder: ".claude"),
                identity: AccountIdentity(email: "work@example.com", organization: nil, plan: "Max 20x"),
                reading: try claudeReading(session: 18, week: 100, model: 71, limitReached: true),
                nextRefreshAt: now.addingTimeInterval(150)
            )
        }

        func personal() throws(ValidationError) -> AccountStatus {
            AccountStatus(
                profile: try profile(2, provider: .claude, label: "Personal", folder: ".claude-personal", tint: .pink, monogram: try AccountMonogram(validating: "P")),
                identity: AccountIdentity(email: "personal@example.com", organization: nil, plan: "Pro"),
                reading: try claudeReading(session: 12, week: 21, model: 9),
                nextRefreshAt: now.addingTimeInterval(240)
            )
        }

        private func codexReading(primary: Double, primaryResetsIn: TimeInterval, secondary: Double) throws(ValidationError) -> UsageReading {
            try UsageReading(
                capturedAt: now.addingTimeInterval(-30),
                source: .codexAppServer,
                buckets: [try LimitBucket(id: "codex", title: nil, windows: [
                    try window("primary", .rolling, used: primary, duration: .fiveHours, resetsIn: primaryResetsIn),
                    try window("secondary", .rolling, used: secondary, duration: .oneWeek, resetsIn: 2 * 86_400 + 12 * 3_600),
                ], isLimitReached: false)],
                credits: nil
            )
        }

        func sideProject() throws(ValidationError) -> AccountStatus {
            AccountStatus(
                profile: try profile(3, provider: .codex, label: "Side project", folder: ".codex"),
                identity: AccountIdentity(email: "side@example.com", organization: nil, plan: "Plus"),
                reading: try codexReading(primary: 34, primaryResetsIn: 2 * 3_600 + 5 * 60, secondary: 57),
                nextRefreshAt: now.addingTimeInterval(120)
            )
        }

        /// The Codex account's 5-hour window reset 90 seconds ago, from 91% to 3%.
        func justResetSideProject() throws(ValidationError) -> (AccountStatus, WindowResetEvent) {
            let account = AccountStatus(
                profile: try profile(3, provider: .codex, label: "Side project", folder: ".codex"),
                identity: AccountIdentity(email: "side@example.com", organization: nil, plan: "Plus"),
                reading: try codexReading(primary: 3, primaryResetsIn: 4 * 3_600 + 58 * 60, secondary: 57),
                nextRefreshAt: now.addingTimeInterval(120)
            )
            let reset = try WindowResetEvent(
                accountID: account.id,
                bucketID: "codex",
                windowID: "primary",
                previousUsed: try Percentage(validating: 91),
                newUsed: try Percentage(validating: 3),
                detectedAt: now.addingTimeInterval(-90)
            )
            return (account, reset)
        }

        func workingSession() throws(ValidationError) -> AgentSession {
            let turn = try TurnTiming(
                startedAt: now.addingTimeInterval(-900),
                endedAt: now.addingTimeInterval(-648),
                duration: 252,
                firstTokenLatency: 2.8,
                wasAborted: false
            )
            return try AgentSession(
                id: DebugFixtures.sessionID(7),
                title: nil,
                projectPath: "/Users/example/checkout-web",
                activity: .working,
                detail: nil,
                activitySince: now.addingTimeInterval(-420),
                processID: nil,
                origin: .terminal,
                model: "claude-opus",
                lastTurn: turn,
                lastEventAt: now.addingTimeInterval(-20)
            )
        }

        func waitingSession() throws(ValidationError) -> AgentSession {
            try AgentSession(
                id: DebugFixtures.sessionID(8),
                title: nil,
                projectPath: "/Users/example/api-gateway",
                activity: .waiting,
                detail: "permission prompt",
                activitySince: now.addingTimeInterval(-65),
                processID: nil,
                origin: .terminal
            )
        }
    }
}
#endif
