import CodometerCore
import CodometerL10n
import SwiftUI

/// General → Energy: how often Codometer refreshes when the Mac is on battery, low or hot.
///
/// The line under the picker always says what is happening right now, so it never appears or disappears; its height is
/// reserved for the longest state in either language (`GeneralSnapshotTests` measures them). It changes without an
/// animation on purpose: animating a row inside a grouped `Form` costs a third of a second of main-thread work here
/// (measured with the harness `monitor`), and nothing moves anyway.
struct EnergySection: View {
    let store: TrackerStore

    @Environment(\.l10n) private var l10n

    var body: some View {
        Section {
            // The segments take the whole row: with a leading row label the Russian titles would not fit.
            Picker(selection: Binding(
                get: { store.settings.general.energyMode },
                set: { mode in store.updateSettings { $0.general.energyMode = mode } }
            )) {
                ForEach(EnergyMode.allCases) { mode in
                    Text(Self.title(mode, l10n: l10n)).tag(mode)
                }
            } label: {
                Text(l10n.energy.mode)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            // No `settingsControl` here: `labelsHidden` hides the label but keeps it for VoiceOver, so a second
            // accessibility label would make the group read its name twice (seen in `ax-general-ru.json`).
            .frame(minHeight: SettingsMetrics.hitTarget)
            Label {
                Text(Self.state(store.energy, l10n: l10n))
            } icon: {
                Image(systemName: symbol)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: Self.stateHeight, alignment: .topLeading)
        } header: {
            Text(l10n.energy.title)
        } footer: {
            SectionNote(l10n.energy.footer)
        }
    }

    /// Two callout lines, so no state changes the section's height.
    static let stateHeight: CGFloat = 34

    static func title(_ mode: EnergyMode, l10n: Localizer) -> String {
        switch mode {
        case .automatic: l10n.energy.modeAutomatic
        case .alwaysFresh: l10n.energy.modeAlwaysFresh
        case .saveBattery: l10n.energy.modeSaveBattery
        }
    }

    /// What the energy policy decided, in words.
    static func state(_ decision: EnergyDecision, l10n: Localizer) -> String {
        switch decision.reason {
        case .normal: l10n.energy.stateNormal
        case .battery: l10n.energy.stateBattery
        case .lowBattery: l10n.energy.stateLowBattery
        case .lowPowerMode: l10n.energy.stateLowPower
        case .thermal: l10n.energy.stateThermal
        case .saver: l10n.energy.stateSaver
        }
    }

    private var symbol: String {
        switch store.energy.reason {
        case .normal: "checkmark.circle"
        case .battery: "battery.75percent"
        case .lowBattery: "battery.25percent"
        case .lowPowerMode: "bolt.badge.clock"
        case .thermal: "thermometer.high"
        case .saver: "leaf"
        }
    }
}
