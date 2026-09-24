import CodometerCore
import CodometerPlatform
import Darwin
import Foundation

/// What one burst of transcript changes produced.
public struct ClaudeTranscriptUpdate: Hashable, Sendable {
    /// Tokens spent since the previous update, at most one sample per session, model and minute.
    public let samples: [TokenSample]
    /// Session id → the newest activity seen in the session's transcripts during this burst.
    public let lastEventAt: [String: Date]

    public init(samples: [TokenSample], lastEventAt: [String: Date]) {
        self.samples = samples
        self.lastEventAt = lastEventAt
    }

    public static let empty = ClaudeTranscriptUpdate(samples: [], lastEventAt: [:])

    public var isEmpty: Bool { samples.isEmpty && lastEventAt.isEmpty }
}

/// Follows the transcripts of live Claude Code sessions and turns appended usage into token samples.
///
/// - Only sessions passed to `track(_:now:)` are read. Their transcripts are
///   `<profile>/projects/<slug>/<sessionId>.jsonl` and `<slug>/<sessionId>/subagents/**/*.jsonl`.
/// - Counting is live only: a file that existed when its session was first tracked starts at its end, so a
///   restart never counts old lines again. A file created later (a new transcript or subagent) is read from
///   its start, but lines stamped before the session was first tracked are history copied by a resume or a
///   fork and are skipped.
/// - Lines are byte-prefiltered and only whitelisted numeric and id fields are decoded (`ClaudeTranscriptLine`).
/// - Repeated blocks of one API request count once (`RequestLedger`). The ledger is shared by all sessions of
///   the account: a resumed or forked session copies earlier responses with their request ids into its own
///   transcript, and those copies must not count again.
/// - At most `maximumFilesPerSession` files per session are followed; a new file replaces the one that has been
///   quiet the longest, whose cursor is remembered so a later append resumes exactly where reading stopped.
public actor ClaudeTranscriptUsageReader {
    /// The directory-event latency monitors should use: usage needs no sub-second freshness.
    public static let eventLatency: TimeInterval = 2
    static let maximumReadBytes: UInt64 = 8 * 1_024 * 1_024
    /// Longer lines are skipped undecoded. Real assistant usage lines stay far below this.
    static let maximumLineBytes = 1_024 * 1_024
    static let maximumTrackedSessions = 64
    static let maximumFilesPerSession = 256
    /// Cursors of files set aside to make room for newer ones, across all sessions.
    static let maximumRetiredFiles = 1_024
    /// Request ids remembered across the account's sessions (hours of heavy use).
    static let ledgerCapacity = 4_096
    static let maximumProjectDirectories = 4_096
    /// Deepest subagent transcript below `subagents/` (`workflows/<run>/<agent>.jsonl`).
    static let maximumSubagentDepth = 3
    /// Directories visited per session when listing subagent transcripts.
    static let maximumSubagentDirectories = 128
    /// Lines stamped this long before a session was first tracked are copied history, not live usage.
    /// Claude Code stamps a block when it is produced and may write it minutes later (observed up to ~3 min).
    static let historyTolerance: TimeInterval = 5 * 60
    /// An ended session's files are still read this long, so its final burst is not lost.
    static let endedSessionGrace: TimeInterval = 30

    public nonisolated let projectsDirectory: URL
    private let accountID: AccountID
    private let roots: [String]
    private let maximumFilesPerSession: Int

    private struct SessionState {
        var project: String?
        let trackedSince: Date
        var endedAt: Date?
        /// `<slug>` of the directory holding the main transcript, once found.
        var slug: String?
    }

    private struct FileState {
        let sessionID: String
        var cursor: TailCursor?
        /// When the file was adopted or last yielded lines; the quietest file is set aside first.
        var lastActivityAt: Date
    }

    private struct RetiredFile {
        let sessionID: String
        let cursor: TailCursor?
        let serial: UInt64
    }

    private struct SampleKey: Hashable {
        let sessionID: String
        let model: String?
        let minute: Int64
    }

    private var sessions: [String: SessionState] = [:]
    /// Relative path below `projectsDirectory` → read state.
    private var files: [String: FileState] = [:]
    /// Relative path → where reading stopped before the file was set aside.
    private var retiredFiles: [String: RetiredFile] = [:]
    private var retiredSerial: UInt64 = 0
    private var ledger = RequestLedger(capacity: ClaudeTranscriptUsageReader.ledgerCapacity)

    public init(projectsDirectory: URL, accountID: AccountID) {
        self.init(projectsDirectory: projectsDirectory, accountID: accountID, maximumFilesPerSession: Self.maximumFilesPerSession)
    }

    init(projectsDirectory: URL, accountID: AccountID, maximumFilesPerSession: Int) {
        let standardized = projectsDirectory.standardizedFileURL
        self.projectsDirectory = standardized
        self.accountID = accountID
        self.maximumFilesPerSession = max(maximumFilesPerSession, 1)
        // Directory events and enumeration can spell the same directory differently (/var vs /private/var).
        roots = Array(Set([standardized.path, standardized.resolvingSymlinksInPath().path]))
    }

    public init(layout: ClaudeProfileLayout, accountID: AccountID) {
        self.init(projectsDirectory: layout.projectsDirectory, accountID: accountID)
    }

    // MARK: - Sessions

    /// Makes `sessions` the set of live sessions. New sessions get their existing transcripts primed at their
    /// ends; sessions that disappeared are dropped after a short grace period.
    /// Returns, for sessions seen for the first time, when their transcripts were last written, so a session that is
    /// already busy at launch does not look silent until its next write.
    @discardableResult
    public func track(_ liveSessions: [AgentSession], now: Date) -> [String: Date] {
        var liveIDs = Set<String>()
        var primedActivity: [String: Date] = [:]
        for session in liveSessions where Self.isTranscriptSessionID(session.id) {
            guard liveIDs.count < Self.maximumTrackedSessions else { break }
            liveIDs.insert(session.id)
            let project = session.projectPath
                .map { ($0 as NSString).lastPathComponent }
                .flatMap { $0.isEmpty ? nil : $0 }
            if sessions[session.id] != nil {
                sessions[session.id]?.project = project
                sessions[session.id]?.endedAt = nil
            } else {
                sessions[session.id] = SessionState(project: project, trackedSince: now)
                if let written = prime(sessionID: session.id, projectPath: session.projectPath, now: now) {
                    primedActivity[session.id] = written
                }
            }
        }
        for (id, state) in sessions where !liveIDs.contains(id) && state.endedAt == nil {
            sessions[id]?.endedAt = now
        }
        purgeEndedSessions(now: now)
        return primedActivity
    }

    /// Session ids currently followed, including ended ones still in their grace period.
    func trackedSessionIDs() -> Set<String> {
        Set(sessions.keys)
    }

    /// Number of transcript files currently followed.
    func trackedFileCount() -> Int {
        files.count
    }

    /// Number of files set aside with a remembered cursor.
    func retiredFileCount() -> Int {
        retiredFiles.count
    }

    // MARK: - Changes

    /// Reads what was appended to the changed paths of tracked sessions since the previous call.
    public func process(changedPaths: Set<String>, now: Date) -> ClaudeTranscriptUpdate {
        purgeEndedSessions(now: now)
        guard !sessions.isEmpty else { return .empty }

        var pending: [SampleKey: (delta: TokenCounts, at: Date)] = [:]
        var activity: [String: Date] = [:]
        var sweepAll = false
        var sweepSessions = Set<String>()
        var changedFiles: [(relative: String, sessionID: String)] = []

        for path in changedPaths {
            guard let components = relativeComponents(of: path) else { continue }
            switch Self.classify(components) {
            case let .transcript(sessionID, _) where sessions[sessionID] != nil:
                changedFiles.append((components.joined(separator: "/"), sessionID))
            case .transcript:
                continue
            case let .directory(sessionID?):
                if sessions[sessionID] != nil { sweepSessions.insert(sessionID) }
            case .directory(nil):
                sweepAll = true
            case .unrelated:
                continue
            }
        }

        // Files written in this burst are active: never set them aside to make room for another file.
        for (relative, _) in changedFiles where files[relative] != nil {
            files[relative]?.lastActivityAt = now
        }
        if sweepAll {
            sweepSessions.formUnion(sessions.keys)
        }
        for sessionID in sweepSessions.sorted() {
            discoverFiles(sessionID: sessionID, now: now)
        }
        var toRead = Set(changedFiles.map(\.relative))
        for (relative, sessionID) in changedFiles where files[relative] == nil {
            if !adopt(relative: relative, sessionID: sessionID, now: now) {
                toRead.remove(relative)
            }
        }
        for (relative, state) in files where sweepSessions.contains(state.sessionID) {
            toRead.insert(relative)
        }

        for relative in toRead.sorted() {
            read(relative: relative, now: now, pending: &pending, activity: &activity)
        }

        let samples = pending
            .compactMap { key, value -> TokenSample? in
                try? TokenSample(
                    accountID: accountID,
                    sessionID: key.sessionID,
                    project: sessions[key.sessionID]?.project,
                    model: key.model,
                    at: value.at,
                    delta: value.delta
                )
            }
            .sorted { lhs, rhs in
                if lhs.at != rhs.at { return lhs.at < rhs.at }
                if lhs.sessionID != rhs.sessionID { return lhs.sessionID < rhs.sessionID }
                return (lhs.model ?? "") < (rhs.model ?? "")
            }
        return ClaudeTranscriptUpdate(samples: samples, lastEventAt: activity)
    }

    // MARK: - Paths

    enum PathKind: Equatable {
        /// A `.jsonl` transcript of `sessionID`; `isMain` for `<slug>/<sessionId>.jsonl`.
        case transcript(sessionID: String, isMain: Bool)
        /// A directory event: `nil` for the projects root or a project folder, else inside one session's folder.
        case directory(sessionID: String?)
        case unrelated
    }

    /// Path components below the projects directory, or `nil` for paths outside it or with unsafe components.
    func relativeComponents(of path: String) -> [String]? {
        for root in roots {
            if path == root { return [] }
            guard path.hasPrefix(root + "/") else { continue }
            let components = path.dropFirst(root.count + 1).split(separator: "/", omittingEmptySubsequences: false)
            guard
                components.count <= 3 + Self.maximumSubagentDepth,
                components.allSatisfy(Self.isSafeComponent)
            else { return nil }
            return components.map(String.init)
        }
        return nil
    }

    static func classify(_ components: [String]) -> PathKind {
        switch components.count {
        case 0:
            return .directory(sessionID: nil)
        case 1:
            // Project folder names never contain dots (every non-alphanumeric becomes "-"): `.DS_Store` is noise.
            return components[0].contains(".") ? .unrelated : .directory(sessionID: nil)
        case 2:
            if let sessionID = transcriptSessionID(fileName: components[1]) {
                return .transcript(sessionID: sessionID, isMain: true)
            }
            return isTranscriptSessionID(components[1]) ? .directory(sessionID: components[1]) : .unrelated
        default:
            let sessionID = components[1]
            guard isTranscriptSessionID(sessionID), components[2] == "subagents" else { return .unrelated }
            guard components.count > 3, let last = components.last else { return .directory(sessionID: sessionID) }
            if last.hasSuffix(".jsonl") {
                return .transcript(sessionID: sessionID, isMain: false)
            }
            // Other files (`agent-1.meta.json`) are not transcripts; undotted names are run folders.
            return last.contains(".") ? .unrelated : .directory(sessionID: sessionID)
        }
    }

    /// Claude Code session ids are UUIDs; anything else cannot name a transcript.
    static func isTranscriptSessionID(_ id: String) -> Bool {
        guard !id.isEmpty, id.utf8.count <= 128 else { return false }
        return id.utf8.allSatisfy { byte in
            switch byte {
            case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "-"), UInt8(ascii: "_"):
                true
            default:
                false
            }
        }
    }

    static func transcriptSessionID(fileName: String) -> String? {
        guard fileName.hasSuffix(".jsonl") else { return nil }
        let stem = String(fileName.dropLast(".jsonl".count))
        return isTranscriptSessionID(stem) ? stem : nil
    }

    private static func isSafeComponent(_ component: Substring) -> Bool {
        !component.isEmpty && component != "." && component != ".." && component.utf8.count <= 255
            && !component.utf8.contains(0)
    }

    /// Claude Code names a project folder after its working directory with every character other than
    /// ASCII letters and digits replaced by "-" (per UTF-16 unit). Long paths are shortened differently,
    /// which the directory scan fallback covers.
    static func projectSlug(for projectPath: String) -> String {
        String(projectPath.utf16.map { unit -> Character in
            switch unit {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A: Character(UnicodeScalar(UInt8(unit)))
            default: "-"
            }
        })
    }

    private func url(for relative: String) -> URL {
        projectsDirectory.appendingPathComponent(relative, isDirectory: false)
    }

    // MARK: - Discovery

    /// Finds a new session's existing transcripts and starts each at its end.
    /// Returns when any of them was last written (never later than `now`), or `nil` when none was found.
    private func prime(sessionID: String, projectPath: String?, now: Date) -> Date? {
        guard let slug = locateMainTranscript(sessionID: sessionID, projectPath: projectPath) else { return nil }
        sessions[sessionID]?.slug = slug
        var count = fileCount(sessionID: sessionID)
        var newestWrite: Date?
        for relative in [slug + "/" + sessionID + ".jsonl"] + subagentTranscripts(slug: slug, sessionID: sessionID)
        where files[relative] == nil {
            if let modifiedAt = SecureFileIO.metadata(at: url(for: relative))?.modifiedAt {
                let written = min(modifiedAt, now)
                newestWrite = newestWrite.map { max($0, written) } ?? written
            }
            // Files beyond the budget are adopted by their own events, at their end unless they are new.
            guard count < maximumFilesPerSession else { continue }
            files[relative] = FileState(sessionID: sessionID, cursor: endCursor(relative: relative), lastActivityAt: now)
            count += 1
        }
        return newestWrite
    }

    /// Picks up files of a session that appeared without their own event (coalesced directory events).
    ///
    /// Only files written recently can hold lines that were never read; older unknown files (set aside, or
    /// beyond the budget at priming) wait for their own events, so a sweep never churns through them.
    private func discoverFiles(sessionID: String, now: Date) {
        guard let state = sessions[sessionID] else { return }
        let slug: String
        if let known = state.slug {
            slug = known
        } else if let found = locateMainTranscript(sessionID: sessionID, projectPath: nil) {
            slug = found
        } else {
            return
        }
        let freshSince = now.addingTimeInterval(-Self.historyTolerance)
        for relative in [slug + "/" + sessionID + ".jsonl"] + subagentTranscripts(slug: slug, sessionID: sessionID)
        where files[relative] == nil && retiredFiles[relative] == nil {
            guard let modifiedAt = SecureFileIO.metadata(at: url(for: relative))?.modifiedAt, modifiedAt >= freshSince else {
                continue
            }
            _ = adopt(relative: relative, sessionID: sessionID, now: now)
        }
    }

    /// Starts following a file first seen after its session was tracked. Returns `false` when refused.
    private func adopt(relative: String, sessionID: String, now: Date) -> Bool {
        guard
            let state = sessions[sessionID],
            parentDirectoriesAreReal(relative: relative),
            let info = Self.fileInfo(at: url(for: relative)), info.isRegularFile
        else { return false }

        if fileCount(sessionID: sessionID) >= maximumFilesPerSession {
            retireQuietestFile(sessionID: sessionID)
        }
        let components = relative.split(separator: "/").map(String.init)
        if case .transcript(_, isMain: true) = Self.classify(components), state.slug == nil {
            sessions[sessionID]?.slug = components[0]
        }
        let cursor: TailCursor?
        if let retired = retiredFiles.removeValue(forKey: relative), retired.sessionID == sessionID {
            // Followed before: resume exactly where reading stopped (a replaced file restarts at its end).
            cursor = retired.cursor
        } else if info.createdAt >= state.trackedSince.addingTimeInterval(-Self.historyTolerance) {
            // Created while the session was tracked: every line is new.
            cursor = TailCursor(identity: info.identity, offset: 0, skipsLeadingFragment: false)
        } else {
            // Older: only what is appended from now on.
            cursor = endCursor(relative: relative)
        }
        files[relative] = FileState(sessionID: sessionID, cursor: cursor, lastActivityAt: now)
        return true
    }

    /// Sets aside the session's file that yielded lines least recently, remembering its cursor.
    private func retireQuietestFile(sessionID: String) {
        let quietest = files
            .filter { $0.value.sessionID == sessionID }
            .min { lhs, rhs in
                lhs.value.lastActivityAt != rhs.value.lastActivityAt
                    ? lhs.value.lastActivityAt < rhs.value.lastActivityAt
                    : lhs.key < rhs.key
            }
        guard let (relative, state) = quietest else { return }
        files[relative] = nil
        if retiredFiles.count >= Self.maximumRetiredFiles,
           let oldest = retiredFiles.min(by: { $0.value.serial < $1.value.serial })?.key {
            retiredFiles[oldest] = nil
        }
        retiredSerial &+= 1
        retiredFiles[relative] = RetiredFile(sessionID: sessionID, cursor: state.cursor, serial: retiredSerial)
    }

    /// The folder holding `<sessionId>.jsonl`: the slug derived from the working directory first, then a
    /// bounded scan of all project folders.
    private func locateMainTranscript(sessionID: String, projectPath: String?) -> String? {
        let fileName = sessionID + ".jsonl"
        if let projectPath {
            let slug = Self.projectSlug(for: projectPath)
            if Self.isSafeComponent(Substring(slug)), isRegularTranscript(relative: slug + "/" + fileName) {
                return slug
            }
        }
        for folder in Self.directoryNames(in: projectsDirectory, limit: Self.maximumProjectDirectories) {
            if isRegularTranscript(relative: folder + "/" + fileName) {
                return folder
            }
        }
        return nil
    }

    private func isRegularTranscript(relative: String) -> Bool {
        parentDirectoriesAreReal(relative: relative)
            && SecureFileIO.metadata(at: url(for: relative))?.isRegularFile == true
    }

    /// `<slug>/<sessionId>/subagents/**/*.jsonl`, depth- and count-bounded, never through symlinks.
    private func subagentTranscripts(slug: String, sessionID: String) -> [String] {
        let root = slug + "/" + sessionID + "/subagents"
        // Deeper folders come from `readdir` entries typed as directories, which excludes symlinks.
        guard isRealDirectory(relative: root) else { return [] }
        var found: [String] = []
        var queue: [(relative: String, depth: Int)] = [(root, 1)]
        var visited = 0
        while let next = queue.popLast(),
              found.count < Self.maximumFilesPerSession,
              visited < Self.maximumSubagentDirectories {
            let (directory, depth) = next
            visited += 1
            let directoryURL = projectsDirectory.appendingPathComponent(directory, isDirectory: true)
            guard SecureFileIO.metadata(at: directoryURL)?.isDirectory == true else { continue }
            let names = (try? SecureFileIO.regularFileNames(in: directoryURL)) ?? []
            for name in names.sorted() where name.hasSuffix(".jsonl") && Self.isSafeComponent(Substring(name)) {
                found.append(directory + "/" + name)
                if found.count >= Self.maximumFilesPerSession { break }
            }
            guard depth < Self.maximumSubagentDepth else { continue }
            for name in Self.directoryNames(in: directoryURL, limit: 64) {
                queue.append((directory + "/" + name, depth + 1))
            }
        }
        return found
    }

    /// Every directory between the projects root and the file is a real directory, not a symlink.
    private func parentDirectoriesAreReal(relative: String) -> Bool {
        var components = relative.split(separator: "/").map(String.init)
        guard !components.isEmpty else { return false }
        components.removeLast()
        return isRealDirectory(components: components)
    }

    /// The relative path and every directory above it (below the projects root) are real directories.
    private func isRealDirectory(relative: String) -> Bool {
        isRealDirectory(components: relative.split(separator: "/").map(String.init))
    }

    private func isRealDirectory(components: [String]) -> Bool {
        var current = projectsDirectory
        for component in components {
            current = current.appendingPathComponent(component, isDirectory: true)
            guard SecureFileIO.metadata(at: current)?.isDirectory == true else { return false }
        }
        return true
    }

    private func fileCount(sessionID: String) -> Int {
        files.values.lazy.filter { $0.sessionID == sessionID }.count
    }

    /// A cursor just past the file's last complete line. Reading only the final byte tells whether the file
    /// ends mid-line, in which case the rest of that line is skipped when it is completed.
    private func endCursor(relative: String) -> TailCursor? {
        try? FileTail.read(at: url(for: relative), after: nil, initialTailBytes: 1, maximumReadBytes: 1).cursor
    }

    private func purgeEndedSessions(now: Date) {
        let expired = sessions.filter { _, state in
            state.endedAt.map { now.timeIntervalSince($0) >= Self.endedSessionGrace } ?? false
        }
        guard !expired.isEmpty else { return }
        for id in expired.keys {
            sessions[id] = nil
        }
        files = files.filter { sessions[$0.value.sessionID] != nil }
        retiredFiles = retiredFiles.filter { sessions[$0.value.sessionID] != nil }
    }

    // MARK: - Reading

    private func read(
        relative: String,
        now: Date,
        pending: inout [SampleKey: (delta: TokenCounts, at: Date)],
        activity: inout [String: Date]
    ) {
        guard var file = files[relative], let session = sessions[file.sessionID] else { return }
        let fileURL = url(for: relative)
        let chunk: TailChunk
        do {
            chunk = try FileTail.read(
                at: fileURL,
                after: file.cursor,
                // A missing or stale cursor restarts at the end (see `endCursor`), never at old content.
                initialTailBytes: 1,
                maximumReadBytes: Self.maximumReadBytes
            )
        } catch {
            files[relative] = nil
            return
        }
        file.cursor = chunk.cursor
        if !chunk.lines.isEmpty {
            file.lastActivityAt = now
        }
        files[relative] = file
        guard !chunk.lines.isEmpty else { return }

        let sessionID = file.sessionID
        var newest = SecureFileIO.metadata(at: fileURL).map { min($0.modifiedAt, now) }
        let historyCutoff = session.trackedSince.addingTimeInterval(-Self.historyTolerance)

        for line in chunk.lines where line.count <= Self.maximumLineBytes {
            guard let record = ClaudeTranscriptLine.parse(line) else { continue }
            if let timestamp = record.timestamp, timestamp < historyCutoff { continue }
            let at = min(record.timestamp ?? now, now)
            newest = newest.map { max($0, at) } ?? at

            let delta = ledger.record(id: record.requestID, counts: record.counts)
            guard !delta.isZero else { continue }
            let minute = Int64((at.timeIntervalSince1970 / 60).rounded(.down))
            let key = SampleKey(sessionID: sessionID, model: record.model, minute: minute)
            if let existing = pending[key] {
                pending[key] = (existing.delta + delta, max(existing.at, at))
            } else {
                pending[key] = (delta, at)
            }
        }

        if let newest {
            activity[sessionID] = activity[sessionID].map { max($0, newest) } ?? newest
        }
    }

    // MARK: - File system

    struct FileInfo {
        let identity: FileIdentity
        let createdAt: Date
        let isRegularFile: Bool
    }

    /// `lstat` with the birth time, which `FileMetadata` does not carry.
    static func fileInfo(at url: URL) -> FileInfo? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        let created = Date(
            timeIntervalSince1970: TimeInterval(info.st_birthtimespec.tv_sec)
                + TimeInterval(info.st_birthtimespec.tv_nsec) / 1_000_000_000
        )
        return FileInfo(
            identity: FileIdentity(device: UInt64(bitPattern: Int64(info.st_dev)), inode: UInt64(info.st_ino)),
            createdAt: created,
            isRegularFile: (info.st_mode & S_IFMT) == S_IFREG
        )
    }

    /// Names of real subdirectories (symlinks excluded), hidden ones skipped, at most `limit`.
    static func directoryNames(in directory: URL, limit: Int) -> [String] {
        guard let handle = opendir(directory.path) else { return [] }
        defer { closedir(handle) }
        var names: [String] = []
        while names.count < limit, let entry = readdir(handle) {
            guard entry.pointee.d_type == DT_DIR else { continue }
            let name = withUnsafePointer(to: entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) {
                    String(cString: $0)
                }
            }
            guard !name.hasPrefix("."), isSafeComponent(Substring(name)) else { continue }
            names.append(name)
        }
        return names
    }
}
