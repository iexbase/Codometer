import Foundation

/// Where the running app bundle lives. Anything but an installed copy gets a warning in Diagnostics, and a disk
/// image, translocated or read-only location stops the launch.
public enum AppLocationKind: String, Sendable, CaseIterable {
    /// `/Applications`
    case applications
    /// `~/Applications`
    case userApplications
    /// Any other writable folder.
    case other
    /// Gatekeeper App Translocation (a quarantined app opened in place).
    case translocated
    /// A mounted disk image under `/Volumes`.
    case diskImage
    /// Any read-only volume.
    case readOnlyVolume
}

/// Version, build and location of the running app, for About and Diagnostics.
public struct AppBuildInfo: Hashable, Sendable {
    public static let maximumFieldLength = 64

    /// `CFBundleShortVersionString`, e.g. "1.0.0".
    public let version: String
    /// `CFBundleVersion`, e.g. "1790000000".
    public let build: String
    public let locationKind: AppLocationKind
    /// The license name injected at build time, `nil` while no license is chosen.
    public let licenseName: String?

    /// Values come from the bundle's Info.plist: they are sanitised and capped, and a missing value reads "—".
    public init(version: String, build: String, locationKind: AppLocationKind, licenseName: String?) {
        self.version = DisplayText.sanitize(version, maximumLength: Self.maximumFieldLength) ?? "—"
        self.build = DisplayText.sanitize(build, maximumLength: Self.maximumFieldLength) ?? "—"
        self.locationKind = locationKind
        self.licenseName = DisplayText.sanitize(licenseName, maximumLength: Self.maximumFieldLength)
    }
}

/// The app's login item as the system reports it (`SMAppService.mainApp.status`).
public enum LoginItemStatus: Sendable {
    case enabled
    case disabled
    /// Registered, but the user has to allow it in System Settings.
    case requiresApproval
    case notFound
    /// The status could not be read (e.g. an isolated test instance).
    case unavailable
}

/// Notification permission as the system reports it.
public enum NotificationAuthorization: Sendable {
    case notDetermined
    case denied
    case authorized
    case provisional
}

/// One locally stored crash or hang diagnostic (MetricKit payload), listed in Diagnostics.
public struct CrashReportSummary: Hashable, Sendable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable {
        case crash
        case hang
        case exception
    }

    /// The payload's file name stem; `[A-Za-z0-9._-]`, at most 64 characters.
    public let id: String
    public let date: Date
    public let kind: Kind

    public init(id: String, date: Date, kind: Kind) throws(ValidationError) {
        self.id = try StableIdentifier.validate(id, field: "crashReport.id")
        self.date = date
        self.kind = kind
    }
}
