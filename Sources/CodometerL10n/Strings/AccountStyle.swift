/// An account's identity mark: the monogram and the colour it wears on badges, dots and the floating card.
///
/// Colour here says *which account*, never how much is left, so the names are plain colour names.
public struct AccountStyleStrings: Sendable {
    let l: Localizer

    /// The account editor's section for monogram and colour.
    public var section: String { l.pick(en: "Look", ru: "Оформление") }

    // MARK: Monogram

    public var monogram: String { l.pick(en: "Monogram", ru: "Монограмма") }
    /// Under the monogram field, explaining what an empty field does.
    public var monogramFooter: String {
        l.pick(
            en: "One or two letters, digits or an emoji. Leave it empty and Codometer takes it from the name.",
            ru: "Одна-две буквы, цифры или эмодзи. Оставьте поле пустым — монограмма возьмётся из названия."
        )
    }
    /// Shown while the typed monogram cannot be used.
    public var monogramInvalid: String {
        l.pick(en: "Use one or two letters, digits or an emoji.", ru: "Подойдут одна-две буквы, цифры или эмодзи.")
    }
    /// VoiceOver value of the monogram field while it follows the account's name: "Automatic: W".
    public func monogramAutomaticA11y(_ monogram: String) -> String {
        l.pick(en: "Automatic: \(monogram)", ru: "Авто: \(monogram)")
    }

    // MARK: Colour

    public var color: String { l.pick(en: "Color", ru: "Цвет") }
    /// The swatch that lets Codometer pick a free colour.
    public var automatic: String { l.pick(en: "Automatic", ru: "Авто") }
    /// VoiceOver label of a colour swatch: "Teal".
    public var teal: String { l.pick(en: "Teal", ru: "Бирюзовый") }
    public var sky: String { l.pick(en: "Sky", ru: "Небесный") }
    public var indigo: String { l.pick(en: "Indigo", ru: "Индиго") }
    public var lime: String { l.pick(en: "Lime", ru: "Лаймовый") }
    public var pink: String { l.pick(en: "Pink", ru: "Розовый") }
    public var sand: String { l.pick(en: "Sand", ru: "Песочный") }
    public var slate: String { l.pick(en: "Slate", ru: "Сланцевый") }
    public var graphite: String { l.pick(en: "Graphite", ru: "Графитовый") }
    /// Under the swatches: where an account's colour shows up.
    public var colorFooter: String {
        l.pick(
            en: "The color marks the account on badges and dots. Ring colors always show usage.",
            ru: "Цвет отмечает аккаунт на значках и точках. Кольца всегда окрашены по расходу."
        )
    }
}

extension Localizer {
    public var accountStyle: AccountStyleStrings { AccountStyleStrings(l: self) }
}
