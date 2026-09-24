import CodometerCore
import CodometerL10n
import SwiftUI

/// An account's usage as a dial: up to three concentric rings (session, weekly all models, the most-used
/// model week), the monochrome provider mark in the centre and the activity orbit around the rings.
///
/// The view is `diameter + 2 × orbitMargin` points square, whether or not an orbit is showing,
/// so activity never resizes anything.
///
/// On the rail and in the deck (`ceremonySurface` `.rail` / `.deck`) the gauge reports its ring box to the
/// environment's `ringAnchorSink`, when there is one.
public struct RingGauge: View {
    let presentation: AccountPresentation
    let diameter: CGFloat
    let showsSecondary: Bool
    let isHighlighted: Bool
    let maximumRings: Int
    let orbitMargin: CGFloat
    let showsActivity: Bool
    let hidesRings: Bool
    let forecastPolicy: RingForecastPolicy
    let centerMark: RingCenterMark
    let ceremonySurface: CeremonySurface?
    @Environment(\.l10n) private var l10n
    @Environment(\.ceremonyStage) private var ceremonyStage

    /// - Parameters:
    ///   - diameter: The outer diameter of the rings.
    ///   - showsSecondary: Whether inner rings may be drawn (only when the diameter leaves room for them).
    ///   - maximumRings: Upper bound for the ring count when `showsSecondary` is on.
    ///   - orbitMargin: Room reserved around the rings for the activity orbit; defaults to `diameter / 7`.
    ///   - showsActivity: Whether the orbit reflects the account's sessions.
    ///   - hidesRings: Draws the rings and the centre glyph fully transparent (the orbit stays), while flying copies
    ///     take their place. The layout never changes.
    ///   - forecastPolicy: When the forecast ghost arc is drawn.
    ///   - ceremonySurface: The surface the gauge is on, for reset ceremonies and anchor reporting. A ceremony plays
    ///     only when the environment carries a `CeremonyStage` for exactly this surface.
    public init(
        presentation: AccountPresentation,
        diameter: CGFloat,
        showsSecondary: Bool,
        isHighlighted: Bool = false,
        maximumRings: Int = RingGeometry.maximumRings,
        orbitMargin: CGFloat? = nil,
        showsActivity: Bool = true,
        hidesRings: Bool = false,
        forecastPolicy: RingForecastPolicy = .never,
        centerMark: RingCenterMark = .providerGlyph,
        ceremonySurface: CeremonySurface? = nil
    ) {
        self.presentation = presentation
        self.diameter = diameter
        self.showsSecondary = showsSecondary
        self.isHighlighted = isHighlighted
        self.maximumRings = maximumRings
        self.orbitMargin = orbitMargin ?? Self.defaultOrbitMargin(diameter: diameter)
        self.showsActivity = showsActivity
        self.hidesRings = hidesRings
        self.forecastPolicy = forecastPolicy
        self.centerMark = centerMark
        self.ceremonySurface = ceremonySurface
    }

    /// The orbit margin used when the caller passes none: 4 pt for a 28 pt rail dial.
    public static func defaultOrbitMargin(diameter: CGFloat) -> CGFloat {
        max(2, diameter / 7)
    }

    public var body: some View {
        // Only the surface the gauge is on may celebrate, and only a stale-free ring shows a forecast.
        let stage = ceremonyStage.flatMap { $0.surface == ceremonySurface ? $0 : nil }
        let specs = RingGeometry.specs(
            headline: presentation.headline,
            windows: presentation.windows,
            maximumRings: showsSecondary ? maximumRings : 1,
            diameter: diameter,
            forecastPolicy: presentation.isStale ? .never : forecastPolicy,
            ceremonies: stage?.ceremonies(of: presentation.id) ?? [:]
        )
        RingStack(
            specs: specs,
            diameter: diameter,
            orbitMargin: orbitMargin,
            isStale: presentation.isStale,
            activity: showsActivity ? presentation.activity : nil,
            hidesRings: hidesRings,
            ceremonySurface: stage == nil ? nil : ceremonySurface
        ) {
            RingCenter(mark: centerMark, presentation: presentation)
        }
        .modifier(RingAnchorReporter(accountID: presentation.id, surface: ceremonySurface, inset: orbitMargin))
        .scaleEffect(isHighlighted ? 1.1 : 1)
        .animation(Motion.snappy, value: isHighlighted)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let details = Self.accessibilityDetails(
            presentation: presentation,
            forecastPolicy: presentation.isStale ? .never : forecastPolicy,
            celebrates: ceremonyStage.map { $0.surface == ceremonySurface && !$0.ceremonies(of: presentation.id).isEmpty } ?? false,
            l10n: l10n
        )
        return ([presentation.status.profile.label.value] + details).joined(separator: ", ")
    }

    /// What a dial says after the account's name: its headline usage ("57% used", or "No data" without a reading),
    /// the forecast ghost when one is drawn, the green flash while it plays, and what agents are doing.
    ///
    /// Every drawn hint gets words: colour and motion are never the only signal.
    static func accessibilityDetails(
        presentation: AccountPresentation,
        forecastPolicy: RingForecastPolicy = .never,
        celebrates: Bool = false,
        l10n: Localizer
    ) -> [String] {
        var details = [presentation.headline.map { l10n.rail.usedA11y(l10n.format.percent($0.primary.used.value)) } ?? l10n.common.noData]
        if let phrase = forecastPhrase(presentation: presentation, forecastPolicy: forecastPolicy, l10n: l10n) {
            details.append(phrase)
        }
        if celebrates {
            details.append(l10n.motion.justResetA11y)
        }
        if let activity = presentation.activity, activity != .idle {
            details.append(UsageFormat.activity(activity, detail: nil, l10n: l10n))
        }
        return details
    }

    /// The headline window's forecast in words, when the policy actually draws it.
    static func forecastPhrase(presentation: AccountPresentation, forecastPolicy: RingForecastPolicy, l10n: Localizer) -> String? {
        guard let headline = presentation.headline,
              let window = presentation.windows.first(where: { $0.isMainBucket && $0.window.id == headline.primary.id }),
              let forecast = window.forecast,
              forecastPolicy.arcEnd(used: window.progress.used, forecast: forecast) != nil
        else { return nil }
        return forecast.reachesLimit
            ? l10n.motion.forecastRunsOutA11y
            : l10n.motion.forecastA11y(l10n.format.percent(forecast.projectedUsed))
    }
}

/// What sits in the middle of a dial.
public enum RingCenterMark: Hashable, Sendable {
    /// The provider's mark, monochrome. What a dial shows when the provider alone identifies the account.
    case providerGlyph
    /// The account's monogram, in the same monochrome weight. Used where two accounts share a provider and the
    /// glyph would be the same on both.
    case monogram
}

/// The dial's centre: the provider's mark, or the account's monogram where that no longer tells accounts apart.
///
/// Monochrome either way — the account's colour lives on its dot and badge, never inside a ring.
struct RingCenter: View {
    let mark: RingCenterMark
    let presentation: AccountPresentation

    var body: some View {
        Group {
            switch mark {
            case .providerGlyph:
                ProviderGlyph(provider: presentation.provider, tinted: false)
            case .monogram:
                GeometryReader { proxy in
                    let side = min(proxy.size.width, proxy.size.height)
                    Text(verbatim: Self.initial(of: presentation.style.monogram))
                        .font(.system(size: max(IslandMetrics.minimumTextSize, side * 0.86), weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
        }
        .foregroundStyle(presentation.isStale ? .tertiary : .secondary)
    }

    /// A rail ring has room for one character; a two-letter monogram shows its first.
    nonisolated static func initial(of monogram: AccountMonogram) -> String {
        monogram.value.first.map(String.init) ?? monogram.value
    }
}

/// Concentric rings drawn from `RingSpec`s with the ring grammar: gradient arc, "now" notch,
/// glow where usage runs ahead of time, tick marks, a dotted grey look for stale data.
public struct RingStack<Center: View>: View {
    let specs: [RingSpec]
    let diameter: CGFloat
    let orbitMargin: CGFloat
    let isStale: Bool
    let activity: AgentActivity?
    let hidesRings: Bool
    /// Non-`nil` only when this stack may celebrate a reset; the stage in the environment says how.
    let ceremonySurface: CeremonySurface?
    let center: Center

    @Environment(\.ceremonyStage) private var ceremonyStage
    @Environment(\.liveEffectsEnabled) private var liveEffectsEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameter hidesRings: Rings and centre at opacity 0 (the orbit stays), without any layout change.
    public init(
        specs: [RingSpec],
        diameter: CGFloat,
        orbitMargin: CGFloat,
        isStale: Bool,
        activity: AgentActivity?,
        hidesRings: Bool = false,
        ceremonySurface: CeremonySurface? = nil,
        @ViewBuilder center: () -> Center
    ) {
        self.specs = specs
        self.diameter = diameter
        self.orbitMargin = orbitMargin
        self.isStale = isStale
        self.activity = activity
        self.hidesRings = hidesRings
        self.ceremonySurface = ceremonySurface
        self.center = center()
    }

    public var body: some View {
        let geometry = RingGeometry(diameter: diameter, count: max(1, specs.count))
        let side = diameter + orbitMargin * 2
        ZStack {
            ZStack {
                if specs.isEmpty, let ring = geometry.rings.first {
                    EmptyRing(ring: ring)
                }
                ForEach(Array(zip(specs, geometry.rings)), id: \.0.id) { spec, ring in
                    RingLayer(spec: spec, ring: ring, isStale: isStale)
                }
                center
                    .frame(width: geometry.innerRadius * 1.12, height: geometry.innerRadius * 1.12)
            }
            .opacity(hidesRings ? 0 : 1)
            if celebrates, let stage = ceremonyStage {
                ceremonies(stage: stage, geometry: geometry)
            }
            ActivityOrbit(activity: activity, diameter: diameter, margin: orbitMargin)
        }
        .frame(width: diameter, height: diameter)
        .frame(width: side, height: side)
    }

    /// A reset is celebrated only on a live, visible surface that asked for it, and never while the rings are hidden
    /// by a ring flight. Reduce Motion keeps the green ring and drops the glint and the swell.
    private var celebrates: Bool {
        ceremonySurface != nil && liveEffectsEnabled && !hidesRings
    }

    @ViewBuilder
    private func ceremonies(stage: CeremonyStage, geometry: RingGeometry) -> some View {
        let reduced = reduceMotion || Motion.reducesMotion
        ForEach(Array(zip(specs, geometry.rings).enumerated()), id: \.element.0.id) { index, pair in
            if let ceremony = pair.0.ceremony {
                ResetCeremonyRing(
                    ceremony: ceremony,
                    ring: pair.1,
                    fraction: min(max(pair.0.progress.used, 0), 1),
                    delay: Double(index) * ResetCeremonyPlan.ringStagger,
                    reduceMotion: reduced,
                    onPlayed: { id in stage.markPlayed(id, stage.surface) }
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}

/// A dotted track for an account without data.
private struct EmptyRing: View {
    let ring: RingGeometry.Ring

    var body: some View {
        Circle()
            .stroke(
                Color.primary.opacity(0.22),
                style: StrokeStyle(lineWidth: ring.lineWidth * 0.55, lineCap: .round, dash: [0.01, ring.lineWidth * 1.4])
            )
            .frame(width: ring.radius * 2, height: ring.radius * 2)
    }
}

/// One ring. The arc animates only when usage changes (never on appear). The notch follows the clock without
/// animating: a tick moves it by a fraction of a point, and animating that would redraw every ring for most
/// of a second twice a minute.
private struct RingLayer: View {
    let spec: RingSpec
    let ring: RingGeometry.Ring
    let isStale: Bool

    @Environment(\.introAnimationsEnabled) private var animationsEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RingCanvas(
            used: spec.progress.used,
            elapsed: spec.progress.elapsed ?? -1,
            tickCount: spec.progress.tickCount,
            band: spec.band,
            forecast: spec.forecast,
            forecastBand: spec.forecastBand,
            ring: ring,
            isStale: isStale
        )
        .animation(animationsEnabled && !reduceMotion ? Motion.gauge : nil, value: spec.progress.used)
    }
}

private struct RingCanvas: View, Animatable {
    var used: Double
    /// Negative when unknown.
    var elapsed: Double
    let tickCount: Int
    let band: UsageBand
    /// Where the ghost arc ends; `nil` draws none. Never animated: its start follows the animated `used`, so it
    /// slides with the arc without redrawing on its own.
    let forecast: Double?
    let forecastBand: UsageBand?
    let ring: RingGeometry.Ring
    let isStale: Bool

    @Environment(\.colorScheme) private var colorScheme

    nonisolated var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(used, elapsed) }
        set {
            used = newValue.first
            elapsed = newValue.second
        }
    }

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = ring.radius
        let width = ring.lineWidth
        let knownElapsed: Double? = elapsed >= 0 ? elapsed : nil
        let fraction = min(max(used, 0), 1)
        let colors = Theme.colors(for: band)

        context.drawLayer { layer in
            // Track.
            let track = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            if isStale {
                layer.stroke(track, with: .color(.primary.opacity(0.22)), style: StrokeStyle(lineWidth: width * 0.5, lineCap: .round, dash: [0.01, width * 1.3]))
            } else {
                layer.stroke(track, with: .color(Theme.track), lineWidth: width)
            }

            // The ghost: where usage lands by the reset at this pace. Dashed, so it stays a hint even where
            // colour is taken away, and never on stale data, whose numbers are already out of date.
            if !isStale, let forecast, forecast > fraction {
                let ghost = arcPath(center: center, radius: radius, from: fraction, to: forecast)
                layer.stroke(
                    ghost,
                    with: .color(Theme.tint(for: forecastBand ?? band).opacity(RingGeometry.ghostOpacity(dark: colorScheme == .dark))),
                    style: StrokeStyle(
                        lineWidth: width * 0.42,
                        lineCap: .round,
                        dash: [max(1.2, width * 0.55), max(1.6, width * 0.7)]
                    )
                )
            }

            // Used arc.
            if fraction > 0.001 {
                let arc = arcPath(center: center, radius: radius, from: 0, to: fraction)
                let style = StrokeStyle(lineWidth: width, lineCap: fraction >= 0.999 ? .butt : .round)
                let shading = isStale ? GraphicsContext.Shading.color(Theme.staleData) : arcShading(colors: colors, fraction: fraction, center: center, radius: radius, width: width)
                if !isStale, let overrun = RingGeometry.overrunRange(used: fraction, elapsed: knownElapsed) {
                    // Glow only where usage runs ahead of time.
                    layer.drawLayer { glow in
                        glow.addFilter(.shadow(color: colors[1].opacity(0.85), radius: width * 0.75))
                        glow.stroke(arcPath(center: center, radius: radius, from: overrun.lowerBound, to: overrun.upperBound), with: shading, style: StrokeStyle(lineWidth: width, lineCap: .round))
                    }
                }
                layer.stroke(arc, with: shading, style: style)
            }

            // Cuts: ticks and the "now" notch let the glass show through.
            layer.blendMode = .destinationOut
            if RingGeometry.showsTicks(lineWidth: width) {
                let dot = max(0.7, width * 0.15)
                for tick in RingGeometry.tickFractions(count: tickCount) {
                    let point = RingGeometry.point(center: center, radius: radius, fraction: tick)
                    layer.fill(Path(ellipseIn: CGRect(x: point.x - dot, y: point.y - dot, width: dot * 2, height: dot * 2)), with: .color(.black))
                }
            }
            if let knownElapsed, RingGeometry.showsNotch(elapsed: knownElapsed) {
                let notch = RingGeometry.notchWidth(lineWidth: width)
                let length = width + 2
                let rect = CGRect(x: -notch / 2, y: -length / 2, width: notch, height: length)
                let point = RingGeometry.point(center: center, radius: radius, fraction: knownElapsed)
                let transform = CGAffineTransform(translationX: point.x, y: point.y)
                    .rotated(by: CGFloat(knownElapsed * 2 * .pi))
                layer.fill(Path(roundedRect: rect, cornerRadius: notch / 2).applying(transform), with: .color(.black))
            }
        }
    }

    private func arcPath(center: CGPoint, radius: CGFloat, from start: Double, to end: Double) -> Path {
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(start * 360 - 90),
            endAngle: .degrees(end * 360 - 90),
            clockwise: false
        )
        return path
    }

    /// A conic gradient stretched over the arc only, starting slightly before 12 o'clock so the round
    /// start cap takes the light colour instead of wrapping around to the deep one.
    private func arcShading(colors: [Color], fraction: Double, center: CGPoint, radius: CGFloat, width: CGFloat) -> GraphicsContext.Shading {
        let cap = radius > 0 ? Double(width / 2 / (2 * .pi * radius)) : 0
        let end = min(0.999, max(fraction + cap, cap * 2 + 0.01))
        let gradient = Gradient(stops: [
            .init(color: colors[0], location: 0),
            .init(color: colors[0], location: min(cap, end)),
            .init(color: colors[1], location: end),
            .init(color: colors[1], location: 1),
        ])
        return .conicGradient(gradient, center: center, angle: .degrees(-90 - cap * 360))
    }
}

/// A capsule usage bar: gradient fill, "now" notch, glow where usage runs ahead of time.
public struct UsageBar: View {
    let fraction: Double
    let band: UsageBand
    let height: CGFloat
    let elapsed: Double?
    let isStale: Bool
    let forecast: Double?
    let forecastBand: UsageBand?

    @Environment(\.introAnimationsEnabled) private var animationsEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameter forecast: Where the dashed ghost ends, as a fraction of the bar; `nil` draws none.
    public init(
        fraction: Double,
        band: UsageBand,
        height: CGFloat,
        elapsed: Double? = nil,
        isStale: Bool = false,
        forecast: Double? = nil,
        forecastBand: UsageBand? = nil
    ) {
        self.fraction = fraction
        self.band = band
        self.height = height
        self.elapsed = elapsed
        self.isStale = isStale
        self.forecast = forecast
        self.forecastBand = forecastBand
    }

    public var body: some View {
        BarCanvas(fraction: fraction, elapsed: elapsed ?? -1, band: band, isStale: isStale, forecast: forecast, forecastBand: forecastBand)
            .frame(height: height)
            // Like rings: only a usage change animates, never the notch following the clock.
            .animation(animationsEnabled && !reduceMotion ? Motion.gauge : nil, value: fraction)
            .accessibilityHidden(true)
    }
}

private struct BarCanvas: View, Animatable {
    var fraction: Double
    var elapsed: Double
    let band: UsageBand
    let isStale: Bool
    let forecast: Double?
    let forecastBand: UsageBand?

    @Environment(\.colorScheme) private var colorScheme

    nonisolated var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(fraction, elapsed) }
        set {
            fraction = newValue.first
            elapsed = newValue.second
        }
    }

    var body: some View {
        Canvas { context, size in
            let height = size.height
            let radius = height / 2
            let colors = Theme.colors(for: band)
            let used = min(max(fraction, 0), 1)
            let knownElapsed: Double? = elapsed >= 0 ? elapsed : nil
            context.drawLayer { layer in
                layer.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: radius), with: .color(Theme.track))
                // The same ghost as the rings: a dashed extension from the used end to the forecast.
                if !isStale, let forecast, forecast > used {
                    let start = size.width * used
                    let line = Path { path in
                        path.move(to: CGPoint(x: start, y: height / 2))
                        path.addLine(to: CGPoint(x: size.width * min(forecast, 1), y: height / 2))
                    }
                    layer.stroke(
                        line,
                        with: .color(Theme.tint(for: forecastBand ?? band).opacity(RingGeometry.ghostOpacity(dark: colorScheme == .dark))),
                        style: StrokeStyle(
                            lineWidth: height * 0.42,
                            lineCap: .round,
                            dash: [max(1.2, height * 0.55), max(1.6, height * 0.7)]
                        )
                    )
                }
                if used > 0.001 {
                    let width = max(height, size.width * used)
                    let rect = CGRect(x: 0, y: 0, width: width, height: height)
                    let shading: GraphicsContext.Shading = isStale
                        ? .color(Theme.staleData)
                        : .linearGradient(Gradient(colors: colors), startPoint: .zero, endPoint: CGPoint(x: max(size.width * 0.6, width), y: 0))
                    if !isStale, let overrun = RingGeometry.overrunRange(used: used, elapsed: knownElapsed) {
                        layer.drawLayer { glow in
                            glow.addFilter(.shadow(color: colors[1].opacity(0.8), radius: height * 0.7))
                            let start = size.width * overrun.lowerBound
                            glow.fill(Path(roundedRect: CGRect(x: start, y: 0, width: max(height, width - start), height: height), cornerRadius: radius), with: shading)
                        }
                    }
                    layer.fill(Path(roundedRect: rect, cornerRadius: radius), with: shading)
                }
                if let knownElapsed, RingGeometry.showsNotch(elapsed: knownElapsed) {
                    let notch = max(1.5, height * 0.3)
                    let x = min(max(size.width * knownElapsed, radius), size.width - radius)
                    layer.blendMode = .destinationOut
                    layer.fill(Path(CGRect(x: x - notch / 2, y: -1, width: notch, height: height + 2)), with: .color(.black))
                }
            }
        }
    }
}

/// A small capsule with an icon and short text, e.g. the time until a reset.
public struct InfoChip: View {
    let systemImage: String
    let text: String
    var tint: Color = .secondary
    let metrics: IslandMetrics

    public init(systemImage: String, text: String, tint: Color = .secondary, metrics: IslandMetrics) {
        self.systemImage = systemImage
        self.text = text
        self.tint = tint
        self.metrics = metrics
    }

    public var body: some View {
        HStack(spacing: 4 * metrics.scale) {
            Image(systemName: systemImage)
                .font(metrics.font(TextSize.badge, .semibold))
            Text(text)
                .font(metrics.digits(TextSize.caption, .medium))
                .lineLimit(1)
                .contentTransition(.numericText())
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8 * metrics.scale)
        .padding(.vertical, 3.5 * metrics.scale)
        .background(Capsule().fill(Theme.subtleFill))
    }
}
