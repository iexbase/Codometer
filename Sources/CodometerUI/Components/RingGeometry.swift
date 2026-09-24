import CodometerCore
import CoreGraphics
import Foundation

/// When a dial draws the forecast ghost arc (where usage lands by the reset at the current pace).
public enum RingForecastPolicy: Hashable, Sendable {
    /// Never (menu bar icon, settings cards).
    case never
    /// Only when the forecast reaches the limit (rail dials, the small widget).
    case warningsOnly
    /// Whenever there is a forecast (deck dials, the floating card, medium and large widgets).
    case always

    /// Whether this policy draws `forecast`.
    public func draws(_ forecast: UsageForecast?) -> Bool {
        guard let forecast else { return false }
        switch self {
        case .never: return false
        case .warningsOnly: return forecast.reachesLimit
        case .always: return true
        }
    }

    /// Where the ghost arc ends, as a fraction of a turn, or `nil` when nothing is drawn or the ghost would add
    /// nothing to the arc that is already there.
    public func arcEnd(used: Double, forecast: UsageForecast?) -> Double? {
        guard draws(forecast), let forecast else { return nil }
        let end = min(forecast.projectedUsed / 100, Self.maximumArcEnd)
        return end > used ? end : nil
    }

    /// A ghost that reached a full turn would close the circle and read as full usage.
    public static let maximumArcEnd = 0.999
}

/// One ring of a dial: a window's progress, the band it is coloured by, the forecast ghost ahead of its arc and the
/// reset it is celebrating.
public struct RingSpec: Hashable, Sendable, Identifiable {
    public let id: String
    public let progress: WindowProgress
    public let band: UsageBand
    /// Where the ghost arc ends, 0…`RingForecastPolicy.maximumArcEnd`; `nil` draws none.
    public let forecast: Double?
    /// The band the ghost is drawn in; `nil` with no ghost.
    public let forecastBand: UsageBand?
    /// The reset this ring celebrates, while one is live and this surface has not played it.
    public let ceremony: ResetCeremony?

    public init(
        id: String,
        progress: WindowProgress,
        band: UsageBand,
        forecast: Double? = nil,
        forecastBand: UsageBand? = nil,
        ceremony: ResetCeremony? = nil
    ) {
        self.id = id
        self.progress = progress
        self.band = band
        self.forecast = forecast
        self.forecastBand = forecastBand
        self.ceremony = ceremony
    }

    init(_ window: WindowPresentation, forecastPolicy: RingForecastPolicy, ceremony: ResetCeremony?) {
        let end = forecastPolicy.arcEnd(used: window.progress.used, forecast: window.forecast)
        self.init(
            id: window.id,
            progress: window.progress,
            band: window.band,
            forecast: end,
            forecastBand: end == nil ? nil : window.forecast?.band,
            ceremony: ceremony
        )
    }
}

/// Stroke geometry for up to three concentric rings inside a dial of a given diameter.
///
/// The outermost ring is the primary one and the thickest; inner rings are thinner and separated by a gap.
public struct RingGeometry: Equatable, Sendable {
    public struct Ring: Equatable, Sendable {
        /// Radius of the stroke's centre line.
        public let radius: CGFloat
        public let lineWidth: CGFloat
    }

    /// The smallest dial that has room for a second ring.
    public static let minimumDiameterForTwoRings: CGFloat = 34
    /// The smallest dial that has room for a third ring.
    public static let minimumDiameterForThreeRings: CGFloat = 42
    public static let maximumRings = 3

    public let diameter: CGFloat
    public let rings: [Ring]
    public let gap: CGFloat

    public init(diameter: CGFloat, count: Int) {
        let diameter = max(0, diameter)
        let count = min(max(1, count), Self.capacity(diameter: diameter))
        let primary: CGFloat
        let inner: CGFloat
        let gap: CGFloat
        switch count {
        case 1:
            primary = max(3, diameter * 0.11)
            inner = 0
            gap = 0
        case 2:
            primary = max(3, diameter * 0.1)
            inner = max(2, diameter * 0.078)
            gap = max(1.5, diameter * 0.04)
        default:
            primary = max(3, diameter * 0.095)
            inner = max(2, diameter * 0.07)
            gap = max(1.5, diameter * 0.036)
        }
        var rings: [Ring] = []
        var outerEdge = diameter / 2
        for index in 0..<count {
            let width = index == 0 ? primary : inner
            let radius = outerEdge - width / 2
            rings.append(Ring(radius: max(0, radius), lineWidth: width))
            outerEdge = radius - width / 2 - gap
        }
        self.diameter = diameter
        self.rings = rings
        self.gap = gap
    }

    /// How many rings a dial of this diameter can hold legibly.
    public static func capacity(diameter: CGFloat) -> Int {
        if diameter >= minimumDiameterForThreeRings { return 3 }
        if diameter >= minimumDiameterForTwoRings { return 2 }
        return 1
    }

    /// Free radius inside the innermost ring, for the provider glyph.
    public var innerRadius: CGFloat {
        guard let last = rings.last else { return diameter / 2 }
        return max(0, last.radius - last.lineWidth / 2)
    }

    /// How visible the forecast ghost is: a hint, well under the used arc's weight, stronger on dark surfaces
    /// where a faint colour disappears.
    public static func ghostOpacity(dark: Bool) -> Double {
        dark ? 0.42 : 0.34
    }

    /// Width of the "now" notch cut into a ring of this line width.
    public static func notchWidth(lineWidth: CGFloat) -> CGFloat {
        max(1.25, lineWidth * 0.3)
    }

    /// The notch is left out right at the window's start and end, where it would read as a gap in the arc.
    public static func showsNotch(elapsed: Double?) -> Bool {
        guard let elapsed else { return false }
        return elapsed > 0.015 && elapsed < 0.985
    }

    /// Where usage runs ahead of time: from the notch to the arc's end, or `nil` when it does not.
    public static func overrunRange(used: Double, elapsed: Double?) -> ClosedRange<Double>? {
        guard let elapsed, showsNotch(elapsed: elapsed) else { return nil }
        let end = min(max(used, 0), 1)
        guard end - elapsed > 0.01 else { return nil }
        return elapsed...end
    }

    /// Day ticks along a weekly ring, as fractions of a turn; the start (12 o'clock) is left out.
    /// Shorter windows get none: hour ticks on a session ring read as noise at dial sizes.
    public static func tickFractions(count: Int) -> [Double] {
        guard count >= 7 else { return [] }
        return (1..<count).map { Double($0) / Double(count) }
    }

    /// Ticks only on rings thick enough to show them.
    public static func showsTicks(lineWidth: CGFloat) -> Bool {
        lineWidth >= 3.5
    }

    /// A point on a circle for a fraction of a turn, clockwise from 12 o'clock, in a y-down coordinate space.
    public static func point(center: CGPoint, radius: CGFloat, fraction: Double) -> CGPoint {
        let angle = (fraction * 360 - 90) * Double.pi / 180
        return CGPoint(x: center.x + radius * CGFloat(cos(angle)), y: center.y + radius * CGFloat(sin(angle)))
    }

    /// The rings a dial shows for an account: the primary window, then (when room allows and the caller asks
    /// for more than one) the weekly all-models window and the most-used model-scoped weekly window.
    /// A window never appears twice.
    ///
    /// - Parameters:
    ///   - forecastPolicy: Which forecasts become a ghost arc on these rings.
    ///   - ceremonies: Live reset ceremonies of this account's main bucket, keyed `"<bucketID>/<windowID>"`. Only the
    ///     rings' own windows can celebrate; other buckets are ignored.
    public static func specs(
        headline: HeadlineWindows?,
        windows: [WindowPresentation],
        maximumRings: Int,
        diameter: CGFloat,
        forecastPolicy: RingForecastPolicy = .never,
        ceremonies: [String: ResetCeremony] = [:]
    ) -> [RingSpec] {
        guard let headline else { return [] }
        let limit = min(max(1, maximumRings), capacity(diameter: diameter))
        let candidates: [LimitWindow?] = [headline.primary, headline.secondary, headline.modelWeekly]
        var seen = Set<String>()
        var specs: [RingSpec] = []
        for case let window? in candidates where specs.count < limit {
            guard seen.insert(window.id).inserted,
                  let presentation = windows.first(where: { $0.isMainBucket && $0.window.id == window.id })
            else { continue }
            specs.append(RingSpec(presentation, forecastPolicy: forecastPolicy, ceremony: ceremonies[presentation.id]))
        }
        return specs
    }
}
