import CodometerCore
import CodometerL10n
import SwiftUI

/// The one thing the card says about itself when something is off: agents waiting, a vendor outage, a limit reached, a
/// limit that just reset, or data that has gone stale. Quiet when everything is fine.
///
/// The slot is always as wide as the widest phrase in the current language, so a pill appearing or changing never
/// moves the header. Only a vendor pill takes a click, which opens that vendor's public status page.
struct CardStatusPill: View {
    let pill: CardContentPlan.StatusPill?
    /// Compact cards have no room for words: they show the colour plus a VoiceOver label.
    var showsText = true
    let onOpenStatusPage: (ProviderKind) -> Void

    @Environment(\.l10n) private var l10n
    @Environment(\.cardTheme) private var theme
    @Environment(\.cardMetrics) private var metrics

    var body: some View {
        Group {
            if showsText {
                textPill
            } else {
                dot
            }
        }
        .animation(Motion.quickFade, value: pill?.text)
    }

    private var slotWidth: CGFloat {
        metrics.width(of: l10n.card.pillTemplate, role: .pill) + metrics.tilePadding * 2 + 2
    }

    @ViewBuilder
    private var textPill: some View {
        let content = Group {
            if let pill {
                Text(pill.text)
                    .font(metrics.font(.pill))
                    .foregroundStyle(theme.color(for: pill.tone))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.horizontal, metrics.tilePadding)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(theme.color(for: pill.tone).opacity(theme.isDark ? 0.18 : 0.14))
                    )
                    .overlay(
                        Capsule().strokeBorder(theme.color(for: pill.tone).opacity(0.35), lineWidth: theme.hairlineWidth * 0.5)
                    )
            } else {
                Color.clear
            }
        }
        // The slot is reserved at the widest phrase, so the header never re-lays out when the pill changes.
        .frame(width: slotWidth, alignment: .trailing)
        .frame(height: metrics.badge)

        if let pill, let provider = pill.statusPageProvider {
            Button {
                onOpenStatusPage(provider)
            } label: {
                content.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(minHeight: 24)
            .help(pill.tooltip)
            .accessibilityLabel(pill.text)
            .accessibilityValue(pill.tooltip)
            .accessibilityHint(l10n.card.openStatusPage)
        } else {
            content
                .help(pill?.tooltip ?? "")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(pill?.text ?? "")
                .accessibilityValue(pill?.tooltip ?? "")
                .accessibilityHidden(pill == nil)
        }
    }

    private var dot: some View {
        Circle()
            .fill(pill.map { theme.color(for: $0.tone) } ?? .clear)
            .frame(width: metrics.pageDot * 1.6, height: metrics.pageDot * 1.6)
            .help(pill?.tooltip ?? "")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(pill?.text ?? "")
            .accessibilityValue(pill?.tooltip ?? "")
            .accessibilityHidden(pill == nil)
    }
}
