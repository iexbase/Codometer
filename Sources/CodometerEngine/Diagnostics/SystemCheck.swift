import CodometerClaude
import CodometerCodex
import CodometerCore
import CodometerPlatform
import Darwin
import Foundation

/// Builds the items of "Check System" that the engine can answer: executables, profiles, history integrity, file
/// modes and network. The app adds its own items (notifications, login item, shortcut, widget, displays).
///
/// Every check is one `lstat`, one bounded read or one interruptible SQLite pragma, and the whole run is bounded by
/// `budget`. Details are technical English and never carry a profile,
/// project or session name.
enum SystemCheck {
    /// The whole check finishes inside this, however slow one step is.
    static let budget: TimeInterval = 10
    /// `PRAGMA quick_check(1)` is interrupted after this long; the item then says the check did not finish.
    static let historyTimeout: TimeInterval = 3
    static let privateDirectoryMode: mode_t = 0o700
    static let privateFileMode: mode_t = 0o600

    /// Whether a profile looks signed in, as far as the filesystem can tell.
    enum SignInState: Equatable {
        case signedIn
        case signedOut
        case unreadable(String)
        /// Not something this provider can be asked about.
        case unknown
    }

    // MARK: - Items

    /// One provider CLI, from every install location's inspection.
    ///
    /// `ok` when a trusted copy is there, `warning` when only untrusted or unsigned copies are (the app refuses to
    /// run those), `failure` when none exists at all.
    static func executableItem(
        kind: SystemCheckItemKind,
        inspections: [CandidateInspection],
        diagnostics: ExecutableDiagnostics?
    ) -> SystemCheckReport.Item {
        let present = inspections.filter(\.exists)
        let trusted = present.first(where: \.isTrusted)
        let status: SystemCheckReport.Item.Status
        var detail: String
        if let trusted {
            status = .ok
            detail = diagnostics?.displayPath ?? trusted.url.lastPathComponent
            if case .trusted(let publisher, let teamID) = trusted.signature {
                detail += ", signed by \(publisher) (\(teamID))" // l10n-ignore: support report
            }
            if let version = diagnostics?.version {
                detail += ", version \(version)" // l10n-ignore: support report
            } else {
                detail += ", version unknown" // l10n-ignore: support report
            }
        } else if present.isEmpty {
            status = .failure
            detail = "not installed in any known location" // l10n-ignore: support report
        } else {
            status = .warning
            detail = "found, but not signed by the expected publisher: \(summary(of: present))" // l10n-ignore: support report
        }
        if trusted != nil, present.count > 1 {
            detail += ", \(present.count - 1) other cop\(present.count == 2 ? "y" : "ies") installed" // l10n-ignore: support report
        }
        return SystemCheckReport.Item(id: kind.rawValue, status: status, kind: kind, detail: detail)
    }

    /// One account's profile directory. The detail never names the directory: the id carries the account, and the
    /// account is what support needs.
    static func profileItem(
        id: String,
        kind: SystemCheckItemKind,
        directory: URL,
        signIn: SignInState
    ) -> SystemCheckReport.Item {
        var info = stat()
        guard lstat(directory.path, &info) == 0 else {
            return SystemCheckReport.Item(id: id, status: .failure, kind: kind, detail: "directory is missing") // l10n-ignore: support report
        }
        if (info.st_mode & S_IFMT) == S_IFLNK {
            return SystemCheckReport.Item(id: id, status: .failure, kind: kind, detail: "a symbolic link, which the app refuses to follow") // l10n-ignore: support report
        }
        guard (info.st_mode & S_IFMT) == S_IFDIR else {
            return SystemCheckReport.Item(id: id, status: .failure, kind: kind, detail: "not a directory") // l10n-ignore: support report
        }
        guard access(directory.path, R_OK | X_OK) == 0 else {
            return SystemCheckReport.Item(id: id, status: .failure, kind: kind, detail: "not readable") // l10n-ignore: support report
        }
        return switch signIn {
        case .signedIn:
            SystemCheckReport.Item(id: id, status: .ok, kind: kind, detail: "readable, signed in") // l10n-ignore: support report
        case .signedOut:
            SystemCheckReport.Item(id: id, status: .warning, kind: kind, detail: "readable, but the profile is not signed in") // l10n-ignore: support report
        case .unreadable(let reason):
            SystemCheckReport.Item(id: id, status: .warning, kind: kind, detail: "readable, sign-in state unknown: \(reason)") // l10n-ignore: support report
        case .unknown:
            SystemCheckReport.Item(id: id, status: .ok, kind: kind, detail: "readable") // l10n-ignore: support report
        }
    }

    /// Permissions of one of the app's own files or folders.
    static func modeItem(
        id: String,
        kind: SystemCheckItemKind,
        url: URL,
        expected: mode_t
    ) -> SystemCheckReport.Item {
        guard let mode = posixMode(of: url) else {
            let missing = kind == .settingsPermissions ? "settings file is missing" : "data folder is missing" // l10n-ignore: support report
            return SystemCheckReport.Item(id: id, status: .warning, kind: kind, detail: missing)
        }
        let text = String(format: "%04o", Int(mode)) // l10n-ignore: support report
        guard mode == expected else {
            let wanted = String(format: "%04o", Int(expected)) // l10n-ignore: support report
            return SystemCheckReport.Item(
                id: id,
                status: .warning,
                kind: kind,
                detail: "mode \(text), expected \(wanted)" // l10n-ignore: support report
            )
        }
        return SystemCheckReport.Item(id: id, status: .ok, kind: kind, detail: "mode \(text)") // l10n-ignore: support report
    }

    /// The history database: integrity plus the schema state the store reported.
    static func historyItem(quickCheck: Bool?, diagnostics: HistoryDiagnostics) -> SystemCheckReport.Item {
        let id = SystemCheckItemKind.historyDatabase.rawValue
        switch diagnostics.health {
        case .unavailable(let reason):
            return SystemCheckReport.Item(id: id, status: .failure, kind: .historyDatabase, detail: "not open: \(reason)") // l10n-ignore: support report
        case .readOnlyNewerSchema:
            return SystemCheckReport.Item(
                id: id,
                status: .warning,
                kind: .historyDatabase,
                detail: "written by a newer Codometer; open read-only" // l10n-ignore: support report
            )
        case .recoveredFromCorruption:
            return SystemCheckReport.Item(
                id: id,
                status: .warning,
                kind: .historyDatabase,
                detail: "the previous file was damaged and was moved aside" // l10n-ignore: support report
            )
        case .writesPaused:
            return SystemCheckReport.Item(id: id, status: .warning, kind: .historyDatabase, detail: "writes are paused (no space)") // l10n-ignore: support report
        case .ok:
            break
        }
        let size = diagnostics.fileBytes.map { ", \($0 / 1_024) KiB" } ?? "" // l10n-ignore: support report
        return switch quickCheck {
        case true:
            SystemCheckReport.Item(id: id, status: .ok, kind: .historyDatabase, detail: "integrity check passed\(size)") // l10n-ignore: support report
        case false:
            SystemCheckReport.Item(id: id, status: .failure, kind: .historyDatabase, detail: "integrity check failed") // l10n-ignore: support report
        default:
            SystemCheckReport.Item(id: id, status: .note, kind: .historyDatabase, detail: "integrity check did not finish\(size)") // l10n-ignore: support report
        }
    }

    static func networkItem(isOnline: Bool) -> SystemCheckReport.Item {
        SystemCheckReport.Item(
            id: SystemCheckItemKind.network.rawValue,
            status: isOnline ? .ok : .warning,
            kind: .network,
            detail: isOnline ? "a network path is available" : "offline" // l10n-ignore: support report
        )
    }

    // MARK: - Helpers

    /// The permission bits of a file or folder, without following a final symbolic link.
    static func posixMode(of url: URL) -> mode_t? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        return info.st_mode & 0o7777
    }

    /// Item ids stay unique per account and carry the account id, which the report redacts into "Account N".
    static func profileItemID(kind: SystemCheckItemKind, accountID: AccountID) -> String {
        "\(kind.rawValue).\(accountID.description)"
    }

    /// Why a profile's sign-in state could not be read, without the file's path.
    ///
    /// `FileAccessError.description` names the file, and a profile may live outside the home folder, where the
    /// support report's `~` abbreviation cannot help. The pane shows this detail verbatim, so it carries the finding
    /// and never the location.
    static func reason(for error: ClaudeAccountReadError) -> String {
        switch error {
        case .unreadable(let access): access.summary
        case .malformed: error.description
        }
    }

    private static func summary(of inspections: [CandidateInspection]) -> String {
        let words = inspections.prefix(3).map { inspection -> String in
            switch inspection.signature {
            case .unsigned: "unsigned" // l10n-ignore: support report
            case .untrusted(let teamID): "team \(teamID ?? "unknown")" // l10n-ignore: support report
            case .invalid(let status): "check failed (\(status))" // l10n-ignore: support report
            case .notFound: "missing" // l10n-ignore: support report
            case .trusted: "trusted" // l10n-ignore: support report
            }
        }
        return words.joined(separator: ", ")
    }
}
