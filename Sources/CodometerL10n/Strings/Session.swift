import Foundation

/// An account's live sessions in the expanded island, and their VoiceOver text.
public struct SessionStrings: Sendable {
    let l: Localizer

    public var title: String { l.pick(en: "Sessions", ru: "Сессии") }

    /// Under the session list: "2 more sessions".
    public func more(_ count: Int) -> String {
        l.plural(
            count,
            en: ("\(count) more session", "\(count) more sessions"),
            ru: ("и ещё \(count) сессия", "и ещё \(count) сессии", "и ещё \(count) сессий")
        )
    }

    /// VoiceOver: "last turn 4 minutes 12 seconds", with `length` from `spokenPrecise`.
    public func lastTurnA11y(_ length: String) -> String {
        l.pick(en: "last turn \(length)", ru: "последний ход \(length)")
    }

    /// VoiceOver: "first token in 2.8 seconds", with `latency` from `spokenLatency`.
    public func firstTokenA11y(_ latency: String) -> String {
        l.pick(en: "first token in \(latency)", ru: "первый токен через \(latency)")
    }

    /// The Codex hedge ("Needs approval or running a command") where a line is too narrow for it, as in an attention
    /// card beside the waiting time.
    public var approvalOrRunningCompact: String {
        l.pick(en: "Waiting or running a command", ru: "ждёт или выполняет команду")
    }

    // MARK: Spoken durations

    /// `format.durationPrecise` in words, for VoiceOver: "38 seconds", "4 minutes 12 seconds", "1 hour 5 minutes" |
    /// «4 минуты 12 секунд». Each unit comes from the system's wide style; units are joined with a space, like
    /// `format.durationSpoken`. A candidate for `Formats`.
    public func spokenPrecise(_ seconds: TimeInterval) -> String {
        let clamped = seconds.isFinite ? min(max(seconds, 0), Self.maximumSeconds) : 0
        let total = max(1, Int(clamped.rounded()))
        let units: [(count: Int, unit: Duration.UnitsFormatStyle.Unit, seconds: Int64)] = if total < 60 {
            [(total, .seconds, 1)]
        } else if total < 3_600 {
            [(total / 60, .minutes, 60), (total % 60, .seconds, 1)]
        } else {
            [(total / 3_600, .hours, 3_600), ((total % 3_600) / 60, .minutes, 60)]
        }
        return units
            .filter { $0.count > 0 }
            .map { part in
                let style = Duration.UnitsFormatStyle(allowedUnits: [part.unit], width: .wide).locale(l.locale)
                return Duration.seconds(Int64(part.count) * part.seconds).formatted(style)
            }
            .joined(separator: " ")
    }

    /// `format.latency` in words, for VoiceOver: "2.8 seconds", "1 second", "less than 0.1 seconds" |
    /// «2,8 секунды»; ten seconds and more as `spokenPrecise`. A candidate for `Formats`.
    public func spokenLatency(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds < 9.95 else { return spokenPrecise(seconds) }
        guard seconds >= 0.05 else {
            let tenth = l.format.decimal(0.1)
            return l.pick(en: "less than \(tenth) seconds", ru: "меньше \(tenth) секунды")
        }
        let tenths = (seconds * 10).rounded() / 10
        let style = Measurement<UnitDuration>.FormatStyle(
            width: .wide,
            locale: l.locale,
            numberFormatStyle: .number.precision(.fractionLength(0...1))
        )
        return Measurement(value: tenths, unit: UnitDuration.seconds).formatted(style)
    }

    private static let maximumSeconds: TimeInterval = 100 * 365 * 86_400
}

extension Localizer {
    public var session: SessionStrings { SessionStrings(l: self) }
}
