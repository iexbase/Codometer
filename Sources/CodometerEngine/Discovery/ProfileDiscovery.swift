import CodometerCore
import Foundation

public struct DiscoveredProfile: Hashable, Sendable {
    public let provider: ProviderKind
    public let directory: ProfileDirectory
    /// "work" for `~/.claude-work`, `nil` for the default profile.
    public let variant: String?
}

/// Finds Claude Code and Codex profile directories in the home folder.
///
/// A directory only counts when it contains files the CLI itself creates, so unrelated
/// folders that merely share the prefix (plugin caches, backups) are ignored.
public enum ProfileDiscovery {
    /// One rule for the suffix of a second profile folder, shared with the onboarding wizard (`ProfileSuffix`).
    public static let maximumVariantLength = ProfileSuffix.maximumLength

    public static func discover(homeDirectory: URL, fileManager: FileManager = .default) -> [DiscoveredProfile] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: homeDirectory.path) else { return [] }
        return names.sorted().compactMap { name -> DiscoveredProfile? in
            for provider in ProviderKind.allCases {
                guard let variant = variant(of: name, provider: provider) else { continue }
                let url = homeDirectory.appendingPathComponent(name, isDirectory: true)
                guard
                    isDirectory(url, fileManager: fileManager),
                    looksLikeProfile(url, provider: provider, isDefault: variant.isEmpty, homeDirectory: homeDirectory),
                    let directory = try? ProfileDirectory(validating: url.path)
                else { return nil }
                return DiscoveredProfile(provider: provider, directory: directory, variant: variant.isEmpty ? nil : variant)
            }
            return nil
        }
    }

    /// Accounts to create on first launch.
    public static func initialAccounts(homeDirectory: URL) -> [AccountProfile] {
        discover(homeDirectory: homeDirectory).compactMap { profile in
            let base = profile.provider == .claude ? "Claude" : "Codex"
            let title = profile.variant.map { "\(base) · \($0)" } ?? base
            guard let label = try? AccountLabel(validating: String(title.prefix(AccountLabel.maximumLength))) else {
                return nil
            }
            return try? AccountProfile(provider: profile.provider, label: label, directory: profile.directory)
        }
    }

    /// `""` for the default directory, the suffix for `.<provider>-<suffix>`, `nil` otherwise.
    ///
    /// The suffix rule is Core's `ProfileSuffix`, so discovery, the onboarding wizard and the Accounts pane guide
    /// agree on what a second profile may be called.
    static func variant(of name: String, provider: ProviderKind) -> String? {
        let base = provider.defaultDirectoryName
        if name == base { return "" }
        guard name.hasPrefix(base + "-") else { return nil }
        return (try? ProfileSuffix(String(name.dropFirst(base.count + 1))))?.value
    }

    private static func looksLikeProfile(_ url: URL, provider: ProviderKind, isDefault: Bool, homeDirectory: URL) -> Bool {
        let markers: [String] = switch provider {
        case .claude: [".claude.json", "sessions", "projects"]
        case .codex: ["auth.json", "config.toml", "sessions"]
        }
        if markers.contains(where: { FileManager.default.fileExists(atPath: url.appendingPathComponent($0).path) }) {
            return true
        }
        return isDefault && provider == .claude
            && FileManager.default.fileExists(atPath: homeDirectory.appendingPathComponent(".claude.json").path)
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
