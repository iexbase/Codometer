import CodometerL10n
import Foundation

extension WidgetSnapshot {
    /// Builds the widget's snapshot from the tracker state.
    ///
    /// Every enabled account is included in settings order, whatever group the island is filtered to: the widget
    /// is a separate surface. E-mails follow `AppearanceSettings.emailVisibility`; session titles, paths and
    /// organisation names never enter the snapshot. Window titles and notices are rendered in `language`, the app's
    /// resolved interface language, which the snapshot carries for the extension's own text.
    ///
    /// Tints and monograms are resolved over the **whole** account list, disabled accounts included, so an account's
    /// identity mark is the same in the widget as on the island whatever the widget happens to show.
    public static func make(state: TrackerState, settings: AppSettings, now: Date, language: Language) -> WidgetSnapshot {
        var statuses: [AccountID: AccountStatus] = [:]
        for status in state.accounts where statuses[status.id] == nil {
            statuses[status.id] = status
        }
        let visibility = settings.appearance.emailVisibility
        let styles = AccountStyleResolver.styles(for: settings.accounts)
        var accounts: [WidgetAccount] = []
        for profile in settings.accounts where profile.isEnabled && accounts.count < maximumAccounts {
            if let account = WidgetAccount.make(
                profile: profile,
                status: statuses[profile.id],
                style: styles[profile.id],
                visibility: visibility,
                now: now,
                language: language
            ) {
                accounts.append(account)
            }
        }
        return WidgetSnapshot(
            generatedAt: now,
            accounts: accounts,
            bands: settings.appearance.bands,
            attentionCount: accounts.reduce(0) { $0 + $1.waitingCount },
            workingCount: accounts.reduce(0) { $0 + $1.workingCount },
            language: language,
            showsForecast: settings.appearance.showsForecast,
            layout: settings.general.widgetLayout
        )
    }

    /// Whether the state already covers every enabled account. Before the engine publishes its first state (or
    /// catches up with a newly added account) a snapshot would replace good numbers with "No data".
    public static func isStateReady(_ state: TrackerState, for settings: AppSettings) -> Bool {
        let known = Set(state.accounts.map(\.id))
        return settings.accounts.allSatisfy { !$0.isEnabled || known.contains($0.id) }
    }
}

extension WidgetAccount {
    /// `nil` only if the profile's validated label could not be carried over, which cannot happen for a valid profile.
    static func make(
        profile: AccountProfile,
        status: AccountStatus?,
        style: AccountStyle?,
        visibility: EmailVisibility,
        now: Date,
        language: Language
    ) -> WidgetAccount? {
        let reading = status?.reading
        let headline = reading.map(HeadlineWindows.init(reading:))
        let windows = Self.windows(reading: reading, headline: headline, language: language)
        let mainBucketID = headline?.bucket.id
        func key(_ window: LimitWindow?) -> String? {
            guard let window, let mainBucketID else { return nil }
            return "\(mainBucketID)/\(window.id)"
        }
        let sessions = status?.sessions ?? []
        let isStale: Bool
        if let status, case .stale = status.freshness(at: now) {
            isStale = true
        } else {
            isStale = false
        }
        return try? WidgetAccount(
            id: profile.id,
            label: profile.label.value,
            provider: profile.provider,
            tint: style?.tint,
            monogram: style?.monogram,
            plan: status?.identity?.plan,
            email: WidgetText.email(status?.identity?.email, visibility: visibility),
            notice: status?.issue.map { WidgetText.notice(for: $0.kind, l10n: Localizer(language: language)) },
            windows: windows,
            primaryWindowID: key(headline?.primary),
            secondaryWindowID: key(headline?.secondary),
            modelWeeklyWindowID: key(headline?.modelWeekly),
            capturedAt: reading?.capturedAt,
            isStale: isStale,
            isLimitReached: headline?.bucket.isLimitReached ?? false,
            waitingCount: sessions.count { $0.activity == .waiting },
            workingCount: sessions.count { $0.activity == .working }
        )
    }

    /// Main-bucket windows in the island's display order, then the other buckets' windows in provider order.
    private static func windows(reading: UsageReading?, headline: HeadlineWindows?, language: Language) -> [WidgetWindow] {
        guard let reading, let headline else { return [] }
        var result: [WidgetWindow] = []
        for window in headline.allWindows {
            if let item = try? WidgetWindow(
                bucketID: headline.bucket.id,
                bucketTitle: headline.bucket.title,
                isMainBucket: true,
                window: window,
                language: language
            ) {
                result.append(item)
            }
        }
        for bucket in reading.buckets.dropFirst() {
            for window in bucket.windows {
                if let item = try? WidgetWindow(
                    bucketID: bucket.id,
                    bucketTitle: bucket.title,
                    isMainBucket: false,
                    window: window,
                    language: language
                ) {
                    result.append(item)
                }
            }
        }
        return Array(result.prefix(maximumWindows))
    }
}
