/// Short texts the widget snapshot carries: ring captions and why an account has no fresh numbers.
public struct WidgetFormatStrings: Sendable {
    let l: Localizer

    /// A window's length inside a small ring: `wk`, `day`, `mo`, `45m`, `5h`, `3d` | «нед», «сут», «мес», «45 мин».
    public func ringCaption(minutes: Int) -> String {
        switch minutes {
        case 10_080:
            return l.pick(en: "wk", ru: "нед")
        case 1_440:
            return l.pick(en: "day", ru: "сут")
        case 43_200, 43_800, 44_640:
            return l.pick(en: "mo", ru: "мес")
        case ..<60:
            let value = max(0, minutes)
            return l.pick(en: "\(value)m", ru: "\(value)\u{00A0}мин")
        case ..<1_440:
            let hours = Int((Double(minutes) / 60).rounded())
            return l.pick(en: "\(hours)h", ru: "\(hours)\u{00A0}ч")
        default:
            let days = Int((Double(minutes) / 1_440).rounded())
            return l.pick(en: "\(days)d", ru: "\(days)\u{00A0}дн")
        }
    }

    // MARK: Notices

    public var cliMissing: String { l.pick(en: "CLI not found", ru: "CLI не найден") }
    public var cliUntrusted: String { l.pick(en: "CLI signature check failed", ru: "подпись CLI неверна") }
    public var signedOut: String { l.pick(en: "Not signed in", ru: "вы не вошли") }
    public var unfamiliarData: String { l.pick(en: "Unfamiliar data format", ru: "незнакомый формат") }
    public var refreshFailed: String { l.pick(en: "Couldn’t refresh", ru: "ошибка обновления") }
    public var notResponding: String { l.pick(en: "Not responding", ru: "нет ответа") }
    public var profileFolderMissing: String { l.pick(en: "Profile folder not found", ru: "нет папки профиля") }
    public var offline: String { l.pick(en: "Offline", ru: "нет сети") }
}

extension Localizer {
    public var widgetFormat: WidgetFormatStrings { WidgetFormatStrings(l: self) }
}
