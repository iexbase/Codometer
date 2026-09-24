import CodometerCore
import CodometerPlatform
import Foundation

public enum CodexProbeError: Error, Equatable, Sendable, CustomStringConvertible {
    case executable(ExecutableLookupError)
    case process(ProcessRunError)
    case timedOut
    case serverClosed
    case serverError(code: Int, message: String)
    case unexpectedResponse(method: String)
    case signedOut
    case noLimits

    public var description: String {
        switch self {
        case .executable(let error): "Codex: \(error.description)"
        case .process(let error): error.description
        case .timedOut: "codex app-server did not answer in time"
        case .serverClosed: "codex app-server exited before answering"
        case let .serverError(code, message): "codex app-server error \(code): \(message)"
        case .unexpectedResponse(let method): "unexpected response to \(method)"
        case .signedOut: "profile is not signed in to ChatGPT"
        case .noLimits: "no rate limits reported"
        }
    }

    public var issueKind: TrackerIssue.Kind {
        switch self {
        case .executable(.notFound): .executableMissing
        case .executable(.untrusted): .executableUntrusted
        case .process, .serverClosed, .serverError: .commandFailed
        case .timedOut: .timedOut
        case .unexpectedResponse, .noLimits: .unexpectedOutput
        case .signedOut: .signedOut
        }
    }
}

public struct CodexProbeResult: Sendable {
    public let identity: AccountIdentity?
    public let reading: UsageReading
    /// The CLI version from the handshake's user agent ("codex_cli_rs/0.154.0 (…)"), when it was readable.
    /// Diagnostics shows it without ever spawning `codex --version`.
    public let cliVersion: String?
}

/// Reads the version out of `codex app-server`'s `InitializeResult.userAgent`.
public enum CodexUserAgent {
    /// Longest user agent looked at.
    static let maximumScannedBytes = 256

    nonisolated(unsafe) private static let pattern = /^[A-Za-z0-9_.-]{1,40}\/(?<version>\d{1,4}\.\d{1,4}\.\d{1,6})\b/

    /// `nil` when the user agent does not start with `<product>/<version>`.
    public static func version(in userAgent: String) -> String? {
        let head = String(userAgent.prefix(maximumScannedBytes)).trimmingCharacters(in: .whitespaces)
        guard let match = head.prefixMatch(of: pattern) else { return nil }
        return String(match.output.version)
    }
}

/// Reads live Codex limits through `codex app-server`, the JSON-RPC interface the official clients use.
///
/// Codex authenticates and refreshes its own tokens; the app only exchanges three read-only
/// requests over stdio and then stops the process.
public actor CodexAppServerProbe {
    public static let exchangeTimeout: Duration = .seconds(30)
    public static let maximumLineBytes = 4 * 1_024 * 1_024
    public static let clientName = "codometer"
    public static let clientVersion = "0.1.0"

    private let locator: TrustedExecutableLocator
    private let registry: ChildProcessRegistry?
    private let homeDirectory: URL
    private let workingDirectory: URL
    private let gate = AsyncSerialGate()
    /// The version from the last successful handshake, kept for Diagnostics (no extra process is ever started).
    private var lastCLIVersion: String?
    /// The last executable facts, keyed by the binary's metadata.
    private var diagnosticsCache: (metadata: FileMetadata, value: ExecutableDiagnostics)?
    /// The signature of the last binary this probe looked at, or `nil` before the first look.
    ///
    /// Remembered so a caller that cannot wait — onboarding's readiness read — can report what the app already
    /// knows. Reading this inspects nothing: the first real look reads the whole binary to check its signature and
    /// takes a second or two on a large CLI.
    public private(set) var lastSignature: ExecutableDiagnostics.Signature?

    public init(
        locator: TrustedExecutableLocator,
        registry: ChildProcessRegistry?,
        homeDirectory: URL,
        workingDirectory: URL
    ) {
        self.locator = locator
        self.registry = registry
        self.homeDirectory = homeDirectory
        self.workingDirectory = workingDirectory
    }

    /// Runs at most one app-server process at a time across all profiles.
    public func fetch(layout: CodexProfileLayout) async throws(CodexProbeError) -> CodexProbeResult {
        await gate.acquire()
        let outcome: Result<CodexProbeResult, CodexProbeError>
        do throws(CodexProbeError) {
            outcome = .success(try await runProbe(layout: layout))
        } catch {
            outcome = .failure(error)
        }
        await gate.release()
        let result = try outcome.get()
        if let version = result.cliVersion {
            lastCLIVersion = version
        }
        return result
    }

    /// The resolved binary; the same lookup the probe itself uses.
    public func executable() async throws(CodexProbeError) -> URL {
        do throws(ExecutableLookupError) {
            return try await locator.locate(
                candidates: CodexProfileLayout.executableCandidates(homeDirectory: homeDirectory),
                publisher: .openAI
            )
        } catch {
            throw .executable(error)
        }
    }

    /// Every install location with its signature, for "Check System".
    public func inspectCandidates() async -> [CandidateInspection] {
        await locator.inspect(
            candidates: CodexProfileLayout.executableCandidates(homeDirectory: homeDirectory),
            publisher: .openAI
        )
    }

    /// The resolved binary as Diagnostics shows it. Cached by the binary's metadata; the version is whatever the
    /// last app-server handshake reported, so nothing is ever spawned for it.
    public func executableDiagnostics() async -> ExecutableDiagnostics {
        let candidates = CodexProfileLayout.executableCandidates(homeDirectory: homeDirectory)
        let inspections = await locator.inspect(candidates: candidates, publisher: .openAI)
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
        if let cached = diagnosticsCache, cached.metadata == metadata, cached.value.version == lastCLIVersion {
            return cached.value
        }
        let value = ExecutableDiagnostics(
            path: chosen.url.path,
            homeDirectory: homeDirectory.path,
            version: lastCLIVersion,
            signature: chosen.signature,
            modifiedAt: metadata.modifiedAt,
            sizeBytes: Int64(clamping: metadata.size)
        )
        diagnosticsCache = (metadata, value)
        return value
    }

    private func runProbe(layout: CodexProfileLayout) async throws(CodexProbeError) -> CodexProbeResult {
        let binary = try await executable()

        let request = ProcessRequest(
            executable: binary,
            // Without this override every start syncs the plugin catalogue (~90 MB) into CODEX_HOME.
            arguments: ["-c", "features.plugins=false", "app-server"],
            environment: ChildEnvironment.minimal(homeDirectory: homeDirectory.path, adding: layout.environmentOverrides),
            workingDirectory: workingDirectory
        )
        let channel: LineChannel
        do throws(ProcessRunError) {
            channel = try LineChannel.launch(request, maximumLineBytes: Self.maximumLineBytes, registry: registry)
        } catch {
            throw .process(error)
        }
        defer { channel.terminate() }

        let outcome = await withTaskGroup(of: Result<CodexProbeResult, CodexProbeError>?.self) { group in
            group.addTask {
                await Self.converse(over: channel)
            }
            group.addTask {
                try? await Task.sleep(for: Self.exchangeTimeout)
                return Task.isCancelled ? nil : .failure(.timedOut)
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            channel.terminate()
            return first ?? .failure(.timedOut)
        }
        return try outcome.get()
    }

    private static func converse(over channel: LineChannel) async -> Result<CodexProbeResult, CodexProbeError> {
        var session = JSONRPCSession(channel: channel)
        do throws(CodexProbeError) {
            let handshake = try await session.call(
                method: "initialize",
                params: InitializeParams(clientInfo: .init(name: clientName, title: "Codometer", version: clientVersion)),
                expecting: InitializeResult.self
            )
            let cliVersion = handshake.userAgent.flatMap(CodexUserAgent.version(in:))
            try session.notify(method: "initialized")
            let account = try await session.call(
                method: "account/read",
                params: AccountReadParams(refreshToken: false),
                expecting: AccountReadResult.self
            )
            if account.account == nil, account.requiresOpenaiAuth {
                throw .signedOut
            }
            let limits: RateLimitsReadResult
            do throws(CodexProbeError) {
                limits = try await session.call(
                    method: "account/rateLimits/read",
                    params: RateLimitsReadParams(excludeResetCreditDetails: true),
                    expecting: RateLimitsReadResult.self
                )
            } catch .serverError(let code, let message) where Self.isAuthenticationError(message) {
                _ = code
                throw .signedOut
            } catch .serverError(let code, _) where code == -32600 || code == -32602 {
                // Older servers reject unknown params; the plain request is always accepted.
                limits = try await session.call(
                    method: "account/rateLimits/read",
                    params: EmptyParams(),
                    expecting: RateLimitsReadResult.self
                )
            }
            let now = Date()
            var snapshots = limits.allSnapshots.map(\.domain)
            if limits.ordinaryUsageAllowed == false, let index = snapshots.firstIndex(where: {
                $0.bucketID == CodexLimitMapper.mainBucketID
            }) {
                snapshots[index] = snapshots[index].markingLimitReached()
            }
            guard let reading = CodexLimitMapper.reading(from: snapshots, capturedAt: now, source: .codexAppServer) else {
                throw .noLimits
            }
            let plan = account.account?.planType ?? snapshots.compactMap(\.planType).first
            let identity = AccountIdentity(
                email: account.account?.email,
                organization: nil,
                plan: account.account?.type == "apiKey" ? "API key" : CodexLimitMapper.planName(plan)
            )
            return .success(CodexProbeResult(
                identity: identity.isEmpty ? nil : identity,
                reading: reading,
                cliVersion: cliVersion
            ))
        } catch {
            return .failure(error)
        }
    }

    static func isAuthenticationError(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("authentication required") || lowered.contains("not logged in")
    }
}

// MARK: - JSON-RPC over newline-delimited stdio

private struct JSONRPCSession {
    private let channel: LineChannel
    private var lines: AsyncStream<Data>.Iterator
    private var nextID = 1
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(channel: LineChannel) {
        self.channel = channel
        lines = channel.lines.makeAsyncIterator()
    }

    mutating func call<Params: Encodable, Result: Decodable>(
        method: String,
        params: Params,
        expecting: Result.Type
    ) async throws(CodexProbeError) -> Result {
        let id = nextID
        nextID += 1
        try send(RequestMessage(id: id, method: method, params: params))

        while let line = await lines.next() {
            guard let header = try? decoder.decode(ResponseHeader.self, from: line), header.id == id else {
                continue // notifications, server requests and unrelated responses
            }
            if let error = header.error {
                throw .serverError(code: error.code, message: DisplayText.sanitize(error.message, maximumLength: 200) ?? "")
            }
            guard let response = try? decoder.decode(ResponseMessage<Result>.self, from: line) else {
                throw .unexpectedResponse(method: method)
            }
            return response.result
        }
        throw Task.isCancelled ? .timedOut : .serverClosed
    }

    func notify(method: String) throws(CodexProbeError) {
        try send(NotificationMessage(method: method))
    }

    private func send(_ message: some Encodable) throws(CodexProbeError) {
        let data: Data
        do {
            data = try encoder.encode(message)
        } catch {
            throw .unexpectedResponse(method: "encode")
        }
        do throws(ProcessRunError) {
            try channel.send(data)
        } catch {
            throw .process(error)
        }
    }
}

private struct RequestMessage<Params: Encodable>: Encodable {
    let id: Int
    let method: String
    let params: Params
}

private struct NotificationMessage: Encodable {
    let method: String
}

private struct ResponseHeader: Decodable {
    struct ErrorBody: Decodable {
        let code: Int
        let message: String
    }

    let id: Int?
    let error: ErrorBody?
}

private struct ResponseMessage<Result: Decodable>: Decodable {
    let result: Result
}

private struct InitializeParams: Encodable {
    struct ClientInfo: Encodable {
        let name: String
        let title: String
        let version: String
    }

    let clientInfo: ClientInfo
}

private struct InitializeResult: Decodable {
    let userAgent: String?
}

private struct AccountReadParams: Encodable {
    let refreshToken: Bool
}

private struct AccountReadResult: Decodable {
    struct Account: Decodable {
        let type: String
        let email: String?
        let planType: String?
    }

    let account: Account?
    let requiresOpenaiAuth: Bool
}

private struct RateLimitsReadParams: Encodable {
    let excludeResetCreditDetails: Bool
}

private struct EmptyParams: Encodable {}

private struct RateLimitsReadResult: Decodable {
    let rateLimits: Snapshot
    let rateLimitsByLimitId: [String: Snapshot]?
    /// The backend's own verdict; `nil` means unknown, never "allowed".
    let ordinaryUsageAllowed: Bool?

    /// Every bucket, with the backward-compatible single view first.
    var allSnapshots: [Snapshot] {
        let extra = (rateLimitsByLimitId ?? [:])
            .sorted { $0.key < $1.key }
            .map { key, snapshot in snapshot.limitId == nil ? snapshot.withLimitID(key) : snapshot }
        return [rateLimits] + extra
    }

    struct Snapshot: Decodable {
        struct Window: Decodable {
            let usedPercent: Double
            let windowDurationMins: Int?
            let resetsAt: Int64?
        }

        struct Credits: Decodable {
            let hasCredits: Bool
            let unlimited: Bool
            let balance: String?
        }

        let limitId: String?
        let limitName: String?
        let primary: Window?
        let secondary: Window?
        let credits: Credits?
        let planType: String?
        let rateLimitReachedType: String?

        func withLimitID(_ id: String) -> Snapshot {
            Snapshot(
                limitId: id,
                limitName: limitName,
                primary: primary,
                secondary: secondary,
                credits: credits,
                planType: planType,
                rateLimitReachedType: rateLimitReachedType
            )
        }

        var domain: CodexLimitSnapshot {
            CodexLimitSnapshot(
                limitID: limitId,
                limitName: limitName,
                primary: primary.map(Self.window),
                secondary: secondary.map(Self.window),
                credits: credits.map {
                    CreditsInfo(hasCredits: $0.hasCredits, isUnlimited: $0.unlimited, balance: $0.balance.flatMap {
                        Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX"))
                    })
                },
                planType: planType,
                isLimitReached: rateLimitReachedType != nil
            )
        }

        private static func window(_ window: Window) -> CodexLimitSnapshot.Window {
            CodexLimitSnapshot.Window(
                usedPercent: window.usedPercent,
                durationMinutes: window.windowDurationMins,
                resetsAt: window.resetsAt.flatMap(EpochSeconds.date)
            )
        }
    }
}
