import CodometerClaude
@testable import CodometerEngine
import Foundation
import Testing

/// "Check System" promises a report within `SystemCheck.budget`. `isOverBudget(since:)` guards the profile loop and
/// the history step, but the executable step runs before either of them and is the one that can queue behind another
/// operation, so its own waits have to fit in the budget by construction.
@Suite("Check System budget")
struct SystemCheckBudgetTests {
    @Test("Waiting for the probe gate, reading the version and the history check fit inside the budget")
    func executableStepFitsTheBudget() {
        let gate = Self.seconds(ClaudeUsageProbe.versionGateTimeout)
        let version = Self.seconds(ClaudeUsageProbe.versionTimeout)
        #expect(gate + version + SystemCheck.historyTimeout <= SystemCheck.budget)
    }

    @Test("The gate wait is far shorter than the usage command it can queue behind")
    func gateWaitIsShorterThanTheUsageCommand() {
        // Without the bound, a `/usage` run in flight made the first check wait for the whole of this.
        #expect(ClaudeUsageProbe.versionGateTimeout < ClaudeUsageProbe.timeout)
        #expect(Self.seconds(ClaudeUsageProbe.timeout) > SystemCheck.budget)
        #expect(Self.seconds(ClaudeUsageProbe.versionGateTimeout) > 0)
    }

    private static func seconds(_ duration: Duration) -> TimeInterval {
        let parts = duration.components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}
