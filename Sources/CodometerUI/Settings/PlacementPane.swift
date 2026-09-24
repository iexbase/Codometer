import CodometerCore
import CodometerL10n
import SwiftUI

/// Settings → Presentation: which surface shows usage, where it sits, what opens it, and what it looks like.
///
/// The style picker at the top chooses between the island and the floating card; below it the pane shows the island's
/// rows or the card's, so neither surface's settings are duplicated or missing. The Behavior section at the bottom
/// holds what both surfaces share (visibility, snapping, haptics) and is built from `behaviorRows(for:)`, so a row
/// cannot go missing for one of the two styles.
struct PlacementPane: View {
    let store: TrackerStore
    @Binding var stageOptions: IslandStageOptions

    @State private var issue: String?
    @Environment(\.l10n) private var l10n

    private var appearance: AppearanceSettings { store.settings.appearance }

    private var isIsland: Bool { appearance.presentationStyle == .island }

    var body: some View {
        Form {
            Section {
                PaneHeader(
                    title: l10n.settingsPanes.presentation,
                    subtitle: isIsland ? l10n.placement.paneSubtitle : l10n.placement.cardPaneSubtitle,
                    systemImage: "rectangle.dashed",
                    tint: .purple
                )
                if let issue {
                    SettingsIssueBanner(message: issue) { self.issue = nil }
                }
            }

            Section {
                stylePicker
            } header: {
                Text(l10n.presentationStyle.showUsageAs)
            } footer: {
                SectionNote(l10n.presentationStyle.footnote)
            }

            Section {
                stage
                    .listRowInsets(EdgeInsets())
                if isIsland {
                    edgeButtons
                }
            }

            if isIsland {
                islandInteraction
                islandShape
            } else {
                CardSettingsSection(store: store)
            }

            Section(l10n.placement.behaviorTitle) {
                ForEach(Self.behaviorRows(for: appearance.presentationStyle)) { row in
                    behaviorToggle(row)
                }
            }
        }
        .formStyle(.grouped)
        .animation(Motion.content, value: issue)
        .animation(Motion.content, value: appearance.presentationStyle)
    }

    // MARK: - Behavior

    /// A switch in the Behavior section. The section is built from this list rather than from a chain of `if`s, so a
    /// row can no longer go missing for one style the way "Show the card" did.
    enum BehaviorRow: String, CaseIterable, Identifiable {
        /// Show the island / Show the card. One `AppearanceSettings.visibility` hides whichever surface is chosen, so
        /// the row belongs to both styles and only renames itself; without it the card could be switched off from the
        /// menu bar item and never switched back on here.
        case visibility
        /// Island only: the card offers the same setting in `CardSettingsSection`, next to its own rows.
        case hideInFullScreen
        /// Dragging behaves the same whichever surface is on screen, so these two never move.
        case snapping
        case haptics

        var id: String { rawValue }
    }

    static func behaviorRows(for style: PresentationStyle) -> [BehaviorRow] {
        BehaviorRow.allCases.filter { $0 != .hideInFullScreen || style == .island }
    }

    static func title(_ row: BehaviorRow, style: PresentationStyle, l10n: Localizer) -> String {
        switch row {
        case .visibility: style == .island ? l10n.placement.showIsland : l10n.placement.showCard
        case .hideInFullScreen: l10n.placement.hideInFullScreen
        case .snapping: l10n.snapping.snapWhileDragging
        case .haptics: l10n.snapping.haptics
        }
    }

    /// The line under a row's title, where it has one.
    static func subtitle(_ row: BehaviorRow, l10n: Localizer) -> String? {
        switch row {
        case .visibility: l10n.placement.showIslandSubtitle
        case .hideInFullScreen: nil
        case .snapping: l10n.snapping.snapCaption
        case .haptics: l10n.snapping.hapticsCaption
        }
    }

    /// The row's symbol. Only the visibility row changes with the style, to the mark its own style tile carries.
    static func systemImage(_ row: BehaviorRow, style: PresentationStyle) -> String {
        switch row {
        case .visibility: style == .island ? "capsule.fill" : "rectangle.on.rectangle"
        case .hideInFullScreen: "arrow.up.left.and.arrow.down.right"
        case .snapping: "dot.scope"
        case .haptics: "hand.tap.fill"
        }
    }

    private func behaviorToggle(_ row: BehaviorRow) -> some View {
        let style = appearance.presentationStyle
        let title = Self.title(row, style: style, l10n: l10n)
        let subtitle = Self.subtitle(row, l10n: l10n)
        return Toggle(isOn: binding(for: row)) {
            SettingsRowLabel(
                title: title,
                subtitle: subtitle,
                systemImage: Self.systemImage(row, style: style),
                tint: Self.tint(row)
            )
        }
        .settingsControl(title: title, subtitle: subtitle)
    }

    private static func tint(_ row: BehaviorRow) -> Color {
        switch row {
        case .visibility: .blue
        case .hideInFullScreen: .gray
        case .snapping: .pink
        case .haptics: .orange
        }
    }

    private func binding(for row: BehaviorRow) -> Binding<Bool> {
        switch row {
        case .visibility:
            Binding(
                get: { appearance.visibility == .always },
                set: { isOn in apply { $0.appearance.visibility = isOn ? .always : .hidden } }
            )
        case .hideInFullScreen:
            Binding(
                get: { appearance.hidesInFullScreen },
                set: { isOn in apply { $0.appearance.hidesInFullScreen = isOn } }
            )
        case .snapping:
            Binding(
                get: { appearance.snapsWhileDragging },
                set: { isOn in apply { $0.appearance.snapsWhileDragging = isOn } }
            )
        case .haptics:
            Binding(
                get: { appearance.playsHaptics },
                set: { isOn in apply { $0.appearance.playsHaptics = isOn } }
            )
        }
    }

    // MARK: - Style

    /// What the three tiles offer. The strip is the floating card in its wide size, offered on its own because it is
    /// a different way to look at the limits, not a detail of the card.
    enum StyleChoice: Equatable {
        case island
        case card
        case strip

        static func current(_ appearance: AppearanceSettings) -> StyleChoice {
            switch appearance.presentationStyle {
            case .island: .island
            case .floatingCard: appearance.floatingCard.size == .strip ? .strip : .card
            }
        }
    }

    /// Three tiles, one per way of showing usage.
    private var stylePicker: some View {
        HStack(alignment: .top, spacing: 10) {
            styleTile(
                .island,
                title: l10n.presentationStyle.island,
                description: l10n.presentationStyle.islandDescription,
                a11y: l10n.presentationStyle.islandA11y,
                systemImage: "capsule.portrait.fill"
            )
            styleTile(
                .card,
                title: l10n.presentationStyle.floatingCard,
                description: l10n.presentationStyle.floatingCardDescription,
                a11y: l10n.presentationStyle.floatingCardA11y,
                systemImage: "rectangle.on.rectangle"
            )
            styleTile(
                .strip,
                title: l10n.presentationStyle.strip,
                description: l10n.presentationStyle.stripDescription,
                a11y: l10n.presentationStyle.stripA11y,
                systemImage: "rectangle.split.3x1"
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func choose(_ choice: StyleChoice) {
        switch choice {
        case .island:
            store.actions.switchPresentationStyle(.island)
        case .card:
            if appearance.floatingCard.size == .strip {
                apply { $0.appearance.floatingCard.size = .regular }
            }
            store.actions.switchPresentationStyle(.floatingCard)
        case .strip:
            apply { $0.appearance.floatingCard.size = .strip }
            store.actions.switchPresentationStyle(.floatingCard)
        }
    }

    private func styleTile(
        _ choice: StyleChoice,
        title: String,
        description: String,
        a11y: String,
        systemImage: String
    ) -> some View {
        let isSelected = StyleChoice.current(appearance) == choice
        return Button {
            guard !isSelected else { return }
            choose(choice)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .labelStyle(.titleAndIcon)
                // Every description reserves three lines, so switching never changes the pane's height.
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3, reservesSpace: true)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Theme.selectionFill : Theme.cardFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor.opacity(0.8) : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
                }
        }
        .accessibilityLabel(a11y)
        .accessibilityHint(description)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// The preview of the selected surface; both stages get the same room, so switching never resizes the pane.
    @ViewBuilder
    private var stage: some View {
        if isIsland {
            IslandStage(store: store, options: $stageOptions)
        } else {
            CardStage(store: store)
                .frame(height: IslandStage.displayHeight)
        }
    }

    // MARK: - Island sections

    private var islandInteraction: some View {
        Section {
            Picker(selection: Binding(
                get: { appearance.openTrigger },
                set: { trigger in apply { $0.appearance.openTrigger = trigger } }
            )) {
                ForEach(IslandOpenTrigger.allCases) { trigger in
                    Text(Self.title(trigger, l10n: l10n)).tag(trigger)
                }
            } label: {
                SettingsRowLabel(title: l10n.placement.expandOn, systemImage: "hand.point.up.left.fill", tint: .indigo)
            }
            .pickerStyle(.segmented)
            .settingsControl(title: l10n.placement.expandOn)
            Text(Self.explanation(appearance.openTrigger, l10n: l10n))
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
                .contentTransition(.opacity)
                .animation(Motion.content, value: appearance.openTrigger)
            if showsDisplayPicker {
                displayPicker
            }
        } header: {
            Text(l10n.placement.interactionTitle)
        } footer: {
            SectionNote(l10n.placement.interactionFooter)
        }
    }

    private var islandShape: some View {
        Section(l10n.placement.shapeTitle) {
            Picker(selection: Binding(
                get: { appearance.style },
                set: { style in apply { $0.appearance.style = style } }
            )) {
                Text(l10n.placement.attached).tag(IslandStyle.attached)
                Text(l10n.placement.floating).tag(IslandStyle.floating)
            } label: {
                SettingsRowLabel(title: l10n.placement.style, systemImage: "square.topthird.inset.filled", tint: .purple)
            }
            .pickerStyle(.segmented)
            .settingsControl(title: l10n.placement.style)
            Picker(selection: Binding(
                get: { appearance.surface },
                set: { surface in apply { $0.appearance.surface = surface } }
            )) {
                Text(l10n.placement.liquidGlass).tag(IslandSurface.glass)
                Text(l10n.placement.darkGlass).tag(IslandSurface.darkGlass)
                Text(l10n.placement.black).tag(IslandSurface.solid)
            } label: {
                SettingsRowLabel(title: l10n.placement.surface, systemImage: "drop.fill", tint: .cyan)
            }
            .pickerStyle(.segmented)
            .settingsControl(title: l10n.placement.surface)
            if showsNotchToggle {
                Toggle(isOn: Binding(
                    get: { appearance.notchFusion == .automatic },
                    set: { isOn in apply { $0.appearance.notchFusion = isOn ? .automatic : .off } }
                )) {
                    SettingsRowLabel(title: l10n.notch.blendWithNotch, subtitle: l10n.notch.blendCaption, systemImage: "macbook", tint: .indigo)
                }
                .settingsControl(title: l10n.notch.blendWithNotch, subtitle: l10n.notch.blendCaption)
            }
            LabeledContent {
                HStack(spacing: 10) {
                    Slider(value: Binding(
                        get: { appearance.scale.value },
                        set: { value in
                            apply { (settings: inout AppSettings) throws(ValidationError) in
                                settings.appearance.scale = try IslandScale((value * 20).rounded() / 20)
                            }
                        }
                    ), in: IslandScale.allowedRange)
                    .accessibilityLabel(l10n.placement.size)
                    .accessibilityValue(l10n.format.percent(appearance.scale.value * 100))
                    Text(l10n.format.percentCompact(appearance.scale.value * 100))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .frame(width: Self.scaleValueWidth, alignment: .trailing)
                        .accessibilityHidden(true)
                }
            } label: {
                SettingsRowLabel(title: l10n.placement.size, systemImage: "plus.magnifyingglass", tint: .teal)
            }
        }
    }

    // MARK: - Displays

    /// Shown with more than one display connected, or when a specific one is saved (so it can be changed back).
    private var showsDisplayPicker: Bool {
        Self.showsDisplayPicker(displays: store.displays, policy: appearance.islandDisplayPolicy, remembered: appearance.islandDisplay)
    }

    nonisolated static func showsDisplayPicker(
        displays: [DisplayDescriptor],
        policy: DisplayPolicy,
        remembered: RememberedDisplay?
    ) -> Bool {
        if displays.count > 1 { return true }
        if case .display = policy { return true }
        return remembered != nil && displays.count == 1 && displays.first?.id != remembered?.id
    }

    private var displayPicker: some View {
        Picker(selection: Binding(
            get: { Self.selection(policy: appearance.islandDisplayPolicy) },
            set: { choice in
                apply { settings in
                    switch choice {
                    case .whereLeft: settings.appearance.islandDisplayPolicy = .whereLeft
                    case .main: settings.appearance.islandDisplayPolicy = .main
                    case .display(let id): settings.appearance.islandDisplayPolicy = .display(id)
                    }
                }
            }
        )) {
            Text(l10n.displays.whereLeft).tag(DisplayChoice.whereLeft)
            Text(l10n.displays.mainDisplay).tag(DisplayChoice.main)
            ForEach(Self.displayOptions(displays: store.displays, policy: appearance.islandDisplayPolicy, remembered: appearance.islandDisplay, l10n: l10n), id: \.id) { option in
                Text(option.title).tag(DisplayChoice.display(option.id))
            }
        } label: {
            SettingsRowLabel(title: l10n.displays.display, subtitle: l10n.displays.displayCaption, systemImage: "display.2", tint: .blue)
        }
        .settingsControl(title: l10n.displays.display, subtitle: l10n.displays.displayCaption)
    }

    /// What the picker offers besides "Where I leave it" and "Main display": every connected display, plus the saved
    /// one when it is not plugged in (so the choice can be seen and changed).
    nonisolated static func displayOptions(
        displays: [DisplayDescriptor],
        policy: DisplayPolicy,
        remembered: RememberedDisplay?,
        l10n: Localizer
    ) -> [(id: DisplayID, title: String)] {
        var options = displays.map { display in
            (id: display.id, title: display.name.isEmpty ? l10n.displays.unnamedDisplay : display.name)
        }
        let pinned: DisplayID? = if case .display(let id) = policy { id } else { nil }
        if let pinned, !displays.contains(where: { $0.id == pinned }) {
            let name = remembered?.id == pinned ? remembered?.name : nil
            options.append((id: pinned, title: l10n.displays.notConnected(name ?? l10n.displays.unnamedDisplay)))
        }
        return options
    }

    /// The picker's selection tag, which never carries a `RememberedDisplay`.
    enum DisplayChoice: Hashable {
        case whereLeft
        case main
        case display(DisplayID)
    }

    nonisolated static func selection(policy: DisplayPolicy) -> DisplayChoice {
        switch policy {
        case .whereLeft: .whereLeft
        case .main: .main
        case .display(let id): .display(id)
        }
    }

    /// Whether the notch toggle is worth showing: only when a connected display actually has a camera notch.
    private var showsNotchToggle: Bool {
        store.displays.contains { $0.notch != nil }
    }

    // MARK: - Edges

    private var edgeButtons: some View {
        HStack(spacing: 8) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(ScreenEdge.allCases) { edge in
                        Button {
                            apply { settings in
                                settings.appearance.edge = edge
                                settings.appearance.offset = .center
                            }
                        } label: {
                            Label(edge.title(l10n), systemImage: edge.systemImage)
                        }
                        .buttonStyle(AnyPrimitiveButtonStyle.glass(selected: appearance.edge == edge))
                        .accessibilityLabel(edge.moveA11y(l10n))
                        .accessibilityAddTraits(appearance.edge == edge ? .isSelected : [])
                    }
                }
            }
            Spacer(minLength: 8)
            Button(l10n.placement.center) {
                apply { $0.appearance.offset = .center }
            }
            .buttonStyle(.glass)
            .disabled(appearance.offset == .center)
            .accessibilityHint(l10n.placement.centerHint)
        }
    }

    /// Width of the size value next to its slider; the largest scale must fit (`SettingsPanesCopyTests`).
    static let scaleValueWidth: CGFloat = 46

    static func title(_ trigger: IslandOpenTrigger, l10n: Localizer) -> String {
        switch trigger {
        case .hover: l10n.placement.hover
        case .click: l10n.placement.click
        case .hoverOrClick: l10n.placement.hoverOrClick
        }
    }

    /// The line under the trigger picker, which has room for two lines.
    static func explanation(_ trigger: IslandOpenTrigger, l10n: Localizer) -> String {
        switch trigger {
        case .hover: l10n.placement.hoverExplanation
        case .click: l10n.placement.clickExplanation
        case .hoverOrClick: l10n.placement.hoverOrClickExplanation
        }
    }

    private func apply(_ change: (inout AppSettings) throws(ValidationError) -> Void) {
        issue = store.updateSettings(change).map { SettingsCopy.settingsMessage(for: $0, l10n: l10n) }
    }
}
