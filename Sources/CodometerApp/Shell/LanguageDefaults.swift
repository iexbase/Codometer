import CodometerL10n
import Foundation

/// Keeps the language macOS draws its own text in (menus, open panels, alert buttons) in step with the in-app choice.
///
/// Our own text switches at once; the process language is read by AppKit at launch, so this takes effect the next time
/// Codometer opens. English and Russian write `AppleLanguages` into the app's own defaults; System removes it, so the
/// app follows the macOS language order again.
@MainActor
enum LanguageDefaults {
    nonisolated static let key = "AppleLanguages"

    /// Writes or removes the app's `AppleLanguages` for `preference`, only when it differs from what is stored.
    /// Unbundled builds (`swift run`) have no defaults domain of their own and are left alone.
    static func apply(
        _ preference: LanguagePreference,
        defaults: UserDefaults = .standard,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        guard let bundleIdentifier else { return }
        let stored = defaults.persistentDomain(forName: bundleIdentifier)?[key] as? [String]
        let wanted = preference.appleLanguages
        guard stored != wanted else { return }
        if let wanted {
            defaults.set(wanted, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    /// The user's macOS language order from the global domain, which this app's own `AppleLanguages` does not hide
    /// (`Locale.preferredLanguages` would return the app's override until the next launch).
    nonisolated static func systemPreferredLanguages() -> [String] {
        let global = CFPreferencesCopyValue(
            key as CFString,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        ) as? [String]
        return global ?? Locale.preferredLanguages
    }
}
