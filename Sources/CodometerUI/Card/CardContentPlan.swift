import CodometerCore
import CodometerL10n
import Foundation

/// Everything the expanded card draws for one account, worked out once per render from data the app already has.
///
/// Pure and `Equatable`, so the tiles, the status pill and the footer can be checked without a renderer, and so the
/// views never decide anything themselves.
public struct CardContentPlan: Equatable, Sendable {
    /// How a value is coloured. Colour is never the only signal: every tone carries words too.
    public enum Tone: Equatable, Sendable {
        case primary
        case secondary
        case band(UsageBand)
        case success
        case attention
    }

    /// One of the three tiles under the hero.
    public struct Tile: Equatable, Sendable, Identifiable {
        public enum Kind: String, Equatable, Sendable {
            case reset, pace, third
        }

        public let kind: Kind
        public let systemImage: String
        public let value: String
        public let label: String
        public let tone: Tone
        /// What VoiceOver reads instead of the compact value ("Resets in 5 days 16 hours").
        public let accessibilityText: String

        public var id: String { kind.rawValue }
    }

    /// One reason the status pill could show, most important first.
    public enum PillKind: Int, Equatable, Sendable, Comparable, CaseIterable {
        case waiting
        case majorOutage
        case partialOutage
        case limitReached
        case justReset
        case degraded
        case maintenance
        case stale

        public static func < (lhs: PillKind, rhs: PillKind) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public struct StatusPill: Equatable, Sendable {
        public let kind: PillKind
        public let text: String
        public let tone: Tone
        /// Every current item, not only the winner.
        public let tooltip: String
        /// Set for a vendor pill: a click opens that vendor's public status page.
        public let statusPageProvider: ProviderKind?
    }

    public struct Hero: Equatable, Sendable {
        /// The window that limits the account (`HeadlineWindows.binding`).
        public let caption: String
        /// "64%".
        public let figure: String
        /// "used".
        public let unit: String
        public let band: UsageBand
        public let fraction: Double
        /// Where usage lands by the reset at this pace, 0…1; `nil` when there is nothing to project.
        public let forecastFraction: Double?
        public let accessibilityText: String
    }

    public let accountLabel: String
    /// The vendor plan, normalised for display ("MAX 20X"); `nil` when the provider reports none.
    public let plan: String?
    public let hero: Hero?
    public let tiles: [Tile]
    public let pill: StatusPill?
    /// "Work · Claude" or the e-mail, per `EmailVisibility`.
    public let identity: String
    /// "updated 14:32" or "updating…".
    public let updated: String
    /// What the Strip size draws; planned only when the caller asks for a scope.
    public let strip: CardStripPlan?

    /// The longest plan chip the header draws; longer ones are dropped rather than truncated.
    public static let maximumPlanLength = 12

    /// - Parameters:
    ///   - stripScope: Plans the strip over `scopePresentations` when set; the other sizes leave it `nil`.
    ///   - scopePresentations: Every account the card may show, in settings order (`presentation` is among them).
    ///   - chipCapacity: How many chips the strip fits.
    public init(
        presentation: AccountPresentation,
        settings: AppSettings,
        thirdTile: CardThirdTile,
        serviceStatus: ServiceStatusBoard,
        ceremonies: CeremonyBoard,
        now: Date,
        l10n: Localizer,
        stripScope: CardStripScope? = nil,
        scopePresentations: [AccountPresentation] = [],
        chipCapacity: Int = CardMetrics.stripChipCapacity
    ) {
        let appearance = settings.appearance
        accountLabel = presentation.status.profile.label.value
        plan = Self.planChip(presentation.status.identity?.plan)
        hero = Self.makeHero(presentation: presentation, l10n: l10n)
        let strip = stripScope.flatMap { scope in
            CardStripPlan.make(
                scope: scope,
                selected: presentation,
                accounts: scopePresentations.isEmpty ? [presentation] : scopePresentations,
                capacity: chipCapacity,
                now: now,
                l10n: l10n
            )
        }
        self.strip = strip
        tiles = Self.makeTiles(
            presentation: presentation,
            resetTextStyle: appearance.resetTextStyle,
            thirdTile: thirdTile,
            now: now,
            l10n: l10n
        )
        // A strip that merges several accounts reports on all of them: the most important reason among them and the
        // oldest reading, so a limit reached on an account outside its scope never shows, and one inside never hides.
        let scoped: [AccountPresentation] = if let strip, !strip.header.isSelectedAccount {
            scopePresentations.filter { strip.accountIDs.contains($0.id) }
        } else {
            [presentation]
        }
        pill = scoped
            .compactMap { Self.makePill(presentation: $0, serviceStatus: serviceStatus, ceremonies: ceremonies, now: now, l10n: l10n) }
            .min { $0.kind < $1.kind }
        identity = Self.identityText(presentation: presentation, l10n: l10n)
        updated = Self.updatedText(presentations: scoped, now: now, l10n: l10n)
    }

    // MARK: - Header

    /// "max_20x" → "MAX 20X"; too long or empty → nothing.
    static func planChip(_ plan: String?) -> String? {
        guard let plan else { return nil }
        let clean = plan.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= maximumPlanLength else { return nil }
        return clean.uppercased()
    }

    // MARK: - Hero

    private static func makeHero(presentation: AccountPresentation, l10n: Localizer) -> Hero? {
        guard let headline = presentation.headline else { return nil }
        let binding = headline.binding
        let window = presentation.windows.first { $0.isMainBucket && $0.window.id == binding.id }
        let band = window?.band ?? UsageBand(used: binding.used, thresholds: .standard)
        let figure = l10n.format.percentCompact(binding.used.value)
        let forecast = window?.forecast
        var speech = [l10n.card.usedA11y(l10n.format.percent(binding.used.value))]
        if let forecast {
            speech.append(l10n.card.forecastA11y(l10n.format.percent(min(forecast.projectedUsed, 100))))
        }
        return Hero(
            caption: UsageFormat.windowTitle(binding, l10n: l10n),
            figure: figure,
            unit: l10n.card.used,
            band: band,
            fraction: min(max(binding.used.value / 100, 0), 1),
            forecastFraction: forecast.map { min(max($0.projectedUsed / 100, 0), 1) },
            accessibilityText: ([UsageFormat.windowTitle(binding, l10n: l10n)] + speech).joined(separator: ", ")
        )
    }

    // MARK: - Tiles

    static func makeTiles(
        presentation: AccountPresentation,
        resetTextStyle: ResetTextStyle,
        thirdTile: CardThirdTile,
        now: Date,
        l10n: Localizer
    ) -> [Tile] {
        [
            resetTile(presentation: presentation, style: resetTextStyle, now: now, l10n: l10n),
            paceTile(presentation: presentation, now: now, l10n: l10n),
            extraTile(kind: thirdTile, presentation: presentation, now: now, l10n: l10n),
        ]
    }

    private static func resetTile(
        presentation: AccountPresentation,
        style: ResetTextStyle,
        now: Date,
        l10n: Localizer
    ) -> Tile {
        let blocked = presentation.isBlocked
        let window = blocked ? presentation.blockingWindow : presentation.headline?.binding
        guard let window, let resetsAt = window.resetsAt else {
            return Tile(
                kind: .reset,
                systemImage: "clock",
                value: l10n.card.noValue,
                label: blocked ? l10n.card.backAt : l10n.card.untilReset,
                tone: .secondary,
                accessibilityText: l10n.common.noData
            )
        }
        let remaining = max(0, resetsAt.timeIntervalSince(now))
        let value = switch style {
        case .countdown: l10n.format.durationCompact(remaining)
        case .clockTime: weeklyValue(resetsAt, now: now, l10n: l10n)
        }
        let spoken = l10n.format.durationSpoken(remaining)
        return Tile(
            kind: .reset,
            systemImage: blocked ? "clock.badge.exclamationmark" : "clock",
            value: value,
            label: blocked ? l10n.card.backAt : l10n.card.untilReset,
            tone: blocked ? .band(.exhausted) : .primary,
            accessibilityText: blocked ? l10n.card.backInA11y(spoken) : l10n.card.resetsInA11y(spoken)
        )
    }

    private static func paceTile(presentation: AccountPresentation, now: Date, l10n: Localizer) -> Tile {
        let image = "gauge.with.dots.needle.33percent"
        guard let binding = presentation.headline?.binding else {
            return Tile(
                kind: .pace,
                systemImage: image,
                value: l10n.card.noValue,
                label: l10n.card.atThisPace,
                tone: .secondary,
                accessibilityText: l10n.common.noData
            )
        }
        if binding.used.isExhausted || presentation.isBlocked {
            let text = l10n.card.out
            return Tile(kind: .pace, systemImage: image, value: text, label: l10n.card.atThisPace, tone: .band(.exhausted), accessibilityText: text)
        }
        guard let pace = UsagePace(window: binding, now: now) else {
            let text = l10n.card.tooEarly
            return Tile(kind: .pace, systemImage: image, value: text, label: l10n.card.atThisPace, tone: .secondary, accessibilityText: text)
        }
        guard pace.elapsedFraction >= UsagePace.minimumElapsedFractionForProjection else {
            let text = l10n.card.tooEarly
            return Tile(kind: .pace, systemImage: image, value: text, label: l10n.card.atThisPace, tone: .secondary, accessibilityText: text)
        }
        if let exhaustion = pace.projectedExhaustion {
            // The value is the moment itself and the label says what it is, so a narrow tile never has to shrink it:
            // the clock today, the weekday and the clock on another day. A countdown here would
            // read wrong under the label — "2d 3h" is not something that "runs out".
            return Tile(
                kind: .pace,
                systemImage: image,
                value: weeklyValue(exhaustion, now: now, l10n: l10n),
                label: l10n.card.runsOut,
                tone: .band(.critical),
                accessibilityText: l10n.card.runsOutA11y(l10n.format.moment(exhaustion, now: now))
            )
        }
        let text = l10n.card.onTrack
        return Tile(kind: .pace, systemImage: image, value: text, label: l10n.card.atThisPace, tone: .success, accessibilityText: text)
    }

    private static func extraTile(
        kind: CardThirdTile,
        presentation: AccountPresentation,
        now: Date,
        l10n: Localizer
    ) -> Tile {
        switch kind {
        case .weeklyReset:
            if let weekly = weeklyWindow(of: presentation), let resetsAt = weekly.resetsAt {
                return Tile(
                    kind: .third,
                    systemImage: "calendar",
                    value: weeklyValue(resetsAt, now: now, l10n: l10n),
                    label: l10n.card.weeklyReset,
                    tone: .primary,
                    // Named, so VoiceOver tells this tile apart from the reset tile beside it, which speaks the same
                    // kind of phrase about the window that binds the account.
                    accessibilityText: "\(l10n.card.resetsInA11y(l10n.format.durationSpoken(max(0, resetsAt.timeIntervalSince(now))))), \(l10n.card.weeklyReset)"
                )
            }
            return extraTile(kind: .sessionWindow, presentation: presentation, now: now, l10n: l10n)
        case .sessionWindow:
            let image = "gauge.with.needle"
            guard let session = sessionWindow(of: presentation) else {
                return Tile(
                    kind: .third,
                    systemImage: image,
                    value: l10n.card.noValue,
                    label: l10n.card.sessionWindow,
                    tone: .secondary,
                    accessibilityText: l10n.common.noData
                )
            }
            // Only a real session window is called one; a provider without that scope gets its window's own title.
            let label = session.scope == .session ? l10n.card.sessionWindow : UsageFormat.windowTitle(session, l10n: l10n)
            return Tile(
                kind: .third,
                systemImage: image,
                value: l10n.format.percentCompact(session.used.value),
                label: label,
                tone: .band(UsageBand(used: session.used, thresholds: .standard)),
                accessibilityText: "\(l10n.card.usedA11y(l10n.format.percent(session.used.value))), \(label)"
            )
        case .agents:
            let sessions = presentation.status.sessions
            let working = sessions.filter { $0.activity == .working }.count
            let waiting = sessions.filter { $0.activity == .waiting }.count
            guard working + waiting > 0 else {
                return Tile(
                    kind: .third,
                    systemImage: "terminal",
                    value: l10n.card.noValue,
                    label: l10n.card.noAgents,
                    tone: .secondary,
                    accessibilityText: l10n.card.noAgents
                )
            }
            let value = "\(working) · \(waiting)"
            return Tile(
                kind: .third,
                systemImage: "terminal",
                value: value,
                label: l10n.card.agentsLabel,
                tone: waiting > 0 ? .attention : .primary,
                accessibilityText: "\(value), \(l10n.card.agentsLabel)"
            )
        }
    }

    /// The weekly window for the third tile: all models first, else the model week with the highest usage.
    static func weeklyWindow(of presentation: AccountPresentation) -> LimitWindow? {
        guard let headline = presentation.headline else { return nil }
        if let allModels = headline.bucket.windows.first(where: { $0.scope == .weekly(model: nil) }) {
            return allModels
        }
        return headline.modelWeekly
    }

    /// The session window, or the headline's secondary window when the provider has no session scope.
    static func sessionWindow(of presentation: AccountPresentation) -> LimitWindow? {
        guard let headline = presentation.headline else { return nil }
        if let session = headline.bucket.windows.first(where: { $0.scope == .session }) {
            return session
        }
        return headline.secondary ?? headline.primary
    }

    /// A weekly reset short enough for a tile: the clock alone today, the weekday and the clock on another day.
    ///
    /// The two parts are separated by a space in both languages (running text uses a comma in Russian, but a tile has
    /// no room for one and reads perfectly well without it).
    static func weeklyValue(_ date: Date, now: Date, l10n: Localizer) -> String {
        guard !l10n.calendar.isDate(date, inSameDayAs: now) else { return l10n.format.clock(date) }
        return "\(l10n.format.weekdayShort(date)) \(l10n.format.clock(date))"
    }

    // MARK: - Status pill

    static func makePill(
        presentation: AccountPresentation,
        serviceStatus: ServiceStatusBoard,
        ceremonies: CeremonyBoard,
        now: Date,
        l10n: Localizer
    ) -> StatusPill? {
        var items: [(kind: PillKind, text: String, tone: Tone, provider: ProviderKind?)] = []
        let waiting = presentation.waitingSessions.count
        if waiting > 0 {
            items.append((.waiting, l10n.card.waiting(waiting), .attention, nil))
        }
        let provider = presentation.provider
        if let status = serviceStatus.visible(for: provider, now: now), let level = status.level {
            switch level {
            case .majorOutage:
                items.append((.majorOutage, l10n.card.majorOutage, .band(.exhausted), provider))
            case .partialOutage:
                items.append((.partialOutage, l10n.card.partialOutage, .band(.critical), provider))
            case .degraded:
                items.append((.degraded, l10n.card.degraded, .band(.watch), provider))
            case .maintenance:
                items.append((.maintenance, l10n.card.maintenance, .secondary, provider))
            }
        }
        if presentation.isBlocked {
            items.append((.limitReached, l10n.card.limitReached, .band(.exhausted), nil))
        }
        if ceremonies.justReset(accountID: presentation.id, now: now) != nil {
            items.append((.justReset, l10n.card.justReset, .success, nil))
        }
        if case .stale(let since) = presentation.freshness {
            items.append((.stale, l10n.card.stale, .band(.watch), nil))
            _ = since
        }
        guard let winner = items.min(by: { $0.kind < $1.kind }) else { return nil }
        var tooltipItems = items.sorted { $0.kind < $1.kind }.map(\.text)
        if case .stale(let since) = presentation.freshness {
            tooltipItems = tooltipItems.map { $0 == l10n.card.stale ? l10n.card.staleSince(l10n.format.clock(since)) : $0 }
        }
        return StatusPill(
            kind: winner.kind,
            text: winner.text,
            tone: winner.tone,
            tooltip: tooltipItems.joined(separator: " · "),
            statusPageProvider: winner.provider
        )
    }

    // MARK: - Footer

    static func identityText(presentation: AccountPresentation, l10n: Localizer) -> String {
        if let email = presentation.displayEmail {
            return email
        }
        let label = presentation.status.profile.label.value
        if let group = presentation.group {
            return "\(label) · \(group.name.value)"
        }
        return "\(label) · \(UsageFormat.providerName(presentation.provider))"
    }

    /// What VoiceOver reads on the minimized pill, after "Codometer, minimized.".
    ///
    /// Durations are spoken in words, never as "5d 16h", and several accounts say which one is shown.
    public static func pillSummary(
        showing presentation: AccountPresentation?,
        accounts: [AccountPresentation],
        now: Date,
        l10n: Localizer
    ) -> String {
        guard let presentation else { return l10n.common.noData }
        var parts = [presentation.status.profile.label.value]
        if let headline = presentation.headline {
            parts.append(l10n.card.usedA11y(l10n.format.percent(headline.binding.used.value)))
            if let resetsAt = headline.binding.resetsAt {
                parts.append(l10n.card.resetsInA11y(l10n.format.durationSpoken(max(0, resetsAt.timeIntervalSince(now)))))
            }
        } else {
            parts.append(l10n.common.noData)
        }
        if accounts.count > 1, let index = accounts.firstIndex(where: { $0.id == presentation.id }) {
            parts.append(l10n.card.accountPosition(index + 1, of: accounts.count))
        }
        return parts.joined(separator: ", ")
    }

    static func updatedText(presentation: AccountPresentation, now: Date, l10n: Localizer) -> String {
        updatedText(presentations: [presentation], now: now, l10n: l10n)
    }

    /// "updating…" while any of `presentations` refreshes, else the oldest reading among them: the strip's merged
    /// scopes say how fresh the *least* fresh of their accounts is.
    static func updatedText(presentations: [AccountPresentation], now: Date, l10n: Localizer) -> String {
        if presentations.contains(where: \.status.isRefreshing) {
            return l10n.card.updating
        }
        guard let capturedAt = presentations.compactMap({ $0.status.reading?.capturedAt }).min() else {
            return l10n.common.noData
        }
        return l10n.card.updated(l10n.format.clock(capturedAt))
    }
}

/// Picks the account the card follows when the user has not fixed one.
///
/// "Most urgent" would flicker on every engine update if it simply took the maximum, so it only changes when the
/// pointer is away, the user has not just switched by hand, and the candidate is clearly ahead.
public enum CardAccountSelector {
    /// How long a manual switch keeps the card on that account before auto-selection may take over again.
    public static let manualHold: TimeInterval = 60
    /// The candidate has to lead the current account by this many points to take over within the same band.
    public static let switchMarginPoints = 5.0

    /// How urgent one account is: worst band first, then agents waiting, then how full its binding window is.
    public static func rank(_ presentation: AccountPresentation) -> (band: Int, waiting: Int, used: Double) {
        let band = presentation.worstBand.map { UsageBand.allCases.firstIndex(of: $0) ?? 0 } ?? -1
        return (band, presentation.waitingSessions.count, presentation.headline?.binding.used.value ?? 0)
    }

    /// The most urgent account, ignoring hysteresis.
    public static func mostUrgent(_ presentations: [AccountPresentation]) -> AccountPresentation? {
        presentations.max { lhs, rhs in
            let a = rank(lhs)
            let b = rank(rhs)
            if a.band != b.band { return a.band < b.band }
            if a.waiting != b.waiting { return a.waiting < b.waiting }
            return a.used < b.used
        }
    }

    /// The account the card should show now.
    ///
    /// - Parameters:
    ///   - pointerInside: Auto-selection never changes the account under the pointer.
    ///   - manualSwitchAt: When the user last switched by hand; auto-selection waits `manualHold` after it.
    public static func select(
        presentations: [AccountPresentation],
        current: AccountID?,
        selection: CardAccountSelection,
        pointerInside: Bool,
        manualSwitchAt: Date?,
        now: Date
    ) -> AccountID? {
        guard !presentations.isEmpty else { return nil }
        if case .fixed(let id) = selection {
            if presentations.contains(where: { $0.id == id }) { return id }
            // The fixed account is gone (removed, disabled, filtered out): fall back to the most urgent one.
            return mostUrgent(presentations)?.id
        }
        guard let candidate = mostUrgent(presentations) else { return nil }
        guard let current, let shown = presentations.first(where: { $0.id == current }) else { return candidate.id }
        if candidate.id == shown.id { return shown.id }
        if pointerInside { return shown.id }
        if let manualSwitchAt, now.timeIntervalSince(manualSwitchAt) < manualHold { return shown.id }
        let a = rank(candidate)
        let b = rank(shown)
        if a.band > b.band { return candidate.id }
        if a.band < b.band { return shown.id }
        if a.waiting != b.waiting { return a.waiting > b.waiting ? candidate.id : shown.id }
        return a.used - b.used >= switchMarginPoints ? candidate.id : shown.id
    }
}
