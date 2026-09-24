import CodometerCore
import Foundation
import IOKit.ps
import Synchronization

/// Turns IOKit's power-source dictionaries and the system's power notifications into `PowerSnapshot` values.
///
/// Pure and testable: every function takes the values the framework hands out, so the mapping is covered on a Mac
/// without a battery (`PowerSnapshotMapperTests`).
public enum PowerSourceMapper {
    /// What `IOPSGetProvidingPowerSourceType` reports while the Mac runs on wall power.
    public static let acPowerType = kIOPMACPowerKey

    /// `ProcessInfo.ThermalState` as the domain spells it.
    public static func thermalLevel(_ state: ProcessInfo.ThermalState) -> ThermalLevel {
        switch state {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .nominal
        }
    }

    /// The system's own low-battery warning (`IOPSGetBatteryWarningLevel`), which covers both the early warning
    /// (about 22 %) and the final one. Change notifications carry it, so low battery never needs polling.
    public static func isLowBatteryWarning(_ level: IOPSLowBatteryWarningLevel) -> Bool {
        level != kIOPSLowBatteryWarningNone
    }

    /// Whether one `IOPSGetPowerSourceDescription` dictionary describes a built-in battery that is present.
    public static func isInternalBattery(_ description: [String: Any]) -> Bool {
        let present = (description[kIOPSIsPresentKey] as? NSNumber)?.boolValue ?? true
        return present
            && description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            && description[kIOPSTransportTypeKey] as? String == kIOPSInternalType
    }

    /// The charge of one power-source dictionary as a percentage, or `nil` when the numbers are missing or absurd.
    public static func batteryPercent(in description: [String: Any]) -> Percentage? {
        guard
            let current = (description[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue,
            let maximum = (description[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue,
            maximum > 0,
            current >= 0
        else { return nil }
        return try? Percentage(validating: min(100, current / maximum * 100))
    }

    /// The lowest charge among the internal batteries, or `nil` on a Mac without one.
    public static func batteryPercent(in descriptions: [[String: Any]]) -> Percentage? {
        descriptions.filter(isInternalBattery).compactMap(batteryPercent(in:)).min()
    }

    /// The whole snapshot from what the framework reported.
    ///
    /// A desktop Mac always reports wall power, so it comes out as `onBattery = false` with no percentage; the
    /// low-battery warning only counts while the Mac actually runs on its battery.
    public static func snapshot(
        providingPowerSourceType: String?,
        descriptions: [[String: Any]],
        lowPowerMode: Bool,
        thermal: ThermalLevel,
        lowBatteryWarning: Bool
    ) -> PowerSnapshot {
        let onBattery = providingPowerSourceType != nil && providingPowerSourceType != acPowerType
        return PowerSnapshot(
            lowPowerMode: lowPowerMode,
            onBattery: onBattery,
            batteryPercent: batteryPercent(in: descriptions),
            thermal: thermal,
            lowBatteryWarning: onBattery && lowBatteryWarning
        )
    }
}

/// Follows power conditions without polling: Low Power Mode, thermal pressure and the power source all arrive as
/// notifications, and the battery percentage is read at most once a minute when a snapshot is built.
///
/// `IOPSCreateLimitedPowerNotification` fires on source changes **and** battery warning-level changes, which is what
/// the "battery is low" rule needs; a change of one percent never wakes the app.
public final class PowerStateMonitor: PowerStateProviding {
    /// Bursts of notifications (unplugging while the Mac heats up) settle into one snapshot after this long.
    public static let coalescingInterval: DispatchTimeInterval = .seconds(2)
    /// The battery percentage is shown for information only, so a value this stale is still fine.
    public static let batteryPercentInterval: TimeInterval = 60

    /// The parts any thread may touch. The notification handles are not `Sendable`, so they live on the main actor
    /// instead (`start()` and `stop()` run there, and the run-loop source belongs to the main run loop anyway).
    private struct Storage {
        var continuations: [UUID: AsyncStream<PowerSnapshot>.Continuation] = [:]
        var lastPublished: PowerSnapshot?
        var cachedPercent: Percentage?
        var percentReadAt: Date?
        /// Raised by every notification; only the newest coalescing wait publishes.
        var generation: UInt64 = 0
    }

    private let storage = Mutex(Storage())
    private let queue = DispatchQueue(label: "codometer.power", qos: .utility)
    private let clock: @Sendable () -> Date

    @MainActor private var isStarted = false
    @MainActor private var observers: [any NSObjectProtocol] = []
    @MainActor private var runLoopSource: CFRunLoopSource?
    @MainActor private var retained: Unmanaged<PowerStateMonitor>?

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        clock = now
    }

    /// Registers the three notification sources. Calling it again does nothing.
    @MainActor public func start() {
        guard !isStarted else { return }
        isStarted = true

        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: nil) { [weak self] _ in
                self?.conditionsChanged()
            },
            center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: nil) { [weak self] _ in
                self?.conditionsChanged()
            },
        ]
        // The callback receives a raw pointer, so the monitor stays alive until `stop()` releases it.
        let held = Unmanaged.passRetained(self)
        let source = IOPSCreateLimitedPowerNotification({ context in
            guard let context else { return }
            Unmanaged<PowerStateMonitor>.fromOpaque(context).takeUnretainedValue().conditionsChanged()
        }, held.toOpaque())?.takeRetainedValue()
        if let source {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
            retained = held
        } else {
            held.release()
        }
    }

    /// Removes every notification source and finishes the streams.
    @MainActor public func stop() {
        guard isStarted else { return }
        isStarted = false
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = nil
        }
        let continuations = storage.withLock { storage -> [AsyncStream<PowerSnapshot>.Continuation] in
            let open = Array(storage.continuations.values)
            storage = Storage()
            return open
        }
        continuations.forEach { $0.finish() }
        retained?.release()
        retained = nil
    }

    /// The conditions right now: Low Power Mode, thermal state, power source and warning level are read every time
    /// (all cheap); the battery percentage comes from a cache at most `batteryPercentInterval` old.
    public func current() -> PowerSnapshot {
        let processInfo = ProcessInfo.processInfo
        let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
        let providing = blob.flatMap { IOPSGetProvidingPowerSourceType($0)?.takeUnretainedValue() } as String?
        let now = clock()
        let reads = storage.withLock { storage in
            Self.shouldReadPercent(lastReadAt: storage.percentReadAt, now: now, interval: Self.batteryPercentInterval)
        }
        let percent: Percentage?
        if reads, let blob {
            let measured = PowerSourceMapper.batteryPercent(in: Self.descriptions(in: blob))
            storage.withLock { storage in
                storage.cachedPercent = measured
                storage.percentReadAt = now
            }
            percent = measured
        } else {
            percent = storage.withLock { $0.cachedPercent }
        }
        let onBattery = providing != nil && providing != PowerSourceMapper.acPowerType
        return PowerSnapshot(
            lowPowerMode: processInfo.isLowPowerModeEnabled,
            onBattery: onBattery,
            batteryPercent: percent,
            thermal: PowerSourceMapper.thermalLevel(processInfo.thermalState),
            lowBatteryWarning: onBattery && PowerSourceMapper.isLowBatteryWarning(IOPSGetBatteryWarningLevel())
        )
    }

    /// Every change, coalesced over `coalescingInterval`; the current snapshot comes first.
    public func snapshots() -> AsyncStream<PowerSnapshot> {
        AsyncStream<PowerSnapshot> { continuation in
            let identifier = UUID()
            let first = current()
            storage.withLock { storage in
                storage.continuations[identifier] = continuation
                storage.lastPublished = first
            }
            continuation.onTermination = { [weak self] _ in
                self?.storage.withLock { $0.continuations[identifier] = nil }
            }
            continuation.yield(first)
        }
    }

    /// Whether the percentage is due for a fresh read (a clock that moved back also counts as due).
    static func shouldReadPercent(lastReadAt: Date?, now: Date, interval: TimeInterval) -> Bool {
        guard let lastReadAt else { return true }
        let elapsed = now.timeIntervalSince(lastReadAt)
        return elapsed < 0 || elapsed >= interval
    }

    private static func descriptions(in blob: CFTypeRef) -> [[String: Any]] {
        guard let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return [] }
        return sources.compactMap { IOPSGetPowerSourceDescription(blob, $0)?.takeUnretainedValue() as? [String: Any] }
    }

    /// One of the three notifications fired: publish the new conditions once the burst has settled. Each
    /// notification raises the generation, so only the last wait of a burst does any work.
    private func conditionsChanged() {
        let generation = storage.withLock { storage -> UInt64 in
            storage.generation &+= 1
            return storage.generation
        }
        queue.asyncAfter(deadline: .now() + Self.coalescingInterval) { [weak self] in
            guard let self, self.storage.withLock({ $0.generation }) == generation else { return }
            self.publish()
        }
    }

    private func publish() {
        let snapshot = current()
        let continuations = storage.withLock { storage -> [AsyncStream<PowerSnapshot>.Continuation] in
            guard storage.lastPublished != snapshot else { return [] }
            storage.lastPublished = snapshot
            return Array(storage.continuations.values)
        }
        continuations.forEach { $0.yield(snapshot) }
    }
}
