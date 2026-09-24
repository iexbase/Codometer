import CodometerCore
import Foundation
import Testing

@Suite("Validated values")
struct ValidationTests {
    @Test("Percentage accepts 0...1000 and rejects garbage", arguments: [0.0, 42.5, 100, 250, 1_000])
    func percentageAcceptsValidValues(_ value: Double) throws {
        #expect(try Percentage(validating: value).value == value)
    }

    @Test("Percentage rejects NaN, infinity and out-of-range values")
    func percentageRejectsInvalidValues() {
        #expect(throws: ValidationError.notFinite(field: "percentage")) { try Percentage(validating: .nan) }
        #expect(throws: ValidationError.notFinite(field: "percentage")) { try Percentage(validating: .infinity) }
        #expect(throws: ValidationError.outOfRange(field: "percentage", value: -1, lowerBound: 0, upperBound: 1_000)) {
            try Percentage(validating: -1)
        }
        #expect(throws: ValidationError.outOfRange(field: "percentage", value: 1_001, lowerBound: 0, upperBound: 1_000)) {
            try Percentage(validating: 1_001)
        }
    }

    @Test("Percentage derived values")
    func percentageDerivedValues() throws {
        let overdrawn = try Percentage(validating: 130)
        #expect(overdrawn.isExhausted)
        #expect(overdrawn.clampedFraction == 1)
        #expect(overdrawn.remaining == 0)
        let partial = try Percentage(validating: 25)
        #expect(partial.fraction == 0.25)
        #expect(partial.remaining == 75)
        #expect(!partial.isExhausted)
    }

    @Test("Decoding re-validates values")
    func decodingRevalidates() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([Percentage].self, from: Data("[-5]".utf8))
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([PollInterval].self, from: Data("[5]".utf8))
        }
    }

    @Test("Account labels are trimmed and bounded")
    func accountLabel() throws {
        #expect(try AccountLabel(validating: "  Work  ").value == "Work")
        #expect(throws: ValidationError.empty(field: "account.label")) { try AccountLabel(validating: "   ") }
        #expect(throws: ValidationError.tooLong(field: "account.label", length: 41, maximum: 40)) {
            try AccountLabel(validating: String(repeating: "a", count: 41))
        }
        #expect(throws: ValidationError.invalidCharacters(field: "account.label")) {
            try AccountLabel(validating: "bad\u{0007}label")
        }
    }

    @Test("Profile directories must be absolute and are standardised")
    func profileDirectory() throws {
        #expect(try ProfileDirectory(validating: "/Users/me/.claude-work/").path == "/Users/me/.claude-work")
        #expect(try ProfileDirectory(validating: "/Users/me/x/../.codex").path == "/Users/me/.codex")
        #expect(throws: ValidationError.notAbsolutePath(field: "account.directory")) {
            try ProfileDirectory(validating: "relative/path")
        }
        #expect(throws: ValidationError.empty(field: "account.directory")) { try ProfileDirectory(validating: "") }
    }

    @Test("Poll interval and window duration bounds")
    func bounds() throws {
        #expect(throws: ValidationError.self) { try PollInterval(seconds: 59) }
        #expect(throws: ValidationError.self) { try PollInterval(seconds: 3_601) }
        #expect(try PollInterval(seconds: 60).seconds == 60)
        #expect(throws: ValidationError.self) { try WindowDuration(minutes: 0) }
        #expect(try WindowDuration(minutes: 10_080) == .oneWeek)
    }

    @Test("Stable identifiers allow only safe characters")
    func stableIdentifier() throws {
        #expect(try StableIdentifier.validate("codex_bengalfox", field: "id") == "codex_bengalfox")
        #expect(try StableIdentifier.validate("week.fable-5", field: "id") == "week.fable-5")
        #expect(throws: ValidationError.invalidCharacters(field: "id")) { try StableIdentifier.validate("a b", field: "id") }
        #expect(throws: ValidationError.empty(field: "id")) { try StableIdentifier.validate("", field: "id") }
    }

    @Test("Display text is sanitised and truncated")
    func displayText() {
        #expect(DisplayText.sanitize("  hi\n", maximumLength: 10) == "hi")
        #expect(DisplayText.sanitize("\u{0000}\u{0001}", maximumLength: 10) == nil)
        #expect(DisplayText.sanitize("abcdefghijk", maximumLength: 5) == "abcd…")
    }
}

@Suite("Accounts and settings")
struct SettingsModelTests {
    private func account(_ provider: ProviderKind, _ path: String, interval: Int? = nil) throws -> AccountProfile {
        try AccountProfile(
            provider: provider,
            label: try AccountLabel(validating: provider.rawValue),
            directory: try ProfileDirectory(validating: path),
            pollInterval: try interval.map { try PollInterval(seconds: $0) }
        )
    }

    @Test("Each provider enforces its minimum poll interval")
    func minimumPollInterval() throws {
        #expect(throws: ValidationError.self) { try account(.claude, "/tmp/.claude", interval: 60) }
        #expect(try account(.codex, "/tmp/.codex", interval: 60).pollInterval.seconds == 60)
        #expect(try account(.claude, "/tmp/.claude").pollInterval == ProviderKind.claude.defaultPollInterval)
    }

    @Test("Settings reject duplicate profiles")
    func duplicateProfiles() throws {
        let first = try account(.claude, "/tmp/.claude")
        let same = try account(.claude, "/tmp/.claude")
        #expect(throws: ValidationError.duplicate(field: "accounts.directory", value: "/tmp/.claude")) {
            try AppSettings(accounts: [first, same])
        }
        // The same directory for a different provider is a different profile.
        #expect(try AppSettings(accounts: [first, try account(.codex, "/tmp/.claude")]).accounts.count == 2)
    }

    @Test("Settings round-trip through JSON")
    func roundTrip() throws {
        var settings = try AppSettings(accounts: [try account(.claude, "/tmp/.claude"), try account(.codex, "/tmp/.codex")])
        settings.appearance.edge = .right
        settings.appearance.offset = try EdgeOffset(0.25)
        settings.appearance.style = .floating
        settings.appearance.surface = .darkGlass
        settings.appearance.scale = try IslandScale(1.25)
        settings.alerts.thresholds = try AlertThresholds([try Percentage(validating: 90), try Percentage(validating: 50)])
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(decoded == settings)
        #expect(decoded.alerts.thresholds.values.map(\.value) == [50, 90])
    }

    @Test("Missing sections fall back to defaults; newer schema versions decode their known keys")
    func decodingDefaultsAndVersions() throws {
        let minimal = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"schemaVersion":1}"#.utf8))
        #expect(minimal.accounts.isEmpty)
        #expect(minimal.appearance == AppearanceSettings())
        // A newer file is not refused any more: it loads read-only (SettingsRepairTests, SettingsStoreOutcomeTests).
        let newer = try AppSettings.decodeFile(Data(#"{"schemaVersion":99,"appearance":{"edge":"left"}}"#.utf8))
        #expect(newer.isReadOnly)
        #expect(newer.settings.appearance.edge == .left)
    }

    @Test("Band thresholds must be ordered")
    func bandThresholds() throws {
        #expect(throws: ValidationError.self) {
            try BandThresholds(watch: try Percentage(validating: 80), critical: try Percentage(validating: 50))
        }
        let bands = try BandThresholds(watch: try Percentage(validating: 50), critical: try Percentage(validating: 80))
        #expect(UsageBand(used: try Percentage(validating: 49.9), thresholds: bands) == .ample)
        #expect(UsageBand(used: try Percentage(validating: 50), thresholds: bands) == .watch)
        #expect(UsageBand(used: try Percentage(validating: 80), thresholds: bands) == .critical)
        #expect(UsageBand(used: try Percentage(validating: 100), thresholds: bands) == .exhausted)
    }

    @Test("Alert thresholds are unique, sorted and bounded")
    func alertThresholds() throws {
        let fifty = try Percentage(validating: 50)
        #expect(throws: ValidationError.self) { try AlertThresholds([fifty, fifty]) }
        #expect(throws: ValidationError.self) { try AlertThresholds([try Percentage(validating: 0.5)]) }
        let thresholds = try AlertThresholds([try Percentage(validating: 100), fifty, try Percentage(validating: 80)])
        #expect(thresholds.highestCrossed(from: try Percentage(validating: 40), to: try Percentage(validating: 85))?.value == 80)
        #expect(thresholds.highestCrossed(from: try Percentage(validating: 85), to: try Percentage(validating: 90)) == nil)
    }
}
