import Foundation

/// The live island preview in Settings: its toolbar, hints and the mock desktop around it.
public struct StageStrings: Sendable {
    let l: Localizer

    /// VoiceOver name of the whole preview.
    public var previewA11y: String { l.pick(en: "Island preview", ru: "Предпросмотр острова") }

    // MARK: Hints (one line each at the settings window's minimum width)

    public var hoverHint: String {
        l.pick(en: "Hover over the island to expand it. Drag to move it.", ru: "Наведите курсор, чтобы раскрыть остров. Его можно перетащить.")
    }
    public var clickHint: String {
        l.pick(en: "Click to expand the island, click outside to collapse. Drag to move it.", ru: "Клик раскрывает, клик мимо сворачивает. Остров можно перетащить.")
    }
    public var hoverOrClickHint: String {
        l.pick(en: "Hover to expand the island, click to keep it open. Drag to move it.", ru: "Наведение раскрывает, клик закрепляет. Остров можно перетащить.")
    }

    // MARK: Toolbar

    /// Wallpapers of the mock display. The whole toolbar must fit the narrowest pane (`SettingsPanesCopyTests`).
    public var light: String { l.pick(en: "Light", ru: "Светлый") }
    public var dark: String { l.pick(en: "Dark", ru: "Тёмный") }
    public var colorful: String { l.pick(en: "Colorful", ru: "Яркий") }
    /// Tooltips and VoiceOver names of the wallpaper buttons (own phrases: lowercasing a title depends on the language).
    public var lightHelp: String { l.pick(en: "Preview on a light background", ru: "Предпросмотр на светлом фоне") }
    public var darkHelp: String { l.pick(en: "Preview on a dark background", ru: "Предпросмотр на тёмном фоне") }
    public var colorfulHelp: String { l.pick(en: "Preview on a colorful background", ru: "Предпросмотр на ярком фоне") }
    public var showExpanded: String { l.pick(en: "Show expanded", ru: "Раскрытый вид") }

    // MARK: Mock menu bar

    /// Menus of the mock menu bar, as the Finder shows them in this language.
    public var menuFile: String { l.pick(en: "File", ru: "Файл") }
    public var menuEdit: String { l.pick(en: "Edit", ru: "Правка") }
    public var menuView: String { l.pick(en: "View", ru: "Вид") }
    public var menuWindow: String { l.pick(en: "Window", ru: "Окно") }
    /// The mock menu bar clock: "Thu 12:10 PM" | «Чт 12:10», in the user's clock.
    public func menuBarClock(_ date: Date) -> String {
        let weekday = date.formatted(
            Date.FormatStyle(locale: l.locale, calendar: l.calendar, timeZone: l.calendar.timeZone).weekday(.abbreviated)
        )
        let time = l.format.clock(date)
        return l.pick(en: "\(weekday) \(time)", ru: "\(weekday) \(time)")
    }
}

extension Localizer {
    public var stage: StageStrings { StageStrings(l: self) }
}
