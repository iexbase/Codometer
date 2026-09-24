@testable import CodometerClaude
import CodometerCore
import CodometerPlatform
import Foundation
import Testing

@Suite("Claude session records")
struct ClaudeSessionRecordTests {
    private func decode(_ json: String) throws -> ClaudeSessionRecord {
        try JSONDecoder().decode(ClaudeSessionRecord.self, from: Data(json.utf8))
    }

    @Test("The entrypoint maps to the session origin", arguments: [
        (#""entrypoint":"cli","#, SessionOrigin.terminal),
        (#""entrypoint":"claude-desktop","#, SessionOrigin.desktopApp),
        (#""entrypoint":"sdk-ts","#, SessionOrigin.unknown),
        (#""entrypoint":42,"#, SessionOrigin.unknown),
        ("", SessionOrigin.unknown),
    ])
    func origin(fragment: String, expected: SessionOrigin) throws {
        let record = try decode(#"{\#(fragment)"pid":42,"sessionId":"s","status":"idle"}"#)
        #expect(record.origin == expected)
        #expect(record.pid == 42)
    }

    @Test("lastEventAt is the newer of updatedAt and statusUpdatedAt")
    func lastEventAt() throws {
        let both = try decode(#"{"pid":1,"updatedAt":1789614000000,"statusUpdatedAt":1789614060000}"#)
        #expect(both.lastEventAt == Date(timeIntervalSince1970: 1_789_614_060))
        let newerUpdate = try decode(#"{"pid":1,"updatedAt":1789614120000,"statusUpdatedAt":1789614060000}"#)
        #expect(newerUpdate.lastEventAt == Date(timeIntervalSince1970: 1_789_614_120))
        let onlyStatus = try decode(#"{"pid":1,"statusUpdatedAt":1789614060000}"#)
        #expect(onlyStatus.lastEventAt == Date(timeIntervalSince1970: 1_789_614_060))
        let none = try decode(#"{"pid":1,"updatedAt":"yesterday","startedAt":1789614000000}"#)
        #expect(none.lastEventAt == nil)
    }

    @Test("A real record shape decodes; unknown keys are ignored")
    func realShape() throws {
        let record = try decode(
            #"{"pid":2322,"sessionId":"0b7c7a1e-7f53-4c1c-9a64-4d3f0f8a2b11","cwd":"/Users/me/project","startedAt":1789610000000,"procStart":"x","version":"2.1.252","peerProtocol":1,"peerFeatures":[],"kind":"interactive","entrypoint":"claude-desktop","pidDomain":"x","messagingSocketPath":"/tmp/x","name":"Refactor","nameSince":1789610000000,"updatedAt":1789614000000,"status":"busy","statusUpdatedAt":1789613000000}"#
        )
        #expect(record.origin == .desktopApp)
        #expect(record.activity == .working)
        #expect(record.lastEventAt == Date(timeIntervalSince1970: 1_789_614_000))
        #expect(record.workingDirectory == "/Users/me/project")
    }

    @Test("Scanned sessions carry the origin and the record's last write time")
    func scannedSession() throws {
        let directory = try TemporaryDirectory()
        let config = directory.url.appendingPathComponent(".claude-test", isDirectory: true)
        let layout = ClaudeProfileLayout(configDirectory: config, homeDirectory: directory.url)
        try FileManager.default.createDirectory(at: layout.sessionsDirectory, withIntermediateDirectories: true)

        let pid = ProcessInfo.processInfo.processIdentifier
        let started = Int64((ProcessInspector.startTime(of: pid) ?? Date()).timeIntervalSince1970 * 1_000)
        let json = #"{"pid":\#(pid),"sessionId":"live","cwd":"/p","status":"busy","entrypoint":"cli","startedAt":\#(started),"statusUpdatedAt":\#(started + 1_000),"updatedAt":\#(started + 9_000)}"#
        try Data(json.utf8).write(to: layout.sessionsDirectory.appendingPathComponent("\(pid).json"))

        // A clock ahead of the record, so the test process's young start time is never clamped.
        let now = Date().addingTimeInterval(60)
        let session = try #require(ClaudeSessionScanner(layout: layout, ownProcesses: nil).scan(now: now).first)
        #expect(session.origin == .terminal)
        #expect(session.lastEventAt == Date(timeIntervalSince1970: TimeInterval(started + 9_000) / 1_000))
        #expect(session.activitySince == Date(timeIntervalSince1970: TimeInterval(started + 1_000) / 1_000))
        #expect(session.lastTurn == nil)
    }
}
