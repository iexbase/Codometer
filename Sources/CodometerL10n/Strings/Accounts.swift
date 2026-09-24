/// Settings → Accounts: tracked accounts, profiles found on this Mac, the account editor and the second-account guide.
/// Account labels, profile folders and Terminal commands are user data or code and are never translated.
public struct AccountsStrings: Sendable {
    let l: Localizer

    // MARK: Pane

    public var paneSubtitle: String {
        l.pick(
            en: "Every account has its own Claude Code or Codex profile folder. Groups keep work and personal accounts apart.",
            ru: "Каждый аккаунт — отдельная папка профиля Claude Code или Codex. Группы разделяют работу и личное."
        )
    }
    public var trackedSection: String { l.pick(en: "Tracked accounts", ru: "Отслеживаются") }
    public var noAccountsTitle: String { l.pick(en: "No accounts yet", ru: "Аккаунтов пока нет") }
    public var noAccountsBody: String {
        l.pick(en: "Add a profile found on this Mac, or choose a folder yourself.", ru: "Добавьте найденный профиль или укажите папку вручную.")
    }
    public var addAccount: String { l.pick(en: "Add Account", ru: "Добавить аккаунт") }
    public var foundSection: String { l.pick(en: "Found on this Mac", ru: "Найдены на этом Mac") }
    /// VoiceOver label of a found profile's Add button: "Add Claude".
    public func addFoundA11y(_ label: String) -> String { l.pick(en: "Add \(label)", ru: "Добавить \(label)") }
    public var secondAccountSection: String { l.pick(en: "Second account", ru: "Второй аккаунт") }

    // MARK: Account row

    public var refreshNow: String { l.pick(en: "Refresh Now", ru: "Обновить сейчас") }
    public var moveUp: String { l.pick(en: "Move Up", ru: "Переместить выше") }
    public var moveDown: String { l.pick(en: "Move Down", ru: "Переместить ниже") }
    /// VoiceOver label of a row's actions menu: "Actions for Work".
    public func actionsA11y(_ label: String) -> String { l.pick(en: "Actions for \(label)", ru: "Действия с аккаунтом \(label)") }
    /// VoiceOver label of a row's tracking switch: "Track Work".
    public func trackA11y(_ label: String) -> String { l.pick(en: "Track \(label)", ru: "Отслеживать \(label)") }

    // MARK: Removing an account

    /// "Remove “Work”?"
    public func removeTitle(_ label: String) -> String { l.pick(en: "Remove “\(label)”?", ru: "Удалить «\(label)»?") }
    public var remove: String { l.pick(en: "Remove", ru: "Удалить") }
    public var removeMessage: String {
        l.pick(
            en: "The profile folder stays as it is. Only this account’s history in Codometer is deleted.",
            ru: "Папка профиля останется как есть — удалится только история аккаунта в Codometer."
        )
    }

    // MARK: Refresh interval

    /// The refresh interval picker's label.
    public var refresh: String { l.pick(en: "Refresh", ru: "Обновление") }
    public var everyMinute: String { l.pick(en: "Every minute", ru: "Каждую минуту") }
    public var everyHour: String { l.pick(en: "Every hour", ru: "Каждый час") }
    /// "Every 5 minutes"; one minute is `everyMinute`.
    public func every(minutes: Int) -> String {
        l.plural(
            minutes,
            en: ("Every \(minutes) minute", "Every \(minutes) minutes"),
            ru: ("Каждую \(minutes) минуту", "Каждые \(minutes) минуты", "Каждые \(minutes) минут")
        )
    }
    /// An interval of whole minutes and seconds, with `duration` from `format.durationPrecise`: "Every 1m 30s".
    public func every(duration: String) -> String { l.pick(en: "Every \(duration)", ru: "Каждые \(duration)") }

    /// How often an account refreshes, in the row caption after its profile folder: "every minute". Kept short
    /// because the caption is one line next to the account's controls.
    public var everyMinuteShort: String { l.pick(en: "every minute", ru: "каждую минуту") }
    public var everyHourShort: String { l.pick(en: "every hour", ru: "каждый час") }
    /// "every 5 min"; the Russian form agrees with the count («каждую 21 мин», «каждые 5 мин»).
    public func everyShort(minutes: Int) -> String {
        l.plural(
            minutes,
            en: ("every \(minutes) min", "every \(minutes) min"),
            ru: ("каждую \(minutes)\u{00A0}мин", "каждые \(minutes)\u{00A0}мин", "каждые \(minutes)\u{00A0}мин")
        )
    }
    /// With `duration` from `format.durationPrecise`: "every 1m 30s".
    public func everyShort(duration: String) -> String { l.pick(en: "every \(duration)", ru: "каждые \(duration)") }
    /// The row caption for VoiceOver, with the interval in words from the picker: "~/.claude-work, refresh: Every 5 minutes".
    public func profileCaptionA11y(path: String, interval: String) -> String {
        l.pick(en: "\(path), refresh: \(interval)", ru: "\(path), обновление: \(interval)")
    }

    // MARK: Editor

    public var newAccountTitle: String { l.pick(en: "New Account", ru: "Новый аккаунт") }
    public var editAccountTitle: String { l.pick(en: "Edit Account", ru: "Изменить аккаунт") }
    public var editorSubtitle: String {
        l.pick(en: "The profile folder determines which account Codometer tracks.", ru: "Папка профиля определяет, какой аккаунт отслеживает Codometer.")
    }
    public var service: String { l.pick(en: "Service", ru: "Сервис") }
    public var name: String { l.pick(en: "Name", ru: "Название") }
    public var profileFolder: String { l.pick(en: "Profile folder", ru: "Папка профиля") }
    /// Opens a folder chooser.
    public var chooseFolder: String { l.pick(en: "Choose…", ru: "Выбрать…") }
    /// The folder chooser's confirm button.
    public var choose: String { l.pick(en: "Choose", ru: "Выбрать") }
    public var trackAccount: String { l.pick(en: "Track this account", ru: "Отслеживать аккаунт") }

    // MARK: Second account guide

    public var secondAccountIntro: String {
        l.pick(
            en: "To track a second account, sign in with a separate profile folder. Run this in Terminal:",
            ru: "Чтобы отслеживать второй аккаунт, войдите в него с отдельной папкой профиля. Выполните в Терминале:"
        )
    }
    /// VoiceOver label of a command's copy button: "Copy the Codex command".
    public func copyCommandA11y(_ provider: String) -> String {
        l.pick(en: "Copy the \(provider) command", ru: "Скопировать команду для \(provider)")
    }
    /// VoiceOver value of a copy button after it copied.
    public var copied: String { l.pick(en: "Copied", ru: "Скопировано") }
    public var secondAccountFootnote: String {
        l.pick(
            en: "The profile will appear under “Found on this Mac.” Codometer doesn’t switch accounts for you.",
            ru: "Профиль появится в разделе «Найдены на этом Mac». Codometer не переключает аккаунты автоматически."
        )
    }
}

extension Localizer {
    public var accounts: AccountsStrings { AccountsStrings(l: self) }
}
