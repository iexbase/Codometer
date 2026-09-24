import CodometerCore
import Foundation

/// Something the user should know about the app's own data, shown by `AppNoticeBanner` until dismissed.
public enum AppNotice: Hashable, Sendable, Identifiable {
    /// `settings.json` was unreadable and moved aside under `backupFileName`; the app started with fresh settings.
    case settingsRecovered(backupFileName: String)
    /// `count` unusable values were replaced by defaults (a backup of the original was written first).
    case settingsRepaired(count: Int)
    /// The settings come from a newer Codometer: changes last for this session only.
    case settingsReadOnly(version: Int)
    /// History is not in its normal state.
    case history(HistoryHealth)

    /// One notice per kind: a newer notice of the same kind replaces the older one.
    public var id: String {
        switch self {
        case .settingsRecovered: "settingsRecovered"
        case .settingsRepaired: "settingsRepaired"
        case .settingsReadOnly: "settingsReadOnly"
        case .history: "history"
        }
    }
}
