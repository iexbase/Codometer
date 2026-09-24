import Foundation

/// What a limit window measures.
public enum LimitWindowScope: Hashable, Sendable, Codable {
    /// Claude's rolling "current session" window.
    case session
    /// A weekly window; `model` names a model-specific limit, `nil` means all models.
    case weekly(model: String?)
    /// A window described only by its duration (Codex primary/secondary windows).
    case rolling
}

/// One usage-limit window: how much is used and when it resets.
public struct LimitWindow: Hashable, Sendable, Identifiable {
    public static let maximumLabelLength = 60

    public let id: String
    public let scope: LimitWindowScope
    public let used: Percentage
    public let duration: WindowDuration?
    public let resetsAt: Date?
    /// The provider's own title for a window without a semantic mapping ("Current week (Opus)"),
    /// sanitised; `nil` when the provider gave none.
    public let label: String?

    public init(
        id: String,
        scope: LimitWindowScope,
        used: Percentage,
        duration: WindowDuration?,
        resetsAt: Date?,
        label: String? = nil
    ) throws(ValidationError) {
        self.id = try StableIdentifier.validate(id, field: "window.id")
        if case .weekly(let model?) = scope {
            guard DisplayText.sanitize(model, maximumLength: 60) == model else {
                throw .invalidCharacters(field: "window.scope.model")
            }
        }
        self.scope = scope
        self.used = used
        self.duration = duration
        self.resetsAt = resetsAt
        self.label = DisplayText.sanitize(label, maximumLength: Self.maximumLabelLength)
    }

    /// Seconds until the reset, or `nil` when the reset time is unknown. Negative once it has passed.
    public func timeUntilReset(from now: Date) -> TimeInterval? {
        resetsAt.map { $0.timeIntervalSince(now) }
    }

    public func hasReset(at now: Date) -> Bool {
        guard let resetsAt else { return false }
        return resetsAt <= now
    }

    /// Start of the current window, when both the duration and the reset time are known.
    public var windowStart: Date? {
        guard let resetsAt, let duration else { return nil }
        return resetsAt.addingTimeInterval(-duration.timeInterval)
    }
}

extension LimitWindow: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, scope, used, duration, resetsAt, label
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let scope = try container.decode(LimitWindowScope.self, forKey: .scope)
        let used = try container.decode(Percentage.self, forKey: .used)
        let duration = try container.decodeIfPresent(WindowDuration.self, forKey: .duration)
        let resetsAt = try container.decodeIfPresent(Date.self, forKey: .resetsAt)
        let label = try container.decodeIfPresent(String.self, forKey: .label)
        do throws(ValidationError) {
            self = try LimitWindow(id: id, scope: scope, used: used, duration: duration, resetsAt: resetsAt, label: label)
        } catch {
            throw error.decodingError(at: container.codingPath)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(scope, forKey: .scope)
        try container.encode(used, forKey: .used)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encodeIfPresent(resetsAt, forKey: .resetsAt)
        try container.encodeIfPresent(label, forKey: .label)
    }
}

/// A group of windows metered together, e.g. Codex's `codex` bucket or a model-specific bucket.
public struct LimitBucket: Hashable, Sendable, Identifiable {
    public static let maximumWindows = 8

    public let id: String
    public let title: String?
    public let windows: [LimitWindow]
    public let isLimitReached: Bool

    public init(id: String, title: String?, windows: [LimitWindow], isLimitReached: Bool) throws(ValidationError) {
        self.id = try StableIdentifier.validate(id, field: "bucket.id")
        guard !windows.isEmpty else { throw .empty(field: "bucket.windows") }
        guard windows.count <= Self.maximumWindows else {
            throw .tooLong(field: "bucket.windows", length: windows.count, maximum: Self.maximumWindows)
        }
        var seen = Set<String>()
        for window in windows where !seen.insert(window.id).inserted {
            throw .duplicate(field: "bucket.windows.id", value: window.id)
        }
        self.title = DisplayText.sanitize(title, maximumLength: 60)
        self.windows = windows
        self.isLimitReached = isLimitReached
    }

    public func window(id: String) -> LimitWindow? {
        windows.first { $0.id == id }
    }
}

extension LimitBucket: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, title, windows, isLimitReached
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let title = try container.decodeIfPresent(String.self, forKey: .title)
        let windows = try container.decode([LimitWindow].self, forKey: .windows)
        let isLimitReached = try container.decodeIfPresent(Bool.self, forKey: .isLimitReached) ?? false
        do throws(ValidationError) {
            self = try LimitBucket(id: id, title: title, windows: windows, isLimitReached: isLimitReached)
        } catch {
            throw error.decodingError(at: container.codingPath)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encode(windows, forKey: .windows)
        try container.encode(isLimitReached, forKey: .isLimitReached)
    }
}

/// Prepaid credits reported alongside Codex limits.
public struct CreditsInfo: Hashable, Sendable, Codable {
    public let hasCredits: Bool
    public let isUnlimited: Bool
    public let balance: Decimal?

    public init(hasCredits: Bool, isUnlimited: Bool, balance: Decimal?) {
        self.hasCredits = hasCredits
        self.isUnlimited = isUnlimited
        self.balance = balance
    }
}

/// Where a reading came from. Readings from different sources are interchangeable.
public enum ReadingSource: String, Sendable, Codable, CaseIterable {
    case claudeUsageCommand
    case codexAppServer
    case codexSessionLog
}

/// A complete usage-limit reading for one account at one moment.
public struct UsageReading: Hashable, Sendable {
    public static let maximumBuckets = 8

    /// When the numbers were true — not when the app received them.
    public let capturedAt: Date
    public let source: ReadingSource
    /// The first bucket is the account's main one.
    public let buckets: [LimitBucket]
    public let credits: CreditsInfo?

    public init(
        capturedAt: Date,
        source: ReadingSource,
        buckets: [LimitBucket],
        credits: CreditsInfo?
    ) throws(ValidationError) {
        guard !buckets.isEmpty else { throw .empty(field: "reading.buckets") }
        guard buckets.count <= Self.maximumBuckets else {
            throw .tooLong(field: "reading.buckets", length: buckets.count, maximum: Self.maximumBuckets)
        }
        var seen = Set<String>()
        for bucket in buckets where !seen.insert(bucket.id).inserted {
            throw .duplicate(field: "reading.buckets.id", value: bucket.id)
        }
        self.capturedAt = capturedAt
        self.source = source
        self.buckets = buckets
        self.credits = credits
    }

    public var mainBucket: LimitBucket { buckets[0] }

    public func bucket(id: String) -> LimitBucket? {
        buckets.first { $0.id == id }
    }

    /// True when any window's reset time has passed, i.e. the reading no longer describes the present.
    public func containsExpiredWindow(at now: Date) -> Bool {
        buckets.contains { bucket in bucket.windows.contains { $0.hasReset(at: now) } }
    }

    public var isAnyLimitReached: Bool {
        buckets.contains { bucket in bucket.isLimitReached || bucket.windows.contains { $0.used.isExhausted } }
    }
}

extension UsageReading: Codable {
    private enum CodingKeys: String, CodingKey {
        case capturedAt, source, buckets, credits
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        let source = try container.decode(ReadingSource.self, forKey: .source)
        let buckets = try container.decode([LimitBucket].self, forKey: .buckets)
        let credits = try container.decodeIfPresent(CreditsInfo.self, forKey: .credits)
        do throws(ValidationError) {
            self = try UsageReading(capturedAt: capturedAt, source: source, buckets: buckets, credits: credits)
        } catch {
            throw error.decodingError(at: container.codingPath)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(capturedAt, forKey: .capturedAt)
        try container.encode(source, forKey: .source)
        try container.encode(buckets, forKey: .buckets)
        try container.encodeIfPresent(credits, forKey: .credits)
    }
}
