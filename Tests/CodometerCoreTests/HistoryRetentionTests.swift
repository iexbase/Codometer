import CodometerCore
import Foundation
import Testing

@Suite("History retention")
struct HistoryRetentionTests {
    @Test("7–90 days; the standard is 35 days; choices are 1, 2 and 5 weeks and 3 months")
    func validation() throws {
        #expect(HistoryRetention.standard.days == 35)
        #expect(HistoryRetention.choices.map(\.days) == [7, 14, 35, 90])
        #expect(try HistoryRetention(days: 7).timeInterval == 7 * 86_400)
        #expect(try HistoryRetention(days: 90).days == 90)
        #expect(try HistoryRetention(days: 21) > HistoryRetention(days: 14))
        #expect(throws: ValidationError.outOfRange(field: "general.historyRetention", value: 6, lowerBound: 7, upperBound: 90)) {
            try HistoryRetention(days: 6)
        }
        #expect(throws: ValidationError.self) { try HistoryRetention(days: 91) }
        #expect(throws: ValidationError.self) { try HistoryRetention(days: -35) }
    }

    @Test("Decodes as a number of days; missing or invalid means the standard")
    func coding() throws {
        #expect(try JSONDecoder().decode(HistoryRetention.self, from: Data("14".utf8)).days == 14)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(HistoryRetention.self, from: Data("400".utf8)) }
        #expect(String(decoding: try JSONEncoder().encode(try HistoryRetention(days: 90)), as: UTF8.self) == "90")
        for json in [#"{}"#, #"{"historyRetention": 3}"#, #"{"historyRetention": "35"}"#] {
            #expect(try JSONDecoder().decode(GeneralSettings.self, from: Data(json.utf8)).historyRetention == .standard)
        }
        #expect(try JSONDecoder().decode(GeneralSettings.self, from: Data(#"{"historyRetention": 21}"#.utf8)).historyRetention.days == 21)
    }
}
