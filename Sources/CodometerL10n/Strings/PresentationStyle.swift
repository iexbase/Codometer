/// Settings → Presentation: the two ways Codometer can show usage on screen.
public struct PresentationStyleStrings: Sendable {
    let l: Localizer

    /// The label of the three-tile picker.
    public var showUsageAs: String { l.pick(en: "Show usage as", ru: "Показывать лимиты как") }

    public var island: String { l.pick(en: "Island", ru: "Остров") }
    public var floatingCard: String { l.pick(en: "Floating card", ru: "Плавающая карточка") }
    public var strip: String { l.pick(en: "Strip", ru: "Полоса") }
    public var stripDescription: String {
        l.pick(
            en: "A wide bar you can move anywhere: what’s left, and every limit side by side.",
            ru: "Широкая полоса, которую можно двигать: сколько осталось и все лимиты в ряд."
        )
    }
    public var stripA11y: String { l.pick(en: "Strip presentation", ru: "Представление «полоса»") }

    /// A short line under each tile; all fit the same three-line space, so switching never changes the height.
    public var islandDescription: String {
        l.pick(
            en: "A tab at the edge of the screen that expands when you need it.",
            ru: "Вкладка у края экрана, которая раскрывается, когда нужно."
        )
    }
    public var floatingCardDescription: String {
        l.pick(
            en: "A small window you can put anywhere and minimize when you’re busy.",
            ru: "Небольшое окно: поставьте его куда угодно и сверните, когда не нужно."
        )
    }

    /// VoiceOver names of the tiles (the description becomes the hint).
    public var islandA11y: String { l.pick(en: "Island presentation", ru: "Представление «остров»") }
    public var floatingCardA11y: String { l.pick(en: "Floating card presentation", ru: "Представление «плавающая карточка»") }

    /// Footnote under the picker.
    public var footnote: String {
        l.pick(
            en: "Only one of them is on screen at a time. The menu bar icon stays either way.",
            ru: "На экране всегда что-то одно. Значок в строке меню остаётся в любом случае."
        )
    }
}

extension Localizer {
    public var presentationStyle: PresentationStyleStrings { PresentationStyleStrings(l: self) }
}
