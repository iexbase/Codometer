import Foundation

/// The public status feeds Codometer may read, and the pages it may open. Every URL here is fixed in code:
/// nothing is ever built from fetched data, and the host allowlist is exactly these two hosts.
public enum VendorStatusFeed: Sendable {
    /// The host whose status page describes `provider`; shown in the chip's tooltip.
    public static func host(for provider: ProviderKind) -> String {
        switch provider {
        case .claude: "status.claude.com"
        case .codex: "status.openai.com"
        }
    }

    /// The JSON endpoint to fetch.
    ///
    /// Claude's summary carries the components Codometer watches and its incidents. OpenAI's summary omits "CLI"
    /// and has no incidents, so the components list is the only reliable source there.
    public static func url(for provider: ProviderKind) -> URL {
        switch provider {
        case .claude: claudeSummary
        case .codex: openAIComponents
        }
    }

    /// The page a click on the chip opens in the browser.
    public static func statusPage(for provider: ProviderKind) -> URL {
        switch provider {
        case .claude: claudePage
        case .codex: openAIPage
        }
    }

    /// The only hosts the client may talk to.
    public static let allowedHosts: Set<String> = Set(ProviderKind.allCases.map { host(for: $0) })

    // URL(string:) of a literal cannot fail; the fallbacks keep the initialisers non-optional without a force unwrap.
    private static let claudeSummary = URL(string: "https://status.claude.com/api/v2/summary.json") ?? claudePage
    private static let openAIComponents = URL(string: "https://status.openai.com/api/v2/components.json") ?? openAIPage
    private static let claudePage = URL(string: "https://status.claude.com") ?? URL(filePath: "/")
    private static let openAIPage = URL(string: "https://status.openai.com") ?? URL(filePath: "/")
}

/// Turns a Statuspage feed into a `ServiceStatus`, reading only the components Codometer's users depend on.
///
/// Pure and total: any shape of JSON produces a value or `nil`, never an error and never a crash. Only whitelisted
/// fields are read (`components[].id/name/status`, `incidents[].name/status/components[].id/name`); everything else in
/// the feed is ignored, and no text from it is stored beyond the sanitised component names in `ServiceStatus`.
public enum VendorStatusParsing: Sendable {
    /// Feeds larger than this are not parsed (the client already caps the body at 256 KiB).
    public static let maximumFeedBytes = 256 * 1_024

    /// The components whose trouble affects Codometer's users, per vendor.
    ///
    /// Claude: "Claude Code" exactly, plus the component whose name starts with "Claude API"
    /// (currently "Claude API (api.anthropic.com)"). Codex: the five exact names OpenAI uses.
    /// Names are compared without surrounding whitespace and without case, so a capitalisation change on the page
    /// does not silently drop a component.
    public static func isFocusComponent(name: String, provider: ProviderKind) -> Bool {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return false }
        switch provider {
        case .claude:
            return clean.compare("Claude Code", options: .caseInsensitive) == .orderedSame
                || clean.lowercased().hasPrefix("claude api")
        case .codex:
            return codexFocusNames.contains { clean.compare($0, options: .caseInsensitive) == .orderedSame }
        }
    }

    private static let codexFocusNames = ["CLI", "Codex API", "Codex Web", "VS Code extension", "Codex in ChatGPT Desktop"]

    /// The status of `provider` as its feed describes it, or `nil` when the feed mentions none of the components
    /// Codometer watches (a page redesign, a wrong endpoint, unreadable JSON): then nothing is shown at all,
    /// rather than a guess from the page headline.
    ///
    /// A `ServiceStatus` with `level == nil` means "the components we watch are fine".
    public static func status(provider: ProviderKind, data: Data, checkedAt: Date) -> ServiceStatus? {
        guard data.count <= maximumFeedBytes, let feed = try? JSONDecoder().decode(StatusFeed.self, from: data) else { return nil }
        return status(provider: provider, feed: feed, checkedAt: checkedAt)
    }

    private static func status(provider: ProviderKind, feed: StatusFeed, checkedAt: Date) -> ServiceStatus? {
        var seen: Set<String> = []
        var focus: [(id: String?, name: String, level: ServiceStatusLevel?)] = []
        for component in feed.components {
            guard let name = component.name, isFocusComponent(name: name, provider: provider) else { continue }
            // Duplicate ids are one component listed twice; components without an id dedupe by name.
            let key = component.id ?? "name:\(name.lowercased())"
            guard seen.insert(key).inserted else { continue }
            focus.append((component.id, name.trimmingCharacters(in: .whitespacesAndNewlines), level(of: component.status)))
        }
        guard !focus.isEmpty else { return nil }

        var level = focus.compactMap(\.level).max()
        var affected = focus.filter { $0.level != nil }
            .sorted { ($0.level ?? .maintenance) > ($1.level ?? .maintenance) }
            .map(\.name)

        // An unresolved incident touching one of those components means trouble even while the component itself
        // still reads "operational".
        let incidentNames = focus.filter { component in
            feed.incidents.contains { incident in
                incident.isUnresolved && incident.touches(id: component.id, name: component.name)
            }
        }.map(\.name)
        if !incidentNames.isEmpty {
            level = max(level ?? .degraded, .degraded)
            if affected.isEmpty {
                affected = incidentNames
            }
        }
        return ServiceStatus(provider: provider, level: level, affectedComponents: affected, checkedAt: checkedAt)
    }

    /// Statuspage component states. An unknown string means the component says nothing, not that it is broken.
    static func level(of status: String?) -> ServiceStatusLevel? {
        switch status {
        case "degraded_performance": .degraded
        case "partial_outage": .partialOutage
        case "major_outage": .majorOutage
        case "under_maintenance": .maintenance
        default: nil
        }
    }
}

// MARK: - Feed shape

/// The whitelisted part of a Statuspage feed. Every field is optional and decodes leniently: a field of the wrong
/// type drops that field, an unreadable element drops that element, and unknown keys are ignored.
private struct StatusFeed: Decodable {
    let components: [Component]
    let incidents: [Incident]

    private enum CodingKeys: String, CodingKey {
        case components, incidents
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        components = LenientFeed.array(container, .components)
        incidents = LenientFeed.array(container, .incidents)
    }

    struct Component: Decodable {
        let id: String?
        let name: String?
        let status: String?

        private enum CodingKeys: String, CodingKey {
            case id, name, status
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = LenientFeed.string(container, .id)
            name = LenientFeed.string(container, .name)
            status = LenientFeed.string(container, .status)
        }
    }

    struct Incident: Decodable {
        let status: String?
        let components: [Component]

        private enum CodingKeys: String, CodingKey {
            case status, components
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            status = LenientFeed.string(container, .status)
            components = LenientFeed.array(container, .components)
        }

        /// Statuspage closes an incident with "resolved" or "postmortem"; a maintenance window closes with
        /// "completed". Anything else (investigating, identified, monitoring, in_progress, unknown) is still open.
        var isUnresolved: Bool {
            switch status {
            case "resolved", "postmortem", "completed": false
            default: true
            }
        }

        /// Ids are the reliable link; a component without one is matched by name.
        func touches(id: String?, name: String) -> Bool {
            components.contains { component in
                if let id, let componentID = component.id { return componentID == id }
                return component.name?.caseInsensitiveCompare(name) == .orderedSame
            }
        }
    }
}

/// Field readers that never throw: a missing field, a null, or a value of the wrong type all read as "absent".
private enum LenientFeed {
    static func string<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, _ key: Key) -> String? {
        ((try? container.decodeIfPresent(String.self, forKey: key)) ?? nil)
            .flatMap { DisplayText.sanitize($0, maximumLength: 200) }
    }

    /// Elements that cannot be read are dropped, not the whole array.
    static func array<Key: CodingKey, Element: Decodable>(_ container: KeyedDecodingContainer<Key>, _ key: Key) -> [Element] {
        guard var list = try? container.nestedUnkeyedContainer(forKey: key) else { return [] }
        var elements: [Element] = []
        while !list.isAtEnd {
            let index = list.currentIndex
            if let element = try? list.decode(Element.self) {
                elements.append(element)
            } else {
                _ = try? list.decode(SkippedElement.self)
            }
            // A decoder that reports no progress would spin forever; stop instead.
            guard list.currentIndex > index else { break }
        }
        return elements
    }

    /// Consumes one element of any shape without reading it.
    private struct SkippedElement: Decodable {
        init(from decoder: any Decoder) throws {}
    }
}
