@testable import CodometerCodex
import CodometerCore
import Foundation
import Testing

/// Line shapes observed in codex-cli 0.154.0 rollouts (numbers only).
private enum Lines {
    static let mainLimits = #"{"timestamp":"2026-09-16T16:46:16.520Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":10,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":5,"reasoning_output_tokens":0,"total_tokens":15}},"rate_limits":{"limit_id":"codex","limit_name":null,"primary":{"used_percent":99.0,"window_minutes":10080,"resets_at":1789805414},"secondary":null,"credits":{"has_credits":false,"unlimited":false,"balance":"0"},"individual_limit":null,"spend_control_reached":null,"plan_type":"pro","rate_limit_reached_type":null}}}"#
    static let sparkLimits = #"{"timestamp":"2026-09-16T16:40:00.000Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"limit_id":"codex_bengalfox","limit_name":"GPT-5.3-Codex-Spark","primary":{"used_percent":12.0,"window_minutes":300,"resets_at":1789600000},"secondary":{"used_percent":3.0,"window_minutes":10080,"resets_at":1789805414},"credits":null,"plan_type":"pro","rate_limit_reached_type":"rate_limit_reached"}}}"#
    static let sessionMeta = #"{"timestamp":"2026-09-16T18:54:41.845Z","ordinal":0,"type":"session_meta","payload":{"session_id":"01a0ab92-37ce-7552-b4ad-ada1b6ba2f4c","id":"01a0ab92-37ce-7552-b4ad-ada1b6ba2f4c","cwd":"/Users/me/app","originator":"Codex Desktop","base_instructions":"long text"}}"#
    static let turnContext = #"{"timestamp":"2026-09-16T18:55:00.000Z","type":"turn_context","payload":{"cwd":"/Users/me/app","model":"gpt","turn_id":"t1"}}"#
    static func taskStarted(_ time: String) -> String {
        #"{"timestamp":"\#(time)","type":"event_msg","payload":{"type":"task_started","turn_id":"t1","started_at":1}}"#
    }
    static func taskComplete(_ time: String) -> String {
        #"{"timestamp":"\#(time)","type":"event_msg","payload":{"type":"task_complete","turn_id":"t1","duration_ms":5}}"#
    }
    static let conversation = #"{"timestamp":"2026-09-16T18:55:01.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"mentions token_count but is a prompt"}]}}"#
}

private func parse(_ line: String) -> CodexRolloutEvent? {
    CodexRolloutParser.parse(line: Data(line.utf8))
}

@Suite("Codex rollout parser")
struct CodexRolloutParserTests {
    @Test("token_count carries a rate-limit snapshot")
    func rateLimits() throws {
        guard case let .rateLimits(snapshot, at) = parse(Lines.mainLimits) else {
            Issue.record("expected rate limits")
            return
        }
        #expect(snapshot.limitID == "codex")
        #expect(snapshot.primary?.usedPercent == 99)
        #expect(snapshot.primary?.durationMinutes == 10_080)
        #expect(snapshot.primary?.resetsAt == Date(timeIntervalSince1970: 1_789_805_414))
        #expect(snapshot.secondary == nil)
        #expect(snapshot.credits?.balance == 0)
        #expect(snapshot.planType == "pro")
        #expect(!snapshot.isLimitReached)
        #expect(abs(at.timeIntervalSince1970 - 1_789_577_176.52) < 0.01)
    }

    @Test("Turn and session events")
    func events() {
        guard case .sessionStarted(let id, let cwd, let originator, _, _) = parse(Lines.sessionMeta) else {
            Issue.record("expected session start")
            return
        }
        #expect(id == "01a0ab92-37ce-7552-b4ad-ada1b6ba2f4c")
        #expect(cwd == "/Users/me/app")
        #expect(originator == "Codex Desktop")
        guard case .turnContext(let contextCWD, _, _, _, _, _, _) = parse(Lines.turnContext) else {
            Issue.record("expected turn context")
            return
        }
        #expect(contextCWD == "/Users/me/app")
        guard case .turnStarted = parse(Lines.taskStarted("2026-09-16T18:55:00Z")) else {
            Issue.record("expected turn start")
            return
        }
        guard case .turnCompleted = parse(Lines.taskComplete("2026-09-16T18:56:00.5Z")) else {
            Issue.record("expected turn completion")
            return
        }
    }

    @Test("Conversation content and malformed lines are ignored")
    func ignored() {
        #expect(parse(Lines.conversation) == nil)
        #expect(parse("{broken token_count") == nil)
        #expect(parse(#"{"type":"event_msg","payload":{"type":"token_count"}}"#) == nil)
    }

    @Test("Implausible reset timestamps are dropped rather than trusted")
    func implausibleReset() {
        let millisecondsByMistake = Lines.mainLimits.replacingOccurrences(of: "1789805414", with: "1789805414000")
        guard case .rateLimits(let snapshot, _) = parse(millisecondsByMistake) else {
            Issue.record("expected rate limits")
            return
        }
        #expect(snapshot.primary?.resetsAt == nil)
    }
}

@Suite("Codex limit mapping")
struct CodexLimitMapperTests {
    private func snapshot(_ line: String) throws -> CodexLimitSnapshot {
        guard case .rateLimits(let snapshot, _) = parse(line) else {
            throw CancellationError()
        }
        return snapshot
    }

    @Test("The main bucket comes first and windows keep their durations")
    func buckets() throws {
        let reading = try #require(CodexLimitMapper.reading(
            from: [try snapshot(Lines.sparkLimits), try snapshot(Lines.mainLimits)],
            capturedAt: Date(),
            source: .codexSessionLog
        ))
        #expect(reading.buckets.map(\.id) == ["codex", "codex_bengalfox"])
        #expect(reading.mainBucket.windows.map(\.id) == ["primary"])
        let spark = try #require(reading.bucket(id: "codex_bengalfox"))
        #expect(spark.title == "GPT-5.3-Codex-Spark")
        #expect(spark.windows.map { $0.duration?.minutes } == [300, 10_080])
        #expect(spark.isLimitReached)
    }

    @Test("Invalid percentages drop the window, not the reading")
    func invalidWindow() {
        let bad = CodexLimitSnapshot(
            limitID: "codex",
            limitName: nil,
            primary: .init(usedPercent: .nan, durationMinutes: 300, resetsAt: nil),
            secondary: .init(usedPercent: 20, durationMinutes: 10_080, resetsAt: nil),
            credits: nil,
            planType: nil,
            isLimitReached: false
        )
        let bucket = CodexLimitMapper.bucket(from: bad)
        #expect(bucket?.windows.map(\.id) == ["secondary"])
    }

    @Test("Unsafe limit ids are sanitised; plan names are humanised")
    func names() {
        let snapshot = CodexLimitSnapshot(limitID: "a b/c", limitName: nil, primary: nil, secondary: nil, credits: nil, planType: nil, isLimitReached: false)
        #expect(snapshot.bucketID == "a_b_c")
        #expect(CodexLimitMapper.planName("pro") == "Pro")
        #expect(CodexLimitMapper.planName("self_serve_business_prolite") == "Self Serve Business Prolite")
        #expect(CodexLimitMapper.planName("unknown") == nil)
    }
}

@Suite("Codex session log reader")
struct CodexSessionLogReaderTests {
    private func makeProfile() throws -> (TemporaryDirectory, CodexProfileLayout, URL) {
        let directory = try TemporaryDirectory()
        let home = directory.url.appendingPathComponent(".codex-test", isDirectory: true)
        let day = home.appendingPathComponent("sessions/2026/09/16", isDirectory: true)
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        let file = day.appendingPathComponent("rollout-2026-09-16T22-54-41-01a0ab92-37ce-7552-b4ad-ada1b6ba2f4c.jsonl")
        return (directory, CodexProfileLayout(home: home, homeDirectory: directory.url), file)
    }

    private func write(_ lines: [String], to file: URL, appending: Bool = false) throws {
        let text = lines.joined(separator: "\n") + "\n"
        if appending, let handle = try? FileHandle(forWritingTo: file) {
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(text.utf8))
            try handle.close()
        } else {
            try Data(text.utf8).write(to: file)
        }
    }

    @Test("Bootstrap reads sessions and limits; appended lines update them")
    func bootstrapAndAppend() async throws {
        let (directory, layout, file) = try makeProfile()
        _ = directory
        let now = try #require(ISO8601DateFormatter().date(from: "2026-09-16T18:56:30Z"))
        try write([Lines.sessionMeta, Lines.taskStarted("2026-09-16T18:55:00Z"), Lines.mainLimits, Lines.conversation], to: file)

        let reader = CodexSessionLogReader(layout: layout, accountID: AccountID())
        let first = await reader.bootstrap(now: now)
        #expect(first.sessions.count == 1)
        #expect(first.sessions.first?.activity == .working)
        #expect(first.sessions.first?.title == "app")
        #expect(first.reading?.mainBucket.windows.first?.used.value == 99)
        #expect(first.planType == "pro")

        try write([Lines.taskComplete("2026-09-16T18:56:10Z")], to: file, appending: true)
        let second = await reader.process(changedPaths: [file.path], now: now)
        #expect(second.sessions.first?.activity == .idle)
    }

    @Test("A turn without log activity for too long is treated as finished")
    func staleTurn() async throws {
        let (directory, layout, file) = try makeProfile()
        _ = directory
        try write([Lines.sessionMeta, Lines.taskStarted("2026-09-16T18:55:00Z")], to: file)
        let muchLater = try #require(ISO8601DateFormatter().date(from: "2026-09-16T19:40:00Z"))
        let reader = CodexSessionLogReader(layout: layout, accountID: AccountID())
        _ = await reader.bootstrap(now: muchLater)
        let snapshot = await reader.snapshot(now: muchLater)
        #expect(snapshot.sessions.allSatisfy { $0.activity == .idle })
    }

    @Test("Buckets whose window already reset are not reported")
    func expiredBuckets() async throws {
        let (directory, layout, file) = try makeProfile()
        _ = directory
        try write([Lines.mainLimits, Lines.sparkLimits], to: file)
        // After the Spark 5-hour window reset (1789600000) but before the weekly reset.
        let afterSparkReset = Date(timeIntervalSince1970: 1_789_600_100)
        let reader = CodexSessionLogReader(layout: layout, accountID: AccountID())
        let snapshot = await reader.bootstrap(now: afterSparkReset)
        #expect(snapshot.reading?.buckets.map(\.id) == ["codex"])
    }

    @Test("Paths outside the profile or with other names are ignored")
    func ignoresForeignPaths() async throws {
        let (directory, layout, _) = try makeProfile()
        _ = directory
        let reader = CodexSessionLogReader(layout: layout, accountID: AccountID())
        let snapshot = await reader.process(changedPaths: ["/etc/passwd", layout.sessionsDirectory.path + "/notes.txt"], now: Date())
        #expect(snapshot.sessions.isEmpty)
        #expect(snapshot.reading == nil)
    }

    @Test("Session ids come from rollout file names")
    func sessionIDs() {
        #expect(CodexSessionLogReader.sessionID(fromFileName: "rollout-2026-09-16T22-54-41-01a0ab92-37ce-7552-b4ad-ada1b6ba2f4c.jsonl") == "01a0ab92-37ce-7552-b4ad-ada1b6ba2f4c")
        #expect(CodexSessionLogReader.isRolloutFileName("rollout-x.jsonl"))
        #expect(!CodexSessionLogReader.isRolloutFileName("rollout-x.jsonl.zst"))
    }

    @Test("CODEX_HOME is set only for named profiles; signed binaries come first")
    func layout() {
        let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
        #expect(CodexProfileLayout(home: home.appendingPathComponent(".codex"), homeDirectory: home).environmentOverrides.isEmpty)
        #expect(CodexProfileLayout(home: home.appendingPathComponent(".codex-2"), homeDirectory: home).environmentOverrides == ["CODEX_HOME": "/Users/me/.codex-2"])
        #expect(CodexProfileLayout.executableCandidates(homeDirectory: home).first?.path == "/Applications/ChatGPT.app/Contents/Resources/codex")
        #expect(CodexAppServerProbe.isAuthenticationError("codex account authentication required to read rate limits"))
    }
}
