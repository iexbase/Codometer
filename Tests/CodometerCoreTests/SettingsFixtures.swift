import Foundation

/// `settings.json` files as Swift literals (test targets carry no resource files). Synthetic values only.
enum SettingsFixtures {
    static let workAccountID = "8C8E4A0E-3B1A-4C7B-9D5E-000000000001"
    static let codexAccountID = "8C8E4A0E-3B1A-4C7B-9D5E-000000000002"
    static let brokenAccountID = "8C8E4A0E-3B1A-4C7B-9D5E-000000000003"
    static let workGroupID = "8C8E4A0E-3B1A-4C7B-9D5E-0000000000AA"
    static let personalGroupID = "8C8E4A0E-3B1A-4C7B-9D5E-0000000000BB"
    static let displayID = "37D8832A-2D66-02CA-B9F7-8F30A301B230"

    /// Today's shape (written before the newer keys existed): every key the previous encoder wrote, pretty-printed
    /// with sorted keys.
    static let r2 = """
    {
      "accounts" : [
        {
          "directory" : "/Users/tester/.claude-work",
          "groupID" : "\(workGroupID)",
          "id" : "\(workAccountID)",
          "isEnabled" : true,
          "label" : "Claude · work",
          "pollInterval" : 300,
          "provider" : "claude"
        },
        {
          "directory" : "/Users/tester/.codex",
          "id" : "\(codexAccountID)",
          "isEnabled" : false,
          "label" : "Codex",
          "pollInterval" : 180,
          "provider" : "codex"
        }
      ],
      "alerts" : {
        "coalescesBursts" : false,
        "minimumTurnForFinishedAlert" : 45,
        "notifiesOnReset" : false,
        "notifiesOnSessionFinished" : true,
        "notifiesOnSessionWaiting" : false,
        "peekDuration" : 8,
        "playsSounds" : false,
        "thresholds" : [
          50,
          90
        ],
        "withdrawsResolvedAlerts" : true
      },
      "appearance" : {
        "bands" : {
          "critical" : 85,
          "watch" : 60
        },
        "edge" : "right",
        "emailVisibility" : "masked",
        "glowsWithUrgency" : false,
        "hidesInFullScreen" : false,
        "offset" : 0.25,
        "openTrigger" : "hoverOrClick",
        "railGroupFilter" : "\(workGroupID)",
        "resetTextStyle" : "clockTime",
        "scale" : 1.25,
        "showsPace" : false,
        "showsSecondaryRing" : false,
        "style" : "floating",
        "surface" : "darkGlass",
        "visibility" : "always"
      },
      "general" : {
        "exportsWidgetData" : false,
        "globalShortcut" : "controlOptionSpace",
        "language" : "ru",
        "launchesAtLogin" : true
      },
      "groups" : [
        {
          "id" : "\(workGroupID)",
          "mutesSessionAlerts" : true,
          "mutesUsageAlerts" : false,
          "name" : "Work"
        },
        {
          "id" : "\(personalGroupID)",
          "mutesSessionAlerts" : false,
          "mutesUsageAlerts" : true,
          "name" : "Personal"
        }
      ],
      "schemaVersion" : 1
    }
    """

    /// Written by a hypothetical newer build: schema 2, unknown enum values, unknown keys everywhere.
    static let future = """
    {
      "schemaVersion": 2,
      "futureTopLevel": {"anything": [1, 2, 3]},
      "accounts": [
        {"id": "\(workAccountID)", "provider": "claude", "label": "Claude · work", "directory": "/Users/tester/.claude-work",
         "isEnabled": true, "pollInterval": 300, "tint": "ultraviolet", "monogram": "W", "futureAccountKey": 7},
        {"id": "\(brokenAccountID)", "provider": "gemini", "label": "Gemini", "directory": "/Users/tester/.gemini"}
      ],
      "groups": [],
      "appearance": {
        "edge": "top", "presentationStyle": "hologram", "notchFusion": "always", "surface": "plasma",
        "islandDisplayPolicy": {"kind": "followMouse"},
        "floatingCard": {"theme": "neon", "size": "tall", "layout": "allAccounts", "thirdTile": "agents",
                         "accountSelection": {"kind": "roundRobin"}, "minimizedForm": "orb", "isMinimized": true},
        "futureAppearanceKey": true
      },
      "alerts": {"playsSounds": false, "futureAlertKey": "x"},
      "general": {"language": "de", "energyMode": "turbo", "historyRetention": 35, "onboarding": {"completedVersion": 3},
                  "showsVendorStatus": true, "lastLaunchedVersion": "2.0.0", "percentBasis": "left"}
    }
    """

    /// One bad account, an out-of-range scale and a duplicate group.
    static let damaged = """
    {
      "schemaVersion": 1,
      "accounts": [
        {"id": "\(workAccountID)", "provider": "claude", "label": "Claude · work", "directory": "/Users/tester/.claude-work",
         "groupID": "\(workGroupID)"},
        {"id": "\(brokenAccountID)", "provider": "claude", "label": "Broken", "directory": "relative/path"},
        {"id": "\(codexAccountID)", "provider": "codex", "label": "Codex", "directory": "/Users/tester/.codex", "groupID": "\(personalGroupID)"}
      ],
      "groups": [
        {"id": "\(workGroupID)", "name": "Work"},
        {"id": "\(workGroupID)", "name": "Work again"},
        {"id": "\(personalGroupID)", "name": "Personal"}
      ],
      "appearance": {"edge": "bottom", "scale": 7.5},
      "alerts": {},
      "general": {"globalShortcut": "controlOptionCommandL"}
    }
    """

    static func data(_ json: String) -> Data { Data(json.utf8) }
}
