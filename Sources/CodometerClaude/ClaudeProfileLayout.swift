import Foundation

/// File locations for one Claude Code profile (`~/.claude` or a `CLAUDE_CONFIG_DIR`).
public struct ClaudeProfileLayout: Hashable, Sendable {
    public let configDirectory: URL
    public let homeDirectory: URL

    public init(configDirectory: URL, homeDirectory: URL) {
        self.configDirectory = configDirectory.standardizedFileURL
        self.homeDirectory = homeDirectory.standardizedFileURL
    }

    public var isDefault: Bool {
        configDirectory.path == homeDirectory.appendingPathComponent(".claude", isDirectory: true).standardizedFileURL.path
    }

    /// One `<pid>.json` per running Claude Code process.
    public var sessionsDirectory: URL {
        configDirectory.appendingPathComponent("sessions", isDirectory: true)
    }

    /// Conversation transcripts: `<slug>/<sessionId>.jsonl` plus `<slug>/<sessionId>/subagents/**/*.jsonl`.
    /// Only token-usage fields are ever decoded from them.
    public var projectsDirectory: URL {
        configDirectory.appendingPathComponent("projects", isDirectory: true)
    }

    /// Non-secret account metadata. The default profile keeps it next to the directory, named profiles inside it.
    public var accountStateFile: URL {
        isDefault
            ? homeDirectory.appendingPathComponent(".claude.json", isDirectory: false)
            : configDirectory.appendingPathComponent(".claude.json", isDirectory: false)
    }

    /// `CLAUDE_CONFIG_DIR` is set only for named profiles: setting it for the default profile would make
    /// Claude Code look up a differently named credential item and appear signed out.
    public var environmentOverrides: [String: String] {
        isDefault ? [:] : ["CLAUDE_CONFIG_DIR": configDirectory.path]
    }

    /// Install locations of the native, code-signed Claude Code binary, in priority order.
    public static func executableCandidates(homeDirectory: URL) -> [URL] {
        [
            homeDirectory.appendingPathComponent(".local/bin/claude"),
            homeDirectory.appendingPathComponent(".claude/local/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude"),
        ]
    }
}
