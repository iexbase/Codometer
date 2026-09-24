/// Settings → General → Language: area `Language`, reached as `l10n.languageSettings` because `l10n.language` is the
/// localizer's own language.
public struct LanguageSettingsStrings: Sendable {
    let l: Localizer

    public var title: String { l.pick(en: "Language", ru: "Язык") }
    /// The choice that follows the macOS language order.
    public var systemLanguage: String { l.pick(en: "System Language", ru: "Язык системы") }
    /// Our text switches at once; text drawn by macOS follows the process language, set at launch.
    public var relaunchFootnote: String {
        l.pick(
            en: "Codometer switches right away. Standard macOS menus and dialogs switch the next time you open Codometer.",
            ru: "Codometer переключается сразу. Системные меню и диалоги macOS сменят язык при следующем запуске Codometer."
        )
    }

    /// Text macOS draws itself (standard menus, open and save panels) follows the process language, which is set at
    /// launch, so the button offers to start Codometer again right away.
    public var relaunch: String { l.pick(en: "Relaunch Codometer", ru: "Перезапустить Codometer") }

    /// A language's name in that language, the same in every interface language: "English", «Русский».
    public func nativeName(_ language: Language) -> String {
        switch language {
        case .en: "English"
        case .ru: "Русский"
        }
    }
}

extension Localizer {
    public var languageSettings: LanguageSettingsStrings { LanguageSettingsStrings(l: self) }
}
