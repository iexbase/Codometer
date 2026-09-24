/// Limit window titles in the provider's meaning: "Session · 5h", "Weekly · All models", "Weekly · Sonnet".
public struct WindowStrings: Sendable {
    let l: Localizer

    /// The 5-hour session window: "Session · 5h".
    public func session(length: String) -> String { l.pick(en: "Session · \(length)", ru: "Сессия · \(length)") }
    public var weeklyAllModels: String { l.pick(en: "Weekly · All models", ru: "Неделя · все модели") }
    /// A weekly window limited to one model: "Weekly · Sonnet".
    public func weekly(model: String) -> String { l.pick(en: "Weekly · \(model)", ru: "Неделя · \(model)") }
    /// A provider's first window when neither its length nor its label is known.
    public var mainLimit: String { l.pick(en: "Main limit", ru: "Основной лимит") }
    /// Any other window whose length and label are unknown.
    public var extraLimit: String { l.pick(en: "Extra limit", ru: "Доп. лимит") }

    public var weekly: String { l.pick(en: "Weekly", ru: "Неделя") }
    public var daily: String { l.pick(en: "Daily", ru: "Сутки") }
    public var monthly: String { l.pick(en: "Monthly", ru: "Месяц") }

    /// A window length that has no name: `45m`, `5h`, `1h 30m`, `3d` | «45 мин», «5 ч», «1 ч 30 мин», «3 дн».
    public func length(minutes: Int) -> String {
        let minutes = max(0, minutes)
        if minutes < 60 {
            return l.pick(en: "\(minutes)m", ru: "\(minutes)\u{00A0}мин")
        }
        if minutes < 1_440 {
            let hours = minutes / 60
            let rest = minutes % 60
            return rest == 0
                ? l.pick(en: "\(hours)h", ru: "\(hours)\u{00A0}ч")
                : l.pick(en: "\(hours)h \(rest)m", ru: "\(hours)\u{00A0}ч \(rest)\u{00A0}мин")
        }
        let days = Int((Double(minutes) / 1_440).rounded())
        return l.pick(en: "\(days)d", ru: "\(days)\u{00A0}дн")
    }
}

extension Localizer {
    public var window: WindowStrings { WindowStrings(l: self) }
}
