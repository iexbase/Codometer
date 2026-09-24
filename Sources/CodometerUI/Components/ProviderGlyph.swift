import CodometerCore
import SwiftUI

/// Original marks that tell providers apart at 10–20 pt.
///
/// Tinted with the provider accent for identity (account headers); untinted it takes the current
/// foreground style, which is how rings show it (monochrome, so it never competes with band colours).
public struct ProviderGlyph: View {
    let provider: ProviderKind
    var tinted = true

    public init(provider: ProviderKind, tinted: Bool = true) {
        self.provider = provider
        self.tinted = tinted
    }

    public var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let style = tinted ? AnyShapeStyle(Theme.accent(for: provider)) : AnyShapeStyle(.foreground)
            Group {
                switch provider {
                case .claude:
                    SparkShape().fill(style)
                case .codex:
                    PromptShape().stroke(style, style: StrokeStyle(lineWidth: max(1.3, side * 0.14), lineCap: .round, lineJoin: .round))
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
struct SparkShape: Shape {
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
struct PromptShape: Shape {
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
