#if DEBUG
import Foundation

/// Commands the debug scenario harness sends to every deck on screen (DEBUG builds only): which page to show and
/// which range the «Хронология» page covers. Posted on the main thread with the raw value under `valueKey`.
public enum DebugDeckCommands {
    /// `valueKey` holds a page's raw value: "overview" or "timeline".
    public static let showPage = Notification.Name("Codometer.debug.deck.showPage")
    /// `valueKey` holds an `AnalyticsRange` raw value: "fiveHours", "day" or "week".
    public static let showRange = Notification.Name("Codometer.debug.deck.showRange")
    public static let valueKey = "value"

    /// Raw values `showPage` accepts.
    public static var pageNames: Set<String> { Set(DeckPage.allCases.map(\.rawValue)) }
    /// Raw values `showRange` accepts.
    public static var rangeNames: Set<String> { Set(AnalyticsRange.allCases.map(\.rawValue)) }

    static func value(of notification: Notification) -> String? {
        notification.userInfo?[valueKey] as? String
    }
}
#endif
