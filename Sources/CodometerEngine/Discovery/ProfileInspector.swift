import CodometerClaude
import CodometerCodex
import CodometerCore
import CodometerPlatform
import Darwin
import Foundation

/// Whether the profile folders onboarding offers are ready to track, from the filesystem only.
///
/// Every answer comes from `lstat` plus, for Claude, a bounded decode of `.claude.json` — and that decode happens
/// only when the file's size or modification time changed since the last look, so the wizard's two-second watch
/// costs a couple of `lstat`s. Codex's `auth.json` is never opened: its existence as a non-empty regular file is
/// the whole check, so a token file stays unread whatever its permissions. Symbolic links are refused, never
/// followed. Nothing is cached on disk and no e-mail is kept: only the plan name reaches `ProfileReadiness`.
///
/// The authoritative state still comes from the account monitor's first refresh.
struct ProfileInspector: Sendable {
    /// What a decode of `.claude.json` found, kept so an unchanged file is not read again.
    private struct Cached: Sendable {
        let size: UInt64
        let modifiedAt: Date
        let plan: String?
        let isSignedIn: Bool
    }

    private var cache: [String: Cached] = [:]

    init() {}

    /// Readiness of every profile folder in the home directory plus the folders of `accounts`, sorted by provider
    /// and path. `signatures` carries the CLI signature the locator already checked, when one is known (no spawn).
    mutating func inspect(
        homeDirectory: URL,
        accounts: [AccountProfile] = [],
        signatures: [ProviderKind: ExecutableDiagnostics.Signature] = [:]
    ) -> [ProfileReadiness] {
        var seen = Set<String>()
        var candidates: [(provider: ProviderKind, directory: ProfileDirectory)] = []
        for candidate in Self.candidateFolders(in: homeDirectory) where seen.insert(candidate.key).inserted {
            candidates.append((candidate.provider, candidate.directory))
        }
        for account in accounts {
            let key = "\(account.provider.rawValue):\(account.directory.path)"
            guard seen.insert(key).inserted else { continue }
            candidates.append((account.provider, account.directory))
        }
        candidates.sort { lhs, rhs in
            lhs.provider == rhs.provider
                ? lhs.directory.path < rhs.directory.path
                : lhs.provider.rawValue < rhs.provider.rawValue
        }
        return candidates.map { candidate in
            ProfileReadiness(
                provider: candidate.provider,
                directory: candidate.directory,
                state: state(provider: candidate.provider, directory: candidate.directory, homeDirectory: homeDirectory),
                cli: signatures[candidate.provider]
            )
        }
    }

    // MARK: - One folder

    private mutating func state(
        provider: ProviderKind,
        directory: ProfileDirectory,
        homeDirectory: URL
    ) -> ProfileReadiness.State {
        let url = URL(fileURLWithPath: directory.path, isDirectory: true)
        switch Self.kind(at: url.path) {
        case .missing: return .missingFolder
        case .symbolicLink: return .symlinkRefused
        case .directory: break
        case .regularFile, .other: return .notAProfile
        }
        return switch provider {
        case .claude: claudeState(directory: url, homeDirectory: homeDirectory)
        case .codex: codexState(directory: url)
        }
    }

    private mutating func claudeState(directory: URL, homeDirectory: URL) -> ProfileReadiness.State {
        let layout = ClaudeProfileLayout(configDirectory: directory, homeDirectory: homeDirectory)
        let stateFile = layout.accountStateFile
        switch Self.kind(at: stateFile.path) {
        case .symbolicLink:
            return .symlinkRefused
        case .missing, .other, .directory:
            return Self.hasMarker(in: directory, names: ["sessions", "projects"]) ? .notSignedIn : .notAProfile
        case .regularFile:
            break
        }
        guard let metadata = SecureFileIO.metadata(at: stateFile) else { return .notSignedIn }
        if let cached = cache[stateFile.path], cached.size == metadata.size, cached.modifiedAt == metadata.modifiedAt {
            return cached.isSignedIn ? .signedIn(plan: cached.plan) : .notSignedIn
        }
        let identity: AccountIdentity? = (try? ClaudeAccountReader.identity(for: layout)) ?? nil
        let plan = identity?.plan
        let isSignedIn = identity != nil
        cache[stateFile.path] = Cached(
            size: metadata.size,
            modifiedAt: metadata.modifiedAt,
            plan: plan,
            isSignedIn: isSignedIn
        )
        return isSignedIn ? .signedIn(plan: plan) : .notSignedIn
    }

    private func codexState(directory: URL) -> ProfileReadiness.State {
        let authentication = directory.appendingPathComponent("auth.json", isDirectory: false)
        switch Self.kind(at: authentication.path) {
        case .symbolicLink:
            return .symlinkRefused
        case .regularFile:
            // Metadata only: the file holds a token and is never opened.
            let size = SecureFileIO.metadata(at: authentication)?.size ?? 0
            return size > 0 ? .signedIn(plan: nil) : .notSignedIn
        case .missing, .directory, .other:
            return Self.hasMarker(in: directory, names: ["sessions", "config.toml"]) ? .notSignedIn : .notAProfile
        }
    }

    // MARK: - Home folder scan

    private struct Candidate {
        let provider: ProviderKind
        let directory: ProfileDirectory
        var key: String { "\(provider.rawValue):\(directory.path)" }
    }

    /// Every `~/.claude`, `~/.claude-<suffix>`, `~/.codex` and `~/.codex-<suffix>` folder, whether or not it holds a
    /// profile yet: the second-account wizard waits for one of them to appear and fill up.
    private static func candidateFolders(in homeDirectory: URL) -> [Candidate] {
        guard let handle = opendir(homeDirectory.path) else { return [] }
        defer { closedir(handle) }
        var found: [Candidate] = []
        while let entry = readdir(handle) {
            let name = entryName(entry)
            guard name.hasPrefix(".") else { continue }
            for provider in ProviderKind.allCases {
                guard ProfileDiscovery.variant(of: name, provider: provider) != nil else { continue }
                let url = homeDirectory.appendingPathComponent(name, isDirectory: true)
                guard let directory = try? ProfileDirectory(validating: url.path) else { continue }
                found.append(Candidate(provider: provider, directory: directory))
            }
        }
        return found.sorted { $0.key < $1.key }
    }

    private static func entryName(_ entry: UnsafeMutablePointer<dirent>) -> String {
        withUnsafePointer(to: entry.pointee.d_name) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) {
                String(cString: $0)
            }
        }
    }

    private enum EntryKind {
        case missing, symbolicLink, directory, regularFile, other
    }

    private static func kind(at path: String) -> EntryKind {
        var info = stat()
        guard lstat(path, &info) == 0 else { return .missing }
        return switch info.st_mode & S_IFMT {
        case S_IFLNK: .symbolicLink
        case S_IFDIR: .directory
        case S_IFREG: .regularFile
        default: .other
        }
    }

    /// Whether the folder holds one of the entries the CLI itself creates (without following symlinks).
    private static func hasMarker(in directory: URL, names: [String]) -> Bool {
        names.contains { name in
            switch kind(at: directory.appendingPathComponent(name).path) {
            case .missing, .symbolicLink: false
            case .directory, .regularFile, .other: true
            }
        }
    }
}
