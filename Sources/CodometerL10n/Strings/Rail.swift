/// The island at rest: VoiceOver text for its dials and the attention tab.
public struct RailStrings: Sendable {
    let l: Localizer

    /// The rail without accounts shows only a gauge glyph.
    public var noAccountsA11y: String { l.pick(en: "No accounts", ru: "Нет аккаунтов") }

    /// A dial's usage, spoken after the account's name: "57% used", with `percent` from `format.percent`.
    public func usedA11y(_ percent: String) -> String { l.pick(en: "\(percent) used", ru: "использовано \(percent)") }

    /// A blocked account: "Limit reached, available again in 2 hours 14 minutes", with `duration` from
    /// `format.durationSpoken`.
    public func limitReachedA11y(backIn duration: String) -> String {
        l.pick(en: "Limit reached, available again in \(duration)", ru: "Лимит исчерпан, снова доступен через \(duration)")
    }

    /// The attention tab's tooltip and VoiceOver label: "3 agents are waiting for you".
    public func waiting(_ count: Int) -> String {
        l.plural(
            count,
            en: ("\(count) agent is waiting for you", "\(count) agents are waiting for you"),
            ru: ("Вас ждёт \(count) агент", "Вас ждут \(count) агента", "Вас ждут \(count) агентов")
        )
    }
}

extension Localizer {
    public var rail: RailStrings { RailStrings(l: self) }
}
