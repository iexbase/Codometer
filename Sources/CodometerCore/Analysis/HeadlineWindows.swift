import Foundation

/// The windows an account's ring shows: a fixed primary window and an optional secondary one.
///
/// The primary window is chosen by meaning (the session window, else the shortest),
/// never by which window is currently highest, so the ring keeps its meaning between refreshes.
/// The remaining properties describe the whole main bucket: which window binds, whether
/// the account is blocked, and the order every window is listed in.
public struct HeadlineWindows: Hashable, Sendable {
    public let bucket: LimitBucket
    public let primary: LimitWindow
    public let secondary: LimitWindow?
    /// The model-scoped weekly window (`weekly(model:)` with a model) with the highest usage, if any.
    public let modelWeekly: LimitWindow?
    /// The main-bucket window with the highest usage; ties go to the shorter window.
    public let binding: LimitWindow

    public init(reading: UsageReading) {
        let bucket = reading.mainBucket
        let primary = Self.primaryWindow(in: bucket)
        self.bucket = bucket
        self.primary = primary
        secondary = Self.secondaryWindow(in: bucket, excluding: primary)
        modelWeekly = Self.highestModelWeekly(in: bucket.windows)
        binding = Self.bindingWindow(in: bucket)
    }

    /// Whether any main-bucket window is exhausted or the provider reports the bucket's limit as reached.
    public var isBlocked: Bool {
        bucket.isLimitReached || bucket.windows.contains { $0.used.isExhausted }
    }

    /// Among exhausted windows, the one that resets last — the one that actually keeps the account blocked.
    ///
    /// A window with an unknown reset time counts as resetting after every known one, so the account is
    /// never shown as available earlier than it is. `nil` when no window is exhausted.
    public var blockingWindow: LimitWindow? {
        // `max(by:)` keeps the first of equal elements, so ties go to the earlier window in bucket order.
        bucket.windows
            .filter { $0.used.isExhausted }
            .max { lhs, rhs in
                switch (lhs.resetsAt, rhs.resetsAt) {
                case let (left?, right?):
                    left < right
                case (.some, nil):
                    true
                case (nil, _):
                    false
                }
            }
    }

    /// Main-bucket windows in display order: session, weekly all models, model-scoped weeks
    /// (highest usage first), then everything else in the provider's order.
    public var allWindows: [LimitWindow] {
        Self.displayOrder(bucket.windows)
    }

    // MARK: - Selection

    private static func primaryWindow(in bucket: LimitBucket) -> LimitWindow {
        if let session = bucket.windows.first(where: { $0.scope == .session }) {
            return session
        }
        let timed = bucket.windows.filter { $0.duration != nil }
        if let shortest = timed.min(by: { lhs, rhs in
            (lhs.duration?.minutes ?? .max) < (rhs.duration?.minutes ?? .max)
        }) {
            return shortest
        }
        return bucket.windows[0]
    }

    private static func secondaryWindow(in bucket: LimitBucket, excluding primary: LimitWindow) -> LimitWindow? {
        let others = bucket.windows.filter { $0.id != primary.id }
        if let allModelsWeek = others.first(where: { $0.scope == .weekly(model: nil) }) {
            return allModelsWeek
        }
        return others.first
    }

    private static func highestModelWeekly(in windows: [LimitWindow]) -> LimitWindow? {
        // `max(by:)` keeps the first of equal elements, i.e. the earlier window in bucket order.
        windows
            .filter(\.isModelWeekly)
            .max { $0.used < $1.used }
    }

    private static func bindingWindow(in bucket: LimitBucket) -> LimitWindow {
        var best = bucket.windows[0]
        for window in bucket.windows.dropFirst() {
            if window.used > best.used {
                best = window
            } else if window.used == best.used, durationRank(window) < durationRank(best) {
                best = window
            }
        }
        return best
    }

    /// Unknown durations rank as the longest.
    private static func durationRank(_ window: LimitWindow) -> Int {
        window.duration?.minutes ?? .max
    }

    static func displayOrder(_ windows: [LimitWindow]) -> [LimitWindow] {
        let sessions = windows.filter { $0.scope == .session }
        let allModels = windows.filter { $0.scope == .weekly(model: nil) }
        let models = windows.enumerated()
            .filter { $0.element.isModelWeekly }
            .sorted { lhs, rhs in
                lhs.element.used == rhs.element.used ? lhs.offset < rhs.offset : lhs.element.used > rhs.element.used
            }
            .map(\.element)
        let others = windows.filter { $0.scope == .rolling }
        return sessions + allModels + models + others
    }
}

extension LimitWindow {
    /// A weekly window limited to one model ("Current week (Sonnet only)").
    var isModelWeekly: Bool {
        if case .weekly(let model) = scope { return model != nil }
        return false
    }
}
