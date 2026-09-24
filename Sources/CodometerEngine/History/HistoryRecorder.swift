import CodometerCore
import CodometerPlatform
import CodometerStorage
import Foundation
import Synchronization
import os

/// One pending change to the history database.
enum HistoryWrite: Hashable, Sendable {
    /// Store a merged reading's windows and remember it as the account's last known state.
    case reading(UsageReading, identity: AccountIdentity?, accountID: AccountID)
    /// Store the segment as open (new, resumed or renamed), seen at `lastSeen`.
    case openSegment(SessionSegment, lastSeen: Date)
    case closeSegment(SessionSegment, at: Date)
    /// Mark every open segment as still active.
    case touchOpenSegments(at: Date)
    /// Close every open segment in the database, including ones this run does not know about.
    case closeOpenSegments(at: Date)
    case tokens([TokenSample])
    /// A collection run starts for the account; the first one ever is also kept as its collection start.
    case beginCollection(AccountID, at: Date)
    /// Mark every open collection run as still collecting.
    case touchCollectionRuns(at: Date)
    /// End every open collection run (of one account, or of all when `nil`) with a reason.
    case endCollection(AccountID?, at: Date, reason: CollectionRun.EndReason)
    case removeAccount(AccountID)
    /// How long history is kept from now on; the next prune uses it.
    case setRetention(TimeInterval)
    case prune(now: Date)
}

/// Applies history writes in order, off the engine's event path.
///
/// `enqueue` is synchronous and only appends to a locked queue, so the engine never waits for SQLite while it
/// handles events, and writes keep the exact order the engine produced them in. One drain task at a time stores
/// them: it waits `coalescingDelay` first so a burst of token samples becomes one transaction, then writes
/// everything queued, consecutive token writes merged into one call. `flush()` skips the wait and returns once
/// everything enqueued before it was stored (or failed and was logged).
final class HistoryRecorder: Sendable {
    static let defaultCoalescingDelay: Duration = .seconds(2)

    private struct Waiter {
        let target: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private struct Queue {
        var pending: [HistoryWrite] = []
        /// Count of writes ever enqueued; a write's sequence number is its position in that count.
        var enqueued = 0
        /// Count of writes that were stored or failed.
        var completed = 0
        var isDraining = false
        /// A flush is waiting, so the drain task must not sleep.
        var isUrgent = false
        var sleeper: Task<Void, Never>?
        var waiters: [Waiter] = []
    }

    private let store: UsageHistoryStore
    private let coalescingDelay: Duration
    private let queue = Mutex(Queue())

    init(store: UsageHistoryStore, coalescingDelay: Duration = HistoryRecorder.defaultCoalescingDelay) {
        self.store = store
        self.coalescingDelay = coalescingDelay
    }

    func enqueue(_ writes: [HistoryWrite]) {
        guard !writes.isEmpty else { return }
        let startsDrain = queue.withLock { queue in
            queue.pending.append(contentsOf: writes)
            queue.enqueued += writes.count
            guard !queue.isDraining else { return false }
            queue.isDraining = true
            return true
        }
        if startsDrain {
            Task.detached(priority: .utility) { [self] in
                await drain()
            }
        }
    }

    func enqueue(_ write: HistoryWrite?) {
        if let write {
            enqueue([write])
        }
    }

    /// Returns once every write enqueued before this call has been applied.
    func flush() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let (isDone, sleeper) = queue.withLock { queue -> (Bool, Task<Void, Never>?) in
                guard queue.completed < queue.enqueued else { return (true, nil) }
                queue.waiters.append(Waiter(target: queue.enqueued, continuation: continuation))
                queue.isUrgent = true
                return (false, queue.sleeper)
            }
            sleeper?.cancel()
            if isDone {
                continuation.resume()
            }
        }
    }

    // MARK: - Draining

    private func drain() async {
        while true {
            await coalesce()
            let (batch, end) = queue.withLock { queue -> ([HistoryWrite], Int) in
                queue.sleeper = nil
                queue.isUrgent = false
                let batch = queue.pending
                queue.pending.removeAll()
                return (batch, queue.completed + batch.count)
            }
            await apply(batch)
            let (isFinished, ready) = queue.withLock { queue -> (Bool, [CheckedContinuation<Void, Never>]) in
                queue.completed = end
                let ready = queue.waiters.filter { $0.target <= end }.map(\.continuation)
                queue.waiters.removeAll { $0.target <= end }
                guard queue.pending.isEmpty else { return (false, ready) }
                queue.isDraining = false
                queue.isUrgent = false
                return (true, ready)
            }
            ready.forEach { $0.resume() }
            if isFinished { return }
        }
    }

    /// Waits `coalescingDelay` unless a flush is waiting (or arrives meanwhile, which cancels the wait).
    private func coalesce() async {
        guard coalescingDelay > .zero else { return }
        let delay = coalescingDelay
        let sleeper = Task<Void, Never> {
            try? await Task.sleep(for: delay, tolerance: .milliseconds(250))
        }
        let waits = queue.withLock { queue -> Bool in
            guard !queue.isUrgent else { return false }
            queue.sleeper = sleeper
            return true
        }
        if waits {
            await sleeper.value
        } else {
            sleeper.cancel()
        }
    }

    private func apply(_ batch: [HistoryWrite]) async {
        var tokens: [TokenSample] = []
        for write in batch {
            if case .tokens(let samples) = write {
                tokens.append(contentsOf: samples)
                continue
            }
            if !tokens.isEmpty {
                await perform(.tokens(tokens))
                tokens.removeAll()
            }
            await perform(write)
        }
        if !tokens.isEmpty {
            await perform(.tokens(tokens))
        }
    }

    private func perform(_ write: HistoryWrite) async {
        do throws(SQLiteError) {
            switch write {
            case let .reading(reading, identity, accountID):
                try await store.record(reading, identity: identity, for: accountID)
            case let .openSegment(segment, lastSeen):
                try await store.openSegment(segment, lastSeen: lastSeen)
            case let .closeSegment(segment, end):
                try await store.closeSegment(segment, at: end)
            case .touchOpenSegments(let date):
                try await store.touchOpenSegments(at: date)
            case .closeOpenSegments(let date):
                try await store.closeOpenSegments(at: date)
            case .tokens(let samples):
                try await store.addTokenSamples(samples)
            case let .beginCollection(accountID, date):
                try await store.beginCollection(accountID: accountID, at: date)
            case .touchCollectionRuns(let date):
                try await store.touchCollectionRuns(at: date)
            case let .endCollection(accountID, date, reason):
                try await store.endCollectionRuns(accountID: accountID, at: date, reason: reason)
            case .setRetention(let seconds):
                await store.setRetention(seconds)
            case .removeAccount(let accountID):
                try await store.removeAccount(accountID)
            case .prune(let now):
                try await store.prune(now: now)
            }
        } catch {
            AppLog.storage.error("history write failed: \(error.description, privacy: .public)")
        }
    }
}
