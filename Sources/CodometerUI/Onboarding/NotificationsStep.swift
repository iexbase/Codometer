import CodometerCore
import CodometerL10n
import SwiftUI

/// Step 5: notification permission (asked here, with the reason in front of it), opening at login, and the global
/// shortcut with its conflict status.
///
/// The shortcut row is General's own `ShortcutPreview`, so the words, the alternatives and the reserved height are
/// the ones Settings uses; a conflict never changes the step's height.
struct NotificationsStep: View {
    let model: OnboardingModel

    @State private var loginItemError: String?
    @Environment(\.l10n) private var l10n

    private var general: GeneralSettings { model.store.settings.general }

    /// The status of the combination the picker shows right now, by General's rule.
    var shortcutStatus: ShortcutStatus {
        GeneralPane.status(model.store.shortcutStatus, for: general.globalShortcut)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            OnboardingHeader(title: l10n.onboarding.notificationsTitle, message: l10n.onboarding.notificationsBody)
            notifications
            Divider()
            login
            Divider()
            shortcut
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .task {
            await model.refreshNotificationAuthorization()
            model.store.actions.refreshShortcutStatus()
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var notifications: some View {
        switch model.notifications {
        case .authorized, .provisional:
            Label(l10n.onboarding.notificationsOn, systemImage: "bell.badge.fill")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(minHeight: SettingsMetrics.hitTarget)
        case .denied:
            HStack(spacing: 10) {
                Label(l10n.onboarding.notificationsOff, systemImage: "bell.slash")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button(l10n.onboarding.openNotificationSettings) { model.store.actions.openNotificationSettings() }
                    .buttonStyle(.glass)
                    .frame(minHeight: SettingsMetrics.hitTarget)
            }
        case .notDetermined:
            Button(l10n.onboarding.allowNotifications) {
                Task { await model.requestNotifications() }
            }
            .buttonStyle(.glass)
            .frame(minHeight: SettingsMetrics.hitTarget)
        }
    }

    private var login: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { general.launchesAtLogin },
                set: { isOn in setLaunchAtLogin(isOn) }
            )) {
                Text(l10n.general.openAtLogin)
            }
            .frame(minHeight: SettingsMetrics.hitTarget)
            .accessibilityLabel(l10n.general.openAtLogin)
            if let loginItemError {
                InlineIssue(message: loginItemError)
            }
        }
    }

    private func setLaunchAtLogin(_ isOn: Bool) {
        loginItemError = model.store.actions.setLaunchAtLogin(isOn)
        guard loginItemError == nil else { return }
        model.store.updateSettings { $0.general.launchesAtLogin = isOn }
    }

    private var shortcut: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n.general.shortcutTitle)
                .font(.callout.weight(.medium))
            Picker(selection: Binding(
                get: { general.globalShortcut },
                set: { shortcut in choose(shortcut) }
            )) {
                ForEach(SettingsCopy.shortcutChoices) { shortcut in
                    Text(ShortcutKeys.title(shortcut, l10n: l10n)).tag(shortcut)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 320)
            .accessibilityLabel(l10n.general.shortcut)
            ShortcutPreview(status: shortcutStatus) { alternative in choose(alternative) }
        }
    }

    private func choose(_ shortcut: GlobalShortcut) {
        model.store.updateSettings { $0.general.globalShortcut = shortcut }
        model.store.actions.refreshShortcutStatus()
    }
}
