/// Settings → Presentation: where the island sits, what opens it, its style and behaviour.
public struct PlacementStrings: Sendable {
    let l: Localizer

    /// Under the pane's title, while the island is the chosen style.
    public var paneSubtitle: String {
        l.pick(
            en: "Drag the island on the screen below or right on your desktop. It snaps to the nearest edge.",
            ru: "Перетащите остров на экране ниже или прямо на рабочем столе — он прилипнет к краю."
        )
    }

    /// The same line for the floating card; both reserve the same room, so switching never moves the pane.
    public var cardPaneSubtitle: String {
        l.pick(
            en: "Drag the card right on your desktop. It snaps to the corners, the edges and the center.",
            ru: "Перетащите карточку прямо на рабочем столе — она притянется к углам, краям и центру."
        )
    }

    // MARK: Edges

    public var top: String { l.pick(en: "Top", ru: "Сверху") }
    public var bottom: String { l.pick(en: "Bottom", ru: "Снизу") }
    public var left: String { l.pick(en: "Left", ru: "Слева") }
    public var right: String { l.pick(en: "Right", ru: "Справа") }
    /// VoiceOver for the edge buttons.
    public var moveToTopA11y: String { l.pick(en: "Move to the top edge", ru: "Переместить к верхнему краю") }
    public var moveToBottomA11y: String { l.pick(en: "Move to the bottom edge", ru: "Переместить к нижнему краю") }
    public var moveToLeftA11y: String { l.pick(en: "Move to the left edge", ru: "Переместить к левому краю") }
    public var moveToRightA11y: String { l.pick(en: "Move to the right edge", ru: "Переместить к правому краю") }
    /// The button that centres the island on its edge.
    public var center: String { l.pick(en: "Center", ru: "По центру") }
    public var centerHint: String { l.pick(en: "Centers the island along its edge", ru: "Ставит остров посередине края") }

    // MARK: Interaction

    public var interactionTitle: String { l.pick(en: "Interaction", ru: "Управление") }
    /// The open-trigger picker.
    public var expandOn: String { l.pick(en: "Expand on", ru: "Раскрывать") }
    public var hover: String { l.pick(en: "Hover", ru: "Наведение") }
    public var click: String { l.pick(en: "Click", ru: "Клик") }
    public var hoverOrClick: String { l.pick(en: "Hover or click", ru: "Наведение или клик") }
    /// One of these sits under the picker in a two-line space, so each must fit two lines at the narrowest pane.
    public var hoverExplanation: String {
        l.pick(
            en: "Expands when the pointer rests on the island and collapses when it leaves.",
            ru: "Раскрывается, когда курсор задерживается на острове, и сворачивается, когда уходит."
        )
    }
    public var clickExplanation: String {
        l.pick(
            en: "Expands on click and stays open until you click elsewhere or press Esc.",
            ru: "Раскрывается по клику и остаётся раскрытым, пока вы не кликнете в другом месте или не нажмёте Esc."
        )
    }
    public var hoverOrClickExplanation: String {
        l.pick(
            en: "Hovering expands the island; a click keeps it open until you click elsewhere or press Esc.",
            ru: "Наведение раскрывает остров, а клик оставляет его раскрытым, пока вы не кликнете в другом месте или не нажмёте Esc."
        )
    }
    public var interactionFooter: String {
        l.pick(
            en: "You can drag the island in any mode. Control-click it for a menu, or double-click it to open Settings.",
            ru: "Перетаскивание работает в любом режиме. Нажатие правой кнопкой открывает меню, двойное — настройки."
        )
    }

    // MARK: Shape and material

    public var shapeTitle: String { l.pick(en: "Shape and material", ru: "Форма и материал") }
    public var style: String { l.pick(en: "Style", ru: "Стиль") }
    public var attached: String { l.pick(en: "Attached to edge", ru: "Прилегает к краю") }
    public var floating: String { l.pick(en: "Detached", ru: "Парящий") }
    public var surface: String { l.pick(en: "Surface", ru: "Поверхность") }
    public var liquidGlass: String { l.pick(en: "Liquid Glass", ru: "Liquid Glass") }
    public var darkGlass: String { l.pick(en: "Dark glass", ru: "Тёмное стекло") }
    public var black: String { l.pick(en: "Black", ru: "Чёрный") }
    public var size: String { l.pick(en: "Size", ru: "Размер") }

    // MARK: Behavior

    public var behaviorTitle: String { l.pick(en: "Behavior", ru: "Поведение") }
    public var showIsland: String { l.pick(en: "Show the island", ru: "Показывать остров") }
    /// The same row while the floating card is the chosen style; one setting, named after the surface it is about.
    public var showCard: String { l.pick(en: "Show the card", ru: "Показывать карточку") }
    /// Under whichever of the two rows is shown. It names no surface, so both share it.
    public var showIslandSubtitle: String {
        l.pick(en: "When this is off, limits appear only in the menu bar.", ru: "Если выключить, лимиты будут видны только в строке меню.")
    }
    public var hideInFullScreen: String { l.pick(en: "Hide in full-screen apps", ru: "Скрывать в полноэкранных приложениях") }
}

extension Localizer {
    public var placement: PlacementStrings { PlacementStrings(l: self) }
}
