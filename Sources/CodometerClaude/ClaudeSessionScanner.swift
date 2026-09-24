import CodometerCore
import CodometerPlatform
import Foundation
import os

/// The subset of Claude Code's `sessions/<pid>.json` record the app relies on.
///
/// Each optional field is decoded independently, so a field that changes type in a future
/// Claude Code version drops only that field instead of the whole session.
struct ClaudeSessionRecord: Decodable, Sendable {
    let pid: Int32
    let sessionID: String?
    let workingDirectory: String?
    let name: String?
    let status: String?
    let tempo: String?
    let waitingFor: String?
    let startedAt: Date?
    let updatedAt: Date?
    let statusUpdatedAt: Date?
    /// Raw `entrypoint`: `cli` for the terminal, `claude-desktop` for the desktop app.
    let entrypoint: String?

    private enum CodingKeys: String, CodingKey {
        case pid, sessionId, cwd, name, status, tempo, waitingFor, needs, startedAt, updatedAt, statusUpdatedAt
        case entrypoint
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawPID = try container.decode(Int64.self, forKey: .pid)
        guard rawPID > 0, rawPID <= Int64(Int32.max) else {
            throw DecodingError.dataCorruptedError(forKey: .pid, in: container, debugDescription: "pid out of range")
        }
        pid = Int32(rawPID)
        sessionID = Self.string(container, .sessionId)
        workingDirectory = Self.string(container, .cwd).flatMap { $0.hasPrefix("/") ? $0 : nil }
        name = Self.string(container, .name)
        status = Self.string(container, .status)
        tempo = Self.string(container, .tempo)
        waitingFor = Self.string(container, .waitingFor) ?? Self.string(container, .needs)
        startedAt = Self.milliseconds(container, .startedAt)
        updatedAt = Self.milliseconds(container, .updatedAt)
        statusUpdatedAt = Self.milliseconds(container, .statusUpdatedAt)
        entrypoint = Self.string(container, .entrypoint)
    }

    /// Where the session runs; unknown entrypoints (SDK, IDE extensions, future values) stay `.unknown`.
    var origin: SessionOrigin {
        switch entrypoint {
        case "cli": .terminal
        case "claude-desktop": .desktopApp
        default: .unknown
        }
    }

    /// The newest time Claude Code wrote the record, when known.
    var lastEventAt: Date? {
        switch (updatedAt, statusUpdatedAt) {
        case let (updated?, status?): max(updated, status)
        case let (updated?, nil): updated
        case let (nil, status?): status
        case (nil, nil): nil
        }
    }

    /// `tempo` is the newer, more precise signal; `status` is the fallback.
    var activity: AgentActivity {
        switch tempo {
        case "blocked": return .waiting
        case "active": return .working
        case "idle": return .idle
        default: break
        }
        switch status {
        case "waiting": return .waiting
        case "busy": return .working
        default: return .idle
        }
    }

    private static func string(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
        (try? container.decodeIfPresent(String.self, forKey: key)) ?? nil
    }

    /// Epoch milliseconds between 2020 and 2100; anything else is treated as absent.
    private static func milliseconds(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Date? {
        guard let value = (try? container.decodeIfPresent(Double.self, forKey: key)) ?? nil else { return nil }
        guard value.isFinite, (1_577_836_800_000...4_102_444_800_000).contains(value) else { return nil }
        return Date(timeIntervalSince1970: value / 1_000)
    }
}

/// Reads the live Claude Code sessions of one profile.
public struct ClaudeSessionScanner: Sendable {
    public static let maximumRecordBytes = 64 * 1_024
    public static let maximumSessions = 64
    /// A process whose kernel start time differs more than this from the record is a different process with a reused PID.
    static let processStartTolerance: TimeInterval = 5 * 60

    private let layout: ClaudeProfileLayout
    private let ownProcesses: ChildProcessRegistry?

    public init(layout: ClaudeProfileLayout, ownProcesses: ChildProcessRegistry?) {
        self.layout = layout
        self.ownProcesses = ownProcesses
    }

    /// Unreadable or dead records are skipped; a missing sessions directory yields no sessions.
    public func scan(now: Date) -> [AgentSession] {
        let names: [String]
        do {
            names = try SecureFileIO.regularFileNames(in: layout.sessionsDirectory)
        } catch {
            AppLog.claude.error("cannot list sessions: \(error.description, privacy: .private)")
            return []
        }

        var newestBySession: [String: (session: AgentSession, startedAt: Date)] = [:]
        for name in names where Self.isRecordFileName(name) {
            let url = layout.sessionsDirectory.appendingPathComponent(name, isDirectory: false)
            guard
                let record = readRecord(at: url),
                ownProcesses?.contains(record.pid) != true,
                isRunning(record),
                let session = makeSession(from: record, recordURL: url, now: now)
            else { continue }
            let startedAt = record.startedAt ?? .distantPast
            if let existing = newestBySession[session.id], existing.startedAt >= startedAt { continue }
            newestBySession[session.id] = (session, startedAt)
        }

        return newestBySession.values
            .map(\.session)
            .sorted { lhs, rhs in
                lhs.activity != rhs.activity ? lhs.activity > rhs.activity : lhs.activitySince > rhs.activitySince
            }
            .prefix(Self.maximumSessions)
            .map { $0 }
    }

    /// Only `<digits>.json`; the `.key` files next to them hold secrets and are never opened.
    static func isRecordFileName(_ name: String) -> Bool {
        guard name.hasSuffix(".json") else { return false }
        let stem = name.dropLast(5)
        return !stem.isEmpty && stem.count <= 10 && stem.allSatisfy { $0.isASCII && $0.isNumber }
    }

    private func readRecord(at url: URL) -> ClaudeSessionRecord? {
        do {
            let data = try SecureFileIO.readRegularFile(at: url, maximumBytes: Self.maximumRecordBytes)
            return try JSONDecoder().decode(ClaudeSessionRecord.self, from: data)
        } catch {
            return nil
        }
    }

    private func isRunning(_ record: ClaudeSessionRecord) -> Bool {
        guard ProcessInspector.isAlive(record.pid) else { return false }
        guard let recordedStart = record.startedAt, let kernelStart = ProcessInspector.startTime(of: record.pid) else {
            return true
        }
        return abs(kernelStart.timeIntervalSince(recordedStart)) <= Self.processStartTolerance
    }

    private func makeSession(from record: ClaudeSessionRecord, recordURL: URL, now: Date) -> AgentSession? {
        let since = record.statusUpdatedAt ?? record.updatedAt ?? record.startedAt
            ?? SecureFileIO.metadata(at: recordURL)?.modifiedAt ?? now
        return try? AgentSession(
            id: record.sessionID ?? "pid-\(record.pid)",
            title: record.name,
            projectPath: record.workingDirectory,
            activity: record.activity,
            detail: record.activity == .waiting ? record.waitingFor : nil,
            activitySince: min(since, now),
            processID: record.pid,
            origin: record.origin,
            lastEventAt: record.lastEventAt.map { min($0, now) }
        )
    }
}
