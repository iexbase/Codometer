import CodometerCore
import CodometerL10n
import SwiftUI

/// General → Network: the opt-in service status check and the hosts it contacts.
///
/// One toggle and an honest explanation. The footer is always there, whichever way the toggle stands, so switching it
/// never changes the pane's height.
struct NetworkSection: View {
    let store: TrackerStore

    @Environment(\.l10n) private var l10n

    var body: some View {
        Section {
            Toggle(isOn: Binding(
                get: { store.settings.general.showsVendorStatus },
                set: { isOn in store.updateSettings { $0.general.showsVendorStatus = isOn } }
            )) {
                SettingsRowLabel(
                    title: l10n.network.showServiceStatus,
                    subtitle: l10n.network.showServiceStatusSubtitle,
                    systemImage: "dot.radiowaves.up.forward",
                    tint: .blue
                )
            }
            .settingsControl(title: l10n.network.showServiceStatus, subtitle: l10n.network.showServiceStatusSubtitle)
        } header: {
            Text(l10n.network.title)
        } footer: {
            SectionNote(l10n.network.disclosure(hosts: Self.hostList(l10n: l10n)))
        }
    }

    /// The two hosts, named in full and joined the way the language joins a list.
    static func hostList(l10n: Localizer) -> String {
        l10n.format.list(ProviderKind.allCases.map { VendorStatusFeed.host(for: $0) })
    }
}
