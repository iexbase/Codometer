import CodometerCore
import CodometerL10n
import SwiftUI

/// The three tiles under the card's hero: when the limit resets, what the current pace means, and whichever third
/// tile the user chose.
///
/// Each tile is a fixed third of the row, and its value line reserves the width of the hidden template, so numbers
/// changing never move anything.
struct CardTilesView: View {
    let tiles: [CardContentPlan.Tile]
    let size: CardSize

    @Environment(\.cardTheme) private var theme
    @Environment(\.cardMetrics) private var metrics

    var body: some View {
        HStack(spacing: metrics.tileSpacing) {
            ForEach(tiles) { tile in
                // A fixed width per tile: a long value can never push its neighbours out of the card.
                CardTileView(tile: tile).frame(width: metrics.tileWidth(size))
            }
        }
        .frame(width: metrics.innerWidth(size), alignment: .leading)
    }
}

struct CardTileView: View {
    let tile: CardContentPlan.Tile

    @Environment(\.cardTheme) private var theme
    @Environment(\.cardMetrics) private var metrics

    var body: some View {
        // The value takes the whole first line; the icon sits with the label, so a narrow tile never has to shrink
        // the number to make room for a glyph.
        VStack(alignment: .leading, spacing: 2) {
            Text(tile.value)
                .font(metrics.font(.tileValue))
                .foregroundStyle(theme.color(for: tile.tone))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .contentTransition(.numericText())
            HStack(spacing: 4) {
                Image(systemName: tile.systemImage)
                    .font(metrics.font(.tileLabel))
                    .foregroundStyle(theme.secondaryTextColor)
                    .accessibilityHidden(true)
                Text(tile.label)
                    .font(metrics.font(.tileLabel))
                    .foregroundStyle(theme.secondaryTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .padding(.horizontal, metrics.tilePadding)
        .padding(.vertical, metrics.tilePadding * 0.75)
        .background(RoundedRectangle(cornerRadius: metrics.tileCorner, style: .continuous).fill(theme.tileFillColor))
        .overlay(
            RoundedRectangle(cornerRadius: metrics.tileCorner, style: .continuous)
                .strokeBorder(theme.hairlineColor.opacity(0.5), lineWidth: theme.hairlineWidth * 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.accessibilityText)
        .accessibilityValue(tile.label)
    }
}
