/// Usage, resets, pace, agent activity and session health. Captions are lowercase in Russian and sentence case in
/// English; fragments that sit inside other text ("just now") stay lowercase in both.
public struct UsageStrings: Sendable {
    let l: Localizer

    /// "64% used · 36% left", with both percentages already formatted.
    public func usedAndLeft(used: String, left: String) -> String {
        l.pick(en: "\(used) used · \(left) left", ru: "использовано \(used) · осталось \(left)")
    }

    // MARK: Resets

    /// The reset time has passed and the next reading has not arrived yet.
    public var resetting: String { l.pick(en: "Resetting…", ru: "сбрасывается…") }
    /// "Resets in 2h 14m".
    public func resetsIn(_ countdown: String) -> String { l.pick(en: "Resets in \(countdown)", ru: "сброс через \(countdown)") }
    /// "Resets tomorrow at 9:00 AM", with `moment` from `format.moment`.
    public func resets(at moment: String) -> String { l.pick(en: "Resets \(moment)", ru: "сброс \(moment)") }
    /// VoiceOver, once when an account's limit resets: "Work: limit reset".
    public func limitResetAnnouncement(account: String) -> String {
        l.pick(en: "\(account): limit reset", ru: "\(account): лимит сброшен")
    }

    // MARK: Pace

    /// "At this pace, runs out at 6:40 PM", with `moment` from `format.moment`.
    public func runsOut(at moment: String) -> String {
        l.pick(en: "At this pace, runs out \(moment)", ru: "при таком темпе закончится \(moment)")
    }
    /// "12% ahead of pace", with a formatted percentage.
    public func aheadOfPace(_ percent: String) -> String {
        l.pick(en: "\(percent) ahead of pace", ru: "опережает темп на \(percent)")
    }
    /// "8% below pace", with a formatted percentage: how far today's usage is under the even-pace line, the
    /// mirror of `aheadOfPace`. Not a forecast: what usage reaches by the reset is the ghost arc's number
    /// (`motion.forecastA11y`), which is a different figure.
    public func spare(_ percent: String) -> String {
        l.pick(en: "\(percent) below pace", ru: "отстаёт от темпа на \(percent)")
    }
    public var onPace: String { l.pick(en: "On pace", ru: "расход в темпе") }

    // MARK: Agents

    public var working: String { l.pick(en: "Working", ru: "работает") }
    public var ready: String { l.pick(en: "Ready", ru: "готово") }
    public var needsApproval: String { l.pick(en: "Needs approval", ru: "ждёт подтверждения") }
    public var needsInput: String { l.pick(en: "Needs input", ru: "ждёт ввода") }
    public var waitingForYou: String { l.pick(en: "Waiting for you", ru: "ждёт вас") }
    /// A Codex permission prompt that may already be approved: Codex logs no approval event.
    public var approvalOrRunning: String {
        l.pick(en: "Needs approval or running a command", ru: "ждёт подтверждения или выполняет команду")
    }

    /// "4m 12s turn", with `length` from `format.durationPrecise`.
    public func turn(_ length: String) -> String { l.pick(en: "\(length) turn", ru: "ход \(length)") }
    /// "first token in 2.8s", with `latency` from `format.latency`.
    public func firstToken(_ latency: String) -> String { l.pick(en: "first token in \(latency)", ru: "первый токен \(latency)") }
    /// The turn was stopped before it finished.
    public var interrupted: String { l.pick(en: "interrupted", ru: "прерван") }

    /// "No activity for 12 min", with `duration` from `format.durationShort`.
    public func quiet(for duration: String) -> String { l.pick(en: "No activity for \(duration)", ru: "нет активности \(duration)") }
    public var unusuallyLongTurn: String { l.pick(en: "Unusually long turn", ru: "необычно долгий ход") }
    /// "Waiting over 10 min".
    public func waitingOver(_ duration: String) -> String { l.pick(en: "Waiting over \(duration)", ru: "ждёт больше \(duration)") }
    /// "Waiting 12 min": how long a session has waited so far.
    public func waiting(for duration: String) -> String { l.pick(en: "Waiting \(duration)", ru: "ждёт \(duration)") }

    /// A session without a project folder, named by the end of its id: "Session 3f9a1c".
    public func unnamedSession(_ idSuffix: String) -> String { l.pick(en: "Session \(idSuffix)", ru: "сессия \(idSuffix)") }

    // MARK: Refresh and credits

    /// "Next refresh in 3 min".
    public func nextRefresh(in duration: String) -> String {
        l.pick(en: "Next refresh in \(duration)", ru: "обновление через \(duration)")
    }
    /// The next refresh is due.
    public var nextRefreshNow: String { l.pick(en: "Refreshing soon", ru: "скоро обновление") }

    public var creditsUnlimited: String { l.pick(en: "Credits: unlimited", ru: "Кредиты: без ограничений") }
    /// "Credits: 12.5".
    public func credits(_ balance: String) -> String { l.pick(en: "Credits: \(balance)", ru: "Кредиты: \(balance)") }
}

extension Localizer {
    public var usage: UsageStrings { UsageStrings(l: self) }
}
