/// What the expanded island says when it has no account to show, and the buttons that fix it.
public struct EmptyStateStrings: Sendable {
    let l: Localizer

    // MARK: A group without accounts

    /// "No accounts in “Work”", with the group's name as the user typed it.
    public func groupTitle(_ name: String) -> String {
        l.pick(en: "No accounts in “\(name)”", ru: "В группе «\(name)» нет аккаунтов")
    }
    /// The filter names a group that no longer exists.
    public var unknownGroupTitle: String { l.pick(en: "No accounts in this group", ru: "В этой группе нет аккаунтов") }
    public var groupBody: String {
        l.pick(
            en: "Add an account to this group in Settings, or show all groups.",
            ru: "Добавьте в неё аккаунт в настройках или покажите все группы."
        )
    }

    // MARK: No accounts at all

    public var noAccountsTitle: String { l.pick(en: "No accounts yet", ru: "Аккаунтов пока нет") }
    public var noAccountsBody: String {
        l.pick(en: "Add a Claude Code or Codex profile in Settings.", ru: "Добавьте профиль Claude Code или Codex в настройках.")
    }
    /// Replaces the header's update time under "Limits"; the title below already says what is missing.
    public var noAccountsCaption: String { l.pick(en: "Not set up yet", ru: "пока не настроены") }

    // MARK: Every account switched off

    public var allDisabledTitle: String { l.pick(en: "All accounts are turned off", ru: "Все аккаунты выключены") }
    public var allDisabledBody: String {
        l.pick(en: "Turn on an account in Settings to see its limits.", ru: "Включите аккаунт в настройках, чтобы видеть его лимиты.")
    }
    /// Replaces the header's update time: nothing is refreshed while every account is off.
    public var allDisabledCaption: String { l.pick(en: "Tracking paused", ru: "отслеживание приостановлено") }

    // MARK: Accounts on their way

    public var loadingTitle: String { l.pick(en: "Loading accounts…", ru: "Загрузка аккаунтов…") }
    public var loadingBody: String {
        l.pick(en: "Your limits will appear in a few seconds.", ru: "Лимиты появятся через несколько секунд.")
    }
    /// Replaces the header's update time before the first reading, without repeating the "Loading accounts…" title.
    public var loadingCaption: String { l.pick(en: "Waiting for data", ru: "ожидание данных") }

    // MARK: Buttons

    /// Clears the group filter.
    public var showAll: String { l.pick(en: "Show All", ru: "Показать все") }
    public var openSettings: String { l.pick(en: "Open Settings", ru: "Открыть настройки") }
}

extension Localizer {
    public var emptyState: EmptyStateStrings { EmptyStateStrings(l: self) }
}
