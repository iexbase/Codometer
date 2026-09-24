import AppKit
import QuartzCore
import SwiftUI

/// A soft band of light that sweeps once across its bounds whenever `trigger` changes, e.g. when the rail's numbers
/// update. Never on first appearance.
///
/// Event-driven Core Animation only: the band rests outside the bounds (clipped), one position animation runs on the
/// render server per change, and nothing runs while the window is hidden or occluded. Callers leave it out entirely
/// without live effects or with Reduce Motion.
struct SheenSweep: NSViewRepresentable {
    /// Any value that changes when the sheen should play.
    let trigger: Int
    /// Sweep along the width (a horizontal rail) or the height (a vertical one).
    let horizontal: Bool
    /// Corner radius of the region the band is clipped to.
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> SheenSweepView {
        SheenSweepView()
    }

    func updateNSView(_ view: SheenSweepView, context: Context) {
        view.update(trigger: trigger, horizontal: horizontal, cornerRadius: cornerRadius)
    }
}

final class SheenSweepView: NSView {
    private static let animationKey = "sheen"
    /// Peak opacity of the band's white core.
    nonisolated static let peakOpacity: CGFloat = 0.16

    private let band = CAGradientLayer()
    private var lastTrigger: Int?
    private var horizontal = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.masksToBounds = true
        band.colors = [
            CGColor(gray: 1, alpha: 0),
            CGColor(gray: 1, alpha: Self.peakOpacity),
            CGColor(gray: 1, alpha: 0),
        ]
        band.locations = [0, 0.5, 1]
        layer?.addSublayer(band)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Decoration only: clicks, hover and drags belong to the island.
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func update(trigger: Int, horizontal: Bool, cornerRadius: CGFloat) {
        let previous = lastTrigger
        lastTrigger = trigger
        if self.horizontal != horizontal || layer?.cornerRadius != cornerRadius {
            self.horizontal = horizontal
            layer?.cornerRadius = cornerRadius
            needsLayout = true
        }
        guard let previous, previous != trigger else { return }
        sweep()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        placeBand()
        CATransaction.commit()
    }

    /// Rests the band just outside the leading end, slanted a little so the light reads as a reflection.
    private func placeBand() {
        let length = Self.bandLength(for: horizontal ? bounds.width : bounds.height)
        if horizontal {
            band.bounds = CGRect(x: 0, y: 0, width: length, height: bounds.height * 1.6)
            band.startPoint = CGPoint(x: 0, y: 0.35)
            band.endPoint = CGPoint(x: 1, y: 0.65)
        } else {
            band.bounds = CGRect(x: 0, y: 0, width: bounds.width * 1.6, height: length)
            band.startPoint = CGPoint(x: 0.35, y: 0)
            band.endPoint = CGPoint(x: 0.65, y: 1)
        }
        band.position = Self.restingPosition(bounds: bounds, horizontal: horizontal, length: length)
    }

    private func sweep() {
        let visible = window.map { $0.isVisible && $0.occlusionState.contains(.visible) } ?? false
        guard visible, bounds.width > 0, bounds.height > 0 else { return }
        let length = Self.bandLength(for: horizontal ? bounds.width : bounds.height)
        let start = Self.restingPosition(bounds: bounds, horizontal: horizontal, length: length)
        let end = horizontal
            ? CGPoint(x: bounds.maxX + length / 2, y: bounds.midY)
            : CGPoint(x: bounds.midX, y: bounds.minY - length / 2)
        let animation = CABasicAnimation(keyPath: "position")
        animation.fromValue = NSValue(point: start)
        animation.toValue = NSValue(point: end)
        animation.duration = Motion.sheenDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        // The model position stays at rest, so the band is outside the bounds again once the sweep is over.
        animation.isRemovedOnCompletion = true
        band.removeAnimation(forKey: Self.animationKey)
        band.add(animation, forKey: Self.animationKey)
    }

    /// The band is a bit under half as long as the region, and never shorter than 36 points.
    nonisolated static func bandLength(for regionLength: CGFloat) -> CGFloat {
        max(36, regionLength * 0.45)
    }

    /// Where the band waits: centred just before the region's leading end (top for a vertical sweep).
    private static func restingPosition(bounds: CGRect, horizontal: Bool, length: CGFloat) -> CGPoint {
        horizontal
            ? CGPoint(x: bounds.minX - length / 2, y: bounds.midY)
            : CGPoint(x: bounds.midX, y: bounds.maxY + length / 2)
    }
}
