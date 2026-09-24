@testable import CodometerCore
import Foundation
import Testing

@Suite("Account appearance")
struct AccountAppearanceTests {
    private func uuid(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "8C8E4A0E-3B1A-4C7B-9D5E-%012d", index)) ?? UUID()
    }

    private func account(
        _ index: Int,
        provider: ProviderKind = .codex,
        label: String? = nil,
        tint: AccountTint = .automatic,
        monogram: String? = nil
    ) throws -> AccountProfile {
        try AccountProfile(
            id: AccountID(rawValue: uuid(index)),
            provider: provider,
            label: try AccountLabel(validating: label ?? "Account \(index)"),
            directory: try ProfileDirectory(validating: "/tmp/.\(provider.rawValue)-\(index)"),
            tint: tint,
            monogram: try monogram.map { try AccountMonogram(validating: $0) }
        )
    }

    @Test("Valid monograms: letters and digits of any script, uppercased, or one emoji", arguments: [
        ("W", "W"), ("wa", "WA"), (" w ", "W"), ("Л", "Л"), ("жё", "ЖЁ"), ("中", "中"), ("7", "7"), ("a1", "A1"),
        ("🚀", "🚀"), ("🇷🇺", "🇷🇺"), ("e\u{301}", "E\u{301}"), ("ß", "ß"),
    ])
    func validMonograms(raw: String, expected: String) throws {
        #expect(try AccountMonogram(validating: raw).value == expected)
    }

    @Test("Invalid monograms", arguments: [
        ("ABC", ValidationError.tooLong(field: "account.monogram", length: 3, maximum: 2)),
        (" ", .empty(field: "account.monogram")),
        ("", .empty(field: "account.monogram")),
        ("a b", .tooLong(field: "account.monogram", length: 3, maximum: 2)),
        ("a\u{7}", .invalidCharacters(field: "account.monogram")),
        ("🚀🚀🚀", .tooLong(field: "account.monogram", length: 3, maximum: 2)),
        ("🚀🚀", .invalidCharacters(field: "account.monogram")),
        ("A🚀", .invalidCharacters(field: "account.monogram")),
        ("!", .invalidCharacters(field: "account.monogram")),
        ("a.", .invalidCharacters(field: "account.monogram")),
        ("👨‍👩‍👧‍👦", .tooLong(field: "account.monogram", length: 25, maximum: 16)),
    ])
    func invalidMonograms(raw: String, error: ValidationError) {
        #expect(throws: error) { try AccountMonogram(validating: raw) }
    }

    @Test("Automatic monograms skip provider names and fall back to the ordinal", arguments: [
        ("Claude · work", ProviderKind.claude, 1, "W"),
        ("Work account", .claude, 1, "WA"),
        ("Личное", .codex, 1, "Л"),
        ("Claude · личный кабинет", .claude, 2, "ЛК"),
        ("Codex", .codex, 1, "1"),
        ("Codex", .codex, 2, "2"),
        ("Claude Code", .claude, 3, "3"),
        ("codex-personal", .codex, 1, "P"),
        ("🚀", .codex, 0, "1"),
        ("Claude", .claude, 150, "99"),
        ("side project 2", .codex, 1, "SP"),
    ])
    func automaticMonograms(label: String, provider: ProviderKind, ordinal: Int, expected: String) throws {
        let monogram = AccountMonogram.automatic(label: try AccountLabel(validating: label), provider: provider, ordinal: ordinal)
        #expect(monogram.value == expected)
    }

    @Test("FNV-1a over the UUID bytes is stable across runs (pinned values, never Hasher)")
    func stableHash() {
        #expect(AccountStyleResolver.fnv1a(uuid(1)) == 0x28E8_279E_3600_F03B)
        #expect(AccountStyleResolver.fnv1a(uuid(8)) == 0x28E8_1E9E_3600_E0F0)
    }

    @Test("Automatic tints start at the hash entry and never repeat for up to eight accounts")
    func automaticTints() throws {
        let accounts = try (1...8).map { try account($0) }
        let styles = AccountStyleResolver.styles(for: accounts)
        #expect(styles[accounts[0].id]?.tint == .lime)
        #expect(styles[accounts[1].id]?.tint == .slate)
        #expect(styles[accounts[7].id]?.tint == .teal)
        let tints = accounts.compactMap { styles[$0.id]?.tint }
        #expect(tints.count == 8)
        #expect(Set(tints).count == 8)
        #expect(!tints.contains(.automatic))
        #expect(styles.values.allSatisfy { $0.isAutomaticTint })
        #expect(AccountStyleResolver.styles(for: accounts) == styles)
    }

    @Test("Collisions probe forward; beyond eight accounts the hash entry repeats")
    func collisionsAndWrap() throws {
        let first = try account(1)
        let colliding = try account(9)
        let pair = AccountStyleResolver.styles(for: [first, colliding])
        #expect(pair[first.id]?.tint == .lime)
        #expect(pair[colliding.id]?.tint == .pink)

        let nine = try (1...9).map { try account($0) }
        let styles = AccountStyleResolver.styles(for: nine)
        #expect(styles[nine[8].id]?.tint == .lime)
    }

    @Test("Explicit tints are kept, may repeat, and automatic ones avoid them")
    func explicitTints() throws {
        let explicitA = try account(2, tint: .lime)
        let explicitB = try account(3, tint: .lime)
        let automatic = try account(1)
        let styles = AccountStyleResolver.styles(for: [automatic, explicitA, explicitB])
        #expect(styles[explicitA.id]?.tint == .lime)
        #expect(styles[explicitB.id]?.tint == .lime)
        #expect(styles[explicitA.id]?.isAutomaticTint == false)
        #expect(styles[automatic.id]?.tint == .pink)
    }

    @Test("Reordering accounts without collisions keeps every tint")
    func reorderKeepsTints() throws {
        let accounts = try [1, 2, 3].map { try account($0) }
        let forward = AccountStyleResolver.styles(for: accounts)
        let backward = AccountStyleResolver.styles(for: accounts.reversed())
        #expect(forward == backward)
    }

    @Test("Monograms: explicit ones are kept, automatic ones count accounts per provider")
    func resolvedMonograms() throws {
        let claudeOne = try account(1, provider: .claude, label: "Claude")
        let codexOne = try account(2, provider: .codex, label: "Codex")
        let claudeTwo = try account(3, provider: .claude, label: "Claude")
        let explicit = try account(4, provider: .codex, label: "Codex", monogram: "x")
        let styles = AccountStyleResolver.styles(for: [claudeOne, codexOne, claudeTwo, explicit])
        #expect(styles[claudeOne.id]?.monogram.value == "1")
        #expect(styles[codexOne.id]?.monogram.value == "1")
        #expect(styles[claudeTwo.id]?.monogram.value == "2")
        #expect(styles[explicit.id]?.monogram.value == "X")
        #expect(styles[explicit.id]?.isAutomaticMonogram == false)
        #expect(styles[claudeTwo.id]?.isAutomaticMonogram == true)
    }

    @Test("A resolved style never carries the automatic tint")
    func styleRejectsAutomatic() throws {
        let monogram = try AccountMonogram(validating: "W")
        #expect(throws: ValidationError.self) {
            try AccountStyle(tint: .automatic, monogram: monogram, isAutomaticTint: true, isAutomaticMonogram: false)
        }
        #expect(try AccountStyle(tint: .sky, monogram: monogram, isAutomaticTint: false, isAutomaticMonogram: false).tint == .sky)
        #expect(AccountTint.palette.count == 8)
        #expect(Set(AccountTint.palette) == Set(AccountTint.allCases).subtracting([.automatic]))
    }

    @Test("Profiles: old files get automatic styles, an invalid monogram decodes to nil, new keys round-trip")
    func profileCoding() throws {
        let old = #"{"id":"8C8E4A0E-3B1A-4C7B-9D5E-000000000001","provider":"codex","label":"Codex","directory":"/tmp/.codex"}"#
        let decoded = try JSONDecoder().decode(AccountProfile.self, from: Data(old.utf8))
        #expect(decoded.tint == .automatic)
        #expect(decoded.monogram == nil)

        let invalid = #"{"id":"8C8E4A0E-3B1A-4C7B-9D5E-000000000001","provider":"codex","label":"Codex","directory":"/tmp/.codex","monogram":"TOO LONG","tint":"magenta"}"#
        let lenient = try JSONDecoder().decode(AccountProfile.self, from: Data(invalid.utf8))
        #expect(lenient.monogram == nil)
        #expect(lenient.tint == .automatic)

        let styled = try account(5, tint: .indigo, monogram: "🚀")
        let roundTrip = try JSONDecoder().decode(AccountProfile.self, from: try JSONEncoder().encode(styled))
        #expect(roundTrip == styled)
        let object = try #require(try JSONSerialization.jsonObject(with: try JSONEncoder().encode(try account(6))) as? [String: Any])
        #expect(object["tint"] as? String == "automatic")
        #expect(object["monogram"] == nil)
    }

    @Test("updated(tint:monogram:) changes, keeps and removes the style")
    func updatedStyle() throws {
        let profile = try account(1)
        let styled = try profile.updated(tint: .sand, monogram: try AccountMonogram(validating: "Q"))
        #expect(styled.tint == .sand && styled.monogram?.value == "Q")
        let relabeled = try styled.updated(label: try AccountLabel(validating: "Renamed"))
        #expect(relabeled.tint == .sand && relabeled.monogram?.value == "Q")
        let cleared = try styled.updated(tint: .automatic, monogram: .some(nil))
        #expect(cleared.tint == .automatic && cleared.monogram == nil)
    }
}
