import CodometerCore
import CodometerL10n
import SwiftUI

/// The rail split into two wings around a MacBook's camera notch.
///
/// Both wings are ordinary `RailView`s, so dials, labels, halos and the sheen are exactly the ones an unfused rail
/// draws. Only the split is new: the first half of the accounts goes left, the rest right, the attention tab ends the
/// right wing (the left one when the right holds no account, `NotchFusion.wingContents`), and accounts neither wing
/// has room for become a "+N" chip that opens the expanded island.
///
/// `NotchWingLayout` gives both wings the width of the wider one, so the gap stays centred on the rail — and the rail
/// is centred on the notch (`IslandGeometry.railFrame`), so the gap lines up with the hardware notch whatever the two
/// wings hold. It measures them instead of drawing hidden copies: a second set of dials would double the rail's
/// drawing and show up in the accessibility tree.
struct NotchRailView: View {
    let store: TrackerStore
    let model: IslandModel
    let accounts: [AccountPresentation]
    let notch: NotchGeometry

    @Environment(\.l10n) private var l10n

    private var metrics: IslandMetrics { model.layout.metrics }

    private var dialDiameter: CGFloat {
        NotchFusion.dialDiameter(
            railDial: metrics.railDial,
            menuBarHeight: notch.menuBarHeight,
            orbitMargin: metrics.orbitMargin
        )
    }

    /// Width one wing item takes: a dial with its orbit margin plus the widest label beside it.
    private var itemWidth: CGFloat {
        dialDiameter + metrics.orbitMargin * 2 + 34 * metrics.scale
    }

    private var wings: NotchWings {
        NotchFusion.wings(
            accountCount: accounts.count,
            hasAttention: store.hasWaiting && !store.attentionQueue.isEmpty,
            maximumWingItems: max(1, NotchFusion.maximumWingItems(notch: notch, itemWidth: itemWidth))
        )
    }

    /// Clear space between a wing and the notch, plus the outer shoulder the fused silhouette needs.
    private var outerInset: CGFloat { NotchFusion.wingGap + metrics.shoulder }

    var body: some View {
        let wings = self.wings
        let left = Array(accounts[safe: wings.left])
        let right = Array(accounts[safe: wings.right])
        let contents = NotchFusion.wingContents(leftCount: left.count, rightCount: right.count)
        NotchWingLayout(gap: notch.rect.width + NotchFusion.wingGap * 2) {
            railStrip(left, showsAttentionTab: contents.showsTabOnLeft, showsPlaceholder: false)
            railStrip(right, showsAttentionTab: contents.showsTabOnRight, showsPlaceholder: contents.showsPlaceholder)
        }
        .padding(.horizontal, outerInset)
        .frame(height: notch.menuBarHeight)
        .overlay(alignment: .leading) {
            if wings.showsOverflowChip {
                overflowChip(wings.overflow)
                    .padding(.leading, outerInset)
            }
        }
    }

    /// One wing's strip. An empty wing draws nothing at all: `RailView`'s "no accounts" placeholder belongs to a rail
    /// that really has none (`showsPlaceholder`), not to the short side of a split one.
    @ViewBuilder
    private func railStrip(_ shown: [AccountPresentation], showsAttentionTab: Bool, showsPlaceholder: Bool) -> some View {
        if shown.isEmpty, !showsPlaceholder {
            Color.clear.frame(width: 0, height: 0)
        } else {
            RailView(
                store: store,
                model: model,
                accounts: shown,
                showsAttentionTab: showsAttentionTab,
                dialDiameter: dialDiameter
            )
            .fixedSize()
        }
    }

    /// "+N" for the accounts neither wing has room for; a click opens the expanded island, where they all fit.
    private func overflowChip(_ count: Int) -> some View {
        Button {
            model.request(.openAttention)
        } label: {
            Text(l10n.notch.overflow(count))
                .font(metrics.digits(TextSize.badge, .bold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5 * metrics.scale)
                .frame(minWidth: 24, minHeight: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(l10n.notch.overflowA11y(count))
        .accessibilityLabel(l10n.notch.overflowA11y(count))
        .accessibilityHint(l10n.notch.overflowHint)
    }
}

/// Two wings of equal width with `gap` points of clear space between them, the left one pushed towards the gap and
/// the right one away from it.
///
/// Equal widths keep the gap in the middle of the whole rail, which is what centres it on the camera notch.
struct NotchWingLayout: Layout {
    /// The notch's own width plus the clear space on each side of it.
    let gap: CGFloat

    /// The widths both wings are given: the wider one's.
    nonisolated static func wingWidth(_ sizes: [CGSize]) -> CGFloat {
        sizes.reduce(0) { max($0, $1.width) }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let wing = Self.wingWidth(sizes)
        let height = sizes.reduce(0) { max($0, $1.height) }
        return CGSize(width: wing * 2 + max(0, gap), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let wing = Self.wingWidth(sizes)
        for (index, subview) in subviews.enumerated() {
            let size = sizes[index]
            // The left wing hugs the gap; the right one starts right after it.
            let x = index == 0
                ? bounds.minX + wing - size.width
                : bounds.minX + wing + max(0, gap)
            subview.place(
                at: CGPoint(x: x, y: bounds.midY - size.height / 2),
                proposal: ProposedViewSize(size)
            )
        }
    }
}

extension Array {
    /// The elements of a range that may reach past the array (a wing plan computed before a reload).
    subscript(safe range: Range<Int>) -> ArraySlice<Element> {
        let lower = Swift.min(Swift.max(range.lowerBound, 0), count)
        let upper = Swift.min(Swift.max(range.upperBound, lower), count)
        return self[lower..<upper]
    }
}
