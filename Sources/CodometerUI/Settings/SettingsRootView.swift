import CodometerCore
import CodometerL10n
import SwiftUI

/// The Settings sidebar, in order.
public enum SettingsPane: String, CaseIterable, Identifiable, Hashable, Sendable {
    case accounts
    /// Island or floating card, and where it sits (formerly Placement).
    case presentation
    case appearance
    case alerts
    case general
    case diagnostics

    public var id: String { rawValue }

    func title(_ l10n: Localizer) -> String {
        switch self {
        case .accounts: l10n.settingsPanes.accounts
        case .presentation: l10n.settingsPanes.presentation
        case .appearance: l10n.settingsPanes.appearance
        case .alerts: l10n.settingsPanes.alerts
        case .general: l10n.settingsPanes.general
        case .diagnostics: l10n.settingsPanes.diagnostics
        }
    }

    var systemImage: String {
        switch self {
        case .accounts: "person.2.fill"
        case .presentation: "rectangle.dashed"
        case .appearance: "paintpalette.fill"
        case .alerts: "bell.badge.fill"
        case .general: "gearshape.fill"
        case .diagnostics: "stethoscope"
        }
    }

    var tint: Color {
        switch self {
        case .accounts: .blue
        case .presentation: .purple
        case .appearance: .pink
        case .alerts: .red
        case .general: .gray
        case .diagnostics: .mint
        }
    }
}

public struct SettingsRootView: View {
    let store: TrackerStore
    @State private var selection: SettingsPane?
    /// Backdrop and "show expanded" of the island preview, shared by the panes that show it.
    @State private var stageOptions = IslandStageOptions()

    /// - Parameter initialPane: The pane selected when the view first appears.
    public init(store: TrackerStore, initialPane: SettingsPane = .accounts) {
        self.store = store
        _selection = State(initialValue: initialPane)
    }

    public var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selection) { pane in
                Label {
                    Text(pane.title(store.localizer))
                } icon: {
                    SettingsSymbol(systemImage: pane.systemImage, tint: pane.tint, size: 22)
                }
                .padding(.vertical, 1)
                .tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 250)
        } detail: {
            let pane = selection ?? .accounts
            SettingsDetail(store: store, pane: pane, stageOptions: $stageOptions)
                .navigationTitle(pane.title(store.localizer))
                .animation(Motion.content, value: selection)
        }
        .frame(minWidth: 800, minHeight: 580)
        .environment(\.l10n, store.localizer)
        .environment(\.locale, store.localizer.locale)
    }
}

/// The detail column: the notice banner above one pane.
struct SettingsDetail: View {
    let store: TrackerStore
    let pane: SettingsPane
    @Binding var stageOptions: IslandStageOptions

    var body: some View {
        VStack(spacing: 0) {
            AppNoticeBanner(store: store)
            Group {
                switch pane {
                case .accounts: AccountsPane(store: store)
                case .presentation: PlacementPane(store: store, stageOptions: $stageOptions)
                case .appearance: AppearancePane(store: store, stageOptions: $stageOptions)
                case .alerts: AlertsPane(store: store)
                case .general: GeneralPane(store: store)
                case .diagnostics: DiagnosticsPane(store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // On the switched pane itself, so changing panes blurs one into the other as before.
            .transition(.blurReplace)
        }
    }
}

#if DEBUG
/// One Settings pane on its own (the detail column without the window's sidebar and toolbar), in the store's language.
///
/// For the debug harness: the Settings window's split-view columns are composited in a way view and layer captures
/// cannot draw, so captures and accessibility dumps of Settings render the selected pane in a stand-in window instead.
public struct SettingsPaneCaptureView: View {
    let store: TrackerStore
    let pane: SettingsPane
    @State private var stageOptions = IslandStageOptions()

    public init(store: TrackerStore, pane: SettingsPane) {
        self.store = store
        self.pane = pane
    }

    public var body: some View {
        SettingsDetail(store: store, pane: pane, stageOptions: $stageOptions)
            .environment(\.l10n, store.localizer)
            .environment(\.locale, store.localizer.locale)
    }
}
#endif
