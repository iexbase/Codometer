/// Notices about Codometer's own data: settings that had to be recovered, repaired or are read-only, history that is
/// not in its normal state, and a former data folder that stayed behind.
///
/// Every notice is one short title plus one sentence. Technical reasons (SQLite messages, `errno` text) never reach
/// the user: they go to the log. File names are shown, absolute paths are not.
public struct RecoveryStrings: Sendable {
    let l: Localizer

    // MARK: Settings

    public var settingsRecoveredTitle: String {
        l.pick(en: "Codometer started with fresh settings", ru: "Codometer начал с чистых настроек")
    }
    /// `backupFileName` is the name of the file the unreadable settings were moved to, inside the data folder.
    public func settingsRecoveredBody(backupFileName: String) -> String {
        l.pick(
            en: "The settings file couldn’t be read. A copy of it is kept as “\(backupFileName)”.",
            ru: "Не удалось прочитать файл настроек. Его копия сохранена как «\(backupFileName)»."
        )
    }

    public var settingsRepairedTitle: String {
        l.pick(en: "Some settings were reset", ru: "Часть настроек сброшена")
    }
    /// How many values could not be read and fell back to their defaults.
    public func settingsRepairedBody(count: Int) -> String {
        l.plural(
            count,
            en: (
                one: "\(count) value couldn’t be read and went back to its default. The original file is kept as a backup.",
                other: "\(count) values couldn’t be read and went back to their defaults. The original file is kept as a backup."
            ),
            ru: (
                "\(count) значение не удалось прочитать, оно вернулось к стандартному. Исходный файл сохранён как резервная копия.",
                "\(count) значения не удалось прочитать, они вернулись к стандартным. Исходный файл сохранён как резервная копия.",
                "\(count) значений не удалось прочитать, они вернулись к стандартным. Исходный файл сохранён как резервная копия."
            )
        )
    }

    public var settingsReadOnlyTitle: String {
        l.pick(en: "These settings come from a newer Codometer", ru: "Настройки созданы более новым Codometer")
    }
    public var settingsReadOnlyBody: String {
        l.pick(
            en: "Changes you make now apply until you quit, and the file stays as it is.",
            ru: "Изменения действуют до выхода из программы, сам файл остаётся без изменений."
        )
    }

    // MARK: History

    public var historyUnavailableTitle: String {
        l.pick(en: "History is unavailable", ru: "История недоступна")
    }
    public var historyUnavailableBody: String {
        l.pick(
            en: "Limits and agents are still tracked; the timeline and charts stay empty until the next launch.",
            ru: "Лимиты и агенты отслеживаются, но лента и графики останутся пустыми до следующего запуска."
        )
    }

    public var historyRecoveredTitle: String {
        l.pick(en: "History started over", ru: "История начата заново")
    }
    /// `backupFileName` is the damaged database, moved aside inside the data folder.
    public func historyRecoveredBody(backupFileName: String) -> String {
        l.pick(
            en: "The history file was damaged. It is kept as “\(backupFileName)” and a fresh one is in use.",
            ru: "Файл истории был повреждён. Он сохранён как «\(backupFileName)», сейчас используется новый."
        )
    }

    public var historyReadOnlyTitle: String {
        l.pick(en: "History comes from a newer Codometer", ru: "История создана более новым Codometer")
    }
    public var historyReadOnlyBody: String {
        l.pick(
            en: "It is read without being changed, so nothing new is recorded right now.",
            ru: "Она только читается и не изменяется, поэтому новые данные пока не записываются."
        )
    }

    public var historyPausedTitle: String {
        l.pick(en: "History isn’t being written", ru: "История не записывается")
    }
    public var historyPausedBody: String {
        l.pick(
            en: "Writing stopped, most likely because the disk is full. Codometer tries again later.",
            ru: "Запись остановлена — скорее всего, на диске нет места. Codometer попробует позже."
        )
    }

    // MARK: The former data folder

    // MARK: Controls

    /// Opens Finder on the file or folder the notice mentions.
    public var showInFinder: String { l.pick(en: "Show in Finder", ru: "Показать в Finder") }
    /// VoiceOver name of the notice as a whole; `title` is the notice's own title.
    public func noticeA11y(title: String) -> String {
        l.pick(en: "Notice: \(title)", ru: "Сообщение: \(title)")
    }
}

extension Localizer {
    public var recovery: RecoveryStrings { RecoveryStrings(l: self) }
}
