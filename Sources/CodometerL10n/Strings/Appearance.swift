import Foundation

/// Settings → Appearance: glass, what the island shows, ring colours and e-mail privacy.
public struct AppearanceStrings: Sendable {
    let l: Localizer

    /// Under the pane's title.
    public var paneSubtitle: String {
        l.pick(
            en: "The island below shows your real data. Switch backgrounds to check that it stays easy to read.",
            ru: "Ниже — настоящий остров с вашими данными. Меняйте фон и проверяйте, как читается стекло."
        )
    }

    // MARK: Glass

    public var glassTitle: String { l.pick(en: "Glass", ru: "Стекло") }
    public var urgencyGlow: String { l.pick(en: "Tint the glass by usage", ru: "Окрашивать стекло по расходу") }
    public var urgencyGlowSubtitle: String {
        l.pick(
            en: "The glass takes a hint of color from your highest usage, and its rim glows when an agent is waiting for you.",
            ru: "Стекло принимает оттенок самого высокого расхода, а ободок светится, когда агент ждёт вас."
        )
    }

    // MARK: Details — what the island shows

    public var detailsTitle: String { l.pick(en: "Details", ru: "Что показывать") }
    /// The picker for how much the opened island shows.
    public var expandedView: String { l.pick(en: "When it opens", ru: "При раскрытии") }
    public var detailEssentials: String { l.pick(en: "Essentials", ru: "Только главное") }
    public var detailFull: String { l.pick(en: "Everything", ru: "Всё") }
    public var detailEssentialsExplanation: String {
        l.pick(
            en: "Every limit with what’s used, what’s left and when it resets. No chart, sessions or timeline.",
            ru: "Все лимиты: сколько израсходовано, сколько осталось и когда сброс. Без графика, сессий и хронологии."
        )
    }
    public var detailFullExplanation: String {
        l.pick(
            en: "Adds the usage chart, pace, live sessions, the timeline and who used the limit.",
            ru: "Добавляет график расхода, темп, сессии, хронологию и «Кто съел лимит»."
        )
    }
    public var resetTime: String { l.pick(en: "Reset time", ru: "Время сброса") }
    /// The countdown choice, shown as an example: "In 2h 14m", with `format.durationCompact`.
    public func countdownSample(_ countdown: String) -> String {
        l.pick(en: "In \(countdown)", ru: "Через \(countdown)")
    }
    /// The clock choice, shown as an example on its own: "Fri 12:10 PM" | «Пт, 12:10», in the user's clock.
    public func clockSample(_ date: Date) -> String {
        let weekday = date.formatted(
            Date.FormatStyle(locale: l.locale, calendar: l.calendar, timeZone: l.calendar.timeZone).weekday(.abbreviated)
        )
        let time = l.format.clock(date)
        return l.pick(en: "\(weekday) \(time)", ru: "\(weekday), \(time)")
    }
    public var weeklyRings: String { l.pick(en: "Show weekly limits as inner rings", ru: "Показывать недельные лимиты внутренними кольцами") }
    public var pace: String { l.pick(en: "Show pace and run-out forecast", ru: "Показывать темп расхода и прогноз исчерпания") }
    public var forecast: String { l.pick(en: "Forecast at reset", ru: "Прогноз к сбросу") }
    public var forecastSubtitle: String {
        l.pick(
            en: "A faint arc shows where usage will land by the reset if you keep this pace.",
            ru: "Бледная дуга показывает, сколько будет израсходовано к сбросу, если темп не изменится."
        )
    }
    public var resets: String { l.pick(en: "Celebrate limit resets", ru: "Отмечать сброс лимита") }
    public var resetsSubtitle: String {
        l.pick(
            en: "The ring spins back and flashes green when a limit resets.",
            ru: "Когда лимит сбрасывается, кольцо откручивается назад и вспыхивает зелёным."
        )
    }

    // MARK: Ring colors

    public var ringColorsTitle: String { l.pick(en: "Ring colors", ru: "Цвета колец") }
    /// The slider for where yellow starts.
    public var yellowFrom: String { l.pick(en: "Yellow at", ru: "Жёлтый с") }
    /// The slider for where red starts.
    public var redFrom: String { l.pick(en: "Red at", ru: "Красный с") }
    /// A band of the colour legend, with compact percentages: "0–60%".
    public func bandRange(from lower: String, to upper: String) -> String {
        l.pick(en: "\(lower)–\(upper)", ru: "\(lower)–\(upper)")
    }
    /// The last band of the colour legend, with a compact percentage: "85%+".
    public func bandAbove(_ lower: String) -> String {
        l.pick(en: "\(lower)+", ru: "\(lower)+")
    }
    /// VoiceOver for the colour legend, with prose percentages.
    public func bandsA11y(watch: String, critical: String) -> String {
        l.pick(
            en: "Green up to \(watch), yellow up to \(critical), red above that",
            ru: "Зелёный до \(watch), жёлтый до \(critical), дальше красный"
        )
    }
    public var ringColorsFooter: String {
        l.pick(
            en: "Color shows usage only. A limit you’ve reached is always red, and purple is reserved for agents waiting for you.",
            ru: "Цвет показывает только расход. Исчерпанный лимит всегда красный, а фиолетовый — только «ждёт вас»."
        )
    }

    // MARK: Privacy

    public var privacyTitle: String { l.pick(en: "Privacy", ru: "Приватность") }
    public var emailAddress: String { l.pick(en: "Email address", ru: "Адрес почты") }
    public var emailShow: String { l.pick(en: "Show", ru: "Показывать") }
    public var emailMask: String { l.pick(en: "Mask", ru: "Частично скрывать") }
    public var emailHide: String { l.pick(en: "Hide", ru: "Скрывать") }
    /// Before the example address.
    public var emailPreview: String { l.pick(en: "Looks like:", ru: "Так будет видно:") }
    /// VoiceOver for the preview line, with the example as shown.
    public func emailPreviewA11y(_ example: String) -> String {
        l.pick(en: "Looks like: \(example)", ru: "Так будет видно: \(example)")
    }
    /// The example when addresses are hidden.
    public var emailNotShown: String { l.pick(en: "Not shown", ru: "не показывается") }
    public var privacyFooter: String {
        l.pick(
            en: "Applies everywhere: the island, the floating card, the menu bar, Settings, notifications, and the widget. Handy when you share your screen.",
            ru: "Настройка действует везде: на острове, на плавающей карточке, в строке меню, в настройках, уведомлениях и виджете. Удобно при демонстрации экрана."
        )
    }
}

extension Localizer {
    public var appearance: AppearanceStrings { AppearanceStrings(l: self) }
}
