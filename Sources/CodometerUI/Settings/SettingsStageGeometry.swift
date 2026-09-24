import CodometerCore
import CoreGraphics

/// Placement math for the settings preview's mock display.
///
/// The preview lays the island out on a "virtual" screen in real island points and draws that screen
/// scaled down, so the island keeps its true proportions and text layout. The island's frame comes from
/// the same `IslandGeometry` functions the island controller uses for its window, in AppKit coordinates
/// (origin bottom-left); `viewRect` converts to SwiftUI's top-left coordinates for drawing.
enum SettingsStageGeometry {
    /// A mock screen in AppKit coordinates: the full frame and the part not covered by the menu bar and Dock.
    struct Screen: Equatable {
        let frame: CGRect
        let visible: CGRect
    }

    /// Virtual heights of the mock menu bar and Dock.
    static let menuBarHeight: CGFloat = 24
    static let dockHeight: CGFloat = 42
    static let dockGap: CGFloat = 5
    /// The screen height the Dock keeps free at the bottom.
    static var dockReserve: CGFloat { dockHeight + dockGap * 2 }

    /// The preview draws the island at this size when the expanded deck fits.
    static let preferredScale: CGFloat = 0.8
    static let minimumScale: CGFloat = 0.4
    /// Scale changes in steps, so a deck growing by a point or two never rescales the preview.
    static let scaleStep: CGFloat = 0.025
    /// Free space kept around the deck when choosing the scale.
    static let breathingRoom: CGFloat = 8

    /// The factor the virtual screen is drawn at: `preferredScale`, or less when the expanded deck
    /// (plus menu bar and Dock) would not fit into `display`. Quantised to `scaleStep`.
    static func displayScale(display: CGSize, deck: CGSize) -> CGFloat {
        guard display.width > 1, display.height > 1, deck.width > 0, deck.height > 0 else { return preferredScale }
        let neededHeight = deck.height + menuBarHeight + dockReserve + breathingRoom * 2
        let neededWidth = deck.width + breathingRoom * 2
        let fit = min(display.height / neededHeight, display.width / neededWidth)
        let stepped = (fit / scaleStep + 1e-9).rounded(.down) * scaleStep
        return min(preferredScale, max(minimumScale, stepped))
    }

    /// The virtual screen shown in `display` at `scale`.
    static func screen(display: CGSize, scale: CGFloat) -> Screen {
        let factor = max(scale, minimumScale)
        let size = CGSize(width: max(1, display.width) / factor, height: max(1, display.height) / factor)
        let frame = CGRect(origin: .zero, size: size)
        let visible = CGRect(
            x: 0,
            y: dockReserve,
            width: size.width,
            height: max(0, size.height - menuBarHeight - dockReserve)
        )
        return Screen(frame: frame, visible: visible)
    }

    /// The frame the island controller would give its window: the rail at rest, or the deck frame while
    /// the deck is shown or still folding. `nil` until the rail has been measured.
    static func windowFrame(rail: CGSize, deck: CGSize, layout: IslandLayout, offset: Double, showsDeck: Bool, in screen: Screen) -> CGRect? {
        guard rail.width > 0, rail.height > 0 else { return nil }
        let area = IslandGeometry.area(edge: layout.edge, style: layout.style, screen: screen.frame, visible: screen.visible)
        let fused = layout.isNotchFused ? layout.notch : nil
        let railFrame = IslandGeometry.railFrame(size: rail, edge: layout.edge, offset: offset, style: layout.style, in: area, fusedNotch: fused)
        guard showsDeck, deck.width > 0, deck.height > 0 else { return railFrame }
        return IslandGeometry.expandedFrame(rail: railFrame, size: deck, anchor: layout.anchor, in: area)
    }

    /// A camera notch for the mock display: the same proportions as a 14" MacBook Pro, in virtual points.
    ///
    /// Only drawn when the display the island resolves to really has one, so the preview never promises fusion on a
    /// Mac that cannot do it.
    static func notch(in screen: Screen) -> NotchGeometry? {
        let width = (screen.frame.width * 0.185).rounded()
        let aux = (screen.frame.width - width) / 2
        guard aux > 0 else { return nil }
        return NotchGeometry.make(
            screen: screen.frame,
            safeTop: menuBarHeight,
            auxLeft: CGRect(x: screen.frame.minX, y: screen.frame.maxY - menuBarHeight, width: aux, height: menuBarHeight),
            auxRight: CGRect(x: screen.frame.minX + aux + width, y: screen.frame.maxY - menuBarHeight, width: aux, height: menuBarHeight)
        )
    }

    /// While carried, the rail is centred on the pointer and kept on the screen.
    static func dragFrame(center: CGPoint, rail: CGSize, in screen: Screen) -> CGRect {
        var frame = CGRect(x: center.x - rail.width / 2, y: center.y - rail.height / 2, width: rail.width, height: rail.height)
        frame.origin.x = min(max(frame.minX, screen.frame.minX), max(screen.frame.minX, screen.frame.maxX - rail.width))
        frame.origin.y = min(max(frame.minY, screen.frame.minY), max(screen.frame.minY, screen.frame.maxY - rail.height))
        return frame.integral
    }

    /// Where a drop at `point` (AppKit coordinates) lands: the same nearest-edge rule as the real island.
    static func dropPlacement(at point: CGPoint, rail: CGSize, style: IslandStyle, in screen: Screen) -> (edge: ScreenEdge, offset: Double) {
        IslandGeometry.placement(for: point, railSize: rail, style: style, screen: screen.frame, visible: screen.visible)
    }

    /// AppKit rect → SwiftUI rect on the same screen.
    static func viewRect(_ rect: CGRect, in screen: Screen) -> CGRect {
        CGRect(x: rect.minX, y: screen.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    /// SwiftUI point → AppKit point on the same screen.
    static func screenPoint(_ point: CGPoint, in screen: Screen) -> CGPoint {
        CGPoint(x: point.x, y: screen.frame.maxY - point.y)
    }
}
