import CodometerCore
import Foundation
import Testing

@Suite("Floating card settings")
struct FloatingCardSettingsTests {
    private static let displays = (0..<20).map { index in
        String(format: "37D8832A-2D66-02CA-B9F7-%012X", index)
    }

    private func placement(_ index: Int, anchor: CardAnchor = .topTrailing) throws -> CardPlacement {
        CardPlacement(displayID: try DisplayID(Self.displays[index]), anchor: anchor, snapped: false, x: .half, y: try UnitInterval(0.25))
    }

    private func decode(_ json: String) throws -> (FloatingCardSettings, [String]) {
        let report = SettingsDecodeReport()
        let decoder = JSONDecoder()
        decoder.userInfo[.settingsDecodeReport] = report
        return (try decoder.decode(FloatingCardSettings.self, from: Data(json.utf8)), report.repairs)
    }

    @Test("Defaults: Graphite, Regular, most urgent account, weekly reset tile, the strip on that account, expanded, above windows")
    func defaults() {
        let card = FloatingCardSettings()
        #expect(card.theme == .graphite && card.size == .regular && card.thirdTile == .weeklyReset)
        #expect(card.stripScope == .selectedAccount)
        #expect(card.accountSelection == .mostUrgent && card.displayPolicy == .whereLeft)
        #expect(!card.isMinimized && card.keepsAboveWindows && !card.hasShownCoachMark)
        #expect(card.placements == .empty && card.placements.byDisplay.isEmpty && card.placements.current == nil)
    }

    @Test("Twenty remembered placements keep the newest eight, one per display")
    func placementsBounded() throws {
        var placements = FloatingCardPlacements.empty
        for index in 0..<20 {
            placements.remember(try placement(index))
        }
        #expect(placements.byDisplay.count == FloatingCardPlacements.maximumCount)
        #expect(placements.byDisplay.first?.displayID.rawValue == Self.displays[19])
        #expect(placements.byDisplay.last?.displayID.rawValue == Self.displays[12])
        // Remembering a display again moves it to the front and replaces its old placement.
        placements.remember(try placement(15, anchor: .bottomLeading))
        #expect(placements.byDisplay.count == 8)
        #expect(placements.byDisplay.first?.anchor == .bottomLeading)
        #expect(placements.byDisplay.filter { $0.displayID.rawValue == Self.displays[15] }.count == 1)
        #expect(try placements.placement(for: DisplayID(Self.displays[15]))?.anchor == .bottomLeading)
        #expect(try placements.placement(for: DisplayID(Self.displays[0])) == nil)
    }

    @Test("Decoding twenty placements trims to eight with a note; duplicates keep the first")
    func decodeTrims() throws {
        let entries = Self.displays.map { #"{"displayID":"\#($0)","anchor":"center","snapped":true,"x":0.5,"y":0.5}"# }
        let duplicate = #"{"displayID":"\#(Self.displays[0])","anchor":"top","snapped":false,"x":0,"y":0}"#
        let json = #"{"placements":{"current":"\#(Self.displays[3])","byDisplay":[\#(([entries[0], duplicate] + entries.dropFirst()).joined(separator: ","))]}}"#
        let (card, notes) = try decode(json)
        #expect(card.placements.byDisplay.count == 8)
        #expect(card.placements.byDisplay.first?.anchor == .center)
        #expect(Set(card.placements.byDisplay.map(\.displayID)).count == 8)
        #expect(card.placements.current?.rawValue == Self.displays[3])
        #expect(notes == ["placements.byDisplay"])
    }

    @Test("Unknown enums take defaults with notes; unknown keys are ignored")
    func unknownEnums() throws {
        let (card, notes) = try decode(#"{"theme":"neon","size":"tall","thirdTile":"weather","stripScope":"galaxy","accountSelection":{"kind":"random"},"displayPolicy":{"kind":"mouse"},"minimizedForm":"orb","isMinimized":true}"#)
        #expect(card.theme == .graphite && card.size == .regular && card.thirdTile == .weeklyReset)
        #expect(card.stripScope == .selectedAccount)
        #expect(card.accountSelection == .mostUrgent && card.displayPolicy == .whereLeft)
        #expect(card.isMinimized)
        #expect(Set(notes) == ["theme", "size", "thirdTile", "stripScope", "accountSelection", "displayPolicy"])
    }

    @Test("The strip size and every scope decode by their raw names; a missing scope is the default without a note")
    func stripSizeAndScope() throws {
        let (strip, notes) = try decode(#"{"size":"strip"}"#)
        #expect(strip.size == .strip && strip.stripScope == .selectedAccount)
        #expect(notes.isEmpty)
        for scope in CardStripScope.allCases {
            let (card, scopeNotes) = try decode(#"{"size":"strip","stripScope":"\#(scope.rawValue)"}"#)
            #expect(card.stripScope == scope)
            #expect(scopeNotes.isEmpty)
        }
        #expect(CardStripScope.allCases.map(\.rawValue) == ["selectedAccount", "claude", "codex", "allAccounts"])
        #expect(CardSize.allCases.map(\.rawValue) == ["compact", "regular", "strip"])
    }

    @Test("A bad display id drops that placement; bad current and displaced ids become nil")
    func badDisplayID() throws {
        let json = #"{"placements":{"current":"monitor-1","displacedFrom":42,"byDisplay":[{"displayID":"monitor-1","anchor":"top","snapped":true,"x":0,"y":0},{"displayID":"\#(Self.displays[1])","anchor":"top","snapped":true,"x":0,"y":0}]}}"#
        let (card, notes) = try decode(json)
        #expect(card.placements.byDisplay.map(\.displayID.rawValue) == [Self.displays[1]])
        #expect(card.placements.current == nil && card.placements.displacedFrom == nil)
        #expect(Set(notes) == ["placements.byDisplay[0]", "placements.current", "placements.displacedFrom"])
    }

    @Test("Fractions out of range are clamped with a note; a missing anchor or fraction drops the placement")
    func fractions() throws {
        let id = Self.displays[2]
        let json = #"{"placements":{"byDisplay":[{"displayID":"\#(id)","anchor":"leading","x":1.2,"y":-0.1},{"displayID":"\#(Self.displays[3])","x":0.5,"y":0.5},{"displayID":"\#(Self.displays[4])","anchor":"trailing","x":"half","y":0.5}]}}"#
        let (card, notes) = try decode(json)
        let placement = try #require(card.placements.byDisplay.first)
        #expect(card.placements.byDisplay.count == 1)
        #expect(placement.x == .one && placement.y == .zero && !placement.snapped)
        #expect(Set(notes) == ["placements.byDisplay[0].x", "placements.byDisplay[0].y", "placements.byDisplay[1]", "placements.byDisplay[2]"])
    }

    @Test("Unit intervals validate and clamp")
    func unitInterval() throws {
        #expect(try UnitInterval(0).value == 0 && UnitInterval(1).value == 1)
        for bad in [-0.01, 1.01, .nan, .infinity] {
            #expect(throws: ValidationError.self) { try UnitInterval(bad) }
        }
        #expect(UnitInterval.clamped(3).value == 1)
        #expect(UnitInterval.clamped(-3).value == 0)
        #expect(UnitInterval.clamped(.nan) == .half)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(UnitInterval.self, from: Data("2".utf8)) }
    }

    @Test("Account selection codes as a kind object and tolerates anything else")
    func accountSelection() throws {
        let id = AccountID()
        let fixed = CardAccountSelection.fixed(id)
        let encoded = try JSONEncoder().encode(fixed)
        let object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: String])
        #expect(object == ["kind": "fixed", "id": id.description])
        #expect(try JSONDecoder().decode(CardAccountSelection.self, from: encoded) == fixed)
        for json in [#"{"kind":"fixed"}"#, #"{"kind":"fixed","id":"x"}"#, #""mostUrgent""#, #"{"kind":"random"}"#] {
            #expect(try JSONDecoder().decode(CardAccountSelection.self, from: Data(json.utf8)) == .mostUrgent)
        }
    }

    @Test("Every card setting round-trips")
    func roundTrip() throws {
        var placements = FloatingCardPlacements(
            byDisplay: [try placement(0), try placement(1, anchor: .bottom)],
            current: try DisplayID(Self.displays[1]),
            displacedFrom: try DisplayID(Self.displays[0])
        )
        placements.current = try DisplayID(Self.displays[0])
        for (theme, scope) in zip(CardTheme.allCases, CardStripScope.allCases) {
            let card = FloatingCardSettings(
                theme: theme,
                size: .strip,
                accountSelection: .fixed(AccountID()),
                thirdTile: .agents,
                stripScope: scope,
                isMinimized: true,
                keepsAboveWindows: false,
                displayPolicy: .display(try DisplayID(Self.displays[5])),
                placements: placements,
                hasShownCoachMark: true
            )
            let (decoded, notes) = try decode(String(decoding: try JSONEncoder().encode(card), as: UTF8.self))
            #expect(decoded == card)
            #expect(notes.isEmpty)
        }
        #expect(CardAnchor.allCases.count == 9)
    }
}
