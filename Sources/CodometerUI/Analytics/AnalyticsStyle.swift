import CodometerCore
import CodometerL10n
import SwiftUI

/// What the analytics views need to colour data like the rest of the island, beyond their fixed initialisers.
///
/// The deck sets it once for the selected account: `.environment(\.analyticsStyle, AnalyticsStyle(provider:bands:))`.
/// Without it, work is drawn in a neutral tone and bands use the standard thresholds.
public struct AnalyticsStyle: Hashable, Sendable {
    /// The account's provider; its accent colours working time and attribution bars.
    public var provider: ProviderKind?
    /// The user's band thresholds, so usage curves take the same colour as the rings.
    public var bands: BandThresholds

    public init(provider: ProviderKind? = nil, bands: BandThresholds = .standard) {
        self.provider = provider
        self.bands = bands
    }

    /// The provider accent, or a neutral tone when the provider is unknown.
    var accent: Color {
        provider.map(Theme.accent(for:)) ?? Color.primary.opacity(0.55)
    }

    func band(for used: Double) -> UsageBand {
        let clamped = min(max(used.isFinite ? used : 0, 0), Percentage.upperSanityBound)
        let percentage = (try? Percentage(validating: clamped)) ?? .zero
        return UsageBand(used: percentage, thresholds: bands)
    }
}

extension EnvironmentValues {
    /// Provider and band thresholds for the analytics views; see `AnalyticsStyle`.
    @Entry public var analyticsStyle = AnalyticsStyle()
}

/// Short texts shared by the analytics views, in the language and time zone of `l10n`.
enum AnalyticsText {
    /// The time of day in the user's clock: "2:32 PM" | «14:32».
    static func clock(_ date: Date, l10n: Localizer) -> String {
        l10n.format.clock(date)
    }

    /// "Mon" | «пн» for the date's weekday.
    static func weekday(_ date: Date, l10n: Localizer) -> String {
        l10n.format.weekdayShort(date)
    }

    /// A past moment: the time on the day of `now`, weekday and time within the last six days ("Mon 2:32 PM" |
    /// «пн 14:32»), day, month and time before that ("09/10 2:32 PM" | «10.09 14:32»).
    static func moment(_ date: Date, now: Date, l10n: Localizer) -> String {
        let time = clock(date, l10n: l10n)
        if l10n.calendar.isDate(date, inSameDayAs: now) {
            return time
        }
        if now.timeIntervalSince(date) < 6 * 86_400 {
            return "\(weekday(date, l10n: l10n)) \(time)"
        }
        return "\(l10n.analyticsFormat.dayMonth(date)) \(time)"
    }

    /// "Data since 2:20 PM" when data only starts after `intervalStart`, else `nil`.
    ///
    /// A minute of slack keeps a coverage that starts together with the interval from reading as partial.
    static func coverageNote(coverageStart: Date?, intervalStart: Date, now: Date, l10n: Localizer) -> String? {
        guard let coverageStart, coverageStart.timeIntervalSince(intervalStart) > 60 else { return nil }
        return l10n.analyticsFormat.dataSince(moment(coverageStart, now: now, l10n: l10n))
    }

    /// "Since 2:20 PM": the short form for the timeline's tick row, where the dashed coverage boundary sits right above it.
    static func coverageShortNote(coverageStart: Date, now: Date, l10n: Localizer) -> String {
        l10n.analyticsFormat.since(moment(coverageStart, now: now, l10n: l10n))
    }

    /// "1 agent", "2 agents", "no agents" | «1 агент», «2 агента», «нет агентов».
    static func agents(_ count: Int, l10n: Localizer) -> String {
        l10n.analyticsFormat.agents(count)
    }

    /// "41%" | «41 %», "<1%" for a tiny non-zero value, "0%".
    static func percent(_ value: Double, l10n: Localizer) -> String {
        l10n.format.percent(value)
    }

    /// What a gap in the timeline says: "Mac was asleep" | «Mac спал».
    static func gapLabel(_ reason: CollectionGap.Reason, l10n: Localizer) -> String {
        let text = l10n.analytics
        switch reason {
        case .appNotRunning: return text.gapAppNotRunning
        case .macAsleep: return text.gapMacAsleep
        case .accountOff: return text.gapAccountOff
        case .unknown: return text.gapNoData
        }
    }

    /// The short form for a gap too narrow for `gapLabel`: "Asleep" | «спал». Unknown gaps have no shorter form,
    /// so they keep "No data".
    static func gapShortLabel(_ reason: CollectionGap.Reason, l10n: Localizer) -> String {
        let text = l10n.analytics
        switch reason {
        case .appNotRunning: return text.gapAppNotRunningShort
        case .macAsleep: return text.gapMacAsleepShort
        case .accountOff: return text.gapAccountOffShort
        case .unknown: return text.gapNoData
        }
    }

    /// The tooltip's second part inside a gap: "no data (Mac was asleep)" | «нет данных (Mac спал)»; plain
    /// "no data" when the reason is unknown, since naming it would only repeat the phrase.
    static func gapTooltip(_ reason: CollectionGap.Reason, l10n: Localizer) -> String {
        guard reason != .unknown else { return l10n.analyticsFormat.noData }
        return l10n.analyticsFormat.noDataBecause(gapLabel(reason, l10n: l10n))
    }
}
