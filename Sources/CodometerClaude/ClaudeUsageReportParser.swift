import CodometerCore
import Foundation

public enum ClaudeUsageParseError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The profile is billed through an API key, which has no subscription limits.
    case notSubscription
    case signedOut
    /// None of the expected limit lines were present — the output format may have changed.
    case noLimitLines
    case invalidWindow(ValidationError)

    public var description: String {
        switch self {
        case .notSubscription: "profile uses API billing, not a subscription"
        case .signedOut: "profile is not signed in"
        case .noLimitLines: "no usage limit lines in the output"
        case .invalidWindow(let error): "invalid limit window: \(error.description)"
        }
    }
}

/// What one `/usage` output looked like, beyond the limits it carried.
///
/// The counts feed `FormatDrift`: they say that Claude Code printed something this version does not recognise, never
/// what the user was doing. Titles are provider UI text ("Current month (spend)"), never conversation.
public struct ClaudeParseStats: Hashable, Sendable {
    /// Titles of limit windows without a semantic mapping, in the order they appeared.
    public let genericTitles: [String]
    /// Limit-shaped lines whose value did not validate and were dropped.
    public let droppedInvalid: Int
    /// The "What's contributing to your limits usage?" section was present.
    public let sawContributingHeading: Bool

    public init(genericTitles: [String] = [], droppedInvalid: Int = 0, sawContributingHeading: Bool = false) {
        self.genericTitles = genericTitles
        self.droppedInvalid = max(0, droppedInvalid)
        self.sawContributingHeading = sawContributingHeading
    }

    public static let empty = ClaudeParseStats()
}

/// Parses the text Claude Code prints for `claude --print /usage`.
///
/// Every `<title>: <n>% used( · resets <text>)?` segment becomes a window; segments are separated by
/// newlines or by " | " (some Claude Code paths join the lines). Anything else — the header and the
/// "What's contributing to your limits usage?" section — is ignored:
///
///     Current session: 7% used · resets Sep 17 at 10:10am (Asia/Dubai)
///     Current week (all models): 38% used · resets Sep 23 at 5am (Asia/Dubai)
///     Current week (Fable): 63% used · resets Sep 23 at 5am (Asia/Dubai)
///     Current week (Sonnet only): 12% used · resets Sep 23 at 5am (Asia/Dubai)
///     Current month (spend): 12% used · resets Oct 1
public enum ClaudeUsageReportParser {
    public static let bucketID = "claude"
    /// Titles longer than this are not limit titles.
    static let maximumTitleLength = 80

    /// The same reading as `parseReport`, for callers that do not watch for format drift.
    public static func parse(_ text: String, now: Date) throws(ClaudeUsageParseError) -> UsageReading {
        try parseReport(text, now: now).reading
    }

    /// The reading plus what the layout looked like, so the monitor can notice the CLI's output drifting away from
    /// what this version understands (item 18).
    public static func parseReport(
        _ text: String,
        now: Date
    ) throws(ClaudeUsageParseError) -> (reading: UsageReading, stats: ClaudeParseStats) {
        var windows: [LimitWindow] = []
        var seenIDs = Set<String>()
        var genericTitles: [String] = []
        var droppedInvalid = 0
        var sawContributingHeading = false

        for segment in segments(of: text) {
            // The limits come first; what follows this heading describes local behaviour, never a limit, even if
            // a line looks like one. (Should a future layout put the heading first, keep looking.)
            if isContributingHeading(segment) {
                sawContributingHeading = true
                if !windows.isEmpty { break }
            }
            // A bucket holds a bounded number of windows; the provider lists the important ones first.
            guard windows.count < LimitBucket.maximumWindows else { break }
            guard
                let match = segment.wholeMatch(of: limitSegment),
                let used = Double(match.output.percent),
                let title = DisplayText.sanitize(String(match.output.title), maximumLength: maximumTitleLength)
            else { continue }

            let descriptor = describe(title: title)
            guard seenIDs.insert(descriptor.id).inserted else { continue }
            let resetsAt = match.output.reset.flatMap { ResetTextParser.parse(String($0), now: now) }

            do throws(ValidationError) {
                let percentage = try Percentage(validating: used, field: "claude.\(descriptor.id).used")
                windows.append(
                    try LimitWindow(
                        id: descriptor.id,
                        scope: descriptor.scope,
                        used: percentage,
                        duration: descriptor.duration,
                        resetsAt: resetsAt,
                        label: descriptor.label
                    )
                )
            } catch {
                // An implausible value in an unrecognised line must not hide the known limits.
                if descriptor.label != nil {
                    droppedInvalid += 1
                    continue
                }
                throw .invalidWindow(error)
            }
            if let label = descriptor.label {
                genericTitles.append(label)
            }
        }

        guard !windows.isEmpty else {
            let lowered = text.lowercased()
            if lowered.contains("not logged in") || lowered.contains("please run /login") {
                throw .signedOut
            }
            if lowered.contains("api key") || lowered.contains("api usage billing") {
                throw .notSubscription
            }
            throw .noLimitLines
        }

        do throws(ValidationError) {
            let bucket = try LimitBucket(
                id: bucketID,
                title: nil,
                windows: windows,
                isLimitReached: windows.contains { $0.used.isExhausted }
            )
            let reading = try UsageReading(capturedAt: now, source: .claudeUsageCommand, buckets: [bucket], credits: nil)
            let stats = ClaudeParseStats(
                genericTitles: genericTitles,
                droppedInvalid: droppedInvalid,
                sawContributingHeading: sawContributingHeading
            )
            return (reading, stats)
        } catch {
            throw .invalidWindow(error)
        }
    }

    /// "What's contributing to your limits usage?" (straight or curly apostrophe).
    static func isContributingHeading(_ segment: String) -> Bool {
        let lowered = segment.lowercased()
        return lowered.hasPrefix("what's contributing") || lowered.hasPrefix("what’s contributing")
    }

    /// Lines, each further split on " | ", trimmed, empty pieces dropped.
    static func segments(of text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).flatMap { line in
            line.split(separator: " | ", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
    }

    /// How one limit title maps onto the domain.
    struct WindowDescriptor: Equatable {
        let id: String
        let scope: LimitWindowScope
        let duration: WindowDuration?
        /// The provider's title, kept only for windows without a semantic mapping.
        let label: String?
    }

    nonisolated(unsafe) private static let limitSegment =
        /(?<title>[^:]{1,80}):\s+(?<percent>\d{1,4}(?:\.\d+)?)%\s+used(?:\s+·\s+resets\s+(?<reset>.+?))?/
    nonisolated(unsafe) private static let weeklyTitle = /Current week \((?<scope>[^()]{1,80})\)/

    static func describe(title: String) -> WindowDescriptor {
        if title.caseInsensitiveCompare("Current session") == .orderedSame {
            return WindowDescriptor(id: "session", scope: .session, duration: .fiveHours, label: nil)
        }
        if let match = title.wholeMatch(of: weeklyTitle.ignoresCase()) {
            let scopeName = String(match.output.scope).trimmingCharacters(in: .whitespaces)
            if scopeName.caseInsensitiveCompare("all models") == .orderedSame {
                return WindowDescriptor(id: "week", scope: .weekly(model: nil), duration: .oneWeek, label: nil)
            }
            let model = modelName(scopeName)
            if let model {
                return WindowDescriptor(
                    id: identifier(prefix: "week.", name: model),
                    scope: .weekly(model: model),
                    duration: .oneWeek,
                    label: nil
                )
            }
        }
        return WindowDescriptor(
            id: identifier(prefix: "limit.", name: title),
            scope: .rolling,
            duration: impliedDuration(title: title),
            label: title
        )
    }

    /// "Sonnet only" → "Sonnet"; `nil` when nothing usable is left or the name cannot be a scope model.
    static func modelName(_ scopeName: String) -> String? {
        var name = scopeName
        let suffix = " only"
        if name.count > suffix.count, name.lowercased().hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
        }
        guard let clean = DisplayText.sanitize(name, maximumLength: 60), clean == name else {
            return nil
        }
        return clean
    }

    /// `prefix` + a lowercase ASCII slug of `name`; names without ASCII letters or digits get a stable hash.
    static func identifier(prefix: String, name: String) -> String {
        let budget = StableIdentifier.maximumLength - prefix.utf8.count
        var slug = ""
        var pendingDash = false
        for scalar in name.lowercased().unicodeScalars {
            if scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) {
                if pendingDash, !slug.isEmpty { slug.append("-") }
                pendingDash = false
                slug.unicodeScalars.append(scalar)
            } else {
                pendingDash = true
            }
        }
        if slug.isEmpty {
            slug = "x" + String(fnv1a(name), radix: 16)
        }
        var trimmed = String(slug.prefix(budget))
        while trimmed.hasSuffix("-") { trimmed.removeLast() }
        return prefix + trimmed
    }

    /// A duration only when the title plainly names one; otherwise unknown.
    static func impliedDuration(title: String) -> WindowDuration? {
        let lowered = title.lowercased()
        let words = Set(lowered.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        if lowered.contains("5-hour") || lowered.contains("5 hour") || lowered.contains("five-hour")
            || lowered.contains("five hour") || words.contains("session") || words.contains("5h") {
            return .fiveHours
        }
        if words.contains("week") || words.contains("weekly") || words.contains("7d") {
            return .oneWeek
        }
        if words.contains("day") || words.contains("daily") || words.contains("24h")
            || lowered.contains("24-hour") || lowered.contains("24 hour") {
            return .oneDay
        }
        if words.contains("month") || words.contains("monthly") {
            return try? WindowDuration(minutes: 30 * 24 * 60)
        }
        return nil
    }

    private static func fnv1a(_ text: String) -> UInt32 {
        var hash: UInt32 = 0x811C_9DC5
        for byte in text.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 0x0100_0193
        }
        return hash
    }
}

/// Parses reset phrases such as `Sep 17 at 12:10am (Asia/Dubai)`, `Sep 23 at 5am`, `3pm (UTC)`, `Oct 1`.
enum ResetTextParser {
    nonisolated(unsafe) private static let zoneSuffix = /^(?<body>.+?)\s*\((?<zone>[A-Za-z]+(?:\/[A-Za-z0-9_+\-]+)*)\)$/
    nonisolated(unsafe) private static let dateTime =
        /^(?:(?<month>[A-Za-z]{3,9})\.?\s+(?<day>\d{1,2}),?\s*(?:at\s+)?)?(?:(?<hour>\d{1,2})(?::(?<minute>\d{2}))?\s*(?<meridiem>am|pm|AM|PM))?$/

    private static let monthPrefixes = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    static func parse(_ text: String, now: Date) -> Date? {
        var body = text.trimmingCharacters(in: .whitespaces)
        var timeZone = TimeZone.current
        if let match = body.wholeMatch(of: zoneSuffix) {
            // The zone must be stripped first: names like "America/…" contain "am".
            guard let zone = TimeZone(identifier: String(match.output.zone)) else { return nil }
            timeZone = zone
            body = String(match.output.body)
        }
        guard !body.isEmpty, let match = body.wholeMatch(of: dateTime) else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        var hour = 0
        var minute = 0
        if let hourText = match.output.hour, let meridiem = match.output.meridiem {
            guard let rawHour = Int(hourText), (1...12).contains(rawHour) else { return nil }
            minute = match.output.minute.flatMap { Int($0) } ?? 0
            guard (0...59).contains(minute) else { return nil }
            let isAfternoon = meridiem.lowercased() == "pm"
            hour = (rawHour % 12) + (isAfternoon ? 12 : 0)
        }

        guard let monthText = match.output.month, let dayText = match.output.day else {
            guard match.output.hour != nil else { return nil }
            // Time only: the next occurrence of that time.
            var components = calendar.dateComponents([.year, .month, .day], from: now)
            components.hour = hour
            components.minute = minute
            guard let today = calendar.date(from: components) else { return nil }
            return today >= now.addingTimeInterval(-60) ? today : calendar.date(byAdding: .day, value: 1, to: today)
        }

        guard
            let month = monthPrefixes.firstIndex(of: String(monthText.prefix(3)).lowercased()).map({ $0 + 1 }),
            let day = Int(dayText),
            (1...31).contains(day)
        else { return nil }

        // No year is printed; pick the candidate closest to now (handles December → January).
        let currentYear = calendar.component(.year, from: now)
        let candidates = [currentYear - 1, currentYear, currentYear + 1].compactMap { year -> Date? in
            let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
            guard let date = calendar.date(from: components), calendar.component(.day, from: date) == day else {
                return nil
            }
            return date
        }
        return candidates.min { abs($0.timeIntervalSince(now)) < abs($1.timeIntervalSince(now)) }
    }
}
