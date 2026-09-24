import CodometerL10n
import Foundation

/// Everything the desktop widget shows: written by the app, read by the sandboxed widget extension.
///
/// The snapshot is bounded (at most 16 accounts with 8 windows each, capped strings and counts) and
/// every value is validated where it is created or decoded, so a damaged or hostile file can never make
/// the widget draw nonsense. It carries no session titles, paths or conversation data — only limits,
/// labels and counts — and the e-mail only in the form `EmailVisibility` allows.
public struct WidgetSnapshot: Hashable, Sendable {
    /// 2 since the snapshot carries `layout`. The reader never refuses another version: a file from an older app has
    /// no layout key and reads as rings, a file from a newer app is read for the keys this build knows.
    public static let currentVersion = 2
    public static let maximumAccounts = 16
    /// The widget refuses larger files before decoding them.
    public static let maximumFileBytes = 256 * 1_024
    /// Waiting and working counts are capped here; the widget never needs more digits.
    public static let maximumCount = 999

    /// The folder under the app's data directory the snapshot lives in.
    public static let directoryName = "Widget"
    public static let fileName = "snapshot.json"
    /// The snapshot directory relative to the user's home, as the extension's sandbox exception names it.
    public static let homeRelativeDirectory = "Library/Application Support/Codometer/Widget"
    /// The WidgetKit kind of the all-accounts widget; `WidgetScope` names the per-provider kinds.
    public static var widgetKind: String { WidgetScope.all.kind }
    /// Reset and capture times outside 2000…2200 come from a damaged file and are refused.
    public static let plausibleDates = Date(timeIntervalSince1970: 946_684_800)...Date(timeIntervalSince1970: 7_258_118_400)

    public let version: Int
    public let generatedAt: Date
    /// Enabled accounts in settings order.
    public let accounts: [WidgetAccount]
    /// The colour thresholds the user chose, so the widget colours usage exactly like the island.
    public let bands: BandThresholds
    /// Sessions waiting for the user across all accounts.
    public let attentionCount: Int
    /// Sessions currently working across all accounts.
    public let workingCount: Int
    /// The app's interface language: the extension renders its own text, and its gallery name, in it. The pre-rendered
    /// window titles and notices are already in it.
    public let language: Language
    /// `AppearanceSettings.showsForecast`: whether the user wants the forecast ghost at all. The widget draws no
    /// forecast when it is off, so "Forecast at reset" means the same thing on every surface. A file written before
    /// the key existed reads as `true`, the setting's own default.
    public let showsForecast: Bool
    /// `GeneralSettings.widgetLayout`: rings or the wide strip in the medium and large widgets. A file written before
    /// the key existed reads as rings, the setting's own default.
    public let layout: WidgetLayout

    /// Keeps the first `maximumAccounts` accounts with distinct ids and clamps the counts.
    public init(
        generatedAt: Date,
        accounts: [WidgetAccount],
        bands: BandThresholds,
        attentionCount: Int,
        workingCount: Int,
        language: Language,
        showsForecast: Bool = true,
        layout: WidgetLayout = .rings
    ) {
        version = Self.currentVersion
        self.generatedAt = generatedAt
        self.language = language
        self.showsForecast = showsForecast
        self.layout = layout
        var seen = Set<AccountID>()
        self.accounts = Array(accounts.filter { seen.insert($0.id).inserted }.prefix(Self.maximumAccounts))
        self.bands = bands
        self.attentionCount = Self.clampCount(attentionCount)
        self.workingCount = Self.clampCount(workingCount)
    }

    static func clampCount(_ value: Int) -> Int {
        min(max(value, 0), maximumCount)
    }

    /// The same snapshot content produced at another moment; `generatedAt` alone never forces a rewrite.
    public func hasSameContent(as other: WidgetSnapshot) -> Bool {
        version == other.version
            && accounts == other.accounts
            && bands == other.bands
            && attentionCount == other.attentionCount
            && workingCount == other.workingCount
            && language == other.language
            && showsForecast == other.showsForecast
            && layout == other.layout
    }
}

/// One enabled account as the widget shows it.
public struct WidgetAccount: Hashable, Sendable, Identifiable {
    public static let maximumWindows = 8
    public static let maximumPlanLength = 24
    public static let maximumNoticeLength = 60

    public let id: AccountID
    /// Sanitised, at most `AccountLabel.maximumLength` characters.
    public let label: String
    public let provider: ProviderKind
    /// The account's identity colour, as `AccountStyleResolver` resolved it. Never `.automatic`; `nil` in a snapshot
    /// from an older build, and in one whose tint the file no longer names.
    public let tint: AccountTint?
    /// The one or two characters that stand for the account where its name does not fit; `nil` in a snapshot written
    /// by an older build.
    public let monogram: AccountMonogram?
    public let plan: String?
    /// Already in the form the user's `EmailVisibility` allows: as is, masked, or `nil` when hidden.
    public let email: String?
    /// Why the account has no fresh numbers ("Not signed in"), in the snapshot's language, when the last refresh failed.
    public let notice: String?
    /// Main-bucket windows in display order, then the other buckets' windows; at most `maximumWindows`.
    public let windows: [WidgetWindow]
    /// Ids (`WidgetWindow.id`) of the island's headline windows, when present in `windows`.
    public let primaryWindowID: String?
    public let secondaryWindowID: String?
    public let modelWeeklyWindowID: String?
    /// When the numbers were true; `nil` without a reading.
    public let capturedAt: Date?
    /// Whether the reading was already stale when the snapshot was made.
    public let isStale: Bool
    /// The provider reports the main bucket's limit as reached.
    public let isLimitReached: Bool
    public let waitingCount: Int
    public let workingCount: Int

    public init(
        id: AccountID,
        label: String,
        provider: ProviderKind,
        tint: AccountTint? = nil,
        monogram: AccountMonogram? = nil,
        plan: String? = nil,
        email: String? = nil,
        notice: String? = nil,
        windows: [WidgetWindow] = [],
        primaryWindowID: String? = nil,
        secondaryWindowID: String? = nil,
        modelWeeklyWindowID: String? = nil,
        capturedAt: Date? = nil,
        isStale: Bool = false,
        isLimitReached: Bool = false,
        waitingCount: Int = 0,
        workingCount: Int = 0
    ) throws(ValidationError) {
        guard let cleanLabel = DisplayText.sanitize(label, maximumLength: AccountLabel.maximumLength) else {
            throw .empty(field: "widget.account.label")
        }
        self.id = id
        self.label = cleanLabel
        self.provider = provider
        // `.automatic` is a request to resolve a tint, not a colour: a snapshot only ever carries resolved ones.
        self.tint = tint == .automatic ? nil : tint
        self.monogram = monogram
        self.plan = DisplayText.sanitize(plan, maximumLength: Self.maximumPlanLength)
        self.email = DisplayText.sanitize(email, maximumLength: AccountIdentity.maximumFieldLength)
        self.notice = DisplayText.sanitize(notice, maximumLength: Self.maximumNoticeLength)
        var seen = Set<String>()
        let kept = Array(windows.filter { seen.insert($0.id).inserted }.prefix(Self.maximumWindows))
        self.windows = kept
        let ids = Set(kept.map(\.id))
        self.primaryWindowID = primaryWindowID.flatMap { ids.contains($0) ? $0 : nil }
        self.secondaryWindowID = secondaryWindowID.flatMap { ids.contains($0) ? $0 : nil }
        self.modelWeeklyWindowID = modelWeeklyWindowID.flatMap { ids.contains($0) ? $0 : nil }
        self.capturedAt = kept.isEmpty ? nil : capturedAt.flatMap { WidgetSnapshot.plausibleDates.contains($0) ? $0 : nil }
        self.isStale = isStale
        self.isLimitReached = isLimitReached
        self.waitingCount = WidgetSnapshot.clampCount(waitingCount)
        self.workingCount = WidgetSnapshot.clampCount(workingCount)
    }

    public var hasReading: Bool { !windows.isEmpty }

    public func window(id: String) -> WidgetWindow? {
        windows.first { $0.id == id }
    }
}

/// One limit window with its display title.
public struct WidgetWindow: Hashable, Sendable, Identifiable {
    public static let maximumTitleLength = 60

    public let bucketID: String
    /// The provider's bucket title for windows outside the main bucket ("GPT-5.3-Codex-Spark").
    public let bucketTitle: String?
    public let isMainBucket: Bool
    public let window: LimitWindow
    /// "Session · 5h", "Weekly · Fable", … in the snapshot's language.
    public let title: String

    /// `title` defaults to `WidgetText.windowTitle(window, l10n:)` in `language`. Throws for an invalid bucket id or an
    /// implausible reset.
    public init(
        bucketID: String,
        bucketTitle: String? = nil,
        isMainBucket: Bool,
        window: LimitWindow,
        title: String? = nil,
        language: Language
    ) throws(ValidationError) {
        self.bucketID = try StableIdentifier.validate(bucketID, field: "widget.window.bucketID")
        if let resetsAt = window.resetsAt, !WidgetSnapshot.plausibleDates.contains(resetsAt) {
            throw .outOfRange(
                field: "widget.window.resetsAt",
                value: resetsAt.timeIntervalSince1970,
                lowerBound: WidgetSnapshot.plausibleDates.lowerBound.timeIntervalSince1970,
                upperBound: WidgetSnapshot.plausibleDates.upperBound.timeIntervalSince1970
            )
        }
        self.bucketTitle = DisplayText.sanitize(bucketTitle, maximumLength: Self.maximumTitleLength)
        self.isMainBucket = isMainBucket
        self.window = window
        self.title = DisplayText.sanitize(title, maximumLength: Self.maximumTitleLength)
            ?? WidgetText.windowTitle(window, l10n: Localizer(language: language))
    }

    /// Unique within an account: other buckets reuse window ids such as `primary`.
    public var id: String { "\(bucketID)/\(window.id)" }

    /// The title with the bucket named for windows outside the main bucket: "Spark · 5h".
    public var displayTitle: String {
        guard !isMainBucket, let bucketTitle else { return title }
        return "\(WidgetText.shortBucketTitle(bucketTitle)) · \(title)"
    }
}
