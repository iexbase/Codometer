import CodometerCore
import SwiftUI

/// A small still picture of where the island will sit: a mock display with a menu bar and the island at the chosen
/// edge and offset.
///
/// A still on purpose. The Presentation pane's `IslandStage` is a live, draggable stage that needs about 460 pt of
/// height; the welcome window is 540 pt tall in total. Nothing here animates or polls, so the step costs nothing
/// while it is on screen.
struct OnboardingStagePreview: View {
    let edge: ScreenEdge
    let offset: EdgeOffset
    let style: IslandStyle

    /// The gap between a floating island and its edge, in preview points.
    private static let floatingInset: CGFloat = 7
    private static let menuBarHeight: CGFloat = 9
    private static let islandThickness: CGFloat = 13
    private static let islandLength: CGFloat = 62

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.24, green: 0.30, blue: 0.48), Color(red: 0.42, green: 0.28, blue: 0.52)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Rectangle()
                    .fill(.black.opacity(0.28))
                    .frame(height: Self.menuBarHeight)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12, style: .continuous))
                island
                    .frame(width: islandSize.width, height: islandSize.height)
                    .offset(x: origin(in: bounds).x, y: origin(in: bounds).y)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            }
        }
        .accessibilityHidden(true)
    }

    private var island: some View {
        Capsule(style: .continuous)
            .fill(Color.black.opacity(0.82))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
            }
            .overlay { rings }
    }

    /// Two ring stand-ins, laid out along the island.
    @ViewBuilder
    private var rings: some View {
        let colors: [Color] = [.green.opacity(0.9), .orange.opacity(0.9)]
        if edge.isHorizontal {
            HStack(spacing: 4) {
                ForEach(Array(colors.enumerated()), id: \.offset) { _, color in ring(color) }
            }
        } else {
            VStack(spacing: 4) {
                ForEach(Array(colors.enumerated()), id: \.offset) { _, color in ring(color) }
            }
        }
    }

    private func ring(_ color: Color) -> some View {
        Circle()
            .strokeBorder(color, lineWidth: 1.6)
            .frame(width: 7, height: 7)
    }

    private var islandSize: CGSize {
        edge.isHorizontal
            ? CGSize(width: Self.islandLength, height: Self.islandThickness)
            : CGSize(width: Self.islandThickness, height: Self.islandLength)
    }

    /// Top-left of the island inside the mock display, from the edge and the offset along it.
    private func origin(in bounds: CGRect) -> CGPoint {
        let inset = style == .floating ? Self.floatingInset : 0
        let size = islandSize
        switch edge {
        case .top:
            return CGPoint(x: along(bounds.width, size.width), y: Self.menuBarHeight + inset)
        case .bottom:
            return CGPoint(x: along(bounds.width, size.width), y: bounds.height - size.height - inset)
        case .left:
            return CGPoint(x: inset, y: alongVertical(bounds.height, size.height))
        case .right:
            return CGPoint(x: bounds.width - size.width - inset, y: alongVertical(bounds.height, size.height))
        }
    }

    private func along(_ total: CGFloat, _ length: CGFloat) -> CGFloat {
        let free = max(0, total - length - 2 * Self.floatingInset)
        return Self.floatingInset + free * offset.value
    }

    private func alongVertical(_ total: CGFloat, _ length: CGFloat) -> CGFloat {
        let top = Self.menuBarHeight + Self.floatingInset
        let free = max(0, total - length - top - Self.floatingInset)
        return top + free * offset.value
    }
}
