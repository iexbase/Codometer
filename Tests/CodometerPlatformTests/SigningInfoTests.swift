import CodometerCore
@testable import CodometerPlatform
import Foundation
import Testing

@Suite("Code signing information")
struct SigningInfoTests {
    private let systemBinary = URL(fileURLWithPath: "/bin/ls")

    @Test("An Apple platform binary is anchored to Apple and carries no team id")
    func platformBinary() async {
        let verifier = CodeSignatureVerifier()
        let info = await verifier.signingInfo(systemBinary)
        #expect(info != nil)
        #expect(info?.isAppleAnchored == true)
        #expect(info?.teamIdentifier == nil)
        #expect(info?.identifier.isEmpty == false)
    }

    @Test("The same file answers from the cache")
    func cached() async {
        let verifier = CodeSignatureVerifier()
        let first = await verifier.signingInfo(systemBinary)
        let second = await verifier.signingInfo(systemBinary)
        #expect(first == second)
    }

    @Test("A file that is not there has no signing information")
    func missingFile() async throws {
        let directory = try TemporaryDirectory()
        let verifier = CodeSignatureVerifier()
        #expect(await verifier.signingInfo(directory.url.appendingPathComponent("nothing")) == nil)
        #expect(await verifier.signingInfo(directory.url) == nil)
    }

    @Test("A plain file carries no signature")
    func unsignedFile() async throws {
        let directory = try TemporaryDirectory()
        let file = directory.url.appendingPathComponent("script.sh")
        try Data("#!/bin/sh\necho hello\n".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        #expect(await CodeSignatureVerifier().signingInfo(file) == nil)
    }

    @Test("Inspecting candidates reports each location without running anything")
    func inspectCandidates() async throws {
        let directory = try TemporaryDirectory()
        let missing = directory.url.appendingPathComponent("claude")
        let plain = directory.url.appendingPathComponent("plain")
        try Data("not a binary".utf8).write(to: plain)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: plain.path)

        let locator = TrustedExecutableLocator(verifier: CodeSignatureVerifier())
        let inspections = await locator.inspect(candidates: [missing, plain, systemBinary], publisher: .anthropic)
        #expect(inspections.count == 3)
        #expect(inspections[0].exists == false)
        #expect(inspections[0].signature == .notFound)
        #expect(inspections[0].metadata == nil)

        #expect(inspections[1].exists)
        #expect(inspections[1].signature == .unsigned)
        #expect(!inspections[1].isTrusted)

        // /bin/ls is signed, but not by Anthropic.
        #expect(inspections[2].exists)
        #expect(!inspections[2].isTrusted)
        if case .untrusted = inspections[2].signature {} else {
            Issue.record("expected an untrusted signature, got \(inspections[2].signature)")
        }
        #expect(inspections[2].metadata?.isRegularFile == true)
    }

    @Test("A directory among the candidates is never treated as an executable")
    func directoryCandidate() async throws {
        let directory = try TemporaryDirectory()
        let folder = directory.url.appendingPathComponent("codex", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let locator = TrustedExecutableLocator(verifier: CodeSignatureVerifier())
        let inspections = await locator.inspect(candidates: [folder], publisher: .openAI)
        #expect(inspections.map(\.signature) == [.notFound])
    }
}
