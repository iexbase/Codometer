@testable import CodometerApp
import CodometerCore
import CodometerL10n
import CodometerUI
import Foundation
import Testing

@Suite("Debug fixtures")
struct DebugFixtureTests {
    /// Every text a fixture can put on screen or into a capture, as one string.
    private func text(of fixture: DebugFixture) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var parts = [String(decoding: try encoder.encode(fixture.settings), as: UTF8.self)]
        for account in fixture.state.accounts {
            parts.append(account.identity.map { [$0.email, $0.organization, $0.plan].compactMap { $0 }.joined(separator: " ") } ?? "")
            parts.append(account.reading.map { String(decoding: (try? encoder.encode($0)) ?? Data(), as: UTF8.self) } ?? "")
            parts.append(account.sessions.map { [$0.title, $0.projectPath ?? "", $0.detail ?? "", $0.model ?? ""].joined(separator: " ") }.joined(separator: " "))
        }
        return parts.joined(separator: "\n")
    }

    @Test("Every fixture validates and matches its description")
    func shapes() throws {
        let single = try DebugFixtures.make(.single)
        #expect(single.state.accounts.map(\.profile.provider) == [.claude])
        let standard = try DebugFixtures.make(.standard)
        #expect(standard.state.accounts.map(\.profile.provider) == [.claude, .codex])
        let multi = try DebugFixtures.make(.multi)
        #expect(multi.settings.accounts.map(\.label.value) == ["Work", "Personal", "Side project"])
        #expect(multi.settings.accounts.filter { $0.provider == .claude }.count == 2)
        #expect(multi.settings.accounts.filter { $0.provider == .claude }.allSatisfy { $0.tint != .automatic && $0.monogram != nil })
        let activities = multi.state.accounts.flatMap(\.sessions).map(\.activity)
        #expect(activities.contains(.waiting) && activities.contains(.working))
        let limits = try DebugFixtures.make(.limits)
        #expect(limits.state.accounts.contains { $0.reading?.isAnyLimitReached == true })
        #expect(limits.resets.count == 1)
        #expect(try DebugFixtures.make(.empty).state.accounts.isEmpty)
        for name in DebugFixtureName.allCases {
            let fixture = try DebugFixtures.make(name)
            #expect(fixture.settings.accounts == fixture.state.accounts.map(\.profile))
            #expect(fixture.now == DebugFixtures.referenceNow)
        }
    }

    @Test("No e-mail but example.com, no real home folder")
    func privacy() throws {
        for name in DebugFixtureName.allCases {
            let text = try text(of: DebugFixtures.make(name))
            var rest = Substring(text)
            while let at = rest.firstIndex(of: "@") {
                let after = rest[rest.index(after: at)...]
                #expect(after.hasPrefix("example.com"), "\(name): an address outside example.com")
                rest = after
            }
            #expect(!text.contains(NSHomeDirectory()))
        }
    }

    @Test("Deterministic: the same fixture twice is the same data, analytics included")
    func deterministic() throws {
        for name in DebugFixtureName.allCases {
            let first = try DebugFixtures.make(name)
            let second = try DebugFixtures.make(name)
            #expect(first.settings == second.settings)
            #expect(first.state == second.state)
            #expect(first.resets == second.resets)
            for account in first.state.accounts {
                let day = DateInterval(start: Date(), duration: 86_400)
                #expect(first.timeline(accountID: account.id, interval: day) == second.timeline(accountID: account.id, interval: day))
                #expect(first.attribution(accountID: account.id, interval: day, grouping: .project) == second.attribution(accountID: account.id, interval: day, grouping: .project))
                #expect(first.windowHistory(accountID: account.id, bucketID: "claude", windowID: "session", since: first.now.addingTimeInterval(-3_600))
                    == second.windowHistory(accountID: account.id, bucketID: "claude", windowID: "session", since: first.now.addingTimeInterval(-3_600)))
            }
        }
    }

    @Test("Analytics end at the fixture's now; a day's timeline shows the Mac asleep")
    func analytics() throws {
        let fixture = try DebugFixtures.make(.multi)
        let account = try #require(fixture.state.accounts.first)
        let timeline = fixture.timeline(accountID: account.id, interval: DateInterval(start: Date(), duration: 86_400))
        #expect(timeline.interval.end == fixture.now && timeline.interval.duration == 86_400)
        #expect(!timeline.segments.isEmpty && timeline.usage != nil)
        #expect(timeline.gaps.map(\.reason) == [.macAsleep])
        let short = fixture.timeline(accountID: account.id, interval: DateInterval(start: Date(), duration: 5 * 3_600))
        #expect(short.gaps.isEmpty)
        let report = try #require(fixture.attribution(accountID: account.id, interval: DateInterval(start: Date(), duration: 86_400), grouping: .project))
        #expect(!report.shares.isEmpty)
    }

    @Test("A fixture keeps the base appearance, alerts and language")
    func base() throws {
        var general = GeneralSettings()
        general.language = .russian
        var appearance = AppearanceSettings()
        appearance.edge = .right
        let base = try AppSettings(accounts: [], appearance: appearance, general: general)
        let fixture = try DebugFixtures.make(.standard, base: base)
        #expect(fixture.settings.general.language == .russian)
        #expect(fixture.settings.appearance.edge == .right)
    }

    @Test("Scenario steps: generic keys are parsed strictly, other keys go to the domain handlers")
    func scenarioParsing() throws {
        let steps = try DebugScenarioScript.parse(Data("""
        [
          {"fixture": "multi"},
          {"language": "ru"},
          {"settingsPane": "diagnostics"},
          {"axdump": {"name": "settings", "window": "settings"}},
          {"capture": {"name": "card", "frames": 2, "interval": 0.1, "window": "card"}},
          {"trace": {"name": "rail", "frames": 3}},
          {"popover": true},
          {"expand": true},
          {"serviceStatus": {"provider": "claude", "level": "partialOutage"}},
          {"quit": true}
        ]
        """.utf8))
        #expect(steps[0] == .fixture(.multi))
        #expect(steps[1] == .language(.russian))
        #expect(steps[2] == .settingsPane(.diagnostics))
        #expect(steps[3] == .axdump(name: "settings", window: "settings"))
        #expect(steps[4] == .capture(name: "card", frames: 2, interval: 0.1, window: "card"))
        #expect(steps[5] == .trace(name: "rail", frames: 3, interval: 0, window: "island"))
        #expect(steps[6] == .popover(true))
        #expect(steps.map(\.key) == ["fixture", "language", "settingsPane", "axdump", "capture", "trace", "popover", "expand", "serviceStatus", "quit"])
        guard case .domain(_, let data) = steps[8] else {
            Issue.record("expected a domain step")
            return
        }
        let value = try #require(try DebugScenarioScript.domainValue(data) as? [String: Any])
        #expect(value["provider"] as? String == "claude")

        #expect(throws: DebugScenarioError.self) { try DebugScenarioScript.parse(Data(#"[{"fixture": "real"}]"#.utf8)) }
        #expect(throws: DebugScenarioError.self) { try DebugScenarioScript.parse(Data(#"[{"language": "de"}]"#.utf8)) }
        #expect(throws: DebugScenarioError.self) { try DebugScenarioScript.parse(Data(#"[{"settingsPane": "placement"}]"#.utf8)) }
        #expect(throws: DebugScenarioError.self) { try DebugScenarioScript.parse(Data(#"[{"capture": {"name": "x", "window": "desktop"}}]"#.utf8)) }
    }
}
