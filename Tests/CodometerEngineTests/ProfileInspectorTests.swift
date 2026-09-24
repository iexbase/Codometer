import CodometerCore
@testable import CodometerEngine
import Foundation
import Testing

/// A home folder with hand-made profile folders.
private struct Home {
    let directory: TemporaryDirectory

    init() throws {
        directory = try TemporaryDirectory()
    }

    var url: URL { directory.url }

    func makeFolder(_ path: String) throws {
        try FileManager.default.createDirectory(
            at: url.appendingPathComponent(path, isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    func write(_ path: String, _ contents: String, permissions: Int? = nil) throws {
        let file = url.appendingPathComponent(path, isDirectory: false)
        try Data(contents.utf8).write(to: file)
        if let permissions {
            try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: file.path)
        }
    }

    func state(_ readiness: [ProfileReadiness], _ folder: String) -> ProfileReadiness.State? {
        readiness.first { $0.directory.lastComponent == folder }?.state
    }
}

private let signedInClaude = """
    {"oauthAccount": {"emailAddress": "someone@example.com", "organizationType": "claude_max",
     "organizationRateLimitTier": "max_20x"}}
    """

@Suite("Profile inspector")
struct ProfileInspectorTests {
    @Test("A folder that is missing, empty, signed out or signed in is told apart from metadata")
    func states() throws {
        let home = try Home()
        try home.makeFolder(".claude/projects")
        try home.write(".claude.json", signedInClaude)
        try home.makeFolder(".claude-work/sessions")
        try home.makeFolder(".claude-empty")
        try home.makeFolder(".codex/sessions")
        try home.write(".codex/auth.json", "{\"tokens\": \"secret\"}", permissions: 0o000)
        try home.makeFolder(".codex-work")
        try home.write(".codex-work/config.toml", "model = \"gpt\"")

        var inspector = ProfileInspector()
        let readiness = inspector.inspect(homeDirectory: home.url)
        #expect(readiness.map(\.provider) == [.claude, .claude, .claude, .codex, .codex])
        #expect(home.state(readiness, ".claude") == .signedIn(plan: "Max 20x"))
        #expect(home.state(readiness, ".claude-work") == .notSignedIn)
        #expect(home.state(readiness, ".claude-empty") == .notAProfile)
        // Codex is judged by metadata only: a file no one may read still counts as signed in.
        #expect(home.state(readiness, ".codex") == .signedIn(plan: nil))
        #expect(home.state(readiness, ".codex-work") == .notSignedIn)
        #expect(readiness.allSatisfy { $0.cli == nil })
        #expect(readiness.map(\.id).allSatisfy { $0.contains(":") })
    }

    @Test("A folder an account points at but that is gone is reported as missing")
    func missingFolder() throws {
        let home = try Home()
        let account = try AccountProfile(
            provider: .claude,
            label: try AccountLabel(validating: "Work"),
            directory: try ProfileDirectory(validating: home.url.appendingPathComponent(".claude-gone").path)
        )
        var inspector = ProfileInspector()
        let readiness = inspector.inspect(homeDirectory: home.url, accounts: [account])
        #expect(readiness.map(\.state) == [.missingFolder])
    }

    @Test("A symlinked profile folder or account file is refused, never followed")
    func refusesSymlinks() throws {
        let home = try Home()
        let real = try Home()
        try real.makeFolder("profile/projects")
        try FileManager.default.createSymbolicLink(
            at: home.url.appendingPathComponent(".claude-linked"),
            withDestinationURL: real.url.appendingPathComponent("profile")
        )
        try home.makeFolder(".codex-linked")
        try real.write("auth.json", "{}")
        try FileManager.default.createSymbolicLink(
            at: home.url.appendingPathComponent(".codex-linked/auth.json"),
            withDestinationURL: real.url.appendingPathComponent("auth.json")
        )

        var inspector = ProfileInspector()
        let readiness = inspector.inspect(homeDirectory: home.url)
        #expect(home.state(readiness, ".claude-linked") == .symlinkRefused)
        #expect(home.state(readiness, ".codex-linked") == .symlinkRefused)
    }

    @Test("A sign-in that happens while the wizard waits is picked up, and an unchanged file is not read again")
    func noticesSignIn() throws {
        let home = try Home()
        try home.makeFolder(".claude-work/projects")
        var inspector = ProfileInspector()
        #expect(home.state(inspector.inspect(homeDirectory: home.url), ".claude-work") == .notSignedIn)

        try home.write(".claude-work/.claude.json", "{\"oauthAccount\": {\"organizationType\": \"claude_pro\"}}")
        #expect(home.state(inspector.inspect(homeDirectory: home.url), ".claude-work") == .signedIn(plan: "Pro"))

        // The answer is cached while size and modification time stay the same: a file that can no longer be read
        // at all still gives the same answer, which it could not if it were decoded again.
        let file = home.url.appendingPathComponent(".claude-work/.claude.json")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        #expect(home.state(inspector.inspect(homeDirectory: home.url), ".claude-work") == .signedIn(plan: "Pro"))
        // A fresh inspector has nothing cached and cannot read it.
        var cold = ProfileInspector()
        #expect(home.state(cold.inspect(homeDirectory: home.url), ".claude-work") == .notSignedIn)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    @Test("A profile folder with an unreadable account file counts as not signed in")
    func malformedAccountFile() throws {
        let home = try Home()
        try home.makeFolder(".claude-work/projects")
        try home.write(".claude-work/.claude.json", "not json at all")
        var inspector = ProfileInspector()
        #expect(home.state(inspector.inspect(homeDirectory: home.url), ".claude-work") == .notSignedIn)
    }

    @Test("Folders that only look like profiles are ignored")
    func ignoresLookAlikes() throws {
        let home = try Home()
        try home.makeFolder(".claude-mem/cache")
        try home.makeFolder(".claudette")
        try home.makeFolder(".codex-bad name")
        try home.makeFolder("claude")
        var inspector = ProfileInspector()
        let readiness = inspector.inspect(homeDirectory: home.url)
        #expect(readiness.map(\.directory.path).contains { $0.hasSuffix(".claudette") } == false)
        #expect(readiness.map(\.directory.path).contains { $0.hasSuffix("bad name") } == false)
        #expect(readiness.map(\.directory.path).contains { $0.hasSuffix("/claude") } == false)
        // `.claude-mem` is a valid suffix, so it is listed — as a folder that is not a profile.
        #expect(home.state(readiness, ".claude-mem") == .notAProfile)
    }
}

@Suite("Profile suffix parity")
struct ProfileSuffixParityTests {
    /// Names discovery and the wizard must agree on.
    static let names = [
        "work", "Work", "personal", "a", "a1", "a_b", "a.b", "team.2", "_", ".hidden",
        String(repeating: "x", count: 24), String(repeating: "x", count: 25),
        "", "bad name", "a/b", "ünicode", "emoji🙂", "-", "a-b",
    ]

    @Test("Discovery accepts exactly the suffixes the wizard accepts, apart from the two the wizard rejects", arguments: names)
    func parity(name: String) {
        let folder = ".claude-\(name)"
        let discovered = ProfileDiscovery.variant(of: folder, provider: .claude)
        let suffix = try? ProfileSuffix(name)
        #expect(discovered == suffix?.value)
        if let suffix {
            #expect(suffix.folderName(for: .claude) == folder)
        }
    }

    @Test("The wizard refuses the two relative names an older rule let through")
    func relativeNames() {
        for name in [".", ".."] {
            #expect(throws: ValidationError.self) { _ = try ProfileSuffix(name) }
            #expect(ProfileDiscovery.variant(of: ".claude-\(name)", provider: .claude) == nil)
        }
    }

    @Test("The default folder has no suffix, and an unrelated name has no variant")
    func defaults() {
        #expect(ProfileDiscovery.variant(of: ".claude", provider: .claude) == "")
        #expect(ProfileDiscovery.variant(of: ".codex", provider: .codex) == "")
        #expect(ProfileDiscovery.variant(of: ".claude", provider: .codex) == nil)
        #expect(ProfileDiscovery.variant(of: ".claude-", provider: .claude) == nil)
        #expect(ProfileDiscovery.maximumVariantLength == ProfileSuffix.maximumLength)
    }

    @Test("The sign-in commands name the folder the suffix builds")
    func commands() throws {
        let suffix = try ProfileSuffix("work")
        #expect(SecondAccountCommands.signIn(provider: .claude, suffix: suffix) == ["CLAUDE_CONFIG_DIR=~/.claude-work claude"])
        #expect(SecondAccountCommands.signIn(provider: .codex, suffix: suffix) == ["mkdir -p ~/.codex-work && CODEX_HOME=~/.codex-work codex login"])
    }
}
