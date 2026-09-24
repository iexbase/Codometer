import CodometerCore
import CodometerL10n
import SwiftUI

/// The floating card's rows in the Presentation pane: theme, size, account, third tile, and where the card lives.
///
/// The Presentation pane shows these rows instead of the island's when the floating card is the selected style.
struct CardSettingsSection: View {
    let store: TrackerStore

    @Environment(\.l10n) private var l10n

    private var settings: FloatingCardSettings { store.settings.appearance.floatingCard }

    var body: some View {
        Section(l10n.card.sectionTitle) {
            themeRow
            sizeRow
            accountRow
            if settings.size == .strip {
                scopeRow
            } else {
                thirdTileRow
            }
        }
        Section {
            keepAboveRow
            fullScreenRow
            scaleRow
            snapRow
            displayRow
            resetRow
        } footer: {
            SectionNote(l10n.card.snapCaption)
        }
    }

    // MARK: - Look

    private var themeRow: some View {
        Picker(selection: binding(\.theme)) {
            ForEach(CardTheme.allCases) { theme in
                Text(CardMenuPlan.title(theme, l10n: l10n)).tag(theme)
            }
        } label: {
            SettingsRowLabel(title: l10n.card.themeRow, systemImage: "paintpalette", tint: .purple)
        }
        .pickerStyle(.menu)
        .settingsControl(title: l10n.card.themeRow)
    }

    private var sizeRow: some View {
        Picker(selection: binding(\.size)) {
            ForEach(CardSize.allCases) { size in
                Text(CardMenuPlan.title(size, l10n: l10n)).tag(size)
            }
        } label: {
            SettingsRowLabel(title: l10n.card.sizeRow, systemImage: "rectangle.resize", tint: .indigo)
        }
        .pickerStyle(.segmented)
        .settingsControl(title: l10n.card.sizeRow)
    }

    private var accountRow: some View {
        Picker(selection: Binding(
            get: { AccountChoice(settings.accountSelection) },
            set: { choice in apply { $0.accountSelection = choice.selection } }
        )) {
            Text(l10n.card.accountAuto).tag(AccountChoice.mostUrgent)
            ForEach(store.settings.accounts) { account in
                Text(account.label.value).tag(AccountChoice.fixed(account.id))
            }
        } label: {
            SettingsRowLabel(title: l10n.card.accountRow, systemImage: "person.crop.circle", tint: .teal)
        }
        .pickerStyle(.menu)
        .settingsControl(title: l10n.card.accountRow)
    }

    private var thirdTileRow: some View {
        Picker(selection: binding(\.thirdTile)) {
            ForEach(CardThirdTile.allCases) { tile in
                Text(CardMenuPlan.title(tile, l10n: l10n)).tag(tile)
            }
        } label: {
            SettingsRowLabel(title: l10n.card.thirdTileRow, systemImage: "square.grid.3x1.below.line.grid.1x2", tint: .orange)
        }
        .pickerStyle(.menu)
        .settingsControl(title: l10n.card.thirdTileRow)
    }

    /// Which accounts the strip covers. Takes the third tile's place: the strip has chips, not tiles.
    private var scopeRow: some View {
        Picker(selection: binding(\.stripScope)) {
            ForEach(CardStripScope.allCases) { scope in
                Text(CardMenuPlan.title(scope, l10n: l10n)).tag(scope)
            }
        } label: {
            SettingsRowLabel(
                title: l10n.card.scopeRow,
                subtitle: l10n.card.scopeCaption,
                systemImage: "person.2.crop.square.stack",
                tint: .orange
            )
        }
        .pickerStyle(.menu)
        .settingsControl(title: l10n.card.scopeRow, subtitle: l10n.card.scopeCaption)
    }

    // MARK: - Behaviour

    private var keepAboveRow: some View {
        Toggle(isOn: binding(\.keepsAboveWindows)) {
            SettingsRowLabel(
                title: l10n.card.keepAboveRow,
                subtitle: l10n.card.keepAboveCaption,
                systemImage: "square.3.layers.3d.top.filled",
                tint: .blue
            )
        }
        .settingsControl(title: l10n.card.keepAboveRow, subtitle: l10n.card.keepAboveCaption)
    }

    /// The card honours the same setting the island does, so it has to be reachable while the card is the selected
    /// style: the island's own row is hidden then.
    private var fullScreenRow: some View {
        Toggle(isOn: Binding(
            get: { store.settings.appearance.hidesInFullScreen },
            set: { value in store.updateSettings { $0.appearance.hidesInFullScreen = value } }
        )) {
            SettingsRowLabel(title: l10n.placement.hideInFullScreen, systemImage: "arrow.up.left.and.arrow.down.right", tint: .gray)
        }
        .settingsControl(title: l10n.placement.hideInFullScreen)
    }

    /// `IslandScale` drives every size on the card, so the slider belongs here as well as on the island's rows.
    private var scaleRow: some View {
        LabeledContent {
            HStack(spacing: 10) {
                Slider(value: Binding(
                    get: { store.settings.appearance.scale.value },
                    set: { value in
                        store.updateSettings { (settings: inout AppSettings) throws(ValidationError) in
                            settings.appearance.scale = try IslandScale((value * 20).rounded() / 20)
                        }
                    }
                ), in: IslandScale.allowedRange)
                .accessibilityLabel(l10n.card.textSizeRow)
                .accessibilityValue(l10n.format.percent(store.settings.appearance.scale.value * 100))
                Text(l10n.format.percentCompact(store.settings.appearance.scale.value * 100))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .frame(width: PlacementPane.scaleValueWidth, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        } label: {
            SettingsRowLabel(title: l10n.card.textSizeRow, systemImage: "plus.magnifyingglass", tint: .teal)
        }
    }

    private var snapRow: some View {
        Toggle(isOn: Binding(
            get: { store.settings.appearance.snapsWhileDragging },
            set: { value in store.updateSettings { $0.appearance.snapsWhileDragging = value } }
        )) {
            SettingsRowLabel(title: l10n.card.snapRow, systemImage: "dot.magnifyingglass", tint: .green)
        }
        .settingsControl(title: l10n.card.snapRow, subtitle: l10n.card.snapCaption)
    }

    private var displayRow: some View {
        Picker(selection: Binding(
            get: { DisplayChoice(settings.displayPolicy) },
            set: { choice in apply { $0.displayPolicy = choice.policy } }
        )) {
            Text(l10n.card.displayWhereLeft).tag(DisplayChoice.whereLeft)
            Text(l10n.card.displayMain).tag(DisplayChoice.main)
            ForEach(store.displays) { display in
                Text(display.name.isEmpty ? display.id.rawValue : display.name).tag(DisplayChoice.display(display.id))
            }
        } label: {
            SettingsRowLabel(title: l10n.card.showOn, systemImage: "display", tint: .cyan)
        }
        .pickerStyle(.menu)
        .settingsControl(title: l10n.card.showOn)
    }

    private var resetRow: some View {
        HStack {
            SettingsRowLabel(
                title: l10n.card.positionRow,
                subtitle: l10n.card.resetPositionCaption,
                systemImage: "arrow.counterclockwise",
                tint: .gray
            )
            Spacer(minLength: 12)
            Button(l10n.card.resetPosition) {
                store.actions.resetCardPosition()
            }
        }
    }

    // MARK: - Bindings

    private func binding<Value>(_ keyPath: WritableKeyPath<FloatingCardSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { value in apply { $0[keyPath: keyPath] = value } }
        )
    }

    private func apply(_ change: (inout FloatingCardSettings) -> Void) {
        store.updateSettings { change(&$0.appearance.floatingCard) }
    }

    /// The account picker's tag type: `CardAccountSelection` is not `Identifiable` and carries an id.
    private enum AccountChoice: Hashable {
        case mostUrgent
        case fixed(AccountID)

        init(_ selection: CardAccountSelection) {
            switch selection {
            case .mostUrgent: self = .mostUrgent
            case .fixed(let id): self = .fixed(id)
            }
        }

        var selection: CardAccountSelection {
            switch self {
            case .mostUrgent: .mostUrgent
            case .fixed(let id): .fixed(id)
            }
        }
    }

    /// The same for the display policy.
    private enum DisplayChoice: Hashable {
        case whereLeft
        case main
        case display(DisplayID)

        init(_ policy: DisplayPolicy) {
            switch policy {
            case .whereLeft: self = .whereLeft
            case .main: self = .main
            case .display(let id): self = .display(id)
            }
        }

        var policy: DisplayPolicy {
            switch self {
            case .whereLeft: .whereLeft
            case .main: .main
            case .display(let id): .display(id)
            }
        }
    }
}
