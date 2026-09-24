/// The expanded island: header, pages, group filter, attention queue, window cards and the account page.
/// Captions are lowercase in Russian and sentence case in English, like the `Usage` phrases next to them.
public struct DeckStrings: Sendable {
    let l: Localizer

    // MARK: Header

    public var title: String { l.pick(en: "Limits", ru: "Лимиты") }
    /// "Updated 2 min ago", with `ago` from `format.ago`.
    public func updated(ago: String) -> String { l.pick(en: "Updated \(ago)", ru: "обновлено \(ago)") }
    /// VoiceOver: "Updated 2 minutes ago", with `duration` from `format.durationSpoken`.
    public func updatedA11y(_ duration: String) -> String {
        l.pick(en: "Updated \(duration) ago", ru: "обновлено \(duration) назад")
    }
    /// The header caption while the first reading is on its way.
    public var loadingLimitsCaption: String { l.pick(en: "Loading limits…", ru: "загрузка лимитов…") }
    /// The header caption before any account has reported anything.
    public var waitingForData: String { l.pick(en: "Waiting for data", ru: "ожидание данных") }
    public var refreshAllHelp: String { l.pick(en: "Refresh all", ru: "Обновить всё") }
    public var settingsHelp: String { l.pick(en: "Settings", ru: "Настройки") }
    public var quitHelp: String { l.pick(en: "Quit Codometer", ru: "Выйти из Codometer") }

    // MARK: Pages and filter

    public var overview: String { l.pick(en: "Overview", ru: "Обзор") }
    public var timeline: String { l.pick(en: "Timeline", ru: "Хронология") }
    /// The group filter's first option: every group.
    public var allGroups: String { l.pick(en: "All", ru: "Все") }

    // MARK: Attention

    public var waitingTitle: String { l.pick(en: "Waiting for you", ru: "Ждут вас") }
    /// Under the attention cards: "2 more agents waiting".
    public func moreWaiting(_ count: Int) -> String {
        l.plural(
            count,
            en: ("\(count) more agent waiting", "\(count) more agents waiting"),
            ru: ("и ещё \(count) агент", "и ещё \(count) агента", "и ещё \(count) агентов")
        )
    }
    /// VoiceOver: how long a session has waited, "waiting for 2 minutes", with `duration` from `format.durationSpoken`.
    public func waitingForA11y(_ duration: String) -> String {
        l.pick(en: "waiting for \(duration)", ru: "ждёт уже \(duration)")
    }
    /// VoiceOver hint of an attention card.
    public var showsAccountHint: String { l.pick(en: "Shows this account’s limits", ru: "Показывает лимиты этого аккаунта") }

    // MARK: Account page

    /// Stands in for the headline window until the first reading arrives.
    public var loadingLimits: String { l.pick(en: "Loading limits…", ru: "Загрузка лимитов…") }
    public var refreshing: String { l.pick(en: "Refreshing…", ru: "обновляется…") }
    /// The account's data is out of date: "Updated 20 min ago", with `ago` from `format.ago`.
    public func staleData(ago: String) -> String { l.pick(en: "Updated \(ago)", ru: "обновлено \(ago)") }
    /// VoiceOver after a stale account's update time.
    public var staleDataA11y: String { l.pick(en: "data is out of date", ru: "данные устарели") }
    /// Under the hero numeral: "36% left", with `percent` from `format.percent`.
    public func percentLeft(_ percent: String) -> String { l.pick(en: "\(percent) left", ru: "осталось \(percent)") }
    /// VoiceOver: "38% used", with `percent` from `format.percent`.
    public func usedA11y(_ percent: String) -> String { l.pick(en: "\(percent) used", ru: "использовано \(percent)") }
    /// A tag beside a model bucket whose limit ran out.
    public var limitReachedTag: String { l.pick(en: "Limit reached", ru: "исчерпан") }
    /// The pace pill when "At this pace, runs out …" is too wide beside the numeral: "Runs out tomorrow at 2:10 PM",
    /// with `moment` from `format.moment`. The flame beside it already says the pace is high.
    public func runsOutCompact(at moment: String) -> String {
        l.pick(en: "Runs out \(moment)", ru: "закончится \(moment)")
    }

    /// Width reserved for elapsed times such as "12h 40m" | «12 ч 40 мин»: the widest `format.durationCompact` value
    /// an elapsed time shows in this language.
    public var elapsedTemplate: String { l.pick(en: "00h 00m", ru: "00\u{00A0}ч 00\u{00A0}мин") }
}

extension Localizer {
    public var deck: DeckStrings { DeckStrings(l: self) }
}
