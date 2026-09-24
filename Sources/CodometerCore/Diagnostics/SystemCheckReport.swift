import Foundation

/// What a system check item is about; the UI localizes the title from this.
public enum SystemCheckItemKind: String, Sendable, CaseIterable {
    case claudeExecutable, codexExecutable, claudeProfile, codexProfile, historyDatabase, settingsPermissions
    case dataFolderPermissions, network, notifications, loginItem, shortcut, widgetSnapshot, displays, appLocation
    case crashReports, serviceStatus

    /// The English title used in the support report.
    public var reportTitle: String {
        switch self {
        case .claudeExecutable: "Claude Code executable" // l10n-ignore: support report
        case .codexExecutable: "Codex executable" // l10n-ignore: support report
        case .claudeProfile: "Claude Code profile" // l10n-ignore: support report
        case .codexProfile: "Codex profile" // l10n-ignore: support report
        case .historyDatabase: "History database" // l10n-ignore: support report
        case .settingsPermissions: "Settings file permissions" // l10n-ignore: support report
        case .dataFolderPermissions: "Data folder permissions" // l10n-ignore: support report
        case .network: "Network" // l10n-ignore: support report
        case .notifications: "Notifications" // l10n-ignore: support report
        case .loginItem: "Open at login" // l10n-ignore: support report
        case .shortcut: "Global shortcut" // l10n-ignore: support report
        case .widgetSnapshot: "Widget snapshot" // l10n-ignore: support report
        case .displays: "Displays" // l10n-ignore: support report
        case .appLocation: "App location" // l10n-ignore: support report
        case .crashReports: "Crash reports" // l10n-ignore: support report
        case .serviceStatus: "Service status" // l10n-ignore: support report
        }
    }
}

/// The result of "Check System".
public struct SystemCheckReport: Hashable, Sendable {
    public struct Item: Hashable, Sendable, Identifiable {
        public static let maximumDetailLength = 300

        public enum Status: String, Sendable, CaseIterable, Comparable {
            case ok, note, warning, failure

            private var rank: Int {
                switch self {
                case .ok: 0
                case .note: 1
                case .warning: 2
                case .failure: 3
                }
            }

            public static func < (lhs: Status, rhs: Status) -> Bool { lhs.rank < rhs.rank }
        }

        /// Unique within a report, e.g. `claudeProfile` or `claudeProfile.<account id>`.
        public let id: String
        public let status: Status
        public let kind: SystemCheckItemKind
        /// Technical English detail, sanitised; account ids in it are replaced when the report text is built.
        public let detail: String?

        public init(id: String, status: Status, kind: SystemCheckItemKind, detail: String?) {
            self.id = DisplayText.sanitize(id, maximumLength: 128) ?? kind.rawValue
            self.status = status
            self.kind = kind
            self.detail = DisplayText.sanitize(detail, maximumLength: Self.maximumDetailLength)
        }
    }

    public let ranAt: Date
    /// In check order (`SystemCheckItemKind.allCases`), then by id.
    public let items: [Item]

    public init(ranAt: Date, items: [Item]) {
        self.ranAt = ranAt
        let order = Dictionary(uniqueKeysWithValues: SystemCheckItemKind.allCases.enumerated().map { ($1, $0) })
        self.items = items.sorted { lhs, rhs in
            let left = order[lhs.kind] ?? 0
            let right = order[rhs.kind] ?? 0
            return left == right ? lhs.id < rhs.id : left < right
        }
    }

    /// The worst status of any item; `ok` for an empty report.
    public var overallStatus: Item.Status { items.map(\.status).max() ?? .ok }

    /// Plain English text for "Copy Report" (support text, never localized).
    ///
    /// No e-mail addresses (and no `@` at all), no absolute home paths (`~` instead), no folder names between the home
    /// folder and a file, no session ids, and account labels only when `includeAccountNames` is on (otherwise
    /// "Account 1", "Account 2", … in order of first mention).
    public func text(includeAccountNames: Bool, labels: [AccountID: String]) -> String {
        text(includeAccountNames: includeAccountNames, labels: labels, homeDirectory: NSHomeDirectory())
    }

    func text(includeAccountNames: Bool, labels: [AccountID: String], homeDirectory: String?) -> String {
        let redaction = SupportTextRedaction(
            homeDirectory: homeDirectory,
            labels: labels,
            includeAccountNames: includeAccountNames
        )
        // Only ids and details carry data; titles and headers are fixed English.
        let redacted = redaction.apply(to: items.flatMap { [$0.id, $0.detail ?? ""] })
        var lines = ["Codometer system check", "Ran at: \(Self.timestamp(ranAt))", "Overall: \(overallStatus.rawValue)", ""] // l10n-ignore: support report
        for (index, item) in items.enumerated() {
            var line = "[\(item.status.rawValue)] \(item.kind.reportTitle) (\(redacted[index * 2]))"
            if item.detail != nil {
                line += ": \(redacted[index * 2 + 1])"
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func timestamp(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeZone(separator: .omitted))
    }
}
