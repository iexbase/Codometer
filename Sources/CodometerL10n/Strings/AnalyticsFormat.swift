import Foundation

/// Short texts of the history chart, the timeline and attribution: range chips, coverage notes, counts.
public struct AnalyticsFormatStrings: Sendable {
    let l: Localizer

    // MARK: Ranges

    public var fiveHours: String { l.pick(en: "5h", ru: "5\u{00A0}ч") }
    public var day: String { l.pick(en: "24h", ru: "24\u{00A0}ч") }
    public var week: String { l.pick(en: "7d", ru: "7\u{00A0}дн") }

    // MARK: Coverage

    /// "Data since 2:20 PM": token data starts later than the period does.
    public func dataSince(_ moment: String) -> String { l.pick(en: "Data since \(moment)", ru: "данные с \(moment)") }
    /// "Since 2:20 PM": the short form under the coverage boundary.
    public func since(_ moment: String) -> String { l.pick(en: "Since \(moment)", ru: "с \(moment)") }

    /// A day and month in numbers, for moments more than a few days back: `09/10` | «10.09».
    public func dayMonth(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(locale: l.locale, calendar: l.calendar, timeZone: l.calendar.timeZone)
                .month(.twoDigits)
                .day(.twoDigits)
        )
    }

    // MARK: Counts and subjects

    /// Agents working or waiting at a moment: "no agents", "1 agent", "3 agents" | «нет агентов», «1 агент».
    public func agents(_ count: Int) -> String {
        guard count > 0 else { return l.pick(en: "no agents", ru: "нет агентов") }
        return l.plural(count, en: ("\(count) agent", "\(count) agents"), ru: ("\(count) агент", "\(count) агента", "\(count) агентов"))
    }

    /// The timeline's tooltip inside a gap of unknown reason, after the time: "no data" | «нет данных».
    public var noData: String { l.pick(en: "no data", ru: "нет данных") }

    /// The timeline's tooltip inside a gap, after the time: "no data (Mac was asleep)" | «нет данных (Mac спал)».
    /// `reason` is one of the `analytics.gap…` phrases.
    public func noDataBecause(_ reason: String) -> String {
        l.pick(en: "no data (\(reason))", ru: "нет данных (\(reason))")
    }

    /// The share that folds the smallest projects or sessions together.
    public var other: String { l.pick(en: "Other", ru: "Другое") }
    /// Tokens whose session had no project folder.
    public var noProject: String { l.pick(en: "No project", ru: "Без проекта") }
}

extension Localizer {
    public var analyticsFormat: AnalyticsFormatStrings { AnalyticsFormatStrings(l: self) }
}
