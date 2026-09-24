@testable import CodometerCodex
import CodometerCore
import Foundation
import Testing

@Suite("Codex token usage")
struct CodexTokenUsageTests {
    private let header = [
        Rollout.sessionMeta(at: "2026-09-16T18:54:41.845Z"),
        Rollout.turnContext(at: "2026-09-16T18:55:00.000Z"),
        Rollout.taskStarted(at: "2026-09-16T18:55:00.100Z"),
    ]
    private let bootstrapTime = Rollout.date("2026-09-16T18:56:00Z")

    @Test("Bootstrap produces no samples, even for recent records")
    func bootstrapIsSilent() async throws {
        let profile = try RolloutProfile()
        try profile.write(header + [
            Rollout.tokenUsageRecord(at: "2026-09-16T18:55:30.000Z", responseID: "resp_1"),
            Rollout.tokenCount(at: "2026-09-16T18:55:30.100Z"),
        ])
        let reader = profile.reader()
        #expect(await reader.bootstrap(now: bootstrapTime).tokenSamples.isEmpty)
        #expect(await reader.snapshot(now: bootstrapTime).tokenSamples.isEmpty)
    }

    @Test("Appended records become per-session samples with uncached input, drained once")
    func liveRecords() async throws {
        let profile = try RolloutProfile()
        try profile.write(header)
        let reader = profile.reader()
        _ = await reader.bootstrap(now: bootstrapTime)

        try profile.append([
            Rollout.tokenUsageRecord(at: "2026-09-16T18:56:10.000Z", responseID: "resp_2", input: 1_200, cached: 1_000, output: 300, reasoning: 120),
            Rollout.tokenCount(at: "2026-09-16T18:56:10.100Z", input: 1_200, cached: 1_000, output: 300),
            Rollout.tokenUsageRecord(at: "2026-09-16T18:56:20.000Z", responseID: "resp_3", input: 5_000, cached: 4_000, output: 50, reasoning: 0),
        ])
        let snapshot = await reader.process(changedPaths: [profile.file.path], now: Rollout.date("2026-09-16T18:56:21Z"))
        let sample = try #require(snapshot.tokenSamples.first)
        #expect(snapshot.tokenSamples.count == 1)
        #expect(sample.accountID == profile.accountID)
        #expect(sample.sessionID == Rollout.sessionID)
        #expect(sample.project == Rollout.project)
        #expect(sample.model == Rollout.model)
        #expect(sample.at == Rollout.date("2026-09-16T18:56:20.000Z"))
        #expect(sample.delta == (try TokenCounts(input: 1_200, cachedInput: 5_000, cacheWrite: 0, output: 350, reasoningOutput: 120)))

        #expect(await reader.snapshot(now: Rollout.date("2026-09-16T18:56:22Z")).tokenSamples.isEmpty)
    }

    @Test("A response id is counted once, including ids first seen during bootstrap")
    func dedupe() async throws {
        let profile = try RolloutProfile()
        try profile.write(header + [Rollout.tokenUsageRecord(at: "2026-09-16T18:55:30.000Z", responseID: "resp_1")])
        let reader = profile.reader()
        _ = await reader.bootstrap(now: bootstrapTime)

        try profile.append([
            Rollout.tokenUsageRecord(at: "2026-09-16T18:56:30.000Z", responseID: "resp_1"),
            Rollout.tokenUsageRecord(at: "2026-09-16T18:56:31.000Z", responseID: "resp_2", input: 100, cached: 0, output: 10),
            Rollout.tokenUsageRecord(at: "2026-09-16T18:56:32.000Z", responseID: "resp_2", input: 100, cached: 0, output: 10),
        ])
        let snapshot = await reader.process(changedPaths: [profile.file.path], now: Rollout.date("2026-09-16T18:56:40Z"))
        #expect(snapshot.tokenSamples.map(\.delta) == [try TokenCounts(input: 100, cachedInput: 0, cacheWrite: 0, output: 10, reasoningOutput: 120)])

        // The same response repeated in another file (a resumed thread) is still counted once.
        let copy = profile.sibling(named: "rollout-2026-09-16T22-58-00-11111111-2222-3333-4444-555555555555.jsonl")
        try profile.write([Rollout.tokenUsageRecord(at: "2026-09-16T18:56:31.000Z", responseID: "resp_2", input: 100, cached: 0, output: 10)], to: copy)
        #expect(await reader.process(changedPaths: [copy.path], now: Rollout.date("2026-09-16T18:57:00Z")).tokenSamples.isEmpty)
    }

    @Test("History copied into a new file before live collection started is not usage")
    func copiedHistory() async throws {
        let profile = try RolloutProfile()
        try profile.write(header)
        let reader = profile.reader()
        _ = await reader.bootstrap(now: bootstrapTime)

        let fork = profile.sibling(named: "rollout-2026-09-16T22-57-00-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.jsonl")
        try profile.write([
            Rollout.tokenUsageRecord(at: "2026-09-16T17:00:00.000Z", responseID: "old_1", input: 9_999, cached: 0, output: 9),
            Rollout.tokenUsageRecord(at: "2026-09-16T18:57:05.000Z", responseID: "new_1", input: 10, cached: 0, output: 1, reasoning: 0),
        ], to: fork)
        let snapshot = await reader.process(changedPaths: [fork.path], now: Rollout.date("2026-09-16T18:57:10Z"))
        #expect(snapshot.tokenSamples.map(\.delta.input) == [10])
    }

    @Test("Samples are split by minute and ordered by time")
    func minutes() async throws {
        let profile = try RolloutProfile()
        try profile.write(header)
        let reader = profile.reader()
        _ = await reader.bootstrap(now: bootstrapTime)
        try profile.append([
            Rollout.tokenUsageRecord(at: "2026-09-16T18:56:59.000Z", responseID: "r1", input: 1, cached: 0, output: 1, reasoning: 0),
            Rollout.tokenUsageRecord(at: "2026-09-16T18:57:01.000Z", responseID: "r2", input: 2, cached: 0, output: 1, reasoning: 0),
        ])
        let snapshot = await reader.process(changedPaths: [profile.file.path], now: Rollout.date("2026-09-16T18:57:05Z"))
        #expect(snapshot.tokenSamples.map(\.delta.input) == [1, 2])
    }

    @Test("token_count is a fallback only for logs without records; identical repeats count once")
    func tokenCountFallback() async throws {
        let profile = try RolloutProfile()
        try profile.write(header + [Rollout.tokenCount(at: "2026-09-16T18:55:40.000Z", input: 50, cached: 0, output: 5, total: 100)])
        let reader = profile.reader()
        _ = await reader.bootstrap(now: bootstrapTime)

        try profile.append([
            // Same numbers as the last bootstrap event: a repeat, not a new response.
            Rollout.tokenCount(at: "2026-09-16T18:56:05.000Z", input: 50, cached: 0, output: 5, total: 100),
            Rollout.tokenCount(at: "2026-09-16T18:56:10.000Z", input: 900, cached: 400, output: 80, total: 1_080),
            Rollout.tokenCount(at: "2026-09-16T18:56:11.000Z", input: 900, cached: 400, output: 80, total: 1_080),
            Rollout.tokenCount(at: "2026-09-16T18:56:20.000Z", input: 300, cached: 100, output: 20, total: 1_400),
        ])
        let snapshot = await reader.process(changedPaths: [profile.file.path], now: Rollout.date("2026-09-16T18:56:30Z"))
        #expect(snapshot.tokenSamples.map(\.delta) == [try TokenCounts(input: 700, cachedInput: 500, cacheWrite: 0, output: 100, reasoningOutput: 20)])

        // Once the log produces a record, token_count is ignored for that file.
        try profile.append([
            Rollout.tokenUsageRecord(at: "2026-09-16T18:56:40.000Z", responseID: "resp_9", input: 10, cached: 0, output: 1, reasoning: 0),
            Rollout.tokenCount(at: "2026-09-16T18:56:40.100Z", input: 10, cached: 0, output: 1, total: 1_411),
        ])
        let after = await reader.process(changedPaths: [profile.file.path], now: Rollout.date("2026-09-16T18:56:50Z"))
        #expect(after.tokenSamples.map(\.delta.input) == [10])
    }

    @Test("The remembered response set is bounded and forgets the oldest first")
    func recentIdentifiers() {
        var recent = RecentIdentifiers(capacity: 2)
        let inserted = ["a", "b", "a", "c"].map { recent.insert($0) }
        #expect(inserted == [true, true, false, true])
        #expect(!recent.contains("a"))
        #expect(recent.contains("b") && recent.contains("c"))
        let reinserted = recent.insert("a")
        #expect(reinserted)
        #expect(!recent.contains("b"))
        #expect(recent.count == 2)
        #expect(RecentIdentifiers(capacity: 0).capacity == 1)
    }
}
