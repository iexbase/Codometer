import CodometerCore
import Foundation
import Testing

@Suite("Service status board")
struct ServiceStatusBoardTests {
    private let now = Date(timeIntervalSince1970: 1_789_600_000)

    @Test("Visible only with a problem checked at most 30 minutes ago")
    func visibility() {
        var board = ServiceStatusBoard.empty
        #expect(board.visible(for: .claude, now: now) == nil)
        board.statuses[.claude] = ServiceStatus(provider: .claude, level: .partialOutage, affectedComponents: ["Claude Code"], checkedAt: now.addingTimeInterval(-60))
        board.statuses[.codex] = ServiceStatus(provider: .codex, level: nil, affectedComponents: [], checkedAt: now)
        #expect(board.visible(for: .claude, now: now)?.level == .partialOutage)
        #expect(board.visible(for: .codex, now: now) == nil)
        #expect(board.visible(for: .claude, now: now.addingTimeInterval(29 * 60)) != nil)
        #expect(board.visible(for: .claude, now: now.addingTimeInterval(30 * 60 + 1)) == nil)
        board.lastFailureAt[.codex] = now
        #expect(board.lastFailureAt[.codex] == now)
        #expect(board != .empty)
    }

    @Test("Levels order by severity; components are deduplicated, sanitised and capped at three")
    func levelsAndComponents() {
        #expect(ServiceStatusLevel.allCases.sorted() == [.maintenance, .degraded, .partialOutage, .majorOutage])
        #expect(ServiceStatusLevel.majorOutage > .degraded)
        let status = ServiceStatus(
            provider: .codex,
            level: .degraded,
            affectedComponents: ["CLI", "CLI", "\n", String(repeating: "c", count: 80), "Codex API", "Codex Web"],
            checkedAt: now
        )
        #expect(status.affectedComponents.count == ServiceStatus.maximumComponents)
        #expect(status.affectedComponents.first == "CLI")
        #expect(status.affectedComponents[1].count == ServiceStatus.maximumComponentLength)
    }

    @Test("Status pages are the fixed vendor URLs")
    func statusPages() {
        #expect(ServiceStatus(provider: .claude, level: nil, affectedComponents: [], checkedAt: now).statusPageURL.absoluteString == "https://status.claude.com")
        #expect(ServiceStatus(provider: .codex, level: nil, affectedComponents: [], checkedAt: now).statusPageURL.absoluteString == "https://status.openai.com")
    }
}
