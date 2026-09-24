import Foundation

/// Settings → General → History & Data: how long history is kept, exporting it, and erasing everything.
///
/// The CSV export's `README.txt` is built here too, line by line, because the engine never localizes (it takes the
/// finished text in the request).
public struct DataControlsStrings: Sendable {
    let l: Localizer

    // MARK: Section

    public var sectionTitle: String { l.pick(en: "History & Data", ru: "История и данные") }
    public var sectionNote: String {
        l.pick(
            en: "History stays on this Mac. Export it whenever you like, and erase everything Codometer stored when you’re done with it.",
            ru: "История хранится на этом Mac. Её можно выгрузить в любой момент, а когда она больше не нужна — стереть всё, что сохранил Codometer."
        )
    }

    // MARK: Retention

    public var retention: String { l.pick(en: "Keep history for", ru: "Хранить историю") }
    public var retentionSubtitle: String {
        l.pick(en: "Older readings are deleted automatically", ru: "Более старые записи удаляются автоматически")
    }
    /// A picker choice and the shrink warning: "2 weeks" | «2 недели».
    public func weeks(_ count: Int) -> String {
        l.plural(
            count,
            en: (one: "\(count) week", other: "\(count) weeks"),
            ru: ("\(count) неделя", "\(count) недели", "\(count) недель")
        )
    }
    public func months(_ count: Int) -> String {
        l.plural(
            count,
            en: (one: "\(count) month", other: "\(count) months"),
            ru: ("\(count) месяц", "\(count) месяца", "\(count) месяцев")
        )
    }
    /// A hand-edited retention that is not one of the four choices.
    public func days(_ count: Int) -> String {
        l.plural(
            count,
            en: (one: "\(count) day", other: "\(count) days"),
            ru: ("\(count) день", "\(count) дня", "\(count) дней")
        )
    }
    /// Asked before a shorter retention takes effect. The period is in the title, so no case endings are needed.
    public var shrinkTitle: String { l.pick(en: "Shorten the history?", ru: "Сократить историю?") }
    public var shrinkMessage: String {
        l.pick(
            en: "Readings older than the new limit are deleted right away. This can’t be undone.",
            ru: "Записи старше нового срока удалятся сразу. Это нельзя отменить."
        )
    }
    public var shrinkConfirm: String { l.pick(en: "Shorten", ru: "Сократить") }

    // MARK: Export

    /// The row's title, next to the "Export History…" button.
    public var exportRowTitle: String { l.pick(en: "Usage history", ru: "История расхода") }
    public var export: String { l.pick(en: "Export History…", ru: "Экспортировать историю…") }
    public var exportSubtitle: String {
        l.pick(en: "Limit readings, sessions and token counts", ru: "Показания лимитов, сессии и токены")
    }
    /// The save panel's confirm button.
    public var exportPrompt: String { l.pick(en: "Export", ru: "Экспортировать") }
    /// The save panel's message above the accessory view.
    public var exportPanelMessage: String {
        l.pick(
            en: "History is written as one JSON file or as a folder of CSV files. Email addresses are never exported.",
            ru: "История сохраняется одним файлом JSON или папкой с файлами CSV. Адреса почты не выгружаются никогда."
        )
    }
    public var format: String { l.pick(en: "Format", ru: "Формат") }
    public var formatJSON: String { l.pick(en: "JSON file", ru: "Файл JSON") }
    public var formatCSV: String { l.pick(en: "CSV folder", ru: "Папка CSV") }
    public var includeAccountNames: String { l.pick(en: "Include account names", ru: "Включать названия аккаунтов") }
    public var exporting: String { l.pick(en: "Exporting…", ru: "Экспорт…") }
    /// The widest inline result line, reserved so the section never changes height.
    public var exportResultTemplate: String {
        l.pick(en: "Exported 9,999,999 rows · Show in Finder", ru: "Экспортировано 9\u{00A0}999\u{00A0}999 строк · Показать в Finder")
    }
    public func exportedRows(_ count: Int, formattedCount: String) -> String {
        l.plural(
            count,
            en: (one: "Exported \(formattedCount) row", other: "Exported \(formattedCount) rows"),
            ru: ("Экспортирована \(formattedCount) строка", "Экспортировано \(formattedCount) строки", "Экспортировано \(formattedCount) строк")
        )
    }
    public var showInFinder: String { l.pick(en: "Show in Finder", ru: "Показать в Finder") }
    public var exportFailedHistoryUnavailable: String {
        l.pick(en: "History isn’t available right now.", ru: "История сейчас недоступна.")
    }
    public var exportFailedDestinationExists: String {
        l.pick(en: "Something else already has that name.", ru: "Это имя уже занято.")
    }
    public var exportFailedWrite: String {
        l.pick(en: "Codometer couldn’t write the export.", ru: "Не удалось записать выгрузку.")
    }
    /// The name a save panel offers, e.g. "Codometer History 2026-09-17"; `day` is the ISO 8601 calendar date, which
    /// sorts and travels better in a file name than a localized one.
    public func exportFileName(day: String) -> String {
        l.pick(en: "Codometer History \(day)", ru: "История Codometer \(day)")
    }

    // MARK: CSV README

    /// `README.txt` of a CSV export, in the interface language. Built from one-line phrases, so each one stays a
    /// plain literal the phrase lint can read.
    public func csvReadme(appVersion: String, exportedAt: String, retentionDays: Int) -> String {
        [
            readmeTitle,
            "",
            readmeWrittenBy(appVersion: appVersion, exportedAt: exportedAt),
            readmeRetention(period: days(retentionDays)),
            readmeEncoding,
            "",
            readmeLimits,
            readmeSessions,
            readmeTokens,
            readmeRuns,
            "",
            readmeTimes,
            readmeNumbers,
            readmePrivacy,
        ].joined(separator: "\n")
    }

    var readmeTitle: String { l.pick(en: "Codometer history export", ru: "Выгрузка истории Codometer") }
    func readmeWrittenBy(appVersion: String, exportedAt: String) -> String {
        l.pick(
            en: "Written by Codometer \(appVersion) on \(exportedAt).",
            ru: "Создано в Codometer \(appVersion), \(exportedAt)."
        )
    }
    func readmeRetention(period: String) -> String {
        l.pick(en: "Codometer keeps \(period) of history.", ru: "Codometer хранит историю за \(period).")
    }
    var readmeEncoding: String {
        l.pick(en: "Files are UTF-8 with no byte order mark; column names are English.", ru: "Файлы в UTF-8 без метки порядка байтов, названия столбцов — английские.")
    }
    var readmeLimits: String {
        l.pick(
            en: "limits.csv — one row per limit reading: which window it belongs to, how much was used, and when it resets.",
            ru: "limits.csv — по строке на каждое показание лимита: окно, расход и время сброса."
        )
    }
    var readmeSessions: String {
        l.pick(
            en: "sessions.csv — agent sessions: the project folder, what the session was doing, and how long it ran.",
            ru: "sessions.csv — сессии агентов: папка проекта, чем сессия занималась и сколько шла."
        )
    }
    var readmeTokens: String {
        l.pick(
            en: "tokens.csv — token counts in five-minute buckets, by model.",
            ru: "tokens.csv — счётчики токенов пятиминутными отрезками, по моделям."
        )
    }
    var readmeRuns: String {
        l.pick(
            en: "collection-runs.csv — when Codometer was collecting, so gaps in the other files are explained.",
            ru: "collection-runs.csv — когда Codometer вёл сбор, чтобы пропуски в остальных файлах были понятны."
        )
    }
    var readmeTimes: String {
        l.pick(
            en: "Times are ISO 8601 with the offset of the Mac’s time zone at export.",
            ru: "Время — по ISO 8601 со сдвигом часового пояса Mac на момент выгрузки."
        )
    }
    var readmeNumbers: String {
        l.pick(en: "Numbers use a dot as the decimal separator.", ru: "В числах десятичный разделитель — точка.")
    }
    var readmePrivacy: String {
        l.pick(
            en: "No email addresses, session titles or prompts are in these files.",
            ru: "В этих файлах нет адресов почты, названий сессий и запросов."
        )
    }

    // MARK: Erase

    /// The row's title, next to the "Erase All Data…" button.
    public var eraseRowTitle: String { l.pick(en: "Everything on this Mac", ru: "Всё на этом Mac") }
    public var erase: String { l.pick(en: "Erase All Data…", ru: "Стереть все данные…") }
    public var eraseSubtitle: String {
        l.pick(en: "Remove everything Codometer stored on this Mac", ru: "Удалить всё, что Codometer сохранил на этом Mac")
    }
    public var eraseSheetTitle: String { l.pick(en: "Erase all Codometer data?", ru: "Стереть все данные Codometer?") }
    public var eraseSheetIntro: String {
        l.pick(
            en: "Everything Codometer stored on this Mac is deleted. Your Claude Code and Codex accounts stay exactly as they are.",
            ru: "Всё, что Codometer сохранил на этом Mac, будет удалено. Аккаунты Claude Code и Codex останутся как есть."
        )
    }
    public var eraseRemovedTitle: String { l.pick(en: "Deleted", ru: "Будет удалено") }
    public var eraseKeptTitle: String { l.pick(en: "Left alone", ru: "Останется нетронутым") }
    public var eraseRemovedHistory: String { l.pick(en: "Usage history and the timeline", ru: "История расхода и таймлайн") }
    public var eraseRemovedSettings: String { l.pick(en: "Settings, accounts and groups", ru: "Настройки, аккаунты и группы") }
    public var eraseRemovedWidget: String { l.pick(en: "Widget data, so widgets show no readings", ru: "Данные виджетов — виджеты останутся без показаний") }
    public var eraseRemovedNotifications: String { l.pick(en: "Delivered notifications and the login item", ru: "Показанные уведомления и объект входа") }
    public var eraseKeptProfiles: String { l.pick(en: "Claude Code and Codex profiles, sign-ins and logs", ru: "Папки профилей Claude Code и Codex, входы и журналы") }
    public var eraseKeptExports: String { l.pick(en: "History you have already exported", ru: "История, которую вы уже выгрузили") }
    public var eraseKeptApp: String { l.pick(en: "Codometer itself — delete the app to remove it", ru: "Сам Codometer — чтобы убрать его, удалите программу") }
    public var eraseExportFirst: String { l.pick(en: "Export History First…", ru: "Сначала выгрузить историю…") }
    /// The first sheet's destructive step, before the two final buttons.
    public var eraseContinue: String { l.pick(en: "Continue", ru: "Продолжить") }
    public var eraseConfirmTitle: String { l.pick(en: "This can’t be undone", ru: "Это нельзя отменить") }
    public var eraseConfirmBody: String {
        l.pick(
            en: "Codometer deletes its data and then quits, or starts over and greets you like a fresh install.",
            ru: "Codometer удалит свои данные и закроется — или начнёт заново, как при первом запуске."
        )
    }
    public var eraseAndQuit: String { l.pick(en: "Erase and Quit", ru: "Стереть и закрыть") }
    public var eraseAndStartOver: String { l.pick(en: "Erase and Start Over", ru: "Стереть и начать заново") }
    public var eraseBack: String { l.pick(en: "Back", ru: "Назад") }
    /// VoiceOver name of the step indicator inside the erase sheet.
    public func eraseStepA11y(_ step: Int, of total: Int) -> String {
        l.pick(en: "Step \(step) of \(total)", ru: "Шаг \(step) из \(total)")
    }
}

extension Localizer {
    public var dataControls: DataControlsStrings { DataControlsStrings(l: self) }
}
