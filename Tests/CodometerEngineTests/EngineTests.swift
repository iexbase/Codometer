import CodometerCore
@testable import CodometerEngine
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

private let now = Date(timeIntervalSince1970: 1_789_600_000)

private func reading(_ buckets: [(String, Double, TimeInterval)], at date: Date, source: ReadingSource = .codexAppServer) throws -> UsageReading {
    try UsageReading(
        capturedAt: date,
        source: source,
        buckets: try buckets.map { id, used, resetsIn in
            try LimitBucket(
                id: id,
                title: nil,
                windows: [try LimitWindow(
                    id: "primary",
                    scope: .rolling,
                    used: try Percentage(validating: used),
                    duration: .fiveHours,
                    resetsAt: now.addingTimeInterval(resetsIn)
                )],
                isLimitReached: false
            )
        },
        credits: nil
    )
}

@Suite("Refresh schedule")
struct RefreshScheduleTests {
    @Test("Failures back off exponentially up to the cap")
    func backoff() throws {
        let interval = try PollInterval(seconds: 180)
        #expect(RefreshSchedule.delay(interval: interval, consecutiveFailures: 0, jitter: 0) == 180)
        #expect(RefreshSchedule.delay(interval: interval, consecutiveFailures: 1, jitter: 0) == 360)
        #expect(RefreshSchedule.delay(interval: interval, consecutiveFailures: 3, jitter: 0) == 1_440)
        #expect(RefreshSchedule.delay(interval: interval, consecutiveFailures: 50, jitter: 0) == RefreshSchedule.maximumBackoff)
        let hourly = try PollInterval(seconds: 3_600)
        #expect(RefreshSchedule.delay(interval: hourly, consecutiveFailures: 2, jitter: 0) == 3_600)
    }

    @Test("Jitter stays within ±10 %")
    func jitter() throws {
        let interval = try PollInterval(seconds: 300)
        #expect(RefreshSchedule.delay(interval: interval, consecutiveFailures: 0, jitter: 1) == 330)
        #expect(RefreshSchedule.delay(interval: interval, consecutiveFailures: 0, jitter: -1) == 270)
    }

    @Test("Refreshes are brought forward to just after the next reset")
    func resetWakeUp() throws {
        let soon = try reading([("codex", 50, 100)], at: now)
        #expect(RefreshSchedule.delay(600, wakingForResetsIn: soon, now: now) == 130)
        let later = try reading([("codex", 50, 10_000)], at: now)
        #expect(RefreshSchedule.delay(600, wakingForResetsIn: later, now: now) == 600)
    }

    @Test("Nearly exhausted limits refresh more often")
    func urgency() throws {
        let urgent = try reading([("codex", 95, 10_000)], at: now)
        #expect(RefreshSchedule.delay(600, urgentAbove: 90, cap: 60, reading: urgent) == 60)
        let calm = try reading([("codex", 40, 10_000)], at: now)
        #expect(RefreshSchedule.delay(600, urgentAbove: 90, cap: 60, reading: calm) == 600)
        let exhausted = try reading([("codex", 100, 10_000)], at: now)
        #expect(RefreshSchedule.delay(600, urgentAbove: 90, cap: 60, reading: exhausted) == 600)
    }
}

@Suite("Reading merger")
struct ReadingMergerTests {
    @Test("A newer partial reading keeps buckets it does not mention")
    func carriesMissingBuckets() throws {
        let live = try reading([("codex", 40, 10_000), ("codex_bengalfox", 10, 10_000)], at: now)
        let log = try reading([("codex", 45, 10_000)], at: now.addingTimeInterval(30), source: .codexSessionLog)
        let merged = try #require(ReadingMerger.merge(current: live, incoming: log, now: now.addingTimeInterval(30)))
        #expect(merged.buckets.map(\.id) == ["codex", "codex_bengalfox"])
        #expect(merged.mainBucket.windows.first?.used.value == 45)
        #expect(merged.source == .codexSessionLog)
    }

    @Test("An older reading only contributes buckets the current one lacks")
    func olderReading() throws {
        let current = try reading([("codex", 45, 10_000)], at: now)
        let older = try reading([("codex", 10, 10_000), ("codex_bengalfox", 5, 10_000)], at: now.addingTimeInterval(-60))
        let merged = try #require(ReadingMerger.merge(current: current, incoming: older, now: now))
        #expect(merged.mainBucket.windows.first?.used.value == 45)
        #expect(merged.buckets.count == 2)

        let redundant = try reading([("codex", 10, 10_000)], at: now.addingTimeInterval(-60))
        #expect(ReadingMerger.merge(current: current, incoming: redundant, now: now) == nil)
    }

    @Test("Buckets whose windows reset are not carried over")
    func expiredNotCarried() throws {
        let live = try reading([("codex", 40, 10_000), ("codex_bengalfox", 90, 10)], at: now)
        let log = try reading([("codex", 41, 10_000)], at: now.addingTimeInterval(60))
        let merged = try #require(ReadingMerger.merge(current: live, incoming: log, now: now.addingTimeInterval(60)))
        #expect(merged.buckets.map(\.id) == ["codex"])
    }
}

@Suite("Profile discovery")
struct ProfileDiscoveryTests {
    @Test("Finds real profiles and ignores look-alike folders")
    func discovery() throws {
        let home = try TemporaryDirectory()
        let fileManager = FileManager.default
        func make(_ path: String) throws {
            try fileManager.createDirectory(at: home.url.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        try make(".claude/projects")
        try Data("{}".utf8).write(to: home.url.appendingPathComponent(".claude.json"))
        try make(".claude-work/sessions")
        try make(".claude-mem/cache")
        try make(".codex/sessions")
        try make(".codex-personal")
        try Data("{}".utf8).write(to: home.url.appendingPathComponent(".codex-personal/config.toml"))
        try make(".codex-bad name/sessions")

        let found = ProfileDiscovery.discover(homeDirectory: home.url)
        #expect(found.map { "\($0.provider.rawValue):\($0.variant ?? "-")" } == ["claude:-", "claude:work", "codex:-", "codex:personal"])

        let accounts = ProfileDiscovery.initialAccounts(homeDirectory: home.url)
        #expect(accounts.map(\.label.value) == ["Claude", "Claude · work", "Codex", "Codex · personal"])
        #expect(try AppSettings(accounts: accounts).accounts.count == 4)
    }

    @Test("Variant names are validated")
    func variants() {
        #expect(ProfileDiscovery.variant(of: ".claude", provider: .claude) == "")
        #expect(ProfileDiscovery.variant(of: ".claude-work", provider: .claude) == "work")
        #expect(ProfileDiscovery.variant(of: ".claude-", provider: .claude) == nil)
        #expect(ProfileDiscovery.variant(of: ".claudette", provider: .claude) == nil)
        #expect(ProfileDiscovery.variant(of: ".codex-a/b", provider: .codex) == nil)
    }
}
