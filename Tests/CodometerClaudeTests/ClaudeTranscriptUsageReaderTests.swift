@testable import CodometerClaude
import CodometerCore
import CodometerPlatform
import Foundation
import Testing

/// One assistant block in Claude Code's transcript shape. The content is a placeholder.
private func assistantLine(
    requestID: String? = "req_1",
    messageID: String? = "msg_1",
    model: String = "claude-opus-5",
    input: Int = 2,
    output: Int = 100,
    cacheWrite: Int = 1_000,
    cacheRead: Int = 5_000,
    at date: Date,
    includeContent: Bool = true
) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var message = #""model":"\#(model)","type":"message","role":"assistant","#
    if let messageID { message += #""id":"\#(messageID)","# }
    if includeContent { message += #""content":[{"type":"text","text":"placeholder usage assistant"}],"# }
    message += #""stop_reason":null,"usage":{"input_tokens":\#(input),"cache_creation_input_tokens":\#(cacheWrite),"cache_read_input_tokens":\#(cacheRead),"output_tokens":\#(output),"service_tier":"standard","server_tool_use":{"web_search_requests":0}}"#
    var line = #"{"parentUuid":"p","isSidechain":false,"message":{\#(message)},"#
    if let requestID { line += #""requestId":"\#(requestID)","# }
    line += #""type":"assistant","uuid":"u","timestamp":"\#(formatter.string(from: date))","cwd":"/Users/me/proj","sessionId":"x"}"#
    return line
}

private final class TranscriptFixture {
    static let sessionID = "0b7c7a1e-7f53-4c1c-9a64-4d3f0f8a2b11"
    static let slug = "-Users-me-proj"

    let directory: TemporaryDirectory
    let projects: URL
    let accountID = AccountID()

    init() throws {
        directory = try TemporaryDirectory()
        projects = directory.url.appendingPathComponent("projects", isDirectory: true)
        try FileManager.default.createDirectory(
            at: projects.appendingPathComponent(Self.slug, isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    var mainTranscript: URL {
        projects.appendingPathComponent("\(Self.slug)/\(Self.sessionID).jsonl")
    }

    func subagent(_ relative: String) -> URL {
        projects.appendingPathComponent("\(Self.slug)/\(Self.sessionID)/subagents/\(relative)")
    }

    func reader(maximumFilesPerSession: Int = ClaudeTranscriptUsageReader.maximumFilesPerSession) -> ClaudeTranscriptUsageReader {
        ClaudeTranscriptUsageReader(
            projectsDirectory: projects,
            accountID: accountID,
            maximumFilesPerSession: maximumFilesPerSession
        )
    }

    func session(id: String = TranscriptFixture.sessionID, projectPath: String? = "/Users/me/proj") throws -> AgentSession {
        try AgentSession(
            id: id,
            title: nil,
            projectPath: projectPath,
            activity: .working,
            detail: nil,
            activitySince: Date(),
            processID: 1
        )
    }

    func write(_ lines: [String], to url: URL, trailingNewline: Bool = true) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = lines.joined(separator: "\n") + (trailingNewline && !lines.isEmpty ? "\n" : "")
        try Data(text.utf8).write(to: url)
    }

    func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    func append(lines: [String], to url: URL) throws {
        try append(lines.map { $0 + "\n" }.joined(), to: url)
    }
}

@Suite("Claude transcript usage reader")
struct ClaudeTranscriptUsageReaderTests {
    @Test("Existing content is never counted; appended assistant lines produce deltas")
    func liveOnly() async throws {
        let fixture = try TranscriptFixture()
        let now = Date()
        try fixture.write([assistantLine(requestID: "old", at: now.addingTimeInterval(-600))], to: fixture.mainTranscript)
        let reader = fixture.reader()
        await reader.track([try fixture.session()], now: now)
        #expect(await reader.trackedFileCount() == 1)

        let nothing = await reader.process(changedPaths: [fixture.mainTranscript.path], now: now)
        #expect(nothing.samples.isEmpty)

        let lineTime = now.addingTimeInterval(2)
        try fixture.append(lines: [assistantLine(requestID: "new", output: 250, at: lineTime)], to: fixture.mainTranscript)
        let update = await reader.process(changedPaths: [fixture.mainTranscript.path], now: now.addingTimeInterval(3))
        let sample = try #require(update.samples.first)
        #expect(update.samples.count == 1)
        #expect(sample.accountID == fixture.accountID)
        #expect(sample.sessionID == TranscriptFixture.sessionID)
        #expect(sample.project == "proj")
        #expect(sample.model == "claude-opus-5")
        #expect(sample.delta == (try TokenCounts(input: 2, cachedInput: 5_000, cacheWrite: 1_000, output: 250, reasoningOutput: 0)))
        #expect(abs(sample.at.timeIntervalSince(lineTime)) < 0.01)
        #expect(update.lastEventAt[TranscriptFixture.sessionID] != nil)

        // Nothing new: nothing counted again.
        let again = await reader.process(changedPaths: [fixture.mainTranscript.path], now: now.addingTimeInterval(4))
        #expect(again.samples.isEmpty)
    }

    @Test("A session seen for the first time reports when its transcripts were last written")
    func primingReportsLastWrite() async throws {
        let fixture = try TranscriptFixture()
        let now = Date()
        try fixture.write([assistantLine(requestID: "old", at: now.addingTimeInterval(-900))], to: fixture.mainTranscript)
        try fixture.write([assistantLine(requestID: "sub", at: now.addingTimeInterval(-60))], to: fixture.subagent("agent-a.jsonl"))
        let mainWrite = now.addingTimeInterval(-900)
        let subagentWrite = now.addingTimeInterval(-45)
        try FileManager.default.setAttributes([.modificationDate: mainWrite], ofItemAtPath: fixture.mainTranscript.path)
        try FileManager.default.setAttributes([.modificationDate: subagentWrite], ofItemAtPath: fixture.subagent("agent-a.jsonl").path)

        let reader = fixture.reader()
        let primed = await reader.track([try fixture.session()], now: now)
        let written = try #require(primed[TranscriptFixture.sessionID])
        #expect(abs(written.timeIntervalSince(subagentWrite)) < 1)

        // Already tracked: nothing reported again, and existing content is still not counted.
        let again = await reader.track([try fixture.session()], now: now.addingTimeInterval(5))
        #expect(again.isEmpty)
        let update = await reader.process(changedPaths: [fixture.mainTranscript.path], now: now.addingTimeInterval(6))
        #expect(update.samples.isEmpty)
    }

    @Test("Blocks of one request count once; a grown output adds only the growth")
    func deduplicatesRequests() async throws {
        let fixture = try TranscriptFixture()
        let now = Date()
        try fixture.write([], to: fixture.mainTranscript)
        let reader = fixture.reader()
        await reader.track([try fixture.session()], now: now)

        try fixture.append(lines: [
            assistantLine(requestID: "req_a", output: 8, at: now),
            assistantLine(requestID: "req_a", output: 8, at: now),
            assistantLine(requestID: "req_a", output: 1_517, at: now),
        ], to: fixture.mainTranscript)
        let first = await reader.process(changedPaths: [fixture.mainTranscript.path], now: now.addingTimeInterval(1))
        #expect(first.samples.count == 1)
        #expect(first.samples.first?.delta.output == 1_517)
        #expect(first.samples.first?.delta.cachedInput == 5_000)

        // The same request seen again in a later burst (or a subagent file) adds nothing.
        try fixture.append(lines: [assistantLine(requestID: "req_a", output: 1_517, at: now)], to: fixture.mainTranscript)
        let second = await reader.process(changedPaths: [fixture.mainTranscript.path], now: now.addingTimeInterval(2))
        #expect(second.samples.isEmpty)

        // Without a request id the message id deduplicates.
        try fixture.append(lines: [
            assistantLine(requestID: nil, messageID: "msg_b", output: 10, at: now),
            assistantLine(requestID: nil, messageID: "msg_b", output: 10, at: now),
            assistantLine(requestID: nil, messageID: nil, output: 999, at: now),
        ], to: fixture.mainTranscript)
        let third = await reader.process(changedPaths: [fixture.mainTranscript.path], now: now.addingTimeInterval(3))
        #expect(third.samples.map(\.delta.output) == [10])
    }

    @Test("Lines without usage are ignored and content is never required")
    func usageOnly() async throws {
        let fixture = try TranscriptFixture()
        let now = Date()
        try fixture.write([], to: fixture.mainTranscript)
        let reader = fixture.reader()
        await reader.track([try fixture.session()], now: now)

        let userLine = #"{"type":"user","message":{"role":"user","content":"what is the usage of the assistant?"},"timestamp":"2026-09-17T06:00:00Z"}"#
        let progressLine = #"{"type":"progress","data":{"message":{"type":"assistant","message":{"usage":{"output_tokens":5}}}},"requestId":"req_p"}"#
        let brokenLine = #"{"type":"assistant","message":{"usage":{"output_tokens":"#
        let negativeLine = assistantLine(requestID: "neg", output: -5, at: now)
        let noContent = assistantLine(requestID: "bare", model: "<synthetic>", output: 42, at: now, includeContent: false)
        try fixture.append(lines: [userLine, progressLine, brokenLine, negativeLine, "", noContent], to: fixture.mainTranscript)

        let update = await reader.process(changedPaths: [fixture.mainTranscript.path], now: now.addingTimeInterval(1))
        #expect(update.samples.count == 1)
        #expect(update.samples.first?.delta.output == 42)
        #expect(update.samples.first?.model == nil)
    }

    @Test("Oversize lines are skipped without stopping the lines after them")
    func oversizeLines() async throws {
        let fixture = try TranscriptFixture()
        let now = Date()
        try fixture.write([], to: fixture.mainTranscript)
        let reader = fixture.reader()
        await reader.track([try fixture.session()], now: now)

        let padding = String(repeating: "x", count: ClaudeTranscriptUsageReader.maximumLineBytes)
        let huge = assistantLine(requestID: "huge", output: 7_777, at: now)
            .replacingOccurrences(of: "placeholder usage assistant", with: padding)
        try fixture.append(lines: [huge, assistantLine(requestID: "small", output: 3, at: now)], to: fixture.mainTranscript)

        let update = await reader.process(changedPaths: [fixture.mainTranscript.path], now: now.addingTimeInterval(1))
        #expect(update.samples.map(\.delta.output) == [3])
    }

    @Test("Subagent transcripts count toward their session: existing ones from their end, new ones in full")
    func subagents() async throws {
        let fixture = try TranscriptFixture()
        let now = Date()
        try fixture.write([assistantLine(requestID: "main_old", at: now.addingTimeInterval(-900))], to: fixture.mainTranscript)
        let existing = fixture.subagent("agent-a1.jsonl")
        try fixture.write([assistantLine(requestID: "sub_old", at: now.addingTimeInterval(-900))], to: existing)

        let reader = fixture.reader()
        await reader.track([try fixture.session()], now: now)
        #expect(await reader.trackedFileCount() == 2)

        // Created after tracking started: every line in it is live.
        let created = fixture.subagent("workflows/wf_1/agent-b2.jsonl")
        try fixture.write([
            assistantLine(requestID: "wf_1", model: "claude-fable-5", output: 11, at: now.addingTimeInterval(1)),
            assistantLine(requestID: "wf_2", model: "claude-fable-5", output: 22, at: now.addingTimeInterval(2)),
        ], to: created)
        try fixture.append(lines: [assistantLine(requestID: "sub_new", output: 5, at: now.addingTimeInterval(2))], to: existing)

        let update = await reader.process(changedPaths: [created.path, existing.path], now: now.addingTimeInterval(3))
        let byModel = Dictionary(grouping: update.samples, by: { $0.model ?? "" })
            .mapValues { $0.reduce(TokenCounts.zero) { $0 + $1.delta }.output }
        #expect(byModel == ["claude-fable-5": 33, "claude-opus-5": 5])
        #expect(update.samples.allSatisfy { $0.sessionID == TranscriptFixture.sessionID })
        #expect(await reader.trackedFileCount() == 3)
    }

    @Test("Copied history in a new file is skipped by its timestamps")
    func copiedHistory() async throws {
        let fixture = try TranscriptFixture()
        let now = Date()
        let reader = fixture.reader()
        await reader.track([try fixture.session()], now: now)
        #expect(await reader.trackedFileCount() == 0)

        // The main transcript appears only now, starting with lines copied from an older conversation.
        try fixture.write([
            assistantLine(requestID: "copied", output: 900, at: now.addingTimeInterval(-3 * 3_600)),
            assistantLine(requestID: "fresh", output: 9, at: now.addingTimeInterval(5)),
        ], to: fixture.mainTranscript)
        let update = await reader.process(changedPaths: [fixture.mainTranscript.path], now: now.addingTimeInterval(6))
        #expect(update.samples.map(\.delta.output) == [9])
    }

    @Test("A file first seen after tracking started but created long before starts at its end")
    func oldFileFirstSeenLater() async throws {
        let fixture = try TranscriptFixture()
        // No main transcript, so tracking cannot find the subagent folder; the file is first seen through its event.
        let agent = fixture.subagent("agent-d4.jsonl")
        try fixture.write([assistantLine(requestID: "before", output: 500, at: Date())], to: agent)
        let trackedAt = Date().addingTimeInterval(3_600)
        let reader = fixture.reader()
        await reader.track([try fixture.session()], now: trackedAt)
        #expect(await reader.trackedFileCount() == 0)

        let first = await reader.process(changedPaths: [agent.path], now: trackedAt.addingTimeInterval(1))
        #expect(first.samples.isEmpty)
        #expect(await reader.trackedFileCount() == 1)

        try fixture.append(lines: [assistantLine(requestID: "after", output: 8, at: trackedAt.addingTimeInterval(2))], to: agent)
        let second = await reader.process(changedPaths: [agent.path], now: trackedAt.addingTimeInterval(3))
        #expect(second.samples.map(\.delta.output) == [8])
    }

    @Test("A directory event picks up files whose own events were coalesced away")
    func directorySweep() async throws {
        let fixture = try TranscriptFixture()
        let now = Date()
        try fixture.write([], to: fixture.mainTranscript)
        let reader = fixture.reader()
        await reader.track([try fixture.session()], now: now)

        let agent = fixture.subagent("agent-c3.jsonl")
        try fixture.write([assistantLine(requestID: "swept", model: "claude-fable-5", output: 13, at: now.addingTimeInterval(1))], to: agent)
        try fixture.append(lines: [assistantLine(requestID: "main", output: 4, at: now.addingTimeInterval(1))], to: fixture.mainTranscript)

        let update = await reader.process(
            changedPaths: [fixture.projects.appendingPathComponent(TranscriptFixture.slug).path],
            now: now.addingTimeInterval(2)
        )
        let byModel = Dictionary(grouping: update.samples, by: { $0.model ?? "" })
            .mapValues { $0.reduce(TokenCounts.zero) { $0 + $1.delta }.output }
        #expect(byModel == ["claude-fable-5": 13, "claude-opus-5": 4])
    }

    @Test("A file of an untracked session or outside the projects directory is never read")
    func unrelatedPaths() async throws {
        let fixture = try TranscriptFixture()
        let now = Date()
        let other = fixture.projects.appendingPathComponent("\(TranscriptFixture.slug)/11111111-2222-3333-4444-555555555555.jsonl")
        try fixture.write([], to: other)
        let reader = fixture.reader()
        await reader.track([try fixture.session()], now: now)
        try fixture.append(lines: [assistantLine(requestID: "other", at: now)], to: other)

        let outside = fixture.directory.url.appendingPathComponent("\(TranscriptFixture.sessionID).jsonl")
        try fixture.write([assistantLine(requestID: "outside", at: now)], to: outside)
        let escaping = fixture.projects.path + "/../\(TranscriptFixture.sessionID).jsonl"

        let update = await reader.process(changedPaths: [other.path, outside.path, escaping], now: now.addingTimeInterval(1))
        #expect(update.samples.isEmpty)
        #expect(await reader.trackedFileCount() == 0)
    }

    @Test("A partial last line at priming is completed without being counted")
    func partialLineAtPriming() async throws {
        let fixture = try TranscriptFixture()
        let now = Date()
        let partial = assistantLine(requestID: "partial", output: 500, at: now)
        let splitIndex = partial.index(partial.startIndex, offsetBy: 40)
        try fixture.write([String(partial[..<splitIndex])], to: fixture.mainTranscript, trailingNewline: false)
        let reader = fixture.reader()
        await reader.track([try fixture.session()], now: now)

        try fixture.append(String(partial[splitIndex...]) + "\n" + assistantLine(requestID: "next", output: 6, at: now) + "\n", to: fixture.mainTranscript)
        let update = await reader.process(changedPaths: [fixture.mainTranscript.path], now: now.addingTimeInterval(1))
        #expect(update.samples.map(\.delta.output) == [6])
    }

    @Test("Ended sessions keep a short grace period, then their state is dropped")
    func endedSessions() async throws {
        let fixture = try TranscriptFixture()
        let now = Date()
        try fixture.write([], to: fixture.mainTranscript)
        let reader = fixture.reader()
        await reader.track([try fixture.session()], now: now)
        await reader.track([], now: now.addingTimeInterval(1))

        // The final burst written just before the process exited still counts.
        try fixture.append(lines: [assistantLine(requestID: "last", output: 77, at: now.addingTimeInterval(1))], to: fixture.mainTranscript)
        let final = await reader.process(changedPaths: [fixture.mainTranscript.path], now: now.addingTimeInterval(3))
        #expect(final.samples.map(\.delta.output) == [77])

        try fixture.append(lines: [assistantLine(requestID: "late", output: 88, at: now.addingTimeInterval(40))], to: fixture.mainTranscript)
        let late = await reader.process(
            changedPaths: [fixture.mainTranscript.path],
            now: now.addingTimeInterval(1 + ClaudeTranscriptUsageReader.endedSessionGrace + 1)
        )
        #expect(late.samples.isEmpty)
        #expect(await reader.trackedSessionIDs().isEmpty)
        #expect(await reader.trackedFileCount() == 0)
    }

    @Test("The transcript is found by scanning when the project folder name is not the derived slug")
    func locatesByScanning() async throws {
        let fixture = try TranscriptFixture()
        let now = Date()
        let elsewhere = fixture.projects.appendingPathComponent("-renamed-folder/\(TranscriptFixture.sessionID).jsonl")
        try fixture.write([assistantLine(requestID: "old", at: now.addingTimeInterval(-60))], to: elsewhere)
        let reader = fixture.reader()
        await reader.track([try fixture.session(projectPath: "/Users/me/other")], now: now)
        #expect(await reader.trackedFileCount() == 1)

        try fixture.append(lines: [assistantLine(requestID: "new", output: 12, at: now)], to: elsewhere)
        let update = await reader.process(changedPaths: [elsewhere.path], now: now.addingTimeInterval(1))
        #expect(update.samples.map(\.delta.output) == [12])
        #expect(update.samples.first?.project == "other")
    }
}

extension ClaudeTranscriptUsageReaderTests {
    @Test("A resumed session's copy of responses already counted in another session counts once")
    func copiesAcrossSessions() async throws {
        let fixture = try TranscriptFixture()
        let now = Date()
        try fixture.write([], to: fixture.mainTranscript)
        let reader = fixture.reader()
        await reader.track([try fixture.session()], now: now)
        try fixture.append(lines: [assistantLine(requestID: "req_shared", output: 300, at: now.addingTimeInterval(1))], to: fixture.mainTranscript)
        let original = await reader.process(changedPaths: [fixture.mainTranscript.path], now: now.addingTimeInterval(2))
        #expect(original.samples.map(\.delta.output) == [300])

        // A minute later the conversation is resumed as a new session whose transcript starts with the copy.
        let resumedID = "22222222-3333-4444-5555-666666666666"
        let resumed = fixture.projects.appendingPathComponent("\(TranscriptFixture.slug)/\(resumedID).jsonl")
        await reader.track([try fixture.session(id: resumedID)], now: now.addingTimeInterval(60))
        try fixture.write([
            assistantLine(requestID: "req_shared", output: 300, at: now.addingTimeInterval(1)),
            assistantLine(requestID: "req_resumed", output: 4, at: now.addingTimeInterval(61)),
        ], to: resumed)
        let update = await reader.process(changedPaths: [resumed.path], now: now.addingTimeInterval(62))
        #expect(update.samples.map(\.delta.output) == [4])
        #expect(update.samples.allSatisfy { $0.sessionID == resumedID })
    }

    @Test("Beyond the file budget the quietest file is set aside and later resumes at its cursor")
    func fileBudget() async throws {
        let fixture = try TranscriptFixture()
        let now = Date()
        // Recent lines: if a set-aside file were ever re-read from its start, they would count.
        try fixture.write([assistantLine(requestID: "main_before", at: now.addingTimeInterval(-30))], to: fixture.mainTranscript)
        let first = fixture.subagent("agent-a1.jsonl")
        try fixture.write([assistantLine(requestID: "a1_before", at: now.addingTimeInterval(-30))], to: first)
        let reader = fixture.reader(maximumFilesPerSession: 2)
        await reader.track([try fixture.session()], now: now)
        #expect(await reader.trackedFileCount() == 2)

        try fixture.append(lines: [assistantLine(requestID: "main_1", output: 1, at: now.addingTimeInterval(1))], to: fixture.mainTranscript)
        #expect(await reader.process(changedPaths: [fixture.mainTranscript.path], now: now.addingTimeInterval(1)).samples.map(\.delta.output) == [1])

        // A new subagent makes room by setting aside the quietest file (agent-a1) and is counted in full.
        let second = fixture.subagent("agent-b2.jsonl")
        try fixture.write([assistantLine(requestID: "b2_1", output: 2, at: now.addingTimeInterval(2))], to: second)
        let added = await reader.process(changedPaths: [second.path], now: now.addingTimeInterval(2))
        #expect(added.samples.map(\.delta.output) == [2])
        #expect(await reader.trackedFileCount() == 2)
        #expect(await reader.retiredFileCount() == 1)

        // The set-aside file is written again: only the new line counts.
        try fixture.append(lines: [assistantLine(requestID: "a1_1", output: 3, at: now.addingTimeInterval(3))], to: first)
        let resumed = await reader.process(changedPaths: [first.path], now: now.addingTimeInterval(3))
        #expect(resumed.samples.map(\.delta.output) == [3])
        #expect(await reader.trackedFileCount() == 2)

        // So is the main transcript, which made room for it.
        try fixture.append(lines: [assistantLine(requestID: "main_2", output: 4, at: now.addingTimeInterval(4))], to: fixture.mainTranscript)
        let main = await reader.process(changedPaths: [fixture.mainTranscript.path], now: now.addingTimeInterval(4))
        #expect(main.samples.map(\.delta.output) == [4])
        #expect(await reader.retiredFileCount() == 1)
    }

    @Test("A directory sweep adopts only recently written files")
    func sweepSkipsStaleFiles() async throws {
        let fixture = try TranscriptFixture()
        let now = Date()
        try fixture.write([], to: fixture.mainTranscript)
        let reader = fixture.reader()
        await reader.track([try fixture.session()], now: now)

        let stale = fixture.subagent("agent-old.jsonl")
        try fixture.write([assistantLine(requestID: "stale", output: 50, at: now.addingTimeInterval(1))], to: stale)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-3_600)], ofItemAtPath: stale.path)
        let fresh = fixture.subagent("agent-new.jsonl")
        try fixture.write([assistantLine(requestID: "fresh", output: 5, at: now.addingTimeInterval(1))], to: fresh)

        let update = await reader.process(
            changedPaths: [fixture.projects.appendingPathComponent("\(TranscriptFixture.slug)/\(TranscriptFixture.sessionID)/subagents").path],
            now: now.addingTimeInterval(2)
        )
        #expect(update.samples.map(\.delta.output) == [5])
        #expect(await reader.trackedFileCount() == 2)
    }

    @Test("Transcripts reached through a symlinked session folder are never followed")
    func symlinkedFolders() async throws {
        let fixture = try TranscriptFixture()
        let now = Date()
        try fixture.write([], to: fixture.mainTranscript)
        let elsewhere = fixture.directory.url.appendingPathComponent("elsewhere", isDirectory: true)
        let outsideAgent = elsewhere.appendingPathComponent("subagents/agent-x.jsonl")
        try fixture.write([assistantLine(requestID: "outside_old", at: now)], to: outsideAgent)
        let sessionFolder = fixture.projects.appendingPathComponent("\(TranscriptFixture.slug)/\(TranscriptFixture.sessionID)")
        try FileManager.default.createSymbolicLink(at: sessionFolder, withDestinationURL: elsewhere)

        let reader = fixture.reader()
        await reader.track([try fixture.session()], now: now)
        #expect(await reader.trackedFileCount() == 1)

        try fixture.append(lines: [assistantLine(requestID: "outside_new", output: 9, at: now.addingTimeInterval(1))], to: outsideAgent)
        let update = await reader.process(changedPaths: [fixture.subagent("agent-x.jsonl").path], now: now.addingTimeInterval(2))
        #expect(update.samples.isEmpty)
        #expect(await reader.trackedFileCount() == 1)
    }
}

@Suite("Claude transcript lines and paths")
struct ClaudeTranscriptLineTests {
    @Test("Only whitelisted fields are extracted")
    func parse() throws {
        let now = try date("2026-09-17T06:00:00Z")
        let record = try #require(ClaudeTranscriptLine.parse(Data(assistantLine(requestID: "req_x", at: now).utf8)))
        #expect(record.requestID == "req_x")
        #expect(record.model == "claude-opus-5")
        #expect(record.counts == (try TokenCounts(input: 2, cachedInput: 5_000, cacheWrite: 1_000, output: 100, reasoningOutput: 0)))
        #expect(record.timestamp == now)
        #expect(ClaudeTranscriptLine.parse(Data(#"{"message":{"usage":{}},"requestId":"r","type":"assistant"}"#.utf8)) == nil)
    }

    @Test("Model and identifier validation")
    func validation() {
        #expect(ClaudeTranscriptLine.model("claude-fable-5-1") == "claude-fable-5-1")
        #expect(ClaudeTranscriptLine.model("<synthetic>") == nil)
        #expect(ClaudeTranscriptLine.model("model with spaces") == nil)
        #expect(ClaudeTranscriptLine.model(String(repeating: "a", count: 61)) == nil)
        #expect(ClaudeTranscriptLine.identifier("req_011CX") == "req_011CX")
        #expect(ClaudeTranscriptLine.identifier("has space") == nil)
        #expect(ClaudeTranscriptLine.identifier("") == nil)
    }

    @Test("The request ledger forgets the oldest requests first")
    func ledger() throws {
        var ledger = RequestLedger(capacity: 2)
        let counts = try TokenCounts(input: 1, cachedInput: 0, cacheWrite: 0, output: 10, reasoningOutput: 0)
        #expect(ledger.record(id: "a", counts: counts) == counts)
        #expect(ledger.record(id: "a", counts: counts).isZero)
        _ = ledger.record(id: "b", counts: counts)
        _ = ledger.record(id: "c", counts: counts)
        #expect(ledger.count == 2)
        // "a" was evicted, so it counts again; "c" is still remembered.
        #expect(ledger.record(id: "a", counts: counts) == counts)
        #expect(ledger.record(id: "c", counts: counts).isZero)
        for index in 0..<50 {
            _ = ledger.record(id: "id\(index)", counts: counts)
        }
        #expect(ledger.count == 2)
    }

    @Test("Changed paths are classified relative to the projects directory")
    func classify() {
        let sid = TranscriptFixture.sessionID
        #expect(ClaudeTranscriptUsageReader.classify(["slug", "\(sid).jsonl"]) == .transcript(sessionID: sid, isMain: true))
        #expect(ClaudeTranscriptUsageReader.classify(["slug", sid, "subagents", "agent-1.jsonl"]) == .transcript(sessionID: sid, isMain: false))
        #expect(ClaudeTranscriptUsageReader.classify(["slug", sid, "subagents", "workflows", "wf", "a.jsonl"]) == .transcript(sessionID: sid, isMain: false))
        #expect(ClaudeTranscriptUsageReader.classify(["slug", sid, "subagents", "agent-1.meta.json"]) == .unrelated)
        #expect(ClaudeTranscriptUsageReader.classify(["slug", sid, "subagents", "workflows"]) == .directory(sessionID: sid))
        #expect(ClaudeTranscriptUsageReader.classify(["slug", sid, "subagents"]) == .directory(sessionID: sid))
        #expect(ClaudeTranscriptUsageReader.classify(["slug", sid]) == .directory(sessionID: sid))
        #expect(ClaudeTranscriptUsageReader.classify(["slug", sid, "tool-results", "x.jsonl"]) == .unrelated)
        #expect(ClaudeTranscriptUsageReader.classify(["slug", "memory.md"]) == .unrelated)
        #expect(ClaudeTranscriptUsageReader.classify(["slug"]) == .directory(sessionID: nil))
        #expect(ClaudeTranscriptUsageReader.classify([".DS_Store"]) == .unrelated)
        #expect(ClaudeTranscriptUsageReader.classify([]) == .directory(sessionID: nil))
    }

    @Test("Project slugs replace every non-alphanumeric UTF-16 unit")
    func slugs() {
        #expect(ClaudeTranscriptUsageReader.projectSlug(for: "/Users/me/Codometer") == "-Users-me-Codometer")
        #expect(ClaudeTranscriptUsageReader.projectSlug(for: "/Users/me/Мой.app") == "-Users-me-----app")
        #expect(ClaudeTranscriptUsageReader.transcriptSessionID(fileName: "abc-123.jsonl") == "abc-123")
        #expect(ClaudeTranscriptUsageReader.transcriptSessionID(fileName: "../x.jsonl") == nil)
        #expect(ClaudeTranscriptUsageReader.transcriptSessionID(fileName: "abc.json") == nil)
    }
}
