import Foundation

/// File locations for one Codex profile (`~/.codex` or a `CODEX_HOME`).
public struct CodexProfileLayout: Hashable, Sendable {
    public let home: URL
    public let homeDirectory: URL

    public init(home: URL, homeDirectory: URL) {
        self.home = home.standardizedFileURL
        self.homeDirectory = homeDirectory.standardizedFileURL
    }

    public var isDefault: Bool {
        home.path == homeDirectory.appendingPathComponent(".codex", isDirectory: true).standardizedFileURL.path
    }

    /// `sessions/YYYY/MM/DD/rollout-*.jsonl`, written by the Codex CLI and the desktop app.
    public var sessionsDirectory: URL {
        home.appendingPathComponent("sessions", isDirectory: true)
    }

    public var environmentOverrides: [String: String] {
        isDefault ? [:] : ["CODEX_HOME": home.path]
    }

    /// Install locations of the code-signed Codex binary, in priority order.
    public static func executableCandidates(homeDirectory: URL) -> [URL] {
        [
            URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
            URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex"),
            homeDirectory.appendingPathComponent("Applications/ChatGPT.app/Contents/Resources/codex"),
            homeDirectory.appendingPathComponent("Applications/Codex.app/Contents/Resources/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
            homeDirectory.appendingPathComponent(".local/bin/codex"),
        ]
    }
}
