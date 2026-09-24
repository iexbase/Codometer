import CodometerCore
import Foundation

/// A system check full of personal data: e-mails, home paths, labels, project folders and session ids.
enum DiagnosticsFixtures {
    static let workID = AccountID(rawValue: UUID(uuidString: "8C8E4A0E-3B1A-4C7B-9D5E-00000000C1A0") ?? UUID())
    static let personalID = AccountID(rawValue: UUID(uuidString: "8C8E4A0E-3B1A-4C7B-9D5E-00000000C1A1") ?? UUID())
    static let defaultID = AccountID(rawValue: UUID(uuidString: "8C8E4A0E-3B1A-4C7B-9D5E-00000000C1A2") ?? UUID())

    static let labels: [AccountID: String] = [
        workID: "Acme Consulting",
        personalID: "Jane personal",
        defaultID: "Claude",
    ]

    static let ranAt = Date(timeIntervalSince1970: 1_789_600_000)

    static let report = SystemCheckReport(ranAt: ranAt, items: [
        .init(id: "network", status: .ok, kind: .network, detail: "online"),
        .init(
            id: "claudeProfile.\(personalID)",
            status: .warning,
            kind: .claudeProfile,
            detail: "~/.claude-personal: signed in as jane.doe@example.com (Jane personal)"
        ),
        .init(
            id: "claudeProfile.\(workID)",
            status: .ok,
            kind: .claudeProfile,
            detail: "/Users/jane.doe/Projects/acme-secret-launch/.claude signed in as jane@acme.io for Acme Consulting, session 3F2504E0-4F89-11D3-9A0C-0305E82C3301"
        ),
        .init(
            id: "claudeExecutable",
            status: .ok,
            kind: .claudeExecutable,
            detail: "/Users/jane.doe/.local/bin/claude 2.1.12, signed by Anthropic PBC (Q6L2SF6YDW)"
        ),
        .init(id: "appLocation", status: .note, kind: .appLocation, detail: "/Users/someone/Downloads/Codometer.app"),
        .init(id: "historyDatabase", status: .failure, kind: .historyDatabase, detail: "quick_check failed at /Users/jane.doe/Library/Application Support/Codometer/history.sqlite"),
        .init(id: "claudeProfile.\(defaultID)", status: .ok, kind: .claudeProfile, detail: "~/.claude (Claude): ops@@team"),
        .init(id: "codexExecutable", status: .note, kind: .codexExecutable, detail: "/opt/homebrew/bin/codex, user agent codex_cli_rs/0.154.0; project ~/work/client-orion/tools"),
    ])
}
