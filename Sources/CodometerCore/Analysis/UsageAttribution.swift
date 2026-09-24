import Foundation

/// What usage is split by.
public enum AttributionGrouping: String, Sendable, CaseIterable {
    case project
    case session
}

/// What an attribution share is about. Views put it into words; no language is baked into the report.
public enum AttributionSubject: Hashable, Sendable {
    /// A project, by its folder name (sanitised, at most `AttributionShare.maximumTitleLength` characters).
    case project(String)
    /// A session, by its project folder and the end of its id.
    case session(SessionLabelParts)
    /// The smallest shares folded together.
    case other
    /// Tokens whose session had no project folder.
    case noProject

    /// A language-neutral key that orders equally weighted shares stably: named subjects by name, then sessions
    /// without a project, then the unnamed groups.
    var sortKey: String {
        switch self {
        case .project(let name): "0" + name
        case .session(let parts): (parts.folder == nil ? "1" : "0") + parts.machineForm
        case .noProject: "2"
        case .other: "3"
        }
    }
}

/// One project's or session's part of the attributed usage.
public struct AttributionShare: Hashable, Sendable, Identifiable {
    public static let maximumTitleLength = 80

    public let id: String
    public let subject: AttributionSubject
    /// Weighted tokens (input-token equivalents, see `TokenCounts.weighted(for:)`).
    public let weightedTokens: Double
    /// 0...1 of all attributed weighted tokens.
    public let share: Double
    /// ≈ percentage points of the reference window this share consumed, when the window's usage is known.
    public let estimatedPoints: Double?

    public init(
        id: String,
        subject: AttributionSubject,
        weightedTokens: Double,
        share: Double,
        estimatedPoints: Double?
    ) throws(ValidationError) {
        guard !id.isEmpty else { throw .empty(field: "attribution.id") }
        guard weightedTokens.isFinite else { throw .notFinite(field: "attribution.weightedTokens") }
        guard weightedTokens >= 0 else {
            throw .outOfRange(
                field: "attribution.weightedTokens",
                value: weightedTokens,
                lowerBound: 0,
                upperBound: .greatestFiniteMagnitude
            )
        }
        guard share.isFinite else { throw .notFinite(field: "attribution.share") }
        guard (0...1).contains(share) else {
            throw .outOfRange(field: "attribution.share", value: share, lowerBound: 0, upperBound: 1)
        }
        if let estimatedPoints {
            guard estimatedPoints.isFinite else { throw .notFinite(field: "attribution.estimatedPoints") }
            guard estimatedPoints >= 0 else {
                throw .outOfRange(
                    field: "attribution.estimatedPoints",
                    value: estimatedPoints,
                    lowerBound: 0,
                    upperBound: .greatestFiniteMagnitude
                )
            }
        }
        self.init(
            trustedID: id,
            subject: subject,
            weightedTokens: weightedTokens,
            share: share,
            estimatedPoints: estimatedPoints
        )
    }

    /// For values computed by `UsageAttribution`, which are finite and in range by construction.
    fileprivate init(trustedID id: String, subject: AttributionSubject, weightedTokens: Double, share: Double, estimatedPoints: Double?) {
        self.id = id
        self.subject = Self.sanitized(subject)
        self.weightedTokens = weightedTokens
        self.share = min(max(share, 0), 1)
        self.estimatedPoints = estimatedPoints
    }

    /// A project name that sanitises to nothing counts as no project.
    private static func sanitized(_ subject: AttributionSubject) -> AttributionSubject {
        guard case .project(let name) = subject else { return subject }
        return DisplayText.sanitize(name, maximumLength: maximumTitleLength).map(AttributionSubject.project) ?? .noProject
    }
}

/// "What's eating your limit": how an interval's token usage splits across projects or sessions.
public struct AttributionReport: Hashable, Sendable {
    public let interval: DateInterval
    /// The reference window (the headline primary window) whose points the shares are estimated in, if known.
    public let windowTitleSource: LimitWindow?
    /// Percentage points the reference window gained in the interval while tokens were collected (when the caller
    /// knows the collection runs); `nil` without enough usage history inside those runs.
    public let usedPoints: Double?
    /// Sorted by weighted tokens, largest first: at most `UsageAttribution.maximumNamedShares` named shares,
    /// then one `.other` share folding the rest.
    public let shares: [AttributionShare]
    public let totalWeightedTokens: Double
    /// Where token data of the interval begins. The engine reports when live collection began for the account (or
    /// the earliest stored bucket, if older), clamped into the interval, so it may equal the interval's end;
    /// `UsageAttribution.report` alone uses the earliest sample. Token data is collected live, so views show
    /// "Data since HH:mm" when this is later than the interval start; `nil` when unknown.
    public let coverageStart: Date?

    public init(
        interval: DateInterval,
        windowTitleSource: LimitWindow?,
        usedPoints: Double?,
        shares: [AttributionShare],
        totalWeightedTokens: Double,
        coverageStart: Date? = nil
    ) {
        self.interval = interval
        self.windowTitleSource = windowTitleSource
        self.usedPoints = usedPoints
        self.shares = shares
        self.totalWeightedTokens = totalWeightedTokens
        self.coverageStart = coverageStart
    }

    public var isEmpty: Bool { shares.isEmpty }
}

/// Splits measured limit usage across the projects or sessions that spent tokens.
///
/// Limits are metered per account, so the split is an estimate: each group's share of weighted tokens in
/// the interval, applied to the percentage points the reference window gained over the same interval while tokens
/// were being collected (see `consumedPoints(in:interval:collectionStarts:)`).
public enum UsageAttribution {
    /// Groups beyond this many are folded into one `.other` share.
    public static let maximumNamedShares = 8
    /// A drop at least this large between two observations means a new window period.
    public static let periodDropPoints = 20.0

    public static let otherShareID = "other"

    public static func report(
        samples: [TokenSample],
        provider: ProviderKind,
        usage: HistorySeries?,
        interval: DateInterval,
        grouping: AttributionGrouping,
        reference: LimitWindow?,
        collectionStarts: [Date]? = nil
    ) -> AttributionReport {
        let inInterval = samples.filter { interval.contains($0.at) }
        let groups = weightedGroups(
            samples: inInterval,
            provider: provider,
            grouping: grouping
        )
        .filter { $0.weight > 0 }
        .sorted { lhs, rhs in
            if lhs.weight != rhs.weight { return lhs.weight > rhs.weight }
            if lhs.subject.sortKey != rhs.subject.sortKey { return lhs.subject.sortKey < rhs.subject.sortKey }
            return lhs.id < rhs.id
        }

        let total = groups.reduce(0) { $0 + $1.weight }
        let usedPoints = usage.flatMap { series -> Double? in
            if let collectionStarts {
                return consumedPoints(in: series, interval: interval, collectionStarts: collectionStarts)
            }
            return series.points.lazy.filter { interval.contains($0.at) }.count >= 2
                ? consumedPoints(in: series, interval: interval)
                : nil
        }

        var folded = Array(groups.prefix(maximumNamedShares))
        if groups.count > maximumNamedShares {
            let rest = groups.dropFirst(maximumNamedShares).reduce(0) { $0 + $1.weight }
            folded.append(WeightedGroup(id: otherShareID, subject: .other, weight: rest))
        }

        var shares: [AttributionShare] = []
        if total > 0 {
            for group in folded {
                let share = group.weight / total
                shares.append(AttributionShare(
                    trustedID: group.id,
                    subject: group.subject,
                    weightedTokens: group.weight,
                    share: share,
                    estimatedPoints: usedPoints.map { share * $0 }
                ))
            }
        }

        return AttributionReport(
            interval: interval,
            windowTitleSource: reference,
            usedPoints: usedPoints,
            shares: shares,
            totalWeightedTokens: total,
            coverageStart: inInterval.lazy.map(\.at).min()
        )
    }

    /// Sum of positive deltas between consecutive observations inside the interval.
    ///
    /// A drop of at least 20 points or a reset marker between two observations starts a new period: the later
    /// observation's whole value counts as consumed since the reset, and the drop is never negative usage.
    /// Smaller drops are source noise and count as zero.
    public static func consumedPoints(in series: HistorySeries, interval: DateInterval) -> Double {
        let points = series.points.filter { interval.contains($0.at) }
        var consumed = 0.0
        var resets = series.resets[...]
        for (previous, current) in zip(points, points.dropFirst()) {
            consumed += delta(from: previous, to: current, resets: &resets)
        }
        return consumed
    }

    /// Like `consumedPoints(in:interval:)`, but only over the stretches token data exists for.
    ///
    /// Tokens are collected live, from the moments in `collectionStarts` (app launches, wakes, accounts enabled)
    /// until the app stops. An observation belongs to the run of the latest start at or before it, and a pair of
    /// observations counts only when both belong to the same run. So usage from before collection first began, or
    /// from while the app was quit or the Mac slept, is never credited to the projects whose tokens were recorded.
    /// `nil` when no pair qualifies, so an estimate is never made from nothing.
    public static func consumedPoints(in series: HistorySeries, interval: DateInterval, collectionStarts: [Date]) -> Double? {
        let points = series.points.filter { interval.contains($0.at) }
        var consumed = 0.0
        var counted = false
        var resets = series.resets[...]
        var laterStarts = collectionStarts.sorted()[...]
        var hasRun = false
        for (previous, current) in zip(points, points.dropFirst()) {
            while let start = laterStarts.first, start <= previous.at {
                hasRun = true
                laterStarts = laterStarts.dropFirst()
            }
            let pointsConsumed = delta(from: previous, to: current, resets: &resets)
            let restartedBetween = laterStarts.first.map { $0 <= current.at } ?? false
            guard hasRun, !restartedBetween else { continue }
            consumed += pointsConsumed
            counted = true
        }
        return counted ? consumed : nil
    }

    /// Points consumed from one observation to the next; `resets` drops the markers at or before `previous`.
    private static func delta(from previous: UsagePoint, to current: UsagePoint, resets: inout ArraySlice<Date>) -> Double {
        while let reset = resets.first, reset <= previous.at {
            resets = resets.dropFirst()
        }
        let resetBetween = resets.first.map { $0 <= current.at } ?? false
        if resetBetween || previous.used - current.used >= periodDropPoints {
            return current.used
        }
        return max(0, current.used - previous.used)
    }

    // MARK: - Grouping

    private struct WeightedGroup {
        let id: String
        let subject: AttributionSubject
        let weight: Double
    }

    private static func weightedGroups(
        samples: [TokenSample],
        provider: ProviderKind,
        grouping: AttributionGrouping
    ) -> [WeightedGroup] {
        var weights: [String: Double] = [:]
        var sessionIDs: [String: String] = [:]
        // Project grouping: the group's project. Session grouping: the session's latest known project.
        var projects: [String: (at: Date, project: String)] = [:]

        for sample in samples {
            let key = groupID(for: sample, grouping: grouping)
            let weight = sample.delta.weighted(for: provider)
            weights[key, default: 0] += weight.isFinite ? max(weight, 0) : 0
            sessionIDs[key] = sample.sessionID
            if let project = sample.project, projects[key].map({ $0.at <= sample.at }) ?? true {
                projects[key] = (sample.at, project)
            }
        }
        return weights.map { key, weight in
            let project = projects[key]?.project
            let subject = switch grouping {
            case .project: projectSubject(project)
            case .session: AttributionSubject.session(SessionLabel.parts(sessionID: sessionIDs[key] ?? key, projectFolder: project))
            }
            return WeightedGroup(id: key, subject: subject, weight: weight)
        }
    }

    private static func groupID(for sample: TokenSample, grouping: AttributionGrouping) -> String {
        switch grouping {
        case .project: "project:" + (sample.project ?? "")
        case .session: "session:" + sample.sessionID
        }
    }

    private static func projectSubject(_ project: String?) -> AttributionSubject {
        SessionLabel.folder(of: project).map(AttributionSubject.project) ?? .noProject
    }
}
