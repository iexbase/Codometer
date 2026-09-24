import Foundation

/// Numbers, durations, times and percentages for one `Localizer` (`l10n.format`).
///
/// Units and relative words come from the language; decimal separators, the clock and weekdays from the locale.
/// Russian keeps a no-break space (U+00A0) between a number and its unit, so «2 ч» never wraps. The compact duration
/// styles are written by hand because the system's narrowest styles read «3 д. 4 ч»; spoken durations use the system.
public struct Formats: Sendable {
    let l: Localizer

    init(l: Localizer) {
        self.l = l
    }

    /// Durations beyond this are clamped, so converting them to whole units never overflows.
    static let maximumSeconds: TimeInterval = 100 * 365 * 86_400

    // MARK: - Durations

    /// Countdowns and elapsed times: `2h 14m`, `3d 4h`, `42m`, `<1m` | «2 ч 14 мин», «3 дн 4 ч», «42 мин», «<1 мин».
    /// Minutes round up, so a countdown never reads zero while time remains.
    public func durationCompact(_ seconds: TimeInterval) -> String {
        let total = Self.wholeMinutesUp(seconds)
        guard total >= 1 else { return l.pick(en: "<1m", ru: "<1\u{00A0}мин") }
        let parts = Self.dayHourMinute(total)
        let days = parts.days, hours = parts.hours, minutes = parts.minutes
        if days > 0 {
            return hours > 0
                ? l.pick(en: "\(days)d \(hours)h", ru: "\(days)\u{00A0}дн \(hours)\u{00A0}ч")
                : l.pick(en: "\(days)d", ru: "\(days)\u{00A0}дн")
        }
        if hours > 0 {
            return minutes > 0
                ? l.pick(en: "\(hours)h \(minutes)m", ru: "\(hours)\u{00A0}ч \(minutes)\u{00A0}мин")
                : l.pick(en: "\(hours)h", ru: "\(hours)\u{00A0}ч")
        }
        return l.pick(en: "\(minutes)m", ru: "\(minutes)\u{00A0}мин")
    }

    /// Like `durationCompact`, but minutes alone read as words in English: `12 min`, `<1 min`, `1h 5m` |
    /// «12 мин», «<1 мин», «1 ч 5 мин». For phrases such as "Updated 2 min ago" and "No activity for 12 min".
    public func durationShort(_ seconds: TimeInterval) -> String {
        let total = Self.wholeMinutesUp(seconds)
        guard total < 60 else { return durationCompact(seconds) }
        guard total >= 1 else { return l.pick(en: "<1 min", ru: "<1\u{00A0}мин") }
        return l.pick(en: "\(total) min", ru: "\(total)\u{00A0}мин")
    }

    /// Turn lengths, where seconds matter: `38s`, `4m 12s`, `1h 5m` | «38 с», «4 мин 12 с», «1 ч 5 мин».
    public func durationPrecise(_ seconds: TimeInterval) -> String {
        let clamped = seconds.isFinite ? min(seconds, Self.maximumSeconds) : 0
        let total = max(1, Int(clamped.rounded()))
        if total < 60 {
            return l.pick(en: "\(total)s", ru: "\(total)\u{00A0}с")
        }
        if total < 3_600 {
            let minutes = total / 60
            let rest = total % 60
            return rest > 0
                ? l.pick(en: "\(minutes)m \(rest)s", ru: "\(minutes)\u{00A0}мин \(rest)\u{00A0}с")
                : l.pick(en: "\(minutes)m", ru: "\(minutes)\u{00A0}мин")
        }
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        return minutes > 0
            ? l.pick(en: "\(hours)h \(minutes)m", ru: "\(hours)\u{00A0}ч \(minutes)\u{00A0}мин")
            : l.pick(en: "\(hours)h", ru: "\(hours)\u{00A0}ч")
    }

    /// For VoiceOver, in words with the same precision as `durationCompact`: "2 hours 14 minutes", "3 days 4 hours" |
    /// «2 часа 14 минут». Each unit comes from the system's wide style, so plurals are right in both languages; units
    /// are joined with a space, as a sentence reads them ("available again in 2 hours 14 minutes").
    public func durationSpoken(_ seconds: TimeInterval) -> String {
        let total = Self.wholeMinutesUp(seconds)
        guard total >= 1 else { return l.pick(en: "less than a minute", ru: "меньше минуты") }
        let parts = Self.dayHourMinute(total)
        let units: [(Int, Duration.UnitsFormatStyle.Unit, Int64)] = parts.days > 0
            ? [(parts.days, .days, 86_400), (parts.hours, .hours, 3_600)]
            : [(parts.hours, .hours, 3_600), (parts.minutes, .minutes, 60)]
        return units
            .filter { $0.0 > 0 }
            .map { count, unit, seconds in
                let style = Duration.UnitsFormatStyle(allowedUnits: [unit], width: .wide).locale(l.locale)
                return Duration.seconds(Int64(count) * seconds).formatted(style)
            }
            .joined(separator: " ")
    }

    /// Time to first token: `2.8s`, `<0.1s` | «2,8 с», «<0,1 с»; ten seconds and more as `durationPrecise`.
    public func latency(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds < 9.95 else { return durationPrecise(seconds) }
        guard seconds >= 0.05 else {
            let tenth = decimal(0.1)
            return l.pick(en: "<\(tenth)s", ru: "<\(tenth)\u{00A0}с")
        }
        let value = decimal(seconds)
        return l.pick(en: "\(value)s", ru: "\(value)\u{00A0}с")
    }

    /// A countdown short enough for the island's rail: `47m` under an hour, `2:14` under a day, `3d` beyond |
    /// «47м», «2:14», «3д». Minutes round up; no time left reads `0m`.
    public func railCountdown(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return l.pick(en: "0m", ru: "0м") }
        let clamped = min(seconds, Self.maximumSeconds)
        let totalMinutes = Int((clamped / 60).rounded(.up))
        if totalMinutes < 60 {
            return l.pick(en: "\(totalMinutes)m", ru: "\(totalMinutes)м")
        }
        if totalMinutes < 1_440 {
            let minutes = totalMinutes % 60
            return "\(totalMinutes / 60):\(minutes < 10 ? "0" : "")\(minutes)"
        }
        let days = max(1, Int((clamped / 86_400).rounded()))
        return l.pick(en: "\(days)d", ru: "\(days)д")
    }

    // MARK: - Numbers

    /// Whole percent for numerals drawn next to their own `%`, the same in every language: `64%`, `<1%` for a tiny
    /// non-zero value.
    public func percentCompact(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "0%" }
        if value < 1 { return "<1%" }
        return "\(Int(min(value, Self.maximumPercent).rounded()))%"
    }

    /// Whole percent in running text, by the locale: `64%` | «64 %» (no-break space); `<1%` for a tiny value.
    public func percent(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return percentStyle(0, fractionDigits: 0) }
        if value < 1 { return "<" + percentStyle(1, fractionDigits: 0) }
        return percentStyle(min(value, Self.maximumPercent).rounded(), fractionDigits: 0)
    }

    /// Estimated percentage points: `≈3.2%`, `≈12%`, `<0.1%`, `0%` | «≈3,2 %», «≈12 %», «<0,1 %», «0 %».
    /// VoiceOver text should say "about" instead of `≈`.
    public func approxPercent(_ points: Double) -> String {
        guard points.isFinite, points > 0 else { return percentStyle(0, fractionDigits: 0) }
        if points < 0.05 { return "<" + percentStyle(0.1, fractionDigits: 1) }
        if points >= 9.95 { return "≈" + percentStyle(min(points, Self.maximumPercent).rounded(), fractionDigits: 0) }
        return "≈" + percentStyle(points, fractionDigits: 1)
    }

    /// A decimal number by the locale: `2.8` | «2,8».
    public func decimal(_ value: Double, fractionDigits: Int = 1) -> String {
        let digits = min(max(fractionDigits, 0), 6)
        let style = FloatingPointFormatStyle<Double>(locale: l.locale)
            .precision(.fractionLength(digits))
            .rounded(rule: .toNearestOrAwayFromZero)
        return (value.isFinite ? value : 0).formatted(style)
    }

    static let maximumPercent = 1_000_000.0

    private func percentStyle(_ points: Double, fractionDigits: Int) -> String {
        let style = FloatingPointFormatStyle<Double>.Percent(locale: l.locale)
            .precision(.fractionLength(fractionDigits))
            .rounded(rule: .toNearestOrAwayFromZero)
        return (points / 100).formatted(style)
    }

    // MARK: - Dates

    /// The time of day in the user's clock: `6:40 PM` or `18:40` | «18:40».
    public func clock(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: l.locale, calendar: l.calendar, timeZone: l.calendar.timeZone))
    }

    /// When something upcoming happens, for use after a verb: `at 6:40 PM`, `tomorrow at 9:00 AM`, `Fri 12:10 PM` within
    /// six days, `Sep 19 at 12:10 PM` beyond | «в 18:40», «завтра в 09:00», «пт, 12:10», «19 сент., 12:10».
    public func moment(_ date: Date, now: Date) -> String {
        let calendar = l.calendar
        let time = clock(date)
        if calendar.isDate(date, inSameDayAs: now) {
            return l.pick(en: "at \(time)", ru: "в \(time)")
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return l.pick(en: "tomorrow at \(time)", ru: "завтра в \(time)")
        }
        if date.timeIntervalSince(now) < 6 * 86_400 {
            let day = weekdayShort(date)
            return l.pick(en: "\(day) \(time)", ru: "\(day), \(time)")
        }
        let day = date.formatted(
            Date.FormatStyle(locale: l.locale, calendar: calendar, timeZone: calendar.timeZone).month(.abbreviated).day()
        )
        return l.pick(en: "\(day) at \(time)", ru: "\(day), \(time)")
    }

    /// How long ago: `just now` under a minute, then `2 min ago`, `1h 5m ago` | «только что», «2 мин назад».
    public func ago(_ date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        guard seconds.isFinite, seconds >= 60 else { return l.pick(en: "just now", ru: "только что") }
        let span = durationShort(seconds)
        return l.pick(en: "\(span) ago", ru: "\(span) назад")
    }

    /// The abbreviated weekday for use inside a phrase: `Mon` | «пн». Russian keeps lowercase, which ICU no longer
    /// produces mid-sentence.
    public func weekdayShort(_ date: Date) -> String {
        let index = l.calendar.component(.weekday, from: date) - 1
        switch l.language {
        case .en:
            let symbols = l.calendar.shortWeekdaySymbols
            return symbols.indices.contains(index) ? symbols[index] : ""
        case .ru:
            let symbols = ["вс", "пн", "вт", "ср", "чт", "пт", "сб"]
            return symbols.indices.contains(index) ? symbols[index] : ""
        }
    }

    /// A sentence list: `Claude, Codex, and Work` | «Claude, Codex и Work».
    public func list(_ items: [String]) -> String {
        items.formatted(.list(type: .and).locale(l.locale))
    }

    // MARK: - Helpers

    /// Whole minutes, rounded up; non-finite and negative values are zero.
    static func wholeMinutesUp(_ seconds: TimeInterval) -> Int {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int((min(seconds, maximumSeconds) / 60).rounded(.up))
    }

    static func dayHourMinute(_ totalMinutes: Int) -> (days: Int, hours: Int, minutes: Int) {
        (totalMinutes / 1_440, (totalMinutes % 1_440) / 60, totalMinutes % 60)
    }
}
