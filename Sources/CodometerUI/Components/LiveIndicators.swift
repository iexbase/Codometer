import CodometerCore
import CodometerL10n
import AppKit
import SwiftUI

extension EnvironmentValues {
    /// Whether never-ending effects (orbits, pulses) run. Off for hidden measurement copies,
    /// static renders and Reduce Motion.
    @Entry public var liveEffectsEnabled = true
}

/// Where an activity orbit runs: in the margin reserved around a ring.
public enum OrbitGeometry {
    /// Radius of the orbit's centre line: halfway through the margin.
    public static func radius(diameter: CGFloat, margin: CGFloat) -> CGFloat {
        diameter / 2 + margin / 2
    }

    /// Stroke width of the orbit: thin enough to stay inside the margin with its round caps.
    public static func lineWidth(margin: CGFloat) -> CGFloat {
        max(1, margin * 0.55)
    }

    /// Orbits need at least this much margin; with less, none is drawn.
    public static let minimumMargin: CGFloat = 1.5
    /// Share of a turn the comet's tail covers.
    public static let tailLength = 0.3
    /// Seconds per lap of the comet.
    public static let lapDuration: CFTimeInterval = 1.4
    /// Seconds for the waiting ring to fade from dim to bright.
    public static let pulseDuration: CFTimeInterval = 0.9

    /// The tail's segments from its end to the head: start and end as fractions of a turn behind the head
    /// (positive values trail the head), with the opacity and relative width of each.
    public static func tailSegments(count: Int) -> [(from: Double, to: Double, opacity: Double, width: Double)] {
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            let head = Double(index + 1) / Double(count)
            let from = tailLength * (1 - Double(index) / Double(count))
            let to = tailLength * (1 - head)
            return (from, to, 0.08 + 0.82 * pow(head, 1.6), 0.45 + 0.55 * head)
        }
    }
}

/// An account's live activity around its ring: a comet while an agent works, a pulsing attention-coloured
/// ring while one waits, nothing while idle.
///
/// Motion runs as Core Animation on the render server (no per-frame work in the app). Without live effects
/// or with Reduce Motion the same shapes are drawn still.
///
/// With live effects the orbit is one `NSView` that lives through every state, idle included, so work ending can seal
/// the circle instead of vanishing. `ImageRenderer` cannot draw an `NSViewRepresentable` (it stamps a placeholder),
/// so every off-screen render turns live effects off, which is what the still branch below is for.
public struct ActivityOrbit: View {
    let activity: AgentActivity?
    let diameter: CGFloat
    let margin: CGFloat
    let style: FinishSequence.Style

    @Environment(\.liveEffectsEnabled) private var liveEffectsEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameter style: How a finished turn settles: `.orbit` fades the sealed ring out beside a small check mark,
    ///   `.glyph` contracts it and draws the mark in the middle (session rows).
    public init(activity: AgentActivity?, diameter: CGFloat, margin: CGFloat, style: FinishSequence.Style = .orbit) {
        self.activity = activity
        self.diameter = diameter
        self.margin = margin
        self.style = style
    }

    public var body: some View {
        let side = diameter + margin * 2
        let radius = OrbitGeometry.radius(diameter: diameter, margin: margin)
        let lineWidth = OrbitGeometry.lineWidth(margin: margin)
        let animated = liveEffectsEnabled && !reduceMotion && !Motion.reducesMotion
        // Without a margin there is nowhere to draw an orbit that does not cover the ring.
        let shown = margin >= OrbitGeometry.minimumMargin ? activity : nil
        ZStack {
            if animated {
                // One view through every state, so working → idle can seal the circle instead of vanishing.
                ActivityLayerRepresentable(
                    activity: shown,
                    radius: radius,
                    lineWidth: lineWidth,
                    style: style,
                    contractedRadius: diameter / 2
                )
            } else {
                switch shown {
                case .working?:
                    StillComet(radius: radius, lineWidth: lineWidth)
                case .waiting?:
                    Circle()
                        .stroke(Theme.attention.opacity(0.7), lineWidth: lineWidth)
                        .frame(width: radius * 2, height: radius * 2)
                case .idle?, nil:
                    Color.clear
                }
            }
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The comet frozen at two o'clock, for static renders and Reduce Motion.
private struct StillComet: View {
    let radius: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let head = 0.16
            for segment in OrbitGeometry.tailSegments(count: 12) {
                var path = Path()
                path.addArc(
                    center: center,
                    radius: radius,
                    startAngle: .degrees((head - segment.from) * 360 - 90),
                    endAngle: .degrees((head - segment.to) * 360 - 90),
                    clockwise: false
                )
                context.stroke(path, with: .color(.primary.opacity(segment.opacity)), lineWidth: lineWidth * segment.width)
            }
            let point = RingGeometry.point(center: center, radius: radius, fraction: head)
            let dot = lineWidth * 0.62
            context.fill(Path(ellipseIn: CGRect(x: point.x - dot, y: point.y - dot, width: dot * 2, height: dot * 2)), with: .color(.primary.opacity(0.92)))
        }
    }
}

/// A session's state as a small glyph: a comet orbit while working, a raised hand with a pulsing ring while
/// waiting, a quiet check mark when done.
public struct ActivityGlyph: View {
    let activity: AgentActivity
    let size: CGFloat

    /// The state before the current one, so the still check mark waits for the drawn one to finish instead of
    /// appearing under it.
    @State private var previous: AgentActivity?
    @Environment(\.liveEffectsEnabled) private var liveEffectsEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.l10n) private var l10n

    public init(activity: AgentActivity, size: CGFloat) {
        self.activity = activity
        self.size = size
    }

    public var body: some View {
        let margin = size * 0.16
        let inner = size - margin * 2
        ZStack {
            switch activity {
            case .working:
                Circle()
                    .stroke(Theme.track, lineWidth: max(1, inner * 0.1))
                    .frame(width: inner * 0.9, height: inner * 0.9)
                Circle()
                    .fill(.primary.opacity(0.75))
                    .frame(width: inner * 0.3, height: inner * 0.3)
            case .waiting:
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: inner * 0.62, weight: .semibold))
                    .foregroundStyle(Theme.attention)
            case .idle:
                Image(systemName: "checkmark")
                    .font(.system(size: inner * 0.55, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: inner, height: inner)
                    .background(Circle().fill(Theme.subtleFill))
                    .transition(.opacity)
            }
            ActivityOrbit(activity: activity, diameter: inner, margin: margin, style: .glyph)
        }
        .frame(width: size, height: size)
        // The drawn check mark hands over to this one; without a finish to wait for, the state simply changes.
        .animation(idleHandover, value: activity)
        .onChange(of: activity) { old, _ in previous = old }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(UsageFormat.activity(activity, detail: nil, l10n: l10n))
    }

    /// The fade the still idle glyph appears with after a finish, and nothing at all in every other case.
    private var idleHandover: Animation? {
        guard activity == .idle, previous == .working, liveEffectsEnabled, !reduceMotion, !Motion.reducesMotion else { return nil }
        return .easeOut(duration: FinishSequence.idleRevealDuration).delay(FinishSequence.idleRevealDelay(.glyph))
    }
}

// MARK: - Core Animation

private struct ActivityLayerRepresentable: NSViewRepresentable {
    let activity: AgentActivity?
    let radius: CGFloat
    let lineWidth: CGFloat
    let style: FinishSequence.Style
    let contractedRadius: CGFloat

    func makeNSView(context: Context) -> ActivityLayerView {
        ActivityLayerView()
    }

    func updateNSView(_ view: ActivityLayerView, context: Context) {
        view.configure(radius: radius, lineWidth: lineWidth)
        view.apply(activity: activity, style: style, contractedRadius: contractedRadius)
    }
}

/// A layer-backed view whose infinite animation runs only while its window is on screen and visible,
/// and which never takes mouse events (dragging the island must keep working over it).
class LiveLayerView: NSView {
    private(set) var radius: CGFloat = 0
    private(set) var lineWidth: CGFloat = 1
    private weak var observedWindow: NSWindow?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(radius: CGFloat, lineWidth: CGFloat) {
        guard radius != self.radius || lineWidth != self.lineWidth else { return }
        self.radius = radius
        self.lineWidth = lineWidth
        // Animations capture geometry; restart them with the new one on the next layout.
        stopAnimating()
        needsLayout = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rebuild()
        CATransaction.commit()
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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }

    @objc private func occlusionChanged(_ notification: Notification) {
        updateRunning()
    }

    /// Whether the user can actually see this view: its window exists, is on screen and is not fully occluded, and
    /// nothing in the chain above it is hidden. One-shot effects check it too, so nothing plays where nobody looks.
    var isVisibleOnScreen: Bool {
        guard let window, window.isVisible, window.occlusionState.contains(.visible) else { return false }
        return !isHiddenOrHasHiddenAncestor
    }

    private func updateRunning() {
        if isVisibleOnScreen, bounds.width > 0 {
            startAnimating()
        } else {
            stopAnimating()
        }
    }

    /// Lays out sublayers for the current bounds, radius, line width and appearance.
    func rebuild() {}
    /// Adds the infinite animation if it is not running.
    func startAnimating() {}
    func stopAnimating() {}

    /// Resolves an AppKit colour for this view's appearance.
    func resolved(_ color: NSColor) -> CGColor {
        var result = color.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            result = color.cgColor
        }
        return result
    }
}
