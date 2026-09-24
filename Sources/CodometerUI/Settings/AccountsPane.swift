import CodometerCore
import CodometerL10n
import AppKit
import SwiftUI

/// Tracked accounts, their groups, profiles found on this Mac, and how to add a second account.
struct AccountsPane: View {
    let store: TrackerStore

    @State private var editor: AccountDraft?
    @State private var discovered: [DiscoveredAccount] = []
    @State private var pendingRemoval: AccountProfile?
    @State private var pendingGroupRemoval: AccountGroup?
    @State private var issue: String?
    @Environment(\.l10n) private var l10n

    var body: some View {
        Form {
            Section {
                PaneHeader(
                    title: l10n.settingsPanes.accounts,
                    subtitle: l10n.accounts.paneSubtitle,
                    systemImage: "person.2.fill",
                    tint: .blue
                )
                if let issue {
                    SettingsIssueBanner(message: issue) { self.issue = nil }
                }
            }

            Section(l10n.accounts.trackedSection) {
                if store.settings.accounts.isEmpty {
                    ContentUnavailableView(
                        l10n.accounts.noAccountsTitle,
                        systemImage: "person.crop.circle.badge.questionmark",
                        description: Text(l10n.accounts.noAccountsBody)
                    )
                }
                ForEach(store.settings.accounts) { account in
                    AccountCard(
                        account: account,
                        presentation: presentation(for: account),
                        groups: store.settings.groups,
                        isFirst: account.id == store.settings.accounts.first?.id,
                        isLast: account.id == store.settings.accounts.last?.id,
                        store: store,
                        onIssue: { error in issue = error.map { SettingsCopy.settingsMessage(for: $0, l10n: l10n) } },
                        onEdit: { editor = AccountDraft(editing: account) },
                        onRemove: { pendingRemoval = account }
                    )
                }
                HStack {
                    Spacer()
                    Button {
                        editor = AccountDraft(provider: .claude)
                    } label: {
                        Label(l10n.accounts.addAccount, systemImage: "plus")
                    }
                    .buttonStyle(.glassProminent)
                }
            }

            AccountGroupsSection(store: store, pendingRemoval: $pendingGroupRemoval)

            if !untracked.isEmpty {
                Section(l10n.accounts.foundSection) {
                    ForEach(untracked) { profile in
                        HStack(spacing: 12) {
                            ProviderBadge(provider: profile.provider, size: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.suggestedLabel).font(.body.weight(.medium))
                                Text(profile.directory.path.abbreviatingHome)
                                    .font(.subheadline.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Button(l10n.common.add) { add(profile) }
                                .buttonStyle(.glass)
                                .accessibilityLabel(l10n.accounts.addFoundA11y(profile.suggestedLabel))
                        }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            }

            Section(l10n.accounts.secondAccountSection) {
                SecondAccountGuide()
            }
        }
        .formStyle(.grouped)
        .animation(Motion.content, value: store.settings.accounts)
        .animation(Motion.content, value: store.settings.groups)
        .animation(Motion.content, value: issue)
        .onAppear { discovered = store.actions.discoverProfiles() }
        .sheet(item: $editor) { draft in
            AccountEditorSheet(draft: draft, store: store) { editor = nil }
        }
        .confirmationDialog(
            l10n.accounts.removeTitle(pendingRemoval?.label.value ?? ""),
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible
        ) {
            Button(l10n.accounts.remove, role: .destructive) {
                if let account = pendingRemoval { store.removeAccount(account.id) }
                pendingRemoval = nil
            }
        } message: {
            Text(l10n.accounts.removeMessage)
        }
        .confirmationDialog(
            l10n.groups.removeTitle(pendingGroupRemoval?.name.value ?? ""),
            isPresented: Binding(get: { pendingGroupRemoval != nil }, set: { if !$0 { pendingGroupRemoval = nil } }),
            titleVisibility: .visible
        ) {
            Button(l10n.groups.removeGroup, role: .destructive) {
                if let group = pendingGroupRemoval {
                    issue = store.updateSettings { (settings: inout AppSettings) throws(ValidationError) in
                        settings = try SettingsGroupEditor.removing(group.id, from: settings)
                    }.map { SettingsCopy.settingsMessage(for: $0, l10n: l10n) }
                }
                pendingGroupRemoval = nil
            }
        } message: {
            Text(groupRemovalMessage)
        }
    }

    private var groupRemovalMessage: String {
        guard let group = pendingGroupRemoval else { return "" }
        let count = SettingsGroupEditor.accountCount(of: group.id, in: store.settings)
        guard count > 0 else { return l10n.groups.removeEmptyMessage }
        return l10n.groups.removeMessage(accounts: count)
    }

    private var untracked: [DiscoveredAccount] {
        let tracked = Set(store.settings.accounts.map { "\($0.provider.rawValue):\($0.directory.path)" })
        return discovered.filter { !tracked.contains($0.id) }
    }

    /// The second half of an account row's caption, drawn on its own so a long folder never truncates it:
    /// " · every 5 min". `SettingsHelpersTests` keeps it identical to `SettingsCopy.profileCaption`'s tail.
    static func intervalCaption(seconds: Int, l10n: Localizer) -> String {
        let interval = switch seconds {
        case 60: l10n.accounts.everyMinuteShort
        case 3_600: l10n.accounts.everyHourShort
        case let value where value > 0 && value % 60 == 0: l10n.accounts.everyShort(minutes: value / 60)
        default: l10n.accounts.everyShort(duration: l10n.format.durationPrecise(TimeInterval(seconds)))
        }
        return " · \(interval)"
    }

    private func presentation(for account: AccountProfile) -> AccountPresentation {
        let status = store.state.account(account.id) ?? AccountStatus(profile: account)
        return AccountPresentation(status: status, settings: store.settings, now: store.now, l10n: store.localizer)
    }

    private func add(_ profile: DiscoveredAccount) {
        let account: AccountProfile
        do throws(ValidationError) {
            let label = try AccountLabel(validating: profile.suggestedLabel)
            account = try AccountProfile(provider: profile.provider, label: label, directory: profile.directory)
        } catch {
            issue = SettingsCopy.accountMessage(for: error, l10n: l10n)
            return
        }
        withAnimation(Motion.content) {
            issue = store.addAccount(account).map { SettingsCopy.settingsMessage(for: $0, l10n: l10n) }
        }
    }
}

private struct AccountCard: View {
    let account: AccountProfile
    let presentation: AccountPresentation
    let groups: [AccountGroup]
    let isFirst: Bool
    let isLast: Bool
    let store: TrackerStore
    let onIssue: (ValidationError?) -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void
    @Environment(\.l10n) private var l10n

    var body: some View {
        HStack(spacing: 14) {
            RingGauge(presentation: presentation, diameter: 46, showsSecondary: false)
                .saturation(account.isEnabled ? 1 : 0)
                .overlay(alignment: .bottomTrailing) {
                    // The account's own mark, so two accounts of one provider are told apart at a glance.
                    AccountBadge(style: presentation.style, provider: nil, size: 20)
                        .saturation(account.isEnabled ? 1 : 0)
                        .offset(x: 2, y: 2)
                }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(account.label.value)
                        .font(.headline)
                        .lineLimit(1)
                    if let plan = presentation.status.identity?.plan {
                        Text(plan)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent(for: account.provider))
                            .lineLimit(1)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Theme.accent(for: account.provider).opacity(0.15)))
                            .fixedSize()
                    }
                }
                if let identity = presentation.displayEmail ?? presentation.displayOrganization {
                    Text(identity)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                // The folder truncates in the middle; the interval keeps its own room, so the separator and the
                // interval are never eaten by a long path.
                HStack(spacing: 0) {
                    Text(account.directory.path.abbreviatingHome)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(AccountsPane.intervalCaption(seconds: account.pollInterval.seconds, l10n: l10n))
                        .lineLimit(1)
                        .fixedSize()
                    Spacer(minLength: 0)
                }
                .font(.subheadline.monospaced())
                .foregroundStyle(.tertiary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(SettingsCopy.profileCaptionA11y(path: account.directory.path.abbreviatingHome, refreshSeconds: account.pollInterval.seconds, l10n: l10n))
                if let issue = presentation.status.issue, account.isEnabled {
                    Label(UsageFormat.issue(issue, provider: account.provider, l10n: l10n), systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if !groups.isEmpty {
                groupMenu
            }
            AccountActionsMenu(
                label: account.label.value,
                canRefresh: account.isEnabled,
                isFirst: isFirst,
                isLast: isLast,
                onEdit: onEdit,
                onRefresh: { store.refresh(account.id) },
                onMove: { store.moveAccount(account.id, by: $0) },
                onRemove: onRemove
            )
            Toggle(l10n.accounts.trackA11y(account.label.value), isOn: Binding(
                get: { account.isEnabled },
                set: { isOn in
                    do throws(ValidationError) {
                        onIssue(store.replaceAccount(try account.updated(isEnabled: isOn)))
                    } catch {
                        onIssue(error)
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(.vertical, 4)
    }

    private var groupMenu: some View {
        let current = account.groupID.flatMap { id in groups.first { $0.id == id } }
        return Menu {
            Picker(l10n.groups.group, selection: Binding(
                get: { account.groupID },
                set: { groupID in
                    onIssue(store.updateSettings { (settings: inout AppSettings) throws(ValidationError) in
                        settings = try SettingsGroupEditor.assigning(account.id, to: groupID, in: settings)
                    })
                }
            )) {
                Text(l10n.groups.noGroup).tag(AccountGroupID?.none)
                ForEach(groups) { group in
                    Text(group.name.value).tag(AccountGroupID?.some(group.id))
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: current == nil ? "folder" : "folder.fill")
                    .foregroundStyle(.secondary)
                Text(current?.name.value ?? l10n.groups.noGroup)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.glass)
        // The same size as the actions menu beside it, and over the 24 pt minimum.
        .controlSize(.extraLarge)
        .fixedSize()
        .help(l10n.groups.accountGroupHelp)
        .accessibilityLabel(l10n.groups.group)
        .accessibilityValue(current?.name.value ?? l10n.groups.noGroup)
    }
}

/// A row's "…" menu. Its own view so `AccountLookTests` can measure that the button really is a 24 pt target.
struct AccountActionsMenu: View {
    let label: String
    let canRefresh: Bool
    let isFirst: Bool
    let isLast: Bool
    let onEdit: () -> Void
    let onRefresh: () -> Void
    let onMove: (Int) -> Void
    let onRemove: () -> Void
    @Environment(\.l10n) private var l10n

    /// The smallest a pointer target may be.
    static let hitTarget: CGFloat = 24

    var body: some View {
        Menu {
            Button(l10n.common.editEllipsis, systemImage: "pencil") { onEdit() }
            Button(l10n.accounts.refreshNow, systemImage: "arrow.clockwise") { onRefresh() }
                .disabled(!canRefresh)
            Divider()
            Button(l10n.accounts.moveUp, systemImage: "arrow.up") { onMove(-1) }.disabled(isFirst)
            Button(l10n.accounts.moveDown, systemImage: "arrow.down") { onMove(1) }.disabled(isLast)
            Divider()
            Button(l10n.common.removeEllipsis, systemImage: "trash", role: .destructive) { onRemove() }
        } label: {
            Image(systemName: "ellipsis")
                // A pointer target, not just a glyph: at least 24 pt on both axes.
                .frame(width: Self.hitTarget, height: Self.hitTarget)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.glass)
        // A glass button takes its size from the control size, not from its label: at `.large` it is 42 × 21 pt,
        // under the 24 pt minimum, and `.extraLarge` is the first size that clears it.
        .controlSize(.extraLarge)
        .fixedSize()
        .accessibilityLabel(l10n.accounts.actionsA11y(label))
    }
}

struct ProviderBadge: View {
    let provider: ProviderKind
    let size: CGFloat

    var body: some View {
        ProviderGlyph(provider: provider)
            .frame(width: size * 0.5, height: size * 0.5)
            .frame(width: size, height: size)
            .background(Circle().fill(Theme.accent(for: provider).opacity(0.16)))
    }
}

private struct SecondAccountGuide: View {
    /// The example suffix the guide shows. It goes through the one rule profile discovery and the onboarding wizard
    /// use (`SecondAccountCommands`), so the guide can never drift from what Codometer actually looks for.
    static let exampleSuffix = "work"

    private var steps: [(ProviderKind, String)] {
        guard let suffix = try? ProfileSuffix(Self.exampleSuffix) else { return [] }
        return ProviderKind.allCases.flatMap { provider in
            SecondAccountCommands.signIn(provider: provider, suffix: suffix).map { (provider, $0) }
        }
    }

    @State private var copied: String?
    @Environment(\.l10n) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l10n.accounts.secondAccountIntro)
                .font(.callout)
            ForEach(steps, id: \.1) { provider, command in
                HStack(spacing: 10) {
                    ProviderBadge(provider: provider, size: 26)
                    Text(command)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        // A Terminal command is never cut off: it wraps instead.
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                        withAnimation(Motion.snappy) { copied = command }
                    } label: {
                        Image(systemName: copied == command ? "checkmark" : "doc.on.doc")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.glass)
                    .help(l10n.common.copy)
                    .accessibilityLabel(l10n.accounts.copyCommandA11y(UsageFormat.providerName(provider)))
                    .accessibilityValue(copied == command ? l10n.accounts.copied : "")
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.quaternary.opacity(0.5)))
            }
            Label(l10n.accounts.secondAccountFootnote, systemImage: "info.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
