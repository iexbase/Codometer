/// Banners on an account's page: a limit that ran out and a refresh that failed.
public struct BannerStrings: Sendable {
    let l: Localizer

    public var limitReached: String { l.pick(en: "Limit reached", ru: "Лимит исчерпан") }
    /// "Limit reached · Weekly · All models", with the window's title.
    public func limitReached(window: String) -> String {
        l.pick(en: "Limit reached · \(window)", ru: "Лимит исчерпан · \(window)")
    }
    public var resetTimeUnknown: String { l.pick(en: "Reset time unknown", ru: "время сброса неизвестно") }
    /// "Back in 3d 4h", with `countdown` from `format.durationCompact`.
    public func backIn(_ countdown: String) -> String {
        l.pick(en: "Back in \(countdown)", ru: "доступ вернётся через \(countdown)")
    }
    /// VoiceOver: "Available again in 3 days 4 hours", with `duration` from `format.durationSpoken`.
    public func backInA11y(_ duration: String) -> String {
        l.pick(en: "Available again in \(duration)", ru: "снова доступен через \(duration)")
    }
    /// The tooltip of the failed refresh banner's button.
    public var refreshAccountHelp: String { l.pick(en: "Refresh this account", ru: "Обновить этот аккаунт") }
}

extension Localizer {
    public var banner: BannerStrings { BannerStrings(l: self) }
}
