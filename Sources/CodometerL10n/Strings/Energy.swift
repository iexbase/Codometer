/// Settings → General → Energy: how hard Codometer works when the Mac is on battery, low or hot.
///
/// The state line under the picker is always there, whatever the conditions, so switching modes never changes the
/// section's height. Every line is measured in both languages by `GeneralSnapshotTests`.
public struct EnergyStrings: Sendable {
    let l: Localizer

    public var title: String { l.pick(en: "Energy", ru: "Энергопотребление") }
    /// Names the picker for VoiceOver.
    public var mode: String { l.pick(en: "Refresh pace", ru: "Темп обновлений") }

    public var modeAutomatic: String { l.pick(en: "Automatic", ru: "Автоматически") }
    /// Russian names the mode by what it does to the battery, next to «Беречь заряд», and fits the segmented control.
    public var modeAlwaysFresh: String { l.pick(en: "Always fresh", ru: "Не экономить") }
    public var modeSaveBattery: String { l.pick(en: "Save battery", ru: "Беречь заряд") }

    // MARK: The live state line

    /// Nothing is slowing refreshes down.
    public var stateNormal: String {
        l.pick(en: "Refreshing at the usual pace.", ru: "Обновления идут в обычном темпе.")
    }
    public var stateBattery: String {
        l.pick(en: "On battery, so refreshing a bit less often.", ru: "Работа от батареи — обновления чуть реже.")
    }
    public var stateLowBattery: String {
        l.pick(en: "Battery is low, so refreshing less often.", ru: "Заряд на исходе — обновления реже.")
    }
    /// The exact factor is in Diagnostics; this line only says that the OS asked for less work.
    public var stateLowPower: String {
        l.pick(
            en: "Low Power Mode is on, so refreshing less often and pausing animations.",
            ru: "Включён режим энергосбережения: обновления реже, анимация не показывается."
        )
    }
    public var stateThermal: String {
        l.pick(en: "Your Mac is running hot, so refreshing less often.", ru: "Mac сильно нагрелся — обновления реже.")
    }
    /// The user chose "Save battery" and nothing else slows refreshes down further.
    public var stateSaver: String {
        l.pick(en: "Saving battery, so refreshing less often.", ru: "Включён режим «Беречь заряд» — обновления реже.")
    }
    /// Under the picker, above the live state line.
    public var footer: String {
        l.pick(
            en: "Automatic slows refreshes down on battery, in Low Power Mode and when your Mac gets hot. Always fresh keeps the usual pace, except when macOS asks for less.",
            ru: "«Автоматически» замедляет обновления от батареи, в режиме энергосбережения и при нагреве. «Не экономить» держит обычный темп, кроме случаев, когда об этом просит macOS."
        )
    }
}

extension Localizer {
    public var energy: EnergyStrings { EnergyStrings(l: self) }
}
