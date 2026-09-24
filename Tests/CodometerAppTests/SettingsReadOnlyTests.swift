@testable import CodometerApp
import CodometerCore
import Foundation
import Testing

@Suite("Settings read-only and erasing")
struct SettingsReadOnlyTests {
    @Test("Settings are saved only when writable, applied in memory while read-only, and ignored while erasing")
    func plan() {
        #expect(SettingsPersistence.plan(isReadOnly: false, isErasing: false, isDebugFixture: false) == .save)
        #expect(SettingsPersistence.plan(isReadOnly: true, isErasing: false, isDebugFixture: false) == .memoryOnly)
        #expect(SettingsPersistence.plan(isReadOnly: false, isErasing: false, isDebugFixture: true) == .memoryOnly)
        #expect(SettingsPersistence.plan(isReadOnly: false, isErasing: true, isDebugFixture: false) == .skip)
        #expect(SettingsPersistence.plan(isReadOnly: true, isErasing: true, isDebugFixture: true) == .skip)
    }

    @Test("Reset announcements: once per account in a burst, then at most once per account every 30 s")
    func announcementThrottle() {
        var throttle = ResetAnnouncementThrottle()
        let work = AccountID()
        let side = AccountID()
        let start = Date(timeIntervalSince1970: 1_789_600_000)
        #expect(throttle.accountsToAnnounce([work, work, side], now: start) == [work, side])
        #expect(throttle.accountsToAnnounce([work], now: start.addingTimeInterval(29)).isEmpty)
        #expect(throttle.accountsToAnnounce([side, work], now: start.addingTimeInterval(30)) == [side, work])
        // A clock set back never silences announcements.
        #expect(throttle.accountsToAnnounce([work], now: start) == [work])
    }
}
