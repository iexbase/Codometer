import CodometerCore
import CodometerL10n
import SwiftUI
import WidgetKit

/// Monochrome provider marks: the island's spark for Claude and prompt for Codex.
struct ProviderMark: View {
    let provider: ProviderKind
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            Group {
                switch provider {
                case .claude:
                    SparkShape().fill(color)
                case .codex:
                    PromptShape().stroke(color, style: StrokeStyle(lineWidth: max(1.3, side * 0.14), lineCap: .round, lineJoin: .round))
                }
            }
            .frame(width: side, height: side)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// An eight-ray spark with tapered, slightly curved rays.
private struct SparkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.3
        var path = Path()
        for index in 0..<8 {
            let angle = Double(index) * .pi / 4 - .pi / 2
            let length = index.isMultiple(of: 2) ? outer : outer * 0.74
            let spread = Double.pi / 8 * 0.62
            func point(_ radius: Double, _ theta: Double) -> CGPoint {
                CGPoint(x: center.x + cos(theta) * radius, y: center.y + sin(theta) * radius)
            }
            path.move(to: center)
            path.addLine(to: point(inner, angle - spread))
            path.addQuadCurve(to: point(length, angle), control: point(length * 0.62, angle - spread * 0.45))
            path.addQuadCurve(to: point(inner, angle + spread), control: point(length * 0.62, angle + spread * 0.45))
            path.closeSubpath()
        }
        return path
    }
}

/// A terminal prompt: a chevron followed by an underscore.
private struct PromptShape: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x * side, y: origin.y + y * side)
        }
        var path = Path()
        path.move(to: point(0.14, 0.24))
        path.addLine(to: point(0.44, 0.5))
        path.addLine(to: point(0.14, 0.76))
        path.move(to: point(0.54, 0.78))
        path.addLine(to: point(0.88, 0.78))
        return path
    }
}

/// "2" (or "2 waiting") in a violet capsule with a small hand: sessions waiting for the user.
struct AttentionBadge: View {
    @Environment(\.widgetL10n) private var l10n
    let count: Int
    let palette: WidgetPalette
    var size: CGFloat = 11.5
    var showsLabel = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: size - 2, weight: .semibold))
            Text(verbatim: showsLabel ? l10n.widget.waiting(count) : "\(count)")
                .font(WidgetFont.digits(size, .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(palette.attention)
        .padding(.horizontal, size * 0.55)
        .padding(.vertical, size * 0.2)
        .background(Capsule().fill(palette.attentionFill))
        .widgetAccentable()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(l10n.widget.waitingA11y(count))
    }
}

/// A quiet capsule with a waveform and the number of working agents; waiting agents get `AttentionBadge` instead.
struct WorkingBadge: View {
    @Environment(\.widgetL10n) private var l10n
    let count: Int
    let palette: WidgetPalette
    var size: CGFloat = 11.5

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "waveform")
                .font(.system(size: size - 1.5, weight: .semibold))
            Text(verbatim: "\(count)")
                .font(WidgetFont.digits(size, .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(palette.secondary)
        .padding(.horizontal, size * 0.55)
        .padding(.vertical, size * 0.2)
        .background(Capsule().fill(palette.chipFill))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(l10n.widget.workingA11y(count))
    }
}

/// A provider's mark in its identity tint on a faint disc, for headers.
struct ProviderBadgeMark: View {
    let provider: ProviderKind
    let palette: WidgetPalette
    var side: CGFloat = 20

    var body: some View {
        ZStack {
            Circle()
                .fill(palette.providerTintFill(provider))
            ProviderMark(provider: provider, color: palette.providerTint(provider))
                .frame(width: side * 0.56, height: side * 0.56)
        }
        .frame(width: side, height: side)
        .widgetAccentable()
    }
}

/// An account's identity mark: its monogram on a soft square in the account tint.
///
/// The island's `AccountBadge`, held to what a widget can do. Identity chrome only, so the tint never says anything
/// about usage. In the accented rendering mode only the monogram is accentable: the square keeps the system's plain
/// fill, which is what stops an account's mark from reading as a tinted state. Decorative for VoiceOver, because the
/// account's name is always beside it.
struct WidgetAccountBadge: View {
    let monogram: AccountMonogram
    /// `nil` falls back to the neutral tint, as an old snapshot's account does.
    let tint: AccountTint?
    let palette: WidgetPalette
    var side: CGFloat = 20

    var body: some View {
        let tint = tint ?? .graphite
        RoundedRectangle(cornerRadius: side * 0.3, style: .continuous)
            .fill(palette.accountTintFill(tint))
            .frame(width: side, height: side)
            .overlay {
                Text(verbatim: monogram.value)
                    .font(WidgetFont.text(Self.fontSize(side: side, characters: monogram.value.count), .semibold))
                    .foregroundStyle(palette.accountTint(tint))
                    .lineLimit(1)
                    .widgetAccentable()
            }
            .accessibilityHidden(true)
    }

    /// Below this a monogram stops being readable on a desktop widget; the ring caption is the only text this small.
    nonisolated static let minimumTextSize: CGFloat = 8

    /// Half the side for one character, a little less for two; an emoji counts as one. Never below
    /// `minimumTextSize`, unless the badge itself is smaller than that.
    nonisolated static func fontSize(side: CGFloat, characters: Int) -> CGFloat {
        let ratio: CGFloat = characters > 1 ? 0.42 : 0.5
        return max(side * ratio, min(minimumTextSize, side * 0.6))
    }
}

/// A small plan capsule such as "Max" (provider data, never translated).
struct PlanChip: View {
    let text: String
    let palette: WidgetPalette

    var body: some View {
        Text(text)
            .font(WidgetFont.text(10.5, .semibold))
            .foregroundStyle(palette.secondary)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(palette.chipFill))
    }
}
