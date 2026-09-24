import CodometerCore
import CodometerL10n
import Foundation
import ServiceManagement

/// "Open at login", kept in step with what the system actually has registered.
///
/// The stored setting and `SMAppService.mainApp.status` can disagree: the user can remove the login item in System
/// Settings, and a renamed or moved app loses its registration without anyone touching the toggle. At launch, and
/// again whenever Settings opens, `LoginItemReconcile` decides which side wins.
@MainActor
enum LoginItemService {
    /// Registers or unregisters the app. Returns a user-facing error message in the language of `l10n`, or `nil` on
    /// success.
    static func setEnabled(_ enabled: Bool, l10n: Localizer) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            // The system's description follows the process language (macOS applies the app's language after a relaunch).
            return l10n.notification.loginItemFailed(reason: error.localizedDescription)
        }
    }

    /// What the system reports. `.unavailable` without an app bundle (`swift run` builds have none).
    static func status() -> LoginItemStatus {
        guard Bundle.main.bundleIdentifier != nil else { return .unavailable }
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        case .notRegistered: return .disabled
        @unknown default: return .unavailable
        }
    }
}

/// The pure decision table behind the reconciliation, so every combination is covered by tests instead of by a
/// launch on someone's Mac.
enum LoginItemReconcile {
    enum Action: Equatable {
        /// Setting and system agree.
        case none
        /// Register once: the app intends to open at login, and an update or the rename dropped the registration.
        case register
        /// The system has no login item: the setting follows it.
        case turnSettingOff
        /// The system has one (or is waiting for approval): the setting follows it.
        case turnSettingOn
        /// Registered, but macOS is waiting for the user to allow it in System Settings.
        case needsApproval
    }

    /// - Parameters:
    ///   - intent: `settings.general.launchesAtLogin`.
    ///   - status: What `SMAppService.mainApp.status` says right now.
    ///   - versionChanged: Whether this is the first launch of a new app version (the rename is such a launch).
    static func action(intent: Bool, status: LoginItemStatus, versionChanged: Bool) -> Action {
        switch (intent, status) {
        case (_, .unavailable):
            return .none
        case (true, .enabled):
            return .none
        case (true, .requiresApproval):
            return .needsApproval
        case (true, .disabled), (true, .notFound):
            // A new version registers again (the rename made the old registration point at another bundle id);
            // otherwise the user removed the login item themselves and the toggle follows.
            return versionChanged ? .register : .turnSettingOff
        case (false, .enabled), (false, .requiresApproval):
            return .turnSettingOn
        case (false, .disabled), (false, .notFound):
            return .none
        }
    }
}
