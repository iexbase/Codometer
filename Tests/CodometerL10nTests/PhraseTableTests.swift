import CodometerL10n
import Foundation
import Testing

/// Key English copy, pinned so a change to it is always deliberate. Rows whose phrase is assembled elsewhere
/// (rows 1 and 4) check the part this module provides.
@Suite("Phrase tables")
struct PhraseTableTests {
    private let en = Localizer.testEnglish
    private let ru = Localizer.testRussian
    private let now = Date(timeIntervalSince1970: 1_789_590_000)

    @Test("Row 1: the spoken countdown of a blocked ring")
    func spokenCountdown() {
        let spoken = en.format.durationSpoken(2 * 3_600 + 14 * 60)
        #expect("Limit reached, available again in \(spoken)" == "Limit reached, available again in 2 hours 14 minutes")
        #expect(ru.format.durationSpoken(2 * 3_600 + 14 * 60) == "2 часа 14 минут")
    }

    @Test("Row 4: the header's freshness")
    func updated() {
        #expect(en.format.ago(now.addingTimeInterval(-120), now: now) == "2 min ago")
    }

    @Test("Row 6: window titles")
    func windowTitles() {
        #expect(en.window.session(length: en.window.length(minutes: 300)) == "Session · 5h")
        #expect(en.window.weeklyAllModels == "Weekly · All models")
        #expect(en.window.weekly(model: "Sonnet") == "Weekly · Sonnet")
        #expect(ru.window.session(length: ru.window.length(minutes: 300)) == "Сессия · 5\u{00A0}ч")
        #expect(ru.window.weeklyAllModels == "Неделя · все модели")
        #expect(en.window.length(minutes: 90) == "1h 30m")
        #expect(en.window.length(minutes: 45) == "45m")
        #expect(en.window.length(minutes: 4_320) == "3d")
    }

    @Test("Rows 8–10: resets and pace")
    func resetsAndPace() {
        #expect(en.usage.resetsIn(en.format.durationCompact(2 * 3_600 + 14 * 60)) == "Resets in 2h 14m")
        let tomorrowMorning = now.addingTimeInterval(12 * 3_600 + 40 * 60)
        #expect(en.usage.resets(at: en.format.moment(tomorrowMorning, now: now)) == "Resets tomorrow at 9:00\u{202F}AM")
        #expect(en.usage.runsOut(at: en.format.moment(now.addingTimeInterval(3_600), now: now)) == "At this pace, runs out at 9:20\u{202F}PM")
        #expect(en.usage.spare(en.format.percent(8)) == "8% below pace")
        #expect(en.usage.onPace == "On pace")
        #expect(ru.usage.resetsIn(ru.format.durationCompact(2 * 3_600 + 14 * 60)) == "сброс через 2\u{00A0}ч 14\u{00A0}мин")
    }

    @Test("Rows 12–14: session status and health")
    func sessions() {
        #expect([en.usage.working, en.usage.ready, en.usage.needsApproval, en.usage.needsInput] == ["Working", "Ready", "Needs approval", "Needs input"])
        #expect(en.usage.approvalOrRunning == "Needs approval or running a command")
        #expect(en.usage.quiet(for: en.format.durationShort(12 * 60)) == "No activity for 12 min")
        #expect(en.usage.unusuallyLongTurn == "Unusually long turn")
        #expect([ru.usage.working, ru.usage.ready, ru.usage.needsApproval, ru.usage.needsInput] == ["работает", "готово", "ждёт подтверждения", "ждёт ввода"])
    }

    @Test("Alert summary bodies end with an ellipsis when fragments were left out")
    func summaryBody() {
        #expect(en.alertSummary.body(fragments: ["a", "b"], isTruncated: false) == "a, b")
        #expect(ru.alertSummary.body(fragments: ["a", "b", "c"], isTruncated: true) == "a, b, c, …")
    }

    @Test("Widget ring captions")
    func ringCaptions() {
        #expect([10_080, 1_440, 43_200, 45, 300, 4_320].map(en.widgetFormat.ringCaption) == ["wk", "day", "mo", "45m", "5h", "3d"])
        #expect([10_080, 1_440, 43_800, 45, 300, 4_320].map(ru.widgetFormat.ringCaption) == ["нед", "сут", "мес", "45\u{00A0}мин", "5\u{00A0}ч", "3\u{00A0}дн"])
    }
}
