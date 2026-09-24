import CodometerCore
import CodometerL10n
import Foundation

/// Group edits made in the settings window, as pure functions over `AppSettings`.
///
/// Every function returns a new value and re-runs the settings invariants, so the pane can hand the
/// result to `TrackerStore.updateSettings` and show the thrown error next to the field that caused it.
enum SettingsGroupEditor {
    /// Names offered as one-click suggestions while they are unused, in the interface language. A group created from
    /// one is user data and keeps its name when the language changes.
    static func suggestedNames(l10n: Localizer) -> [String] {
        [l10n.groups.suggestedWork, l10n.groups.suggestedPersonal]
    }

    /// Appends a group named `name` (trimmed and validated like an account label).
    static func adding(named name: String, to settings: AppSettings) throws(ValidationError) -> AppSettings {
        let group = AccountGroup(name: try AccountLabel(validating: name))
        return try settings.replacingGroups(settings.groups + [group])
    }

    static func renaming(_ id: AccountGroupID, to name: String, in settings: AppSettings) throws(ValidationError) -> AppSettings {
        let label = try AccountLabel(validating: name)
        return try updatingGroup(id, in: settings) { $0.name = label }
    }

    /// Removes a group; its accounts stay tracked without a group and an island filter on it is cleared.
    static func removing(_ id: AccountGroupID, from settings: AppSettings) throws(ValidationError) -> AppSettings {
        guard settings.group(id) != nil else { throw unknownGroup(id) }
        return try settings.replacingGroups(settings.groups.filter { $0.id != id })
    }

    /// Changes a group's notification mutes; `nil` keeps the current value.
    static func settingMutes(
        _ id: AccountGroupID,
        sessions: Bool? = nil,
        usage: Bool? = nil,
        in settings: AppSettings
    ) throws(ValidationError) -> AppSettings {
        try updatingGroup(id, in: settings) { group in
            if let sessions { group.mutesSessionAlerts = sessions }
            if let usage { group.mutesUsageAlerts = usage }
        }
    }

    /// Moves an account into a group, or out of every group with `nil`.
    static func assigning(_ accountID: AccountID, to groupID: AccountGroupID?, in settings: AppSettings) throws(ValidationError) -> AppSettings {
        guard let account = settings.account(accountID) else {
            throw .inconsistent(field: "accounts.id", reason: "unknown account \(accountID)")
        }
        if let groupID, settings.group(groupID) == nil { throw unknownGroup(groupID) }
        let updated = try account.updated(groupID: .some(groupID))
        return try settings.replacingAccounts(settings.accounts.map { $0.id == accountID ? updated : $0 })
    }

    /// Limits the island to one group, or shows every group with `nil`.
    static func filteringIsland(to groupID: AccountGroupID?, in settings: AppSettings) throws(ValidationError) -> AppSettings {
        if let groupID, settings.group(groupID) == nil { throw unknownGroup(groupID) }
        var copy = settings
        copy.appearance.railGroupFilter = groupID
        return copy
    }

    static func accountCount(of groupID: AccountGroupID, in settings: AppSettings) -> Int {
        settings.accounts.count { $0.groupID == groupID }
    }

    /// Suggested names that no group uses yet (compared like the settings compare names), while groups can still be added.
    static func suggestions(for settings: AppSettings, l10n: Localizer) -> [String] {
        guard settings.groups.count < AppSettings.maximumGroups else { return [] }
        let used = Set(settings.groups.map { fold($0.name.value) })
        return suggestedNames(l10n: l10n).filter { !used.contains(fold($0)) }
    }

    private static func updatingGroup(
        _ id: AccountGroupID,
        in settings: AppSettings,
        _ change: (inout AccountGroup) -> Void
    ) throws(ValidationError) -> AppSettings {
        guard settings.group(id) != nil else { throw unknownGroup(id) }
        let groups = settings.groups.map { group -> AccountGroup in
            guard group.id == id else { return group }
            var edited = group
            change(&edited)
            return edited
        }
        return try settings.replacingGroups(groups)
    }

    private static func unknownGroup(_ id: AccountGroupID) -> ValidationError {
        .inconsistent(field: "groups.id", reason: "unknown group \(id)")
    }

    private static func fold(_ name: String) -> String {
        name.folding(options: [.caseInsensitive], locale: nil)
    }
}
