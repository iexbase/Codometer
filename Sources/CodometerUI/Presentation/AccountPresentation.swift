import CodometerCore
import CodometerL10n
import Foundation

/// Everything a view needs about one account, computed once per render.
public struct AccountPresentation: Identifiable {
    public typealias WindowPresentation = CodometerUI.WindowPresentation

    public let status: AccountStatus
    public let headline: HeadlineWindows?
    public let primaryBand: UsageBand?
    public let secondaryBand: UsageBand?
    public let freshness: ReadingFreshness
    public let activity: AgentActivity?
    /// Every window of every bucket: the main bucket first in `HeadlineWindows.allWindows` order,
    /// then the other buckets' windows in the provider's order.
    public let windows: [WindowPresentation]
    /// Any main-bucket window is exhausted or the provider reports the main bucket's limit as reached.
    public let isBlocked: Bool
    /// The exhausted window that resets last, i.e. the one keeping the account blocked.
    public let blockingWindow: LimitWindow?
    /// The worst band over the main bucket's windows; `nil` without a reading.
    public let worstBand: UsageBand?
    /// The e-mail as `AppearanceSettings.emailVisibility` allows: as is, masked, or `nil` when hidden.
    public let displayEmail: String?
    /// The organisation name with any e-mail inside it masked or dropped per the same setting.
    public let displayOrganization: String?
    public let group: AccountGroup?
    /// Sessions waiting for the user, longest wait first.
    public let waitingSessions: [AgentSession]
    /// The account's identity tint and monogram (identity chrome only, never data colours).
    public let style: AccountStyle

    /// Resolves the account's group from `settings`. Window titles are written with `l10n`. `style` should come from
    /// one `AccountStyleResolver.styles(for: settings.accounts)` call for all accounts (as `TrackerStore` does); without
    /// it the account is resolved on its own, whose automatic tint may differ.
    public init(status: AccountStatus, settings: AppSettings, now: Date, l10n: Localizer, style: AccountStyle? = nil) {
        self.init(
            status: status,
            appearance: settings.appearance,
            now: now,
            l10n: l10n,
            group: status.profile.groupID.flatMap(settings.group),
            style: style
        )
    }

    public init(
        status: AccountStatus,
        appearance: AppearanceSettings,
        now: Date,
        l10n: Localizer,
        group: AccountGroup? = nil,
        style: AccountStyle? = nil
    ) {
        self.status = status
        let headline = status.reading.map(HeadlineWindows.init(reading:))
        self.headline = headline
        primaryBand = headline.map { UsageBand(used: $0.primary.used, thresholds: appearance.bands) }
        secondaryBand = headline?.secondary.map { UsageBand(used: $0.used, thresholds: appearance.bands) }
        freshness = status.freshness(at: now)
        activity = status.dominantActivity
        windows = Self.windows(reading: status.reading, headline: headline, appearance: appearance, now: now, l10n: l10n)
        isBlocked = headline?.isBlocked ?? false
        blockingWindow = headline?.blockingWindow
        worstBand = Self.worstBand(of: status.reading, thresholds: appearance.bands)
        displayEmail = UsageFormat.email(status.identity, visibility: appearance.emailVisibility)
        displayOrganization = UsageFormat.organization(status.identity, visibility: appearance.emailVisibility)
        self.group = group
        waitingSessions = Self.waitingSessions(in: status.sessions)
        self.style = style ?? Self.ownStyle(of: status.profile)
    }

    public var id: AccountID { status.id }
    public var provider: ProviderKind { status.profile.provider }

    public var isStale: Bool {
        if case .stale = freshness { return true }
        return false
    }

    /// The main-bucket windows only, in display order.
    public var mainWindows: [WindowPresentation] {
        windows.filter(\.isMainBucket)
    }

    // MARK: - Derivations

    /// The profile's style resolved without the other accounts.
    static func ownStyle(of profile: AccountProfile) -> AccountStyle {
        guard let style = AccountStyleResolver.styles(for: [profile])[profile.id] else {
            preconditionFailure("AccountStyleResolver styles every account it is given")
        }
        return style
    }

    /// The worst band over the main bucket's windows; a bucket the provider reports as limited counts as exhausted.
    static func worstBand(of reading: UsageReading?, thresholds: BandThresholds) -> UsageBand? {
        guard let bucket = reading?.mainBucket else { return nil }
        if bucket.isLimitReached { return .exhausted }
        return bucket.windows.map { UsageBand(used: $0.used, thresholds: thresholds) }.max()
    }

    static func windows(
        reading: UsageReading?,
        headline: HeadlineWindows?,
        appearance: AppearanceSettings,
        now: Date,
        l10n: Localizer
    ) -> [WindowPresentation] {
        guard let reading, let headline else { return [] }
        let main = headline.allWindows.map { window in
            WindowPresentation(bucket: headline.bucket, window: window, isMainBucket: true, appearance: appearance, now: now, l10n: l10n)
        }
        let others = reading.buckets.dropFirst().flatMap { bucket in
            bucket.windows.map { window in
                WindowPresentation(bucket: bucket, window: window, isMainBucket: false, appearance: appearance, now: now, l10n: l10n)
            }
        }
        return main + others
    }

    static func waitingSessions(in sessions: [AgentSession]) -> [AgentSession] {
        let waiting: [(offset: Int, element: AgentSession)] = Array(sessions.filter { $0.activity == .waiting }.enumerated())
        return waiting
            .sorted { lhs, rhs in
                lhs.element.activitySince == rhs.element.activitySince
                    ? lhs.offset < rhs.offset
                    : lhs.element.activitySince < rhs.element.activitySince
            }
            .map(\.element)
    }
}

/// One limit window ready to draw: its title, colour band, ring progress and pace.
public struct WindowPresentation: Identifiable, Hashable, Sendable {
    public let bucketID: String
    public let bucketTitle: String?
    /// Whether the window belongs to the account's main bucket (the one rings and alerts headline).
    public let isMainBucket: Bool
    public let window: LimitWindow
    /// `UsageFormat.windowTitle(window, l10n:)`.
    public let title: String
    public let progress: WindowProgress
    public let band: UsageBand
    /// How usage compares with elapsed time; `nil` when unknown or when the user turned pace hints off.
    public let pace: UsagePace?
    /// Where usage lands by the reset at the current pace; `nil` when there is nothing to show or the user turned
    /// forecasts off (`appearance.showsForecast`).
    public let forecast: UsageForecast?

    public init(
        bucketID: String,
        bucketTitle: String?,
        isMainBucket: Bool,
        window: LimitWindow,
        appearance: AppearanceSettings,
        now: Date,
        l10n: Localizer
    ) {
        self.bucketID = bucketID
        self.bucketTitle = bucketTitle
        self.isMainBucket = isMainBucket
        self.window = window
        title = UsageFormat.windowTitle(window, l10n: l10n)
        progress = WindowProgress(window: window, now: now)
        band = UsageBand(used: window.used, thresholds: appearance.bands)
        pace = appearance.showsPace ? UsagePace(window: window, now: now) : nil
        forecast = appearance.showsForecast ? UsageForecast(window: window, now: now, thresholds: appearance.bands) : nil
    }

    init(bucket: LimitBucket, window: LimitWindow, isMainBucket: Bool, appearance: AppearanceSettings, now: Date, l10n: Localizer) {
        self.init(
            bucketID: bucket.id,
            bucketTitle: bucket.title,
            isMainBucket: isMainBucket,
            window: window,
            appearance: appearance,
            now: now,
            l10n: l10n
        )
    }

    public var id: String { "\(bucketID)/\(window.id)" }
}
