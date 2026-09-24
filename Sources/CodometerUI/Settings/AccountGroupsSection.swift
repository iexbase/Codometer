import CodometerCore
import CodometerL10n
import SwiftUI

/// Account groups such as "Work" and "Personal": add, rename, remove, per-group mutes and the island filter.
struct AccountGroupsSection: View {
    let store: TrackerStore
    @Binding var pendingRemoval: AccountGroup?

    @State private var newName = ""
    @State private var addIssue: String?
    @State private var filterIssue: String?
    @Environment(\.l10n) private var l10n

    private var settings: AppSettings { store.settings }
    private var groups: [AccountGroup] { settings.groups }
    private var canAdd: Bool { groups.count < AppSettings.maximumGroups }

    var body: some View {
        Section {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                AccountGroupRow(
                    group: group,
                    accountCount: SettingsGroupEditor.accountCount(of: group.id, in: settings),
                    tint: Self.tint(at: index),
                    onRename: { name in
                        update { (settings: inout AppSettings) throws(ValidationError) in
                            settings = try SettingsGroupEditor.renaming(group.id, to: name, in: settings)
                        }.map { SettingsCopy.groupMessage(for: $0, l10n: l10n) }
                    },
                    onMute: { sessions, usage in
                        update { (settings: inout AppSettings) throws(ValidationError) in
                            settings = try SettingsGroupEditor.settingMutes(group.id, sessions: sessions, usage: usage, in: settings)
                        }.map { SettingsCopy.settingsMessage(for: $0, l10n: l10n) }
                    },
                    onRemove: { pendingRemoval = group }
                )
            }
            addRow
            if !groups.isEmpty {
                islandFilter
            }
        } header: {
            Text(l10n.groups.sectionTitle)
        } footer: {
            SectionNote(l10n.groups.sectionFooter)
        }
    }

    private var addRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                SettingsSymbol(systemImage: "folder.badge.plus", tint: .gray)
                TextField(l10n.groups.newGroup, text: $newName, prompt: Text(l10n.groups.newGroupPlaceholder))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onSubmit { add(newName) }
                    .disabled(!canAdd)
                Button {
                    add(newName)
                } label: {
                    Label(l10n.common.add, systemImage: "plus")
                }
                .buttonStyle(.glassProminent)
                .accessibilityLabel(l10n.groups.addGroupA11y)
                .disabled(!canAdd || newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            let suggestions = SettingsGroupEditor.suggestions(for: settings, l10n: l10n)
            if !suggestions.isEmpty || !canAdd {
                HStack(spacing: 8) {
                    if canAdd {
                        Text(l10n.groups.suggestionsLabel)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        ForEach(suggestions, id: \.self) { name in
                            Button {
                                add(name)
                            } label: {
                                Label(name, systemImage: "plus")
                            }
                            .buttonStyle(.glass)
                            // A glass button takes its height from the control size, not its label: `.small` and
                            // `.large` both stay under the 24 pt minimum target size, and this is the first size
                            // that clears it.
                            .controlSize(.extraLarge)
                            .accessibilityLabel(l10n.groups.addSuggestedA11y(name))
                        }
                    } else {
                        Text(l10n.groups.maximumReached(AppSettings.maximumGroups))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 34)
            }
            if let addIssue {
                InlineIssue(message: addIssue)
                    .padding(.leading, 34)
            }
        }
        .padding(.vertical, 2)
        .onChange(of: newName) { addIssue = nil }
        .animation(Motion.content, value: addIssue)
    }

    private var islandFilter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker(selection: Binding(
                get: { settings.appearance.railGroupFilter },
                set: { groupID in
                    filterIssue = update { (settings: inout AppSettings) throws(ValidationError) in
                        settings = try SettingsGroupEditor.filteringIsland(to: groupID, in: settings)
                    }.map { SettingsCopy.settingsMessage(for: $0, l10n: l10n) }
                }
            )) {
                Text(l10n.groups.allGroups).tag(AccountGroupID?.none)
                ForEach(groups) { group in
                    Text(group.name.value).tag(AccountGroupID?.some(group.id))
                }
            } label: {
                SettingsRowLabel(
                    title: l10n.groups.islandShows,
                    subtitle: l10n.groups.islandShowsSubtitle,
                    systemImage: "line.3.horizontal.decrease.circle.fill",
                    tint: .blue
                )
            }
            .pickerStyle(.menu)
            if let filterIssue {
                InlineIssue(message: filterIssue)
            }
        }
    }

    private func add(_ name: String) {
        guard canAdd else { return }
        addIssue = update { (settings: inout AppSettings) throws(ValidationError) in
            settings = try SettingsGroupEditor.adding(named: name, to: settings)
        }.map { SettingsCopy.groupMessage(for: $0, l10n: l10n) }
        if addIssue == nil, name == newName {
            newName = ""
        }
    }

    private func update(_ change: (inout AppSettings) throws(ValidationError) -> Void) -> ValidationError? {
        withAnimation(Motion.content) {
            store.updateSettings(change)
        }
    }

    /// Calm, stable tile colours that never look like a usage band or the attention colour.
    static func tint(at index: Int) -> Color {
        let palette: [Color] = [.blue, .teal, .indigo, .cyan, .mint, .brown, .gray, Color(red: 0.36, green: 0.46, blue: 0.62)]
        return palette[index % palette.count]
    }
}

/// One group: an inline-editable name, its account count, notification mutes and a remove button.
private struct AccountGroupRow: View {
    let group: AccountGroup
    let accountCount: Int
    let tint: Color
    /// Returns the message to show when the new name is rejected.
    let onRename: (String) -> String?
    let onMute: (_ sessions: Bool?, _ usage: Bool?) -> String?
    let onRemove: () -> Void

    @State private var draft: String
    @State private var issue: String?
    @FocusState private var isEditing: Bool
    @Environment(\.l10n) private var l10n

    init(
        group: AccountGroup,
        accountCount: Int,
        tint: Color,
        onRename: @escaping (String) -> String?,
        onMute: @escaping (_ sessions: Bool?, _ usage: Bool?) -> String?,
        onRemove: @escaping () -> Void
    ) {
        self.group = group
        self.accountCount = accountCount
        self.tint = tint
        self.onRename = onRename
        self.onMute = onMute
        self.onRemove = onRemove
        _draft = State(initialValue: group.name.value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                SettingsSymbol(systemImage: "folder.fill", tint: tint)
                TextField(l10n.groups.groupName, text: $draft, prompt: Text(l10n.groups.groupName))
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.leading)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .focused($isEditing)
                    .onSubmit(commit)
                    .onExitCommand(perform: revert)
                    .help(l10n.groups.renameHelp)
                    .accessibilityLabel(l10n.groups.groupName)
                Text(SettingsCopy.accountCount(accountCount, l10n: l10n))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize()
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.glass)
                .help(l10n.groups.removeGroupHelp)
                .accessibilityLabel(l10n.groups.removeGroupA11y(group.name.value))
            }
            HStack(spacing: 18) {
                Toggle(l10n.groups.muteSessionAlerts, isOn: Binding(
                    get: { group.mutesSessionAlerts },
                    set: { issue = onMute($0, nil) }
                ))
                .accessibilityLabel(l10n.groups.muteSessionAlertsA11y(group.name.value))
                Toggle(l10n.groups.muteUsageAlerts, isOn: Binding(
                    get: { group.mutesUsageAlerts },
                    set: { issue = onMute(nil, $0) }
                ))
                .accessibilityLabel(l10n.groups.muteUsageAlertsA11y(group.name.value))
            }
            .toggleStyle(.checkbox)
            .font(.callout)
            .padding(.leading, 34)
            if let issue {
                InlineIssue(message: issue)
                    .padding(.leading, 34)
            }
        }
        .padding(.vertical, 4)
        .animation(Motion.content, value: issue)
        .onChange(of: isEditing) { _, editing in
            if !editing { commit() }
        }
        .onChange(of: group.name) { _, name in
            if !isEditing { draft = name.value }
        }
        .onChange(of: draft) { issue = nil }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != group.name.value else {
            draft = group.name.value
            return
        }
        if let message = onRename(draft) {
            issue = message
        } else {
            draft = trimmed
        }
    }

    private func revert() {
        draft = group.name.value
        issue = nil
        isEditing = false
    }
}
