import CodometerCore
@testable import CodometerEngine
import Foundation
import Testing

@Suite("Monitor identity")
struct MonitorIdentityTests {
    private let id = AccountID()

    private func profile(
        provider: ProviderKind = .claude,
        label: String = "Work",
        directory: String = "/Users/example/.claude",
        isEnabled: Bool = true,
        poll: Int? = nil,
        group: AccountGroupID? = nil,
        tint: AccountTint = .automatic,
        monogram: String? = nil
    ) throws -> AccountProfile {
        try AccountProfile(
            id: id,
            provider: provider,
            label: try AccountLabel(validating: label),
            directory: try ProfileDirectory(validating: directory),
            isEnabled: isEnabled,
            pollInterval: try poll.map { try PollInterval(seconds: $0) },
            groupID: group,
            tint: tint,
            monogram: try monogram.map { try AccountMonogram(validating: $0) }
        )
    }

    @Test("Tint, monogram, label and group edits never restart a monitor")
    func cosmeticEdits() throws {
        let base = try profile()
        for edited in [
            try profile(tint: .teal),
            try profile(monogram: "W"),
            try profile(label: "Personal"),
            try profile(group: AccountGroupID()),
            try profile(label: "Side project", group: AccountGroupID(), tint: .pink, monogram: "SP"),
        ] {
            #expect(MonitorIdentity(edited) == MonitorIdentity(base))
            #expect(!TrackerEngine.needsNewMonitor(wanted: edited, monitored: base))
        }
    }

    @Test("Provider, directory, enabled state and poll interval restart a monitor")
    func realChanges() throws {
        let base = try profile()
        for changed in [
            try profile(provider: .codex),
            try profile(directory: "/Users/example/.claude-work"),
            try profile(isEnabled: false),
            try profile(poll: 900),
        ] {
            #expect(MonitorIdentity(changed) != MonitorIdentity(base))
            #expect(TrackerEngine.needsNewMonitor(wanted: changed, monitored: base))
        }
    }

    @Test("Adding or removing an account starts or stops its monitor")
    func presence() throws {
        let base = try profile()
        #expect(TrackerEngine.needsNewMonitor(wanted: nil, monitored: base))
        #expect(TrackerEngine.needsNewMonitor(wanted: base, monitored: nil))
        #expect(!TrackerEngine.needsNewMonitor(wanted: nil, monitored: nil))
    }
}
