import CodometerCore
import CoreGraphics
import Foundation
import Testing

@Suite("Display identity and policy")
struct DisplayPolicyTests {
    @Test("Display ids accept any UUID spelling and store it uppercase")
    func displayID() throws {
        #expect(try DisplayID("37d8832a-2d66-02ca-b9f7-8f30a301b230").rawValue == Displays.mainID)
        #expect(try DisplayID(Displays.mainID).description == Displays.mainID)
        for bad in ["", "not-a-uuid", "37D8832A2D6602CAB9F78F30A301B230", "{37D8832A-2D66-02CA-B9F7-8F30A301B230}", " \(Displays.mainID)", "1"] {
            #expect(throws: ValidationError.self) { try DisplayID(bad) }
        }
    }

    @Test("Policies round-trip as kind objects", arguments: [
        (DisplayPolicy.whereLeft, #"{"kind":"whereLeft"}"#),
        (.main, #"{"kind":"main"}"#),
        (.display(Displays.id(Displays.mainID)), #"{"id":"37D8832A-2D66-02CA-B9F7-8F30A301B230","kind":"display"}"#),
    ])
    func roundTrip(policy: DisplayPolicy, json: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        #expect(String(decoding: try encoder.encode(policy), as: UTF8.self) == json)
        #expect(try JSONDecoder().decode(DisplayPolicy.self, from: Data(json.utf8)) == policy)
    }

    @Test("An unknown kind, a bad or missing id, or a non-object decodes as whereLeft with a note", arguments: [
        #"{"kind":"followMouse"}"#, #"{"kind":"display","id":"nope"}"#, #"{"kind":"display"}"#, #""main""#, #"{}"#, "7",
    ])
    func tolerantDecode(json: String) throws {
        let report = SettingsDecodeReport()
        let decoder = JSONDecoder()
        decoder.userInfo[.settingsDecodeReport] = report
        let wrapped = #"{"policy":\#(json)}"#
        let decoded = try decoder.decode([String: DisplayPolicy].self, from: Data(wrapped.utf8))
        #expect(decoded["policy"] == .whereLeft)
        #expect(report.repairs == ["policy"])
    }

    @Test("A remembered display requires its id and sanitises its name to 64 characters")
    func rememberedDisplay() throws {
        let long = String(repeating: "x", count: 100)
        let remembered = RememberedDisplay(id: Displays.id(Displays.mainID), name: "  LG\u{0}UltraFine \n")
        #expect(remembered.name == "LGUltraFine")
        #expect(RememberedDisplay(id: Displays.id(Displays.mainID), name: long).name?.count == 64)
        #expect(RememberedDisplay(id: Displays.id(Displays.mainID), name: "   ").name == nil)
        let decoded = try JSONDecoder().decode(RememberedDisplay.self, from: Data(#"{"id":"\#(Displays.mainID)","name":5}"#.utf8))
        #expect(decoded.name == nil)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(RememberedDisplay.self, from: Data(#"{"name":"LG"}"#.utf8))
        }
        let roundTrip = try JSONDecoder().decode(RememberedDisplay.self, from: try JSONEncoder().encode(remembered))
        #expect(roundTrip == remembered)
    }
}
