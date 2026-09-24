/// The coding assistants the app knows how to read.
public enum ProviderKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case claude
    case codex

    public var id: String { rawValue }

    /// Claude is read by running the official CLI, which costs ~1 s of CPU, so it polls less often.
    public var defaultPollInterval: PollInterval {
        switch self {
        case .claude: .constant(300)
        case .codex: .constant(180)
        }
    }

    public var minimumPollInterval: PollInterval {
        switch self {
        case .claude: .constant(120)
        case .codex: .constant(60)
        }
    }

    /// Name of the default profile directory inside the home folder.
    public var defaultDirectoryName: String {
        switch self {
        case .claude: ".claude"
        case .codex: ".codex"
        }
    }
}
