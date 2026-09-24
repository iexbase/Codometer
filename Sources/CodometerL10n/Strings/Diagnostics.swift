import Foundation

/// Settings → Diagnostics: the system check, how each account's refreshes are going, the provider tools, storage and
/// crash reports.
///
/// The support report itself stays English by design; these phrases are the pane around it. Technical
/// details that come from the check (file modes, signature summaries) are data, not copy, and are shown verbatim.
public struct DiagnosticsStrings: Sendable {
    let l: Localizer

    /// Under the pane's title.
    public var paneSubtitle: String {
        l.pick(
            en: "What Codometer found on this Mac, and how its refreshes are going.",
            ru: "Что Codometer нашёл на этом Mac и как идут обновления."
        )
    }

    // MARK: System check

    public var checkTitle: String { l.pick(en: "System check", ru: "Проверка системы") }
    public var checkSystem: String { l.pick(en: "Check System", ru: "Проверить систему") }
    /// While the check runs.
    public var checking: String { l.pick(en: "Checking…", ru: "Проверка…") }
    /// "Last checked 2 min ago".
    public func lastChecked(_ ago: String) -> String {
        l.pick(en: "Last checked \(ago)", ru: "Последняя проверка: \(ago)")
    }
    public var neverChecked: String { l.pick(en: "Not checked yet", ru: "Ещё не проверялось") }
    public var checkIntro: String {
        l.pick(
            en: "Looks at the tools, profiles, files and permissions Codometer needs. Nothing leaves this Mac.",
            ru: "Проверяет программы, профили, файлы и права, которые нужны Codometer. Ничего не покидает этот Mac."
        )
    }
    public var copyReport: String { l.pick(en: "Copy Report", ru: "Скопировать отчёт") }
    /// Replaces the button's title for a moment after a copy.
    public var copied: String { l.pick(en: "Copied", ru: "Скопировано") }
    public var exportReport: String { l.pick(en: "Export Diagnostics…", ru: "Сохранить диагностику…") }
    public var includeNames: String { l.pick(en: "Include account names", ru: "Включать названия аккаунтов") }
    public var reportFooter: String {
        l.pick(
            en: "The report and the technical details under each row are written in English for support. Neither contains email addresses, project or session names, or your home folder path. Account names stay out of the copy and the saved file unless “Include account names” is on.",
            ru: "Отчёт и технические строки под каждой проверкой написаны по-английски — для поддержки. В них никогда нет адресов почты, названий проектов и сессий, а также пути к домашней папке. Названий аккаунтов не будет ни в копии, ни в сохранённом файле, пока не включено «Включать названия аккаунтов»."
        )
    }

    /// The worst result decides the word next to each row, so colour is never the only signal.
    public var statusOK: String { l.pick(en: "OK", ru: "В порядке") }
    public var statusNote: String { l.pick(en: "Note", ru: "Замечание") }
    public var statusWarning: String { l.pick(en: "Warning", ru: "Предупреждение") }
    public var statusFailure: String { l.pick(en: "Problem", ru: "Проблема") }

    public var itemClaudeTool: String { l.pick(en: "Claude Code tool", ru: "Программа Claude Code") }
    public var itemCodexTool: String { l.pick(en: "Codex tool", ru: "Программа Codex") }
    public var itemClaudeProfile: String { l.pick(en: "Claude Code profile", ru: "Профиль Claude Code") }
    public var itemCodexProfile: String { l.pick(en: "Codex profile", ru: "Профиль Codex") }
    public var itemHistory: String { l.pick(en: "History file", ru: "Файл истории") }
    public var itemSettingsFile: String { l.pick(en: "Settings file", ru: "Файл настроек") }
    public var itemDataFolder: String { l.pick(en: "Data folder", ru: "Папка данных") }
    public var itemNetwork: String { l.pick(en: "Network", ru: "Сеть") }
    public var itemNotifications: String { l.pick(en: "Notifications", ru: "Уведомления") }
    public var itemLoginItem: String { l.pick(en: "Open at login", ru: "Открывать при входе в систему") }
    public var itemShortcut: String { l.pick(en: "Keyboard shortcut", ru: "Сочетание клавиш") }
    public var itemWidget: String { l.pick(en: "Widget data", ru: "Данные виджета") }
    public var itemDisplays: String { l.pick(en: "Displays", ru: "Экраны") }
    public var itemAppLocation: String { l.pick(en: "App location", ru: "Расположение приложения") }
    public var itemCrashReports: String { l.pick(en: "Crash reports", ru: "Отчёты о сбоях") }
    public var itemServiceStatus: String { l.pick(en: "Service status", ru: "Статус сервисов") }

    /// VoiceOver for one check row: "History file: OK".
    public func itemA11y(title: String, status: String) -> String {
        l.pick(en: "\(title): \(status)", ru: "\(title): \(status)")
    }

    // MARK: Accounts

    public var accountsTitle: String { l.pick(en: "Accounts", ru: "Аккаунты") }
    /// "Last refresh 14:32 · took 2.4s".
    public func lastRefresh(at time: String, took duration: String) -> String {
        l.pick(en: "Last refresh \(time) · took \(duration)", ru: "Последнее обновление \(time) · заняло \(duration)")
    }
    public var noRefreshYet: String { l.pick(en: "No refresh yet", ru: "Обновлений ещё не было") }
    /// How many limits one refresh brought back.
    public func limitsRead(_ count: Int) -> String {
        l.plural(
            count,
            en: (one: "\(count) limit", other: "\(count) limits"),
            ru: ("\(count) лимит", "\(count) лимита", "\(count) лимитов")
        )
    }
    /// A refresh that did not run at all.
    public func skipped(_ reason: String) -> String {
        l.pick(en: "skipped (\(reason))", ru: "пропущено (\(reason))")
    }
    public var skipOffline: String { l.pick(en: "offline", ru: "нет сети") }
    public var skipSignedOut: String { l.pick(en: "waiting for sign-in", ru: "ждёт входа") }
    public var skipLogsFresh: String { l.pick(en: "logs already fresh", ru: "логи уже свежие") }
    public var skipPaused: String { l.pick(en: "paused after a format change", ru: "пауза из-за смены формата") }
    /// The dots that show the last refreshes, read out in order.
    public func recentRefreshesA11y(_ list: String) -> String {
        l.pick(en: "Recent refreshes: \(list)", ru: "Недавние обновления: \(list)")
    }
    /// Only when the energy policy slows this account down.
    public func slowedBy(_ factor: String) -> String {
        l.pick(en: "Refreshing \(factor)× less often", ru: "Обновления в \(factor) раза реже")
    }
    public func failuresInARow(_ count: Int) -> String {
        l.plural(
            count,
            en: (one: "\(count) failure in a row", other: "\(count) failures in a row"),
            ru: ("\(count) ошибка подряд", "\(count) ошибки подряд", "\(count) ошибок подряд")
        )
    }
    public var noAccounts: String { l.pick(en: "No accounts yet", ru: "Аккаунтов пока нет") }
    /// VoiceOver for one account's "Refresh Now", so several identical buttons are told apart.
    public func refreshAccountA11y(_ name: String) -> String {
        l.pick(en: "Refresh \(name) now", ru: "Обновить «\(name)» сейчас")
    }

    // MARK: Tools

    public var toolsTitle: String { l.pick(en: "Tools", ru: "Программы") }
    /// "Signed by Anthropic PBC (Q6L2SF6YDW)".
    public func signedBy(publisher: String, teamID: String) -> String {
        l.pick(en: "Signed by \(publisher) (\(teamID))", ru: "Подпись: \(publisher) (\(teamID))")
    }
    public func signedByOther(teamID: String) -> String {
        l.pick(en: "Signed by another developer (\(teamID))", ru: "Подпись другого разработчика (\(teamID))")
    }
    public var signedByOtherUnknown: String {
        l.pick(en: "Signed by another developer", ru: "Подпись другого разработчика")
    }
    public var unsigned: String { l.pick(en: "Not signed", ru: "Без подписи") }
    public var notInstalled: String { l.pick(en: "Not installed", ru: "Не установлено") }
    /// `code` is an `OSStatus`, shown as it is.
    public func signatureCheckFailed(code: String) -> String {
        l.pick(en: "Signature check failed (\(code))", ru: "Проверка подписи не удалась (\(code))")
    }
    public func version(_ value: String) -> String { l.pick(en: "Version \(value)", ru: "Версия \(value)") }
    public var versionUnknown: String { l.pick(en: "Version unknown", ru: "Версия неизвестна") }

    // MARK: Data format

    public var driftTitle: String { l.pick(en: "Data format", ru: "Формат данных") }
    /// Claude refreshes are paused until the user asks for one by hand.
    public var driftPaused: String {
        l.pick(
            en: "Claude Code’s usage output looks different from what this version of Codometer expects, so refreshes are paused to keep the command from turning into a model request. Update Codometer, or press Refresh Now to try again.",
            ru: "Вывод расхода в Claude Code отличается от того, что ждёт эта версия Codometer, поэтому обновления приостановлены — чтобы команда не превратилась в запрос к модели. Обновите Codometer или нажмите «Обновить сейчас», чтобы попробовать снова."
        )
    }
    public var driftNote: String {
        l.pick(
            en: "Some limits have names Codometer doesn’t recognize yet. They’re shown under their own titles.",
            ru: "Некоторые лимиты называются так, как Codometer пока не знает. Они показаны под своими названиями."
        )
    }

    // MARK: Storage

    /// A moment in the past, with the day it happened on: `Sep 18 at 12:20 AM` | «18 сент., 0:20».
    ///
    /// `format.moment` describes something upcoming, and every past date lands in its "within six days" branch, so an
    /// entry from last month would read as a bare weekday. The oldest history entry and a stored crash report are
    /// often weeks old, and both need their date.
    public func pastMoment(_ date: Date) -> String {
        let day = date.formatted(
            Date.FormatStyle(locale: l.locale, calendar: l.calendar, timeZone: l.calendar.timeZone)
                .month(.abbreviated)
                .day()
        )
        let time = l.format.clock(date)
        return l.pick(en: "\(day) at \(time)", ru: "\(day), \(time)")
    }

    public var storageTitle: String { l.pick(en: "Storage", ru: "Хранилище") }
    public var historySize: String { l.pick(en: "History size", ru: "Размер истории") }
    public var historyState: String { l.pick(en: "History", ru: "История") }
    public var historyOK: String { l.pick(en: "Working normally", ru: "Работает нормально") }
    public var historyUnavailable: String { l.pick(en: "Not available", ru: "Недоступна") }
    public var historyRecovered: String { l.pick(en: "Rebuilt after damage", ru: "Создана заново после повреждения") }
    public var historyReadOnly: String {
        l.pick(en: "Read-only: written by a newer Codometer", ru: "Только для чтения: файл от более новой версии Codometer")
    }
    public var historyWritesPaused: String { l.pick(en: "Writes paused", ru: "Запись приостановлена") }
    public var oldestEntry: String { l.pick(en: "Oldest entry", ru: "Самая ранняя запись") }
    public var keptFor: String { l.pick(en: "Kept for", ru: "Хранится") }
    public func days(_ count: Int) -> String {
        l.plural(
            count,
            en: (one: "\(count) day", other: "\(count) days"),
            ru: ("\(count) день", "\(count) дня", "\(count) дней")
        )
    }
    /// A file size on disk, rounded to one decimal.
    public func megabytes(_ value: String) -> String { l.pick(en: "\(value) MB", ru: "\(value)\u{00A0}МБ") }
    public func kilobytes(_ value: String) -> String { l.pick(en: "\(value) KB", ru: "\(value)\u{00A0}КБ") }

    // MARK: Crash reports

    public var crashTitle: String { l.pick(en: "Crash reports", ru: "Отчёты о сбоях") }
    public var crashKindCrash: String { l.pick(en: "Crash", ru: "Сбой") }
    public var crashKindHang: String { l.pick(en: "Hang", ru: "Зависание") }
    public var crashKindException: String { l.pick(en: "Exception", ru: "Исключение") }
    public var crashFooter: String {
        l.pick(
            en: "Kept on this Mac only, and never sent anywhere.",
            ru: "Хранятся только на этом Mac и никуда не отправляются."
        )
    }
}

extension Localizer {
    public var diagnostics: DiagnosticsStrings { DiagnosticsStrings(l: self) }
}
