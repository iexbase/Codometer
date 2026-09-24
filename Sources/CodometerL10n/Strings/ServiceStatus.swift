/// Vendor service status: the chip in the expanded island and the popover, and the card's status pill.
///
/// Two forms of every level: `level` starts a chip or a line of its own, `levelInSentence` sits inside the tooltip.
/// Russian is sentence case everywhere, so only the first letter differs there.
public struct ServiceStatusStrings: Sendable {
    let l: Localizer

    // MARK: Levels

    /// The chip's word for `maintenance`.
    public var maintenance: String { l.pick(en: "Maintenance", ru: "Техработы") }
    /// The chip's word for `degraded`.
    public var degraded: String { l.pick(en: "Slowdown", ru: "Замедление") }
    /// The chip's word for `partialOutage`.
    public var partialOutage: String { l.pick(en: "Partial outage", ru: "Частичный сбой") }
    /// The chip's word for `majorOutage`.
    public var majorOutage: String { l.pick(en: "Major outage", ru: "Серьёзный сбой") }

    /// `maintenance` inside a sentence.
    public var maintenanceInSentence: String { l.pick(en: "maintenance", ru: "техработы") }
    /// `degraded` inside a sentence.
    public var degradedInSentence: String { l.pick(en: "slowdown", ru: "замедление") }
    /// `partialOutage` inside a sentence.
    public var partialOutageInSentence: String { l.pick(en: "partial outage", ru: "частичный сбой") }
    /// `majorOutage` inside a sentence.
    public var majorOutageInSentence: String { l.pick(en: "major outage", ru: "серьёзный сбой") }

    // MARK: Chip

    /// The chip: the vendor and what is wrong, "Claude · Partial outage".
    public func chip(vendor: String, level: String) -> String {
        l.pick(en: "\(vendor) · \(level)", ru: "\(vendor) · \(level)")
    }

    /// The widest chip the header reserves room for, so a status appearing never moves the buttons.
    /// Measured per language, not translated word for word.
    public var chipTemplate: String { l.pick(en: "Claude · Partial outage", ru: "Claude · Серьёзный сбой") }

    /// The chip's tooltip: "Claude Code: partial outage — from status.claude.com, checked 3 min ago",
    /// with `components` from the status page, `level` in sentence form and `ago` from `format.ago`.
    public func tooltip(components: String, level: String, host: String, ago: String) -> String {
        l.pick(
            en: "\(components): \(level) — from \(host), checked \(ago)",
            ru: "\(components): \(level) — по данным \(host), проверено \(ago)"
        )
    }

    /// VoiceOver on the chip: "Service status: Claude Code, partial outage", with `duration` from
    /// `format.durationSpoken` for how long ago it was checked.
    public func chipA11y(components: String, level: String, duration: String) -> String {
        l.pick(
            en: "Service status: \(components), \(level), checked \(duration) ago",
            ru: "Статус сервиса: \(components), \(level), проверено \(duration) назад"
        )
    }

    /// VoiceOver hint on the chip.
    public var opensStatusPage: String { l.pick(en: "Opens the vendor’s status page", ru: "Открывает страницу статуса сервиса") }
}

extension Localizer {
    public var serviceStatus: ServiceStatusStrings { ServiceStatusStrings(l: self) }
}
