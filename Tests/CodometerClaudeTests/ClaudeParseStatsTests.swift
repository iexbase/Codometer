@testable import CodometerClaude
import CodometerCore
import Foundation
import Testing

/// Output shapes used only by the drift tests; numbers and provider UI text only.
private enum DriftFixtures {
    /// Every window has a known meaning.
    static let known = """
    Current session: 7% used · resets Sep 17 at 10:10am (Asia/Dubai)
    Current week (all models): 38% used · resets Sep 23 at 5am (Asia/Dubai)
    Current week (Sonnet only): 12% used · resets Sep 23 at 5am (Asia/Dubai)
    """

    /// Window titles this version has no mapping for.
    static let unknownTitle = """
    Current session: 7% used · resets Sep 17 at 10:10am (Asia/Dubai)
    Current month (spend): 4% used · resets Oct 1
    Enterprise pool: 9% used
    """

    /// A weekly window scoped to a model this version has never heard of: a known shape, so no drift.
    static let unfamiliarModel = """
    Current session: 7% used · resets Sep 17 at 10:10am (Asia/Dubai)
    Current week (Opus 5): 12% used · resets Sep 23 at 5am (Asia/Dubai)
    """

    /// An unknown line whose percentage is out of range: it is dropped, the known limits survive.
    static let invalidUnknownValue = """
    Current session: 7% used · resets Sep 17 at 10:10am (Asia/Dubai)
    Lifetime spend: 4210% used
    """

    static let withContributing = """
    Current session: 7% used · resets Sep 17 at 10:10am (Asia/Dubai)

    What's contributing to your limits usage?
    Last 24h · 1746 requests · 9 sessions
    """
}

@Suite("Claude parse statistics")
struct ClaudeParseStatsTests {
    private let now = Date(timeIntervalSince1970: 1_789_600_000)

    @Test("A known layout reports no drift")
    func knownLayout() throws {
        let result = try ClaudeUsageReportParser.parseReport(DriftFixtures.known, now: now)
        #expect(result.reading.mainBucket.windows.count == 3)
        #expect(result.stats.genericTitles.isEmpty)
        #expect(result.stats.droppedInvalid == 0)
        #expect(!result.stats.sawContributingHeading)
    }

    @Test("A window title without a meaning is reported, with its text")
    func unknownTitles() throws {
        let result = try ClaudeUsageReportParser.parseReport(DriftFixtures.unknownTitle, now: now)
        #expect(result.stats.genericTitles == ["Current month (spend)", "Enterprise pool"])
        #expect(result.stats.droppedInvalid == 0)
        // The windows are still tracked; only their meaning is unknown.
        #expect(result.reading.mainBucket.windows.count == 3)
        #expect(result.reading.mainBucket.windows.compactMap(\.label).count == 2)
    }

    @Test("A weekly window scoped to an unfamiliar model is a known shape, not drift")
    func unfamiliarModelIsKnown() throws {
        let result = try ClaudeUsageReportParser.parseReport(DriftFixtures.unfamiliarModel, now: now)
        #expect(result.stats.genericTitles.isEmpty)
        #expect(result.reading.mainBucket.windows.map(\.id) == ["session", "week.opus-5"])
    }

    @Test("An implausible value on an unknown line is counted and dropped")
    func droppedInvalidValue() throws {
        let result = try ClaudeUsageReportParser.parseReport(DriftFixtures.invalidUnknownValue, now: now)
        #expect(result.stats.droppedInvalid == 1)
        #expect(result.stats.genericTitles.isEmpty)
        #expect(result.reading.mainBucket.windows.map(\.id) == ["session"])
    }

    @Test("The contributing section is noticed but never parsed")
    func contributingHeading() throws {
        let result = try ClaudeUsageReportParser.parseReport(DriftFixtures.withContributing, now: now)
        #expect(result.stats.sawContributingHeading)
        #expect(result.reading.mainBucket.windows.map(\.id) == ["session"])
    }

    @Test("`parse` still returns exactly the reading `parseReport` does")
    func wrapperAgrees() throws {
        for text in [DriftFixtures.known, DriftFixtures.unknownTitle, DriftFixtures.unfamiliarModel, DriftFixtures.withContributing] {
            let plain = try ClaudeUsageReportParser.parse(text, now: now)
            let detailed = try ClaudeUsageReportParser.parseReport(text, now: now)
            #expect(plain == detailed.reading)
        }
    }

    @Test("Statistics never hold negative counts")
    func statsAreBounded() {
        let stats = ClaudeParseStats(genericTitles: [], droppedInvalid: -4, sawContributingHeading: false)
        #expect(stats.droppedInvalid == 0)
        #expect(ClaudeParseStats.empty.genericTitles.isEmpty)
    }
}
