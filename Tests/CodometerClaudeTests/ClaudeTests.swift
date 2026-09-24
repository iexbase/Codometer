@testable import CodometerClaude
import CodometerCore
import CodometerPlatform
import Foundation
import Testing

final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codometer-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

func date(_ text: String) throws -> Date {
    try #require(ISO8601DateFormatter().date(from: text))
}

@Suite("Claude sessions")
struct ClaudeSessionScannerTests {
    private func layout(in directory: TemporaryDirectory) throws -> ClaudeProfileLayout {
        let config = directory.url.appendingPathComponent(".claude-test", isDirectory: true)
        try FileManager.default.createDirectory(at: config.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        return ClaudeProfileLayout(configDirectory: config, homeDirectory: directory.url)
    }

    private func writeRecord(_ json: String, name: String, layout: ClaudeProfileLayout) throws {
        try Data(json.utf8).write(to: layout.sessionsDirectory.appendingPathComponent(name))
    }

    private var currentProcess: (pid: Int32, startedAtMilliseconds: Int64) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let start = ProcessInspector.startTime(of: pid) ?? Date()
        return (pid, Int64(start.timeIntervalSince1970 * 1_000))
    }

    @Test("Live sessions are read with their activity; dead, foreign and secret files are skipped")
    func scan() throws {
        let directory = try TemporaryDirectory()
        let layout = try layout(in: directory)
        let (pid, started) = currentProcess

        try writeRecord(
            #"{"pid":\#(pid),"sessionId":"live","cwd":"/Users/me/project","status":"busy","startedAt":\#(started),"statusUpdatedAt":\#(started + 5_000)}"#,
            name: "\(pid).json",
            layout: layout
        )
        try writeRecord(#"{"pid":999999,"sessionId":"dead","cwd":"/x","status":"busy"}"#, name: "999999.json", layout: layout)
        try writeRecord("secret", name: "\(pid).abcdef.key", layout: layout)
        try writeRecord("{not json", name: "123.json", layout: layout)

        let sessions = ClaudeSessionScanner(layout: layout, ownProcesses: nil).scan(now: Date())
        #expect(sessions.map(\.id) == ["live"])
        #expect(sessions.first?.activity == .working)
        #expect(sessions.first?.title == "project")
        #expect(sessions.first?.processID == pid)
    }

    @Test("tempo overrides status, and the waiting reason is kept")
    func waiting() throws {
        let directory = try TemporaryDirectory()
        let layout = try layout(in: directory)
        let (pid, started) = currentProcess
        try writeRecord(
            #"{"pid":\#(pid),"sessionId":"s","cwd":"/p","status":"busy","tempo":"blocked","waitingFor":"permission prompt","startedAt":\#(started),"name":"Refactor"}"#,
            name: "\(pid).json",
            layout: layout
        )
        let session = try #require(ClaudeSessionScanner(layout: layout, ownProcesses: nil).scan(now: Date()).first)
        #expect(session.activity == .waiting)
        #expect(session.detail == "permission prompt")
        #expect(session.title == "Refactor")
    }

    @Test("A reused PID with a different start time is not treated as the session")
    func pidReuse() throws {
        let directory = try TemporaryDirectory()
        let layout = try layout(in: directory)
        let (pid, started) = currentProcess
        let yearEarlier = started - 365 * 24 * 3_600 * 1_000
        try writeRecord(#"{"pid":\#(pid),"sessionId":"old","cwd":"/p","status":"busy","startedAt":\#(yearEarlier)}"#, name: "\(pid).json", layout: layout)
        #expect(ClaudeSessionScanner(layout: layout, ownProcesses: nil).scan(now: Date()).isEmpty)
    }

    @Test("Sessions started by the app's own probes are ignored")
    func ownProcesses() throws {
        let directory = try TemporaryDirectory()
        let layout = try layout(in: directory)
        let (pid, started) = currentProcess
        try writeRecord(#"{"pid":\#(pid),"sessionId":"probe","cwd":"/p","status":"busy","startedAt":\#(started)}"#, name: "\(pid).json", layout: layout)
        let registry = ChildProcessRegistry()
        registry.insert(pid)
        #expect(ClaudeSessionScanner(layout: layout, ownProcesses: registry).scan(now: Date()).isEmpty)
    }

    @Test("Only digit-named JSON files are session records")
    func recordNames() {
        #expect(ClaudeSessionScanner.isRecordFileName("48306.json"))
        #expect(!ClaudeSessionScanner.isRecordFileName("48306.abc.key"))
        #expect(!ClaudeSessionScanner.isRecordFileName("abc.json"))
        #expect(!ClaudeSessionScanner.isRecordFileName(".json"))
    }
}

@Suite("Claude profiles and accounts")
struct ClaudeProfileTests {
    @Test("CLAUDE_CONFIG_DIR is set only for named profiles")
    func environment() {
        let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
        let defaultProfile = ClaudeProfileLayout(configDirectory: home.appendingPathComponent(".claude"), homeDirectory: home)
        let named = ClaudeProfileLayout(configDirectory: home.appendingPathComponent(".claude-work"), homeDirectory: home)
        #expect(defaultProfile.isDefault)
        #expect(defaultProfile.environmentOverrides.isEmpty)
        #expect(defaultProfile.accountStateFile.path == "/Users/me/.claude.json")
        #expect(!named.isDefault)
        #expect(named.environmentOverrides == ["CLAUDE_CONFIG_DIR": "/Users/me/.claude-work"])
        #expect(named.accountStateFile.path == "/Users/me/.claude-work/.claude.json")
    }

    @Test("Identity comes from oauthAccount metadata")
    func identity() throws {
        let directory = try TemporaryDirectory()
        let config = directory.url.appendingPathComponent(".claude-work", isDirectory: true)
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        let layout = ClaudeProfileLayout(configDirectory: config, homeDirectory: directory.url)

        #expect(try ClaudeAccountReader.identity(for: layout) == nil)

        try Data(#"{"numStartups":3,"oauthAccount":{"emailAddress":"me@example.com","organizationName":"Me","organizationType":"claude_max","organizationRateLimitTier":"default_claude_max_20x"}}"#.utf8)
            .write(to: layout.accountStateFile)
        let identity = try #require(try ClaudeAccountReader.identity(for: layout))
        #expect(identity.email == "me@example.com")
        #expect(identity.plan == "Max 20x")

        try Data("{broken".utf8).write(to: layout.accountStateFile)
        #expect(throws: ClaudeAccountReadError.malformed) { try ClaudeAccountReader.identity(for: layout) }
    }

    @Test("Plan names from tiers and organisation types")
    func planNames() {
        #expect(ClaudeAccountReader.planName(tier: "default_claude_max_5x", organizationType: nil) == "Max 5x")
        #expect(ClaudeAccountReader.planName(tier: nil, organizationType: "claude_pro") == "Pro")
        #expect(ClaudeAccountReader.planName(tier: "unknown", organizationType: "other") == nil)
    }

    @Test("Probe errors map to issue kinds")
    func issueKinds() {
        #expect(ClaudeProbeError.executable(.notFound(searched: [])).issueKind == .executableMissing)
        #expect(ClaudeProbeError.output(.signedOut).issueKind == .signedOut)
        #expect(ClaudeProbeError.output(.noLimitLines).issueKind == .unexpectedOutput)
        #expect(ClaudeProbeError.process(.timedOut(seconds: 1)).issueKind == .timedOut)
    }
}
