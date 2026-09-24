@testable import CodometerCodex
import CodometerCore
import Foundation
import Testing

/// Lines only these tests need.
private enum Drift {
    /// An `event_msg` with a payload type this version knows and deliberately ignores.
    static func knownEvent(at time: String, type: String = "item_completed") -> String {
        #"{"timestamp":"\#(time)","type":"event_msg","payload":{"type":"\#(type)","item":{"id":"item_1"}}}"#
    }

    /// An `event_msg` of a type this version has never seen.
    static func unknownEvent(at time: String, type: String = "quantum_flux_started") -> String {
        #"{"timestamp":"\#(time)","type":"event_msg","payload":{"type":"\#(type)","detail":"whatever"}}"#
    }
}

@Suite("Codex reader statistics")
struct CodexReaderStatisticsTests {
    private let header = [
        Rollout.sessionMeta(at: "2026-09-16T18:54:41.845Z"),
        Rollout.turnContext(at: "2026-09-16T18:55:00.000Z"),
        Rollout.taskStarted(at: "2026-09-16T18:55:00.100Z"),
    ]
    private let bootstrapTime = Rollout.date("2026-09-16T18:56:00Z")

    @Test("Nothing unusual means empty counters")
    func cleanLogs() async throws {
        let profile = try RolloutProfile()
        try profile.write(header + [
            Drift.knownEvent(at: "2026-09-16T18:55:10.000Z"),
            Rollout.tokenCount(at: "2026-09-16T18:55:30.100Z"),
            Rollout.message(at: "2026-09-16T18:55:40.000Z"),
        ])
        let reader = profile.reader()
        let snapshot = await reader.bootstrap(now: bootstrapTime)
        #expect(snapshot.statistics == .empty)
    }

    @Test("An unfamiliar event type is counted once per line, names never kept")
    func unknownEventTypes() async throws {
        let profile = try RolloutProfile()
        try profile.write(header)
        let reader = profile.reader()
        _ = await reader.bootstrap(now: bootstrapTime)

        try profile.append([
            Drift.knownEvent(at: "2026-09-16T18:56:10.000Z"),
            Drift.unknownEvent(at: "2026-09-16T18:56:11.000Z"),
            Drift.unknownEvent(at: "2026-09-16T18:56:12.000Z", type: "another_new_event"),
            Rollout.message(at: "2026-09-16T18:56:13.000Z"),
        ])
        let snapshot = await reader.process(changedPaths: [profile.file.path], now: Rollout.date("2026-09-16T18:56:20Z"))
        #expect(snapshot.statistics.unknownEventTypes == 2)
        #expect(snapshot.statistics.oversizedLinesSkipped == 0)
        #expect(await reader.statistics().unknownEventTypes == 2)
    }

    @Test("Reading a tail at startup never counts events")
    func bootstrapDoesNotCount() async throws {
        let profile = try RolloutProfile()
        try profile.write(header + [
            Drift.unknownEvent(at: "2026-09-16T18:55:20.000Z"),
            Drift.unknownEvent(at: "2026-09-16T18:55:21.000Z"),
        ])
        let reader = profile.reader()
        #expect(await reader.bootstrap(now: bootstrapTime).statistics.unknownEventTypes == 0)
    }

    @Test("Every event type the parser acts on is known")
    func parserTypesAreKnown() {
        let acted = ["token_count", "task_started", "task_complete", "turn_aborted"]
        #expect(acted.allSatisfy(CodexSessionLogReader.knownEventTypes.contains))
    }

    @Test("A burst larger than one read counts as skipped content")
    func oversizedLinesSkipped() async throws {
        let profile = try RolloutProfile()
        try profile.write(header)
        let reader = profile.reader()
        _ = await reader.bootstrap(now: bootstrapTime)

        // More than `maximumReadBytes` appended at once: the tail starts inside the burst and drops what it passed.
        let chunk = Int(CodexSessionLogReader.maximumReadBytes) / 8
        for index in 0..<9 {
            try profile.append([Rollout.filler(at: "2026-09-16T18:56:\(String(format: "%02d", index)).000Z", bytes: chunk)])
        }
        let snapshot = await reader.process(changedPaths: [profile.file.path], now: Rollout.date("2026-09-16T18:57:00Z"))
        #expect(snapshot.statistics.oversizedLinesSkipped == 1)
    }

    @Test("Statistics start over when the reader bootstraps again")
    func bootstrapResets() async throws {
        let profile = try RolloutProfile()
        try profile.write(header)
        let reader = profile.reader()
        _ = await reader.bootstrap(now: bootstrapTime)
        try profile.append([Drift.unknownEvent(at: "2026-09-16T18:56:10.000Z")])
        #expect(await reader.process(changedPaths: [profile.file.path], now: bootstrapTime).statistics.unknownEventTypes == 1)
        #expect(await reader.bootstrap(now: bootstrapTime).statistics == .empty)
    }

    @Test("Counters never go negative")
    func bounded() {
        let statistics = CodexReaderStatistics(oversizedLinesSkipped: -3, unknownEventTypes: -1)
        #expect(statistics == .empty)
    }
}

@Suite("Codex version parsing")
struct CodexUserAgentTests {
    @Test("Reads the version out of the app-server user agent")
    func realUserAgent() {
        #expect(CodexUserAgent.version(in: "codex_cli_rs/0.154.0 (Mac OS 26.0.0; arm64) WindowsTerminal") == "0.154.0")
        #expect(CodexUserAgent.version(in: "codex_cli_rs/1.0.0") == "1.0.0")
        #expect(CodexUserAgent.version(in: " codex/0.9.12 (Mac OS)") == "0.9.12")
    }

    @Test("Anything else reads as unknown")
    func garbage() {
        #expect(CodexUserAgent.version(in: "") == nil)
        #expect(CodexUserAgent.version(in: "codex_cli_rs") == nil)
        #expect(CodexUserAgent.version(in: "codex_cli_rs/dev") == nil)
        #expect(CodexUserAgent.version(in: "0.154.0") == nil)
        #expect(CodexUserAgent.version(in: "built with codex_cli_rs/0.154.0") == nil)
        #expect(CodexUserAgent.version(in: String(repeating: "x", count: 5_000)) == nil)
    }
}
