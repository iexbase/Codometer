import CodometerCore
import Foundation
import Security

/// A software publisher identified by its Apple Developer Team ID.
public struct TrustedPublisher: Hashable, Sendable {
    public let name: String
    public let teamIdentifier: String

    public init(name: String, teamIdentifier: String) {
        precondition(
            teamIdentifier.count == 10 && teamIdentifier.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber) },
            "a Team ID is ten uppercase letters or digits"
        )
        self.name = name
        self.teamIdentifier = teamIdentifier
    }

    public static let anthropic = TrustedPublisher(name: "Anthropic PBC", teamIdentifier: "Q6L2SF6YDW")
    public static let openAI = TrustedPublisher(name: "OpenAI OpCo, LLC", teamIdentifier: "2DC432GLL2")

    /// Apple-anchored certificate chain whose leaf belongs to this team.
    var requirementText: String {
        "anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
    }
}

public enum CodeSignatureError: Error, Equatable, Sendable, CustomStringConvertible {
    case notFound(path: String)
    case unsigned(path: String)
    case wrongPublisher(path: String, expected: String)
    case invalid(path: String, status: Int32)

    public var description: String {
        switch self {
        case .notFound(let path): "executable not found: \(path)"
        case .unsigned(let path): "executable is not code-signed: \(path)"
        case let .wrongPublisher(path, expected): "executable is not signed by \(expected): \(path)"
        case let .invalid(path, status): "code signature check failed (\(status)): \(path)"
        }
    }
}

/// Verifies that an executable is signed by an expected publisher before the app runs it.
///
/// Binaries on common install paths live in user-writable folders; checking the signature
/// means a file planted there by anything else is refused rather than executed.
public actor CodeSignatureVerifier {
    private struct CacheKey: Hashable {
        let path: String
        let metadata: FileMetadata
        let publisher: TrustedPublisher
    }

    private struct InfoKey: Hashable {
        let path: String
        let metadata: FileMetadata
    }

    /// Longest signing-information cache; the app inspects a handful of binaries.
    static let maximumCachedSigningInfo = 32

    private var verified: Set<CacheKey> = []
    private var signingInfoCache: [InfoKey: SigningInfo?] = [:]
    /// Apple's roots: platform binaries, Mac App Store apps and Developer ID apps all chain up to them. Built once
    /// per verifier, inside the actor (a `SecRequirement` is not `Sendable`).
    private lazy var appleAnchor: SecRequirement? = {
        var requirement: SecRequirement?
        let status = SecRequirementCreateWithString("anchor apple generic" as CFString, SecCSFlags(), &requirement)
        return status == errSecSuccess ? requirement : nil
    }()

    public init() {}

    /// What the file's signature says about who made it, or `nil` when it carries no signature.
    ///
    /// Cached by the file's metadata, so repeated Diagnostics pulls cost one `lstat`. Reads the signature only; it
    /// never runs the file and never checks it against a publisher requirement (see `verify`).
    public func signingInfo(_ url: URL) -> SigningInfo? {
        guard let metadata = SecureFileIO.metadata(at: url), metadata.isRegularFile else { return nil }
        let key = InfoKey(path: url.path, metadata: metadata)
        if let cached = signingInfoCache[key] { return cached }

        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &staticCode) == errSecSuccess, let staticCode else {
            return remember(nil, for: key)
        }
        var information: CFDictionary?
        let status = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        )
        guard
            status == errSecSuccess,
            let dictionary = information as? [String: Any],
            // An unsigned file answers with a dictionary that has no signing identifier (and sometimes with
            // errSecCSUnsigned); either way there is nothing to report.
            let identifier = dictionary[kSecCodeInfoIdentifier as String] as? String
        else {
            return remember(nil, for: key)
        }
        let anchored = SecStaticCodeCheckValidity(staticCode, SecCSFlags(), appleAnchor) == errSecSuccess
        let info = SigningInfo(
            teamIdentifier: dictionary[kSecCodeInfoTeamIdentifier as String] as? String,
            identifier: identifier,
            isAppleAnchored: anchored
        )
        return remember(info, for: key)
    }

    private func remember(_ info: SigningInfo?, for key: InfoKey) -> SigningInfo? {
        if signingInfoCache.count >= Self.maximumCachedSigningInfo { signingInfoCache.removeAll() }
        signingInfoCache[key] = info
        return info
    }

    public func verify(_ url: URL, publisher: TrustedPublisher) throws(CodeSignatureError) {
        let path = url.path
        guard let metadata = SecureFileIO.metadata(at: url), metadata.isRegularFile else {
            throw .notFound(path: path)
        }
        let key = CacheKey(path: path, metadata: metadata, publisher: publisher)
        if verified.contains(key) { return }

        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            throw .invalid(path: path, status: createStatus)
        }
        var requirement: SecRequirement?
        let requirementStatus = SecRequirementCreateWithString(
            publisher.requirementText as CFString,
            SecCSFlags(),
            &requirement
        )
        guard requirementStatus == errSecSuccess, let requirement else {
            throw .invalid(path: path, status: requirementStatus)
        }
        let status = SecStaticCodeCheckValidity(staticCode, SecCSFlags(), requirement)
        switch status {
        case errSecSuccess:
            if verified.count > 64 { verified.removeAll() }
            verified.insert(key)
        case errSecCSUnsigned:
            throw .unsigned(path: path)
        case errSecCSReqFailed:
            throw .wrongPublisher(path: path, expected: publisher.name)
        default:
            throw .invalid(path: path, status: status)
        }
    }
}

public enum ExecutableLookupError: Error, Equatable, Sendable, CustomStringConvertible {
    case notFound(searched: [String])
    case untrusted(CodeSignatureError)

    public var description: String {
        switch self {
        case .notFound(let searched): "not found in: \(searched.joined(separator: ", "))"
        case .untrusted(let error): error.description
        }
    }
}

/// Finds the first candidate executable that exists and carries the expected signature.
public struct TrustedExecutableLocator: Sendable {
    let verifier: CodeSignatureVerifier

    public init(verifier: CodeSignatureVerifier) {
        self.verifier = verifier
    }

    public func locate(candidates: [URL], publisher: TrustedPublisher) async throws(ExecutableLookupError) -> URL {
        var firstRejection: CodeSignatureError?
        for candidate in candidates {
            let resolved = candidate.resolvingSymlinksInPath()
            guard FileManager.default.isExecutableFile(atPath: resolved.path) else { continue }
            do throws(CodeSignatureError) {
                try await verifier.verify(resolved, publisher: publisher)
                return resolved
            } catch {
                firstRejection = firstRejection ?? error
            }
        }
        if let firstRejection {
            throw .untrusted(firstRejection)
        }
        throw .notFound(searched: candidates.map(\.path))
    }
}

/// What a file's code signature says about who made it (`SecCodeCopySigningInformation`).
public struct SigningInfo: Hashable, Sendable {
    /// The Apple Developer Team ID; `nil` for Apple's own platform binaries and for ad-hoc signatures.
    public let teamIdentifier: String?
    /// The signing identifier, usually a bundle id or the tool's name. A signature always carries one.
    public let identifier: String
    /// The certificate chain ends at an Apple root (a platform binary, a Mac App Store app or a Developer ID app).
    public let isAppleAnchored: Bool

    public init(teamIdentifier: String?, identifier: String, isAppleAnchored: Bool) {
        self.teamIdentifier = teamIdentifier
        self.identifier = identifier
        self.isAppleAnchored = isAppleAnchored
    }
}

/// One install location as "Check System" and the Diagnostics pane see it.
public struct CandidateInspection: Hashable, Sendable {
    public let url: URL
    /// A regular, executable file is there.
    public let exists: Bool
    public let signature: ExecutableDiagnostics.Signature
    public let metadata: FileMetadata?

    public init(url: URL, exists: Bool, signature: ExecutableDiagnostics.Signature, metadata: FileMetadata?) {
        self.url = url
        self.exists = exists
        self.signature = signature
        self.metadata = metadata
    }

    /// Signed by the publisher the app expects, so the app is willing to run it.
    public var isTrusted: Bool {
        if case .trusted = signature { return true }
        return false
    }
}

extension TrustedExecutableLocator {
    /// Every candidate's existence and signature, without choosing one.
    ///
    /// Diagnostics shows all of them so a shadowing copy on `PATH` is visible; nothing here runs a binary.
    public func inspect(candidates: [URL], publisher: TrustedPublisher) async -> [CandidateInspection] {
        var inspections: [CandidateInspection] = []
        for candidate in candidates {
            let resolved = candidate.resolvingSymlinksInPath()
            let metadata = SecureFileIO.metadata(at: resolved)
            guard
                let metadata,
                metadata.isRegularFile,
                FileManager.default.isExecutableFile(atPath: resolved.path)
            else {
                inspections.append(CandidateInspection(url: resolved, exists: false, signature: .notFound, metadata: nil))
                continue
            }
            inspections.append(
                CandidateInspection(
                    url: resolved,
                    exists: true,
                    signature: await signature(of: resolved, publisher: publisher),
                    metadata: metadata
                )
            )
        }
        return inspections
    }

    private func signature(of url: URL, publisher: TrustedPublisher) async -> ExecutableDiagnostics.Signature {
        do throws(CodeSignatureError) {
            try await verifier.verify(url, publisher: publisher)
            let teamID = await verifier.signingInfo(url)?.teamIdentifier ?? publisher.teamIdentifier
            return .trusted(publisher: publisher.name, teamID: teamID)
        } catch {
            switch error {
            case .notFound: return .notFound
            case .unsigned: return .unsigned
            case .wrongPublisher: return .untrusted(teamID: await verifier.signingInfo(url)?.teamIdentifier)
            case .invalid(_, let status): return .invalid(status: status)
            }
        }
    }
}
