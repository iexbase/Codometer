import CodometerCore
import Foundation

/// A set of recently seen identifiers with a fixed capacity: once full, the oldest member is forgotten first.
struct RecentIdentifiers: Sendable {
    let capacity: Int
    private var members: Set<String> = []
    private var order: [String] = []
    private var oldest = 0

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    var count: Int {
        members.count
    }

    func contains(_ identifier: String) -> Bool {
        members.contains(identifier)
    }

    /// Adds `identifier`. Returns `false` when it was already a member.
    mutating func insert(_ identifier: String) -> Bool {
        guard !members.contains(identifier) else { return false }
        if order.count < capacity {
            order.append(identifier)
        } else {
            members.remove(order[oldest])
            order[oldest] = identifier
            oldest = (oldest + 1) % capacity
        }
        members.insert(identifier)
        return true
    }
}

/// Turns token observations from rollout files into per-session `TokenSample`s, each response exactly once.
///
/// - Responses are deduplicated by `response_id` across all files of the profile (a resumed or forked thread can
///   repeat lines in another file).
/// - Nothing written before live collection started counts: those lines were either read during bootstrap or
///   copied from older history, and counting them again would double usage after every restart.
/// - Observations are merged per session, model and minute until the next drain.
struct CodexTokenLedger: Sendable {
    static let rememberedResponses = 4_096
    static let maximumPendingGroups = 512

    private struct GroupKey: Hashable, Sendable {
        let sessionID: String
        let project: String?
        let model: String?
        let minute: Int64
    }

    private struct Group: Sendable {
        var delta: TokenCounts
        var at: Date
    }

    /// Lines stamped earlier than this are history, not live usage.
    private(set) var liveSince: Date = .distantPast
    private var seenResponses = RecentIdentifiers(capacity: rememberedResponses)
    private var pending: [GroupKey: Group] = [:]

    /// Starts live collection at `date`, dropping anything not drained yet. Remembered response ids are kept.
    mutating func beginLiveCollection(at date: Date) {
        liveSince = date
        pending.removeAll()
    }

    /// Remembers the observation's response and, when `collecting`, adds it to the pending samples.
    mutating func record(_ observation: CodexTokenObservation, in session: CodexSessionState, collecting: Bool) {
        if let responseID = observation.responseID, !seenResponses.insert(responseID) {
            return
        }
        guard collecting, observation.at >= liveSince, !observation.counts.isZero else { return }
        let key = GroupKey(
            sessionID: session.sessionID,
            project: session.workingDirectory,
            model: session.model,
            minute: Int64((observation.at.timeIntervalSince1970 / 60).rounded(.down))
        )
        if var group = pending[key] {
            group.delta = group.delta + observation.counts
            group.at = max(group.at, observation.at)
            pending[key] = group
        } else if pending.count < Self.maximumPendingGroups {
            pending[key] = Group(delta: observation.counts, at: observation.at)
        }
    }

    /// Returns the pending samples, oldest first, and forgets them.
    mutating func drain(accountID: AccountID) -> [TokenSample] {
        guard !pending.isEmpty else { return [] }
        let samples = pending
            .compactMap { key, group in
                try? TokenSample(
                    accountID: accountID,
                    sessionID: key.sessionID,
                    project: key.project,
                    model: key.model,
                    at: group.at,
                    delta: group.delta
                )
            }
            .sorted { lhs, rhs in
                if lhs.at != rhs.at { return lhs.at < rhs.at }
                if lhs.sessionID != rhs.sessionID { return lhs.sessionID < rhs.sessionID }
                return (lhs.model ?? "") < (rhs.model ?? "")
            }
        pending.removeAll()
        return samples
    }
}
