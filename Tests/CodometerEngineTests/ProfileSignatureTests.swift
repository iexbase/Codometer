import CodometerCore
@testable import CodometerEngine
import CodometerPlatform
import Foundation
import Testing

/// `ProfileReadiness.cli`: what the app already knows about a provider's CLI, shown beside the profile folders
/// onboarding offers. Nothing here starts a process — the signature comes from inspecting the file.
@Suite("Profile readiness signatures")
struct ProfileSignatureTests {
    private static let anthropic = ExecutableDiagnostics.Signature.trusted(publisher: "Anthropic PBC", teamID: "Q6L2SF6YDW")

    /// A home with one Claude and one Codex profile folder, each holding a marker the CLI itself creates.
    private func home() throws -> TemporaryDirectory {
        let home = try TemporaryDirectory()
        for path in [".claude/projects", ".codex/sessions"] {
            try FileManager.default.createDirectory(
                at: home.url.appendingPathComponent(path, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        return home
    }

    @Test("The inspector puts each provider's signature on that provider's rows")
    func inspectorCarriesSignatures() throws {
        let home = try home()
        var inspector = ProfileInspector()
        let readiness = inspector.inspect(
            homeDirectory: home.url,
            signatures: [.claude: Self.anthropic, .codex: .unsigned]
        )
        #expect(readiness.map(\.provider) == [.claude, .codex])
        #expect(readiness.first { $0.provider == .claude }?.cli == Self.anthropic)
        #expect(readiness.first { $0.provider == .codex }?.cli == .unsigned)
    }

    @Test("A provider the caller says nothing about keeps a nil signature")
    func missingSignatureStaysNil() throws {
        let home = try home()
        var inspector = ProfileInspector()
        let readiness = inspector.inspect(homeDirectory: home.url, signatures: [.claude: Self.anthropic])
        #expect(readiness.first { $0.provider == .claude }?.cli == Self.anthropic)
        #expect(readiness.first { $0.provider == .codex }?.cli == nil)
    }

    /// The engine used to call `inspect(homeDirectory:accounts:)` and let `signatures` default to `[:]`, so every
    /// row reached onboarding with `cli == nil` whatever the app knew about the CLIs.
    @Test("Once the CLIs have been looked at, every row carries a signature")
    func engineFillsEveryRowAfterWarming() async throws {
        let home = try home()
        let engine = TrackerEngine(
            dependencies: EngineDependencies.live(homeDirectory: home.url, directories: AppDirectories(root: home.url), history: nil)
        )
        await engine.warmExecutableSignatures()
        let readiness = await engine.inspectProfiles()
        #expect(readiness.map(\.provider) == [.claude, .codex])
        // Whatever this Mac has installed, every row carries an answer: `.notFound` is one, `nil` was the bug.
        #expect(readiness.allSatisfy { $0.cli != nil })
        // The wizard asks again every two seconds; the answer must not wander.
        #expect(await engine.inspectProfiles() == readiness)
        // Warming again is free, and changes nothing.
        await engine.warmExecutableSignatures()
        #expect(await engine.inspectProfiles() == readiness)
    }

    /// The step that shows this list draws "no profiles found" while it is empty, so the readiness read must never
    /// wait for a signature check: reading a large CLI binary to verify it takes a second or two the first time.
    @Test("A readiness read never waits for a signature check")
    func readinessNeverWaits() async throws {
        let home = try home()
        let engine = TrackerEngine(
            dependencies: EngineDependencies.live(homeDirectory: home.url, directories: AppDirectories(root: home.url), history: nil)
        )
        let clock = ContinuousClock()
        let started = clock.now
        let readiness = await engine.inspectProfiles()
        let took = clock.now - started
        #expect(readiness.count == 2)
        #expect(took < .milliseconds(500), "a cold readiness read took \(took)")
        // Nothing has looked at a CLI yet, so there is nothing to report about one.
        #expect(readiness.allSatisfy { $0.cli == nil })
    }
}
