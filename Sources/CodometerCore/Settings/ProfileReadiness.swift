/// Whether a profile folder is ready to track, from filesystem metadata only (onboarding and the second-account wizard).
///
/// The authoritative state still comes from the account monitor's first refresh.
public struct ProfileReadiness: Hashable, Sendable, Identifiable {
    public static let maximumPlanLength = 60

    public enum State: Hashable, Sendable {
        case missingFolder
        /// The folder exists but holds nothing the CLI creates.
        case notAProfile
        case notSignedIn
        /// `plan` is sanitised, at most 60 characters.
        case signedIn(plan: String?)
        /// The folder or a file in it is a symlink, which is never followed.
        case symlinkRefused
    }

    /// `provider:path`
    public let id: String
    public let provider: ProviderKind
    public let directory: ProfileDirectory
    public let state: State
    /// The CLI's cached signature check, when known (no spawn).
    public let cli: ExecutableDiagnostics.Signature?

    public init(provider: ProviderKind, directory: ProfileDirectory, state: State, cli: ExecutableDiagnostics.Signature?) {
        id = "\(provider.rawValue):\(directory.path)"
        self.provider = provider
        self.directory = directory
        if case .signedIn(let plan) = state {
            self.state = .signedIn(plan: DisplayText.sanitize(plan, maximumLength: Self.maximumPlanLength))
        } else {
            self.state = state
        }
        self.cli = cli
    }
}
