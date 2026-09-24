import CodometerCore
import CodometerL10n
import AppKit
import QuartzCore
import SwiftUI

/// The rail's "waiting for you" capsule: a raised hand and how many agents wait, in the attention colour, with a
/// calm pulse. Clicking it opens the deck on the attention queue.
struct AttentionTab: View {
    let count: Int
    let metrics: IslandMetrics
    let action: () -> Void

    @Environment(\.liveEffectsEnabled) private var liveEffectsEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.l10n) private var l10n

    /// The count as shown: 0…99, larger queues read "99". Digits are monospaced, so the tab only widens when
    /// the count gains a digit.
    nonisolated static func countText(_ count: Int) -> String {
        "\(min(max(count, 0), 99))"
    }

    /// The smallest a pointer target may be. The tab's own padding leaves it a few points short, so the
    /// capsule is held to this. It stays well under a dial's height at every island scale, so the rail never grows.
    nonisolated static func hitTarget(_ metrics: IslandMetrics) -> CGFloat {
        max(24, 24 * metrics.scale)
    }

    var body: some View {
        let shape = Capsule(style: .continuous)
        Button(action: action) {
            HStack(spacing: 3 * metrics.scale) {
                Image(systemName: "hand.raised.fill")
                    .font(metrics.font(TextSize.badge, .semibold))
                Text(Self.countText(count))
                    .font(metrics.digits(TextSize.footnote, .bold))
                    .contentTransition(.numericText(value: Double(count)))
                    .fixedSize()
                    // Keep a rolling digit inside its own box (see RailLabelView).
                    .compositingGroup()
                    .clipped()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 7 * metrics.scale)
            .padding(.vertical, 3.5 * metrics.scale)
            // A real pointer target, not just a chip: the padded label alone comes out 22 pt tall.
            .frame(minWidth: Self.hitTarget(metrics), minHeight: Self.hitTarget(metrics))
            .background {
                shape.fill(LinearGradient(
                    colors: [Theme.attention.mix(with: .white, by: 0.18), Theme.attention],
                    startPoint: .top,
                    endPoint: .bottom
                ))
            }
            .background {
                if liveEffectsEnabled, !reduceMotion, !Motion.reducesMotion {
                    AttentionPulse(color: NSColor(Theme.attention))
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .animation(Motion.snappy, value: count)
        .help(l10n.rail.waiting(count))
        .accessibilityLabel(l10n.rail.waiting(count))
        .accessibilityAddTraits(.isButton)
    }
}

/// A capsule halo that swells and fades on the render server, so waiting costs the app no per-frame work.
private struct AttentionPulse: NSViewRepresentable {
    let color: NSColor

    func makeNSView(context: Context) -> AttentionPulseView {
        AttentionPulseView()
    }

    func updateNSView(_ view: AttentionPulseView, context: Context) {
        view.color = color
    }
}

/// The halo's layer. Its infinite animation runs only while the window is on screen and visible, restarts when
/// the tab changes size (the swell is measured in points), and layout never animates implicitly.
final class AttentionPulseView: NSView {
    private static let animationKey = "pulse"
    /// How far the halo swells past the capsule, in points on each axis.
    static let swell: CGFloat = 10

    var color: NSColor = .systemPurple {
        didSet {
            guard color != oldValue else { return }
            withoutActions { halo.fillColor = color.withAlphaComponent(0.5).cgColor }
        }
    }

    private let halo = CAShapeLayer()
    private weak var observedWindow: NSWindow?
    /// The size the running animation was built for.
    private var animatedSize: CGSize = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.addSublayer(halo)
        halo.fillColor = color.withAlphaComponent(0.5).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Decoration only: clicks belong to the tab above it.
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()
        let radius = bounds.height / 2
        withoutActions {
            halo.bounds = bounds
            halo.position = CGPoint(x: bounds.midX, y: bounds.midY)
            halo.path = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        }
        if bounds.size != animatedSize {
            stopAnimating()
        }
        updateRunning()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if let observedWindow {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: observedWindow)
        }
        observedWindow = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            observedWindow = window
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(occlusionChanged(_:)),
                name: NSWindow.didChangeOcclusionStateNotification,
                object: window
            )
        }
        updateRunning()
    }

    @objc private func occlusionChanged(_ notification: Notification) {
        updateRunning()
    }

    private func updateRunning() {
        let visible = window.map { $0.occlusionState.contains(.visible) } ?? false
        if visible, bounds.width > 0, bounds.height > 0 {
            startAnimating()
        } else {
            stopAnimating()
        }
    }

    private func startAnimating() {
        guard halo.animation(forKey: Self.animationKey) == nil else { return }
        animatedSize = bounds.size
        let scaleX = CABasicAnimation(keyPath: "transform.scale.x")
        scaleX.fromValue = 1
        scaleX.toValue = 1 + Self.swell / bounds.width
        let scaleY = CABasicAnimation(keyPath: "transform.scale.y")
        scaleY.fromValue = 1
        scaleY.toValue = 1 + Self.swell / bounds.height
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.85
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scaleX, scaleY, fade]
        group.duration = 1.8
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.isRemovedOnCompletion = false
        halo.add(group, forKey: Self.animationKey)
    }

    private func stopAnimating() {
        halo.removeAnimation(forKey: Self.animationKey)
        animatedSize = .zero
    }

    private func withoutActions(_ change: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        change()
        CATransaction.commit()
    }
}
