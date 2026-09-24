import CodometerCore
import CodometerL10n
import Foundation
import SwiftUI

/// Language, launch, the global shortcut, the desktop widget, energy, the network check, your data, and About.
///
/// The sections that belong to other features bring their own `Section` (`EnergySection`, `NetworkSection`,
/// `DataSection`), so this pane only places them.
struct GeneralPane: View {
    let store: TrackerStore

    @State private var loginItemError: String?
    @State private var issue: String?
    @State private var loginStatus: LoginItemStatus = .unavailable
    @State private var build: AppBuildInfo?
    @Environment(\.l10n) private var l10n

    private var general: GeneralSettings { store.settings.general }

    var body: some View {
        Form {
            Group {
                headerSection
                languageSection
                startupSection
                shortcutSection
                widgetSection
            }
            Group {
                EnergySection(store: store)
                NetworkSection(store: store)
                DataSection(store: store)
                sourcesSection
                privacySection
                welcomeSection
                aboutSection
            }
        }
        .formStyle(.grouped)
        .onAppear {
            // The registration may have been retried since the window last opened, and a login item can be switched
            // off in System Settings without the app hearing about it.
            store.actions.refreshShortcutStatus()
            loginStatus = store.actions.loginItemStatus()
            build = store.actions.appBuildInfo()
        }
        .animation(Motion.content, value: issue)
        .animation(Motion.content, value: loginItemError)
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            PaneHeader(
                title: l10n.settingsPanes.general,
                subtitle: l10n.general.paneSubtitle,
                systemImage: "gearshape.fill",
                tint: .gray
            )
            if let issue {
                SettingsIssueBanner(message: issue) { self.issue = nil }
            }
        }
    }

    private var languageSection: some View {
        Section {
            Picker(selection: Binding(
                get: { general.language },
                set: { language in apply { $0.general.language = language } }
            )) {
                ForEach(LanguagePreference.allCases) { preference in
                    Text(languageName(preference)).tag(preference)
                }
            } label: {
                SettingsRowLabel(title: l10n.languageSettings.title, systemImage: "globe", tint: .blue)
            }
            .settingsControl(title: l10n.languageSettings.title)
            HStack {
                Spacer()
                Button(l10n.languageSettings.relaunch) { store.actions.relaunch() }
                    .buttonStyle(.glass)
                    .frame(minHeight: SettingsMetrics.hitTarget)
            }
        } footer: {
            // Always shown, so choosing a language never changes the section's height.
            SectionNote(l10n.languageSettings.relaunchFootnote)
        }
    }

    private var startupSection: some View {
        Section(l10n.general.startupTitle) {
            Toggle(isOn: Binding(
                get: { general.launchesAtLogin },
                set: { isOn in
                    loginItemError = store.actions.setLaunchAtLogin(isOn)
                    if loginItemError == nil {
                        apply { $0.general.launchesAtLogin = isOn }
                    }
                    loginStatus = store.actions.loginItemStatus()
                }
            )) {
                SettingsRowLabel(title: l10n.general.openAtLogin, systemImage: "power", tint: .green)
            }
            .settingsControl(title: l10n.general.openAtLogin)
            if let loginItemError {
                InlineIssue(message: loginItemError)
            }
            switch loginStatus {
            case .requiresApproval:
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(l10n.general.loginItemNeedsApproval)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button(l10n.general.allowInSystemSettings) { store.actions.openLoginItemsSettings() }
                        .buttonStyle(.glass)
                        .frame(minHeight: SettingsMetrics.hitTarget)
                }
            case .notFound where general.launchesAtLogin:
                InlineIssue(message: l10n.general.loginItemNotFound)
            case .enabled, .disabled, .notFound, .unavailable:
                EmptyView()
            }
        }
    }

    private var shortcutSection: some View {
        Section {
            Picker(selection: Binding(
                get: { general.globalShortcut },
                set: { shortcut in apply { $0.general.globalShortcut = shortcut } }
            )) {
                ForEach(SettingsCopy.shortcutChoices) { shortcut in
                    Text(ShortcutKeys.title(shortcut, l10n: l10n)).tag(shortcut)
                }
            } label: {
                SettingsRowLabel(title: l10n.general.shortcut, systemImage: "command", tint: .indigo)
            }
            .settingsControl(title: l10n.general.shortcut)
            .pickerStyle(.segmented)
            ShortcutPreview(status: shortcutStatus) { alternative in
                apply { $0.general.globalShortcut = alternative }
            }
        } header: {
            Text(l10n.general.shortcutTitle)
        } footer: {
            SectionNote(l10n.general.shortcutFooter)
        }
    }

    private var widgetSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { general.exportsWidgetData },
                set: { isOn in apply { $0.general.exportsWidgetData = isOn } }
            )) {
                SettingsRowLabel(
                    title: l10n.general.widgetData,
                    subtitle: l10n.general.widgetDataSubtitle,
                    systemImage: "square.grid.2x2.fill",
                    tint: .teal
                )
            }
            .settingsControl(title: l10n.general.widgetData, subtitle: l10n.general.widgetDataSubtitle)
            Picker(selection: Binding(
                get: { general.widgetLayout },
                set: { layout in apply { $0.general.widgetLayout = layout } }
            )) {
                ForEach(WidgetLayout.allCases) { layout in
                    Text(Self.title(layout, l10n: l10n)).tag(layout)
                }
            } label: {
                SettingsRowLabel(
                    title: l10n.general.widgetLayout,
                    subtitle: l10n.general.widgetLayoutSubtitle,
                    systemImage: "rectangle.split.2x1",
                    tint: .teal
                )
            }
            .pickerStyle(.segmented)
            .settingsControl(title: l10n.general.widgetLayout, subtitle: l10n.general.widgetLayoutSubtitle)
            WidgetSteps()
                .opacity(general.exportsWidgetData ? 1 : 0.45)
                .animation(Motion.content, value: general.exportsWidgetData)
        } header: {
            Text(l10n.general.widgetTitle)
        } footer: {
            // One text for both states, so switching never changes the section's height.
            SectionNote(l10n.general.widgetFooter(
                appearancePane: l10n.settingsPanes.appearance,
                privacySection: l10n.appearance.privacyTitle,
                noData: l10n.common.noData
            ))
        }
    }

    private var sourcesSection: some View {
        Section(l10n.general.sourcesTitle) {
            infoRow("Claude", detail: l10n.general.claudeSource, systemImage: "sparkle", tint: Theme.accent(for: .claude))
            infoRow("Codex", detail: l10n.general.codexSource, systemImage: "chevron.left.forwardslash.chevron.right", tint: Theme.accent(for: .codex))
            infoRow(l10n.general.signatureCheck, detail: l10n.general.signatureCheckDetail, systemImage: "checkmark.seal.fill", tint: .green)
        }
    }

    private var privacySection: some View {
        Section(l10n.general.privacyTitle) {
            infoRow(l10n.general.tokens, detail: l10n.general.tokensDetail, systemImage: "lock.shield.fill", tint: .blue)
            infoRow(l10n.general.network, detail: l10n.general.networkDetail, systemImage: "network.slash", tint: .gray)
            infoRow(l10n.general.conversations, detail: l10n.general.conversationsDetail, systemImage: "eye.slash.fill", tint: .purple)
            HStack {
                Spacer()
                Button {
                    store.actions.revealDataFolder()
                } label: {
                    Label(l10n.general.showDataFolder, systemImage: "folder")
                }
                .buttonStyle(.glass)
                .frame(minHeight: SettingsMetrics.hitTarget)
            }
        }
    }

    private var welcomeSection: some View {
        Section {
            HStack {
                Spacer()
                Button(l10n.general.showWelcomeGuide) { store.actions.showOnboarding() }
                    .buttonStyle(.glass)
                    .frame(minHeight: SettingsMetrics.hitTarget)
            }
        } footer: {
            SectionNote(l10n.general.welcomeGuideFooter)
        }
    }

    private var aboutSection: some View {
        Section(l10n.general.aboutTitle) {
            let info = build ?? AppBuildInfo(version: "", build: "", locationKind: .other, licenseName: nil)
            let version = l10n.general.versionAndBuild(version: info.version, build: info.build)
            LabeledContent {
                HStack(spacing: 10) {
                    Text(version)
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Button(l10n.common.copy) { store.actions.copyToPasteboard(l10n.general.appVersion(version)) }
                        .buttonStyle(.glass)
                        .frame(minHeight: SettingsMetrics.hitTarget)
                        .accessibilityLabel(l10n.general.copyVersionA11y)
                }
            } label: {
                SettingsRowLabel(title: l10n.general.versionTitle, systemImage: "info.circle.fill", tint: .gray)
            }
            if let license = info.licenseName {
                LabeledContent {
                    Text(license).foregroundStyle(.secondary)
                } label: {
                    SettingsRowLabel(title: l10n.general.licenseTitle, systemImage: "doc.text.fill", tint: .brown)
                }
            }
            HStack {
                Spacer()
                Button(l10n.menu.quit, role: .destructive) { store.actions.quit() }
                    .buttonStyle(.glass)
                    .frame(minHeight: SettingsMetrics.hitTarget)
            }
        }
    }

    // MARK: - Helpers

    /// The status of the shortcut the picker shows right now. A status left over from another combination (the user
    /// just picked a different one and registration has not answered yet) is ignored, so the row never blames the
    /// wrong keys.
    var shortcutStatus: ShortcutStatus {
        Self.status(store.shortcutStatus, for: general.globalShortcut)
    }

    /// Pure rule behind `shortcutStatus`.
    nonisolated static func status(_ reported: ShortcutStatus, for chosen: GlobalShortcut) -> ShortcutStatus {
        guard chosen != .off else { return .off }
        switch reported {
        case .off:
            return .active(chosen)
        case .active(let shortcut):
            return shortcut == chosen ? reported : .active(chosen)
        case .unavailable(let shortcut, _, _):
            return shortcut == chosen ? reported : .active(chosen)
        }
    }

    /// The widget layout picker's titles.
    nonisolated static func title(_ layout: WidgetLayout, l10n: Localizer) -> String {
        switch layout {
        case .rings: l10n.general.widgetLayoutRings
        case .strip: l10n.general.widgetLayoutStrip
        }
    }

    /// English and Russian are named in their own language, whatever the interface language.
    private func languageName(_ preference: LanguagePreference) -> String {
        switch preference {
        case .english: l10n.languageSettings.nativeName(.en)
        case .russian: l10n.languageSettings.nativeName(.ru)
        case .system: l10n.languageSettings.systemLanguage
        }
    }

    /// `detail` is inline Markdown, so commands in backticks keep their monospaced look.
    private func infoRow(_ title: String, detail: String, systemImage: String, tint: Color) -> some View {
        LabeledContent {
            Text(Self.inlineMarkdown(detail))
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
        } label: {
            SettingsRowLabel(title: title, systemImage: systemImage, tint: tint)
        }
    }

    /// Inline Markdown only (code spans, emphasis), whitespace kept; plain text if it does not parse.
    static func inlineMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    private func apply(_ change: (inout AppSettings) throws(ValidationError) -> Void) {
        issue = store.updateSettings(change).map { SettingsCopy.settingsMessage(for: $0, l10n: l10n) }
    }
}

/// Sizes the General and Diagnostics panes reserve, so text and status changes never resize a row.
enum SettingsMetrics {
    /// The smallest side of anything the pointer or VoiceOver targets.
    static let hitTarget: CGFloat = 24
    /// The key-cap row of the shortcut preview.
    static let shortcutKeyRow: CGFloat = 30
    /// Two callout lines of explanation under the key caps.
    static let shortcutCaption: CGFloat = 34
}

/// Key caps and picker titles of the global shortcuts, with the space bar named in the interface language.
enum ShortcutKeys {
    /// One key: what its cap shows and what VoiceOver says.
    struct Key: Equatable {
        let cap: String
        let spoken: String
    }

    /// The keys of `shortcut`, in order; empty when it is off. Modifier names are the ones printed on Mac keyboards.
    static func keys(_ shortcut: GlobalShortcut, l10n: Localizer) -> [Key] {
        let control = Key(cap: "⌃", spoken: "Control")
        let option = Key(cap: "⌥", spoken: "Option")
        let command = Key(cap: "⌘", spoken: "Command")
        switch shortcut {
        case .off: return []
        case .controlOptionCommandU: return [control, option, command, Key(cap: "U", spoken: "U")]
        case .controlOptionSpace: return [control, option, Key(cap: l10n.general.spaceKey, spoken: l10n.general.spaceKey)]
        case .controlOptionCommandL: return [control, option, command, Key(cap: "L", spoken: "L")]
        }
    }

    /// The picker's title: the key caps run together ("⌃⌥⌘U", "⌃⌥Space"), or "Off".
    static func title(_ shortcut: GlobalShortcut, l10n: Localizer) -> String {
        shortcut == .off ? l10n.general.shortcutOff : keys(shortcut, l10n: l10n).map(\.cap).joined()
    }

    /// The keys as VoiceOver reads a shortcut: "Control-Option-Command-U".
    static func spoken(_ shortcut: GlobalShortcut, l10n: Localizer) -> String {
        keys(shortcut, l10n: l10n).map(\.spoken).joined(separator: "-")
    }

    /// A warning for shortcuts macOS often uses itself, while nothing worse is known about them.
    static func warning(_ shortcut: GlobalShortcut, l10n: Localizer) -> String? {
        switch shortcut {
        case .controlOptionSpace: l10n.general.spaceShortcutWarning
        case .off, .controlOptionCommandU, .controlOptionCommandL: nil
        }
    }

    /// The line under the key caps: why the shortcut does not work, the standing caution, or where it works.
    static func caption(_ status: ShortcutStatus, l10n: Localizer) -> String {
        switch status {
        case .off:
            return l10n.general.shortcutOffHint
        case .active(let shortcut):
            return warning(shortcut, l10n: l10n) ?? l10n.general.fromAnyApp
        case .unavailable(let shortcut, let reason, _):
            let keys = title(shortcut, l10n: l10n)
            return switch reason {
            case .usedByMacOS: l10n.shortcut.unavailableMacOS(keys: keys)
            case .usedByAnotherApp: l10n.shortcut.unavailableApp(keys: keys)
            case .failed: l10n.shortcut.unavailableFailed(keys: keys)
            }
        }
    }

    /// What VoiceOver reads for the key-cap row.
    static func keysA11y(_ status: ShortcutStatus, l10n: Localizer) -> String {
        switch status {
        case .off: l10n.general.shortcutOffHint
        case .active(let shortcut), .unavailable(let shortcut, _, _):
            l10n.general.shortcutA11y(keys: spoken(shortcut, l10n: l10n))
        }
    }
}

/// The chosen shortcut as key caps, with what happened to it underneath: nothing, the ⌃⌥Space caution, or a conflict
/// with the free combinations to switch to.
///
/// The whole preview keeps one height in every state, so a conflict appearing never moves the pane.
struct ShortcutPreview: View {
    let status: ShortcutStatus
    /// Applies one of the offered combinations.
    var onChoose: (GlobalShortcut) -> Void = { _ in }

    @Environment(\.l10n) private var l10n

    private var shortcut: GlobalShortcut {
        switch status {
        case .off: .off
        case .active(let shortcut), .unavailable(let shortcut, _, _): shortcut
        }
    }

    private var alternatives: [GlobalShortcut] {
        guard case .unavailable(_, _, let alternatives) = status else { return [] }
        return alternatives
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                let keys = ShortcutKeys.keys(shortcut, l10n: l10n)
                if keys.isEmpty {
                    Image(systemName: "keyboard")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                } else {
                    ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                        KeyCap(key: key.cap)
                    }
                }
                if !alternatives.isEmpty {
                    Text(l10n.shortcut.tryInstead)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 6)
                    ForEach(alternatives) { alternative in
                        Button(ShortcutKeys.title(alternative, l10n: l10n)) { onChoose(alternative) }
                            .buttonStyle(.glass)
                            .frame(minHeight: SettingsMetrics.hitTarget)
                            .accessibilityLabel(l10n.shortcut.tryA11y(keys: ShortcutKeys.spoken(alternative, l10n: l10n)))
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: SettingsMetrics.shortcutKeyRow)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(ShortcutKeys.keysA11y(status, l10n: l10n))
            Label {
                Text(ShortcutKeys.caption(status, l10n: l10n))
            } icon: {
                Image(systemName: captionSymbol)
                    .symbolRenderingMode(isWarning ? .multicolor : .monochrome)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: SettingsMetrics.shortcutCaption, alignment: .topLeading)
        }
        .animation(Motion.content, value: shortcut)
    }

    private var isWarning: Bool {
        if case .unavailable = status { return true }
        return ShortcutKeys.warning(shortcut, l10n: l10n) != nil
    }

    private var captionSymbol: String {
        isWarning ? "exclamationmark.triangle.fill" : "info.circle"
    }
}

/// How to put the widget on the desktop.
private struct WidgetSteps: View {
    @Environment(\.l10n) private var l10n

    private var steps: [(symbol: String, text: String)] {
        [
            ("cursorarrow.click.2", l10n.general.widgetStepOpenMenu),
            ("square.grid.2x2", l10n.general.widgetStepEditWidgets),
            ("magnifyingglass", l10n.general.widgetStepDrag),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .center, spacing: 12) {
                    Text(verbatim: String(index + 1))
                        .font(.callout.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.teal.gradient))
                    Image(systemName: step.symbol)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 22)
                    Text(step.text)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(l10n.general.widgetStepsA11y)
    }
}
