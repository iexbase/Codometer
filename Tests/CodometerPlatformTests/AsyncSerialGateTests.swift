import CodometerPlatform
import Testing

/// The bounded wait added for "Check System": a caller under a deadline must be able to give up on the gate
/// without disturbing the operation holding it or the callers still queued behind it.
@Suite("Async serial gate")
struct AsyncSerialGateTests {
    /// Generous enough that a loaded machine cannot turn "takes the gate" into "gave up".
    private static let generous = Duration.seconds(30)

    @Test("A bounded wait takes a free gate at once")
    func freeGate() async {
        let gate = AsyncSerialGate()
        #expect(await gate.acquire(timeout: Self.generous))
        await gate.release()
        // Released, so the next bounded caller gets it too.
        #expect(await gate.acquire(timeout: .zero))
        await gate.release()
    }

    @Test("A zero timeout takes the gate only when nobody holds it")
    func zeroTimeout() async {
        let gate = AsyncSerialGate()
        await gate.acquire()
        #expect(await gate.acquire(timeout: .zero) == false)
        await gate.release()
        #expect(await gate.acquire(timeout: .zero))
        await gate.release()
    }

    @Test("A bounded wait gives up on a holder that keeps the gate, and leaves it in the holder's hands")
    func givesUp() async {
        let gate = AsyncSerialGate()
        await gate.acquire()
        let clock = ContinuousClock()
        let started = clock.now
        let acquired = await gate.acquire(timeout: .milliseconds(150))
        let waited = clock.now - started
        #expect(acquired == false)
        #expect(waited >= .milliseconds(120))
        // The holder is untouched: it still owns the gate and hands it on when it is done.
        await gate.release()
        #expect(await gate.acquire(timeout: .zero))
        await gate.release()
    }

    @Test("A bounded wait that arrives in time takes its turn")
    func takesItsTurn() async {
        let gate = AsyncSerialGate()
        await gate.acquire()
        let waiter = Task { await gate.acquire(timeout: Self.generous) }
        try? await Task.sleep(for: .milliseconds(30))
        await gate.release()
        #expect(await waiter.value)
        await gate.release()
    }

    @Test("A wait that ran out leaves the queue to the caller still in it")
    func leavesTheQueue() async {
        let gate = AsyncSerialGate()
        await gate.acquire()
        let quitter = Task { await gate.acquire(timeout: .milliseconds(120)) }
        try? await Task.sleep(for: .milliseconds(20))
        let patient = Task { await gate.acquire() }
        #expect(await quitter.value == false)
        // One release, and it must reach the caller that is still waiting rather than the one that left.
        await gate.release()
        await patient.value
        await gate.release()
        // Nothing is stuck: the gate is free again.
        #expect(await gate.acquire(timeout: .zero))
        await gate.release()
    }

    @Test("Bounded and unbounded callers still run one at a time")
    func exclusivity() async {
        let gate = AsyncSerialGate()
        let counter = GateCounter()
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<8 {
                group.addTask {
                    if index.isMultiple(of: 2) {
                        await gate.acquire()
                    } else {
                        guard await gate.acquire(timeout: Self.generous) else { return }
                    }
                    await counter.enter()
                    try? await Task.sleep(for: .milliseconds(5))
                    await counter.leave()
                    await gate.release()
                }
            }
        }
        #expect(await counter.maximum == 1)
        #expect(await counter.total == 8)
    }

    @Test("Unbounded waiters are served in arrival order")
    func arrivalOrder() async {
        let gate = AsyncSerialGate()
        let order = GateOrder()
        await gate.acquire()
        var waiters: [Task<Void, Never>] = []
        for index in 0..<4 {
            waiters.append(Task { await gate.acquire(); await order.add(index); await gate.release() })
            // Queue them one at a time, so "arrival order" is the order this loop makes.
            try? await Task.sleep(for: .milliseconds(20))
        }
        await gate.release()
        for waiter in waiters { await waiter.value }
        #expect(await order.items == [0, 1, 2, 3])
    }
}

private actor GateCounter {
    private var current = 0
    private(set) var maximum = 0
    private(set) var total = 0

    func enter() {
        current += 1
        total += 1
        maximum = max(maximum, current)
    }

    func leave() {
        current -= 1
    }
}

private actor GateOrder {
    private(set) var items: [Int] = []

    func add(_ value: Int) {
        items.append(value)
    }
}
