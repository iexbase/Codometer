/// Menu items shared by the menu bar item and the island's context menu, plus the app's main menu
/// (Title Case in English, sentence case in Russian).
public struct MenuStrings: Sendable {
    let l: Localizer

    public var refreshAll: String { l.pick(en: "Refresh All", ru: "Обновить всё") }
    public var settings: String { l.pick(en: "Settings…", ru: "Настройки…") }
    public var hideIsland: String { l.pick(en: "Hide Island", ru: "Скрыть остров") }
    public var showIsland: String { l.pick(en: "Show Island", ru: "Показать остров") }
    public var quit: String { l.pick(en: "Quit Codometer", ru: "Выйти из Codometer") }

    // MARK: Main menu

    // The menu bar's own menus, so ⌘C, ⌘V, ⌘Z, ⌘W and ⌘Q work in the Settings and onboarding windows.
    // The app menu's own title is the brand name and is never translated.

    public var about: String { l.pick(en: "About Codometer", ru: "О программе Codometer") }
    public var hideApp: String { l.pick(en: "Hide Codometer", ru: "Скрыть Codometer") }

    public var edit: String { l.pick(en: "Edit", ru: "Правка") }
    public var undo: String { l.pick(en: "Undo", ru: "Отменить") }
    public var redo: String { l.pick(en: "Redo", ru: "Повторить") }
    public var cut: String { l.pick(en: "Cut", ru: "Вырезать") }
    public var copy: String { l.pick(en: "Copy", ru: "Скопировать") }
    public var paste: String { l.pick(en: "Paste", ru: "Вставить") }
    public var selectAll: String { l.pick(en: "Select All", ru: "Выбрать все") }

    public var window: String { l.pick(en: "Window", ru: "Окно") }
    public var close: String { l.pick(en: "Close", ru: "Закрыть") }
    public var minimize: String { l.pick(en: "Minimize", ru: "Свернуть") }
}

extension Localizer {
    public var menu: MenuStrings { MenuStrings(l: self) }
}
