import CodometerCore
import CodometerL10n
import AppKit
import SwiftUI

/// When to notify, how quietly, and whether the island opens by itself.
struct AlertsPane: View {
    let store: TrackerStore

    @State private var issue: String?
    /// Notification permission as the system reports it; `nil` until the first answer arrives.
    @State private var authorization: NotificationAuthorization?
    @Environment(\.l10n) private var l10n

    private static let thresholdChoices: [Double] = [50, 75, 80, 90, 95, 100]
    /// How long the island opens by itself, in seconds; 0 is off.
    private static let peekChoices = [0, 3, 5, 10]
    private var alerts: AlertSettings { store.settings.alerts }

    var body: some View {
        Form {
            Section {
                PaneHeader(
                    title: l10n.settingsPanes.alerts,
                    subtitle: l10n.alerts.paneSubtitle,
                    systemImage: "bell.badge.fill",
                    tint: .red
                )
                if let issue {
                    SettingsIssueBanner(message: issue) { self.issue = nil }
                }
                if authorization == .denied {
                    permissionBanner
                }
            }

            Section {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(Self.thresholdChoices, id: \.self) { value in
                            let isOn = alerts.thresholds.values.contains { $0.value == value }
                            Button {
                                toggleThreshold(value, isOn: !isOn)
                            } label: {
                                Text(l10n.format.percentCompact(value))
                                    .monospacedDigit()
                                    .frame(minWidth: 40)
                            }
                            .buttonStyle(AnyPrimitiveButtonStyle.glass(selected: isOn))
                            .accessibilityLabel(l10n.alerts.thresholdA11y(l10n.format.percent(value)))
                            .accessibilityAddTraits(isOn ? .isSelected : [])
                            .animation(Motion.snappy, value: isOn)
                        }
                    }
                }
            } header: {
                Text(l10n.alerts.thresholdsTitle)
            } footer: {
                SectionNote(l10n.alerts.thresholdsFooter)
            }

            Section(l10n.alerts.eventsTitle) {
                eventToggle(l10n.alerts.limitReset, systemImage: "arrow.counterclockwise", tint: Theme.success, keyPath: \.notifiesOnReset)
                eventToggle(l10n.alerts.agentFinished, systemImage: "checkmark", tint: Theme.success, keyPath: \.notifiesOnSessionFinished)
                shortTurnPicker
                    .disabled(!alerts.notifiesOnSessionFinished)
                eventToggle(l10n.alerts.agentWaiting, subtitle: l10n.alerts.agentWaitingSubtitle, systemImage: "hand.raised.fill", tint: Theme.attention, keyPath: \.notifiesOnSessionWaiting)
            }

            Section {
                eventToggle(
                    l10n.alerts.withdrawResolved,
                    subtitle: l10n.alerts.withdrawResolvedSubtitle,
                    systemImage: "bell.slash.fill",
                    tint: .gray,
                    keyPath: \.withdrawsResolvedAlerts
                )
                eventToggle(
                    l10n.alerts.coalesce,
                    subtitle: l10n.alerts.coalesceSubtitle,
                    systemImage: "square.stack.3d.up.fill",
                    tint: .indigo,
                    keyPath: \.coalescesBursts
                )
            } header: {
                Text(l10n.alerts.quietTitle)
            } footer: {
                SectionNote(l10n.alerts.quietFooter(accountsPane: l10n.settingsPanes.accounts))
            }

            Section(l10n.alerts.soundAndIslandTitle) {
                Toggle(isOn: binding(\.playsSounds)) {
                    SettingsRowLabel(title: l10n.alerts.playSounds, systemImage: "speaker.wave.2.fill", tint: .pink)
                }
                .settingsControl(title: l10n.alerts.playSounds)
                HStack(spacing: 8) {
                    // System sound names, never shown.
                    ForEach([(l10n.alerts.soundFinished, "Glass"), (l10n.alerts.soundAttention, "Funk"), (l10n.alerts.soundThreshold, "Tink")], id: \.1) { title, sound in
                        Button {
                            NSSound(named: NSSound.Name(sound))?.play()
                        } label: {
                            Label(title, systemImage: "play.fill")
                        }
                        .buttonStyle(.glass)
                        .accessibilityLabel(l10n.alerts.playSoundA11y(title))
                    }
                    Spacer(minLength: 0)
                }
                .disabled(!alerts.playsSounds)
                durationPicker(
                    title: l10n.alerts.peek,
                    systemImage: "rectangle.expand.vertical",
                    tint: .purple,
                    choices: Self.peekChoices,
                    selection: Binding(
                        get: { alerts.peekDuration.seconds },
                        set: { seconds in
                            apply { (settings: inout AppSettings) throws(ValidationError) in
                                settings.alerts.peekDuration = try PeekDuration(seconds: seconds)
                            }
                        }
                    )
                )
            }
        }
        .formStyle(.grouped)
        .animation(Motion.content, value: issue)
        .animation(Motion.content, value: authorization)
        .task { await refreshAuthorization() }
        // Coming back from System Settings: ask again instead of leaving a stale banner.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshAuthorization() }
        }
    }

    /// macOS shows none of Codometer's notifications: say so once, and offer the one place that can change it.
    ///
    /// The button sits under the text, not beside it: the Russian title is long, and the detail column can be as
    /// narrow as 550 pt, where a trailing button truncates.
    private var permissionBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bell.slash.fill")
                .font(.title3)
                .foregroundStyle(Theme.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(l10n.alerts.permissionDeniedTitle)
                    .font(.callout.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(l10n.alerts.permissionDeniedBody)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(l10n.alerts.openNotificationSettings) {
                    store.actions.openNotificationSettings()
                }
                .buttonStyle(.glass)
                .frame(minHeight: 24)
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(l10n.alerts.permissionDeniedTitle)
    }

    private func refreshAuthorization() async {
        authorization = await store.actions.notificationAuthorization()
    }

    private var shortTurnPicker: some View {
        durationPicker(
            title: l10n.alerts.skipShortTurns,
            subtitle: l10n.alerts.skipShortTurnsSubtitle(finished: l10n.alerts.agentFinished),
            systemImage: "timer",
            tint: .orange,
            choices: SettingsCopy.turnThresholdOptions(current: alerts.minimumTurnForFinishedAlert),
            selection: Binding(
                get: { alerts.minimumTurnForFinishedAlert.seconds },
                set: { seconds in
                    apply { (settings: inout AppSettings) throws(ValidationError) in
                        settings.alerts.minimumTurnForFinishedAlert = try TurnAlertThreshold(seconds: seconds)
                    }
                }
            )
        )
    }

    /// A segmented choice of durations in seconds, drawn compactly ("Off", "20s", "1m").
    ///
    /// SwiftUI does not reliably keep accessibility labels on individual segments (they fall back to the drawn "3s",
    /// which speech need not read as a duration), so VoiceOver gets an equivalent radio group whose choices are the
    /// durations in words ("3 seconds"), followed by the row's explanation. Checked with AX dumps in both languages
    /// and after a language switch.
    private func durationPicker(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        tint: Color,
        choices: [Int],
        selection: Binding<Int>
    ) -> some View {
        Picker(selection: selection) {
            ForEach(choices, id: \.self) { seconds in
                Text(durationTitle(seconds: seconds)).tag(seconds)
            }
        } label: {
            SettingsRowLabel(title: title, subtitle: subtitle, systemImage: systemImage, tint: tint)
        }
        .pickerStyle(.segmented)
        .accessibilityRepresentation {
            VStack(alignment: .leading) {
                Picker(title, selection: selection) {
                    ForEach(choices, id: \.self) { seconds in
                        Text(l10n.alerts.secondsA11y(seconds)).tag(seconds)
                    }
                }
                .pickerStyle(.radioGroup)
                .horizontalRadioGroupLayout()
                .accessibilityLabel(title)
                if let subtitle {
                    Text(subtitle)
                }
            }
        }
    }

    /// A picker's duration: "Off" for zero, else "20s", "1m", "1m 30s" | «20 с», «1 мин».
    private func durationTitle(seconds: Int) -> String {
        seconds > 0 ? l10n.format.durationPrecise(TimeInterval(seconds)) : l10n.alerts.off
    }

    private func toggleThreshold(_ value: Double, isOn: Bool) {
        apply { (settings: inout AppSettings) throws(ValidationError) in
            var values = settings.alerts.thresholds.values.filter { $0.value != value }
            if isOn { values.append(try Percentage(validating: value)) }
            settings.alerts.thresholds = try AlertThresholds(values)
        }
    }

    private func eventToggle(
        _ title: String,
        subtitle: String? = nil,
        systemImage: String,
        tint: Color,
        keyPath: WritableKeyPath<AlertSettings, Bool>
    ) -> some View {
        Toggle(isOn: binding(keyPath)) {
            SettingsRowLabel(title: title, subtitle: subtitle, systemImage: systemImage, tint: tint)
        }
        .settingsControl(title: title, subtitle: subtitle)
    }

    private func binding(_ keyPath: WritableKeyPath<AlertSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.settings.alerts[keyPath: keyPath] },
            set: { newValue in apply { $0.alerts[keyPath: keyPath] = newValue } }
        )
    }

    private func apply(_ change: (inout AppSettings) throws(ValidationError) -> Void) {
        issue = store.updateSettings(change).map { SettingsCopy.settingsMessage(for: $0, l10n: l10n) }
    }
}
