/// The ring's live grammar: what the forecast ghost and a just-celebrated reset say out loud.
///
/// The ghost arc and the green flash are drawn, so VoiceOver needs words for them; both are appended to a dial's
/// usage, after `rail.usedA11y`.
public struct MotionStrings: Sendable {
    let l: Localizer

    /// The forecast ghost, after the usage it extends: "at this pace about 92% by reset", with `projected` from
    /// `format.percent`.
    public func forecastA11y(_ projected: String) -> String {
        l.pick(
            en: "at this pace about \(projected) by reset",
            ru: "при таком темпе к сбросу около \(projected)"
        )
    }

    /// The forecast when it runs into the limit before the window ends.
    public var forecastRunsOutA11y: String {
        l.pick(
            en: "at this pace it runs out before the reset",
            ru: "при таком темпе лимит кончится до сброса"
        )
    }

    /// A ring celebrating a reset, so the green flash is not the only sign of it.
    public var justResetA11y: String { l.pick(en: "just reset", ru: "только что сброшен") }
}

extension Localizer {
    public var motion: MotionStrings { MotionStrings(l: self) }
}
