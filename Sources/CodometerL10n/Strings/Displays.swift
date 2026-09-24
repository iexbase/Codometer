/// Choosing the display a surface lives on. Display names come from macOS and are never translated.
public struct DisplaysStrings: Sendable {
    let l: Localizer

    public var display: String { l.pick(en: "Display", ru: "Экран") }
    public var displayCaption: String {
        l.pick(
            en: "Which display the island appears on when more than one is connected.",
            ru: "На каком экране показывать остров, когда их подключено несколько."
        )
    }

    /// Follows the display the surface was last dropped on (the default).
    public var whereLeft: String { l.pick(en: "Where I leave it", ru: "Где оставлю") }
    /// The display with the menu bar.
    public var mainDisplay: String { l.pick(en: "Main display", ru: "Основной экран") }

    /// A saved display that is not plugged in right now.
    public func notConnected(_ name: String) -> String {
        l.pick(en: "\(name) (not connected)", ru: "\(name) (не подключён)")
    }

    /// A display macOS gives no name for.
    public var unnamedDisplay: String { l.pick(en: "Unnamed display", ru: "Экран без имени") }

    /// The island's context menu (Title Case in English).
    public var moveToDisplay: String { l.pick(en: "Move to Display", ru: "Переместить на экран") }
}

extension Localizer {
    public var displays: DisplaysStrings { DisplaysStrings(l: self) }
}
