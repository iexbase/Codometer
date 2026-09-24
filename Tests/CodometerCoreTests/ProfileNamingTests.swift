import CodometerCore
import Foundation
import Testing

@Suite("Profile naming")
struct ProfileNamingTests {
    @Test("Valid suffixes", arguments: ["work", "Work_2", "a", "client.acme", "..x", String(repeating: "z", count: 24)])
    func valid(raw: String) throws {
        #expect(try ProfileSuffix(raw).value == raw)
    }

    @Test("Invalid suffixes", arguments: ["", ".", "..", "a b", "work-2", "work/..", "личный", "wörk", "a\u{0}", "~", String(repeating: "z", count: 25)])
    func invalid(raw: String) {
        #expect(throws: ValidationError.self) { try ProfileSuffix(raw) }
    }

    @Test("Folder names per provider")
    func folderNames() throws {
        let suffix = try ProfileSuffix("work")
        #expect(suffix.folderName(for: .claude) == ".claude-work")
        #expect(suffix.folderName(for: .codex) == ".codex-work")
        #expect(suffix.description == "work")
    }

    @Test("Sign-in commands for both providers")
    func commands() throws {
        let suffix = try ProfileSuffix("work")
        #expect(SecondAccountCommands.signIn(provider: .claude, suffix: suffix) == ["CLAUDE_CONFIG_DIR=~/.claude-work claude"])
        #expect(SecondAccountCommands.signIn(provider: .codex, suffix: suffix) == ["mkdir -p ~/.codex-work && CODEX_HOME=~/.codex-work codex login"])
        let dotted = try ProfileSuffix("client.v2")
        #expect(SecondAccountCommands.signIn(provider: .claude, suffix: dotted) == ["CLAUDE_CONFIG_DIR=~/.claude-client.v2 claude"])
    }

    @Test("Readiness ids combine provider and path; plans are sanitised")
    func readiness() throws {
        let directory = try ProfileDirectory(validating: "/Users/tester/.claude-work")
        let readiness = ProfileReadiness(provider: .claude, directory: directory, state: .signedIn(plan: "  Max\n"), cli: .notFound)
        #expect(readiness.id == "claude:/Users/tester/.claude-work")
        #expect(readiness.state == .signedIn(plan: "Max"))
        let long = ProfileReadiness(provider: .claude, directory: directory, state: .signedIn(plan: String(repeating: "p", count: 90)), cli: nil)
        guard case .signedIn(let plan?) = long.state else {
            Issue.record("expected a plan")
            return
        }
        #expect(plan.count == ProfileReadiness.maximumPlanLength)
        #expect(ProfileReadiness(provider: .codex, directory: directory, state: .symlinkRefused, cli: nil).state == .symlinkRefused)
    }
}
