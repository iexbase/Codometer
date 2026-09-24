import CodometerCore
@testable import CodometerEngine
import Foundation
import Testing

@Suite("Monitor reconciliation")
struct MonitorReconciliationTests {
    private func profile(id: AccountID, label: String = "Claude", poll: Int? = nil, group: AccountGroupID? = nil) throws -> AccountProfile {
        try AccountProfile(
            id: id,
            provider: .claude,
            label: try AccountLabel(validating: label),
            directory: try ProfileDirectory(validating: "/Users/me/.claude"),
            pollInterval: try poll.map { try PollInterval(seconds: $0) },
            groupID: group
        )
    }

    @Test("Moving or renaming an account keeps its monitor; real profile changes restart it")
    func restarts() throws {
        let id = AccountID()
        let base = try profile(id: id)
        #expect(!TrackerEngine.needsNewMonitor(wanted: base, monitored: base))
        #expect(!TrackerEngine.needsNewMonitor(wanted: try profile(id: id, group: AccountGroupID()), monitored: base))
        #expect(TrackerEngine.needsNewMonitor(wanted: try profile(id: id, poll: 900), monitored: base))
        // Monitors never use the label (MonitorIdentity), so renaming keeps the monitor running.
        #expect(!TrackerEngine.needsNewMonitor(wanted: try profile(id: id, label: "Claude · work"), monitored: base))
        #expect(TrackerEngine.needsNewMonitor(wanted: nil, monitored: base))
        #expect(TrackerEngine.needsNewMonitor(wanted: base, monitored: nil))
        #expect(!TrackerEngine.needsNewMonitor(wanted: nil, monitored: nil))
    }
}
