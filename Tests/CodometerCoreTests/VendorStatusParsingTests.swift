@testable import CodometerCore
import Foundation
import Testing

@Suite("Vendor status parsing")
struct VendorStatusParsingTests {
    private let now = Date(timeIntervalSince1970: 1_789_600_000)

    private func parse(_ provider: ProviderKind, _ fixture: String) -> ServiceStatus? {
        VendorStatusParsing.status(provider: provider, data: StatusFeedFixture.data(fixture), checkedAt: now)
    }

    @Test("Claude: the watched components are fine")
    func claudeOperational() throws {
        let status = try #require(parse(.claude, StatusFeedFixture.claudeOperational))
        #expect(status.provider == .claude)
        #expect(status.level == nil)
        #expect(status.affectedComponents.isEmpty)
        #expect(status.checkedAt == now)
    }

    @Test("Claude: the worst watched component decides, and components outside the focus never do")
    func claudePartialOutage() throws {
        let status = try #require(parse(.claude, StatusFeedFixture.claudePartialOutage))
        // claude.ai is in a major outage and is deliberately ignored.
        #expect(status.level == .partialOutage)
        #expect(status.affectedComponents == ["Claude Code", "Claude API (api.anthropic.com)"])
    }

    @Test("Claude: an open incident on a watched component means at least degraded")
    func claudeIncident() throws {
        let status = try #require(parse(.claude, StatusFeedFixture.claudeIncidentOnly))
        #expect(status.level == .degraded)
        #expect(status.affectedComponents == ["Claude Code"])
    }

    @Test("Claude: a resolved or completed incident changes nothing")
    func claudeResolvedIncident() throws {
        let status = try #require(parse(.claude, StatusFeedFixture.claudeResolvedIncident))
        #expect(status.level == nil)
        #expect(status.affectedComponents.isEmpty)
    }

    @Test("No watched component in the feed means no status at all, whatever else is broken")
    func noFocus() {
        #expect(parse(.claude, StatusFeedFixture.claudeWithoutFocus) == nil)
        // The Claude feed read as Codex: none of its components are Codex's.
        #expect(parse(.codex, StatusFeedFixture.claudeOperational) == nil)
    }

    @Test("Codex: duplicate ids collapse, duplicate names elsewhere are ignored, unknown states count as silence")
    func openAIComponents() throws {
        let status = try #require(parse(.codex, StatusFeedFixture.openAIComponents))
        // "CLI" is listed twice under id o4: the first one wins, so degraded, not the major outage of the copy.
        // "Login" twice and "Playground" in a partial outage are outside the focus.
        // "Codex Web" reads "sunny", which is ignored rather than guessed at.
        #expect(status.level == .degraded)
        #expect(status.affectedComponents == ["CLI"])
    }

    @Test("Codex: maintenance on a watched component")
    func openAIMaintenance() throws {
        let status = try #require(parse(.codex, StatusFeedFixture.openAIMaintenance))
        #expect(status.level == .maintenance)
        #expect(status.affectedComponents == ["Codex API"])
    }

    @Test("Values of the wrong type drop their field or their element, never the whole feed")
    func malformedValues() throws {
        let status = try #require(parse(.codex, StatusFeedFixture.openAIMalformedValues))
        // The CLI element keeps its name and status although its id is a number; the others lose a field each.
        #expect(status.level == .partialOutage)
        #expect(status.affectedComponents == ["CLI"])
    }

    @Test("Unreadable bodies produce nothing")
    func unreadable() {
        #expect(parse(.claude, StatusFeedFixture.notJSON) == nil)
        #expect(parse(.claude, StatusFeedFixture.jsonArray) == nil)
        #expect(VendorStatusParsing.status(provider: .claude, data: Data(), checkedAt: now) == nil)
        #expect(VendorStatusParsing.status(provider: .claude, data: Data(repeating: 0x20, count: 8), checkedAt: now) == nil)
    }

    @Test("A body past the cap is not even parsed")
    func oversizeBody() {
        var padded = StatusFeedFixture.claudePartialOutage
        padded += String(repeating: " ", count: VendorStatusParsing.maximumFeedBytes)
        #expect(VendorStatusParsing.status(provider: .claude, data: StatusFeedFixture.data(padded), checkedAt: now) == nil)
    }

    @Test("The watched components are exactly the ones the vendors name")
    func focusComponents() {
        for name in ["Claude Code", "claude code", " Claude Code ", "Claude API (api.anthropic.com)", "Claude API"] {
            #expect(VendorStatusParsing.isFocusComponent(name: name, provider: .claude), "\(name)")
        }
        for name in ["claude.ai", "Claude Console (platform.claude.com)", "Claude Cowork", "Claude for Government", "", "CLI"] {
            #expect(!VendorStatusParsing.isFocusComponent(name: name, provider: .claude), "\(name)")
        }
        for name in ["CLI", "Codex API", "Codex Web", "VS Code extension", "Codex in ChatGPT Desktop"] {
            #expect(VendorStatusParsing.isFocusComponent(name: name, provider: .codex), "\(name)")
        }
        for name in ["Login", "API", "Playground", "Codex", "Claude Code", "CLI tools"] {
            #expect(!VendorStatusParsing.isFocusComponent(name: name, provider: .codex), "\(name)")
        }
    }

    @Test("Statuspage states map to levels, and anything unknown maps to none")
    func levelMapping() {
        #expect(VendorStatusParsing.level(of: "degraded_performance") == .degraded)
        #expect(VendorStatusParsing.level(of: "partial_outage") == .partialOutage)
        #expect(VendorStatusParsing.level(of: "major_outage") == .majorOutage)
        #expect(VendorStatusParsing.level(of: "under_maintenance") == .maintenance)
        #expect(VendorStatusParsing.level(of: "operational") == nil)
        #expect(VendorStatusParsing.level(of: "MAJOR_OUTAGE") == nil)
        #expect(VendorStatusParsing.level(of: nil) == nil)
    }

    @Test("Feed and page URLs are fixed, HTTPS and on the two allowed hosts")
    func feedURLs() {
        #expect(VendorStatusFeed.url(for: .claude).absoluteString == "https://status.claude.com/api/v2/summary.json")
        #expect(VendorStatusFeed.url(for: .codex).absoluteString == "https://status.openai.com/api/v2/components.json")
        #expect(VendorStatusFeed.allowedHosts == ["status.claude.com", "status.openai.com"])
        for provider in ProviderKind.allCases {
            #expect(VendorStatusFeed.url(for: provider).scheme == "https")
            #expect(VendorStatusFeed.url(for: provider).host() == VendorStatusFeed.host(for: provider))
            // The page the chip opens is the same page the reading came from.
            let status = ServiceStatus(provider: provider, level: nil, affectedComponents: [], checkedAt: now)
            #expect(VendorStatusFeed.statusPage(for: provider) == status.statusPageURL)
            #expect(VendorStatusFeed.statusPage(for: provider).host() == VendorStatusFeed.host(for: provider))
        }
    }
}
