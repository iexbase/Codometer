import Foundation

/// Everything text needs: the language words come from, and the locale and calendar numbers and dates follow.
///
/// Words come from `language`. Number, date and clock conventions (decimal separator, 12/24-hour clock, first weekday)
/// come from the user's region, the way Apple apps behave with "English" on a Mac set to the Russia region. Tests and
/// renders pin `testEnglish` and `testRussian`.
///
/// Phrases live in one file per area under `Strings/`, each an extension exposing `l10n.<area>.<phrase>`.
public struct Localizer: Sendable, Hashable {
    public let language: Language
    /// The language plus the region's conventions: region, hour cycle and first weekday.
    public let locale: Locale
    /// Gregorian, in `locale` and the given time zone.
    public let calendar: Calendar

    /// - Parameters:
    ///   - region: Supplies the region, hour cycle and first weekday (only those: the language stays `language`).
    ///   - timeZone: The calendar's time zone; `.autoupdatingCurrent` keeps following the system.
    public init(language: Language, region: Locale = .autoupdatingCurrent, timeZone: TimeZone = .autoupdatingCurrent) {
        // `Locale.Components(locale:)` with only the language changed would drop the region, so build it up instead.
        var components = Locale.Components(identifier: language.rawValue)
        components.region = region.region
        components.hourCycle = region.hourCycle
        components.firstDayOfWeek = region.firstDayOfWeek
        self.init(language: language, components: components, timeZone: timeZone)
    }

    private init(language: Language, components: Locale.Components, timeZone: TimeZone) {
        self.language = language
        let locale = Locale(components: components)
        self.locale = locale
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    /// English in the United States: 12-hour clock, weeks start on Sunday, GMT.
    public static let testEnglish = Localizer.fixed(.en, region: "US", hourCycle: .oneToTwelve, firstDay: .sunday)
    /// Russian in Russia: 24-hour clock, weeks start on Monday, GMT.
    public static let testRussian = Localizer.fixed(.ru, region: "RU", hourCycle: .zeroToTwentyThree, firstDay: .monday)

    private static func fixed(
        _ language: Language,
        region: String,
        hourCycle: Locale.HourCycle,
        firstDay: Locale.Weekday
    ) -> Localizer {
        var components = Locale.Components(identifier: language.rawValue)
        components.region = Locale.Region(region)
        components.hourCycle = hourCycle
        components.firstDayOfWeek = firstDay
        return Localizer(language: language, components: components, timeZone: TimeZone(identifier: "GMT") ?? .gmt)
    }

    // MARK: - Phrases

    /// The phrase in the current language. Only the chosen branch is evaluated.
    @inlinable
    public func pick(en: @autoclosure () -> String, ru: @autoclosure () -> String) -> String {
        let text = switch language {
        case .en: en()
        case .ru: ru()
        }
        return PseudoLocalization.isEnabled ? PseudoLocalization.expand(text) : text
    }

    /// The plural form for `count`. Every form carries the number itself, so word order is free in each language;
    /// a count of zero with different wording gets its own phrase.
    public func plural(_ count: Int, en: (one: String, other: String), ru: (one: String, few: String, many: String)) -> String {
        let text = switch (language, language.pluralCategory(count)) {
        case (.en, .one): en.one
        case (.en, _): en.other
        case (.ru, .one): ru.one
        case (.ru, .few): ru.few
        case (.ru, _): ru.many
        }
        return PseudoLocalization.isEnabled ? PseudoLocalization.expand(text) : text
    }

    /// A phrase around one live `Text` (a system countdown, say): the text before and after it.
    ///
    /// Compose as `Text("\(slot.prefix)\(live)\(slot.suffix)")`; `Text + Text` is deprecated.
    public func slot(en: (String, String), ru: (String, String)) -> (prefix: String, suffix: String) {
        let parts = switch language {
        case .en: en
        case .ru: ru
        }
        guard PseudoLocalization.isEnabled else { return (parts.0, parts.1) }
        return (parts.0.isEmpty ? "" : PseudoLocalization.expand(parts.0), parts.1.isEmpty ? "" : PseudoLocalization.expand(parts.1))
    }

    /// Numbers, durations, times and percentages in this language and region.
    public var format: Formats { Formats(l: self) }
}

/// Pseudo-localization for finding truncation and hard-coded text in debug captures.
///
/// Debug builds started with `CODOMETER_L10N_PSEUDO=1` wrap every phrase as `⟦text···⟧`, about a third longer.
/// Release builds never read the variable.
public enum PseudoLocalization {
    /// Read once per process.
    public static let isEnabled: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.environment["CODOMETER_L10N_PSEUDO"] == "1"
        #else
        false
        #endif
    }()

    /// `⟦text···⟧`, with padding of about a third of the text's length.
    public static func expand(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        let padding = String(repeating: "·", count: max(1, text.count / 3))
        return "⟦" + text + padding + "⟧"
    }
}
