import CodometerCore
@testable import CodometerUI
import Foundation
import Observation
import Testing

@MainActor
@Suite("Store tick guard")
struct StoreTickGuardTests {
    @MainActor
    private final class Counter {
        var count = 0
    }

    private func store() throws -> TrackerStore {
        TrackerStore(state: .empty, settings: try AppSettings(accounts: []), now: UIFixture.now, actions: UIFixture.actions())
    }

    @Test("Ticks less than a second from now change nothing and notify no view")
    func ignoresSmallSteps() throws {
        let store = try store()
        let counter = Counter()
        withObservationTracking {
            _ = store.now
        } onChange: {
            MainActor.assumeIsolated { counter.count += 1 }
        }
        store.tick(UIFixture.now.addingTimeInterval(0.4))
        store.tick(UIFixture.now.addingTimeInterval(-0.99))
        store.tick(UIFixture.now)
        #expect(store.now == UIFixture.now)
        #expect(counter.count == 0)
    }

    @Test("A second or more moves the clock, forwards and backwards")
    func movesOnLargerSteps() throws {
        let store = try store()
        store.tick(UIFixture.now.addingTimeInterval(1))
        #expect(store.now == UIFixture.now.addingTimeInterval(1))
        store.tick(UIFixture.now.addingTimeInterval(30))
        #expect(store.now == UIFixture.now.addingTimeInterval(30))
        store.tick(UIFixture.now.addingTimeInterval(-5))
        #expect(store.now == UIFixture.now.addingTimeInterval(-5))
    }
}
