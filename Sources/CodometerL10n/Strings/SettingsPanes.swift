/// The Settings sidebar and window titles (Title Case in English), plus controls every pane shares.
public struct SettingsPanesStrings: Sendable {
    let l: Localizer

    public var accounts: String { l.pick(en: "Accounts", ru: "Аккаунты") }
    public var placement: String { l.pick(en: "Placement", ru: "Расположение") }
    public var appearance: String { l.pick(en: "Appearance", ru: "Внешний вид") }
    public var alerts: String { l.pick(en: "Notifications", ru: "Уведомления") }
    public var general: String { l.pick(en: "General", ru: "Общие") }
    /// Island or floating card, and where it sits (the former Placement pane).
    public var presentation: String { l.pick(en: "Presentation", ru: "Отображение") }
    public var diagnostics: String { l.pick(en: "Diagnostics", ru: "Диагностика") }

    // MARK: Shared controls

    /// Tooltip of the button that closes a notice about a rejected change.
    public var dismiss: String { l.pick(en: "Dismiss", ru: "Скрыть") }
    /// VoiceOver name of that button.
    public var dismissMessageA11y: String { l.pick(en: "Dismiss message", ru: "Скрыть сообщение") }
}

extension Localizer {
    public var settingsPanes: SettingsPanesStrings { SettingsPanesStrings(l: self) }
}
