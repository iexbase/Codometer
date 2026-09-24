import Foundation

/// Tokens one session consumed since its previous sample. Monitors report these; the engine aggregates them.
public struct TokenSample: Hashable, Sendable {
    public let accountID: AccountID
    public let sessionID: String
    /// The session's project folder or path, sanitised.
    public let project: String?
    /// The model that produced the tokens, sanitised.
    public let model: String?
    public let at: Date
    /// Tokens consumed since the previous sample of this session.
    public let delta: TokenCounts

    public init(
        accountID: AccountID,
        sessionID: String,
        project: String?,
        model: String?,
        at: Date,
        delta: TokenCounts
    ) throws(ValidationError) {
        guard let cleanID = DisplayText.sanitize(sessionID, maximumLength: 128), cleanID == sessionID else {
            throw .invalidCharacters(field: "tokens.sessionID")
        }
        self.accountID = accountID
        self.sessionID = sessionID
        self.project = DisplayText.sanitize(project, maximumLength: ProfileDirectory.maximumLength)
        self.model = DisplayText.sanitize(model, maximumLength: AgentSession.maximumModelLength)
        self.at = at
        self.delta = delta
    }
}
