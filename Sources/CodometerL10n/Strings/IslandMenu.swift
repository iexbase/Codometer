/// The island's context menu beyond the shared `Menu` items (Title Case in English). Group names in the "Show"
/// submenu are user data and never translated.
public struct IslandMenuStrings: Sendable {
    let l: Localizer

    // MARK: Show ▸

    /// The submenu that filters the island to one group of accounts.
    public var show: String { l.pick(en: "Show", ru: "Показывать") }
    public var allAccounts: String { l.pick(en: "All Accounts", ru: "Все аккаунты") }

    // MARK: Expand ▸

    /// The submenu that picks how the island expands.
    public var expand: String { l.pick(en: "Expand", ru: "Раскрывать") }
    public var onHover: String { l.pick(en: "On Hover", ru: "При наведении") }
    public var onClick: String { l.pick(en: "On Click", ru: "По клику") }
    public var onHoverOrClick: String { l.pick(en: "On Hover or Click", ru: "При наведении или по клику") }

    // MARK: Placement ▸

    /// The submenu with the screen edges and the island's shape.
    public var placement: String { l.pick(en: "Placement", ru: "Расположение") }
    public var top: String { l.pick(en: "Top", ru: "Сверху") }
    public var bottom: String { l.pick(en: "Bottom", ru: "Снизу") }
    public var left: String { l.pick(en: "Left", ru: "Слева") }
    public var right: String { l.pick(en: "Right", ru: "Справа") }
    /// The island grows out of the screen edge.
    public var attachedToEdge: String { l.pick(en: "Attached to Edge", ru: "Прилегает к краю") }
    /// The island floats a little away from the edge.
    public var floating: String { l.pick(en: "Detached", ru: "Парящий") }

    // MARK: Presentation and displays

    /// Replaces the island with the floating card.
    public var switchToFloatingCard: String { l.pick(en: "Switch to Floating Card", ru: "Переключиться на плавающую карточку") }
}

extension Localizer {
    public var islandMenu: IslandMenuStrings { IslandMenuStrings(l: self) }
}
