import Foundation

/// The state of `history.sqlite`, for Diagnostics and notices.
public enum HistoryHealth: Hashable, Sendable {
    case ok
    /// History could not be opened; the app runs without it.
    case unavailable(reason: String)
    /// The file was damaged, moved aside under `backupFileName`, and a fresh file was created.
    case recoveredFromCorruption(backupFileName: String)
    /// Written by a newer Codometer: read only, never written or pruned.
    case readOnlyNewerSchema(version: Int)
    /// Writes stopped (for example, the disk is full) and are retried at the next maintenance.
    case writesPaused(reason: String)
}

/// The file layout of a history export.
public enum HistoryExportFormat: String, Sendable, CaseIterable {
    /// One JSON file.
    case json
    /// A folder of CSV files plus a README.
    case csvFolder
}

/// What the user asked to export.
public struct HistoryExportRequest: Sendable {
    public let format: HistoryExportFormat
    /// Account labels go into the export only when this is on; e-mails never do.
    public let includeAccountNames: Bool
    /// Labels by account, sanitised like `AccountLabel`.
    public let labels: [AccountID: String]
    public let appVersion: String
    public let retentionDays: Int
    /// The README text of a CSV export, rendered by the App in the UI language (the engine never localizes).
    public let readmeText: String

    public init(
        format: HistoryExportFormat,
        includeAccountNames: Bool,
        labels: [AccountID: String],
        appVersion: String,
        retentionDays: Int,
        readmeText: String
    ) {
        self.format = format
        self.includeAccountNames = includeAccountNames
        self.labels = labels.compactMapValues { DisplayText.sanitize($0, maximumLength: AccountLabel.maximumLength) }
        self.appVersion = DisplayText.sanitize(appVersion, maximumLength: AppVersion.maximumLength) ?? "unknown"
        self.retentionDays = retentionDays
        self.readmeText = readmeText
    }
}

/// A finished export.
public struct HistoryExportSummary: Hashable, Sendable {
    public let rowCount: Int
    public let destination: URL

    public init(rowCount: Int, destination: URL) {
        self.rowCount = max(0, rowCount)
        self.destination = destination
    }
}

public enum HistoryExportError: Error, Hashable, Sendable {
    case historyUnavailable
    case destinationExists
    /// A technical reason for logs; never shown with paths.
    case writeFailed(String)
    case cancelled
}

/// What "Erase All Data" did.
public struct EraseSummary: Hashable, Sendable {
    public let removedItems: Int
    /// Symlinks found where app files should be; never followed or removed.
    public let refusedSymlinks: Int
    public let failures: Int

    public init(removedItems: Int, refusedSymlinks: Int, failures: Int) {
        self.removedItems = max(0, removedItems)
        self.refusedSymlinks = max(0, refusedSymlinks)
        self.failures = max(0, failures)
    }

    /// Nothing was refused and nothing failed.
    public var isComplete: Bool { refusedSymlinks == 0 && failures == 0 }
}

/// History facts for the Diagnostics pane.
public struct HistoryDiagnostics: Hashable, Sendable {
    public let health: HistoryHealth
    public let fileBytes: Int64?
    public let schemaVersion: Int?
    public let oldestSampleAt: Date?
    public let retentionDays: Int
    /// Row counts by table name (bounded counts).
    public let rowCounts: [String: Int]

    public init(
        health: HistoryHealth,
        fileBytes: Int64?,
        schemaVersion: Int?,
        oldestSampleAt: Date?,
        retentionDays: Int,
        rowCounts: [String: Int]
    ) {
        self.health = health
        self.fileBytes = fileBytes.map { max(0, $0) }
        self.schemaVersion = schemaVersion
        self.oldestSampleAt = oldestSampleAt
        self.retentionDays = retentionDays
        self.rowCounts = rowCounts.mapValues { max(0, $0) }
    }

    /// History that could not be opened.
    public static func unavailable(reason: String, retentionDays: Int) -> HistoryDiagnostics {
        HistoryDiagnostics(
            health: .unavailable(reason: reason),
            fileBytes: nil,
            schemaVersion: nil,
            oldestSampleAt: nil,
            retentionDays: retentionDays,
            rowCounts: [:]
        )
    }
}
