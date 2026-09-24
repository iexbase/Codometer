@testable import CodometerClaude
import CodometerCore
import Foundation
import Testing

/// Output captured from Claude Code on this Mac on 2026-09-17 (numbers only; no account data).
private let usageOutput = """
You are currently using your subscription to power your Claude Code usage

Current session: 7% used · resets Sep 17 at 10:10am (Asia/Dubai)
Current week (all models): 38% used · resets Sep 23 at 5am (Asia/Dubai)
Current week (Fable): 63% used · resets Sep 23 at 5am (Asia/Dubai)

What's contributing to your limits usage?
Approximate, based on local sessions on this machine — does not include other devices or claude.ai. Behaviors are independent characteristics, not a breakdown.

Last 24h · 1746 requests · 9 sessions
  98% of your usage came from subagent-heavy sessions
  Top subagents: general-purpose 20%, workflow-subagent 2%
"""

@Suite("Claude /usage parser")
struct ClaudeUsageReportParserTests {
    @Test("Parses session, weekly and model-scoped weekly windows and ignores the contributing section")
    func realOutput() throws {
        let now = try date("2026-09-17T06:00:00Z")
        let reading = try ClaudeUsageReportParser.parse(usageOutput, now: now)
        let windows = reading.mainBucket.windows
        #expect(windows.map(\.id) == ["session", "week", "week.fable"])
        #expect(windows.map(\.used.value) == [7, 38, 63])
        #expect(windows.map(\.scope) == [.session, .weekly(model: nil), .weekly(model: "Fable")])
        #expect(windows.map(\.duration) == [.fiveHours, .oneWeek, .oneWeek])
        #expect(windows.allSatisfy { $0.label == nil })
        // 10:10am in Dubai (UTC+4) on Sep 17 is 06:10 UTC.
        #expect(windows[0].resetsAt == (try date("2026-09-17T06:10:00Z")))
        #expect(windows[1].resetsAt == (try date("2026-09-23T01:00:00Z")))
        #expect(windows[2].resetsAt == (try date("2026-09-23T01:00:00Z")))
        #expect(reading.source == .claudeUsageCommand)
        #expect(reading.buckets.count == 1)
        #expect(!reading.mainBucket.isLimitReached)
    }

    @Test("Lines joined with \" | \" parse like separate lines; \"Sonnet only\" scopes the week to Sonnet")
    func pipeJoined() throws {
        let now = try date("2026-09-17T06:00:00Z")
        let joined = "Current session: 7% used · resets Sep 17 at 10:10am (Asia/Dubai) | "
            + "Current week (all models): 38% used · resets Sep 23 at 5am (Asia/Dubai) | "
            + "Current week (Sonnet only): 12.5% used · resets Sep 23 at 5am (Asia/Dubai)"
        let windows = try ClaudeUsageReportParser.parse(joined, now: now).mainBucket.windows
        #expect(windows.map(\.id) == ["session", "week", "week.sonnet"])
        #expect(windows.map(\.used.value) == [7, 38, 12.5])
        #expect(windows[2].scope == .weekly(model: "Sonnet"))
        #expect(windows[2].duration == .oneWeek)
        #expect(windows[0].resetsAt == (try date("2026-09-17T06:10:00Z")))
        #expect(windows[2].resetsAt == (try date("2026-09-23T01:00:00Z")))
    }

    @Test("An unknown limit line becomes a generic window titled by the provider")
    func genericLine() throws {
        let now = try date("2026-09-17T06:00:00Z")
        let text = "Current session: 7% used\nCurrent month (spend): 12% used · resets Oct 1"
        let windows = try ClaudeUsageReportParser.parse(text, now: now).mainBucket.windows
        #expect(windows.map(\.id) == ["session", "limit.current-month-spend"])
        let month = windows[1]
        #expect(month.scope == .rolling)
        #expect(month.label == "Current month (spend)")
        #expect(month.duration?.minutes == 30 * 24 * 60)
        #expect(month.used.value == 12)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let octoberFirst = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 1)))
        #expect(month.resetsAt == octoberFirst)
    }

    @Test("Generic windows only get a duration their title plainly names")
    func impliedDurations() {
        #expect(ClaudeUsageReportParser.impliedDuration(title: "Extra usage") == nil)
        #expect(ClaudeUsageReportParser.impliedDuration(title: "Current session (Opus)") == .fiveHours)
        #expect(ClaudeUsageReportParser.impliedDuration(title: "5-hour burst") == .fiveHours)
        #expect(ClaudeUsageReportParser.impliedDuration(title: "Weekly Opus limit") == .oneWeek)
        #expect(ClaudeUsageReportParser.impliedDuration(title: "Daily requests") == .oneDay)
        #expect(ClaudeUsageReportParser.impliedDuration(title: "Monthly spend")?.minutes == 43_200)
        // "Sessions" or "weekday" are not the words "session" or "week".
        #expect(ClaudeUsageReportParser.impliedDuration(title: "Weekday bonus") == nil)
    }

    @Test("Duplicate titles keep the first line; ids ignore case")
    func duplicates() throws {
        let text = """
        Current session: 7% used · resets 3pm (UTC)
        Current session: 99% used · resets 4pm (UTC)
        Current week (Fable): 63% used
        Current week (fable): 10% used
        Current week (Sonnet only): 5% used
        Current week (Sonnet): 6% used
        """
        let windows = try ClaudeUsageReportParser.parse(text, now: Date()).mainBucket.windows
        #expect(windows.map(\.id) == ["session", "week.fable", "week.sonnet"])
        #expect(windows.map(\.used.value) == [7, 63, 5])
    }

    @Test("Window ids are always valid stable identifiers")
    func identifiers() throws {
        #expect(ClaudeUsageReportParser.identifier(prefix: "week.", name: "Opus 4.1") == "week.opus-4-1")
        let cyrillic = ClaudeUsageReportParser.identifier(prefix: "week.", name: "Опус")
        #expect(cyrillic.hasPrefix("week.x"))
        #expect(cyrillic == ClaudeUsageReportParser.identifier(prefix: "week.", name: "Опус"))
        let long = ClaudeUsageReportParser.identifier(prefix: "limit.", name: String(repeating: "Very long title ", count: 10))
        #expect(long.utf8.count <= StableIdentifier.maximumLength)
        #expect(!long.hasSuffix("-"))
        for id in [cyrillic, long] {
            _ = try StableIdentifier.validate(id, field: "test")
        }

        let window = try #require(
            try ClaudeUsageReportParser.parse("Current week (Опус): 40% used", now: Date()).mainBucket.windows.first
        )
        #expect(window.scope == .weekly(model: "Опус"))
    }

    @Test("More windows than a bucket holds are cut at the limit instead of failing")
    func tooManyWindows() throws {
        let text = (1...12).map { "Current week (Model \($0)): \($0)% used" }.joined(separator: " | ")
        let windows = try ClaudeUsageReportParser.parse(text, now: Date()).mainBucket.windows
        #expect(windows.count == LimitBucket.maximumWindows)
        #expect(windows.first?.id == "week.model-1")
    }

    @Test("Lines without a reset keep their percentage")
    func noReset() throws {
        let reading = try ClaudeUsageReportParser.parse("Current session: 0% used", now: Date())
        #expect(reading.mainBucket.windows.first?.resetsAt == nil)
        #expect(reading.mainBucket.windows.first?.used == .zero)
    }

    @Test("A full limit marks the bucket as reached")
    func exhausted() throws {
        let reading = try ClaudeUsageReportParser.parse("Current session: 100% used · resets 3pm (UTC)", now: Date())
        #expect(reading.mainBucket.isLimitReached)
    }

    @Test("Unrecognised output is an error, never an empty reading")
    func failures() {
        #expect(throws: ClaudeUsageParseError.noLimitLines) {
            try ClaudeUsageReportParser.parse("Total cost: $1.23\nTotal duration: 5m", now: Date())
        }
        #expect(throws: ClaudeUsageParseError.noLimitLines) {
            try ClaudeUsageReportParser.parse("Top subagents: general-purpose 20%, workflow-subagent 2%", now: Date())
        }
        #expect(throws: ClaudeUsageParseError.signedOut) {
            try ClaudeUsageReportParser.parse("Not logged in · Please run /login", now: Date())
        }
        #expect(throws: ClaudeUsageParseError.notSubscription) {
            try ClaudeUsageReportParser.parse("You are using an API key | Current usage is billed", now: Date())
        }
    }

    @Test("Reset phrases: on-the-hour times, zones containing 'am', dates without a time, the year boundary")
    func resetPhrases() throws {
        let now = try date("2026-12-31T20:00:00Z")
        let newYear = ResetTextParser.parse("Jan 1 at 9am (America/Panama)", now: now)
        #expect(newYear == (try date("2027-01-01T14:00:00Z")))
        let sameDay = ResetTextParser.parse("11:30pm (UTC)", now: now)
        #expect(sameDay == (try date("2026-12-31T23:30:00Z")))
        let rolledOver = ResetTextParser.parse("7pm (UTC)", now: now)
        #expect(rolledOver == (try date("2027-01-01T19:00:00Z")))
        #expect(ResetTextParser.parse("Jan 2 (UTC)", now: now) == (try date("2027-01-02T00:00:00Z")))
        #expect(ResetTextParser.parse("Sep 17 at 12:10am (Not/AZone)", now: now) == nil)
        #expect(ResetTextParser.parse("sometime soon", now: now) == nil)
        #expect(ResetTextParser.parse("Sep 45 at 1am (UTC)", now: now) == nil)
    }

    @Test("Limit-like lines after the contributing heading are ignored; a heading before the limits is not a stop")
    func contributingSection() throws {
        let now = try date("2026-09-17T06:00:00Z")
        let after = "Current session: 7% used\nWhat’s contributing to your limits usage?\nSubagents: 20% used"
        #expect(try ClaudeUsageReportParser.parse(after, now: now).mainBucket.windows.map(\.id) == ["session"])
        let before = "What's contributing to your limits usage? | Current week (all models): 38% used"
        #expect(try ClaudeUsageReportParser.parse(before, now: now).mainBucket.windows.map(\.id) == ["week"])
    }

    @Test("An implausible value in an unknown line is dropped; in a known line it is an error")
    func implausibleValues() throws {
        let now = try date("2026-09-17T06:00:00Z")
        let text = "Current session: 7% used | Bonus pool: 5000% used"
        #expect(try ClaudeUsageReportParser.parse(text, now: now).mainBucket.windows.map(\.id) == ["session"])
        #expect(throws: ClaudeUsageParseError.self) {
            try ClaudeUsageReportParser.parse("Current session: 5000% used", now: now)
        }
    }

    @Test("Segments split on newlines and \" | \" and drop blanks")
    func segments() {
        #expect(ClaudeUsageReportParser.segments(of: "a | b\n\n  c  |  | d\r\ne") == ["a", "b", "c", "d", "e"])
    }
}
