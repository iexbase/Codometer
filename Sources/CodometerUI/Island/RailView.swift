import CodometerCore
import CodometerL10n
import SwiftUI

/// At rest: a dial per visible account with a fixed-width label, hairlines between account groups, and an
/// attention tab while agents wait.
///
/// Calm and readable at a glance: each ring sits on a faint static halo in its band colour, percentages are set
/// as bold digits with a lighter, smaller percent sign (tinted once usage leaves the ample band), and group
/// separators fade out at both ends. The only motion is event-driven: a single sheen sweeps across the rail when
/// its numbers change (Core Animation, never at idle), besides the existing activity orbits.
///
/// Nothing on the rail changes its size when values change: labels reserve the widest text they can show,
/// dials reserve room for their activity orbit, and only the attention tab appearing grows the rail.
struct RailView: View {
    let store: TrackerStore
    let model: IslandModel
    let accounts: [AccountPresentation]
    /// `false` leaves the attention tab out (e.g. the left wing of a rail split around the camera notch).
    var showsAttentionTab: Bool = true
    /// Overrides `metrics.railDial`, e.g. for a rail that has to fit beside the camera notch.
    var dialDiameter: CGFloat?

    @Environment(\.displayScale) private var displayScale
    @Environment(\.liveEffectsEnabled) private var liveEffectsEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.l10n) private var l10n
    @Environment(\.ringFlightHiddenAccounts) private var ringFlightHiddenAccounts

    var body: some View {
        let layout = model.layout
        let metrics = layout.metrics
        let dialSize = dialDiameter ?? metrics.railDial
        let horizontal = layout.edge.isHorizontal
        let separators = Self.separatorIndices(groups: accounts.map { $0.group?.id })
        let waitingCount = showsAttentionTab && store.hasWaiting ? store.attentionQueue.count : 0
        // Identity marks appear only when two enabled accounts share a provider, and that is a settings change:
        // within one setup the rail's layout never changes.
        let shared = Self.sharedProviders(accounts: store.settings.accounts)
        let stage = ceremonyStage

        // Labels reserve their widest text, which already adds air after short ones; the gap between dials stays
        // modest, but clear enough that neighbouring accounts never read as one.
        stack(horizontal: horizontal, spacing: horizontal ? 8 * metrics.scale : 12 * metrics.scale) {
            if accounts.isEmpty {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(metrics.font(15, .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: dialSize, height: dialSize)
                    .padding(metrics.orbitMargin)
                    .accessibilityLabel(l10n.rail.noAccountsA11y)
            } else {
                ForEach(Array(accounts.enumerated()), id: \.element.id) { index, presentation in
                    if separators.contains(index) {
                        hairline(horizontal: horizontal, metrics: metrics, dialSize: dialSize)
                    }
                    dial(presentation, horizontal: horizontal, metrics: metrics, diameter: dialSize, shared: shared)
                }
            }
            if waitingCount > 0 {
                AttentionTab(count: waitingCount, metrics: metrics) {
                    model.request(.openAttention)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
        }
        .animation(Motion.snappy, value: waitingCount > 0)
        .padding(Self.contentInsets(horizontal: horizontal, metrics: metrics))
        .overlay {
            if liveEffectsEnabled, !reduceMotion, !Motion.reducesMotion, !accounts.isEmpty {
                SheenSweep(
                    trigger: Self.sheenTrigger(
                        labels: accounts.map { RailLabel(presentation: $0, now: store.now, l10n: l10n) },
                        // A reset gets its own glint; the sheen stays out of its way.
                        celebrating: Self.celebratingIndices(accounts: accounts, stage: stage)
                    ),
                    horizontal: horizontal,
                    cornerRadius: metrics.railCorner
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .padding(layout.shoulderInsets)
        // Only the live rail celebrates; measurement copies and static renders get no stage at all.
        .environment(\.ceremonyStage, stage)
    }

    /// The stage this rail's dials celebrate on, or `nil` when they must not: hidden measurement copies, static
    /// renders and previews all run without live effects.
    private var ceremonyStage: CeremonyStage? {
        guard liveEffectsEnabled, store.settings.appearance.celebratesResets else { return nil }
        return CeremonyStage(surface: .rail, board: store.ceremonies, now: store.now) { [store] id, surface in
            store.markCeremonyPlayed(id, on: surface)
        }
    }

    /// Indices of accounts with a reset still to celebrate on the rail.
    static func celebratingIndices(accounts: [AccountPresentation], stage: CeremonyStage?) -> Set<Int> {
        guard let stage else { return [] }
        let celebrating = Set(stage.board.unplayed(on: stage.surface, now: stage.now).map(\.event.accountID))
        guard !celebrating.isEmpty else { return [] }
        return Set(accounts.indices.filter { celebrating.contains(accounts[$0].id) })
    }

    /// Providers that more than one tracked account uses. Their dials show the account's monogram instead of the
    /// provider's mark, which would be the same on both; the others keep their glyph.
    nonisolated static func sharedProviders(accounts: [AccountProfile]) -> Set<ProviderKind> {
        var seen = Set<ProviderKind>()
        var shared = Set<ProviderKind>()
        for account in accounts where account.isEnabled {
            if !seen.insert(account.provider).inserted { shared.insert(account.provider) }
        }
        return shared
    }

    /// Whether the rail marks which account is which at all. It follows the settings, never the data, so the rail's
    /// height changes only when the user adds or removes an account.
    nonisolated static func showsIdentityMarks(accounts: [AccountProfile]) -> Bool {
        !sharedProviders(accounts: accounts).isEmpty
    }

    /// Changes when a label shows a new percentage or switches between a percentage, a countdown and no data, so the
    /// sheen plays on new numbers only. A countdown ticking down does not count: a blocked account would otherwise
    /// flash the rail every minute until its reset.
    /// - Parameter celebrating: Indices whose account has a reset ceremony still to play on the rail. Their labels
    ///   hash as one constant token, so the new percentage after a reset does not also sweep the rail.
    nonisolated static func sheenTrigger(labels: [RailLabel], celebrating: Set<Int> = []) -> Int {
        var hasher = Hasher()
        for (index, label) in labels.enumerated() {
            guard !celebrating.contains(index) else {
                hasher.combine("ceremony")
                continue
            }
            switch label {
            case .percent(let text, _): hasher.combine(text)
            case .countdown: hasher.combine("countdown")
            case .unknown: hasher.combine(RailLabel.unknownText)
            }
        }
        hasher.combine(labels.count)
        return hasher.finalize()
    }

    @ViewBuilder
    private func stack(horizontal: Bool, spacing: CGFloat, @ViewBuilder content: () -> some View) -> some View {
        if horizontal {
            HStack(spacing: spacing, content: content)
        } else {
            VStack(spacing: spacing, content: content)
        }
    }

    private func dial(_ presentation: AccountPresentation, horizontal: Bool, metrics: IslandMetrics, diameter: CGFloat, shared: Set<ProviderKind>) -> some View {
        // Every dial reserves the dot's row together, so the rail keeps one height; only a dial whose provider is
        // shared gives up its glyph for a monogram.
        let showsIdentity = !shared.isEmpty
        // The gauge always reserves room for the activity orbit around its ring, so activity never resizes the rail.
        let gauge = RingGauge(
            presentation: presentation,
            diameter: diameter,
            showsSecondary: false,
            isHighlighted: model.highlightedAccountID == presentation.id,
            orbitMargin: metrics.orbitMargin,
            hidesRings: ringFlightHiddenAccounts.contains(presentation.id),
            // Small rings stay calm: only a forecast that runs into the limit is worth a ghost here.
            forecastPolicy: .warningsOnly,
            centerMark: shared.contains(presentation.provider) ? .monogram : .providerGlyph,
            ceremonySurface: .rail
        )
        let label = RailLabelView(
            label: RailLabel(presentation: presentation, now: store.now, l10n: l10n),
            isStale: presentation.isStale,
            band: presentation.primaryBand,
            metrics: metrics,
            alignment: horizontal ? .leading : .center
        )
        // The identity dot hangs below the label as an overlay, in space the taller gauge already occupies: a row of
        // its own would push every label above its ring and leave the rail bottom-heavy.
        let dotSize = Self.identityDotSize(metrics: metrics)
        let identified = label
            .overlay(alignment: .bottom) {
                if showsIdentity {
                    AccountBadge.Dot(tint: presentation.style.tint, diameter: dotSize)
                        .offset(y: dotSize + 3 * metrics.scale)
                }
            }
        let halo = RingHalo(band: presentation.isStale ? nil : presentation.primaryBand, diameter: diameter)
        return Group {
            if horizontal {
                HStack(spacing: max(0, 5 * metrics.scale - metrics.orbitMargin)) {
                    gauge.background { halo }
                    identified
                }
            } else {
                VStack(spacing: max(0, 3 * metrics.scale - metrics.orbitMargin)) {
                    gauge.background { halo }
                    identified
                }
            }
        }
        .help(presentation.group.map { "\(presentation.status.profile.label.value) · \($0.name.value)" } ?? presentation.status.profile.label.value)
        // One element per account: its name (and group), then usage or how long it stays blocked, in words.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(([presentation.status.profile.label.value] + [presentation.group?.name.value].compactMap { $0 }).joined(separator: ", "))
        .accessibilityValue(Self.dialAccessibilityValue(
            presentation: presentation,
            now: store.now,
            celebrates: ceremonyStage.map { !$0.ceremonies(of: presentation.id).isEmpty } ?? false,
            l10n: l10n
        ))
    }

    /// The identity dot under a rail label: small enough to stay a mark, never a second gauge.
    nonisolated static func identityDotSize(metrics: IslandMetrics) -> CGFloat {
        max(3, 4 * metrics.scale)
    }

    /// What VoiceOver says after a rail dial's name: "57% used, Working", or "Limit reached, available again in
    /// 2 hours 14 minutes" while the account is blocked.
    static func dialAccessibilityValue(
        presentation: AccountPresentation,
        now: Date,
        forecastPolicy: RingForecastPolicy = .warningsOnly,
        celebrates: Bool = false,
        l10n: Localizer
    ) -> String {
        var details = RingGauge.accessibilityDetails(
            presentation: presentation,
            forecastPolicy: presentation.isStale ? .never : forecastPolicy,
            celebrates: celebrates,
            l10n: l10n
        )
        if case .countdown = RailLabel(presentation: presentation, now: now, l10n: l10n),
           let remaining = presentation.headline?.blockingWindow?.timeUntilReset(from: now), remaining > 0 {
            details[0] = l10n.rail.limitReachedA11y(backIn: l10n.format.durationSpoken(remaining))
        }
        return details.joined(separator: ", ")
    }

    /// A hairline between groups that fades out towards both ends.
    private func hairline(horizontal: Bool, metrics: IslandMetrics, dialSize: CGFloat) -> some View {
        let thickness = 1 / max(displayScale, 1)
        let length = dialSize * 0.86
        let fade = Gradient(stops: [
            .init(color: Color.primary.opacity(0), location: 0),
            .init(color: Color.primary.opacity(0.26), location: 0.5),
            .init(color: Color.primary.opacity(0), location: 1),
        ])
        return Rectangle()
            .fill(LinearGradient(gradient: fade, startPoint: horizontal ? .top : .leading, endPoint: horizontal ? .bottom : .trailing))
            .frame(width: horizontal ? thickness : length, height: horizontal ? length : thickness)
            .accessibilityHidden(true)
    }

    /// Padding around the rail's stack. The stack starts with a dial whose orbit margin already adds room, so the
    /// start is inset less than the end and both ends look equally spaced. Along the rail's own axis the ends get
    /// real air: a rail whose first and last dials touch its rounded ends looks cramped against the screen edge.
    nonisolated static func contentInsets(horizontal: Bool, metrics: IslandMetrics) -> EdgeInsets {
        let orbit = metrics.orbitMargin
        let end = 13 * metrics.scale
        if horizontal {
            return EdgeInsets(top: 3 * metrics.scale, leading: max(0, end - orbit), bottom: 3 * metrics.scale, trailing: end)
        }
        return EdgeInsets(top: max(0, end - orbit), leading: 6 * metrics.scale, bottom: end, trailing: 6 * metrics.scale)
    }

    /// Indices of accounts that start a new group: a hairline goes before each of them.
    nonisolated static func separatorIndices(groups: [AccountGroupID?]) -> Set<Int> {
        var indices: Set<Int> = []
        for index in groups.indices.dropFirst() where groups[index] != groups[index - 1] {
            indices.insert(index)
        }
        return indices
    }
}

/// What a rail label says: the headline percentage, or how long until a blocked account is usable again.
enum RailLabel: Hashable {
    case percent(String, value: Double)
    /// The account is blocked; the text counts down to the blocking window's reset.
    case countdown(String)
    case unknown

    /// The widest percentage a label can show.
    static let percentTemplate = "100%"
    /// The widest countdown a label can show.
    static let countdownTemplate = UsageFormat.railCountdownTemplate
    static let unknownText = "—"

    init(presentation: AccountPresentation, now: Date, l10n: Localizer) {
        self.init(headline: presentation.headline, now: now, l10n: l10n)
    }

    init(headline: HeadlineWindows?, now: Date, l10n: Localizer) {
        guard let headline else {
            self = .unknown
            return
        }
        if headline.isBlocked, let resetsAt = headline.blockingWindow?.resetsAt, resetsAt > now {
            self = .countdown(UsageFormat.railCountdown(resetsAt.timeIntervalSince(now), l10n: l10n))
            return
        }
        self = .percent(UsageFormat.percent(headline.primary.used, l10n: l10n), value: headline.primary.used.value)
    }

    var text: String {
        switch self {
        case .percent(let text, _): text
        case .countdown(let text): text
        case .unknown: Self.unknownText
        }
    }

    /// A percentage split into its number and its percent sign; text without a trailing sign has an empty sign.
    nonisolated static func percentParts(_ text: String) -> (number: String, sign: String) {
        guard text.hasSuffix("%"), text.count > 1 else { return (text, "") }
        return (String(text.dropLast()), "%")
    }
}

/// A rail label that always takes the width of the widest label it could show at this scale.
///
/// Percentages read as bold digits with a smaller, lighter percent sign; the digits take the band's text colour
/// once usage leaves the ample band, so a rising number is noticed without reading it.
struct RailLabelView: View {
    let label: RailLabel
    let isStale: Bool
    var band: UsageBand?
    let metrics: IslandMetrics
    let alignment: Alignment
    @Environment(\.l10n) private var l10n

    var body: some View {
        ZStack(alignment: alignment) {
            percent(RailLabel.percentTemplate)
                .hidden()
            blocked(RailLabel.countdownTemplate)
                .hidden()
            switch label {
            case .percent(let text, let value):
                percent(text)
                    .contentTransition(.numericText(value: value))
                    .transition(.opacity)
            case .countdown(let text):
                blocked(text)
                    .contentTransition(.numericText())
                    .transition(.opacity)
            case .unknown:
                Text(RailLabel.unknownText)
                    .transition(.opacity)
            }
        }
        .font(metrics.digits(TextSize.footnote, .bold))
        .lineLimit(1)
        .fixedSize()
        // A rolling digit travels a line height while it changes; clipping keeps it inside the label's own box
        // instead of letting it fly over the dial above (and the spring is dropped so it cannot overshoot).
        .compositingGroup()
        .clipped()
        // Stale data reads calm grey instead of fading the whole dial.
        .foregroundStyle(digitStyle)
        .animation(Motion.reveal, value: label)
        .accessibilityLabel(accessibilityText)
    }

    /// Band colour for watch and above; primary while ample; secondary while stale.
    private var digitStyle: AnyShapeStyle {
        if isStale { return AnyShapeStyle(HierarchicalShapeStyle.secondary) }
        guard let band = Self.tintedBand(band) else { return AnyShapeStyle(HierarchicalShapeStyle.primary) }
        return AnyShapeStyle(Theme.bandText(for: band))
    }

    /// Only bands past ample tint the digits.
    nonisolated static func tintedBand(_ band: UsageBand?) -> UsageBand? {
        guard let band, band != .ample else { return nil }
        return band
    }

    /// Size of the percent sign relative to the digits.
    nonisolated static let percentSignScale: CGFloat = 0.72

    /// "57%" as "57" followed by a smaller, lighter "%"; any other text as it is.
    private func percent(_ text: String) -> Text {
        let parts = RailLabel.percentParts(text)
        guard !parts.sign.isEmpty else { return Text(text) }
        let sign = Text(parts.sign)
            .font(.system(size: metrics.textSize(TextSize.footnote) * Self.percentSignScale, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
        return Text("\(Text(parts.number))\(sign)")
    }

    /// The lock beside a countdown keeps its proportion to the label's digits, which never shrink below their
    /// floor, so it stays legible at small scales instead of scaling down on its own.
    nonisolated static func lockGlyphSize(metrics: IslandMetrics) -> CGFloat {
        (IslandMetrics.textSize(TextSize.footnote, scale: metrics.scale) * 0.68).rounded(.toNearestOrEven)
    }

    private func blocked(_ text: String) -> some View {
        HStack(spacing: 1 * metrics.scale) {
            Image(systemName: "lock.fill")
                .font(.system(size: Self.lockGlyphSize(metrics: metrics), weight: .bold))
                .foregroundStyle(isStale ? AnyShapeStyle(HierarchicalShapeStyle.secondary) : AnyShapeStyle(Theme.bandText(for: .exhausted)))
            Text(text)
        }
    }

    /// The label on its own; the rail reads a dial and its label as one element with the time in words instead.
    private var accessibilityText: String {
        switch label {
        case .percent(let text, _): text
        case .countdown(let text): l10n.rail.limitReachedA11y(backIn: text)
        case .unknown: l10n.common.noData
        }
    }
}

/// A soft, static glow under a rail ring in its band colour: calm when ample, warmer as usage rises. Drawn as a
/// radial gradient (no blur, no animation), so it costs nothing after the first frame.
struct RingHalo: View {
    let band: UsageBand?
    let diameter: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let band {
            let tint = Theme.tint(for: band)
            let peak = Self.opacity(for: band, dark: colorScheme == .dark)
            Circle()
                .fill(RadialGradient(
                    colors: [tint.opacity(peak), tint.opacity(peak * 0.45), tint.opacity(0)],
                    center: .center,
                    startRadius: diameter * 0.18,
                    endRadius: diameter * 0.92
                ))
                .frame(width: diameter * 1.84, height: diameter * 1.84)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// Peak opacity of the halo: stronger on dark surfaces, where a glow reads as light, and as usage rises.
    nonisolated static func opacity(for band: UsageBand, dark: Bool) -> Double {
        let base: Double = switch band {
        case .ample: 0.14
        case .watch: 0.2
        case .critical: 0.26
        case .exhausted: 0.3
        }
        return dark ? base : base * 0.55
    }
}
