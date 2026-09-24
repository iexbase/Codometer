import CodometerCore
import Foundation

/// Pure timing rules for background refreshes.
public enum RefreshSchedule {
    public static let maximumBackoff: TimeInterval = 30 * 60
    public static let minimumDelay: TimeInterval = 30
    /// Wake this long after a window resets, so the provider has already rolled it over.
    public static let resetSettleDelay: TimeInterval = 30
    public static let jitterFraction = 0.1

    /// The regular interval, doubled per consecutive failure up to `maximumBackoff`, with ±10 % jitter
    /// so several accounts do not refresh in lockstep. `jitter` is a unit value in -1...1.
    public static func delay(interval: PollInterval, consecutiveFailures: Int, jitter: Double) -> TimeInterval {
        precondition((-1...1).contains(jitter), "jitter must be a unit value")
        let base = interval.timeInterval
        let exponent = min(max(consecutiveFailures, 0), 10)
        let backedOff = min(base * pow(2, Double(exponent)), max(base, maximumBackoff))
        return max(minimumDelay, backedOff * (1 + jitter * jitterFraction))
    }

    /// Brings the delay forward so the app refreshes shortly after the next window reset.
    public static func delay(_ delay: TimeInterval, wakingForResetsIn reading: UsageReading?, now: Date) -> TimeInterval {
        guard let reading else { return delay }
        let nextReset = reading.buckets
            .flatMap(\.windows)
            .compactMap(\.resetsAt)
            .filter { $0 > now }
            .min()
        guard let nextReset else { return delay }
        let untilSettled = nextReset.timeIntervalSince(now) + resetSettleDelay
        return max(minimumDelay, min(delay, untilSettled))
    }

    /// Caps the delay while a limit is nearly used up, when fresh numbers matter most.
    public static func delay(
        _ delay: TimeInterval,
        urgentAbove threshold: Double,
        cap: TimeInterval,
        reading: UsageReading?
    ) -> TimeInterval {
        guard let reading else { return delay }
        let headline = HeadlineWindows(reading: reading)
        let urgent = [headline.primary, headline.secondary].compactMap { $0 }.contains { window in
            window.used.value >= threshold && !window.used.isExhausted
        }
        return urgent ? max(minimumDelay, min(delay, cap)) : delay
    }
}

/// Energy-aware scaling of scheduled delays (item 19).
extension RefreshSchedule {
    /// Stretches a scheduled delay by the energy factor, keeping it inside the schedule's own bounds.
    ///
    /// Applied to the regular interval and the failure backoff, never after the reset and urgency caps: a stretched
    /// schedule still refreshes right after a window reset and while a limit is nearly used up.
    public static func scaled(_ delay: TimeInterval, by factor: EnergyFactor) -> TimeInterval {
        min(max(minimumDelay, delay * factor.value), maximumBackoff)
    }

    /// The urgent-cap multiplier that belongs to a scheduling factor.
    ///
    /// Monitors receive only the scheduling factor (`AccountMonitor.setEnergyFactor`), so the gentler multiplier for
    /// the ≥ 90 % cap is derived from it. `EnergyPolicy` combines conditions by maximum and every condition's cap
    /// rises with its factor, so this reproduces `EnergyDecision.urgentCapFactor` exactly (proved in
    /// `RefreshScheduleEnergyTests`).
    public static func urgentCapFactor(for factor: EnergyFactor) -> EnergyFactor {
        let value: Double = switch factor.value {
        case ..<2: 1
        case ..<3: 1.5
        default: 2
        }
        return (try? EnergyFactor(value)) ?? .normal
    }
}

/// When an armed refresh timer moves after the energy factor changed (item 19, "re-arm rule").
///
/// A decrease (the Mac was plugged in, cooled down, left Low Power Mode) may bring the next refresh forward; an
/// increase never postpones a refresh that is already armed — the next schedule uses the new factor.
public enum RefreshTimerPlan {
    /// A re-armed refresh never fires sooner than this after the change, so a burst of power events cannot cause a
    /// burst of probes.
    public static let minimumLead: TimeInterval = 5
    /// Moving the deadline is only worth it when it saves at least this much, so a flapping thermal state does not
    /// keep rescheduling the same refresh.
    public static let minimumSaving: TimeInterval = 30

    /// The new deadline for an armed timer, or `nil` to keep the one that is armed.
    ///
    /// - Parameters:
    ///   - armedAt: the deadline the monitor's timer is armed for; `nil` when no timer is armed.
    ///   - lastRefreshAt: when the account last refreshed; `nil` means "as if it just refreshed".
    ///   - newDelay: the delay the new factor produces.
    public static func rearm(
        armedAt: Date?,
        lastRefreshAt: Date?,
        newDelay: TimeInterval,
        now: Date
    ) -> Date? {
        guard let armedAt else { return nil }
        let target = (lastRefreshAt ?? now).addingTimeInterval(newDelay)
        guard target < armedAt else { return nil }
        let candidate = max(now.addingTimeInterval(minimumLead), target)
        guard armedAt.timeIntervalSince(candidate) >= minimumSaving else { return nil }
        return candidate
    }
}
