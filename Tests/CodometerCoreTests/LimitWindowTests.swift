import CodometerCore
import Foundation
import Testing

@Suite("Limit window labels")
struct LimitWindowLabelTests {
    @Test("Labels are sanitised, capped at 60 characters and default to nil")
    func sanitised() throws {
        #expect(try Fixture.window("w", used: 1).label == nil)
        #expect(try Fixture.window("w", used: 1, label: "  Current week (Opus)\n").label == "Current week (Opus)")
        #expect(try Fixture.window("w", used: 1, label: "\u{0007}  ").label == nil)
        let long = try Fixture.window("w", used: 1, label: String(repeating: "x", count: 80))
        #expect(long.label?.count == 60)
        #expect(long.label?.hasSuffix("…") == true)
    }

    @Test("Labels round-trip through JSON, and windows stored without one still decode")
    func codable() throws {
        let labelled = try Fixture.window("limit.opus", .rolling, used: 42, label: "Opus")
        let decoded = try JSONDecoder().decode(LimitWindow.self, from: try JSONEncoder().encode(labelled))
        #expect(decoded == labelled)
        #expect(decoded.label == "Opus")

        let legacy = Data(#"{"id":"session","scope":{"session":{}},"used":12.5,"duration":300}"#.utf8)
        let old = try JSONDecoder().decode(LimitWindow.self, from: legacy)
        #expect(old.label == nil)
        #expect(old.scope == .session)

        let unlabelled = try JSONEncoder().encode(try Fixture.window("w", used: 1))
        let object = try #require(try JSONSerialization.jsonObject(with: unlabelled) as? [String: Any])
        #expect(object["label"] == nil)
    }
}

@Suite("Headline window additions")
struct HeadlineAdditionsTests {
    private func claudeReading(fable: Double = 63, sonnet: Double = 12, week: Double = 38, session: Double = 20) throws -> UsageReading {
        try Fixture.reading([
            try Fixture.window("limit.extra", .rolling, used: 5, minutes: nil, label: "Extra"),
            try Fixture.window("week.sonnet", .weekly(model: "Sonnet"), used: sonnet, minutes: 10_080),
            try Fixture.window("week", .weekly(model: nil), used: week, minutes: 10_080),
            try Fixture.window("week.fable", .weekly(model: "Fable"), used: fable, minutes: 10_080),
            try Fixture.window("session", .session, used: session, minutes: 300),
        ])
    }

    @Test("The most used model-scoped weekly window is surfaced")
    func modelWeekly() throws {
        let headline = HeadlineWindows(reading: try claudeReading())
        #expect(headline.modelWeekly?.id == "week.fable")
        #expect(HeadlineWindows(reading: try claudeReading(fable: 10, sonnet: 70)).modelWeekly?.id == "week.sonnet")
        // Equal usage keeps the provider's order.
        #expect(HeadlineWindows(reading: try claudeReading(fable: 30, sonnet: 30)).modelWeekly?.id == "week.sonnet")
        let codex = HeadlineWindows(reading: try Fixture.reading([try Fixture.window("primary", used: 90)]))
        #expect(codex.modelWeekly == nil)
    }

    @Test("The binding window is the most used one; ties go to the shorter window")
    func binding() throws {
        #expect(HeadlineWindows(reading: try claudeReading()).binding.id == "week.fable")
        let tied = HeadlineWindows(reading: try Fixture.reading([
            try Fixture.window("week", .weekly(model: nil), used: 50, minutes: 10_080),
            try Fixture.window("session", .session, used: 50, minutes: 300),
        ]))
        #expect(tied.binding.id == "session")
        let unknownDuration = HeadlineWindows(reading: try Fixture.reading([
            try Fixture.window("a", used: 50, minutes: nil),
            try Fixture.window("b", used: 50, minutes: 10_080),
        ]))
        #expect(unknownDuration.binding.id == "b")
        let allEqual = HeadlineWindows(reading: try Fixture.reading([
            try Fixture.window("a", used: 50, minutes: 300),
            try Fixture.window("b", used: 50, minutes: 300),
        ]))
        #expect(allEqual.binding.id == "a")
    }

    @Test("Blocked when any window is exhausted or the bucket reports its limit")
    func blocked() throws {
        #expect(!HeadlineWindows(reading: try claudeReading()).isBlocked)
        #expect(HeadlineWindows(reading: try claudeReading(fable: 100)).isBlocked)
        let flagged = try Fixture.reading([try Fixture.bucket("main", [try Fixture.window("primary", used: 10)], limitReached: true)])
        let headline = HeadlineWindows(reading: flagged)
        #expect(headline.isBlocked)
        #expect(headline.blockingWindow == nil)
    }

    @Test("The blocking window is the exhausted window that resets last; unknown resets count as last")
    func blockingWindow() throws {
        let known = HeadlineWindows(reading: try Fixture.reading([
            try Fixture.window("session", .session, used: 100, minutes: 300, resetsIn: 3_600),
            try Fixture.window("week", .weekly(model: nil), used: 104, minutes: 10_080, resetsIn: 86_400),
            try Fixture.window("week.fable", .weekly(model: "Fable"), used: 99, minutes: 10_080, resetsIn: 200_000),
        ]))
        #expect(known.blockingWindow?.id == "week")

        let unknown = HeadlineWindows(reading: try Fixture.reading([
            try Fixture.window("a", used: 100, resetsIn: nil),
            try Fixture.window("b", used: 100, resetsIn: 86_400),
        ]))
        #expect(unknown.blockingWindow?.id == "a")

        let tie = HeadlineWindows(reading: try Fixture.reading([
            try Fixture.window("a", used: 100, resetsIn: 600),
            try Fixture.window("b", used: 100, resetsIn: 600),
        ]))
        #expect(tie.blockingWindow?.id == "a")
        #expect(HeadlineWindows(reading: try claudeReading()).blockingWindow == nil)
    }

    @Test("All windows are listed session, weekly all models, model weeks by usage, then the rest")
    func displayOrder() throws {
        let headline = HeadlineWindows(reading: try claudeReading())
        #expect(headline.allWindows.map(\.id) == ["session", "week", "week.fable", "week.sonnet", "limit.extra"])
        let codex = HeadlineWindows(reading: try Fixture.reading([
            try Fixture.window("secondary", used: 20, minutes: 10_080),
            try Fixture.window("primary", used: 5, minutes: 300),
        ]))
        #expect(codex.allWindows.map(\.id) == ["secondary", "primary"])
    }

    @Test("Only the main bucket is considered")
    func mainBucketOnly() throws {
        let reading = try Fixture.reading([
            try Fixture.bucket("codex", [try Fixture.window("primary", used: 10)]),
            try Fixture.bucket("codex_other", [try Fixture.window("primary", used: 100)]),
        ])
        let headline = HeadlineWindows(reading: reading)
        #expect(!headline.isBlocked)
        #expect(headline.allWindows.count == 1)
    }
}

@Suite("Window progress")
struct WindowProgressTests {
    @Test("Used share is clamped and elapsed follows the reset time")
    func basics() throws {
        // 5 h window resetting in 1 h: 80 % of its time has passed.
        let progress = WindowProgress(window: try Fixture.window("w", used: 50, minutes: 300, resetsIn: 3_600), now: Fixture.now)
        #expect(progress.used == 0.5)
        #expect(abs((progress.elapsed ?? -1) - 0.8) < 1e-9)
        #expect(progress.overrun == 0)
        #expect(progress.tickCount == 5)

        let overdrawn = WindowProgress(window: try Fixture.window("w", used: 130, minutes: 300, resetsIn: 14_400), now: Fixture.now)
        #expect(overdrawn.used == 1)
        #expect(abs((overdrawn.elapsed ?? -1) - 0.2) < 1e-9)
        #expect(abs(overdrawn.overrun - 0.8) < 1e-9)
    }

    @Test("Elapsed is unknown without a duration or reset time, and overrun is then zero")
    func unknownElapsed() throws {
        let noReset = WindowProgress(window: try Fixture.window("w", used: 90, resetsIn: nil), now: Fixture.now)
        #expect(noReset.elapsed == nil)
        #expect(noReset.overrun == 0)
        let noDuration = WindowProgress(window: try Fixture.window("w", used: 90, minutes: nil), now: Fixture.now)
        #expect(noDuration.elapsed == nil)
        #expect(noDuration.overrun == 0)
    }

    @Test("Elapsed is clamped: a passed reset is fully elapsed, a far reset has just started")
    func clamped() throws {
        let passed = WindowProgress(window: try Fixture.window("w", used: 10, minutes: 60, resetsIn: -120), now: Fixture.now)
        #expect(passed.elapsed == 1)
        let skewed = WindowProgress(window: try Fixture.window("w", used: 10, minutes: 60, resetsIn: 7_200), now: Fixture.now)
        #expect(skewed.elapsed == 0)
        #expect(abs(skewed.overrun - 0.1) < 1e-9)
    }

    @Test("Tick counts: 7 for week-long windows, 5 for five hours, otherwise 0")
    func ticks() throws {
        #expect(WindowProgress(window: try Fixture.window("w", used: 1, minutes: 10_080), now: Fixture.now).tickCount == 7)
        #expect(WindowProgress(window: try Fixture.window("w", used: 1, minutes: 8_640), now: Fixture.now).tickCount == 7)
        #expect(WindowProgress(window: try Fixture.window("w", used: 1, minutes: 8_639), now: Fixture.now).tickCount == 0)
        #expect(WindowProgress(window: try Fixture.window("w", used: 1, minutes: 300), now: Fixture.now).tickCount == 5)
        #expect(WindowProgress(window: try Fixture.window("w", used: 1, minutes: 60), now: Fixture.now).tickCount == 0)
        #expect(WindowProgress(window: try Fixture.window("w", .weekly(model: nil), used: 1, minutes: nil), now: Fixture.now).tickCount == 7)
        #expect(WindowProgress(window: try Fixture.window("w", .session, used: 1, minutes: nil), now: Fixture.now).tickCount == 5)
        #expect(WindowProgress(window: try Fixture.window("w", .rolling, used: 1, minutes: nil), now: Fixture.now).tickCount == 0)
    }
}
