import CodometerCore
import SwiftUI

/// The widget's container background: a quiet graphite or porcelain gradient with a glass sheen.
///
/// Like the island's urgency glass, a faint glow of the worst band colour rises from the top corner once usage
/// leaves the ample band, and a violet glow warms the bottom corner while an agent waits. The system removes the
/// background in accented and vibrant rendering, so nothing here may carry meaning on its own.
public struct WidgetBackground: View {
    let urgency: UsageBand?
    let hasAttention: Bool
    let scheme: ColorScheme

    public init(urgency: UsageBand?, hasAttention: Bool, scheme: ColorScheme) {
        self.urgency = urgency
        self.hasAttention = hasAttention
        self.scheme = scheme
    }

    private var isDark: Bool { scheme == .dark }

    /// The two ends of the base gradient, lightest first. Exposed so a contrast test can measure the widget's text
    /// against the surface it actually sits on, rather than against a colour written down twice.
    public nonisolated static func gradientStops(isDark: Bool) -> [Color] {
        isDark
            ? [Color(red: 0.145, green: 0.155, blue: 0.195), Color(red: 0.070, green: 0.075, blue: 0.100)]
            : [Color(red: 0.995, green: 0.995, blue: 1.000), Color(red: 0.918, green: 0.928, blue: 0.955)]
    }

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: Self.gradientStops(isDark: isDark),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if let glow = urgencyGlow {
                EllipticalGradient(
                    colors: [glow, glow.opacity(0)],
                    center: UnitPoint(x: 0.08, y: 0.0),
                    startRadiusFraction: 0,
                    endRadiusFraction: 0.85
                )
            }
            if hasAttention {
                EllipticalGradient(
                    colors: [attentionGlow, attentionGlow.opacity(0)],
                    center: UnitPoint(x: 1.0, y: 1.0),
                    startRadiusFraction: 0,
                    endRadiusFraction: 0.75
                )
            }
            LinearGradient(
                colors: [Color.white.opacity(isDark ? 0.075 : 0.55), Color.white.opacity(0)],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.42)
            )
        }
    }

    private var urgencyGlow: Color? {
        guard let urgency, urgency > .ample else { return nil }
        let strength: Double = switch urgency {
        case .ample: 0
        case .watch: isDark ? 0.16 : 0.13
        case .critical: isDark ? 0.21 : 0.16
        case .exhausted: isDark ? 0.26 : 0.19
        }
        return WidgetPalette.bandGradient(urgency)[1].opacity(strength)
    }

    private var attentionGlow: Color {
        Color(red: 0.76, green: 0.35, blue: 0.96).opacity(isDark ? 0.24 : 0.15)
    }
}
