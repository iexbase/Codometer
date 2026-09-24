import Foundation

/// How the medium and large desktop widgets arrange an account's limits. The small widget always draws a ring.
///
/// The user's choice lives in `GeneralSettings.widgetLayout`, travels to the extension inside the snapshot, and is a
/// significant change for the export policy, so switching in Settings reaches the desktop within a minute.
public enum WidgetLayout: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Usage rings with a number inside, one per account (the original look).
    case rings
    /// A wide strip: the weekly window as a headline of what is left, and a compact chip for every other window.
    case strip

    public var id: String { rawValue }
}
