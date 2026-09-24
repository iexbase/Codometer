import CodometerCore
import CodometerL10n
import SwiftUI

/// The account cannot be used until a window resets.
struct BlockedBanner: View {
    let window: LimitWindow?
    let now: Date
    let metrics: IslandMetrics
    @Environment(\.l10n) private var l10n

    var body: some View {
        let tint = Theme.bandText(for: .exhausted)
        HStack(spacing: 10 * metrics.scale) {
            Image(systemName: "lock.fill")
                .font(metrics.font(TextSize.body, .semibold))
                .foregroundStyle(tint)
                .frame(width: 22 * metrics.scale)
            VStack(alignment: .leading, spacing: 1 * metrics.scale) {
                Text(title)
                    .font(metrics.font(TextSize.body, .semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                Text(detail)
                    .font(metrics.digits(TextSize.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10 * metrics.scale)
        .padding(.vertical, 8 * metrics.scale)
        .background(RoundedRectangle(cornerRadius: metrics.cardCorner, style: .continuous).fill(Theme.tint(for: .exhausted).opacity(0.12)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(detailA11y)
    }

    private var title: String {
        guard let window else { return l10n.banner.limitReached }
        return l10n.banner.limitReached(window: UsageFormat.windowTitle(window, l10n: l10n))
    }

    private var detail: String {
        guard let remaining = window?.timeUntilReset(from: now) else { return l10n.banner.resetTimeUnknown }
        guard remaining > 0 else { return l10n.usage.resetting }
        return l10n.banner.backIn(UsageFormat.compactDuration(remaining, l10n: l10n))
    }

    /// `detail` with the countdown in words.
    private var detailA11y: String {
        guard let remaining = window?.timeUntilReset(from: now), remaining > 0 else { return detail }
        return l10n.banner.backInA11y(l10n.format.durationSpoken(remaining))
    }
}

/// The latest refresh failed; calm and neutral, since no usage colour applies. "Try Again" refreshes just this
/// account (polling may have stopped until a manual refresh).
///
/// The title says what went wrong in the user's language, on up to two lines. The technical detail (English CLI
/// output) is only the title's tooltip.
struct IssueBanner: View {
    let issue: TrackerIssue
    let provider: ProviderKind
    let isRefreshing: Bool
    let metrics: IslandMetrics
    let onRetry: () -> Void
    @Environment(\.l10n) private var l10n

    var body: some View {
        HStack(alignment: .center, spacing: 10 * metrics.scale) {
            Image(systemName: issue.kind == .offline ? "wifi.slash" : "exclamationmark.triangle.fill")
                .font(metrics.font(TextSize.body, .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22 * metrics.scale)
                .accessibilityHidden(true)
            Text(UsageFormat.issue(issue, provider: provider, l10n: l10n))
                .font(metrics.font(TextSize.body, .semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .help(issue.detail)
            Spacer(minLength: 0)
            Button(action: onRetry) {
                Text(l10n.common.tryAgain)
                    .font(metrics.font(TextSize.footnote, .semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 9 * metrics.scale)
                    .padding(.vertical, 4 * metrics.scale)
                    .background(Capsule().fill(Theme.selectionFill))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            // Dimmed rather than hidden while refreshing, so the banner keeps its layout.
            .opacity(isRefreshing ? 0.45 : 1)
            .disabled(isRefreshing)
            .help(l10n.banner.refreshAccountHelp)
        }
        .padding(.horizontal, 10 * metrics.scale)
        .padding(.vertical, 8 * metrics.scale)
        .background(RoundedRectangle(cornerRadius: metrics.cardCorner, style: .continuous).fill(Theme.cardFill))
        .accessibilityElement(children: .contain)
    }
}
