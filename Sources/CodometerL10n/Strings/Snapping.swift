/// Magnetic snapping and trackpad feedback while a surface is dragged. Shared by the island and the floating card.
public struct SnappingStrings: Sendable {
    let l: Localizer

    public var snapWhileDragging: String { l.pick(en: "Snap while dragging", ru: "Притягивать при перетаскивании") }
    /// The ⌘ hint under the toggle.
    public var snapCaption: String {
        l.pick(
            en: "Pulls to the edges, the corners and the center. Hold ⌘ while dragging to place it exactly.",
            ru: "Притягивает к краям, углам и центру. Удерживайте ⌘ при перетаскивании, чтобы поставить точно."
        )
    }

    public var haptics: String { l.pick(en: "Haptic feedback", ru: "Отклик трекпада") }
    public var hapticsCaption: String {
        l.pick(
            en: "A small tap on the trackpad when the island or the card snaps into place.",
            ru: "Лёгкий щелчок трекпада, когда остров или карточка встают на место."
        )
    }
}

extension Localizer {
    public var snapping: SnappingStrings { SnappingStrings(l: self) }
}
