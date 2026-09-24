import CodometerCore
import Foundation
import Testing

@Suite("Lenient decoding")
struct LenientDecodingTests {
    private enum Color: String, Codable {
        case red, green
    }

    /// Decodes one object through each helper, with a fresh report.
    private struct Probe: Decodable {
        let color: Color
        let optionalColor: Color?
        let numbers: [Int]

        enum CodingKeys: String, CodingKey {
            case color, optionalColor, numbers
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let report = decoder.settingsDecodeReport
            color = container.decodeLenient(Color.self, forKey: .color, default: .green, report: report)
            optionalColor = container.decodeLenientIfPresent(Color.self, forKey: .optionalColor, report: report)
            numbers = container.decodeLossyArray(Int.self, forKey: .numbers, report: report)
        }
    }

    private func probe(_ json: String) throws -> (Probe, [String]) {
        let report = SettingsDecodeReport()
        let decoder = JSONDecoder()
        decoder.userInfo[.settingsDecodeReport] = report
        let value = try decoder.decode(Probe.self, from: Data(json.utf8))
        return (value, report.repairs)
    }

    @Test("Missing and null values take the default silently")
    func missingAndNull() throws {
        let (missing, missingNotes) = try probe("{}")
        #expect(missing.color == .green && missing.optionalColor == nil && missing.numbers.isEmpty)
        #expect(missingNotes.isEmpty)
        let (null, nullNotes) = try probe(#"{"color": null, "optionalColor": null, "numbers": null}"#)
        #expect(null.color == .green && null.optionalColor == nil && null.numbers.isEmpty)
        #expect(nullNotes.isEmpty)
    }

    @Test("Valid values decode without notes")
    func valid() throws {
        let (value, notes) = try probe(#"{"color": "red", "optionalColor": "red", "numbers": [1, 2]}"#)
        #expect(value.color == .red && value.optionalColor == .red && value.numbers == [1, 2])
        #expect(notes.isEmpty)
    }

    @Test("Unknown raw values and wrong types take the default with a note", arguments: [
        #"{"color": "blue"}"#, #"{"color": 3}"#, #"{"color": ["red"]}"#, #"{"color": {"x": 1}}"#,
    ])
    func unusable(json: String) throws {
        let (value, notes) = try probe(json)
        #expect(value.color == .green)
        #expect(notes == ["color"])
    }

    @Test("An unusable optional value becomes nil with a note")
    func unusableOptional() throws {
        let (value, notes) = try probe(#"{"optionalColor": "purple"}"#)
        #expect(value.optionalColor == nil)
        #expect(notes == ["optionalColor"])
    }

    @Test("Lossy arrays drop only unusable elements and note each index")
    func lossyArray() throws {
        let (value, notes) = try probe(#"{"numbers": [1, "two", 3, null, 4.5, 5]}"#)
        #expect(value.numbers == [1, 3, 5])
        #expect(notes == ["numbers[1]", "numbers[3]", "numbers[4]"])
        let (notArray, arrayNotes) = try probe(#"{"numbers": {"0": 1}}"#)
        #expect(notArray.numbers.isEmpty)
        #expect(arrayNotes == ["numbers"])
    }

    @Test("Without a report nothing is noted and decoding still repairs")
    func withoutReport() throws {
        let value = try JSONDecoder().decode(Probe.self, from: Data(#"{"color": "blue", "numbers": [1, "x"]}"#.utf8))
        #expect(value.color == .green)
        #expect(value.numbers == [1])
    }

    @Test("Coding paths name nested keys and indexes")
    func paths() throws {
        let report = SettingsDecodeReport()
        let decoder = JSONDecoder()
        decoder.userInfo[.settingsDecodeReport] = report
        let json = #"{"schemaVersion":1,"accounts":[{"id":"8C8E4A0E-3B1A-4C7B-9D5E-000000000001","provider":"codex","label":"Codex","directory":"/tmp/.codex","tint":"blue","isEnabled":"yes"}],"appearance":{"floatingCard":{"placements":{"byDisplay":[{"displayID":"bad"}]}}}}"#
        _ = try decoder.decode(AppSettings.self, from: Data(json.utf8))
        #expect(report.repairs == [
            "accounts[0].isEnabled", "accounts[0].tint",
            "appearance.floatingCard.placements.byDisplay[0]",
        ])
        #expect(SettingsDecodeReport.path([]) == "(root)")
    }

    @Test("A report keeps at most its maximum number of notes")
    func boundedNotes() {
        let report = SettingsDecodeReport()
        for index in 0..<(SettingsDecodeReport.maximumNotes + 20) {
            report.note("numbers[\(index)]")
        }
        #expect(report.repairs.count == SettingsDecodeReport.maximumNotes)
        #expect(report.repairs.first == "numbers[0]")
    }

    @Test("Every settings section decodes leniently field by field")
    func everySection() throws {
        let json = """
        {"schemaVersion": 1,
         "appearance": {"edge": "diagonal", "offset": 2, "style": 1, "surface": "wood", "visibility": "sometimes", "scale": 0.1,
                        "resetTextStyle": "sundial", "showsSecondaryRing": "no", "showsPace": 0, "hidesInFullScreen": [],
                        "bands": {"watch": 90, "critical": 10}, "openTrigger": "telepathy", "emailVisibility": "loud",
                        "glowsWithUrgency": "bright", "railGroupFilter": "not-a-uuid", "celebratesResets": "yes",
                        "showsForecast": 1, "snapsWhileDragging": null, "playsHaptics": "on", "islandDisplay": {"id": "nope"}},
         "alerts": {"thresholds": [0], "notifiesOnReset": "x", "notifiesOnSessionFinished": 2, "notifiesOnSessionWaiting": [],
                    "playsSounds": {}, "peekDuration": 99, "minimumTurnForFinishedAlert": -1, "withdrawsResolvedAlerts": "y",
                    "coalescesBursts": 5},
         "general": {"launchesAtLogin": "sure", "globalShortcut": "hyperKey", "exportsWidgetData": 3, "historyRetention": 400,
                     "onboarding": {"completedVersion": -2}, "showsVendorStatus": "maybe", "lastLaunchedVersion": "1.0"}}
        """
        let file = try AppSettings.decodeFile(Data(json.utf8))
        let defaults = AppSettings.empty
        #expect(file.settings.appearance == defaults.appearance)
        #expect(file.settings.alerts == defaults.alerts)
        #expect(file.settings.general == defaults.general)
        let expected: Set<String> = [
            "appearance.edge", "appearance.offset", "appearance.style", "appearance.surface", "appearance.visibility",
            "appearance.scale", "appearance.resetTextStyle", "appearance.showsSecondaryRing", "appearance.showsPace",
            "appearance.hidesInFullScreen", "appearance.bands", "appearance.openTrigger", "appearance.emailVisibility",
            "appearance.glowsWithUrgency", "appearance.railGroupFilter", "appearance.celebratesResets",
            "appearance.showsForecast", "appearance.playsHaptics", "appearance.islandDisplay",
            "alerts.thresholds", "alerts.notifiesOnReset", "alerts.notifiesOnSessionFinished",
            "alerts.notifiesOnSessionWaiting", "alerts.playsSounds", "alerts.peekDuration",
            "alerts.minimumTurnForFinishedAlert", "alerts.withdrawsResolvedAlerts", "alerts.coalescesBursts",
            "general.launchesAtLogin", "general.globalShortcut", "general.exportsWidgetData", "general.historyRetention",
            "general.onboarding", "general.showsVendorStatus", "general.lastLaunchedVersion",
        ]
        #expect(Set(file.repairs) == expected)
    }

    @Test("Account fields: a bad provider, label or directory drops the account; other fields repair")
    func accountFields() throws {
        func accounts(_ body: String) throws -> DecodedSettingsFile {
            try AppSettings.decodeFile(Data(#"{"schemaVersion":1,"accounts":[\#(body)]}"#.utf8))
        }
        let base = #""id":"8C8E4A0E-3B1A-4C7B-9D5E-000000000001""#
        for broken in [
            #"{\#(base),"provider":"gemini","label":"x","directory":"/tmp/.x"}"#,
            #"{\#(base),"provider":"claude","label":"  ","directory":"/tmp/.claude"}"#,
            #"{\#(base),"provider":"claude","label":"Claude","directory":"relative"}"#,
            #"{"id":"nope","provider":"claude","label":"Claude","directory":"/tmp/.claude"}"#,
        ] {
            let file = try accounts(broken)
            #expect(file.settings.accounts.isEmpty)
            #expect(file.repairs == ["accounts[0]"])
        }
        let repaired = try accounts(#"{\#(base),"provider":"claude","label":"Claude","directory":"/tmp/.claude","pollInterval":60,"groupID":7,"monogram":"ABC","isEnabled":false}"#)
        let account = try #require(repaired.settings.accounts.first)
        #expect(account.pollInterval == ProviderKind.claude.defaultPollInterval)
        #expect(account.groupID == nil)
        #expect(account.monogram == nil)
        #expect(!account.isEnabled)
        #expect(Set(repaired.repairs) == ["accounts[0].pollInterval", "accounts[0].groupID", "accounts[0].monogram"])
    }

    @Test("Group fields: a bad id or name drops the group; bad mutes repair")
    func groupFields() throws {
        let json = #"{"schemaVersion":1,"groups":[{"id":"x","name":"A"},{"id":"8C8E4A0E-3B1A-4C7B-9D5E-0000000000AA","name":"B","mutesSessionAlerts":"yes"}]}"#
        let file = try AppSettings.decodeFile(Data(json.utf8))
        #expect(file.settings.groups.map(\.name.value) == ["B"])
        #expect(file.settings.groups.first?.mutesSessionAlerts == false)
        #expect(Set(file.repairs) == ["groups[0]", "groups[1].mutesSessionAlerts"])
    }
}
