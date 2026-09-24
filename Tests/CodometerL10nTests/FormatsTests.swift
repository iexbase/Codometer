import CodometerL10n
import Foundation
import Testing

/// U+00A0: Russian keeps a number and its unit together.
private let nbsp = "\u{00A0}"
/// U+202F: ICU puts it between a time and AM/PM.
private let narrow = "\u{202F}"
private let english = Localizer.testEnglish.format
private let russian = Localizer.testRussian.format
/// Wednesday, 16 September 2026, 20:20 GMT.
private let now = Date(timeIntervalSince1970: 1_789_590_000)

@Suite("Formats: durations")
struct FormatsDurationTests {
    @Test("Compact durations round minutes up")
    func compact() {
        #expect(english.durationCompact(0) == "<1m")
        #expect(english.durationCompact(-5) == "<1m")
        #expect(english.durationCompact(.nan) == "<1m")
        #expect(english.durationCompact(30) == "1m")
        #expect(english.durationCompact(42 * 60) == "42m")
        #expect(english.durationCompact(2 * 3_600 + 13 * 60 + 1) == "2h 14m")
        #expect(english.durationCompact(2 * 3_600) == "2h")
        #expect(english.durationCompact(3 * 86_400 + 4 * 3_600) == "3d 4h")
        #expect(english.durationCompact(3 * 86_400) == "3d")
        #expect(english.durationCompact(.infinity) == "<1m")
        #expect(english.durationCompact(1e300).hasSuffix("d"))

        #expect(russian.durationCompact(0) == "<1\(nbsp)мин")
        #expect(russian.durationCompact(42 * 60) == "42\(nbsp)мин")
        #expect(russian.durationCompact(2 * 3_600 + 14 * 60) == "2\(nbsp)ч 14\(nbsp)мин")
        #expect(russian.durationCompact(3 * 86_400 + 4 * 3_600) == "3\(nbsp)дн 4\(nbsp)ч")
        #expect(russian.durationCompact(3 * 86_400) == "3\(nbsp)дн")
    }

    @Test("Short durations spell out minutes in English")
    func short() {
        #expect(english.durationShort(0) == "<1 min")
        #expect(english.durationShort(125) == "3 min")
        #expect(english.durationShort(59 * 60) == "59 min")
        #expect(english.durationShort(3_900) == "1h 5m")
        #expect(russian.durationShort(125) == "3\(nbsp)мин")
        #expect(russian.durationShort(3_900) == "1\(nbsp)ч 5\(nbsp)мин")
    }

    @Test("Precise durations keep seconds")
    func precise() {
        #expect(english.durationPrecise(0.3) == "1s")
        #expect(english.durationPrecise(38) == "38s")
        #expect(english.durationPrecise(252) == "4m 12s")
        #expect(english.durationPrecise(120) == "2m")
        #expect(english.durationPrecise(3_900) == "1h 5m")
        #expect(english.durationPrecise(7_200) == "2h")
        #expect(russian.durationPrecise(38) == "38\(nbsp)с")
        #expect(russian.durationPrecise(252) == "4\(nbsp)мин 12\(nbsp)с")
        #expect(russian.durationPrecise(3_900) == "1\(nbsp)ч 5\(nbsp)мин")
    }

    @Test("Spoken durations use words and grammatical plurals")
    func spoken() {
        #expect(english.durationSpoken(0) == "less than a minute")
        #expect(english.durationSpoken(60) == "1 minute")
        #expect(english.durationSpoken(2 * 3_600 + 14 * 60) == "2 hours 14 minutes")
        #expect(english.durationSpoken(2 * 3_600) == "2 hours")
        #expect(english.durationSpoken(21 * 60) == "21 minutes")
        #expect(english.durationSpoken(3 * 86_400 + 4 * 3_600 + 5 * 60) == "3 days 4 hours")
        #expect(english.durationSpoken(86_400) == "1 day")
        #expect(russian.durationSpoken(0) == "меньше минуты")
        #expect(russian.durationSpoken(2 * 3_600 + 14 * 60) == "2 часа 14 минут")
        #expect(russian.durationSpoken(21 * 60) == "21 минута")
        #expect(russian.durationSpoken(22 * 60) == "22 минуты")
        #expect(russian.durationSpoken(3 * 86_400 + 4 * 3_600) == "3 дня 4 часа")
        #expect(russian.durationSpoken(5 * 86_400) == "5 дней")
        #expect(russian.durationSpoken(3_600 + 60) == "1 час 1 минута")
    }

    @Test("Latency has one decimal below ten seconds")
    func latency() {
        #expect(english.latency(2.8) == "2.8s")
        #expect(english.latency(0.01) == "<0.1s")
        #expect(english.latency(12.4) == "12s")
        #expect(russian.latency(2.8) == "2,8\(nbsp)с")
        #expect(russian.latency(0.01) == "<0,1\(nbsp)с")
    }

    private static let railCases: [(TimeInterval, String, String)] = [
        (-5, "0m", "0м"),
        (0, "0m", "0м"),
        (.nan, "0m", "0м"),
        (30, "1m", "1м"),
        (47 * 60, "47m", "47м"),
        (59 * 60 + 1, "1:00", "1:00"),
        (2 * 3_600 + 13 * 60 + 30, "2:14", "2:14"),
        (9 * 3_600 + 5 * 60, "9:05", "9:05"),
        (86_399, "1d", "1д"),
        (2.4 * 86_400, "2d", "2д"),
        (3 * 86_400, "3d", "3д"),
    ]

    @Test("Rail countdowns stay within the five-character template", arguments: railCases)
    func rail(seconds: TimeInterval, en: String, ru: String) {
        #expect(english.railCountdown(seconds) == en)
        #expect(russian.railCountdown(seconds) == ru)
        #expect(en.count <= 5 && ru.count <= 5)
    }
}

@Suite("Formats: numbers")
struct FormatsNumberTests {
    @Test("Drawn percentages have no space in any language")
    func compact() {
        for format in [english, russian] {
            #expect(format.percentCompact(64) == "64%")
            #expect(format.percentCompact(63.5) == "64%")
            #expect(format.percentCompact(0.3) == "<1%")
            #expect(format.percentCompact(0) == "0%")
            #expect(format.percentCompact(.nan) == "0%")
        }
    }

    @Test("Prose percentages follow the locale")
    func prose() {
        #expect(english.percent(64) == "64%")
        #expect(english.percent(0.4) == "<1%")
        #expect(english.percent(0) == "0%")
        #expect(russian.percent(64) == "64\(nbsp)%")
        #expect(russian.percent(0.4) == "<1\(nbsp)%")
        #expect(russian.percent(-3) == "0\(nbsp)%")
    }

    @Test("Approximate points")
    func approximate() {
        #expect(english.approxPercent(3.24) == "≈3.2%")
        #expect(english.approxPercent(0.05) == "≈0.1%")
        #expect(english.approxPercent(0.01) == "<0.1%")
        #expect(english.approxPercent(0) == "0%")
        #expect(english.approxPercent(9.96) == "≈10%")
        #expect(english.approxPercent(12.4) == "≈12%")
        #expect(russian.approxPercent(3.24) == "≈3,2\(nbsp)%")
        #expect(russian.approxPercent(0.01) == "<0,1\(nbsp)%")
        #expect(russian.approxPercent(12.4) == "≈12\(nbsp)%")
    }

    @Test("Decimals use the locale's separators")
    func decimals() {
        #expect(english.decimal(2.8) == "2.8")
        #expect(english.decimal(2.85) == "2.9")
        #expect(english.decimal(12_345.67) == "12,345.7")
        #expect(english.decimal(3, fractionDigits: 0) == "3")
        #expect(russian.decimal(2.8) == "2,8")
        #expect(russian.decimal(12_345.67) == "12\(nbsp)345,7")
        #expect(english.decimal(.nan) == "0.0")
    }

    @Test("Lists use the language's conjunction")
    func lists() {
        #expect(english.list(["Claude", "Codex", "Work"]) == "Claude, Codex, and Work")
        #expect(english.list(["Claude", "Codex"]) == "Claude and Codex")
        #expect(russian.list(["Claude", "Codex", "Work"]) == "Claude, Codex и Work")
        #expect(english.list([]).isEmpty)
    }
}

@Suite("Formats: dates")
struct FormatsDateTests {
    @Test("The clock follows the hour cycle")
    func clock() {
        #expect(english.clock(now) == "8:20\(narrow)PM")
        #expect(russian.clock(now) == "20:20")
        #expect(russian.clock(now.addingTimeInterval(13 * 3_600)) == "9:20")
    }

    @Test("Moments: today, tomorrow, this week, later")
    func moments() {
        #expect(english.moment(now.addingTimeInterval(3_600), now: now) == "at 9:20\(narrow)PM")
        #expect(english.moment(now.addingTimeInterval(86_400), now: now) == "tomorrow at 8:20\(narrow)PM")
        #expect(english.moment(now.addingTimeInterval(3 * 86_400), now: now) == "Sat 8:20\(narrow)PM")
        #expect(english.moment(now.addingTimeInterval(9 * 86_400), now: now) == "Sep 25 at 8:20\(narrow)PM")
        #expect(russian.moment(now.addingTimeInterval(3_600), now: now) == "в 21:20")
        #expect(russian.moment(now.addingTimeInterval(86_400), now: now) == "завтра в 20:20")
        #expect(russian.moment(now.addingTimeInterval(3 * 86_400), now: now) == "сб, 20:20")
        #expect(russian.moment(now.addingTimeInterval(9 * 86_400), now: now) == "25 сент., 20:20")
    }

    @Test("Ago: just now under a minute")
    func ago() {
        #expect(english.ago(now, now: now) == "just now")
        #expect(english.ago(now.addingTimeInterval(-59), now: now) == "just now")
        #expect(english.ago(now.addingTimeInterval(30), now: now) == "just now")
        #expect(english.ago(now.addingTimeInterval(-120), now: now) == "2 min ago")
        #expect(english.ago(now.addingTimeInterval(-3_900), now: now) == "1h 5m ago")
        #expect(russian.ago(now, now: now) == "только что")
        #expect(russian.ago(now.addingTimeInterval(-120), now: now) == "2\(nbsp)мин назад")
    }

    @Test("Weekdays: calendar symbols in English, lowercase in Russian")
    func weekdays() {
        let days = (0..<7).map { now.addingTimeInterval(Double($0) * 86_400) }
        #expect(days.map(english.weekdayShort) == ["Wed", "Thu", "Fri", "Sat", "Sun", "Mon", "Tue"])
        #expect(days.map(russian.weekdayShort) == ["ср", "чт", "пт", "сб", "вс", "пн", "вт"])
    }

    @Test("English with a Russian region: English words, Russian numbers and 24-hour clock")
    func englishInRussia() throws {
        let gmt = try #require(TimeZone(identifier: "GMT"))
        let format = Localizer(language: .en, region: Locale(identifier: "ru_RU"), timeZone: gmt).format
        #expect(format.clock(now) == "20:20")
        #expect(format.moment(now.addingTimeInterval(86_400), now: now) == "tomorrow at 20:20")
        #expect(format.decimal(2.8) == "2,8")
        #expect(format.latency(2.8) == "2,8s")
        #expect(format.durationCompact(2 * 3_600 + 14 * 60) == "2h 14m")
        #expect(format.weekdayShort(now) == "Wed")
    }

    @Test("A 24-hour English region and a 12-hour Russian one")
    func hourCycles() throws {
        let gmt = try #require(TimeZone(identifier: "GMT"))
        #expect(Localizer(language: .en, region: Locale(identifier: "en_GB"), timeZone: gmt).format.clock(now) == "20:20")
        #expect(Localizer(language: .ru, region: Locale(identifier: "en_US"), timeZone: gmt).format.clock(now) == "8:20\(narrow)PM")
    }

    @Test("Day and month in numbers for analytics")
    func dayMonth() {
        #expect(Localizer.testEnglish.analyticsFormat.dayMonth(now) == "09/16")
        #expect(Localizer.testRussian.analyticsFormat.dayMonth(now) == "16.09")
    }
}
