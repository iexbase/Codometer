import CodometerCore
import Foundation
import Testing

@Suite("Account groups")
struct AccountGroupTests {
    @Test("Groups round-trip through JSON; missing mute flags default to false")
    func codable() throws {
        let group = try Fixture.group("Работа", mutesSessions: true)
        let decoded = try JSONDecoder().decode(AccountGroup.self, from: try JSONEncoder().encode(group))
        #expect(decoded == group)

        let minimal = try JSONDecoder().decode(
            AccountGroup.self,
            from: Data(#"{"id":"8C8E4A0E-3B1A-4C7B-9D5E-0000000000AA","name":" Личное "}"#.utf8)
        )
        #expect(minimal.name.value == "Личное")
        #expect(!minimal.mutesSessionAlerts)
        #expect(!minimal.mutesUsageAlerts)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(AccountGroup.self, from: Data(#"{"id":"8C8E4A0E-3B1A-4C7B-9D5E-0000000000AA","name":"  "}"#.utf8))
        }
    }

    @Test("Profiles join and leave groups through updated(groupID:)")
    func profileGroup() throws {
        let group = AccountGroupID()
        let profile = try Fixture.profile()
        #expect(profile.groupID == nil)
        let grouped = try profile.updated(groupID: group)
        #expect(grouped.groupID == group)
        #expect(try grouped.updated(label: try AccountLabel(validating: "Renamed")).groupID == group)
        #expect(try grouped.updated(groupID: .some(nil)).groupID == nil)

        let decoded = try JSONDecoder().decode(AccountProfile.self, from: try JSONEncoder().encode(grouped))
        #expect(decoded == grouped)
        let ungroupedJSON = try #require(try JSONSerialization.jsonObject(with: try JSONEncoder().encode(profile)) as? [String: Any])
        #expect(ungroupedJSON["groupID"] == nil)
    }

    @Test("At most eight groups with unique ids and case-insensitively unique names")
    func validation() throws {
        let work = try Fixture.group("Работа")
        #expect(try AppSettings(accounts: [], groups: [work, try Fixture.group("Личное")]).groups.count == 2)
        #expect(throws: ValidationError.duplicate(field: "groups.name", value: "работа")) {
            try AppSettings(accounts: [], groups: [work, try Fixture.group("работа")])
        }
        #expect(throws: ValidationError.duplicate(field: "groups.name", value: "WORK")) {
            try AppSettings(accounts: [], groups: [try Fixture.group("work"), try Fixture.group("WORK")])
        }
        #expect(throws: ValidationError.duplicate(field: "groups.id", value: work.id.description)) {
            try AppSettings(accounts: [], groups: [work, AccountGroup(id: work.id, name: try AccountLabel(validating: "Other"))])
        }
        let nine = try (1...9).map { try Fixture.group("Group \($0)") }
        #expect(throws: ValidationError.tooLong(field: "groups", length: 9, maximum: 8)) {
            try AppSettings(accounts: [], groups: nine)
        }
        #expect(try AppSettings.empty.replacingGroups(Array(nine.prefix(8))).groups.count == 8)
        #expect(throws: ValidationError.self) { try AppSettings.empty.replacingGroups(nine) }
    }

    @Test("Accounts may only refer to existing groups")
    func accountReferences() throws {
        let work = try Fixture.group("Работа")
        let member = try Fixture.profile(groupID: work.id)
        let settings = try AppSettings(accounts: [member], groups: [work])
        #expect(settings.group(work.id) == work)
        #expect(settings.group(AccountGroupID()) == nil)

        let stranger = try Fixture.profile(.claude, path: "/tmp/.claude", groupID: AccountGroupID())
        #expect(throws: ValidationError.self) { try settings.replacingAccounts([member, stranger]) }
        #expect(throws: ValidationError.self) { try AppSettings(accounts: [member]) }
    }

    @Test("Removing a group ungroups its accounts and clears a rail filter on it")
    func replacingGroups() throws {
        let work = try Fixture.group("Работа")
        let personal = try Fixture.group("Личное")
        var settings = try AppSettings(
            accounts: [
                try Fixture.profile(.claude, path: "/tmp/.claude", groupID: work.id),
                try Fixture.profile(.codex, path: "/tmp/.codex", groupID: personal.id),
            ],
            groups: [work, personal]
        )
        settings.appearance.railGroupFilter = work.id

        var renamed = personal
        renamed.name = try AccountLabel(validating: "Дом")
        renamed.mutesUsageAlerts = true
        let updated = try settings.replacingGroups([renamed])
        #expect(updated.groups == [renamed])
        #expect(updated.accounts[0].groupID == nil)
        #expect(updated.accounts[1].groupID == personal.id)
        #expect(updated.appearance.railGroupFilter == nil)

        settings.appearance.railGroupFilter = personal.id
        #expect(try settings.replacingGroups([renamed]).appearance.railGroupFilter == personal.id)
    }

    @Test("Decoding tolerates accounts and filters that refer to unknown groups")
    func tolerantDecoding() throws {
        let json = #"""
        {
          "schemaVersion": 1,
          "groups": [{"id": "8C8E4A0E-3B1A-4C7B-9D5E-0000000000AA", "name": "Работа", "mutesUsageAlerts": true}],
          "accounts": [
            {"id": "8C8E4A0E-3B1A-4C7B-9D5E-000000000001", "provider": "claude", "label": "A", "directory": "/tmp/.claude",
             "groupID": "8C8E4A0E-3B1A-4C7B-9D5E-0000000000AA"},
            {"id": "8C8E4A0E-3B1A-4C7B-9D5E-000000000002", "provider": "codex", "label": "B", "directory": "/tmp/.codex",
             "groupID": "8C8E4A0E-3B1A-4C7B-9D5E-0000000000BB"}
          ],
          "appearance": {"railGroupFilter": "8C8E4A0E-3B1A-4C7B-9D5E-0000000000CC"}
        }
        """#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.groups.count == 1)
        #expect(settings.groups[0].mutesUsageAlerts)
        #expect(settings.accounts[0].groupID == settings.groups[0].id)
        #expect(settings.accounts[1].groupID == nil)
        #expect(settings.appearance.railGroupFilter == nil)

        // A duplicate group name no longer fails the file; the first group is kept and the repair is noted.
        let duplicateNames = #"{"schemaVersion":1,"groups":[{"id":"8C8E4A0E-3B1A-4C7B-9D5E-0000000000AA","name":"A"},{"id":"8C8E4A0E-3B1A-4C7B-9D5E-0000000000BB","name":"a"}]}"#
        let repaired = try AppSettings.decodeFile(Data(duplicateNames.utf8))
        #expect(repaired.settings.groups.map(\.name.value) == ["A"])
        #expect(repaired.repairs == ["groups.name"])
    }
}

@Suite("Release 2 settings")
struct ReleaseTwoSettingsTests {
    /// The shape of `settings.json` written by release 1 (values anonymised).
    private static let releaseOneFile = #"""
    {
      "accounts" : [
        {
          "directory" : "/Users/me/.claude",
          "id" : "8C8E4A0E-3B1A-4C7B-9D5E-000000000001",
          "isEnabled" : true,
          "label" : "Личный",
          "pollInterval" : 300,
          "provider" : "claude"
        },
        {
          "directory" : "/Users/me/.claude-work",
          "id" : "8C8E4A0E-3B1A-4C7B-9D5E-000000000002",
          "isEnabled" : true,
          "label" : "Работа",
          "pollInterval" : 300,
          "provider" : "claude"
        }
      ],
      "alerts" : {
        "notifiesOnReset" : true,
        "notifiesOnSessionFinished" : true,
        "notifiesOnSessionWaiting" : true,
        "peekDuration" : 5,
        "playsSounds" : true,
        "thresholds" : [
          80,
          100
        ]
      },
      "appearance" : {
        "bands" : {
          "critical" : 80,
          "watch" : 50
        },
        "edge" : "right",
        "hidesInFullScreen" : true,
        "offset" : 0.11625928217821782,
        "resetTextStyle" : "countdown",
        "scale" : 0.85,
        "showsPace" : true,
        "showsSecondaryRing" : true,
        "style" : "attached",
        "surface" : "glass",
        "visibility" : "always"
      },
      "general" : {
        "launchesAtLogin" : false
      },
      "schemaVersion" : 1
    }
    """#

    @Test("The release 1 settings file still loads, with defaults for every new key")
    func releaseOneFileLoads() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(Self.releaseOneFile.utf8))
        #expect(settings.accounts.count == 2)
        #expect(settings.accounts.allSatisfy { $0.groupID == nil })
        #expect(settings.groups.isEmpty)
        #expect(settings.appearance.edge == .right)
        #expect(settings.appearance.scale.value == 0.85)
        #expect(abs(settings.appearance.offset.value - 0.11625928217821782) < 1e-12)
        #expect(settings.appearance.openTrigger == .hover)
        #expect(settings.appearance.emailVisibility == .hidden)
        #expect(settings.appearance.glowsWithUrgency)
        #expect(settings.appearance.railGroupFilter == nil)
        #expect(settings.alerts.thresholds.values.map(\.value) == [80, 100])
        #expect(settings.alerts.minimumTurnForFinishedAlert == .standard)
        #expect(settings.alerts.minimumTurnForFinishedAlert.seconds == 20)
        #expect(settings.alerts.withdrawsResolvedAlerts)
        #expect(settings.alerts.coalescesBursts)
        #expect(settings.general.globalShortcut == .controlOptionCommandU)
        #expect(settings.general.exportsWidgetData)
        #expect(!settings.general.launchesAtLogin)

        // Saving and loading again changes nothing.
        let reloaded = try JSONDecoder().decode(AppSettings.self, from: try JSONEncoder().encode(settings))
        #expect(reloaded == settings)
    }

    @Test("New keys are written to the settings file")
    func newKeysEncoded() throws {
        var settings = try AppSettings(accounts: [], groups: [try Fixture.group("Работа")])
        settings.appearance.railGroupFilter = settings.groups[0].id
        let data = try JSONEncoder().encode(settings)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let appearance = try #require(root["appearance"] as? [String: Any])
        let alerts = try #require(root["alerts"] as? [String: Any])
        let general = try #require(root["general"] as? [String: Any])
        #expect((root["groups"] as? [Any])?.count == 1)
        #expect(appearance["openTrigger"] as? String == "hover")
        #expect(appearance["emailVisibility"] as? String == "hidden")
        #expect(appearance["glowsWithUrgency"] as? Bool == true)
        #expect(appearance["railGroupFilter"] as? String == settings.groups[0].id.description)
        #expect(appearance["edge"] as? String == "top")
        #expect(appearance["bands"] != nil)
        #expect(alerts["minimumTurnForFinishedAlert"] as? Int == 20)
        #expect(alerts["withdrawsResolvedAlerts"] as? Bool == true)
        #expect(alerts["coalescesBursts"] as? Bool == true)
        #expect(alerts["peekDuration"] as? Int == 5)
        #expect(general["globalShortcut"] as? String == "controlOptionCommandU")
        #expect(general["exportsWidgetData"] as? Bool == true)
        #expect(general["launchesAtLogin"] as? Bool == false)
    }

    @Test("Every new option survives a round trip")
    func roundTrip() throws {
        let work = try Fixture.group("Работа", mutesSessions: true, mutesUsage: true)
        var settings = try AppSettings(
            accounts: [try Fixture.profile(.claude, path: "/tmp/.claude", groupID: work.id)],
            groups: [work]
        )
        settings.appearance.openTrigger = .hoverOrClick
        settings.appearance.emailVisibility = .masked
        settings.appearance.glowsWithUrgency = false
        settings.appearance.railGroupFilter = work.id
        settings.alerts.minimumTurnForFinishedAlert = try TurnAlertThreshold(seconds: 600)
        settings.alerts.withdrawsResolvedAlerts = false
        settings.alerts.coalescesBursts = false
        settings.general.globalShortcut = .off
        settings.general.exportsWidgetData = false
        let decoded = try JSONDecoder().decode(AppSettings.self, from: try JSONEncoder().encode(settings))
        #expect(decoded == settings)
    }

    @Test("Option enums have stable raw values")
    func enums() throws {
        #expect(IslandOpenTrigger.allCases.map(\.id) == ["hover", "click", "hoverOrClick"])
        #expect(EmailVisibility.allCases.map(\.id) == ["visible", "masked", "hidden"])
        #expect(GlobalShortcut.allCases.map(\.id) == ["off", "controlOptionCommandU", "controlOptionSpace", "controlOptionCommandL"])
        // An unknown value falls back to the default instead of failing the file.
        #expect(try JSONDecoder().decode(AppearanceSettings.self, from: Data(#"{"openTrigger":"doubleClick"}"#.utf8)).openTrigger == .hover)
    }

    @Test("Turn alert threshold: 0–600 seconds, stored as whole seconds")
    func turnAlertThreshold() throws {
        #expect(try TurnAlertThreshold(seconds: 0) == .always)
        #expect(try TurnAlertThreshold(seconds: 600).seconds == 600)
        #expect(throws: ValidationError.outOfRange(field: "alerts.minimumTurnForFinishedAlert", value: 601, lowerBound: 0, upperBound: 600)) {
            try TurnAlertThreshold(seconds: 601)
        }
        #expect(throws: ValidationError.self) { try TurnAlertThreshold(seconds: -1) }
        let fortyFive = try TurnAlertThreshold(seconds: 45)
        #expect(try JSONDecoder().decode([TurnAlertThreshold].self, from: Data("[45]".utf8)) == [fortyFive])
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([TurnAlertThreshold].self, from: Data("[900]".utf8)) }
        #expect(String(decoding: try JSONEncoder().encode([TurnAlertThreshold.standard]), as: UTF8.self) == "[20]")

        #expect(TurnAlertThreshold.standard.suppresses(turnDuration: 19.9))
        #expect(!TurnAlertThreshold.standard.suppresses(turnDuration: 20))
        #expect(!TurnAlertThreshold.always.suppresses(turnDuration: 0))
        #expect(TurnAlertThreshold.always < .standard)
    }
}

@Suite("E-mail masking")
struct EmailMaskTests {
    @Test("Addresses keep the first and last letter of the name and the whole domain", arguments: [
        ("example@test.com", "e••••e@test.com"),
        ("ab@x.io", "a•••@x.io"),
        ("a@x.io", "a•••@x.io"),
        ("abc@x.io", "a•••c@x.io"),
        ("abcdefgh@x.io", "a••••h@x.io"),
        ("averyveryverylongname@corp.example.com", "a••••••e@corp.example.com"),
        ("  me.name+tag@sub.domain.org \n", "m••••••g@sub.domain.org"),
        ("Шамсудин@почта.рф", "Ш••••н@почта.рф"),
    ])
    func addresses(input: String, expected: String) {
        #expect(DisplayText.maskEmail(input) == expected)
    }

    @Test("Text that is not an address becomes its first character plus bullets", arguments: [
        ("example", "e••••"),
        ("x", "x•••"),
        ("@gmail.com", "@•••••"),
        ("name@", "n•••"),
        ("", ""),
        ("   ", ""),
    ])
    func nonAddresses(input: String, expected: String) {
        #expect(DisplayText.maskEmail(input) == expected)
    }
}
