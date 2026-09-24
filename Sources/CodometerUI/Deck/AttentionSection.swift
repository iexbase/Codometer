import CodometerCore
import CodometerL10n
import SwiftUI

/// "Waiting for you": every session blocked on the user, longest wait first, as compact attention-coloured cards.
struct AttentionSection: View {
    let items: [AttentionItem]
    let labels: [AccountID: String]
    let providers: [AccountID: ProviderKind]
    let now: Date
    let metrics: IslandMetrics
    let onSelect: (AccountID) -> Void
    @Environment(\.l10n) private var l10n

    var body: some View {
        let queue = DeckLayout.attention(items)
        VStack(alignment: .leading, spacing: 6 * metrics.scale) {
            SectionTitle(l10n.deck.waitingTitle, metrics: metrics) {
                Text("\(items.count)")
                    .font(metrics.digits(TextSize.badge, .bold))
                    .foregroundStyle(Theme.attentionText)
                    .padding(.horizontal, 6 * metrics.scale)
                    .padding(.vertical, 1 * metrics.scale)
                    .background(Capsule().fill(Theme.attention.opacity(0.16)))
                    .contentTransition(.numericText(value: Double(items.count)))
            }
            .padding(.leading, 4 * metrics.scale)
            ForEach(queue.shown) { item in
                AttentionCard(
                    item: item,
                    accountLabel: labels[item.accountID],
                    provider: providers[item.accountID],
                    now: now,
                    metrics: metrics
                )
                    .onTapGesture { onSelect(item.accountID) }
                    .accessibilityAction { onSelect(item.accountID) }
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
            if queue.hidden > 0 {
                Text(l10n.deck.moreWaiting(queue.hidden))
                    .font(metrics.font(TextSize.caption))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4 * metrics.scale)
            }
        }
    }
}

private struct AttentionCard: View {
    let item: AttentionItem
    let accountLabel: String?
    let provider: ProviderKind?
    let now: Date
    let metrics: IslandMetrics
    @Environment(\.l10n) private var l10n

    var body: some View {
        let session = item.session
        let activity = provider.map { UsageFormat.activity(of: session, provider: $0, now: now, l10n: l10n) }
            ?? UsageFormat.activity(.waiting, detail: session.detail, l10n: l10n)
        HStack(spacing: 10 * metrics.scale) {
            ActivityGlyph(activity: .waiting, size: 24 * metrics.scale)
            VStack(alignment: .leading, spacing: 1 * metrics.scale) {
                Text(session.title)
                    .font(metrics.font(TextSize.body, .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                // The account and what the session needs on one line; when both do not fit, what the session needs
                // wins (VoiceOver still names the account), in shorter words if it has them. One line either way, so
                // the card never changes height.
                ViewThatFits(in: .horizontal) {
                    if let accountLabel {
                        Text(verbatim: "\(accountLabel) · \(activity)")
                    }
                    Text(activity)
                        .truncationMode(.tail)
                    if let compact = DeckLayout.compactStatus(activity, l10n: l10n) {
                        Text(compact)
                            .truncationMode(.tail)
                    }
                }
                .font(metrics.font(TextSize.caption, .medium))
                .foregroundStyle(Theme.attentionText)
                .lineLimit(1)
            }
            Spacer(minLength: 6 * metrics.scale)
            ReservedWidthText(text: UsageFormat.elapsed(since: item.waitingSince, now: now, l10n: l10n), template: DeckLayout.elapsedTemplate(l10n: l10n))
                .font(metrics.digits(TextSize.caption, .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 8 * metrics.scale)
        .padding(.trailing, 12 * metrics.scale)
        .padding(.vertical, 7 * metrics.scale)
        .background {
            RoundedRectangle(cornerRadius: metrics.cardCorner, style: .continuous)
                .fill(Theme.attention.opacity(0.11))
                .overlay(
                    RoundedRectangle(cornerRadius: metrics.cardCorner, style: .continuous)
                        .strokeBorder(Theme.attention.opacity(0.28), lineWidth: 0.75)
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: metrics.cardCorner, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(session.title)
        .accessibilityValue(detailA11y(activity: activity))
        .accessibilityHint(l10n.deck.showsAccountHint)
        .accessibilityAddTraits(.isButton)
    }

    /// The account, what the session needs and how long it has waited, in words.
    private func detailA11y(activity: String) -> String {
        let waited = l10n.deck.waitingForA11y(l10n.format.durationSpoken(max(0, now.timeIntervalSince(item.waitingSince))))
        return [accountLabel, activity, waited].compactMap { $0 }.joined(separator: ", ")
    }
}
