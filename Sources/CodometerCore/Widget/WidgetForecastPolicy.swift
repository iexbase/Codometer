import Foundation

/// When a widget ring draws the forecast ghost arc — where usage lands by the reset at the pace since the window
/// started.
///
/// The island's `RingForecastPolicy` makes the same distinction for its own dials; the widget keeps its own copy
/// because the extension cannot link the app's UI module. Medium and large widgets draw every forecast; a small
/// widget's ring is 54–62 pt across and stays calm, so it shows only a forecast that runs into the limit.
///
/// The policy decides only *which* forecasts a family draws. Whether there are any at all is the user's
/// `showsForecast` setting, which the snapshot carries and `WidgetWindowState` applies.
public enum WidgetForecastPolicy: String, Hashable, Sendable, CaseIterable {
    /// Never: inner companion rings, where a second dashed arc would only add noise.
    case never
    /// Only when the forecast reaches the limit (small widgets).
    case warningsOnly
    /// Whenever there is a forecast (medium and large widgets).
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

    /// The fraction of the ring the ghost arc ends at, just short of a full turn so it never laps its own start;
    /// `nil` when nothing is drawn or the forecast adds nothing to the arc already there.
    public func arcEnd(for window: WidgetWindowState) -> Double? {
        guard draws(window.forecast), let forecast = window.forecast else { return nil }
        let end = min(forecast.projectedUsed / 100, Self.maximumArcEnd)
        return end > window.progress.used ? end : nil
    }

    /// A ghost that reached 1.0 would close the circle and read as full usage.
    public static let maximumArcEnd = 0.999
}
