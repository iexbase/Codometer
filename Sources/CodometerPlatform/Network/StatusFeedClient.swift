import CodometerCore
import Foundation
import Synchronization

/// Why a status feed could not be read. Never shown to the user; Diagnostics reports only that a check failed.
public enum StatusFeedError: Error, Hashable, Sendable, CustomStringConvertible {
    /// The URL is not HTTPS, or its host is not one of the two allowed status hosts.
    case hostNotAllowed
    /// The reply was not HTTP, or it tried to redirect to another host.
    case invalidResponse
    case unacceptableStatus(Int)
    case unacceptableContentType(String)
    /// The body grew past `StatusFeedClient.maximumBodyBytes` and the transfer was abandoned.
    case tooLarge
    case transport(String)

    public var description: String {
        switch self {
        case .hostNotAllowed: "host not allowed"
        case .invalidResponse: "invalid response"
        case .unacceptableStatus(let code): "http \(code)"
        case .unacceptableContentType(let type): "content type \(type)"
        case .tooLarge: "body too large"
        case .transport(let reason): "transport: \(reason)"
        }
    }
}

/// What one fetch produced.
public enum StatusFeedResult: Hashable, Sendable {
    case updated(Data)
    /// The host answered 304: the last body is still current.
    case notModified
}

/// The only code in Codometer that makes a network request, used solely by the opt-in service status
/// check, which is off by default.
///
/// Everything about the session is deliberately narrow: it keeps no cookies and no cache, refuses constrained and
/// expensive networks, never waits for connectivity, times out quickly, accepts only HTTPS to an exact host
/// allowlist, refuses redirects that leave that host, accepts only a JSON 200 or 304, and stops reading a body past
/// 256 KiB. The only thing it remembers between calls is an ETag per URL, in memory.
public actor StatusFeedClient {
    /// Bodies are a few kilobytes; anything approaching this is not a status feed.
    public static let maximumBodyBytes = 256 * 1_024
    public static let requestTimeout: TimeInterval = 10
    public static let resourceTimeout: TimeInterval = 15
    /// No version and no identifier: the hosts learn nothing beyond the request itself.
    public static let userAgent = "Codometer"

    private let allowedHosts: Set<String>
    private let session: URLSession
    private let delegate: RedirectGuard
    /// Per URL, in memory only, dropped when the app quits.
    private var etags: [URL: String] = [:]

    /// - Parameters:
    ///   - allowedHosts: Lowercase host names; a request to any other host fails without touching the network.
    ///   - protocolClasses: Test stubs. `nil` uses the system's, so production never routes through anything else.
    public init(allowedHosts: Set<String> = VendorStatusFeed.allowedHosts, protocolClasses: [AnyClass]? = nil) {
        self.allowedHosts = Set(allowedHosts.map { $0.lowercased() })
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.allowsConstrainedNetworkAccess = false
        configuration.allowsExpensiveNetworkAccess = false
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = Self.requestTimeout
        configuration.timeoutIntervalForResource = Self.resourceTimeout
        configuration.httpMaximumConnectionsPerHost = 1
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        configuration.httpAdditionalHeaders = ["Accept": "application/json", "User-Agent": Self.userAgent]
        if let protocolClasses {
            configuration.protocolClasses = protocolClasses
        }
        let redirectGuard = RedirectGuard()
        delegate = redirectGuard
        session = URLSession(configuration: configuration, delegate: redirectGuard, delegateQueue: nil)
    }

    deinit {
        session.invalidateAndCancel()
    }

    /// Fetches `url`, or reports why it could not be read. Nothing is written to disk at any point.
    public func fetch(_ url: URL) async throws(StatusFeedError) -> StatusFeedResult {
        guard url.scheme?.lowercased() == "https", let host = url.host()?.lowercased(), allowedHosts.contains(host) else {
            throw StatusFeedError.hostNotAllowed
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.httpShouldHandleCookies = false
        if let etag = etags[url] {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            throw StatusFeedError.transport((error as NSError).code.description)
        }
        // Taken, not just read: the record belongs to this one task and must not reach the next request.
        let refusedRedirect = delegate.takeRefusal(of: bytes.task.taskIdentifier)
        guard let http = response as? HTTPURLResponse else { throw StatusFeedError.invalidResponse }
        if refusedRedirect { throw StatusFeedError.invalidResponse }
        switch http.statusCode {
        case 304:
            return .notModified
        case 200:
            break
        default:
            throw StatusFeedError.unacceptableStatus(http.statusCode)
        }
        let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? http.mimeType ?? "").lowercased()
        guard contentType.contains("json") else {
            // Bounded: the header comes from the network and only ever reaches the log.
            throw StatusFeedError.unacceptableContentType(String(contentType.prefix(64)))
        }
        // The declared length is only a hint, so the read is bounded as it goes as well.
        if http.expectedContentLength > Int64(Self.maximumBodyBytes) { throw StatusFeedError.tooLarge }

        var data = Data()
        data.reserveCapacity(min(Int(max(http.expectedContentLength, 0)), Self.maximumBodyBytes))
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count > Self.maximumBodyBytes { throw StatusFeedError.tooLarge }
            }
        } catch let error as StatusFeedError {
            throw error
        } catch {
            throw StatusFeedError.transport((error as NSError).code.description)
        }
        if let etag = http.value(forHTTPHeaderField: "Etag") {
            etags[url] = etag
        } else {
            etags[url] = nil
        }
        return .updated(data)
    }

    /// Forgets the remembered ETags (used when checks are switched off).
    public func reset() {
        etags.removeAll()
    }
}

/// Refuses every redirect that leaves the host the request was sent to, and remembers which task it did that to.
///
/// A refused redirect also makes the task finish on the 3xx response itself, which `fetch` rejects; the record makes
/// the reason unambiguous whatever the host answers with. It is kept per task because one client serves both vendors
/// for as long as the app runs: a captive portal bouncing one request elsewhere must not reject the next one.
private final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    private let refused = Mutex(Set<Int>())

    /// Whether `taskIdentifier` was stopped from leaving its host, and forgets it.
    func takeRefusal(of taskIdentifier: Int) -> Bool {
        refused.withLock { identifiers in
            let wasRefused = identifiers.remove(taskIdentifier) != nil
            // A session hands out identifiers in order, so anything older belongs to a task that failed before it
            // could collect its answer. Dropping those keeps the set at one entry at most.
            identifiers = identifiers.filter { $0 > taskIdentifier }
            return wasRefused
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let originalHost = task.originalRequest?.url?.host()?.lowercased()
        let newHost = request.url?.host()?.lowercased()
        let staysOnHost = originalHost != nil && originalHost == newHost && request.url?.scheme?.lowercased() == "https"
        if !staysOnHost {
            refused.withLock { _ = $0.insert(task.taskIdentifier) }
        }
        completionHandler(staysOnHost ? request : nil)
    }
}
