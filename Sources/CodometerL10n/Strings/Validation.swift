import Foundation

/// Settings value text that `SettingsCopy` provides to every Settings pane: why a change was rejected, and the option
/// titles and hints other panes read through it (open trigger, e-mail visibility, shortcut, widget note, short turns).
///
/// Messages are full sentences with a period in both languages. Option titles are sentence case, without a period.
public struct ValidationStrings: Sendable {
    let l: Localizer

    // MARK: - Any setting

    public var notANumber: String { l.pick(en: "Enter a number.", ru: "Введите число.") }

    /// "Use a value from 0.75 to 1.5." Whole bounds print without a fraction, others with up to two decimals.
    public func outOfRange(lower: Double, upper: Double) -> String {
        let lower = number(lower)
        let upper = number(upper)
        return l.pick(en: "Use a value from \(lower) to \(upper).", ru: "Введите значение от \(lower) до \(upper).")
    }

    public var empty: String { l.pick(en: "This field can’t be empty.", ru: "Поле не может быть пустым.") }

    /// "You can create up to 8 groups."
    public func tooManyGroups(_ maximum: Int) -> String {
        l.plural(
            maximum,
            en: ("You can create up to \(maximum) group.", "You can create up to \(maximum) groups."),
            ru: ("Можно создать не больше \(maximum) группы.", "Можно создать не больше \(maximum) групп.", "Можно создать не больше \(maximum) групп.")
        )
    }

    /// "You can track up to 16 accounts."
    public func tooManyAccounts(_ maximum: Int) -> String {
        l.plural(
            maximum,
            en: ("You can track up to \(maximum) account.", "You can track up to \(maximum) accounts."),
            ru: (
                "Можно отслеживать не больше \(maximum) аккаунта.",
                "Можно отслеживать не больше \(maximum) аккаунтов.",
                "Можно отслеживать не больше \(maximum) аккаунтов."
            )
        )
    }

    /// "You can choose up to 6 thresholds."
    public func tooManyThresholds(_ maximum: Int) -> String {
        l.plural(
            maximum,
            en: ("You can choose up to \(maximum) threshold.", "You can choose up to \(maximum) thresholds."),
            ru: ("Можно выбрать не больше \(maximum) порога.", "Можно выбрать не больше \(maximum) порогов.", "Можно выбрать не больше \(maximum) порогов.")
        )
    }

    /// Any other text that is too long: "Use up to 40 characters."
    public func tooLong(_ maximum: Int) -> String {
        l.plural(
            maximum,
            en: ("Use up to \(maximum) character.", "Use up to \(maximum) characters."),
            ru: ("Не длиннее \(maximum) символа.", "Не длиннее \(maximum) символов.", "Не длиннее \(maximum) символов.")
        )
    }

    public var invalidCharacters: String { l.pick(en: "Some characters aren’t allowed.", ru: "Есть недопустимые символы.") }
    public var notAbsolutePath: String {
        l.pick(en: "Enter the full path to the profile folder.", ru: "Укажите полный путь к папке профиля.")
    }

    /// "A group named “Work” already exists." The name is user data and is never translated.
    public func duplicateGroup(_ name: String) -> String {
        l.pick(en: "A group named “\(name)” already exists.", ru: "Группа «\(name)» уже есть.")
    }

    public var duplicateProfile: String { l.pick(en: "You’re already tracking this profile.", ru: "Этот профиль уже отслеживается.") }
    public var duplicateValue: String { l.pick(en: "This value is already in use.", ru: "Такое значение уже есть.") }
    /// The yellow band must start below the red one.
    public var bandsOrder: String { l.pick(en: "Set the yellow threshold below the red one.", ru: "Жёлтый порог должен быть ниже красного.") }
    public var groupGone: String { l.pick(en: "This group no longer exists.", ru: "Такой группы больше нет.") }
    public var accountGone: String { l.pick(en: "This account no longer exists.", ru: "Такого аккаунта больше нет.") }
    public var conflictingSettings: String { l.pick(en: "These settings conflict.", ru: "Настройки противоречат друг другу.") }

    // MARK: - Names typed by the user

    public var groupNameEmpty: String { l.pick(en: "Enter a group name.", ru: "Введите название группы.") }

    /// "Use up to 40 characters for the group name."
    public func groupNameTooLong(_ maximum: Int) -> String {
        l.plural(
            maximum,
            en: ("Use up to \(maximum) character for the group name.", "Use up to \(maximum) characters for the group name."),
            ru: (
                "Название группы — не длиннее \(maximum) символа.",
                "Название группы — не длиннее \(maximum) символов.",
                "Название группы — не длиннее \(maximum) символов."
            )
        )
    }

    public var accountNameEmpty: String { l.pick(en: "Enter a name.", ru: "Введите название.") }

    /// "Use up to 40 characters for the name."
    public func accountNameTooLong(_ maximum: Int) -> String {
        l.plural(
            maximum,
            en: ("Use up to \(maximum) character for the name.", "Use up to \(maximum) characters for the name."),
            ru: ("Название — не длиннее \(maximum) символа.", "Название — не длиннее \(maximum) символов.", "Название — не длиннее \(maximum) символов.")
        )
    }

    public var nameInvalidCharacters: String {
        l.pick(en: "Some characters in the name aren’t allowed.", ru: "В названии есть недопустимые символы.")
    }

    /// The refresh interval is shorter than the provider allows.
    public var refreshTooFrequent: String {
        l.pick(en: "That’s more often than this service allows.", ru: "Слишком частое обновление для этого сервиса.")
    }

    // MARK: - Island open trigger (Placement pane and its preview)

    public var openOnHover: String { l.pick(en: "Hover", ru: "При наведении") }
    public var openOnClick: String { l.pick(en: "Click", ru: "По клику") }
    public var openOnHoverOrClick: String { l.pick(en: "Hover or click", ru: "Наведение или клик") }

    /// Under the trigger picker; at most two lines.
    public var hoverExplanation: String {
        l.pick(
            en: "Expands when the pointer rests on the island and collapses when it moves away.",
            ru: "Раскрывается, когда курсор задерживается на острове, и сворачивается, когда уходит."
        )
    }
    public var clickExplanation: String {
        l.pick(
            en: "Expands when you click and stays open until you click elsewhere or press Esc.",
            ru: "Раскрывается по клику и остаётся открытым до клика мимо или Esc."
        )
    }
    public var hoverOrClickExplanation: String {
        l.pick(
            en: "Hover to expand, click to keep it open until you click elsewhere or press Esc.",
            ru: "Наведение раскрывает, клик закрепляет открытым до клика мимо или Esc."
        )
    }

    /// Under the live preview; one line at the Settings window's minimum width.
    public var hoverStageHint: String {
        l.pick(en: "Hover over the island to expand it. Drag to move it.", ru: "Наведите курсор на остров, чтобы раскрыть. Остров можно перетащить.")
    }
    public var clickStageHint: String {
        l.pick(en: "Click to expand the island, click elsewhere to collapse. Drag to move it.", ru: "Клик раскрывает остров, клик мимо сворачивает. Остров можно перетащить.")
    }
    public var hoverOrClickStageHint: String {
        l.pick(en: "Hover to expand the island, click to keep it open. Drag to move it.", ru: "Наведение раскрывает остров, клик закрепляет. Остров можно перетащить.")
    }

    // MARK: - E-mail visibility (Appearance pane)

    public var showEmail: String { l.pick(en: "Show", ru: "Показывать") }
    public var maskEmail: String { l.pick(en: "Partially hide", ru: "Частично скрывать") }
    public var hideEmail: String { l.pick(en: "Hide", ru: "Скрывать") }
    /// Stands in for the example address when addresses are hidden.
    public var emailHidden: String { l.pick(en: "address not shown", ru: "адрес не показывается") }

    // MARK: - Global shortcut (General pane)

    /// The shortcut picker's choice for no shortcut.
    public var shortcutOff: String { l.pick(en: "Off", ru: "Выкл.") }
    /// The Space bar as a key cap.
    public var spaceKey: String { l.pick(en: "Space", ru: "Пробел") }
    /// A warning for ⌃⌥Space, which macOS often takes for itself.
    public var inputSourceShortcutNote: String {
        l.pick(
            en: "macOS often uses this shortcut to switch input sources. If the island doesn’t open, choose a different one.",
            ru: "В macOS это сочетание часто переключает раскладку. Если остров не открывается, выберите другое."
        )
    }

    // MARK: - Widget (General pane)

    /// Under the widget toggle, the same for both states so the section never changes height.
    public var widgetNote: String {
        l.pick(
            en: "Data stays on this Mac. The widget shows important changes—a ring changing color, a limit reached, an agent waiting for you—within a minute, and everything else within 15 minutes. Email addresses follow your Appearance → Privacy setting. When this is off, the widget shows “No data.”",
            ru: "Данные остаются на этом Mac. Важные изменения (цвет кольца, исчерпанный лимит, «ждёт вас») виджет покажет в течение минуты, остальные — в течение 15\u{00A0}минут. Адрес почты — по настройке «Внешний вид → Приватность». Если выключить, виджет покажет «Нет данных»."
        )
    }

    // MARK: - Short turns (Notifications pane)

    /// The short-turn choice that skips nothing, so every finished turn notifies.
    public var shortTurnsOff: String { l.pick(en: "Off", ru: "Выкл.") }

    // MARK: - Helpers

    /// A bound for `outOfRange`: whole numbers without a fraction, others with up to two decimals, in the locale
    /// ("0.75" | «0,75»); never "-0".
    private func number(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        var rounded = (value * 100).rounded() / 100
        if rounded == 0 { rounded = 0 }
        let style = FloatingPointFormatStyle<Double>(locale: l.locale).precision(.fractionLength(0...2))
        return rounded.formatted(style)
    }
}

extension Localizer {
    public var validation: ValidationStrings { ValidationStrings(l: self) }
}
