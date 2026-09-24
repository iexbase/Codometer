/// Fusing the island with a MacBook's camera notch.
public struct NotchStrings: Sendable {
    let l: Localizer

    public var blendWithNotch: String { l.pick(en: "Blend with the camera notch", ru: "Сливаться с вырезом камеры") }
    /// Under the toggle: the trade-off is worth saying out loud.
    public var blendCaption: String {
        l.pick(
            en: "Centered on the top edge, the island wraps around the notch and turns solid black, whatever surface you picked.",
            ru: "В центре верхнего края остров расходится вокруг выреза и становится чёрным, какую бы поверхность вы ни выбрали."
        )
    }

    /// The "+N" chip that stands for accounts the wings have no room for.
    public func overflow(_ count: Int) -> String {
        "+\(max(0, count))"
    }

    /// VoiceOver for that chip.
    public func overflowA11y(_ count: Int) -> String {
        l.plural(
            count,
            en: ("\(count) more account", "\(count) more accounts"),
            ru: ("ещё \(count) аккаунт", "ещё \(count) аккаунта", "ещё \(count) аккаунтов")
        )
    }

    public var overflowHint: String { l.pick(en: "Expands the island", ru: "Раскрывает остров") }
}

extension Localizer {
    public var notch: NotchStrings { NotchStrings(l: self) }
}
