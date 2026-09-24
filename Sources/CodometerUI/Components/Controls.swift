import SwiftUI

extension EnvironmentValues {
    /// Whether Liquid Glass renders in this context. Off in offscreen renders (`ImageRenderer` draws no glass),
    /// where controls fall back to a material.
    @Entry var rendersGlass = true
}

/// A round Liquid Glass icon button for the deck header.
struct GlassIconButton: View {
    let systemImage: String
    let help: String
    var isBusy = false
    let metrics: IslandMetrics
    let action: () -> Void

    @Environment(\.rendersGlass) private var rendersGlass
    @State private var taps = 0

    var body: some View {
        let side = metrics.headerButton
        // The small glass button style adds this much around its label.
        let glassInset: CGFloat = 6
        let icon = Image(systemName: systemImage)
            .font(metrics.font(TextSize.body, .semibold))
            .symbolEffect(.rotate.byLayer, options: .nonRepeating, value: taps)
            .opacity(isBusy ? 0.45 : 1)
        Group {
            if rendersGlass {
                Button {
                    taps += 1
                    action()
                } label: {
                    icon.frame(width: side - glassInset, height: side - glassInset)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
            } else {
                Button(action: action) {
                    icon.frame(width: side, height: side).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .background(Circle().fill(.thinMaterial))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            }
        }
        .frame(width: side, height: side)
        .controlSize(.small)
        .disabled(isBusy)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// A compact capsule segmented control that fits inside glass without another glass layer.
/// Every segment uses the same weight, so selecting one never shifts its neighbours.
struct CapsuleSegmentedControl<ID: Hashable>: View {
    let options: [(id: ID, title: String)]
    let selection: ID
    let metrics: IslandMetrics
    let onSelect: (ID) -> Void

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2 * metrics.scale) {
            ForEach(options, id: \.id) { option in
                let isSelected = option.id == selection
                Button {
                    guard !isSelected else { return }
                    // A selection may change what the island shows, so it animates like geometry: no overshoot.
                    withAnimation(Motion.geometry) { onSelect(option.id) }
                } label: {
                    Text(option.title)
                        .font(metrics.font(TextSize.footnote, .medium))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 10 * metrics.scale)
                        .padding(.vertical, 4 * metrics.scale)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Theme.selectionFill)
                                    .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.5))
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2 * metrics.scale)
        .background(Capsule().fill(Theme.cardFill))
    }
}

/// Text that reserves the width of a template, so a changing value (a clock, a countdown) never moves
/// the views next to it. Set the font on this view, not on the text.
struct ReservedWidthText: View {
    let text: String
    let template: String
    var alignment: Alignment = .trailing

    var body: some View {
        Text(template)
            .lineLimit(1)
            .hidden()
            .overlay(alignment: alignment) {
                Text(text)
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
    }
}

/// A one-pixel divider.
struct Hairline: View {
    @Environment(\.pixelLength) private var pixelLength

    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: max(pixelLength, 0.5))
            .accessibilityHidden(true)
    }
}

/// A small caption above a group of cards.
struct SectionTitle<Accessory: View>: View {
    let title: String
    let metrics: IslandMetrics
    let accessory: Accessory

    init(_ title: String, metrics: IslandMetrics, @ViewBuilder accessory: () -> Accessory = { EmptyView() }) {
        self.title = title
        self.metrics = metrics
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 6 * metrics.scale) {
            Text(title)
                .font(metrics.font(TextSize.footnote, .semibold))
                .foregroundStyle(.secondary)
            accessory
            Spacer(minLength: 0)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// A capsule label such as the plan name, tinted with an identity colour.
struct TagChip: View {
    let text: String
    let tint: Color
    let metrics: IslandMetrics

    var body: some View {
        Text(text)
            .font(metrics.font(TextSize.badge, .semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 7 * metrics.scale)
            .padding(.vertical, 2 * metrics.scale)
            .background(Capsule().fill(tint.opacity(0.14)))
    }
}
