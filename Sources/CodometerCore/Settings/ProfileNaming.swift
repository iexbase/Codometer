/// The part after the dash in a second profile folder: `work` in `~/.claude-work`.
///
/// One rule for profile discovery, the onboarding wizard and the Accounts pane guide.
public struct ProfileSuffix: Hashable, Sendable, CustomStringConvertible {
    public static let maximumLength = 24

    public let value: String

    /// `[A-Za-z0-9_.]`, 1–24 characters, not "." or "..".
    public init(_ raw: String) throws(ValidationError) {
        guard !raw.isEmpty else { throw .empty(field: "profile.suffix") }
        guard raw.utf8.count <= Self.maximumLength else {
            throw .tooLong(field: "profile.suffix", length: raw.utf8.count, maximum: Self.maximumLength)
        }
        let allowed = raw.utf8.allSatisfy { byte in
            switch byte {
            case UInt8(ascii: "a")...UInt8(ascii: "z"),
                 UInt8(ascii: "A")...UInt8(ascii: "Z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"),
                 UInt8(ascii: "_"), UInt8(ascii: "."):
                true
            default:
                false
            }
        }
        guard allowed, raw != ".", raw != ".." else { throw .invalidCharacters(field: "profile.suffix") }
        value = raw
    }

    public var description: String { value }

    /// `.claude-work` / `.codex-work`, a folder name in the home directory.
    public func folderName(for provider: ProviderKind) -> String {
        "\(provider.defaultDirectoryName)-\(value)"
    }
}

/// Terminal commands that sign a second account in to its own profile folder. Shell text: never localized.
public enum SecondAccountCommands {
    /// Claude: `CLAUDE_CONFIG_DIR=~/.claude-work claude` (then `/login` inside Claude Code).
    /// Codex: `mkdir -p ~/.codex-work && CODEX_HOME=~/.codex-work codex login`.
    /// The suffix alphabet needs no shell quoting.
    public static func signIn(provider: ProviderKind, suffix: ProfileSuffix) -> [String] {
        let folder = "~/" + suffix.folderName(for: provider)
        switch provider {
        case .claude:
            return ["CLAUDE_CONFIG_DIR=\(folder) claude"]
        case .codex:
            return ["mkdir -p \(folder) && CODEX_HOME=\(folder) codex login"]
        }
    }
}
