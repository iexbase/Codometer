import CodometerCore
import CodometerStorage
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

    func file(_ name: String) -> URL {
        url.appendingPathComponent(name, isDirectory: false)
    }
}

private func sampleSettings() throws -> AppSettings {
    let account = try AccountProfile(
        provider: .codex,
        label: try AccountLabel(validating: "Codex"),
        directory: try ProfileDirectory(validating: "/Users/me/.codex")
    )
    return try AppSettings(accounts: [account])
}

private func reading(used: Double, capturedAt: Date, resetsAt: Date) throws -> UsageReading {
    let window = try LimitWindow(
        id: "primary",
        scope: .rolling,
        used: try Percentage(validating: used),
        duration: .oneWeek,
        resetsAt: resetsAt
    )
    return try UsageReading(
        capturedAt: capturedAt,
        source: .codexAppServer,
        buckets: [try LimitBucket(id: "codex", title: nil, windows: [window], isLimitReached: false)],
        credits: CreditsInfo(hasCredits: false, isUnlimited: false, balance: 0)
    )
}

@Suite("Settings store")
struct SettingsStoreTests {
    @Test("A missing file is reported, not treated as an error")
    func missing() throws {
        let directory = try TemporaryDirectory()
        guard case .missing = SettingsStore(fileURL: directory.file("settings.json")).load() else {
            Issue.record("expected .missing")
            return
        }
    }

    @Test("Saved settings load back identically")
    func roundTrip() throws {
        let directory = try TemporaryDirectory()
        let store = SettingsStore(fileURL: directory.file("settings.json"))
        let settings = try sampleSettings()
        try store.save(settings)
        guard case .loaded(let loaded, let repairs) = store.load() else {
            Issue.record("expected .loaded")
            return
        }
        #expect(loaded == settings)
        #expect(repairs.isEmpty)
    }

    // Files that are JSON objects are repaired instead (see SettingsStoreOutcomeTests); only unusable files move aside.
    @Test("Invalid files are moved aside instead of crashing or being overwritten silently", arguments: [
        "not json at all",
        #"[{"schemaVersion":1}]"#,
        #""settings""#,
    ])
    func recovery(_ contents: String) throws {
        let directory = try TemporaryDirectory()
        let file = directory.file("settings.json")
        try Data(contents.utf8).write(to: file)
        guard case .recovered(let backupPath, _) = SettingsStore(fileURL: file).load() else {
            Issue.record("expected .recovered")
            return
        }
        #expect(FileManager.default.fileExists(atPath: backupPath))
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}

@Suite("Usage history")
struct UsageHistoryStoreTests {
    @Test("Readings are restored after reopening the database")
    func restore() async throws {
        let directory = try TemporaryDirectory()
        let database = directory.file("history.sqlite")
        let accountID = AccountID()
        let now = Date(timeIntervalSince1970: 1_789_600_000)
        let identity = AccountIdentity(email: "me@example.com", organization: nil, plan: "Pro")

        do {
            let store = try UsageHistoryStore(databaseURL: database)
            try await store.record(try reading(used: 42, capturedAt: now, resetsAt: now.addingTimeInterval(3_600)), identity: identity, for: accountID)
        }
        let reopened = try UsageHistoryStore(databaseURL: database)
        let restored = try #require(try await reopened.restoredStates()[accountID])
        #expect(restored.identity == identity)
        #expect(restored.reading?.mainBucket.windows.first?.used.value == 42)
    }

    @Test("Unchanged values are not stored twice, changes and heartbeats are")
    func deduplication() async throws {
        let directory = try TemporaryDirectory()
        let store = try UsageHistoryStore(databaseURL: directory.file("history.sqlite"))
        let accountID = AccountID()
        let start = Date(timeIntervalSince1970: 1_789_600_000)
        let reset = start.addingTimeInterval(7 * 24 * 3_600)

        try await store.record(try reading(used: 10, capturedAt: start, resetsAt: reset), identity: nil, for: accountID)
        try await store.record(try reading(used: 10, capturedAt: start.addingTimeInterval(60), resetsAt: reset), identity: nil, for: accountID)
        try await store.record(try reading(used: 11, capturedAt: start.addingTimeInterval(120), resetsAt: reset), identity: nil, for: accountID)
        try await store.record(try reading(used: 11, capturedAt: start.addingTimeInterval(120 + 31 * 60), resetsAt: reset), identity: nil, for: accountID)

        let samples = try await store.samples(accountID: accountID, bucketID: "codex", windowID: "primary", since: start)
        #expect(samples.map(\.used.value) == [10, 11, 11])
    }

    @Test("Removing an account deletes its history")
    func removeAccount() async throws {
        let directory = try TemporaryDirectory()
        let store = try UsageHistoryStore(databaseURL: directory.file("history.sqlite"))
        let accountID = AccountID()
        let now = Date(timeIntervalSince1970: 1_789_600_000)
        try await store.record(try reading(used: 5, capturedAt: now, resetsAt: now.addingTimeInterval(60)), identity: nil, for: accountID)
        try await store.removeAccount(accountID)
        #expect(try await store.restoredStates().isEmpty)
        #expect(try await store.samples(accountID: accountID, bucketID: "codex", windowID: "primary", since: .distantPast).isEmpty)
    }

    @Test("Old samples are pruned")
    func prune() async throws {
        let directory = try TemporaryDirectory()
        let store = try UsageHistoryStore(databaseURL: directory.file("history.sqlite"))
        let accountID = AccountID()
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.record(try reading(used: 5, capturedAt: old, resetsAt: old.addingTimeInterval(60)), identity: nil, for: accountID)
        try await store.prune(now: old.addingTimeInterval(UsageHistoryStore.defaultRetention + 1))
        #expect(try await store.samples(accountID: accountID, bucketID: "codex", windowID: "primary", since: .distantPast).isEmpty)
    }
}
