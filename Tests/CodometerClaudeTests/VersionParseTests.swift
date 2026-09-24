@testable import CodometerClaude
import CodometerCore
import Foundation
import Testing

@Suite("Claude version parsing")
struct VersionParseTests {
    @Test("Reads the version `claude --version` prints")
    func realOutput() {
        #expect(ClaudeVersionParser.version(in: "2.1.12 (Claude Code)\n") == "2.1.12")
        #expect(ClaudeVersionParser.version(in: "2.1.12\n") == "2.1.12")
        #expect(ClaudeVersionParser.version(in: "  2.1.12 (Claude Code)") == "2.1.12")
        #expect(ClaudeVersionParser.version(in: "v0.9.3 (Claude Code)") == "0.9.3")
    }

    @Test("Only the first line counts")
    func firstLineOnly() {
        #expect(ClaudeVersionParser.version(in: "1.0.0 (Claude Code)\n9.9.9 (other)") == "1.0.0")
        #expect(ClaudeVersionParser.version(in: "warning: update available\n2.1.12 (Claude Code)") == nil)
    }

    @Test("Anything that is not a version reads as unknown")
    func garbage() {
        #expect(ClaudeVersionParser.version(in: "") == nil)
        #expect(ClaudeVersionParser.version(in: "\n\n") == nil)
        #expect(ClaudeVersionParser.version(in: "Claude Code 2.1.12") == nil)
        #expect(ClaudeVersionParser.version(in: "2.1 (Claude Code)") == nil)
        #expect(ClaudeVersionParser.version(in: "unknown") == nil)
    }

    @Test("A very long line is not scanned past its head")
    func bounded() {
        let long = String(repeating: "x", count: 10_000)
        #expect(ClaudeVersionParser.version(in: long) == nil)
        #expect(ClaudeVersionParser.version(in: "3.0.1 " + long) == "3.0.1")
    }

    /// The executable cache is keyed by the binary's metadata, so a pull that skipped the version must not become
    /// the answer for a later pull that wants one: that would hide the version until the binary changed.
    @Test("A cached entry without a version never answers a caller that reads one")
    func versionlessCacheIsNotAnAnswer() {
        func entry(version: String?) -> ExecutableDiagnostics {
            ExecutableDiagnostics(
                path: "/Users/someone/.local/bin/claude",
                homeDirectory: "/Users/someone",
                version: version,
                signature: .trusted(publisher: "Anthropic PBC", teamID: "Q6L2SF6YDW"),
                modifiedAt: nil,
                sizeBytes: nil
            )
        }
        #expect(!ClaudeUsageProbe.cacheAnswers(entry(version: nil), readsVersion: true))
        #expect(ClaudeUsageProbe.cacheAnswers(entry(version: nil), readsVersion: false))
        #expect(ClaudeUsageProbe.cacheAnswers(entry(version: "2.1.12"), readsVersion: true))
        #expect(ClaudeUsageProbe.cacheAnswers(entry(version: "2.1.12"), readsVersion: false))
    }
}
