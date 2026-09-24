import CodometerCore
import CodometerPlatform
import os
import Foundation

/// Everything that decides whether a status check may run at all, read on the main actor and handed over as one
/// value so the service never reaches back into the UI.
public struct VendorStatusConditions: Hashable, Sendable {
    public static let off = VendorStatusConditions()

    /// `general.showsVendorStatus`.
    public let isEnabled: Bool
    /// A surface that shows status is on screen (expanded island, popover, expanded card).
    public let hasDemand: Bool
    /// Vendors with at least one enabled account; no account for a vendor means its page is never fetched.
    public let providers: Set<ProviderKind>
    public let lowPowerMode: Bool
    public let isOnline: Bool
    public let isConstrained: Bool
    public let isExpensive: Bool

    public init(
        isEnabled: Bool = false,
        hasDemand: Bool = false,
        providers: Set<ProviderKind> = [],
        lowPowerMode: Bool = false,
        isOnline: Bool = true,
        isConstrained: Bool = false,
        isExpensive: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.hasDemand = hasDemand
        self.providers = providers
        self.lowPowerMode = lowPowerMode
        self.isOnline = isOnline
        self.isConstrained = isConstrained
        self.isExpensive = isExpensive
    }

    /// Whether any check may run now.
    public var allowsChecks: Bool {
        isEnabled && hasDemand && !providers.isEmpty && !lowPowerMode && isOnline && !isConstrained && !isExpensive
    }

    /// The vendors to check now, in a stable order.
    public var checkedProviders: [ProviderKind] {
        guard allowsChecks else { return [] }
        return ProviderKind.allCases.filter { providers.contains($0) }
    }
}

/// When the next check of one vendor is due. Pure, so the cadence, the "on show" rule, the backoff and the jitter
/// bounds are all testable without a clock or a network.
public enum VendorStatusPolicy: Sendable {
    /// Normal cadence while a status surface is visible.
    public static let interval: TimeInterval = 600
    /// A surface appearing refreshes a reading only once it is this old.
    public static let refreshOnShowAge: TimeInterval = 300
    /// Failures back off 10 → 20 → 40 → 60 minutes, and never retry faster.
    public static let backoff: [TimeInterval] = [600, 1_200, 2_400, 3_600]
    /// Each delay is spread by ±10 %, so two vendors never march in lockstep.
    public static let jitterFraction = 0.1

    /// The delay after a check: the cadence when it worked, the backoff step when it failed.
    public static func delay(consecutiveFailures: Int) -> TimeInterval {
        guard consecutiveFailures > 0 else { return interval }
        let index = min(consecutiveFailures, backoff.count) - 1
        return backoff[index]
    }

    /// `delay` spread by ±`jitterFraction`; `random` is a fraction of 0…1.
    public static func jittered(_ delay: TimeInterval, random: Double) -> TimeInterval {
        let fraction = min(max(random, 0), 1)
        return delay * (1 - jitterFraction + 2 * jitterFraction * fraction)
    }

    /// When a vendor may be checked again after a check at `lastCheckAt`.
    public static func nextCheck(after lastCheckAt: Date, consecutiveFailures: Int, random: Double) -> Date {
        lastCheckAt.addingTimeInterval(jittered(delay(consecutiveFailures: consecutiveFailures), random: random))
    }

    /// When a status surface appears, a reading older than `refreshOnShowAge` is refreshed at once; a fresher one
    /// keeps its scheduled time, and a vendor in backoff is never pulled forward.
    public static func nextCheckOnShow(scheduled: Date?, lastCheckAt: Date?, consecutiveFailures: Int) -> Date {
        guard let lastCheckAt else { return .distantPast }
        let earliest = lastCheckAt.addingTimeInterval(consecutiveFailures > 0 ? delay(consecutiveFailures: consecutiveFailures) : refreshOnShowAge)
        guard let scheduled else { return earliest }
        return min(scheduled, earliest)
    }
}

/// What one fetch of one vendor produced. The service never sees an error type, so a new transport cannot change
/// its behaviour.
public enum VendorStatusOutcome: Hashable, Sendable {
    /// The feed was read; `nil` means it says nothing about the components Codometer watches.
    case status(ServiceStatus?)
    /// The host answered 304: keep the last reading and only move its timestamp.
    case notModified
    /// Anything else. The reason is for the log, never for the user.
    case failed(String)
}

/// Fetches one vendor's public status page.
public protocol VendorStatusFetching: Sendable {
    func fetch(_ provider: ProviderKind, checkedAt: Date) async -> VendorStatusOutcome
}

/// Production fetcher: the bounded HTTPS client plus the pure parser, and nothing else.
public struct LiveVendorStatusFetcher: VendorStatusFetching {
    private let client: StatusFeedClient

    public init(client: StatusFeedClient = StatusFeedClient()) {
        self.client = client
    }

    public func fetch(_ provider: ProviderKind, checkedAt: Date) async -> VendorStatusOutcome {
        do throws(StatusFeedError) {
            switch try await client.fetch(VendorStatusFeed.url(for: provider)) {
            case .notModified:
                return .notModified
            case .updated(let data):
                return .status(VendorStatusParsing.status(provider: provider, data: data, checkedAt: checkedAt))
            }
        } catch {
            return .failed(error.description)
        }
    }
}

/// Checks the vendors' public status pages while, and only while, the user asked for it and a surface that shows the
/// result is on screen.
///
/// Nothing is persisted and nothing is scheduled in advance: the service holds one task that sleeps until the next
/// vendor is due, and `update(_:)` cancels it the moment the conditions stop allowing checks (the toggle going off
/// mid-backoff, the last surface closing, Low Power Mode, going offline).
public actor VendorStatusService {
    private let fetcher: any VendorStatusFetching
    private let publish: @Sendable (ServiceStatusBoard) -> Void
    private let now: @Sendable () -> Date
    private let random: @Sendable () -> Double
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    private struct VendorState {
        var lastCheckAt: Date?
        var nextCheckAt: Date = .distantPast
        var consecutiveFailures = 0
    }

    private var states: [ProviderKind: VendorState] = [:]
    private var conditions: VendorStatusConditions = .off
    private var board: ServiceStatusBoard = .empty
    private var loop: Task<Void, Never>?

    public init(
        fetcher: any VendorStatusFetching,
        publish: @escaping @Sendable (ServiceStatusBoard) -> Void,
        now: @escaping @Sendable () -> Date = { Date() },
        random: @escaping @Sendable () -> Double = { Double.random(in: 0...1) },
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
            try await Task.sleep(for: .seconds(seconds), tolerance: .seconds(min(30, max(1, seconds / 10))))
        }
    ) {
        self.fetcher = fetcher
        self.publish = publish
        self.now = now
        self.random = random
        self.sleep = sleep
    }

    /// Whether a checking loop is running right now.
    public var isRunning: Bool { loop != nil }

    /// Applies new conditions: starts checking, brings a stale vendor forward when a surface appears, or stops
    /// everything at once.
    public func update(_ conditions: VendorStatusConditions) {
        let appeared = conditions.hasDemand && !self.conditions.hasDemand
        self.conditions = conditions
        guard conditions.allowsChecks else {
            stop()
            return
        }
        if appeared {
            for provider in conditions.checkedProviders {
                var state = states[provider] ?? VendorState()
                state.nextCheckAt = VendorStatusPolicy.nextCheckOnShow(
                    scheduled: state.lastCheckAt == nil ? nil : state.nextCheckAt,
                    lastCheckAt: state.lastCheckAt,
                    consecutiveFailures: state.consecutiveFailures
                )
                states[provider] = state
            }
        }
        startLoop()
    }

    /// Stops checking and drops the loop; readings already taken stay until they age out of the board.
    public func stop() {
        loop?.cancel()
        loop = nil
    }

    private func startLoop() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let delay = await self.tick() else { return }
                do {
                    try await self.sleepFor(delay)
                } catch {
                    return
                }
            }
        }
    }

    private func sleepFor(_ seconds: TimeInterval) async throws {
        try await sleep(seconds)
    }

    /// One round: checks every vendor that is due and returns how long to sleep before the next round,
    /// or `nil` when checks are no longer allowed.
    func tick() async -> TimeInterval? {
        guard conditions.allowsChecks else {
            stop()
            return nil
        }
        let providers = conditions.checkedProviders
        for provider in providers where (states[provider] ?? VendorState()).nextCheckAt <= now() {
            await check(provider)
            // The conditions may have changed while the request was in flight.
            guard conditions.allowsChecks else { return nil }
        }
        let current = now()
        let next = conditions.checkedProviders
            .compactMap { states[$0]?.nextCheckAt }
            .min() ?? current.addingTimeInterval(VendorStatusPolicy.interval)
        return max(1, next.timeIntervalSince(current))
    }

    private func check(_ provider: ProviderKind) async {
        let checkedAt = now()
        let outcome = await fetcher.fetch(provider, checkedAt: checkedAt)
        var state = states[provider] ?? VendorState()
        state.lastCheckAt = checkedAt
        switch outcome {
        case .status(let status):
            state.consecutiveFailures = 0
            board.statuses[provider] = status
            board.lastFailureAt[provider] = nil
        case .notModified:
            state.consecutiveFailures = 0
            // The reading did not change, but it is this fresh: keep it visible.
            if let previous = board.statuses[provider] {
                board.statuses[provider] = ServiceStatus(
                    provider: previous.provider,
                    level: previous.level,
                    affectedComponents: previous.affectedComponents,
                    checkedAt: checkedAt
                )
            }
            board.lastFailureAt[provider] = nil
        case .failed(let reason):
            state.consecutiveFailures += 1
            board.lastFailureAt[provider] = checkedAt
            AppLog.engine.notice("service status check failed for \(provider.rawValue, privacy: .public): \(reason, privacy: .public)")
        }
        state.nextCheckAt = VendorStatusPolicy.nextCheck(
            after: checkedAt,
            consecutiveFailures: state.consecutiveFailures,
            random: random()
        )
        states[provider] = state
        publish(board)
    }
}
