import Foundation

/// The history chart, the session timeline and the attribution list: captions, placeholders, chart labels and
/// VoiceOver summaries. The short formats they share (ranges, coverage notes, agent counts) are in `AnalyticsFormat`.
public struct AnalyticsStrings: Sendable {
    let l: Localizer

    // MARK: History chart

    /// The chart's placeholder while too little history exists.
    public var collectingHistory: String { l.pick(en: "Collecting history…", ru: "сбор истории…") }

    /// Swift Charts value labels, read by chart descriptors.
    public var chartTime: String { l.pick(en: "Time", ru: "Время") }
    public var chartUsed: String { l.pick(en: "Used", ru: "Использовано") }
    public var chartEvenPace: String { l.pick(en: "Even pace", ru: "Ровный темп") }
    public var chartProjection: String { l.pick(en: "Projection", ru: "Прогноз") }
    public var chartNow: String { l.pick(en: "Now", ru: "Сейчас") }
    public var chartReset: String { l.pick(en: "Reset", ru: "Сброс") }
    public var chartZero: String { l.pick(en: "Zero", ru: "Ноль") }
    public var chartLimit: String { l.pick(en: "Limit", ru: "Лимит") }
    public var chartSeries: String { l.pick(en: "Series", ru: "Ряд") }

    /// VoiceOver: "Usage history: 57% now, 12% ahead of pace, runs out at 4:40 PM", with `details` joined by ", ".
    public func historyA11y(_ details: String) -> String {
        l.pick(en: "Usage history: \(details)", ru: "История расхода: \(details)")
    }
    public var historyCollectingA11y: String {
        l.pick(en: "Usage history: still collecting data", ru: "История расхода: данные ещё собираются")
    }
    /// "57% now", with `percent` from `format.percent`.
    public func nowA11y(_ percent: String) -> String { l.pick(en: "\(percent) now", ru: "сейчас \(percent)") }
    /// "12% ahead of pace", with `percent` from `format.percent`.
    public func aheadOfPaceA11y(_ percent: String) -> String {
        l.pick(en: "\(percent) ahead of pace", ru: "опережает темп на \(percent)")
    }
    /// "8% below pace", with `percent` from `format.percent`; the same figure as `usage.spare`.
    public func spareA11y(_ percent: String) -> String { l.pick(en: "\(percent) below pace", ru: "отстаёт от темпа на \(percent)") }
    public var onPaceA11y: String { l.pick(en: "on pace", ru: "в темпе") }
    /// "runs out at 4:40 PM", with `moment` from `format.moment`.
    public func runsOutA11y(_ moment: String) -> String { l.pick(en: "runs out \(moment)", ru: "закончится \(moment)") }

    // MARK: Timeline

    /// The caption above the limit's current value, beside the usage curve.
    public var limitCaption: String { l.pick(en: "Limit", ru: "лимит") }
    public var noSessionsInPeriod: String { l.pick(en: "No sessions in this period", ru: "нет сессий за этот период") }
    /// The usage curve before its first stored observation, named like the chart's "Usage history".
    public var noLimitHistory: String { l.pick(en: "No usage history", ru: "нет истории расхода") }
    /// The timeline before its first snapshot.
    public var timelineEmpty: String { l.pick(en: "Nothing to show yet", ru: "хронология пока пуста") }
    /// Under the lane titles: "2 more" sessions did not fit.
    public func moreLanes(_ count: Int) -> String { l.pick(en: "\(count) more", ru: "ещё \(count)") }

    // MARK: Gaps in the timeline

    /// Drawn across a stretch the app did not record, when the label fits. Brand names stay as they are, and the
    /// other phrases are lower case in Russian like the timeline's other drawn captions.
    public var gapAppNotRunning: String { l.pick(en: "Codometer wasn’t running", ru: "Codometer не был запущен") }
    public var gapMacAsleep: String { l.pick(en: "Mac was asleep", ru: "Mac спал") }
    public var gapAccountOff: String { l.pick(en: "Account was off", ru: "аккаунт был выключен") }
    /// A gap whose reason is unknown, and the form the tooltip uses for every gap.
    public var gapNoData: String { l.pick(en: "No data", ru: "нет данных") }

    /// The short forms, drawn in a gap too narrow for the full phrase.
    public var gapAppNotRunningShort: String { l.pick(en: "Not running", ru: "не запущен") }
    public var gapMacAsleepShort: String { l.pick(en: "Asleep", ru: "спал") }
    public var gapAccountOffShort: String { l.pick(en: "Account off", ru: "выключен") }

    /// VoiceOver: "Timeline: 3 sessions, working for 2 hours 10 minutes, …", with `details` joined by ", ".
    public func timelineA11y(_ details: String) -> String { l.pick(en: "Timeline: \(details)", ru: "Хронология: \(details)") }
    /// "2 gaps in the data" | «2 пропуска в данных», the last part of the timeline's VoiceOver summary.
    public func gapsA11y(_ count: Int) -> String {
        l.plural(
            count,
            en: ("\(count) gap in the data", "\(count) gaps in the data"),
            ru: ("\(count) пропуск в данных", "\(count) пропуска в данных", "\(count) пропусков в данных")
        )
    }
    public var timelineNoDataA11y: String { l.pick(en: "Timeline: no data", ru: "Хронология: нет данных") }
    /// "no sessions", "1 session", "3 sessions" | «нет сессий», «1 сессия», «3 сессии».
    public func sessions(_ count: Int) -> String {
        guard count > 0 else { return l.pick(en: "no sessions", ru: "нет сессий") }
        return l.plural(count, en: ("\(count) session", "\(count) sessions"), ru: ("\(count) сессия", "\(count) сессии", "\(count) сессий"))
    }
    /// "working for 2 hours", with `duration` from `format.durationSpoken`.
    public func workingA11y(_ duration: String) -> String { l.pick(en: "working for \(duration)", ru: "в работе \(duration)") }
    /// "waiting for 12 minutes", with `duration` from `format.durationSpoken`.
    public func waitingA11y(_ duration: String) -> String { l.pick(en: "waiting for \(duration)", ru: "в ожидании \(duration)") }
    /// "41% of the limit used", with `percent` from `format.percent`.
    public func limitUsedA11y(_ percent: String) -> String {
        l.pick(en: "\(percent) of the limit used", ru: "использовано \(percent) лимита")
    }

    // MARK: Attribution

    public var whatsEatingLimit: String { l.pick(en: "What’s eating your limit", ru: "Кто съел лимит") }
    public var noTokenData: String { l.pick(en: "No token data for this period", ru: "нет данных о токенах за этот период") }
    /// The header note when token data covers the whole period.
    public var estimatedFromTokens: String { l.pick(en: "Estimated from tokens", ru: "оценка по токенам") }
    /// Width reserved for a row's value: wider than any `format.approxPercent` or `format.percent` value up to 100
    /// in this language.
    public var valueTemplate: String { l.pick(en: "≈00.0%", ru: "≈00,0\u{00A0}%") }

    /// VoiceOver for estimated percentage points, instead of `≈`: "about 3.2%", "about 12%", "less than 0.1%" |
    /// «около 3,2 %».
    public func pointsA11y(_ points: Double) -> String {
        guard points.isFinite, points >= 0.05 else {
            let tenth = percent(0.1, fractionDigits: 1)
            return l.pick(en: "less than \(tenth)", ru: "меньше \(tenth)")
        }
        let value = percent(min(points, 100_000), fractionDigits: points >= 9.95 ? 0 : 1)
        return l.pick(en: "about \(value)", ru: "около \(value)")
    }

    private func percent(_ points: Double, fractionDigits: Int) -> String {
        let style = FloatingPointFormatStyle<Double>.Percent(locale: l.locale)
            .precision(.fractionLength(fractionDigits))
            .rounded(rule: .toNearestOrAwayFromZero)
        return (points / 100).formatted(style)
    }
}

extension Localizer {
    public var analytics: AnalyticsStrings { AnalyticsStrings(l: self) }
}
