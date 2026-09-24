import CodometerCore
import CodometerL10n
import SwiftUI

/// The account's live sessions in one card: waiting first, at most four, with hedged status wording
/// and the last turn's timing.
struct SessionList: View {
    let sessions: [AgentSession]
    let provider: ProviderKind
    let now: Date
    let metrics: IslandMetrics
    @Environment(\.l10n) private var l10n

    var body: some View {
        let list = DeckLayout.sessions(sessions)
        VStack(alignment: .leading, spacing: 6 * metrics.scale) {
            SectionTitle(l10n.session.title, metrics: metrics)
                .padding(.leading, 4 * metrics.scale)
            VStack(spacing: 0) {
                ForEach(Array(list.shown.enumerated()), id: \.element.id) { index, session in
                    VStack(spacing: 0) {
                        if index > 0 {
                            Hairline()
                                .padding(.leading, (10 + 22 + 10) * metrics.scale)
                        }
                        SessionRow(session: session, provider: provider, now: now, metrics: metrics)
                    }
                    .transition(.opacity)
                }
                if list.hidden > 0 {
                    Hairline()
                        .padding(.leading, (10 + 22 + 10) * metrics.scale)
                    Text(l10n.session.more(list.hidden))
                        .font(metrics.font(TextSize.caption))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, (10 + 22 + 10) * metrics.scale)
                        .padding(.vertical, 6 * metrics.scale)
                }
            }
            .background(RoundedRectangle(cornerRadius: metrics.cardCorner, style: .continuous).fill(Theme.cardFill))
        }
    }
}

private struct SessionRow: View {
    let session: AgentSession
    let provider: ProviderKind
    let now: Date
    let metrics: IslandMetrics
    @Environment(\.l10n) private var l10n

    var body: some View {
        let isWaiting = session.activity == .waiting
        HStack(alignment: .center, spacing: 10 * metrics.scale) {
            ActivityGlyph(activity: session.activity, size: 22 * metrics.scale)
            VStack(alignment: .leading, spacing: 1.5 * metrics.scale) {
                HStack(alignment: .firstTextBaseline, spacing: 6 * metrics.scale) {
                    Text(session.title)
                        .font(metrics.font(TextSize.body, .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 6 * metrics.scale)
                    ReservedWidthText(text: UsageFormat.elapsed(since: session.activitySince, now: now, l10n: l10n), template: DeckLayout.elapsedTemplate(l10n: l10n))
                        .font(metrics.digits(TextSize.caption, .medium))
                        .foregroundStyle(.secondary)
                }
                let status = DeckLayout.sessionStatus(session, provider: provider, now: now, l10n: l10n)
                // Shorter words on a narrow line (a small island scale), never a second line.
                ViewThatFits(in: .horizontal) {
                    Text(status)
                    if let compact = DeckLayout.compactStatus(status, l10n: l10n) {
                        Text(compact)
                    }
                }
                .font(metrics.font(TextSize.caption, isWaiting ? .medium : .regular))
                .foregroundStyle(isWaiting ? AnyShapeStyle(Theme.attentionText) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                if let turn = session.lastTurn {
                    Label {
                        Text(UsageFormat.turn(turn, l10n: l10n))
                    } icon: {
                        Image(systemName: "timer")
                    }
                    .labelStyle(CompactLabelStyle(spacing: 3 * metrics.scale))
                    .font(metrics.digits(TextSize.caption, .regular))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 10 * metrics.scale)
        .padding(.vertical, 8 * metrics.scale)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(session.title)
        .accessibilityValue(SessionList.valueA11y(session, provider: provider, now: now, l10n: l10n))
    }
}

extension SessionList {
    /// A session row for VoiceOver, times in words: "Working, 7 minutes, last turn 4 minutes 12 seconds, first token in
    /// 2.8 seconds".
    static func valueA11y(_ session: AgentSession, provider: ProviderKind, now: Date, l10n: Localizer) -> String {
        var parts = [
            DeckLayout.sessionStatus(session, provider: provider, now: now, l10n: l10n),
            l10n.format.durationSpoken(max(0, now.timeIntervalSince(session.activitySince))),
        ]
        if let turn = session.lastTurn {
            parts.append(l10n.session.lastTurnA11y(l10n.session.spokenPrecise(turn.duration)))
            if let latency = turn.firstTokenLatency {
                parts.append(l10n.session.firstTokenA11y(l10n.session.spokenLatency(latency)))
            }
            if turn.wasAborted {
                parts.append(l10n.usage.interrupted)
            }
        }
        return parts.joined(separator: ", ")
    }
}

/// An icon and title with a tight, explicit spacing.
struct CompactLabelStyle: LabelStyle {
    let spacing: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: spacing) {
            configuration.icon
            configuration.title
        }
    }
}
