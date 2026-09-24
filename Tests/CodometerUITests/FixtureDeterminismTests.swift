import CodometerCore
@testable import CodometerUI
import Foundation
import Testing

/// Gated renders are reviewed as English/Russian pairs and compared between runs, and `AccountStyleResolver` seeds
/// an automatic tint with a hash of the account's id. A fixture that minted a fresh `AccountID` therefore painted
/// the same surface a different colour in each pass. Every fixture account is derived from a seed instead, and
/// these tests are what keeps it that way.
@Suite("Fixture determinism")
struct FixtureDeterminismTests {
    @Test("A fixture account's id depends only on its seed")
    func idsAreDerived() throws {
        #expect(UIFixture.accountID("a") == UIFixture.accountID("a"))
        #expect(UIFixture.accountID("a") != UIFixture.accountID("b"))
        #expect(UIFixture.groupID("a") != UIFixture.groupID("b"))
        #expect(try UIFixture.profile("Work").id == UIFixture.profile("Work").id)
        #expect(try UIFixture.profile("Work").id != UIFixture.profile("Home").id)
        #expect(try UIFixture.profile("Work").id != UIFixture.profile("Work", provider: .codex).id)
        #expect(try UIFixture.group("Работа").id == UIFixture.group("Работа").id)
        // An explicit id still wins, for a fixture that needs two accounts with the same provider and label.
        let pinned = UIFixture.accountID("second")
        #expect(try UIFixture.profile("Work", id: pinned).id == pinned)
    }

    /// Pinned, so a change to the derivation shows up here instead of as a silent recolouring of every render.
    @Test("The ids are the same in every process, not only within one")
    func idsSurviveARestart() throws {
        #expect(UIFixture.accountID("visuals/side").rawValue.uuidString == "42880B32-B639-4EF8-8793-A1C69023A38F")
        #expect(UIFixture.groupID("Работа").rawValue.uuidString == "4E685148-9E20-4D0B-A9A4-8741B1F93A10")
        #expect(try UIFixture.profile("Work").id.rawValue.uuidString == "D159B485-C6C7-4095-BDD7-7CDB6F8C3F14")
        // Shaped like an ordinary random UUID, so nothing downstream can tell a fixture id apart by its bits.
        let raw = UIFixture.accountID("anything").rawValue.uuid
        let version = raw.6 & 0xF0
        let variant = raw.8 & 0xC0
        #expect(version == 0x40)
        #expect(variant == 0x80)
    }

    @Test("Automatic tints come out the same twice")
    func automaticTintsAreStable() throws {
        func tints() throws -> [String: AccountTint] {
            let accounts = [
                try UIFixture.profile("Work"),
                try UIFixture.profile("Personal"),
                try UIFixture.profile("Side project", provider: .codex),
            ]
            let resolved = AccountStyleResolver.styles(for: accounts)
            return Dictionary(uniqueKeysWithValues: accounts.map { ($0.label.value, resolved[$0.id]?.tint ?? .automatic) })
        }
        let first = try tints()
        #expect(try tints() == first)
        #expect(first.count == 3)
        #expect(first.values.allSatisfy { $0 != .automatic })
        // Distinct accounts keep distinct colours, which is what the identity dots are for.
        #expect(Set(first.values).count == 3)
    }

    @Test("An explicit tint is still honoured")
    func explicitTintWins() throws {
        let account = try UIFixture.profile("Work", tint: .indigo, monogram: try AccountMonogram(validating: "WK"))
        let resolved = AccountStyleResolver.styles(for: [account])[account.id]
        #expect(resolved?.tint == .indigo)
        #expect(resolved?.monogram.value == "WK")
        #expect(resolved?.isAutomaticTint == false)
    }
}
