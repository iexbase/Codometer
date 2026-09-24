import CodometerCore
import CodometerL10n
import SwiftUI

/// The card's account controls: the chip in the header that opens the account menu, and the page dots in the footer.
///
/// Both are drawn even for a single account's chip, so the header never changes height when an account is added; the
/// dots appear only when there is more than one account, in a row whose height is reserved either way.
struct CardAccountChip: View {
    let style: AccountStyle
    let provider: ProviderKind
    let label: String
    let plan: String?
    let hasMenu: Bool
    let onOpenMenu: () -> Void

    @Environment(\.l10n) private var l10n
    @Environment(\.cardTheme) private var theme
    @Environment(\.cardMetrics) private var metrics

    var body: some View {
        let content = HStack(spacing: 6) {
            AccountBadge(style: style, provider: provider, size: metrics.badge)
            Text(label)
                .font(metrics.font(.header))
                .foregroundStyle(theme.primaryTextColor)
                .lineLimit(1)
                .truncationMode(.tail)
            if let plan {
                Text(plan)
                    .font(metrics.font(.plan))
                    .foregroundStyle(theme.secondaryTextColor)
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(theme.hairlineColor.opacity(0.35))
                    )
                    .layoutPriority(-1)
            }
        }
        .frame(minHeight: 24, alignment: .leading)

        if hasMenu {
            Button(action: onOpenMenu) {
                content.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityValue(plan ?? "")
            .accessibilityHint(l10n.card.switchAccountHint)
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityValue(plan ?? "")
        }
    }
}

/// One dot per account; the current one is filled, and a manual choice that has not expired is drawn hollow.
struct CardPageDots: View {
    let accounts: [AccountPresentation]
    let selected: AccountID?
    /// The user picked this account by hand, so the card is not following the most urgent one right now.
    let isPinned: Bool
    let onSelect: (AccountID) -> Void

    @Environment(\.l10n) private var l10n
    @Environment(\.cardTheme) private var theme
    @Environment(\.cardMetrics) private var metrics

    var body: some View {
        HStack(spacing: metrics.pageDot) {
            ForEach(accounts) { account in
                let isCurrent = account.id == selected
                Button {
                    onSelect(account.id)
                } label: {
                    Group {
                        if isCurrent, isPinned {
                            Circle().strokeBorder(theme.primaryTextColor.opacity(0.85), lineWidth: 1.5)
                        } else {
                            Circle().fill(theme.primaryTextColor.opacity(isCurrent ? 0.85 : 0.3))
                        }
                    }
                    .frame(width: metrics.pageDot, height: metrics.pageDot)
                    // A dot is tiny; its hit target is not.
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(account.status.profile.label.value)
                .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(l10n.card.pages)
        .opacity(accounts.count > 1 ? 1 : 0)
        .accessibilityHidden(accounts.count <= 1)
    }
}

/// The strip's header when it merges several accounts: the provider's glyph (or both) and the scope's name.
struct CardScopeChip: View {
    let header: CardStripPlan.Header

    @Environment(\.cardTheme) private var theme
    @Environment(\.cardMetrics) private var metrics

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: -metrics.badge * 0.25) {
                ForEach(header.provider.map { [$0] } ?? ProviderKind.allCases) { provider in
                    ProviderGlyph(provider: provider, tinted: true)
                        .frame(width: metrics.badge * 0.7, height: metrics.badge * 0.7)
                        .padding(metrics.badge * 0.15)
                        .background(
                            RoundedRectangle(cornerRadius: metrics.badge * 0.3, style: .continuous)
                                .fill(theme.tileFillColor)
                        )
                }
            }
            Text(header.title)
                .font(metrics.font(.header))
                .foregroundStyle(theme.primaryTextColor)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(minHeight: 24, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(header.title)
    }
}
