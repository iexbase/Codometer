import CodometerCore
import CodometerL10n
import SwiftUI

/// One account in the deck's switcher: its rings with the activity orbit, headline value and name.
struct DeckDial: View {
    let presentation: AccountPresentation
    let isSelected: Bool
    let isHovered: Bool
    let isHighlighted: Bool
    let showsInnerRings: Bool
    let now: Date
    let metrics: IslandMetrics
    @Environment(\.l10n) private var l10n
    @Environment(\.ringFlightHiddenAccounts) private var ringFlightHiddenAccounts
    @Environment(\.ceremonyStage) private var ceremonyStage

    static func itemWidth(_ metrics: IslandMetrics) -> CGFloat {
        84 * metrics.scale
    }

    /// The tint dot before a dial's name: enough to tell two accounts of one provider apart at a glance.
    static func identityDotSize(_ metrics: IslandMetrics) -> CGFloat {
        max(4, 6 * metrics.scale)
    }

    var body: some View {
        let caption = DeckLayout.dialCaption(primary: presentation.headline?.primary, blocking: presentation.blockingWindow, now: now, l10n: l10n)
        let band = caption.isCountdown ? UsageBand.exhausted : presentation.primaryBand
        VStack(spacing: 2 * metrics.scale) {
            RingGauge(
                presentation: presentation,
                diameter: metrics.deckDial,
                showsSecondary: showsInnerRings,
                isHighlighted: isHighlighted,
                orbitMargin: metrics.orbitMargin,
                hidesRings: ringFlightHiddenAccounts.contains(presentation.id),
                // A deck dial is large enough to carry every forecast without crowding.
                forecastPolicy: .always,
                ceremonySurface: .deck
            )
            HStack(spacing: 3 * metrics.scale) {
                if caption.isCountdown {
                    Image(systemName: "lock.fill")
                        .font(metrics.font(TextSize.badge, .bold))
                }
                Text(caption.text)
                    .font(metrics.digits(TextSize.dialValue, .bold))
                    .contentTransition(.numericText(value: presentation.headline?.primary.used.value ?? 0))
            }
            .foregroundStyle(presentation.isStale ? AnyShapeStyle(.secondary) : AnyShapeStyle(band.map(Theme.bandText(for:)) ?? .secondary))
            .lineLimit(1)
            // A tight gap: the dot takes room from a name that already truncates in the middle.
            HStack(spacing: 3 * metrics.scale) {
                // Identity, not data: the dot says which account this is, the rings say how much is left.
                AccountBadge.Dot(tint: presentation.style.tint, diameter: Self.identityDotSize(metrics))
                Text(presentation.status.profile.label.value)
                    .font(metrics.font(TextSize.caption, .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 4 * metrics.scale)
        .padding(.top, 4 * metrics.scale)
        .padding(.bottom, 7 * metrics.scale)
        .frame(width: Self.itemWidth(metrics))
        .background {
            RoundedRectangle(cornerRadius: metrics.tileCorner, style: .continuous)
                .fill(isSelected ? Theme.selectionFill : isHovered ? Theme.cardFill : .clear)
        }
        .contentShape(RoundedRectangle(cornerRadius: metrics.tileCorner, style: .continuous))
        .animation(Motion.snappy, value: isSelected)
        .animation(Motion.snappy, value: isHovered)
        // One element per dial, like the rail's: the account's name, then its usage and reset in words.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.status.profile.label.value)
        .accessibilityValue(RailView.dialAccessibilityValue(
            presentation: presentation,
            now: now,
            forecastPolicy: .always,
            celebrates: ceremonyStage.map { $0.surface == .deck && !$0.ceremonies(of: presentation.id).isEmpty } ?? false,
            l10n: l10n
        ))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
