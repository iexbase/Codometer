import CodometerCore
import Foundation

/// Where the app reads power conditions from: the live power monitor, or a fixed snapshot in tests and isolated runs.
public protocol PowerStateProviding: Sendable {
    /// The conditions right now.
    func current() -> PowerSnapshot
    /// Every change, coalesced by the provider; the current snapshot comes first.
    func snapshots() -> AsyncStream<PowerSnapshot>
}

/// Power conditions that never change.
public struct FixedPowerState: PowerStateProviding {
    private let snapshot: PowerSnapshot

    public init(_ snapshot: PowerSnapshot = .nominalAC) {
        self.snapshot = snapshot
    }

    public func current() -> PowerSnapshot {
        snapshot
    }

    /// Yields the snapshot once and finishes: nothing ever changes.
    public func snapshots() -> AsyncStream<PowerSnapshot> {
        let snapshot = snapshot
        return AsyncStream { continuation in
            continuation.yield(snapshot)
            continuation.finish()
        }
    }
}
