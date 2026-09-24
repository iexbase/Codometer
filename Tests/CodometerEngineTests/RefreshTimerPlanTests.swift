import CodometerCore
@testable import CodometerEngine
import Foundation
import Testing

@Suite("Refresh timer re-arming")
struct RefreshTimerPlanTests {
    private let now = Date(timeIntervalSince1970: 1_789_600_000)

    @Test("Nothing armed means nothing to move")
    func nothingArmed() {
        #expect(RefreshTimerPlan.rearm(armedAt: nil, lastRefreshAt: now, newDelay: 60, now: now) == nil)
    }

    @Test("A smaller delay brings the refresh forward")
    func decreaseMovesEarlier() {
        let lastRefresh = now.addingTimeInterval(-60)
        let armed = now.addingTimeInterval(540)
        let moved = RefreshTimerPlan.rearm(armedAt: armed, lastRefreshAt: lastRefresh, newDelay: 300, now: now)
        // last refresh + 300 s is 240 s from now, which is earlier than the armed 540 s and saves 300 s.
        #expect(moved == now.addingTimeInterval(240))
    }

    @Test("A re-armed refresh never fires sooner than the minimum lead")
    func minimumLead() {
        let lastRefresh = now.addingTimeInterval(-3_000)
        let armed = now.addingTimeInterval(600)
        let moved = RefreshTimerPlan.rearm(armedAt: armed, lastRefreshAt: lastRefresh, newDelay: 300, now: now)
        #expect(moved == now.addingTimeInterval(RefreshTimerPlan.minimumLead))
    }

    @Test("A larger delay keeps the armed timer")
    func increaseKeepsDeadline() {
        let lastRefresh = now.addingTimeInterval(-60)
        let armed = now.addingTimeInterval(240)
        #expect(RefreshTimerPlan.rearm(armedAt: armed, lastRefreshAt: lastRefresh, newDelay: 900, now: now) == nil)
    }

    @Test("A move that saves less than half a minute is not worth it")
    func smallSavingIgnored() {
        let lastRefresh = now.addingTimeInterval(-60)
        let armed = now.addingTimeInterval(300)
        // last refresh + 340 s is 280 s from now: only 20 s earlier.
        #expect(RefreshTimerPlan.rearm(armedAt: armed, lastRefreshAt: lastRefresh, newDelay: 340, now: now) == nil)
        // 60 s earlier is worth the move.
        #expect(RefreshTimerPlan.rearm(armedAt: armed, lastRefreshAt: lastRefresh, newDelay: 300, now: now) != nil)
    }

    @Test("Without a recorded refresh the new delay counts from now")
    func noLastRefresh() {
        let armed = now.addingTimeInterval(1_800)
        #expect(RefreshTimerPlan.rearm(armedAt: armed, lastRefreshAt: nil, newDelay: 300, now: now) == now.addingTimeInterval(300))
        #expect(RefreshTimerPlan.rearm(armedAt: armed, lastRefreshAt: nil, newDelay: 1_800, now: now) == nil)
    }
}
