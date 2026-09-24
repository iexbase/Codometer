/// Account groups in Settings → Accounts: the Groups section, group rows, the group picker on an account and removing a
/// group. Group names are user data and are never translated, including groups created from the suggested names.
public struct GroupsStrings: Sendable {
    let l: Localizer

    public var sectionTitle: String { l.pick(en: "Groups", ru: "Группы") }
    public var sectionFooter: String {
        l.pick(
            en: "On the island, a thin line separates groups. You can mute notifications for a whole group, and other accounts keep notifying you as usual.",
            ru: "На острове группы разделяются тонкой линией. Уведомления можно отключить для целой группы — остальные аккаунты продолжат сообщать как обычно."
        )
    }

    // MARK: Adding

    /// The new group field's label, spoken by VoiceOver.
    public var newGroup: String { l.pick(en: "New group", ru: "Новая группа") }
    public var newGroupPlaceholder: String { l.pick(en: "New group, like “Family”", ru: "Новая группа, например «Семья»") }
    /// VoiceOver label of the button next to the field, whose visible title is "Add".
    public var addGroupA11y: String { l.pick(en: "Add group", ru: "Добавить группу") }
    /// Before the one-click suggestions.
    public var suggestionsLabel: String { l.pick(en: "Suggestions:", ru: "Например:") }
    /// Suggested names; once a group is created, its name is user data.
    public var suggestedWork: String { l.pick(en: "Work", ru: "Работа") }
    public var suggestedPersonal: String { l.pick(en: "Personal", ru: "Личное") }
    /// VoiceOver label of a suggestion button: "Add group “Work”".
    public func addSuggestedA11y(_ name: String) -> String {
        l.pick(en: "Add group “\(name)”", ru: "Добавить группу «\(name)»")
    }
    /// "You’ve reached the maximum of 8 groups."
    public func maximumReached(_ maximum: Int) -> String {
        l.plural(
            maximum,
            en: ("You’ve reached the maximum of \(maximum) group.", "You’ve reached the maximum of \(maximum) groups."),
            ru: (
                "Больше \(maximum) группы создать нельзя.",
                "Больше \(maximum) групп создать нельзя.",
                "Больше \(maximum) групп создать нельзя."
            )
        )
    }

    // MARK: Island filter

    public var allGroups: String { l.pick(en: "All groups", ru: "Все группы") }
    public var islandShows: String { l.pick(en: "Show on the island", ru: "Остров показывает") }
    public var islandShowsSubtitle: String {
        l.pick(en: "“Waiting for you” always includes every group.", ru: "Очередь «Ждут вас» всегда включает все группы.")
    }

    // MARK: A group row

    public var groupName: String { l.pick(en: "Group name", ru: "Название группы") }
    public var renameHelp: String { l.pick(en: "Click to rename", ru: "Нажмите, чтобы переименовать") }
    public var removeGroupHelp: String { l.pick(en: "Remove group", ru: "Удалить группу") }
    /// VoiceOver label of a row's remove button: "Remove the “Work” group".
    public func removeGroupA11y(_ name: String) -> String {
        l.pick(en: "Remove the “\(name)” group", ru: "Удалить группу «\(name)»")
    }
    public var muteSessionAlerts: String { l.pick(en: "Mute session notifications", ru: "Без уведомлений о сессиях") }
    public var muteUsageAlerts: String { l.pick(en: "Mute limit notifications", ru: "Без уведомлений о лимитах") }
    /// VoiceOver labels of a row's checkboxes, naming the group: "Mute session notifications for “Work”".
    public func muteSessionAlertsA11y(_ name: String) -> String {
        l.pick(en: "Mute session notifications for “\(name)”", ru: "Без уведомлений о сессиях для группы «\(name)»")
    }
    public func muteUsageAlertsA11y(_ name: String) -> String {
        l.pick(en: "Mute limit notifications for “\(name)”", ru: "Без уведомлений о лимитах для группы «\(name)»")
    }

    /// A group's size: "No accounts", "1 account", "3 accounts" | «Нет аккаунтов», «1 аккаунт», «3 аккаунта».
    public func accountCount(_ count: Int) -> String {
        guard count > 0 else { return l.pick(en: "No accounts", ru: "Нет аккаунтов") }
        return l.plural(count, en: ("\(count) account", "\(count) accounts"), ru: ("\(count) аккаунт", "\(count) аккаунта", "\(count) аккаунтов"))
    }

    // MARK: An account's group

    /// The group picker's label.
    public var group: String { l.pick(en: "Group", ru: "Группа") }
    public var noGroup: String { l.pick(en: "No group", ru: "Без группы") }
    public var accountGroupHelp: String { l.pick(en: "Account group", ru: "Группа аккаунта") }

    // MARK: Removing a group

    /// "Remove the “Work” group?"
    public func removeTitle(_ name: String) -> String {
        l.pick(en: "Remove the “\(name)” group?", ru: "Удалить группу «\(name)»?")
    }
    public var removeGroup: String { l.pick(en: "Remove Group", ru: "Удалить группу") }
    public var removeEmptyMessage: String { l.pick(en: "This group has no accounts.", ru: "В группе нет аккаунтов.") }
    /// What happens to the group's accounts: "3 accounts will stay in Codometer without a group."
    public func removeMessage(accounts count: Int) -> String {
        l.plural(
            count,
            en: ("\(count) account will stay in Codometer without a group.", "\(count) accounts will stay in Codometer without a group."),
            ru: (
                "\(count) аккаунт останется в Codometer без группы.",
                "\(count) аккаунта останутся в Codometer без группы.",
                "\(count) аккаунтов останутся в Codometer без группы."
            )
        )
    }
}

extension Localizer {
    public var groups: GroupsStrings { GroupsStrings(l: self) }
}
