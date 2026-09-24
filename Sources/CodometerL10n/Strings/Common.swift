/// Generic words shared by many surfaces.
public struct CommonStrings: Sendable {
    let l: Localizer

    /// A value that is not known yet, as a label.
    public var noData: String { l.pick(en: "No data", ru: "Нет данных") }
    public var loading: String { l.pick(en: "Loading…", ru: "Загрузка…") }
    public var cancel: String { l.pick(en: "Cancel", ru: "Отменить") }
    public var save: String { l.pick(en: "Save", ru: "Сохранить") }
    public var done: String { l.pick(en: "Done", ru: "Готово") }
    public var add: String { l.pick(en: "Add", ru: "Добавить") }
    /// Opens a sheet or asks for confirmation first.
    public var editEllipsis: String { l.pick(en: "Edit…", ru: "Изменить…") }
    /// Asks for confirmation first.
    public var removeEllipsis: String { l.pick(en: "Remove…", ru: "Удалить…") }
    public var copy: String { l.pick(en: "Copy", ru: "Скопировать") }
    public var tryAgain: String { l.pick(en: "Try Again", ru: "Повторить") }
    public var hide: String { l.pick(en: "Hide", ru: "Скрыть") }
}

extension Localizer {
    public var common: CommonStrings { CommonStrings(l: self) }
}
