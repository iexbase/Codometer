import CodometerCore
import SwiftUI

/// An account's identity mark: its monogram on a soft square in the account tint, with an optional provider glyph in
/// the corner.
///
/// Identity chrome only: tints never colour arcs, bars, rims or glass. The badge is decorative for VoiceOver, because
/// the account's name is always next to it.
public struct AccountBadge: View {
    let style: AccountStyle
    let provider: ProviderKind?
    let size: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    /// - Parameters:
    ///   - provider: Adds the provider glyph at the bottom-trailing corner; `nil` shows the monogram only.
    ///   - size: The side of the square in points.
    public init(style: AccountStyle, provider: ProviderKind?, size: CGFloat) {
        self.style = style
        self.provider = provider
        self.size = size
    }

    public var body: some View {
        let side = max(size, 1)
        let tint = Self.color(for: style.tint)
        RoundedRectangle(cornerRadius: side * 0.3, style: .continuous)
            .fill(tint.opacity(colorScheme == .dark ? 0.26 : 0.2))
            .frame(width: side, height: side)
            .overlay {
                Text(verbatim: style.monogram.value)
                    .font(.system(size: Self.fontSize(side: side, characters: style.monogram.value.count), weight: .semibold, design: .rounded))
                    // The wash is faint, so the monogram takes the contrast-safe text colour, not the wash's own.
                    .foregroundStyle(Theme.accountTintText(for: style.tint))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .overlay(alignment: .bottomTrailing) {
                if let provider {
                    ProviderGlyph(provider: provider, tinted: true)
                        .frame(width: side * 0.36, height: side * 0.36)
                        .offset(x: side * 0.08, y: side * 0.08)
                }
            }
            .accessibilityHidden(true)
    }

    /// Half the side for one character, a little less for two, never below the legible minimum.
    nonisolated static func fontSize(side: CGFloat, characters: Int) -> CGFloat {
        let ratio: CGFloat = characters > 1 ? 0.42 : 0.5
        return max(side * ratio, min(IslandMetrics.minimumTextSize, side * 0.6))
    }

    /// The tint's mark colour, from the design system's account palette.
    nonisolated static func color(for tint: AccountTint) -> Color {
        Theme.accountTint(for: tint)
    }

    /// The identity dot that marks an account where a whole badge would be too much: beside a deck dial's name and
    /// under a rail dial. Never on an arc — this is identity, not usage.
    public struct Dot: View {
        let tint: AccountTint
        let diameter: CGFloat

        public init(tint: AccountTint, diameter: CGFloat) {
            self.tint = tint
            self.diameter = diameter
        }

        public var body: some View {
            Circle()
                .fill(Theme.accountTint(for: tint))
                .frame(width: max(diameter, 1), height: max(diameter, 1))
                .accessibilityHidden(true)
        }
    }
}
