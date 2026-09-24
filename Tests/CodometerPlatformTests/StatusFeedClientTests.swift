import CodometerCore
@testable import CodometerPlatform
import Foundation
import Synchronization
import Testing

/// Everything the status feed client refuses, and the little it accepts. No test here touches the network:
/// `StatusFeedStub` answers every request inside the process.
@Suite("Status feed client", .serialized)
struct StatusFeedClientTests {
    private let claudeFeed = VendorStatusFeed.url(for: .claude)

    private func makeClient() -> StatusFeedClient {
        StatusFeedStub.reset()
        return StatusFeedClient(protocolClasses: [StatusFeedStub.self])
    }

    @Test("A JSON 200 comes back whole, with a plain request and no cookies")
    func acceptsJSON() async throws {
        let client = makeClient()
        StatusFeedStub.reply(for: claudeFeed, .init(status: 200, headers: ["Content-Type": "application/json; charset=utf-8"], body: Data("{}".utf8)))
        let result = try await client.fetch(claudeFeed)
        #expect(result == .updated(Data("{}".utf8)))

        let request = try #require(StatusFeedStub.requests.first)
        #expect(StatusFeedStub.requests.count == 1)
        #expect(request.url == claudeFeed)
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Codometer")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == nil)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(!request.httpShouldHandleCookies)
        #expect(request.httpBody == nil)
    }

    @Test("Only HTTPS on the two allowed hosts is even attempted")
    func refusesOtherHosts() async throws {
        let client = makeClient()
        let refused = [
            "http://status.claude.com/api/v2/summary.json",
            "https://status.claude.com.example.com/api/v2/summary.json",
            "https://example.com/api/v2/summary.json",
            "https://STATUS.CLAUDE.COM.evil.test/summary.json",
            "file:///etc/hosts",
        ]
        for text in refused {
            let url = try #require(URL(string: text))
            await #expect(throws: StatusFeedError.hostNotAllowed, "\(text)") {
                try await client.fetch(url)
            }
        }
        #expect(StatusFeedStub.requests.isEmpty)
    }

    @Test("An ETag is remembered in memory and answered with 304")
    func etagRoundTrip() async throws {
        let client = makeClient()
        StatusFeedStub.reply(for: claudeFeed, .init(status: 200, headers: ["Content-Type": "application/json", "Etag": "W/\"abc\""], body: Data("{}".utf8)))
        _ = try await client.fetch(claudeFeed)
        StatusFeedStub.reply(for: claudeFeed, .init(status: 304, headers: ["Content-Type": "application/json"], body: Data()))
        #expect(try await client.fetch(claudeFeed) == .notModified)
        #expect(StatusFeedStub.requests.last?.value(forHTTPHeaderField: "If-None-Match") == "W/\"abc\"")

        // Forgetting the ETags stops sending it.
        await client.reset()
        StatusFeedStub.reply(for: claudeFeed, .init(status: 200, headers: ["Content-Type": "application/json"], body: Data("{}".utf8)))
        _ = try await client.fetch(claudeFeed)
        #expect(StatusFeedStub.requests.last?.value(forHTTPHeaderField: "If-None-Match") == nil)
    }

    @Test("Anything but 200 or 304 is refused", arguments: [201, 301, 400, 403, 429, 500, 503])
    func refusesOtherStatusCodes(code: Int) async throws {
        let client = makeClient()
        StatusFeedStub.reply(for: claudeFeed, .init(status: code, headers: ["Content-Type": "application/json"], body: Data("{}".utf8)))
        await #expect(throws: StatusFeedError.unacceptableStatus(code)) {
            try await client.fetch(claudeFeed)
        }
    }

    @Test("A body that is not JSON is refused before it is read")
    func refusesNonJSON() async throws {
        let client = makeClient()
        StatusFeedStub.reply(for: claudeFeed, .init(status: 200, headers: ["Content-Type": "text/html; charset=utf-8"], body: Data("<html>".utf8)))
        await #expect(throws: StatusFeedError.unacceptableContentType("text/html; charset=utf-8")) {
            try await client.fetch(claudeFeed)
        }
    }

    @Test("A body past 256 KiB is abandoned, whether or not the host declares its length")
    func refusesOversizeBody() async throws {
        let client = makeClient()
        let huge = Data(repeating: 0x20, count: StatusFeedClient.maximumBodyBytes + 1_024)
        StatusFeedStub.reply(for: claudeFeed, .init(status: 200, headers: ["Content-Type": "application/json", "Content-Length": "\(huge.count)"], body: huge))
        await #expect(throws: StatusFeedError.tooLarge) {
            try await client.fetch(claudeFeed)
        }
        StatusFeedStub.reply(for: claudeFeed, .init(status: 200, headers: ["Content-Type": "application/json"], body: huge, declaresLength: false))
        await #expect(throws: StatusFeedError.tooLarge) {
            try await client.fetch(claudeFeed)
        }
    }

    @Test("A body of exactly the cap still comes through")
    func acceptsBodyAtTheCap() async throws {
        let client = makeClient()
        let body = Data(repeating: 0x20, count: StatusFeedClient.maximumBodyBytes)
        StatusFeedStub.reply(for: claudeFeed, .init(status: 200, headers: ["Content-Type": "application/json"], body: body))
        #expect(try await client.fetch(claudeFeed) == .updated(body))
    }

    @Test("A redirect to another host is refused")
    func refusesRedirectOffHost() async throws {
        let client = makeClient()
        let elsewhere = try #require(URL(string: "https://example.com/summary.json"))
        StatusFeedStub.reply(for: claudeFeed, .init(status: 302, headers: ["Location": elsewhere.absoluteString], body: Data(), redirectsTo: elsewhere))
        // The guard declines the redirect, so the reply is treated as no usable response at all.
        await #expect(throws: StatusFeedError.invalidResponse) {
            try await client.fetch(claudeFeed)
        }
        // Nothing was requested from the other host.
        #expect(StatusFeedStub.requests.allSatisfy { $0.url?.host() == "status.claude.com" })
    }

    @Test("A refused redirect ends that one request and nothing else")
    func refusedRedirectDoesNotOutliveItsRequest() async throws {
        let client = makeClient()
        let codexFeed = VendorStatusFeed.url(for: .codex)
        let elsewhere = try #require(URL(string: "https://example.com/summary.json"))
        let body = Data("{}".utf8)
        StatusFeedStub.reply(for: claudeFeed, .init(status: 302, headers: ["Location": elsewhere.absoluteString], body: Data(), redirectsTo: elsewhere))
        await #expect(throws: StatusFeedError.invalidResponse) {
            try await client.fetch(claudeFeed)
        }

        // One client serves both vendors for the whole session, so the other vendor's check still works …
        StatusFeedStub.reply(for: codexFeed, .init(status: 200, headers: ["Content-Type": "application/json"], body: body))
        #expect(try await client.fetch(codexFeed) == .updated(body))
        // … and so does the next check of the host that redirected, once it stops.
        StatusFeedStub.reply(for: claudeFeed, .init(status: 200, headers: ["Content-Type": "application/json"], body: body))
        #expect(try await client.fetch(claudeFeed) == .updated(body))
    }

    @Test("A transport failure is reported without leaking the address")
    func reportsTransportFailure() async throws {
        let client = makeClient()
        StatusFeedStub.fail(for: claudeFeed, with: URLError(.timedOut))
        let error = await #expect(throws: StatusFeedError.self) {
            try await client.fetch(claudeFeed)
        }
        let description = try #require(error).description
        #expect(description.hasPrefix("transport: "))
        #expect(!description.contains("status.claude.com"))
    }

    @Test("The client's limits are the ones the spec fixes")
    func limits() {
        #expect(StatusFeedClient.maximumBodyBytes == 256 * 1_024)
        #expect(StatusFeedClient.requestTimeout == 10)
        #expect(StatusFeedClient.resourceTimeout == 15)
        #expect(StatusFeedClient.userAgent == "Codometer")
    }
}

/// Answers the client's requests inside the process and records what it was asked for.
final class StatusFeedStub: URLProtocol, @unchecked Sendable {
    struct Reply {
        var status = 200
        var headers: [String: String] = [:]
        var body = Data()
        var declaresLength = true
        var redirectsTo: URL?
        var error: (any Error)?
    }

    private struct State {
        var replies: [URL: Reply] = [:]
        var requests: [URLRequest] = []
    }

    private static let state = Mutex(State())

    static func reset() {
        state.withLock { $0 = State() }
    }

    static func reply(for url: URL, _ reply: Reply) {
        state.withLock { $0.replies[url] = reply }
    }

    static func fail(for url: URL, with error: any Error) {
        state.withLock { $0.replies[url] = Reply(error: error) }
    }

    static var requests: [URLRequest] {
        state.withLock { $0.requests }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let request = request
        Self.state.withLock { $0.requests.append(request) }
        guard let url = request.url, let reply = Self.state.withLock({ $0.replies[url] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        if let error = reply.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        var headers = reply.headers
        if reply.declaresLength, headers["Content-Length"] == nil, !reply.body.isEmpty {
            headers["Content-Length"] = "\(reply.body.count)"
        }
        guard let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: headers) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        if let target = reply.redirectsTo {
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !reply.body.isEmpty {
            client?.urlProtocol(self, didLoad: reply.body)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
