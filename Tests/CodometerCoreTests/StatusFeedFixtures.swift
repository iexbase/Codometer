import Foundation

/// Status feed bodies in the shapes the two public pages served on 2026-09-17, trimmed to
/// the fields Codometer reads. Swift literals, never resource files: test targets carry no resources.
///
/// Nothing here is user data; component names and incident texts are the vendors' own public wording or invented.
enum StatusFeedFixture {
    /// `status.claude.com/api/v2/summary.json` with everything operational: six components, no incidents.
    static let claudeOperational = """
    {
      "page": {"id": "9pw6q0m4kzlq", "name": "Anthropic", "url": "https://status.claude.com"},
      "components": [
        {"id": "c1", "name": "claude.ai", "status": "operational", "group": false, "showcase": true},
        {"id": "c2", "name": "Claude Console (platform.claude.com)", "status": "operational"},
        {"id": "c3", "name": "Claude API (api.anthropic.com)", "status": "operational"},
        {"id": "c4", "name": "Claude Code", "status": "operational"},
        {"id": "c5", "name": "Claude Cowork", "status": "operational"},
        {"id": "c6", "name": "Claude for Government", "status": "operational"}
      ],
      "incidents": [],
      "scheduled_maintenances": [],
      "status": {"indicator": "none", "description": "All Systems Operational"}
    }
    """

    /// Claude Code in a partial outage while the API only slows down: the worst focus component wins.
    static let claudePartialOutage = """
    {
      "components": [
        {"id": "c1", "name": "claude.ai", "status": "major_outage"},
        {"id": "c3", "name": "Claude API (api.anthropic.com)", "status": "degraded_performance"},
        {"id": "c4", "name": "Claude Code", "status": "partial_outage"}
      ],
      "incidents": []
    }
    """

    /// Every focus component reads operational, but an incident is open on Claude Code.
    static let claudeIncidentOnly = """
    {
      "components": [
        {"id": "c3", "name": "Claude API (api.anthropic.com)", "status": "operational"},
        {"id": "c4", "name": "Claude Code", "status": "operational"}
      ],
      "incidents": [
        {
          "id": "i1", "name": "Elevated errors on Claude Code", "status": "investigating",
          "components": [{"id": "c4", "name": "Claude Code"}]
        },
        {
          "id": "i2", "name": "Resolved console issue", "status": "resolved",
          "components": [{"id": "c3", "name": "Claude API (api.anthropic.com)"}]
        }
      ]
    }
    """

    /// A finished incident never raises the level.
    static let claudeResolvedIncident = """
    {
      "components": [{"id": "c4", "name": "Claude Code", "status": "operational"}],
      "incidents": [
        {"id": "i1", "name": "Yesterday", "status": "postmortem", "components": [{"id": "c4", "name": "Claude Code"}]},
        {"id": "i2", "name": "Maintenance", "status": "completed", "components": [{"id": "c4", "name": "Claude Code"}]}
      ]
    }
    """

    /// The page redesigned: no component Codometer watches. Nothing may be shown.
    static let claudeWithoutFocus = """
    {
      "components": [
        {"id": "c1", "name": "claude.ai", "status": "major_outage"},
        {"id": "c9", "name": "Claude for Government", "status": "major_outage"}
      ],
      "incidents": [{"id": "i1", "name": "Outage", "status": "identified", "components": [{"id": "c1", "name": "claude.ai"}]}]
    }
    """

    /// `status.openai.com/api/v2/components.json`: 34 components in the real feed, with "Login" listed twice under
    /// different ids, one focus component duplicated, and one unknown status string.
    static let openAIComponents = """
    {
      "page": {"id": "openai", "name": "OpenAI"},
      "components": [
        {"id": "o1", "name": "Login", "status": "operational"},
        {"id": "o2", "name": "Login", "status": "major_outage"},
        {"id": "o3", "name": "API", "status": "operational"},
        {"id": "o4", "name": "CLI", "status": "degraded_performance"},
        {"id": "o4", "name": "CLI", "status": "major_outage"},
        {"id": "o5", "name": "Codex API", "status": "operational"},
        {"id": "o6", "name": "Codex Web", "status": "sunny"},
        {"id": "o7", "name": "VS Code extension", "status": "operational"},
        {"id": "o8", "name": "Codex in ChatGPT Desktop", "status": "operational"},
        {"id": "o9", "name": "Playground", "status": "partial_outage"}
      ]
    }
    """

    /// OpenAI under maintenance on one focus component, with the rest fine.
    static let openAIMaintenance = """
    {
      "components": [
        {"id": "o4", "name": "CLI", "status": "operational"},
        {"id": "o5", "name": "Codex API", "status": "under_maintenance"},
        {"id": "o7", "name": "VS Code extension", "status": "operational"}
      ]
    }
    """

    /// Values of the wrong type everywhere, and an element that is not an object: the readable parts still parse.
    static let openAIMalformedValues = """
    {
      "components": [
        17,
        {"id": 5, "name": "CLI", "status": "partial_outage"},
        {"id": "o5", "name": ["Codex API"], "status": "operational"},
        {"id": "o7", "name": "VS Code extension", "status": {"kind": "operational"}},
        null
      ],
      "incidents": "none"
    }
    """

    /// Not JSON at all.
    static let notJSON = "<html><body>503 Service Unavailable</body></html>"

    /// A JSON array where an object is expected.
    static let jsonArray = "[{\"name\": \"Claude Code\", \"status\": \"major_outage\"}]"

    static func data(_ text: String) -> Data {
        Data(text.utf8)
    }
}
