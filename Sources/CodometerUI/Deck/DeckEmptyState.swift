import CodometerL10n
import SwiftUI

/// A calm placeholder where the accounts would be: a glyph, what is missing and what to do about it.
///
/// For an empty group it fills the room the deck reserves for the accounts (`fillsRoom`) and floats, unboxed, at the
/// room's optical centre (`OpticalCenterLayout`), so it never sizes the deck; with no accounts at all it is a card in the
/// flow at its own height.
struct DeckEmptyStateView: View {
    let state: DeckSections.EmptyState
    let metrics: IslandMetrics
    let fillsRoom: Bool
    let onShowAll: () -> Void
    let onOpenSettings: () -> Void
    @Environment(\.l10n) private var l10n

    var body: some View {
        if fillsRoom {
            OpticalCenterLayout {
                content
            }
        } else {
            let shape = RoundedRectangle(cornerRadius: metrics.tileCorner, style: .continuous)
            content
                .background {
                    shape
                        .fill(Theme.cardFill)
                        .overlay(shape.strokeBorder(Theme.hairline, lineWidth: 0.5))
                }
        }
    }

    private var content: some View {
        VStack(spacing: 14 * metrics.scale) {
            glyph
            VStack(spacing: 4 * metrics.scale) {
                Text(state.title(l10n: l10n))
                    .font(metrics.font(TextSize.headline, .semibold))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .accessibilityAddTraits(.isHeader)
                Text(state.message(l10n: l10n))
                    .font(metrics.font(TextSize.callout))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            if state.offersShowAll || state.offersSettings {
                HStack(spacing: 8 * metrics.scale) {
                    if state.offersShowAll {
                        DeckPillButton(title: l10n.emptyState.showAll, systemImage: "square.stack.3d.up", isProminent: true, metrics: metrics, action: onShowAll)
                    }
                    if state.offersSettings {
                        DeckPillButton(title: l10n.emptyState.openSettings, systemImage: "gearshape", isProminent: !state.offersShowAll, metrics: metrics, action: onOpenSettings)
                    }
                }
                .padding(.top, 2 * metrics.scale)
            }
        }
        .padding(.horizontal, 18 * metrics.scale)
        .padding(.vertical, 24 * metrics.scale)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var glyph: some View {
        let side = 54 * metrics.scale
        return Image(systemName: state.systemImage)
            .font(metrics.font(22, .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.secondary)
            .frame(width: side, height: side)
            .background {
                Circle()
                    .fill(Theme.subtleFill)
                    .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 0.5))
            }
            .accessibilityHidden(true)
    }
}

/// A compact capsule button for the deck's empty states. Neutral on purpose: colour on the island means usage
/// (and purple means an agent waits), so the prominent button is only stronger, not tinted.
struct DeckPillButton: View {
    let title: String
    let systemImage: String
    let isProminent: Bool
    let metrics: IslandMetrics
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(CompactLabelStyle(spacing: 5 * metrics.scale))
                .font(metrics.font(TextSize.footnote, .semibold))
                .foregroundStyle(isProminent ? .primary : .secondary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 12 * metrics.scale)
                .padding(.vertical, 6 * metrics.scale)
                .background {
                    Capsule()
                        .fill(Color.primary.opacity(fillOpacity))
                        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: isProminent ? 0.5 : 0))
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if isHovered != hovering {
                isHovered = hovering
            }
        }
        .animation(Motion.snappy, value: isHovered)
    }

    private var fillOpacity: Double {
        switch (isProminent, isHovered) {
        case (true, false): 0.10
        case (true, true): 0.15
        case (false, false): 0.05
        case (false, true): 0.09
        }
    }
}

/// Places its content across the middle of the room it is offered and down by `fraction` of the height left over, so
/// content sits at the room's optical centre (a little above the geometric one) however tall the room is. It takes the
/// whole room; content taller than the room starts at its top.
struct OpticalCenterLayout: Layout {
    /// Where the eye expects the centre of an empty area: 40 % of the free height above the content, 60 % below.
    static let defaultFraction: CGFloat = 0.4

    var fraction: CGFloat = defaultFraction

    /// The content's distance from the top of the room, in whole points.
    nonisolated static func offset(room: CGFloat, content: CGFloat, fraction: CGFloat) -> CGFloat {
        guard room.isFinite, content.isFinite else { return 0 }
        return (max(0, room - content) * min(max(fraction, 0), 1)).rounded()
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let content = subviews.first?.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)) ?? .zero
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? content.width
        let height = proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? content.height
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            let top = Self.offset(room: bounds.height, content: size.height, fraction: fraction)
            subview.place(
                at: CGPoint(x: bounds.midX, y: bounds.minY + top),
                anchor: .top,
                proposal: ProposedViewSize(width: bounds.width, height: size.height)
            )
        }
    }
}
