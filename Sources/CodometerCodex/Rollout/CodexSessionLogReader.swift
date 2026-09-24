import CodometerCore
import CodometerPlatform
import Foundation

/// What the session logs of one Codex profile currently say.
public struct CodexLogSnapshot: Sendable {
    public let sessions: [AgentSession]
    /// The newest reading assembled from `token_count` events, if any were seen.
    public let reading: UsageReading?
    public let planType: String?
    /// Tokens consumed since the previous snapshot, per session. Drained: each sample is reported once.
    public let tokenSamples: [TokenSample]
    /// When a pending approval will have waited long enough to count as a prompt; recompute the snapshot then.
    public let needsRecheckAt: Date?
    /// Increases with every snapshot the reader takes. Callers that receive snapshots from several tasks use it to
    /// ignore an older snapshot arriving after a newer one (its sessions and recheck time are out of date).
    public let generation: UInt64
    /// What the reader could not use so far, for the Diagnostics pane's format-drift note (item 18).
    public let statistics: CodexReaderStatistics
}

/// Counts of rollout content this version could not use. Counts only: no names, no text, nothing persisted.
public struct CodexReaderStatistics: Hashable, Sendable {
    /// Reads where the tail had to jump over bytes it never saw (a single line larger than the read budget, or more
    /// appended at once than one read may take).
    public var oversizedLinesSkipped: Int
    /// `event_msg` lines whose payload type this version does not know. Codex adds event types often, so this is a
    /// hint, not a failure (`FormatDrift.severity` never rises from it alone).
    public var unknownEventTypes: Int

    public init(oversizedLinesSkipped: Int = 0, unknownEventTypes: Int = 0) {
        self.oversizedLinesSkipped = max(0, oversizedLinesSkipped)
        self.unknownEventTypes = max(0, unknownEventTypes)
    }

    public static let empty = CodexReaderStatistics()
}

/// Follows Codex rollout logs incrementally and derives sessions, rate limits and token usage from them.
public actor CodexSessionLogReader {
    /// Files untouched for longer than this are not read at startup.
    public static let recentFileWindow: TimeInterval = 12 * 60 * 60
    /// An idle session disappears from the list after this long.
    public static let idleSessionVisibility: TimeInterval = 30 * 60
    /// A turn with no log activity for this long is assumed dead (crash, killed process).
    public static let staleTurnTimeout: TimeInterval = 30 * 60
    /// A session waiting for the user with no log activity for this long is assumed abandoned (app closed).
    public static let staleWaitTimeout: TimeInterval = 2 * 60 * 60
    /// See `CodexSessionState.approvalPromptDelay`.
    public static let approvalPromptDelay: TimeInterval = CodexSessionState.approvalPromptDelay
    static let initialTailBytes: UInt64 = 1_024 * 1_024
    static let maximumReadBytes: UInt64 = 8 * 1_024 * 1_024
    static let maximumTrackedFiles = 200

    private struct FileEntry: Sendable {
        var cursor: TailCursor?
        var didReadHeader = false
        var session: CodexSessionState
    }

    private struct LimitEntry: Sendable {
        let snapshot: CodexLimitSnapshot
        let capturedAt: Date
    }

    private let layout: CodexProfileLayout
    private let accountID: AccountID
    private var files: [String: FileEntry] = [:]
    private var limits: [String: LimitEntry] = [:]
    private var ledger = CodexTokenLedger()
    private var generation: UInt64 = 0
    private var counters = CodexReaderStatistics.empty

    /// `event_msg` payload types this version knows: the ones `CodexRolloutParser` turns into events, and the ones
    /// it deliberately ignores. Anything outside this set is counted as drift. Kept here rather than in the parser
    /// so a type the parser starts using simply stops reaching the count (a line with events is never counted).
    static let knownEventTypes: Set<String> = [
        "agent_message", "agent_message_delta", "agent_reasoning", "agent_reasoning_delta",
        "agent_reasoning_raw_content", "agent_reasoning_raw_content_delta", "agent_reasoning_section_break",
        "apply_patch_approval_request", "background_event", "conversation_path", "entered_review_mode", "error",
        "exec_approval_request", "exec_command_begin", "exec_command_end", "exec_command_output_delta",
        "exited_review_mode", "get_history_entry_response", "item_completed", "item_started", "item_updated",
        "list_custom_prompts_response", "mcp_list_tools_response", "mcp_tool_call_begin", "mcp_tool_call_end",
        "notification", "patch_apply_begin", "patch_apply_end", "plan_update", "session_configured",
        "shutdown_complete", "stream_error", "task_complete", "task_started", "thread_settings_applied",
        "token_count", "turn_aborted", "turn_diff", "undo_status", "user_message", "view_image_tool_call",
        "web_search_begin", "web_search_end",
    ]

    /// - Parameter accountID: the account token samples are attributed to.
    public init(layout: CodexProfileLayout, accountID: AccountID) {
        self.layout = layout
        self.accountID = accountID
    }

    /// Reads the tails of recently modified logs. Safe to call again to rebuild state.
    ///
    /// Token usage is collected live only: lines read here, or stamped before `now`, never become samples.
    public func bootstrap(now: Date) -> CodexLogSnapshot {
        files.removeAll()
        limits.removeAll()
        counters = .empty
        ledger.beginLiveCollection(at: now)
        for url in recentRolloutFiles(now: now) {
            ingest(url: url, now: now, collectsTokens: false)
        }
        return snapshot(now: now)
    }

    /// Reads what was appended to the given paths since the last call.
    public func process(changedPaths: Set<String>, now: Date) -> CodexLogSnapshot {
        let roots = [layout.sessionsDirectory, layout.sessionsDirectory.resolvingSymlinksInPath()].map { $0.path + "/" }
        for path in changedPaths where Self.isRolloutFileName((path as NSString).lastPathComponent) {
            guard roots.contains(where: path.hasPrefix) else { continue }
            ingest(url: URL(fileURLWithPath: path, isDirectory: false), now: now, collectsTokens: true)
        }
        return snapshot(now: now)
    }

    /// The current state at `now`. Drains the pending token samples.
    public func snapshot(now: Date) -> CodexLogSnapshot {
        // One entry per session even if several files belong to it: a resumed thread writes a new file and
        // subagent threads log under their parent's session id. See `session(representing:now:)`.
        var statesPerSession: [String: [CodexSessionState]] = [:]
        for entry in files.values {
            statesPerSession[entry.session.sessionID, default: []].append(entry.session)
        }
        let sessions = statesPerSession.values
            .compactMap { states in Self.session(representing: states, now: now) }
            .sorted { lhs, rhs in
                if lhs.activity != rhs.activity { return lhs.activity > rhs.activity }
                if lhs.activitySince != rhs.activitySince { return lhs.activitySince > rhs.activitySince }
                // Files are kept in a dictionary: without a final key equal sessions would swap places between
                // snapshots and republish for nothing.
                return lhs.id < rhs.id
            }
        let needsRecheckAt = files.values.compactMap { $0.session.nextRecheck(now: now) }.min()

        let live = limits.values.filter { entry in
            ![entry.snapshot.primary, entry.snapshot.secondary].contains { window in
                window?.resetsAt.map { $0 <= now } ?? false
            }
        }
        let newest = live.map(\.capturedAt).max()
        let reading = newest.flatMap { capturedAt in
            CodexLimitMapper.reading(from: live.map(\.snapshot), capturedAt: capturedAt, source: .codexSessionLog)
        }
        let planType = live.sorted { $0.capturedAt > $1.capturedAt }.compactMap(\.snapshot.planType).first
        generation &+= 1
        return CodexLogSnapshot(
            sessions: sessions,
            reading: reading,
            planType: planType,
            tokenSamples: ledger.drain(accountID: accountID),
            needsRecheckAt: needsRecheckAt,
            generation: generation,
            statistics: counters
        )
    }

    /// What the reader could not use so far.
    public func statistics() -> CodexReaderStatistics {
        counters
    }

    /// The session shown for all files of one session id.
    ///
    /// - A subagent never outlives its parent's turn. When the parent's turn ended after a subagent's file went silent,
    ///   the subagent was stopped with it (an interrupt does not always close the subagent's turn): its open turn or
    ///   pending prompt no longer counts.
    /// - A prompt waiting in any file is what the user must see: the longest wait.
    /// - Otherwise, while any file is mid-turn the session is working. Subagents log under their parent's session id
    ///   and usually finish their turns while the parent's turn goes on; letting the newest file win would flip the
    ///   session to idle and back (a false «закончил»). The earliest turn start is shown, with the latest activity
    ///   of all the session's files, so a parent silently waiting for its subagent does not look stuck.
    /// - Otherwise the newest file.
    static func session(representing states: [CodexSessionState], now: Date) -> AgentSession? {
        var shown = states.compactMap { state in state.session(now: now).map { (state: state, session: $0) } }
        let parentIdleSince = shown
            .filter { !$0.state.isSubagentThread && $0.session.activity == .idle }
            .map(\.session.activitySince)
            .max()
        if let parentIdleSince {
            shown.removeAll { entry in
                entry.state.isSubagentThread && entry.session.activity != .idle && entry.state.lastEventAt < parentIdleSince
            }
        }
        let waiting = shown
            .filter { $0.session.activity == .waiting }
            .min { $0.session.activitySince < $1.session.activitySince }
        if let waiting {
            return waiting.session
        }
        let working = shown.filter { $0.session.activity == .working }
        if let longest = working.min(by: { $0.session.activitySince < $1.session.activitySince }) {
            let latestActivity = shown.map(\.state.lastEventAt).max()
            return longest.state.session(now: now, latestActivity: latestActivity) ?? longest.session
        }
        return shown.max { $0.state.lastEventAt < $1.state.lastEventAt }?.session
    }

    static func isRolloutFileName(_ name: String) -> Bool {
        name.hasPrefix("rollout-") && name.hasSuffix(".jsonl") && name.utf8.count <= 255
    }

    /// `rollout-2026-09-16T22-54-41-<uuid>.jsonl` → `<uuid>`; the whole stem when it has no UUID suffix.
    static func sessionID(fromFileName name: String) -> String {
        let stem = String(name.dropFirst("rollout-".count).dropLast(".jsonl".count))
        let parts = stem.split(separator: "-")
        guard parts.count >= 5 else { return stem }
        let candidate = parts.suffix(5).joined(separator: "-")
        return candidate.count == 36 ? candidate : stem
    }

    // MARK: - Reading

    private func ingest(url: URL, now: Date, collectsTokens: Bool) {
        // FSEvents and directory enumeration can spell the same file differently (/var vs /private/var).
        let path = url.resolvingSymlinksInPath().path
        var entry = files[path] ?? FileEntry(session: CodexSessionState(
            sessionID: Self.sessionID(fromFileName: url.lastPathComponent),
            activitySince: .distantPast,
            lastEventAt: .distantPast
        ))

        let isFirstRead = entry.cursor == nil
        let metadata = isFirstRead ? SecureFileIO.metadata(at: url) : nil
        let tailSkipsStart = (metadata?.size ?? 0) > Self.initialTailBytes
        if isFirstRead, !entry.didReadHeader {
            // The `session_meta` header is the first line; read it separately when the tail starts after it.
            entry.didReadHeader = true
            if tailSkipsStart, let header = RolloutFileHistory.firstLine(of: url) {
                for event in CodexRolloutParser.events(in: header) {
                    if case .sessionStarted = event { _ = entry.session.apply(event) }
                }
            }
        }

        let chunk: TailChunk
        do {
            chunk = try FileTail.read(
                at: url,
                after: entry.cursor,
                initialTailBytes: Self.initialTailBytes,
                maximumReadBytes: Self.maximumReadBytes
            )
        } catch {
            files[path] = nil
            return
        }
        if chunk.didRestart {
            entry.session.restart()
        }
        // Bytes the reader never saw: the tail advanced further than the lines it returned account for (a single
        // line larger than the read budget, or a burst larger than one read). The first read of a file always
        // starts inside the file, and a restart replaces the state, so neither counts.
        if !isFirstRead, !chunk.didRestart, let previous = entry.cursor {
            let accounted = chunk.lines.reduce(UInt64(0)) { $0 + UInt64($1.count) + 1 }
            let advanced = chunk.cursor.offset > previous.offset ? chunk.cursor.offset - previous.offset : 0
            if advanced > accounted {
                counters.oversizedLinesSkipped += 1
            }
        }
        entry.cursor = chunk.cursor

        // A long turn in progress started before the tail: recover its start and context (approval policy, model),
        // or turn state and waiting detection stay unknown until the next turn. Long turns write several turn
        // contexts (one after each compaction), so a context inside the tail does not mean its start is there too.
        // Only for files written recently enough to still be working.
        if isFirstRead, tailSkipsStart, let metadata, now.timeIntervalSince(metadata.modifiedAt) <= Self.staleTurnTimeout {
            let tail = Self.turnLineKinds(in: chunk.lines)
            if !tail.contains(.turnContext) || !tail.contains(.turnBoundary) {
                let recovered = RolloutFileHistory.latestTurnEvents(
                    of: url,
                    before: metadata.size - Self.initialTailBytes,
                    needsContext: !tail.contains(.turnContext),
                    needsBoundary: !tail.contains(.turnBoundary)
                )
                for event in recovered {
                    _ = entry.session.apply(event)
                }
            }
        }

        for line in chunk.lines {
            let events = CodexRolloutParser.events(in: line, scanningCallOutputs: entry.session.hasPendingCalls)
            if events.isEmpty, collectsTokens {
                countUnknownEventType(in: line)
            }
            for event in events {
                if case let .rateLimits(snapshot, at) = event {
                    record(snapshot, at: at)
                }
                if let observation = entry.session.apply(event) {
                    ledger.record(observation, in: entry.session, collecting: collectsTokens)
                }
            }
        }
        // Conversation lines are not parsed, but they still show the session is alive.
        if let last = chunk.lines.last, let at = CodexRolloutParser.timestamp(of: last) {
            entry.session.touch(min(at, now))
        }
        if entry.session.lastEventAt == .distantPast, let modified = (metadata ?? SecureFileIO.metadata(at: url))?.modifiedAt {
            entry.session.lastEventAt = modified
        }
        if entry.session.activitySince == .distantPast {
            // No turn event seen yet: the session has been idle since its last activity, not since the app started.
            entry.session.activitySince = entry.session.lastEventAt
        }
        files[path] = entry
        evictIfNeeded()
    }

    /// A line the parser produced nothing from: count it when it is an `event_msg` of an unfamiliar type. Only
    /// live processing counts, so re-reading a tail at startup never inflates the number.
    private func countUnknownEventType(in line: Data) {
        let types = RolloutLineScanner.lineTypes(line)
        guard types.type == "event_msg" else { return }
        let isKnown = types.payloadType.map(Self.knownEventTypes.contains) ?? false
        if !isKnown {
            counters.unknownEventTypes += 1
        }
    }

    /// Which kinds of turn lines occur in `lines`; stops once both were seen.
    private static func turnLineKinds(in lines: [Data]) -> Set<RolloutLineKind> {
        var kinds: Set<RolloutLineKind> = []
        for line in lines {
            let kind = CodexRolloutParser.lineKind(of: line)
            if kind != .other {
                kinds.insert(kind)
                if kinds.count == 2 { break }
            }
        }
        return kinds
    }

    private func record(_ snapshot: CodexLimitSnapshot, at: Date) {
        let key = snapshot.bucketID
        if let existing = limits[key], existing.capturedAt > at {
            return
        }
        limits[key] = LimitEntry(snapshot: snapshot, capturedAt: at)
    }

    private func recentRolloutFiles(now: Date) -> [URL] {
        let root = layout.sessionsDirectory
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var found: [(URL, Date)] = []
        for case let url as URL in enumerator {
            guard
                Self.isRolloutFileName(url.lastPathComponent),
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey]),
                values.isRegularFile == true,
                values.isSymbolicLink != true,
                let modified = values.contentModificationDate,
                now.timeIntervalSince(modified) <= Self.recentFileWindow
            else { continue }
            found.append((url, modified))
        }
        return found
            .sorted { $0.1 > $1.1 }
            .prefix(Self.maximumTrackedFiles)
            .map(\.0)
    }

    private func evictIfNeeded() {
        guard files.count > Self.maximumTrackedFiles else { return }
        let surplus = files.count - Self.maximumTrackedFiles
        let oldest = files.sorted { $0.value.session.lastEventAt < $1.value.session.lastEventAt }.prefix(surplus)
        for (path, _) in oldest {
            files[path] = nil
        }
    }
}
