import CodometerCore
import CodometerL10n
import Foundation
import Testing

@Suite("Settings files and repairs")
struct SettingsRepairTests {
    private func decode(_ json: String) throws -> DecodedSettingsFile {
        try AppSettings.decodeFile(SettingsFixtures.data(json))
    }

    private func id(_ raw: String) throws -> AccountID {
        AccountID(rawValue: try #require(UUID(uuidString: raw)))
    }

    @Test("Today's settings file loads unchanged, without repairs, and new keys take their defaults")
    func r2LoadsUnchanged() throws {
        let file = try decode(SettingsFixtures.r2)
        #expect(file.repairs.isEmpty)
        #expect(file.schemaVersion == 1)
        #expect(!file.isReadOnly)
        let settings = file.settings

        #expect(settings.accounts.count == 2)
        let work = try #require(settings.account(try id(SettingsFixtures.workAccountID)))
        #expect(work.label.value == "Claude · work")
        #expect(work.directory.path == "/Users/tester/.claude-work")
        #expect(work.pollInterval.seconds == 300)
        #expect(work.groupID?.description == SettingsFixtures.workGroupID)
        #expect(work.tint == .automatic)
        #expect(work.monogram == nil)
        let codex = try #require(settings.account(try id(SettingsFixtures.codexAccountID)))
        #expect(!codex.isEnabled)
        #expect(settings.groups.map(\.name.value) == ["Work", "Personal"])
        #expect(settings.groups.first?.mutesSessionAlerts == true)

        let appearance = settings.appearance
        #expect(appearance.edge == .right)
        #expect(appearance.offset.value == 0.25)
        #expect(appearance.style == .floating)
        #expect(appearance.surface == .darkGlass)
        #expect(appearance.scale.value == 1.25)
        #expect(appearance.resetTextStyle == .clockTime)
        #expect(!appearance.showsSecondaryRing && !appearance.showsPace && !appearance.hidesInFullScreen && !appearance.glowsWithUrgency)
        #expect(appearance.bands.watch.value == 60 && appearance.bands.critical.value == 85)
        #expect(appearance.openTrigger == .hoverOrClick)
        #expect(appearance.emailVisibility == .masked)
        #expect(appearance.railGroupFilter?.description == SettingsFixtures.workGroupID)

        let alerts = settings.alerts
        #expect(alerts.thresholds.values.map(\.value) == [50, 90])
        #expect(!alerts.notifiesOnReset && alerts.notifiesOnSessionFinished && !alerts.notifiesOnSessionWaiting)
        #expect(!alerts.playsSounds && !alerts.coalescesBursts && alerts.withdrawsResolvedAlerts)
        #expect(alerts.peekDuration.seconds == 8)
        #expect(alerts.minimumTurnForFinishedAlert.seconds == 45)

        let general = settings.general
        #expect(general.launchesAtLogin && !general.exportsWidgetData)
        #expect(general.globalShortcut == .controlOptionSpace)
        #expect(general.language == .russian)

        // Newer keys: defaults, and an existing install never sees onboarding.
        #expect(appearance.presentationStyle == .island)
        #expect(appearance.celebratesResets && appearance.showsForecast && appearance.snapsWhileDragging && appearance.playsHaptics)
        #expect(appearance.notchFusion == .automatic)
        #expect(appearance.islandDisplayPolicy == .whereLeft)
        #expect(appearance.islandDisplay == nil)
        #expect(appearance.floatingCard == FloatingCardSettings())
        #expect(general.energyMode == .automatic)
        #expect(general.historyRetention == .standard)
        #expect(general.onboarding == .completed)
        #expect(!general.onboarding.needsOnboarding)
        #expect(!general.showsVendorStatus)
        #expect(general.lastLaunchedVersion == nil)
    }

    @Test("Re-encoding today's file keeps every old key and value")
    func r2KeysSurviveReEncoding() throws {
        let settings = try decode(SettingsFixtures.r2).settings
        let encoded = try JSONEncoder().encode(settings)
        let original = try #require(try JSONSerialization.jsonObject(with: SettingsFixtures.data(SettingsFixtures.r2)) as? NSDictionary)
        let written = try #require(try JSONSerialization.jsonObject(with: encoded) as? NSDictionary)
        for section in ["appearance", "alerts", "general"] {
            let old = try #require(original[section] as? NSDictionary)
            let new = try #require(written[section] as? NSDictionary)
            for case let key as String in old.allKeys {
                #expect(new[key] as? NSObject == old[key] as? NSObject, "\(section).\(key)")
            }
        }
        #expect(written["accounts"] as? NSArray != nil)
        #expect(try AppSettings.decodeFile(encoded).settings == settings)
    }

    @Test("A file from a newer build loads read-only: known keys kept, unknown values repaired, extra keys ignored")
    func futureLoadsReadOnly() throws {
        let file = try decode(SettingsFixtures.future)
        #expect(file.schemaVersion == 2)
        #expect(file.isReadOnly)
        let settings = file.settings
        // The account with an unknown provider drops only itself; the other keeps its known values.
        #expect(settings.accounts.count == 1)
        let work = try #require(settings.accounts.first)
        #expect(work.tint == .automatic)
        #expect(work.monogram?.value == "W")
        #expect(settings.appearance.edge == .top)
        #expect(settings.appearance.presentationStyle == .island)
        #expect(settings.appearance.notchFusion == .automatic)
        #expect(settings.appearance.surface == .glass)
        #expect(settings.appearance.islandDisplayPolicy == .whereLeft)
        let card = settings.appearance.floatingCard
        #expect(card.theme == .graphite)
        #expect(card.size == .regular)
        #expect(card.thirdTile == .agents)
        #expect(card.accountSelection == .mostUrgent)
        #expect(card.isMinimized)
        #expect(!settings.alerts.playsSounds)
        #expect(settings.general.language == .english)
        #expect(settings.general.energyMode == .automatic)
        #expect(settings.general.showsVendorStatus)
        #expect(settings.general.onboarding.completedVersion == 3)
        #expect(!settings.general.onboarding.needsOnboarding)
        let newer = try AppVersion("2.0.0")
        #expect(settings.general.lastLaunchedVersion == newer)

        let expected: Set<String> = [
            "accounts[0].tint", "accounts[1]",
            "appearance.presentationStyle", "appearance.notchFusion", "appearance.surface", "appearance.islandDisplayPolicy",
            "appearance.floatingCard.theme", "appearance.floatingCard.size", "appearance.floatingCard.accountSelection",
            "general.language", "general.energyMode",
        ]
        #expect(Set(file.repairs) == expected)
    }

    @Test("A damaged file keeps everything valid and notes each repair")
    func damagedIsRepaired() throws {
        let file = try decode(SettingsFixtures.damaged)
        #expect(file.schemaVersion == 1)
        #expect(!file.isReadOnly)
        let settings = file.settings
        #expect(settings.accounts.map(\.label.value) == ["Claude · work", "Codex"])
        #expect(settings.groups.map(\.name.value) == ["Work", "Personal"])
        #expect(settings.accounts.first?.groupID?.description == SettingsFixtures.workGroupID)
        #expect(settings.accounts.last?.groupID?.description == SettingsFixtures.personalGroupID)
        #expect(settings.appearance.edge == .bottom)
        #expect(settings.appearance.scale == .standard)
        #expect(settings.general.globalShortcut == .controlOptionCommandL)
        #expect(Set(file.repairs) == ["accounts[1]", "groups.id", "appearance.scale"])
        // The repaired settings are valid by construction: they round-trip without further repairs.
        let again = try AppSettings.decodeFile(try JSONEncoder().encode(settings))
        #expect(again.repairs.isEmpty)
        #expect(again.settings == settings)
    }

    @Test("Duplicate accounts and groups keep the first; limits keep the first sixteen accounts and eight groups")
    func invariantsRepaired() throws {
        func account(_ index: Int, id: String? = nil, path: String? = nil) -> String {
            let uuid = id ?? String(format: "8C8E4A0E-3B1A-4C7B-9D5E-%012d", index)
            return #"{"id":"\#(uuid)","provider":"codex","label":"Codex \#(index)","directory":"\#(path ?? "/tmp/.codex-\(index)")"}"#
        }
        func group(_ index: Int, id: String? = nil, name: String? = nil) -> String {
            let uuid = id ?? String(format: "9C8E4A0E-3B1A-4C7B-9D5E-%012d", index)
            return #"{"id":"\#(uuid)","name":"\#(name ?? "Group \(index)")"}"#
        }
        let accounts = (1...18).map { account($0) }
            + [account(19, id: String(format: "8C8E4A0E-3B1A-4C7B-9D5E-%012d", 1)), account(20, path: "/tmp/.codex-2")]
        let groups = (1...9).map { group($0) } + [group(10, name: "GROUP 1")]
        let json = #"{"schemaVersion":1,"accounts":[\#(accounts.joined(separator: ","))],"groups":[\#(groups.joined(separator: ","))]}"#
        let file = try decode(json)
        #expect(file.settings.accounts.count == AppSettings.maximumAccounts)
        #expect(file.settings.accounts.first?.label.value == "Codex 1")
        #expect(file.settings.accounts.last?.label.value == "Codex 16")
        #expect(file.settings.groups.count == AppSettings.maximumGroups)
        #expect(file.settings.groups.map(\.name.value) == (1...8).map { "Group \($0)" })
        #expect(Set(file.repairs) == ["accounts.id", "accounts.directory", "accounts", "groups.name", "groups"])
    }

    @Test("Group references and filters to missing groups are dropped quietly")
    func danglingReferences() throws {
        let json = """
        {"schemaVersion":1,
         "accounts":[{"id":"\(SettingsFixtures.workAccountID)","provider":"codex","label":"Codex","directory":"/tmp/.codex","groupID":"\(SettingsFixtures.workGroupID)"}],
         "appearance":{"railGroupFilter":"\(SettingsFixtures.personalGroupID)",
                       "floatingCard":{"accountSelection":{"kind":"fixed","id":"\(SettingsFixtures.brokenAccountID)"}}}}
        """
        let file = try decode(json)
        #expect(file.repairs.isEmpty)
        #expect(file.settings.accounts.first?.groupID == nil)
        #expect(file.settings.appearance.railGroupFilter == nil)
        #expect(file.settings.appearance.floatingCard.accountSelection == .mostUrgent)
    }

    @Test("A card fixed to an existing account keeps it until that account is removed")
    func cardAccountFollowsAccounts() throws {
        let codex = try Fixture.profile()
        let claude = try Fixture.profile(.claude, path: "/tmp/.claude", label: "Claude")
        var settings = try AppSettings(accounts: [codex, claude])
        settings.appearance.floatingCard.accountSelection = .fixed(claude.id)
        let decoded = try AppSettings.decodeFile(try JSONEncoder().encode(settings)).settings
        #expect(decoded.appearance.floatingCard.accountSelection == .fixed(claude.id))
        let removed = try settings.replacingAccounts([codex])
        #expect(removed.appearance.floatingCard.accountSelection == .mostUrgent)
    }

    @Test("Schema versions: missing or invalid is repaired as 1, newer is read-only", arguments: [
        (#"{}"#, 1, true, false),
        (#"{"schemaVersion": null}"#, 1, true, false),
        (#"{"schemaVersion": 0}"#, 1, true, false),
        (#"{"schemaVersion": "one"}"#, 1, true, false),
        (#"{"schemaVersion": 1}"#, 1, false, false),
        (#"{"schemaVersion": 99}"#, 99, false, true),
    ])
    func schemaVersions(json: String, version: Int, repaired: Bool, readOnly: Bool) throws {
        let file = try decode(json)
        #expect(file.schemaVersion == version)
        #expect(file.repairs == (repaired ? ["schemaVersion"] : []))
        #expect(file.isReadOnly == readOnly)
        #expect(file.settings.accounts.isEmpty)
    }

    @Test("Only data that is not a JSON object fails", arguments: ["not json", "[]", #""settings""#, "42", ""])
    func notAnObject(json: String) {
        #expect(throws: (any Error).self) { try AppSettings.decodeFile(SettingsFixtures.data(json)) }
    }

    @Test("Sections of the wrong type fall back to defaults with a note")
    func wrongSectionTypes() throws {
        let file = try decode(#"{"schemaVersion":1,"accounts":{"a":1},"groups":"none","appearance":[],"alerts":3,"general":true}"#)
        #expect(Set(file.repairs) == ["accounts", "groups", "appearance", "alerts", "general"])
        #expect(file.settings == .empty)
    }

    @Test("Every new key round-trips with non-default values")
    func newKeysRoundTrip() throws {
        let display = try DisplayID(SettingsFixtures.displayID)
        let account = try Fixture.profile(.claude, path: "/tmp/.claude-work", label: "Claude · work")
            .updated(tint: .teal, monogram: try AccountMonogram(validating: "w"))
        var settings = try AppSettings(accounts: [account])
        settings.appearance.presentationStyle = .floatingCard
        settings.appearance.celebratesResets = false
        settings.appearance.showsForecast = false
        settings.appearance.snapsWhileDragging = false
        settings.appearance.playsHaptics = false
        settings.appearance.notchFusion = .off
        settings.appearance.islandDisplayPolicy = .display(display)
        settings.appearance.islandDisplay = RememberedDisplay(id: display, name: "LG UltraFine")
        var placements = FloatingCardPlacements()
        placements.remember(CardPlacement(displayID: display, anchor: .topTrailing, snapped: true, x: .one, y: .zero))
        placements.current = display
        placements.displacedFrom = display
        settings.appearance.floatingCard = FloatingCardSettings(
            theme: .midnight,
            size: .compact,
            accountSelection: .fixed(account.id),
            thirdTile: .sessionWindow,
            isMinimized: true,
            keepsAboveWindows: false,
            displayPolicy: .main,
            placements: placements,
            hasShownCoachMark: true
        )
        settings.general.energyMode = .saveBattery
        settings.general.historyRetention = try HistoryRetention(days: 90)
        settings.general.onboarding = .notStarted
        settings.general.showsVendorStatus = true
        settings.general.lastLaunchedVersion = try AppVersion("1.0.0")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(settings)
        let file = try AppSettings.decodeFile(data)
        #expect(file.repairs.isEmpty)
        #expect(file.settings == settings)

        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let appearance = try #require(object["appearance"] as? [String: Any])
        #expect(appearance["presentationStyle"] as? String == "floatingCard")
        #expect(appearance["notchFusion"] as? String == "off")
        #expect((appearance["islandDisplayPolicy"] as? [String: String]) == ["kind": "display", "id": SettingsFixtures.displayID])
        #expect((appearance["islandDisplay"] as? [String: String]) == ["id": SettingsFixtures.displayID, "name": "LG UltraFine"])
        let card = try #require(appearance["floatingCard"] as? [String: Any])
        #expect((card["accountSelection"] as? [String: String]) == ["kind": "fixed", "id": account.id.description])
        #expect((card["displayPolicy"] as? [String: String]) == ["kind": "main"])
        let general = try #require(object["general"] as? [String: Any])
        #expect(general["historyRetention"] as? Int == 90)
        #expect((general["onboarding"] as? [String: Int]) == ["completedVersion": 0])
        #expect(general["lastLaunchedVersion"] as? String == "1.0.0")
        #expect(general["energyMode"] as? String == "saveBattery")
        let accounts = try #require(object["accounts"] as? [[String: Any]])
        #expect(accounts.first?["tint"] as? String == "teal")
        #expect(accounts.first?["monogram"] as? String == "W")
    }

    @Test("The Appendix A example decodes without repairs")
    func appendixExample() throws {
        let json = """
        {
          "schemaVersion": 1,
          "accounts": [{ "id": "\(SettingsFixtures.workAccountID)", "provider": "claude", "label": "Claude · work",
                         "directory": "/Users/tester/.claude-work", "tint": "teal", "monogram": "W" }],
          "appearance": {
            "presentationStyle": "island", "celebratesResets": true, "showsForecast": true,
            "snapsWhileDragging": true, "playsHaptics": true, "notchFusion": "automatic",
            "islandDisplayPolicy": { "kind": "whereLeft" },
            "islandDisplay": { "id": "\(SettingsFixtures.displayID)", "name": "LG UltraFine" },
            "floatingCard": {
              "theme": "graphite", "size": "regular", "accountSelection": { "kind": "mostUrgent" },
              "thirdTile": "weeklyReset", "isMinimized": false, "keepsAboveWindows": true,
              "displayPolicy": { "kind": "whereLeft" },
              "placements": { "current": "\(SettingsFixtures.displayID)", "byDisplay": [
                { "displayID": "\(SettingsFixtures.displayID)", "anchor": "topTrailing", "snapped": true, "x": 1, "y": 0 } ] },
              "hasShownCoachMark": false
            }
          },
          "general": {
            "language": "en", "energyMode": "automatic", "historyRetention": 35,
            "onboarding": { "completedVersion": 1 }, "showsVendorStatus": false, "lastLaunchedVersion": "1.0.0"
          }
        }
        """
        let file = try decode(json)
        #expect(file.repairs.isEmpty)
        let placement = try #require(file.settings.appearance.floatingCard.placements.byDisplay.first)
        #expect(placement.anchor == .topTrailing)
        #expect(placement.x == .one && placement.y == .zero)
        #expect(file.settings.accounts.first?.tint == .teal)
        #expect(file.settings.general.language == LanguagePreference.english)
    }
}
