import CodometerCore
import CodometerL10n
import AppKit
import SwiftUI

/// Editable, not-yet-validated account fields.
struct AccountDraft: Identifiable {
    let id = UUID()
    let editingID: AccountID?
    var provider: ProviderKind
    var label: String
    var directory: String
    var pollSeconds: Int
    var isEnabled: Bool
    /// Kept when editing, so saving an account never drops it from its group.
    var groupID: AccountGroupID?
    /// The identity colour; `.automatic` lets Codometer pick a free one.
    var tint: AccountTint
    /// The typed monogram; empty follows the account's name.
    var monogramText: String

    init(provider: ProviderKind) {
        editingID = nil
        self.provider = provider
        label = UsageFormat.providerName(provider) + " · work"
        directory = NSHomeDirectory() + "/" + provider.defaultDirectoryName + "-work"
        pollSeconds = provider.defaultPollInterval.seconds
        isEnabled = true
        groupID = nil
        tint = .automatic
        monogramText = ""
    }

    init(editing account: AccountProfile) {
        editingID = account.id
        provider = account.provider
        label = account.label.value
        directory = account.directory.path
        pollSeconds = account.pollInterval.seconds
        isEnabled = account.isEnabled
        groupID = account.groupID
        tint = account.tint
        monogramText = account.monogram?.value ?? ""
    }

    /// The typed monogram, or `nil` when the field is empty and the name decides.
    func validatedMonogram() throws(ValidationError) -> AccountMonogram? {
        let trimmed = monogramText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return try AccountMonogram(validating: trimmed)
    }

    func validated() throws(ValidationError) -> AccountProfile {
        try AccountProfile(
            id: editingID ?? AccountID(),
            provider: provider,
            label: try AccountLabel(validating: label),
            directory: try ProfileDirectory(validating: (directory as NSString).expandingTildeInPath),
            isEnabled: isEnabled,
            pollInterval: try PollInterval(seconds: pollSeconds),
            groupID: groupID,
            tint: tint,
            monogram: try validatedMonogram()
        )
    }

    /// The monogram the account gets while the field is empty: from its name, or its number among the provider's
    /// accounts. The placeholder shows it, so the field never looks empty in the island.
    ///
    /// `nil` only while the typed name is not a valid label yet; the row then shows no placeholder.
    func automaticMonogram(in accounts: [AccountProfile]) -> AccountMonogram? {
        guard let name = try? AccountLabel(validating: label) else { return nil }
        return AccountMonogram.automatic(
            label: name,
            provider: provider,
            ordinal: Self.ordinal(of: editingID, provider: provider, in: accounts)
        )
    }

    /// An account's 1-based place among the accounts of its provider; a new account comes last.
    nonisolated static func ordinal(of id: AccountID?, provider: ProviderKind, in accounts: [AccountProfile]) -> Int {
        let sameProvider = accounts.filter { $0.provider == provider }
        if let id, let index = sameProvider.firstIndex(where: { $0.id == id }) {
            return index + 1
        }
        return sameProvider.count + 1
    }
}

struct AccountEditorSheet: View {
    @State var draft: AccountDraft
    let store: TrackerStore
    let onClose: () -> Void

    @State private var errorText: String?
    @Environment(\.l10n) private var l10n

    private static let intervalChoices = [60, 120, 180, 300, 600, 900, 1_800, 3_600]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ProviderBadge(provider: draft.provider, size: 44)
                    .animation(Motion.snappy, value: draft.provider)
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.editingID == nil ? l10n.accounts.newAccountTitle : l10n.accounts.editAccountTitle).font(.title3.weight(.semibold))
                    Text(l10n.accounts.editorSubtitle).font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(20)

            Form {
                Picker(l10n.accounts.service, selection: $draft.provider) {
                    Text("Claude Code").tag(ProviderKind.claude)
                    Text("Codex").tag(ProviderKind.codex)
                }
                .pickerStyle(.segmented)
                .disabled(draft.editingID != nil)
                .onChange(of: draft.provider) { _, provider in
                    draft.pollSeconds = max(draft.pollSeconds, provider.minimumPollInterval.seconds)
                    if draft.editingID == nil {
                        draft.label = UsageFormat.providerName(provider) + " · work"
                        draft.directory = NSHomeDirectory() + "/" + provider.defaultDirectoryName + "-work"
                    }
                }
                TextField(l10n.accounts.name, text: $draft.label)
                LabeledContent(l10n.accounts.profileFolder) {
                    HStack {
                        TextField("", text: $draft.directory)
                            .labelsHidden()
                            .font(.callout.monospaced())
                            .accessibilityLabel(l10n.accounts.profileFolder)
                        Button(l10n.accounts.chooseFolder) { chooseDirectory() }
                            .buttonStyle(.glass)
                    }
                }
                Picker(l10n.accounts.refresh, selection: $draft.pollSeconds) {
                    ForEach(Self.intervalChoices.filter { $0 >= draft.provider.minimumPollInterval.seconds }, id: \.self) { seconds in
                        Text(SettingsCopy.refreshInterval(seconds: seconds, l10n: l10n)).tag(seconds)
                    }
                }
                if !store.settings.groups.isEmpty {
                    Picker(l10n.groups.group, selection: $draft.groupID) {
                        Text(l10n.groups.noGroup).tag(AccountGroupID?.none)
                        ForEach(store.settings.groups) { group in
                            Text(group.name.value).tag(AccountGroupID?.some(group.id))
                        }
                    }
                }
                Toggle(l10n.accounts.trackAccount, isOn: $draft.isEnabled)
                if let errorText {
                    InlineIssue(message: errorText)
                }

                Section {
                    LabeledContent(l10n.accountStyle.monogram) {
                        HStack(spacing: 10) {
                            TextField(
                                l10n.accountStyle.monogram,
                                text: $draft.monogramText,
                                prompt: automaticMonogram.map { Text(verbatim: $0.value) }
                            )
                            .labelsHidden()
                            .frame(width: Self.monogramFieldWidth)
                            .accessibilityLabel(l10n.accountStyle.monogram)
                            .accessibilityValue(monogramA11yValue)
                            // The badge's room is always reserved, so the row never changes height while typing.
                            Color.clear
                                .frame(width: 30, height: 30)
                                .overlay {
                                    if let previewStyle {
                                        AccountBadge(style: previewStyle, provider: draft.provider, size: 30)
                                    }
                                }
                            Spacer(minLength: 0)
                        }
                    }
                    if let monogramIssue {
                        InlineIssue(message: monogramIssue)
                    } else {
                        SectionNote(l10n.accountStyle.monogramFooter)
                    }
                    LabeledContent(l10n.accountStyle.color) {
                        TintSwatches(selection: $draft.tint)
                    }
                } header: {
                    Text(l10n.accountStyle.section)
                } footer: {
                    SectionNote(l10n.accountStyle.colorFooter)
                }
            }
            .formStyle(.grouped)
            .animation(Motion.content, value: errorText)
            .animation(Motion.content, value: monogramIssue)
            .onChange(of: draft.label) { errorText = nil }
            .onChange(of: draft.directory) { errorText = nil }
            .onChange(of: draft.monogramText) { _, text in
                // Two characters is the whole point of a monogram; extra typing is dropped as it happens.
                let trimmed = String(text.prefix(AccountMonogram.maximumCharacters))
                if trimmed != text { draft.monogramText = trimmed }
                errorText = nil
            }

            HStack {
                Spacer()
                Button(l10n.common.cancel, role: .cancel) { onClose() }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
                Button(l10n.common.save) { save() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 540)
    }

    /// Wide enough for two characters and an emoji at the system body size.
    static let monogramFieldWidth: CGFloat = 64

    /// What the account's monogram would be while the field is empty.
    private var automaticMonogram: AccountMonogram? {
        draft.automaticMonogram(in: store.settings.accounts)
    }

    /// The badge as it will look: the typed monogram when it is usable, the automatic one otherwise. `nil` while
    /// neither is available — the name is still being typed — and the badge's room simply stays empty.
    private var previewStyle: AccountStyle? {
        let typed = (try? draft.validatedMonogram()) ?? nil
        guard let monogram = typed ?? automaticMonogram else { return nil }
        return try? AccountStyle(
            tint: resolvedTint,
            monogram: monogram,
            isAutomaticTint: draft.tint == .automatic,
            isAutomaticMonogram: typed == nil
        )
    }

    /// The colour the badge shows: the chosen one, or the one the resolver already handed this account. A brand-new
    /// account has no place in the resolver yet, so its automatic colour previews as the neutral tint.
    private var resolvedTint: AccountTint {
        guard draft.tint == .automatic else { return draft.tint }
        guard let id = draft.editingID, let style = AccountStyleResolver.styles(for: store.settings.accounts)[id] else {
            return .graphite
        }
        return style.tint
    }

    /// The live validation message under the monogram field, while the typed text cannot be used.
    private var monogramIssue: String? {
        guard !draft.monogramText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        do throws(ValidationError) {
            _ = try draft.validatedMonogram()
            return nil
        } catch {
            return l10n.accountStyle.monogramInvalid
        }
    }

    /// VoiceOver reads what the field will actually produce, including the automatic monogram behind an empty field.
    private var monogramA11yValue: String {
        guard draft.monogramText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return draft.monogramText }
        guard let automaticMonogram else { return "" }
        return l10n.accountStyle.monogramAutomaticA11y(automaticMonogram.value)
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        panel.prompt = l10n.accounts.choose
        if panel.runModal() == .OK, let url = panel.url {
            draft.directory = url.path
        }
    }

    private func save() {
        // A group deleted while the sheet was open is dropped instead of failing the save.
        if let groupID = draft.groupID, store.settings.group(groupID) == nil {
            draft.groupID = nil
        }
        let account: AccountProfile
        do throws(ValidationError) {
            account = try draft.validated()
        } catch {
            errorText = SettingsCopy.accountMessage(for: error, l10n: l10n)
            return
        }
        let failure = draft.editingID == nil ? store.addAccount(account) : store.replaceAccount(account)
        if let failure {
            errorText = SettingsCopy.accountMessage(for: failure, l10n: l10n)
        } else {
            onClose()
        }
    }
}

/// The account's colour: Automatic plus the eight palette tints, each a circle with its own VoiceOver name.
///
/// Colour alone never carries the choice: the selected swatch wears a ring and a check mark, and VoiceOver reads
/// the tint's name.
struct TintSwatches: View {
    @Binding var selection: AccountTint
    @Environment(\.l10n) private var l10n

    /// The circle itself; the button around it is `hitTarget` so every swatch clears the 24 pt minimum.
    static let swatchSize: CGFloat = 22
    static let hitTarget: CGFloat = 28

    var body: some View {
        HStack(spacing: 2) {
            swatch(.automatic)
            ForEach(AccountTint.palette) { tint in
                swatch(tint)
            }
            Spacer(minLength: 0)
        }
    }

    private func swatch(_ tint: AccountTint) -> some View {
        let isSelected = selection == tint
        let name = Self.name(of: tint, l10n: l10n)
        return Button {
            selection = tint
        } label: {
            ZStack {
                Circle()
                    .fill(tint == .automatic ? AnyShapeStyle(Theme.subtleFill) : AnyShapeStyle(Theme.accountTint(for: tint)))
                    .frame(width: Self.swatchSize, height: Self.swatchSize)
                if tint == .automatic, !isSelected {
                    Image(systemName: "wand.and.sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(tint == .automatic ? AnyShapeStyle(HierarchicalShapeStyle.secondary) : AnyShapeStyle(Color.white))
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.55), lineWidth: 1.5)
                        .frame(width: Self.swatchSize + 5, height: Self.swatchSize + 5)
                }
            }
            .frame(width: Self.hitTarget, height: Self.hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// The tint's name, for VoiceOver and the tooltip.
    static func name(of tint: AccountTint, l10n: Localizer) -> String {
        switch tint {
        case .automatic: l10n.accountStyle.automatic
        case .teal: l10n.accountStyle.teal
        case .sky: l10n.accountStyle.sky
        case .indigo: l10n.accountStyle.indigo
        case .lime: l10n.accountStyle.lime
        case .pink: l10n.accountStyle.pink
        case .sand: l10n.accountStyle.sand
        case .slate: l10n.accountStyle.slate
        case .graphite: l10n.accountStyle.graphite
        }
    }
}
