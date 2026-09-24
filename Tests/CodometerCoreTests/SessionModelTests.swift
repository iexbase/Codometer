import CodometerCore
import Foundation
import Testing

@Suite("Turn timing")
struct TurnTimingTests {
    private let start = Fixture.now

    @Test("A valid turn keeps its values")
    func valid() throws {
        let turn = try TurnTiming(
            startedAt: start,
            endedAt: start.addingTimeInterval(252),
            duration: 252,
            firstTokenLatency: 2.8,
            wasAborted: false
        )
        #expect(turn.duration == 252)
        #expect(turn.firstTokenLatency == 2.8)
        #expect(!turn.wasAborted)
        let unknownLatency = try TurnTiming(startedAt: start, endedAt: start, duration: 0.5, firstTokenLatency: nil, wasAborted: true)
        #expect(unknownLatency.firstTokenLatency == nil)
        #expect(unknownLatency.wasAborted)
    }

    @Test("Duration must be positive, finite and shorter than a day")
    func duration() {
        let end = start.addingTimeInterval(10)
        #expect(throws: ValidationError.outOfRange(field: "turn.duration", value: 0, lowerBound: 0, upperBound: 86_400)) {
            try TurnTiming(startedAt: start, endedAt: end, duration: 0, firstTokenLatency: nil, wasAborted: false)
        }
        #expect(throws: ValidationError.self) {
            try TurnTiming(startedAt: start, endedAt: end, duration: -5, firstTokenLatency: nil, wasAborted: false)
        }
        #expect(throws: ValidationError.self) {
            try TurnTiming(startedAt: start, endedAt: end, duration: 86_400, firstTokenLatency: nil, wasAborted: false)
        }
        #expect(throws: ValidationError.notFinite(field: "turn.duration")) {
            try TurnTiming(startedAt: start, endedAt: end, duration: .nan, firstTokenLatency: nil, wasAborted: false)
        }
        #expect(throws: ValidationError.notFinite(field: "turn.duration")) {
            try TurnTiming(startedAt: start, endedAt: end, duration: .infinity, firstTokenLatency: nil, wasAborted: false)
        }
    }

    @Test("First-token latency lies within the turn; a turn cannot end before it starts")
    func latencyAndOrder() throws {
        let end = start.addingTimeInterval(10)
        #expect(throws: ValidationError.self) {
            try TurnTiming(startedAt: start, endedAt: end, duration: 10, firstTokenLatency: -0.1, wasAborted: false)
        }
        #expect(throws: ValidationError.self) {
            try TurnTiming(startedAt: start, endedAt: end, duration: 10, firstTokenLatency: 10.5, wasAborted: false)
        }
        #expect(throws: ValidationError.notFinite(field: "turn.firstTokenLatency")) {
            try TurnTiming(startedAt: start, endedAt: end, duration: 10, firstTokenLatency: .nan, wasAborted: false)
        }
        #expect(try TurnTiming(startedAt: start, endedAt: end, duration: 10, firstTokenLatency: 0, wasAborted: false).firstTokenLatency == 0)
        #expect(try TurnTiming(startedAt: start, endedAt: end, duration: 10, firstTokenLatency: 10, wasAborted: false).firstTokenLatency == 10)
        #expect(throws: ValidationError.self) {
            try TurnTiming(startedAt: end, endedAt: start, duration: 10, firstTokenLatency: nil, wasAborted: false)
        }
    }
}

@Suite("Token counts")
struct TokenCountsTests {
    @Test("Counts must not be negative")
    func validation() throws {
        #expect(throws: ValidationError.outOfRange(field: "tokens.output", value: -1, lowerBound: 0, upperBound: Double(Int64.max))) {
            try Fixture.tokens(output: -1)
        }
        #expect(throws: ValidationError.self) { try Fixture.tokens(input: -1) }
        #expect(throws: ValidationError.self) { try Fixture.tokens(cachedInput: -1) }
        #expect(throws: ValidationError.self) { try Fixture.tokens(cacheWrite: -1) }
        #expect(throws: ValidationError.self) { try Fixture.tokens(reasoningOutput: -1) }
        #expect(try Fixture.tokens() == .zero)
        #expect(TokenCounts.zero.isZero)
    }

    @Test("Addition is field by field and saturates instead of overflowing")
    func addition() throws {
        let lhs = try Fixture.tokens(input: 1, cachedInput: 2, cacheWrite: 3, output: 4, reasoningOutput: 5)
        let rhs = try Fixture.tokens(input: 10, cachedInput: 20, cacheWrite: 30, output: 40, reasoningOutput: 50)
        let expected = try Fixture.tokens(input: 11, cachedInput: 22, cacheWrite: 33, output: 44, reasoningOutput: 55)
        #expect(lhs + rhs == expected)
        #expect(lhs + .zero == lhs)

        let huge = try Fixture.tokens(input: .max, output: .max - 1)
        let small = try Fixture.tokens(input: 1, output: 5)
        let sum = huge + small
        #expect(sum.input == .max)
        #expect(sum.output == .max)

        // A negative value stored through the public setter never subtracts.
        var tampered = lhs
        tampered.input = -100
        #expect((tampered + rhs).input == 10)
    }

    @Test("Claude weights: input 1, cache write 1.25, cache read 0.1, output 5, reasoning not added")
    func claudeWeights() throws {
        #expect(try Fixture.tokens(input: 1_000).weighted(for: .claude) == 1_000)
        #expect(try Fixture.tokens(cacheWrite: 1_000).weighted(for: .claude) == 1_250)
        #expect(try Fixture.tokens(cachedInput: 1_000).weighted(for: .claude) == 100)
        #expect(try Fixture.tokens(output: 1_000).weighted(for: .claude) == 5_000)
        #expect(try Fixture.tokens(reasoningOutput: 1_000).weighted(for: .claude) == 0)
        let mixed = try Fixture.tokens(input: 100, cachedInput: 10_000, cacheWrite: 400, output: 200, reasoningOutput: 50)
        #expect(abs(mixed.weighted(for: .claude) - (100 + 1_000 + 500 + 1_000)) < 1e-9)
    }

    @Test("Codex weights: input 1, cache write 1, cache read 0.1, output 8, reasoning not added")
    func codexWeights() throws {
        #expect(try Fixture.tokens(input: 1_000).weighted(for: .codex) == 1_000)
        #expect(try Fixture.tokens(cacheWrite: 1_000).weighted(for: .codex) == 1_000)
        #expect(try Fixture.tokens(cachedInput: 1_000).weighted(for: .codex) == 100)
        #expect(try Fixture.tokens(output: 1_000).weighted(for: .codex) == 8_000)
        #expect(try Fixture.tokens(output: 1_000, reasoningOutput: 600).weighted(for: .codex) == 8_000)
        #expect(TokenCounts.zero.weighted(for: .codex) == 0)
    }
}

@Suite("Agent session additions")
struct AgentSessionAdditionsTests {
    @Test("New fields default so existing call sites keep working")
    func defaults() throws {
        let session = try AgentSession(
            id: "a",
            title: "t",
            projectPath: nil,
            activity: .idle,
            detail: nil,
            activitySince: Fixture.now,
            processID: nil
        )
        #expect(session.origin == .unknown)
        #expect(session.model == nil)
        #expect(session.lastTurn == nil)
        #expect(session.lastEventAt == nil)
    }

    @Test("The model name is sanitised and capped at 60 characters")
    func model() throws {
        let turn = try TurnTiming(startedAt: Fixture.now, endedAt: Fixture.now.addingTimeInterval(5), duration: 5, firstTokenLatency: 1, wasAborted: false)
        let session = try AgentSession(
            id: "a",
            title: nil,
            projectPath: "/tmp/Codometer",
            activity: .working,
            detail: nil,
            activitySince: Fixture.now,
            processID: 4,
            origin: .desktopApp,
            model: " gpt-5.5\n",
            lastTurn: turn,
            lastEventAt: Fixture.now
        )
        #expect(session.model == "gpt-5.5")
        #expect(session.origin == .desktopApp)
        #expect(session.lastTurn == turn)
        #expect(session.title == "Codometer")
        let long = try AgentSession(
            id: "b", title: nil, projectPath: nil, activity: .idle, detail: nil, activitySince: Fixture.now, processID: nil,
            model: String(repeating: "m", count: 100)
        )
        #expect(long.model?.count == 60)
        #expect(SessionOrigin.allCases == [.terminal, .desktopApp, .unknown])
        #expect(try JSONDecoder().decode(SessionOrigin.self, from: Data(#""desktopApp""#.utf8)) == .desktopApp)
    }
}

@Suite("Session health")
struct SessionHealthTests {
    private let now = Fixture.now

    @Test("Thresholds")
    func thresholds() {
        #expect(SessionHealth.quietAfter == 360)
        #expect(SessionHealth.longTurnAfter == 1_500)
        #expect(SessionHealth.waitingLongAfter == 600)
    }

    @Test("Idle sessions are always normal")
    func idle() throws {
        let session = try Fixture.session(.idle, since: now.addingTimeInterval(-86_400), lastEventAt: now.addingTimeInterval(-86_400))
        #expect(session.health(now: now) == .normal)
    }

    @Test("Waiting turns long at ten minutes")
    func waiting() throws {
        #expect(try Fixture.session(.waiting, since: now.addingTimeInterval(-599)).health(now: now) == .normal)
        #expect(try Fixture.session(.waiting, since: now.addingTimeInterval(-600)).health(now: now) == .waitingLong)
    }

    @Test("Working sessions: quiet after six silent minutes, long turn after 25 minutes")
    func working() throws {
        #expect(try Fixture.session(.working, since: now.addingTimeInterval(-60)).health(now: now) == .normal)
        #expect(try Fixture.session(.working, since: now.addingTimeInterval(-1_499)).health(now: now) == .normal)
        #expect(try Fixture.session(.working, since: now.addingTimeInterval(-1_500)).health(now: now) == .longTurn)

        let lastEvent = now.addingTimeInterval(-360)
        let quiet = try Fixture.session(.working, since: now.addingTimeInterval(-400), lastEventAt: lastEvent)
        #expect(quiet.health(now: now) == .quiet(since: lastEvent))
        let active = try Fixture.session(.working, since: now.addingTimeInterval(-400), lastEventAt: now.addingTimeInterval(-359))
        #expect(active.health(now: now) == .normal)
        // Silence is reported before a long turn.
        let quietAndLong = try Fixture.session(.working, since: now.addingTimeInterval(-3_600), lastEventAt: lastEvent)
        #expect(quietAndLong.health(now: now) == .quiet(since: lastEvent))
        // Recent activity during a long turn still reports the long turn.
        let busyAndLong = try Fixture.session(.working, since: now.addingTimeInterval(-3_600), lastEventAt: now)
        #expect(busyAndLong.health(now: now) == .longTurn)
    }
}

@Suite("Attention queue")
struct AttentionQueueTests {
    @Test("Waiting sessions of enabled accounts, longest wait first")
    func queue() throws {
        let work = try Fixture.profile(.claude, path: "/tmp/.claude-work", label: "Work")
        let personal = try Fixture.profile(.codex, path: "/tmp/.codex", label: "Personal")
        let disabled = try Fixture.profile(.codex, path: "/tmp/.codex-old", label: "Old", isEnabled: false)
        let state = TrackerState(accounts: [
            AccountStatus(profile: work, sessions: [
                try Fixture.session(.waiting, id: "w1", since: Fixture.now.addingTimeInterval(-30)),
                try Fixture.session(.working, id: "w2", since: Fixture.now.addingTimeInterval(-900)),
                try Fixture.session(.waiting, id: "w3", since: Fixture.now.addingTimeInterval(-300)),
            ]),
            AccountStatus(profile: personal, sessions: [
                try Fixture.session(.waiting, id: "p1", since: Fixture.now.addingTimeInterval(-120)),
                try Fixture.session(.waiting, id: "p2", since: Fixture.now.addingTimeInterval(-30)),
            ]),
            AccountStatus(profile: disabled, sessions: [
                try Fixture.session(.waiting, id: "d1", since: Fixture.now.addingTimeInterval(-9_000)),
            ]),
        ])
        let queue = state.attentionQueue
        #expect(queue.map(\.session.id) == ["w3", "p1", "w1", "p2"])
        #expect(queue.first?.accountID == work.id)
        #expect(queue.first?.id == "\(work.id)/w3")
        #expect(queue.first?.waitingSince == Fixture.now.addingTimeInterval(-300))
        #expect(TrackerState.empty.attentionQueue.isEmpty)
    }
}
