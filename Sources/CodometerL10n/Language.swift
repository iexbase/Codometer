import Foundation

/// The interface language the user picked in Settings → General → Language, stored in `settings.json`.
///
/// A missing or unknown value means `.english` (`default`): English is the app's default language.
public enum LanguagePreference: String, Codable, Sendable, CaseIterable, Identifiable {
    case english = "en"
    case russian = "ru"
    /// Follows the macOS language order: the first supported language, else English.
    case system

    public var id: String { rawValue }

    public static let `default` = LanguagePreference.english

    /// The `AppleLanguages` value the app writes into its own defaults for this choice, so text drawn by macOS (menus,
    /// open panels, alert buttons) follows it from the next launch; `nil` for `.system`, which removes the value.
    public var appleLanguages: [String]? {
        switch self {
        case .english: [Language.en.rawValue]
        case .russian: [Language.ru.rawValue]
        case .system: nil
        }
    }
}

/// A language the interface text is written in.
public enum Language: String, Codable, Sendable, CaseIterable, Hashable {
    case en
    case ru

    /// The language to show for a preference. `.system` takes the first language in `preferredLanguages` that the app
    /// supports, the way `Bundle` matches localizations (so "ru-UA" picks Russian), and English when none matches.
    public static func resolve(
        _ preference: LanguagePreference,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> Language {
        switch preference {
        case .english:
            return .en
        case .russian:
            return .ru
        case .system:
            let supported = allCases.map(\.rawValue)
            let match = Bundle.preferredLocalizations(from: supported, forPreferences: preferredLanguages).first
            // With no preferred languages at all, Bundle falls back to its development region: take English explicitly.
            guard !preferredLanguages.isEmpty, let match else { return .en }
            return Language(rawValue: match) ?? .en
        }
    }

    /// The CLDR plural category of a whole count: English has one/other, Russian one/few/many.
    ///
    /// Negative counts use their magnitude. Fractions never occur: the app only counts things.
    public func pluralCategory(_ count: Int) -> PluralCategory {
        let n = count.magnitude
        switch self {
        case .en:
            return n == 1 ? .one : .other
        case .ru:
            let lastDigit = n % 10
            let lastTwoDigits = n % 100
            if lastDigit == 1 && lastTwoDigits != 11 { return .one }
            if (2...4).contains(lastDigit) && !(12...14).contains(lastTwoDigits) { return .few }
            return .many
        }
    }
}

/// CLDR plural categories for whole numbers in the supported languages.
public enum PluralCategory: Sendable, Hashable {
    case one
    case few
    case many
    case other
}
