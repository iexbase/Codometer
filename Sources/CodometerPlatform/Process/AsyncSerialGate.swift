/// Lets one async operation run at a time, in arrival order.
///
/// Used so that probes for several accounts never start several CLI processes at once.
public actor AsyncSerialGate {
    /// One caller waiting its turn. The ticket lets a wait that ran out of time take itself out of the queue
    /// without disturbing the caller the gate has already handed over to.
    private struct Waiter {
        let ticket: UInt64
        /// `true` = the gate is yours and you must `release()` it; `false` = the wait ran out.
        let continuation: CheckedContinuation<Bool, Never>
    }

    private var isBusy = false
    private var waiters: [Waiter] = []
    private var nextTicket: UInt64 = 0

    public init() {}

    /// Waits for the gate for as long as it takes.
    public func acquire() async {
        _ = await acquire(deadlineAfter: nil)
    }

    /// Waits for the gate for at most `timeout`; `false` means the wait ran out and the caller does **not** hold
    /// the gate (and so must not `release()` it).
    ///
    /// For work under a deadline — "Check System" has ten seconds for everything — where queueing behind an
    /// operation with a much longer timeout of its own would blow the budget. A caller that gives up simply does
    /// without: it never cancels or disturbs the operation that holds the gate.
    ///
    /// A timeout of zero or less takes the gate only when it is free.
    @discardableResult
    public func acquire(timeout: Duration) async -> Bool {
        await acquire(deadlineAfter: timeout)
    }

    public func release() {
        if waiters.isEmpty {
            isBusy = false
        } else {
            waiters.removeFirst().continuation.resume(returning: true)
        }
    }

    // MARK: - One implementation for both waits

    /// `nil` waits indefinitely, which is the only case that always returns `true`.
    private func acquire(deadlineAfter timeout: Duration?) async -> Bool {
        guard isBusy else {
            isBusy = true
            return true
        }
        if let timeout, timeout <= .zero { return false }
        let ticket = nextTicket
        nextTicket += 1
        let countdown = timeout.map { limit in
            Task { [weak self] in
                try? await Task.sleep(for: limit)
                guard !Task.isCancelled else { return }
                await self?.giveUp(ticket: ticket)
            }
        }
        // The waiter is queued before this call suspends, so `release()` and `giveUp(ticket:)` both see it.
        let acquired = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            waiters.append(Waiter(ticket: ticket, continuation: continuation))
        }
        countdown?.cancel()
        return acquired
    }

    /// Takes a waiter out of the queue when its time ran out. Runs on the actor, so it cannot interleave with
    /// `release()`: whichever of the two arrives first wins, and the other finds nothing to do. A waiter that
    /// `release()` handed the gate to therefore keeps it, even when its countdown fires in the same instant.
    private func giveUp(ticket: UInt64) {
        guard let index = waiters.firstIndex(where: { $0.ticket == ticket }) else { return }
        waiters.remove(at: index).continuation.resume(returning: false)
    }
}
