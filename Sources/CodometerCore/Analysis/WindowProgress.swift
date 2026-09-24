import Foundation

/// What a ring draws for one window: the used arc, a "now" notch for the elapsed share of the window,
/// the overrun where usage runs ahead of time, and day or hour ticks.
public struct WindowProgress: Hashable, Sendable {
    /// Windows at least this long count as weekly and get one tick per day.
    public static let weeklyTickThreshold: TimeInterval = 6 * 24 * 60 * 60

    /// Used share of the limit, clamped to 0...1.
    public let used: Double
    /// Share of the window's time that has passed, 0...1; `nil` when the duration or reset time is unknown.
    public let elapsed: Double?
    /// How far usage runs ahead of time: `max(0, used − elapsed)`, or 0 when `elapsed` is unknown.
    public let overrun: Double
    /// 7 for weekly windows (six days or longer), 5 for five-hour windows, 0 otherwise.
    public let tickCount: Int

    public init(window: LimitWindow, now: Date) {
        let used = window.used.clampedFraction
        let elapsed = Self.elapsedFraction(of: window, now: now)
        self.used = used
        self.elapsed = elapsed
        overrun = elapsed.map { max(0, used - $0) } ?? 0
        tickCount = Self.tickCount(for: window)
    }

    /// A reset further away than one window (clock skew) clamps to the window start; a passed reset to its end.
    static func elapsedFraction(of window: LimitWindow, now: Date) -> Double? {
        guard let resetsAt = window.resetsAt, let duration = window.duration else { return nil }
        let length = duration.timeInterval
        let remaining = resetsAt.timeIntervalSince(now)
        guard length > 0, remaining.isFinite else { return nil }
        let clampedRemaining = min(max(remaining, 0), length)
        return (length - clampedRemaining) / length
    }

    static func tickCount(for window: LimitWindow) -> Int {
        guard let duration = window.duration else {
            // Without a duration the scope still tells the window's rhythm.
            switch window.scope {
            case .weekly: return 7
            case .session: return 5
            case .rolling: return 0
            }
        }
        if duration.timeInterval >= weeklyTickThreshold { return 7 }
        if duration == .fiveHours { return 5 }
        return 0
    }
}
