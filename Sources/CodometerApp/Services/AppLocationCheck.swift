import CodometerCore
import CodometerL10n
import Foundation

/// Where the running bundle lives, and whether that is a place Codometer may run from.
///
/// Launching from a mounted disk image, from Gatekeeper's App Translocation copy or from any other read-only volume
/// breaks the parts of the app that depend on a stable path: WidgetKit registers the copy it saw and bans reloads
/// when the path disappears, and `SMAppService.mainApp.register()` fails outright. Such a launch is
/// stopped with an alert **before** the legacy migration, the instance lock, the engine or any write.
///
/// The classifier itself is pure, so the tests cover every shape without mounting anything.
enum AppLocationCheck {
    /// The folder Gatekeeper translocates a quarantined app into.
    static let translocationMarker = "/AppTranslocation/"
    /// Where macOS mounts removable volumes and disk images.
    static let volumesPrefix = "/Volumes/"
    static let systemApplications = "/Applications"

    /// Classifies a bundle path.
    ///
    /// - Parameters:
    ///   - bundlePath: The standardized path of `Bundle.main.bundleURL`.
    ///   - isReadOnlyVolume: `URLResourceValues.volumeIsReadOnly` for that URL (which also catches
    ///     `hdiutil -mountrandom` mounts outside `/Volumes`).
    ///   - homePath: The user's home folder, for `~/Applications`.
    static func classify(bundlePath: String, isReadOnlyVolume: Bool, homePath: String) -> AppLocationKind {
        if bundlePath.contains(translocationMarker) { return .translocated }
        if bundlePath.hasPrefix(volumesPrefix) { return .diskImage }
        if isReadOnlyVolume { return .readOnlyVolume }
        if isInside(bundlePath, folder: systemApplications) { return .applications }
        if isInside(bundlePath, folder: homePath + systemApplications) { return .userApplications }
        return .other
    }

    /// Whether this location stops the launch. Everything writable and stable is allowed, including a build folder,
    /// so development and `swift run` keep working; only Diagnostics remarks on it.
    static func blocksLaunch(_ kind: AppLocationKind) -> Bool {
        switch kind {
        case .translocated, .diskImage, .readOnlyVolume: true
        case .applications, .userApplications, .other: false
        }
    }

    /// The bundle's kind as the running process sees it.
    static func current(bundleURL: URL, homeDirectory: URL) -> AppLocationKind {
        let url = bundleURL.standardizedFileURL
        let readOnly = (try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? false
        return classify(
            bundlePath: url.path,
            isReadOnlyVolume: readOnly,
            homePath: homeDirectory.standardizedFileURL.path
        )
    }

    /// `path` is `folder` itself or something inside it (never a prefix match on a longer name).
    private static func isInside(_ path: String, folder: String) -> Bool {
        let folder = folder.hasSuffix("/") ? String(folder.dropLast()) : folder
        return path == folder || path.hasPrefix(folder + "/")
    }
}

/// The text of the "Move Codometer to Applications" alert, separated from AppKit so both languages can be tested and
/// rendered without showing a modal.
struct AppLocationAlertText: Equatable {
    let title: String
    let message: String
    let button: String

    /// - Parameter kind: A kind for which `AppLocationCheck.blocksLaunch` is true.
    init(kind: AppLocationKind, l10n: Localizer) {
        title = l10n.lifecycle.moveToApplicationsTitle
        let lead = switch kind {
        case .diskImage: l10n.lifecycle.runningFromDiskImage
        case .translocated: l10n.lifecycle.runningTranslocated
        default: l10n.lifecycle.runningFromReadOnlyVolume
        }
        message = lead + "\n\n" + l10n.lifecycle.installedCopyNeeded
        button = l10n.notification.quit
    }
}
