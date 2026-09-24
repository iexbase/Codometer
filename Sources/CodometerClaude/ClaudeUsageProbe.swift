import CodometerCore
import CodometerPlatform
import Foundation

public enum ClaudeProbeError: Error, Equatable, Sendable, CustomStringConvertible {
    case executable(ExecutableLookupError)
    case process(ProcessRunError)
    case commandFailed(exit: ProcessExit, message: String)
    case output(ClaudeUsageParseError)

    public var description: String {
        switch self {
        case .executable(let error): "Claude Code: \(error.description)"
        case .process(let error): error.description
        case let .commandFailed(exit, message): "claude exited with \(exit): \(message)"
        case .output(let error): error.description
        }
    }

    public var issueKind: TrackerIssue.Kind {
        switch self {
        case .executable(.notFound): .executableMissing
        case .executable(.untrusted): .executableUntrusted
        case .process(.timedOut): .timedOut
        case .process: .commandFailed
        case .commandFailed: .commandFailed
        case .output(.signedOut), .output(.notSubscription): .signedOut
        case .output: .unexpectedOutput
        }
    }
}

/// Reads Claude subscription limits by running the official, signature-verified `claude` CLI.
///
/// Claude Code makes the request with its own credentials; the app never touches tokens.
/// The command is local (`/usage`) and does not consume model usage.
public actor ClaudeUsageProbe {
    public static let arguments = ["--print", "--no-session-persistence", "--strict-mcp-config", "/usage"]
    public static let timeout: Duration = .seconds(45)
    public static let maximumOutputBytes = 512 * 1_024
    /// `claude --version` prints one short line; it never needs the usage command's budget.
    public static let versionArguments = ["--version"]
    public static let versionTimeout: Duration = .seconds(5)
    public static let maximumVersionOutputBytes = 8 * 1_024
    /// How long the version step waits for the serial gate before reporting an unknown version.
    ///
    /// "Check System" reads the executable first and has ten seconds for everything, while the usage command that
    /// may be holding the gate has forty-five of its own. Two seconds here keeps the whole check inside its budget
    /// (2 s waiting + 5 s `versionTimeout` + 3 s for the history quick check) instead of queueing behind a probe.
    /// Nothing is lost: the version is read on the next pull, and the caller shows "version unknown" meanwhile.
    public static let versionGateTimeout: Duration = .seconds(2)

    private let locator: TrustedExecutableLocator
    private let runner: ProcessRunner
    private let homeDirectory: URL
    private let workingDirectory: URL
    private let gate = AsyncSerialGate()
    /// The version of the binary with this metadata; re-read only when the binary changes (item 18).
    private var versionCache: (metadata: FileMetadata, version: String?)?
    /// The last executable facts, keyed by the binary's metadata, so Diagnostics costs one `lstat` while nothing moves.
    private var diagnosticsCache: (metadata: FileMetadata, value: ExecutableDiagnostics)?
    /// The signature of the last binary this probe looked at, or `nil` before the first look.
    ///
    /// Remembered so a caller that cannot wait — onboarding's readiness read — can report what the app already
    /// knows. Reading this inspects nothing: the first real look reads the whole binary to check its signature and
    /// takes a second or two on a large CLI.
    public private(set) var lastSignature: ExecutableDiagnostics.Signature?

    public init(
        locator: TrustedExecutableLocator,
        runner: ProcessRunner,
        homeDirectory: URL,
        workingDirectory: URL
    ) {
        self.locator = locator
        self.runner = runner
        self.homeDirectory = homeDirectory
        self.workingDirectory = workingDirectory
    }

    /// The resolved binary; its modification also serves as a key for resetting failure breakers.
    public func executable() async throws(ClaudeProbeError) -> URL {
        do throws(ExecutableLookupError) {
            return try await locator.locate(
                candidates: ClaudeProfileLayout.executableCandidates(homeDirectory: homeDirectory),
                publisher: .anthropic
            )
        } catch {
            throw .executable(error)
        }
    }

    /// Runs at most one `claude` process at a time across all profiles.
    public func fetch(layout: ClaudeProfileLayout) async throws(ClaudeProbeError) -> UsageReading {
        try await fetchReport(layout: layout).reading
    }

    /// The reading plus what the output's layout looked like, for the monitor's format-drift counters (item 18).
    public func fetchReport(
        layout: ClaudeProfileLayout
    ) async throws(ClaudeProbeError) -> (reading: UsageReading, stats: ClaudeParseStats) {
        await gate.acquire()
        let outcome: Result<(reading: UsageReading, stats: ClaudeParseStats), ClaudeProbeError>
        do throws(ClaudeProbeError) {
            outcome = .success(try await runProbe(layout: layout))
        } catch {
            outcome = .failure(error)
        }
        await gate.release()
        return try outcome.get()
    }

    private func runProbe(
        layout: ClaudeProfileLayout
    ) async throws(ClaudeProbeError) -> (reading: UsageReading, stats: ClaudeParseStats) {
        let binary = try await executable()
        let environment = ChildEnvironment.minimal(
            homeDirectory: homeDirectory.path,
            adding: layout.environmentOverrides.merging(["DISABLE_AUTOUPDATER": "1"]) { current, _ in current }
        )
        let request = ProcessRequest(
            executable: binary,
            arguments: Self.arguments,
            environment: environment,
            workingDirectory: workingDirectory
        )

        let result: ProcessResult
        do throws(ProcessRunError) {
            result = try await runner.run(request, timeout: Self.timeout, maximumOutputBytes: Self.maximumOutputBytes)
        } catch {
            throw .process(error)
        }

        let output = String(decoding: result.standardOutput, as: UTF8.self)
        guard result.exit.isSuccess else {
            let message = DisplayText.sanitize(
                String(decoding: result.standardError, as: UTF8.self) + " " + output,
                maximumLength: 200
            ) ?? ""
            throw .commandFailed(exit: result.exit, message: message)
        }
        do throws(ClaudeUsageParseError) {
            return try ClaudeUsageReportParser.parseReport(output, now: Date())
        } catch {
            throw .output(error)
        }
    }

    // MARK: - Diagnostics (pull-only, item 18)

    /// The CLI's version, spawned at most once per binary.
    ///
    /// The result is cached by the binary's metadata, so `claude --version` runs during "Check System" and on the
    /// first pull after the binary changed, never on a schedule. It takes the same serial gate as the usage command,
    /// so it never overlaps a probe; `waitsForGate == false` gives up instead of queueing behind a 45 s usage run,
    /// which is what the Diagnostics pane's 5 s pull wants. A caller that does wait waits at most
    /// `versionGateTimeout` and then reports no version, so a usage run in flight cannot push "Check System" past
    /// its own budget.
    public func version(waitsForGate: Bool = true) async -> String? {
        guard let binary = try? await executable(), let metadata = SecureFileIO.metadata(at: binary) else { return nil }
        if let cached = versionCache, cached.metadata == metadata { return cached.version }
        guard waitsForGate else { return nil }
        guard await gate.acquire(timeout: Self.versionGateTimeout) else { return nil }
        // Another caller may have run it while this one waited.
        if let cached = versionCache, cached.metadata == metadata {
            await gate.release()
            return cached.version
        }
        let output = await runVersion(binary: binary)
        await gate.release()
        let version = output.flatMap(ClaudeVersionParser.version(in:))
        versionCache = (metadata, version)
        return version
    }

    /// Every install location with its signature, for "Check System".
    public func inspectCandidates() async -> [CandidateInspection] {
        await locator.inspect(
            candidates: ClaudeProfileLayout.executableCandidates(homeDirectory: homeDirectory),
            publisher: .anthropic
        )
    }

    /// The resolved binary as Diagnostics shows it. Cached by the binary's metadata: while nothing changes this is
    /// one `lstat` and no signature work.
    ///
    /// - Parameter readsVersion: run `claude --version` when the cache is stale. The pane's periodic pull passes
    ///   `false` once it has a version, so nothing is spawned on a schedule.
    public func executableDiagnostics(readsVersion: Bool = true) async -> ExecutableDiagnostics {
        let candidates = ClaudeProfileLayout.executableCandidates(homeDirectory: homeDirectory)
        let inspections = await locator.inspect(candidates: candidates, publisher: .anthropic)
        let chosen = inspections.first(where: \.isTrusted) ?? inspections.first { $0.exists }
        guard let chosen, let metadata = chosen.metadata else {
            diagnosticsCache = nil
            lastSignature = .notFound
            return ExecutableDiagnostics(
                path: candidates.first?.path ?? "",
                homeDirectory: homeDirectory.path,
                version: nil,
                signature: .notFound,
                modifiedAt: nil,
                sizeBytes: nil
            )
        }
        lastSignature = chosen.signature
        if let cached = diagnosticsCache, cached.metadata == metadata,
           Self.cacheAnswers(cached.value, readsVersion: readsVersion) {
            return cached.value
        }
        let version = await version(waitsForGate: readsVersion)
        let value = ExecutableDiagnostics(
            path: chosen.url.path,
            homeDirectory: homeDirectory.path,
            version: version,
            signature: chosen.signature,
            modifiedAt: metadata.modifiedAt,
            sizeBytes: Int64(clamping: metadata.size)
        )
        diagnosticsCache = (metadata, value)
        return value
    }

    /// Whether a cached entry answers this request.
    ///
    /// An entry recorded by a caller that skipped the version (`readsVersion: false`) has no version in it, and the
    /// entry is keyed by the binary's metadata: serving it to a caller that does want one would hide the version
    /// until the binary changed. Running the version again costs nothing when it is already known, because
    /// `version(waitsForGate:)` answers from its own cache and only spawns a process for a binary it has not seen.
    static func cacheAnswers(_ cached: ExecutableDiagnostics, readsVersion: Bool) -> Bool {
        !readsVersion || cached.version != nil
    }

    private func runVersion(binary: URL) async -> String? {
        let request = ProcessRequest(
            executable: binary,
            arguments: Self.versionArguments,
            environment: ChildEnvironment.minimal(
                homeDirectory: homeDirectory.path,
                adding: ["DISABLE_AUTOUPDATER": "1"]
            ),
            workingDirectory: workingDirectory
        )
        guard
            let result = try? await runner.run(
                request,
                timeout: Self.versionTimeout,
                maximumOutputBytes: Self.maximumVersionOutputBytes
            ),
            result.exit.isSuccess
        else { return nil }
        return String(decoding: result.standardOutput, as: UTF8.self)
    }
}

/// Reads the version out of `claude --version` output ("2.1.12 (Claude Code)").
public enum ClaudeVersionParser {
    /// Longest output looked at; a version is always on the first line.
    static let maximumScannedBytes = 256

    nonisolated(unsafe) private static let pattern = /^v?(?<version>\d{1,4}\.\d{1,4}\.\d{1,6})\b/

    /// `nil` when the output does not start with a version.
    public static func version(in output: String) -> String? {
        let head = String(output.prefix(maximumScannedBytes))
        guard let line = head.split(whereSeparator: \.isNewline).first else { return nil }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let match = trimmed.prefixMatch(of: pattern) else { return nil }
        return String(match.output.version)
    }
}
