import CodometerCore
import CodometerPlatform
import Foundation

public enum ClaudeAccountReadError: Error, Equatable, Sendable, CustomStringConvertible {
    case unreadable(FileAccessError)
    case malformed

    public var description: String {
        switch self {
        case .unreadable(let error): error.description
        case .malformed: "account state file is not valid JSON"
        }
    }
}

/// Reads who a profile is signed in as from Claude Code's account state file.
///
/// The file holds account metadata only (email, organisation, plan tier); credentials live
/// in the Keychain, which this app never reads.
public enum ClaudeAccountReader {
    public static let maximumBytes = 16 * 1_024 * 1_024

    private struct StateFile: Decodable {
        let oauthAccount: OAuthAccount?
    }

    private struct OAuthAccount: Decodable {
        let emailAddress: String?
        let organizationName: String?
        let organizationType: String?
        let organizationRateLimitTier: String?
        let userRateLimitTier: String?
    }

    /// `nil` when the file does not exist or the profile is not signed in with a Claude account.
    public static func identity(for layout: ClaudeProfileLayout) throws(ClaudeAccountReadError) -> AccountIdentity? {
        let data: Data
        do {
            data = try SecureFileIO.readRegularFile(at: layout.accountStateFile, maximumBytes: maximumBytes)
        } catch {
            if case .notFound = error { return nil }
            throw .unreadable(error)
        }
        let state: StateFile
        do {
            state = try JSONDecoder().decode(StateFile.self, from: data)
        } catch {
            throw .malformed
        }
        guard let account = state.oauthAccount else { return nil }
        let identity = AccountIdentity(
            email: account.emailAddress,
            organization: account.organizationName,
            plan: planName(
                tier: account.organizationRateLimitTier ?? account.userRateLimitTier,
                organizationType: account.organizationType
            )
        )
        return identity.isEmpty ? nil : identity
    }

    static func planName(tier: String?, organizationType: String?) -> String? {
        let tier = tier?.lowercased() ?? ""
        if tier.contains("max_20x") { return "Max 20x" }
        if tier.contains("max_5x") { return "Max 5x" }
        switch organizationType?.lowercased() {
        case "claude_max": return "Max"
        case "claude_pro": return "Pro"
        case "claude_team": return "Team"
        case "claude_enterprise": return "Enterprise"
        default: return nil
        }
    }
}
