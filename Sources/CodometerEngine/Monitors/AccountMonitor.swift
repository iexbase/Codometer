import CodometerCore
import Foundation

/// What a monitor reports about its account. The engine folds these into `TrackerState`.
enum MonitorEvent: Sendable {
    case refreshStarted(AccountID)
    case refreshFinished(AccountID, nextRefreshAt: Date?)
    case reading(AccountID, UsageReading)
    case identity(AccountID, AccountIdentity)
    case sessions(AccountID, [AgentSession])
    case issue(AccountID, TrackerIssue?)
    /// Tokens sessions consumed since their previous samples, batched per burst of log activity.
    case tokenUsage(AccountID, [TokenSample])

    var accountID: AccountID {
        switch self {
        case .refreshStarted(let id), .refreshFinished(let id, _), .reading(let id, _), .identity(let id, _),
             .sessions(let id, _), .issue(let id, _), .tokenUsage(let id, _):
            id
        }
    }
}

/// Watches one account: local files for instant updates plus scheduled live refreshes.
protocol AccountMonitor: Actor {
    func start() async
    func stop()
    /// Refreshes immediately, bypassing backoff and pauses.
    func refreshNow()
    func setPaused(_ paused: Bool)
    /// This account's refresh history and state for the Diagnostics pane, gathered now.
    func diagnostics() -> AccountDiagnostics
    /// Stretches scheduled refreshes and liveness rescans by `factor` (1 = normal); manual refreshes are unaffected.
    func setEnergyFactor(_ factor: EnergyFactor)
}

/// The timer-plus-manual-trigger loop shared by monitors.
///
/// Every refresh request, scheduled or manual, becomes one element in a stream with a buffer of
/// one, so bursts of requests collapse into a single refresh and refreshes never overlap.
struct RefreshLoop: Sendable {
    let triggers: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() {
        (triggers, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    }

    func fire() {
        continuation.yield()
    }

    /// Starts a timer that fires once after `delay`. Cancel the returned task to disarm it.
    func arm(after delay: TimeInterval) -> Task<Void, Never> {
        let seconds = max(delay, 1)
        let continuation = continuation
        return Task {
            try? await Task.sleep(for: .seconds(seconds), tolerance: .seconds(seconds * 0.05))
            guard !Task.isCancelled else { return }
            continuation.yield()
        }
    }

    func finish() {
        continuation.finish()
    }
}

/// Uniform random jitter in -1...1.
func unitJitter() -> Double {
    Double.random(in: -1...1)
}
