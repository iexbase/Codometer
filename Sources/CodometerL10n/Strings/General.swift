/// Settings → General: startup, the keyboard shortcut, the desktop widget, where limits come from and privacy.
/// The Language section has its own area, `LanguageSettings`.
public struct GeneralStrings: Sendable {
    let l: Localizer

    /// Under the pane's title.
    public var paneSubtitle: String {
        l.pick(
            en: "Language, startup, the keyboard shortcut, the widget, energy, and how Codometer handles your data.",
            ru: "Язык, запуск, сочетание клавиш, виджет, энергопотребление и то, как Codometer обращается с вашими данными."
        )
    }

    // MARK: Startup

    public var startupTitle: String { l.pick(en: "Startup", ru: "Запуск") }
    public var openAtLogin: String { l.pick(en: "Open at login", ru: "Открывать при входе в систему") }
    /// macOS registered the login item but the user still has to switch it on in System Settings.
    public var loginItemNeedsApproval: String {
        l.pick(en: "Waiting for your approval in System Settings.", ru: "Ждёт разрешения в Системных настройках.")
    }
    public var allowInSystemSettings: String {
        l.pick(en: "Allow in System Settings", ru: "Разрешить в Системных настройках")
    }
    /// The system does not know this copy: usually an app that was never moved to Applications.
    public var loginItemNotFound: String {
        l.pick(
            en: "macOS doesn’t know this copy of Codometer yet. Move it to Applications and open it from there.",
            ru: "macOS пока не знает эту копию Codometer. Перенесите её в «Программы» и запустите оттуда."
        )
    }

    // MARK: Keyboard shortcut

    public var shortcutTitle: String { l.pick(en: "Keyboard shortcut", ru: "Сочетание клавиш") }
    /// The row that picks the shortcut.
    public var shortcut: String { l.pick(en: "Shortcut", ru: "Сочетание") }
    /// The picker's choice for no shortcut.
    public var shortcutOff: String { l.pick(en: "Off", ru: "Выкл.") }
    /// The space bar as a key cap, as macOS names it in shortcuts: "⌃⌥Space".
    public var spaceKey: String { l.pick(en: "Space", ru: "Пробел") }
    /// Under the key caps of the chosen shortcut, in the slot that otherwise explains a conflict, so it is a sentence.
    public var fromAnyApp: String { l.pick(en: "Works from any app.", ru: "Работает из любого приложения.") }
    /// VoiceOver for the key caps: "Control-Option-Command-U, from any app".
    public func shortcutA11y(keys: String) -> String {
        l.pick(en: "\(keys), from any app", ru: "\(keys), из любого приложения")
    }
    /// Instead of the key caps when the shortcut is off.
    public var shortcutOffHint: String {
        l.pick(
            en: "The shortcut is off. Your limits are still on screen and in the menu bar.",
            ru: "Сочетание выключено. Лимиты остаются на экране и в строке меню."
        )
    }
    /// A warning for ⌃⌥Space, which macOS often uses itself.
    public var spaceShortcutWarning: String {
        l.pick(
            en: "macOS often uses this shortcut to switch input sources. If nothing happens when you press it, choose another one.",
            ru: "В macOS это сочетание часто переключает раскладку. Если по нажатию ничего не происходит, выберите другое."
        )
    }
    public var shortcutFooter: String {
        l.pick(
            en: "Opens and closes your limits from any app. When agents are waiting for you, it opens straight to them.",
            ru: "Открывает и закрывает лимиты из любого приложения. Если вас ждут агенты, сразу откроет их."
        )
    }

    // MARK: Desktop widget

    public var widgetTitle: String { l.pick(en: "Desktop widget", ru: "Виджет на рабочем столе") }
    /// The toggle that exports data for the widget.
    public var widgetData: String { l.pick(en: "Share data with the widget", ru: "Передавать данные виджету") }
    public var widgetDataSubtitle: String {
        l.pick(en: "Limit rings and reset times on your desktop", ru: "Кольца лимитов и время сброса на рабочем столе")
    }
    /// The picker that chooses between rings and the strip in the medium and large widgets.
    public var widgetLayout: String { l.pick(en: "Widget layout", ru: "Вид виджета") }
    public var widgetLayoutSubtitle: String {
        l.pick(en: "Medium and large sizes; the small one keeps its ring", ru: "Для среднего и большого размера; маленький остаётся кольцом")
    }
    /// The picker's first choice: usage rings, the original look.
    public var widgetLayoutRings: String { l.pick(en: "Rings", ru: "Кольца") }
    /// The picker's second choice: the weekly window as a headline of what is left, a chip per other window.
    public var widgetLayoutStrip: String { l.pick(en: "Strip", ru: "Полоса") }
    /// Step 1 of adding the widget.
    public var widgetStepOpenMenu: String {
        l.pick(en: "Control-click an empty spot on your desktop.", ru: "Нажмите правой кнопкой мыши на свободное место рабочего стола.")
    }
    /// Step 2; macOS's menu item is “Edit Widgets…” | «Изменить виджеты…».
    public var widgetStepEditWidgets: String { l.pick(en: "Choose Edit Widgets.", ru: "Выберите «Изменить виджеты…».") }
    /// Step 3.
    public var widgetStepDrag: String {
        l.pick(
            en: "Find Codometer and drag the size you like onto the desktop.",
            ru: "Найдите Codometer и перетащите виджет нужного размера на рабочий стол."
        )
    }
    /// VoiceOver for the three steps together.
    public var widgetStepsA11y: String {
        l.pick(
            en: "To add the widget, Control-click the desktop, choose Edit Widgets, and find Codometer.",
            ru: "Чтобы добавить виджет, нажмите правой кнопкой на рабочий стол, выберите «Изменить виджеты…» и найдите Codometer."
        )
    }
    /// Under the widget toggle, the same for both states, so the section never changes height. `appearancePane` and
    /// `privacySection` name where the e-mail setting lives; `noData` is what the widget shows without data.
    public func widgetFooter(appearancePane: String, privacySection: String, noData: String) -> String {
        l.pick(
            en: "Your data stays on this Mac. The widget shows important changes (a ring changing color, a limit reached, an agent waiting for you) within a minute, and everything else within 15 minutes. Email addresses follow your \(appearancePane) → \(privacySection) setting. When this is off, the widget shows “\(noData).”",
            ru: "Данные остаются на этом Mac. Важные изменения (цвет кольца, исчерпанный лимит, «ждёт вас») виджет показывает в течение минуты, остальное — в течение 15\u{00A0}минут. Адрес почты виджет показывает или скрывает по настройке «\(appearancePane) → \(privacySection)». Если выключить, виджет покажет «\(noData)»."
        )
    }

    // MARK: Where limits come from

    public var sourcesTitle: String { l.pick(en: "Where limits come from", ru: "Откуда берутся лимиты") }
    /// Inline Markdown: the command stays in backticks and is never translated.
    public var claudeSource: String {
        l.pick(en: "Claude Code’s own `claude /usage` command", ru: "команда `claude /usage` самого Claude Code")
    }
    /// Inline Markdown: the command stays in backticks and is never translated.
    public var codexSource: String {
        l.pick(en: "`codex app-server` and local session logs", ru: "`codex app-server` и локальные логи сессий")
    }
    public var signatureCheck: String { l.pick(en: "Signature check", ru: "Проверка подписи") }
    public var signatureCheckDetail: String {
        l.pick(en: "Only tools signed by Anthropic or OpenAI", ru: "только программы Anthropic и OpenAI")
    }

    // MARK: Privacy

    public var privacyTitle: String { l.pick(en: "Privacy", ru: "Приватность") }
    public var tokens: String { l.pick(en: "Tokens and passwords", ru: "Токены и пароли") }
    public var tokensDetail: String { l.pick(en: "Never read or stored", ru: "не читаются и не хранятся") }
    public var network: String { l.pick(en: "Network", ru: "Сеть") }
    /// Agrees with the Network section above it: with the status check off nothing leaves the Mac, and with it on
    /// only the two public status pages are asked.
    public var networkDetail: String {
        l.pick(
            en: "Only the optional status check",
            ru: "только необязательная проверка статуса"
        )
    }
    public var conversations: String { l.pick(en: "Conversations", ru: "Переписка") }
    public var conversationsDetail: String {
        l.pick(en: "Only events and limits are read, not messages", ru: "только события и лимиты, без текста сообщений")
    }
    public var showDataFolder: String { l.pick(en: "Show Data Folder", ru: "Показать папку данных") }

    // MARK: Welcome guide

    /// Opens the first-run guide again. Onboarding reuses this phrase rather than adding its own.
    public var showWelcomeGuide: String { l.pick(en: "Show Welcome Guide…", ru: "Открыть знакомство…") }
    public var welcomeGuideFooter: String {
        l.pick(
            en: "The short guide you saw on the first launch: the profiles on this Mac, how Codometer shows up on screen, notifications and startup.",
            ru: "То же короткое знакомство, что и при первом запуске: профили на этом Mac, вид Codometer на экране, уведомления и запуск."
        )
    }

    // MARK: About

    public var aboutTitle: String { l.pick(en: "About", ru: "О программе") }
    public var versionTitle: String { l.pick(en: "Version", ru: "Версия") }
    /// "1.0.0 (1790000000)": the version with its build number.
    public func versionAndBuild(version: String, build: String) -> String {
        l.pick(en: "\(version) (\(build))", ru: "\(version) (\(build))")
    }
    /// VoiceOver for the Copy button next to the version.
    public var copyVersionA11y: String {
        l.pick(en: "Copy the version and build number", ru: "Скопировать версию и номер сборки")
    }
    public var licenseTitle: String { l.pick(en: "License", ru: "Лицензия") }

    /// The version line at the bottom of the pane: "Codometer 1.0.0".
    public func appVersion(_ version: String) -> String {
        l.pick(en: "Codometer \(version)", ru: "Codometer \(version)")
    }
}

extension Localizer {
    public var general: GeneralStrings { GeneralStrings(l: self) }
}
