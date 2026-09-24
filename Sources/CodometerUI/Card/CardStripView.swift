import CodometerCore
import CodometerL10n
import SwiftUI

/// The Strip card's body: the hero column on the left and the row of chips on the right.
///
/// Every width here comes from `CardMetrics`: the hero column and each chip are fixed, so a number changing, an
/// account joining the scope or the language switching never moves anything. Chips beyond the row's capacity are
/// already folded into `plan.more` by `CardStripPlan`.
struct CardStripBody: View {
    let plan: CardStripPlan

    @Environment(\.l10n) private var l10n
    @Environment(\.cardTheme) private var theme
    @Environment(\.cardMetrics) private var metrics

    var body: some View {
        HStack(alignment: .center, spacing: metrics.stripGap) {
            CardStripHero(hero: plan.hero)
                .frame(width: metrics.stripHeroWidth, alignment: .leading)
            HStack(spacing: metrics.chipSpacing) {
                ForEach(plan.chips) { chip in
                    CardStripChip(chip: chip, showsProvider: plan.showsProviders)
                }
                if let text = plan.moreText, let speech = plan.moreAccessibilityText {
                    CardStripMoreChip(text: text, accessibilityText: speech)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: metrics.innerWidth(.strip), height: metrics.stripBodyHeight, alignment: .leading)
    }
}

/// The caption, the big "left" figure and the used line, stacked.
struct CardStripHero: View {
    let hero: CardStripPlan.Hero?

    @Environment(\.l10n) private var l10n
    @Environment(\.cardTheme) private var theme
    @Environment(\.cardMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(hero?.caption ?? l10n.common.noData)
                .font(metrics.font(.footer))
                .foregroundStyle(theme.secondaryTextColor)
                .lineLimit(1)
                .truncationMode(.tail)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(hero?.remainingFigure ?? l10n.card.noValue)
                    .font(metrics.font(.hero))
                    .foregroundStyle(hero.map { theme.bandTextColor($0.band) } ?? theme.secondaryTextColor)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Text(hero?.unit ?? l10n.card.left)
                    .font(metrics.font(.heroUnit))
                    .foregroundStyle(theme.secondaryTextColor)
                    .lineLimit(1)
            }
            Text(hero?.usedLine ?? l10n.common.noData)
                .font(metrics.font(.footer))
                .foregroundStyle(theme.secondaryTextColor)
                .lineLimit(1)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hero?.accessibilityText ?? l10n.common.noData)
    }
}

/// One limit window: its title, how much is used, when it resets, and how many accounts it stands for.
struct CardStripChip: View {
    let chip: CardStripPlan.Chip
    /// Adds the provider's glyph before the title when the row mixes providers.
    let showsProvider: Bool

    @Environment(\.l10n) private var l10n
    @Environment(\.cardTheme) private var theme
    @Environment(\.cardMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if showsProvider {
                    ProviderGlyph(provider: chip.provider, tinted: true)
                        .frame(width: metrics.textSize(TextSize.badge) * 0.85, height: metrics.textSize(TextSize.badge) * 0.85)
                }
                Text(chip.title)
                    .font(metrics.font(.tileLabel))
                    .foregroundStyle(theme.secondaryTextColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.8)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(chip.percentText)
                    .font(metrics.font(.tileValue))
                    .foregroundStyle(theme.bandTextColor(chip.band))
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Spacer(minLength: 0)
                if chip.accountsCount > 1 {
                    accountsBadge
                }
            }
            Text(chip.resetText ?? l10n.card.noValue)
                .font(metrics.font(.tileLabel))
                .foregroundStyle(theme.secondaryTextColor)
                .lineLimit(1)
                .contentTransition(.numericText())
        }
        .frame(width: metrics.chipContentWidth, alignment: .leading)
        .padding(.horizontal, metrics.chipPadding)
        .frame(width: metrics.chipWidth, height: metrics.chipHeight, alignment: .leading)
        .background(CardChipSurface())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chip.accessibilityText)
    }

    /// "⊞ 2": the accounts folded into this chip.
    private var accountsBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: "square.on.square")
                .font(metrics.font(TextSize.badge, .semibold))
            Text(verbatim: "\(chip.accountsCount)")
                .font(metrics.font(.plan))
        }
        .foregroundStyle(theme.secondaryTextColor)
        .lineLimit(1)
    }
}

/// The last chip when more windows exist than the row fits: "+3".
struct CardStripMoreChip: View {
    let text: String
    let accessibilityText: String

    @Environment(\.cardTheme) private var theme
    @Environment(\.cardMetrics) private var metrics

    var body: some View {
        Text(text)
            .font(metrics.font(.tileValue))
            .foregroundStyle(theme.secondaryTextColor)
            .lineLimit(1)
            .frame(width: metrics.chipWidth, height: metrics.chipHeight)
            .background(CardChipSurface())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
    }
}

/// A chip's ground: the tile fill under a faint diagonal hatch, inside a hairline. Drawn once; nothing here moves.
struct CardChipSurface: View {
    @Environment(\.cardTheme) private var theme
    @Environment(\.cardMetrics) private var metrics

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: metrics.chipCorner, style: .continuous)
        shape
            .fill(theme.tileFillColor)
            .overlay(CardHatch(spacing: 7 * metrics.layoutScale).clipShape(shape))
            .overlay(shape.strokeBorder(theme.hairlineColor.opacity(0.5), lineWidth: theme.hairlineWidth * 0.5))
    }
}

/// Faint diagonal hairlines, the texture the chips and nothing else carry.
struct CardHatch: View {
    let spacing: CGFloat

    @Environment(\.cardTheme) private var theme

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            var path = Path()
            let step = max(3, spacing)
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += step
            }
            context.stroke(path, with: .color(theme.primaryTextColor.opacity(theme.isDark ? 0.045 : 0.06)), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
