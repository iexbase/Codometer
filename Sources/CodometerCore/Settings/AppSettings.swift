import CodometerL10n
import Foundation

/// The screen edge the island sits on.
public enum ScreenEdge: String, Codable, Sendable, CaseIterable, Identifiable {
    case top
    case bottom
    case left
    case right

    public var id: String { rawValue }

    /// Top and bottom islands lay accounts out in a row, side islands in a column.
    public var isHorizontal: Bool { self == .top || self == .bottom }
}

public enum IslandVisibility: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Always on screen; expands on hover.
    case always
    /// Only the menu bar item is shown.
    case hidden

    public var id: String { rawValue }
}

public enum IslandStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    /// A tab that grows out of the screen edge, blended in with concave shoulders.
    case attached
    /// A capsule floating a few points away from the edge.
    case floating

    public var id: String { rawValue }
}

/// What the island is made of.
public enum IslandSurface: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Liquid Glass that follows the system appearance.
    case glass
    /// Clear glass over a dark tint: readable on any wallpaper.
    case darkGlass
    /// Opaque black, like a hardware notch.
    case solid

    public var id: String { rawValue }
}

public enum ResetTextStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    /// "in 2 h 14 min"
    case countdown
    /// "Fri 12:10"
    case clockTime

    public var id: String { rawValue }
}

/// Position along the edge: 0 is the top or left end, 1 the bottom or right end.
public struct EdgeOffset: Hashable, Sendable, Comparable {
    public let value: Double

    public init(_ value: Double) throws(ValidationError) {
        guard value.isFinite else { throw .notFinite(field: "appearance.offset") }
        guard (0...1).contains(value) else {
            throw .outOfRange(field: "appearance.offset", value: value, lowerBound: 0, upperBound: 1)
        }
        self.value = value
    }

    private init(trusted value: Double) {
        self.value = value
    }

    public static let center = EdgeOffset(trusted: 0.5)

    /// Clamps any finite value into range; used for positions that come from pointer drags.
    public static func clamped(_ value: Double) -> EdgeOffset {
        EdgeOffset(trusted: value.isFinite ? min(max(value, 0), 1) : 0.5)
    }

    public static func < (lhs: EdgeOffset, rhs: EdgeOffset) -> Bool { lhs.value < rhs.value }
}

extension EdgeOffset: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try Double(from: decoder)
        do throws(ValidationError) {
            self = try EdgeOffset(raw)
        } catch {
            throw error.decodingError(at: decoder.codingPath)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        try value.encode(to: encoder)
    }
}

/// Size multiplier for the island: 75 %–150 %.
public struct IslandScale: Hashable, Sendable, Comparable {
    public static let allowedRange: ClosedRange<Double> = 0.75...1.5

    public let value: Double

    public init(_ value: Double) throws(ValidationError) {
        guard value.isFinite else { throw .notFinite(field: "appearance.scale") }
        guard Self.allowedRange.contains(value) else {
            throw .outOfRange(
                field: "appearance.scale",
                value: value,
                lowerBound: Self.allowedRange.lowerBound,
                upperBound: Self.allowedRange.upperBound
            )
        }
        self.value = value
    }

    private init(trusted value: Double) {
        self.value = value
    }

    public static let standard = IslandScale(trusted: 1)

    public static func < (lhs: IslandScale, rhs: IslandScale) -> Bool { lhs.value < rhs.value }
}

extension IslandScale: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try Double(from: decoder)
        do throws(ValidationError) {
            self = try IslandScale(raw)
        } catch {
            throw error.decodingError(at: decoder.codingPath)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        try value.encode(to: encoder)
    }
}

/// How long the island opens by itself when a session finishes or needs attention. Zero disables it.
public struct PeekDuration: Hashable, Sendable, Comparable {
    public static let allowedSeconds: ClosedRange<Int> = 0...30

    public let seconds: Int

    public init(seconds: Int) throws(ValidationError) {
        guard Self.allowedSeconds.contains(seconds) else {
            throw .outOfRange(
                field: "alerts.peekDuration",
                value: Double(seconds),
                lowerBound: Double(Self.allowedSeconds.lowerBound),
                upperBound: Double(Self.allowedSeconds.upperBound)
            )
        }
        self.seconds = seconds
    }

    private init(trustedSeconds: Int) {
        seconds = trustedSeconds
    }

    public static let standard = PeekDuration(trustedSeconds: 5)
    public static let disabled = PeekDuration(trustedSeconds: 0)

    public var isEnabled: Bool { seconds > 0 }

    public static func < (lhs: PeekDuration, rhs: PeekDuration) -> Bool { lhs.seconds < rhs.seconds }
}

extension PeekDuration: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try Int(from: decoder)
        do throws(ValidationError) {
            self = try PeekDuration(seconds: raw)
        } catch {
            throw error.decodingError(at: decoder.codingPath)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        try seconds.encode(to: encoder)
    }
}

/// Where the colour bands switch: ample below `watch`, watch below `critical`.
public struct BandThresholds: Hashable, Sendable {
    public let watch: Percentage
    public let critical: Percentage

    public init(watch: Percentage, critical: Percentage) throws(ValidationError) {
        guard watch.value >= 1, critical.value <= 100 else {
            throw .outOfRange(field: "appearance.bands", value: watch.value, lowerBound: 1, upperBound: 100)
        }
        guard watch < critical else {
            throw .inconsistent(field: "appearance.bands", reason: "watch threshold must be below critical")
        }
        self.watch = watch
        self.critical = critical
    }

    private init(trustedWatch watch: Double, critical: Double) {
        // Both literals are within 0...100, so the validating initialiser cannot fail.
        self.watch = (try? Percentage(validating: watch)) ?? .zero
        self.critical = (try? Percentage(validating: critical)) ?? .full
    }

    public static let standard = BandThresholds(trustedWatch: 50, critical: 80)
}

extension BandThresholds: Codable {
    private enum CodingKeys: String, CodingKey {
        case watch, critical
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let watch = try container.decode(Percentage.self, forKey: .watch)
        let critical = try container.decode(Percentage.self, forKey: .critical)
        do throws(ValidationError) {
            self = try BandThresholds(watch: watch, critical: critical)
        } catch {
            throw error.decodingError(at: container.codingPath)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(watch, forKey: .watch)
        try container.encode(critical, forKey: .critical)
    }
}

/// Usage levels that trigger a notification: up to six distinct values within 1–100, kept sorted.
public struct AlertThresholds: Hashable, Sendable {
    public static let maximumCount = 6

    public let values: [Percentage]

    public init(_ values: [Percentage]) throws(ValidationError) {
        guard values.count <= Self.maximumCount else {
            throw .tooLong(field: "alerts.thresholds", length: values.count, maximum: Self.maximumCount)
        }
        for value in values where value.value < 1 || value.value > 100 {
            throw .outOfRange(field: "alerts.thresholds", value: value.value, lowerBound: 1, upperBound: 100)
        }
        let sorted = values.sorted()
        for (lower, upper) in zip(sorted, sorted.dropFirst()) where lower == upper {
            throw .duplicate(field: "alerts.thresholds", value: String(lower.value))
        }
        self.values = sorted
    }

    public static let standard: AlertThresholds = {
        let values = [80.0, 100.0].compactMap { try? Percentage(validating: $0) }
        return (try? AlertThresholds(values)) ?? AlertThresholds(uncheckedEmpty: ())
    }()

    private init(uncheckedEmpty: Void) {
        values = []
    }

    /// The highest threshold passed when usage moves from `previous` to `current`.
    public func highestCrossed(from previous: Percentage, to current: Percentage) -> Percentage? {
        values.last { previous < $0 && $0 <= current }
    }
}

extension AlertThresholds: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try [Percentage](from: decoder)
        do throws(ValidationError) {
            self = try AlertThresholds(raw)
        } catch {
            throw error.decodingError(at: decoder.codingPath)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        try values.encode(to: encoder)
    }
}

public struct AppearanceSettings: Hashable, Sendable {
    public var edge: ScreenEdge
    public var offset: EdgeOffset
    public var style: IslandStyle
    public var surface: IslandSurface
    public var visibility: IslandVisibility
    public var scale: IslandScale
    public var resetTextStyle: ResetTextStyle
    public var showsSecondaryRing: Bool
    public var showsPace: Bool
    public var hidesInFullScreen: Bool
    public var bands: BandThresholds
    public var openTrigger: IslandOpenTrigger
    public var emailVisibility: EmailVisibility
    /// The glass takes a faint band tint and rim light as usage becomes urgent.
    public var glowsWithUrgency: Bool
    /// The only group the island shows; `nil` shows every group.
    public var railGroupFilter: AccountGroupID?
    /// Island (default) or floating card; the menu bar item always stays.
    public var presentationStyle: PresentationStyle
    /// Rings unwind and flash green when a limit resets.
    public var celebratesResets: Bool
    /// A faint arc shows where usage lands by the reset at the current pace.
    public var showsForecast: Bool
    /// Island and card snap to targets while dragged (hold ⌘ to place freely).
    public var snapsWhileDragging: Bool
    /// Snapping plays trackpad haptics (island and card).
    public var playsHaptics: Bool
    public var notchFusion: NotchFusionMode
    public var islandDisplayPolicy: DisplayPolicy
    /// The display the island was last dropped on (`nil`: the main display).
    public var islandDisplay: RememberedDisplay?
    public var floatingCard: FloatingCardSettings
    /// What the deck shows: the essentials (the default) or everything.
    public var deckDetail: DeckDetail

    public init(
        edge: ScreenEdge = .top,
        offset: EdgeOffset = .center,
        style: IslandStyle = .attached,
        surface: IslandSurface = .glass,
        visibility: IslandVisibility = .always,
        scale: IslandScale = .standard,
        resetTextStyle: ResetTextStyle = .countdown,
        showsSecondaryRing: Bool = true,
        showsPace: Bool = true,
        hidesInFullScreen: Bool = true,
        bands: BandThresholds = .standard,
        openTrigger: IslandOpenTrigger = .hover,
        emailVisibility: EmailVisibility = .hidden,
        glowsWithUrgency: Bool = true,
        railGroupFilter: AccountGroupID? = nil,
        presentationStyle: PresentationStyle = .island,
        celebratesResets: Bool = true,
        showsForecast: Bool = true,
        snapsWhileDragging: Bool = true,
        playsHaptics: Bool = true,
        notchFusion: NotchFusionMode = .automatic,
        islandDisplayPolicy: DisplayPolicy = .whereLeft,
        islandDisplay: RememberedDisplay? = nil,
        floatingCard: FloatingCardSettings = FloatingCardSettings(),
        deckDetail: DeckDetail = .essentials
    ) {
        self.edge = edge
        self.offset = offset
        self.style = style
        self.surface = surface
        self.visibility = visibility
        self.scale = scale
        self.resetTextStyle = resetTextStyle
        self.showsSecondaryRing = showsSecondaryRing
        self.showsPace = showsPace
        self.hidesInFullScreen = hidesInFullScreen
        self.bands = bands
        self.openTrigger = openTrigger
        self.emailVisibility = emailVisibility
        self.glowsWithUrgency = glowsWithUrgency
        self.railGroupFilter = railGroupFilter
        self.presentationStyle = presentationStyle
        self.celebratesResets = celebratesResets
        self.showsForecast = showsForecast
        self.snapsWhileDragging = snapsWhileDragging
        self.playsHaptics = playsHaptics
        self.notchFusion = notchFusion
        self.islandDisplayPolicy = islandDisplayPolicy
        self.islandDisplay = islandDisplay
        self.floatingCard = floatingCard
        self.deckDetail = deckDetail
    }
}

extension AppearanceSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case edge, offset, style, surface, visibility, scale, resetTextStyle, showsSecondaryRing, showsPace, hidesInFullScreen
        case bands
        case openTrigger, emailVisibility, glowsWithUrgency, railGroupFilter
        case presentationStyle, celebratesResets, showsForecast, snapsWhileDragging, playsHaptics, notchFusion
        case islandDisplayPolicy, islandDisplay, floatingCard, deckDetail
    }

    /// Every key is lenient: missing or null takes the default silently, an unusable value (unknown case, failed
    /// validation, wrong type) takes the default with a repair note. Only a value that is not an object fails.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let report = decoder.settingsDecodeReport
        let defaults = AppearanceSettings()
        edge = container.decodeLenient(ScreenEdge.self, forKey: .edge, default: defaults.edge, report: report)
        offset = container.decodeLenient(EdgeOffset.self, forKey: .offset, default: defaults.offset, report: report)
        style = container.decodeLenient(IslandStyle.self, forKey: .style, default: defaults.style, report: report)
        surface = container.decodeLenient(IslandSurface.self, forKey: .surface, default: defaults.surface, report: report)
        visibility = container.decodeLenient(IslandVisibility.self, forKey: .visibility, default: defaults.visibility, report: report)
        scale = container.decodeLenient(IslandScale.self, forKey: .scale, default: defaults.scale, report: report)
        resetTextStyle = container.decodeLenient(
            ResetTextStyle.self,
            forKey: .resetTextStyle,
            default: defaults.resetTextStyle,
            report: report
        )
        showsSecondaryRing = container.decodeLenient(
            Bool.self,
            forKey: .showsSecondaryRing,
            default: defaults.showsSecondaryRing,
            report: report
        )
        showsPace = container.decodeLenient(Bool.self, forKey: .showsPace, default: defaults.showsPace, report: report)
        hidesInFullScreen = container.decodeLenient(
            Bool.self,
            forKey: .hidesInFullScreen,
            default: defaults.hidesInFullScreen,
            report: report
        )
        bands = container.decodeLenient(BandThresholds.self, forKey: .bands, default: defaults.bands, report: report)
        openTrigger = container.decodeLenient(
            IslandOpenTrigger.self,
            forKey: .openTrigger,
            default: defaults.openTrigger,
            report: report
        )
        emailVisibility = container.decodeLenient(
            EmailVisibility.self,
            forKey: .emailVisibility,
            default: defaults.emailVisibility,
            report: report
        )
        glowsWithUrgency = container.decodeLenient(
            Bool.self,
            forKey: .glowsWithUrgency,
            default: defaults.glowsWithUrgency,
            report: report
        )
        railGroupFilter = container.decodeLenientIfPresent(AccountGroupID.self, forKey: .railGroupFilter, report: report)
        presentationStyle = container.decodeLenient(
            PresentationStyle.self,
            forKey: .presentationStyle,
            default: defaults.presentationStyle,
            report: report
        )
        celebratesResets = container.decodeLenient(
            Bool.self,
            forKey: .celebratesResets,
            default: defaults.celebratesResets,
            report: report
        )
        showsForecast = container.decodeLenient(Bool.self, forKey: .showsForecast, default: defaults.showsForecast, report: report)
        snapsWhileDragging = container.decodeLenient(
            Bool.self,
            forKey: .snapsWhileDragging,
            default: defaults.snapsWhileDragging,
            report: report
        )
        playsHaptics = container.decodeLenient(Bool.self, forKey: .playsHaptics, default: defaults.playsHaptics, report: report)
        notchFusion = container.decodeLenient(
            NotchFusionMode.self,
            forKey: .notchFusion,
            default: defaults.notchFusion,
            report: report
        )
        islandDisplayPolicy = container.decodeLenient(
            DisplayPolicy.self,
            forKey: .islandDisplayPolicy,
            default: defaults.islandDisplayPolicy,
            report: report
        )
        islandDisplay = container.decodeLenientIfPresent(RememberedDisplay.self, forKey: .islandDisplay, report: report)
        floatingCard = container.decodeLenient(
            FloatingCardSettings.self,
            forKey: .floatingCard,
            default: defaults.floatingCard,
            report: report
        )
        deckDetail = container.decodeLenient(DeckDetail.self, forKey: .deckDetail, default: defaults.deckDetail, report: report)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(edge, forKey: .edge)
        try container.encode(offset, forKey: .offset)
        try container.encode(style, forKey: .style)
        try container.encode(surface, forKey: .surface)
        try container.encode(visibility, forKey: .visibility)
        try container.encode(scale, forKey: .scale)
        try container.encode(resetTextStyle, forKey: .resetTextStyle)
        try container.encode(showsSecondaryRing, forKey: .showsSecondaryRing)
        try container.encode(showsPace, forKey: .showsPace)
        try container.encode(hidesInFullScreen, forKey: .hidesInFullScreen)
        try container.encode(bands, forKey: .bands)
        try container.encode(openTrigger, forKey: .openTrigger)
        try container.encode(emailVisibility, forKey: .emailVisibility)
        try container.encode(glowsWithUrgency, forKey: .glowsWithUrgency)
        try container.encodeIfPresent(railGroupFilter, forKey: .railGroupFilter)
        try container.encode(presentationStyle, forKey: .presentationStyle)
        try container.encode(celebratesResets, forKey: .celebratesResets)
        try container.encode(showsForecast, forKey: .showsForecast)
        try container.encode(snapsWhileDragging, forKey: .snapsWhileDragging)
        try container.encode(playsHaptics, forKey: .playsHaptics)
        try container.encode(notchFusion, forKey: .notchFusion)
        try container.encode(islandDisplayPolicy, forKey: .islandDisplayPolicy)
        try container.encodeIfPresent(islandDisplay, forKey: .islandDisplay)
        try container.encode(floatingCard, forKey: .floatingCard)
        try container.encode(deckDetail, forKey: .deckDetail)
    }
}

public struct AlertSettings: Hashable, Sendable {
    public var thresholds: AlertThresholds
    public var notifiesOnReset: Bool
    public var notifiesOnSessionFinished: Bool
    public var notifiesOnSessionWaiting: Bool
    public var playsSounds: Bool
    public var peekDuration: PeekDuration
    /// "Agent finished" is skipped for turns shorter than this.
    public var minimumTurnForFinishedAlert: TurnAlertThreshold
    /// "Needs attention" notifications are withdrawn once the session stops waiting.
    public var withdrawsResolvedAlerts: Bool
    /// Alerts arriving in a burst are delivered as one summary.
    public var coalescesBursts: Bool

    public init(
        thresholds: AlertThresholds = .standard,
        notifiesOnReset: Bool = true,
        notifiesOnSessionFinished: Bool = true,
        notifiesOnSessionWaiting: Bool = true,
        playsSounds: Bool = true,
        peekDuration: PeekDuration = .standard,
        minimumTurnForFinishedAlert: TurnAlertThreshold = .standard,
        withdrawsResolvedAlerts: Bool = true,
        coalescesBursts: Bool = true
    ) {
        self.thresholds = thresholds
        self.notifiesOnReset = notifiesOnReset
        self.notifiesOnSessionFinished = notifiesOnSessionFinished
        self.notifiesOnSessionWaiting = notifiesOnSessionWaiting
        self.playsSounds = playsSounds
        self.peekDuration = peekDuration
        self.minimumTurnForFinishedAlert = minimumTurnForFinishedAlert
        self.withdrawsResolvedAlerts = withdrawsResolvedAlerts
        self.coalescesBursts = coalescesBursts
    }
}

extension AlertSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case thresholds, notifiesOnReset, notifiesOnSessionFinished, notifiesOnSessionWaiting, playsSounds
        case peekDuration
        case minimumTurnForFinishedAlert, withdrawsResolvedAlerts, coalescesBursts
    }

    /// Every key is lenient (see `AppearanceSettings.init(from:)`).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let report = decoder.settingsDecodeReport
        let defaults = AlertSettings()
        thresholds = container.decodeLenient(AlertThresholds.self, forKey: .thresholds, default: defaults.thresholds, report: report)
        notifiesOnReset = container.decodeLenient(Bool.self, forKey: .notifiesOnReset, default: defaults.notifiesOnReset, report: report)
        notifiesOnSessionFinished = container.decodeLenient(
            Bool.self,
            forKey: .notifiesOnSessionFinished,
            default: defaults.notifiesOnSessionFinished,
            report: report
        )
        notifiesOnSessionWaiting = container.decodeLenient(
            Bool.self,
            forKey: .notifiesOnSessionWaiting,
            default: defaults.notifiesOnSessionWaiting,
            report: report
        )
        playsSounds = container.decodeLenient(Bool.self, forKey: .playsSounds, default: defaults.playsSounds, report: report)
        peekDuration = container.decodeLenient(PeekDuration.self, forKey: .peekDuration, default: defaults.peekDuration, report: report)
        minimumTurnForFinishedAlert = container.decodeLenient(
            TurnAlertThreshold.self,
            forKey: .minimumTurnForFinishedAlert,
            default: defaults.minimumTurnForFinishedAlert,
            report: report
        )
        withdrawsResolvedAlerts = container.decodeLenient(
            Bool.self,
            forKey: .withdrawsResolvedAlerts,
            default: defaults.withdrawsResolvedAlerts,
            report: report
        )
        coalescesBursts = container.decodeLenient(Bool.self, forKey: .coalescesBursts, default: defaults.coalescesBursts, report: report)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(thresholds, forKey: .thresholds)
        try container.encode(notifiesOnReset, forKey: .notifiesOnReset)
        try container.encode(notifiesOnSessionFinished, forKey: .notifiesOnSessionFinished)
        try container.encode(notifiesOnSessionWaiting, forKey: .notifiesOnSessionWaiting)
        try container.encode(playsSounds, forKey: .playsSounds)
        try container.encode(peekDuration, forKey: .peekDuration)
        try container.encode(minimumTurnForFinishedAlert, forKey: .minimumTurnForFinishedAlert)
        try container.encode(withdrawsResolvedAlerts, forKey: .withdrawsResolvedAlerts)
        try container.encode(coalescesBursts, forKey: .coalescesBursts)
    }
}

public struct GeneralSettings: Hashable, Sendable {
    public var launchesAtLogin: Bool
    /// The system-wide shortcut that toggles the deck.
    public var globalShortcut: GlobalShortcut
    /// A usage snapshot is written for the desktop widget.
    public var exportsWidgetData: Bool
    /// How the medium and large widgets arrange the limits: rings (the default) or the wide strip. The snapshot
    /// carries it to the extension; settings written before the key existed, and unknown values, mean rings.
    public var widgetLayout: WidgetLayout
    /// The interface language. Settings written before it existed, and unknown values, mean English.
    public var language: LanguagePreference
    public var energyMode: EnergyMode
    public var historyRetention: HistoryRetention
    /// Settings written before the key existed count as completed; a fresh install starts at `notStarted`.
    public var onboarding: OnboardingState
    /// Opt-in check of the vendors' public status pages (the app's only network access).
    public var showsVendorStatus: Bool
    /// The version that last launched with these settings, for upgrade bookkeeping.
    public var lastLaunchedVersion: AppVersion?

    public init(
        launchesAtLogin: Bool = false,
        globalShortcut: GlobalShortcut = .controlOptionCommandU,
        exportsWidgetData: Bool = true,
        widgetLayout: WidgetLayout = .rings,
        language: LanguagePreference = .default,
        energyMode: EnergyMode = .automatic,
        historyRetention: HistoryRetention = .standard,
        onboarding: OnboardingState = .completed,
        showsVendorStatus: Bool = false,
        lastLaunchedVersion: AppVersion? = nil
    ) {
        self.launchesAtLogin = launchesAtLogin
        self.globalShortcut = globalShortcut
        self.exportsWidgetData = exportsWidgetData
        self.widgetLayout = widgetLayout
        self.language = language
        self.energyMode = energyMode
        self.historyRetention = historyRetention
        self.onboarding = onboarding
        self.showsVendorStatus = showsVendorStatus
        self.lastLaunchedVersion = lastLaunchedVersion
    }
}

extension GeneralSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case launchesAtLogin, globalShortcut, exportsWidgetData, widgetLayout, language
        case energyMode, historyRetention, onboarding, showsVendorStatus, lastLaunchedVersion
    }

    /// Every key is lenient (see `AppearanceSettings.init(from:)`).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let report = decoder.settingsDecodeReport
        let defaults = GeneralSettings()
        launchesAtLogin = container.decodeLenient(Bool.self, forKey: .launchesAtLogin, default: defaults.launchesAtLogin, report: report)
        globalShortcut = container.decodeLenient(
            GlobalShortcut.self,
            forKey: .globalShortcut,
            default: defaults.globalShortcut,
            report: report
        )
        exportsWidgetData = container.decodeLenient(
            Bool.self,
            forKey: .exportsWidgetData,
            default: defaults.exportsWidgetData,
            report: report
        )
        widgetLayout = container.decodeLenient(WidgetLayout.self, forKey: .widgetLayout, default: defaults.widgetLayout, report: report)
        language = container.decodeLenient(LanguagePreference.self, forKey: .language, default: defaults.language, report: report)
        energyMode = container.decodeLenient(EnergyMode.self, forKey: .energyMode, default: defaults.energyMode, report: report)
        historyRetention = container.decodeLenient(
            HistoryRetention.self,
            forKey: .historyRetention,
            default: defaults.historyRetention,
            report: report
        )
        onboarding = container.decodeLenient(OnboardingState.self, forKey: .onboarding, default: defaults.onboarding, report: report)
        showsVendorStatus = container.decodeLenient(
            Bool.self,
            forKey: .showsVendorStatus,
            default: defaults.showsVendorStatus,
            report: report
        )
        lastLaunchedVersion = container.decodeLenientIfPresent(AppVersion.self, forKey: .lastLaunchedVersion, report: report)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(launchesAtLogin, forKey: .launchesAtLogin)
        try container.encode(globalShortcut, forKey: .globalShortcut)
        try container.encode(exportsWidgetData, forKey: .exportsWidgetData)
        try container.encode(widgetLayout, forKey: .widgetLayout)
        try container.encode(language, forKey: .language)
        try container.encode(energyMode, forKey: .energyMode)
        try container.encode(historyRetention, forKey: .historyRetention)
        try container.encode(onboarding, forKey: .onboarding)
        try container.encode(showsVendorStatus, forKey: .showsVendorStatus)
        try container.encodeIfPresent(lastLaunchedVersion, forKey: .lastLaunchedVersion)
    }
}

/// Everything the user can configure. Account and group invariants are enforced on every change.
public struct AppSettings: Hashable, Sendable {
    public static let currentSchemaVersion = 1
    public static let maximumAccounts = 16
    public static let maximumGroups = 8

    public private(set) var accounts: [AccountProfile]
    /// Unique ids and names (case-insensitive); every account's `groupID` refers to one of them.
    public private(set) var groups: [AccountGroup]
    public var appearance: AppearanceSettings
    public var alerts: AlertSettings
    public var general: GeneralSettings

    /// Validates groups first, then accounts and their group references. A rail group filter naming a group
    /// that does not exist is dropped, so the island shows every group.
    public init(
        accounts: [AccountProfile],
        groups: [AccountGroup] = [],
        appearance: AppearanceSettings = AppearanceSettings(),
        alerts: AlertSettings = AlertSettings(),
        general: GeneralSettings = GeneralSettings()
    ) throws(ValidationError) {
        try Self.validate(groups: groups)
        try Self.validate(accounts: accounts, groups: groups)
        self.accounts = accounts
        self.groups = groups
        self.appearance = appearance
        self.alerts = alerts
        self.general = general
        dropUnknownGroupFilter()
        dropUnknownCardAccount()
    }

    public static let empty: AppSettings = {
        do {
            return try AppSettings(accounts: [])
        } catch {
            preconditionFailure("an empty account list is always valid: \(error)")
        }
    }()

    public func replacingAccounts(_ accounts: [AccountProfile]) throws(ValidationError) -> AppSettings {
        var copy = self
        try Self.validate(accounts: accounts, groups: groups)
        copy.accounts = accounts
        copy.dropUnknownCardAccount()
        return copy
    }

    /// Replaces the group list. Accounts of removed groups become ungrouped, and a rail filter on a
    /// removed group is cleared.
    public func replacingGroups(_ groups: [AccountGroup]) throws(ValidationError) -> AppSettings {
        try Self.validate(groups: groups)
        var copy = self
        copy.groups = groups
        copy.accounts = try Self.ungroupingUnknown(accounts, groups: groups)
        copy.dropUnknownGroupFilter()
        return copy
    }

    public func account(_ id: AccountID) -> AccountProfile? {
        accounts.first { $0.id == id }
    }

    public func group(_ id: AccountGroupID) -> AccountGroup? {
        groups.first { $0.id == id }
    }

    private mutating func dropUnknownGroupFilter() {
        if let filter = appearance.railGroupFilter, group(filter) == nil {
            appearance.railGroupFilter = nil
        }
    }

    /// A card fixed to an account that no longer exists follows the most urgent account again.
    private mutating func dropUnknownCardAccount() {
        if case .fixed(let id) = appearance.floatingCard.accountSelection, account(id) == nil {
            appearance.floatingCard.accountSelection = .mostUrgent
        }
    }

    private static func ungroupingUnknown(
        _ accounts: [AccountProfile],
        groups: [AccountGroup]
    ) throws(ValidationError) -> [AccountProfile] {
        let known = Set(groups.map(\.id))
        var result: [AccountProfile] = []
        result.reserveCapacity(accounts.count)
        for account in accounts {
            if let groupID = account.groupID, !known.contains(groupID) {
                result.append(try account.updated(groupID: .some(nil)))
            } else {
                result.append(account)
            }
        }
        return result
    }

    private static func validate(groups: [AccountGroup]) throws(ValidationError) {
        guard groups.count <= maximumGroups else {
            throw .tooLong(field: "groups", length: groups.count, maximum: maximumGroups)
        }
        var ids = Set<AccountGroupID>()
        var names = Set<String>()
        for group in groups {
            guard ids.insert(group.id).inserted else {
                throw .duplicate(field: "groups.id", value: group.id.description)
            }
            let folded = group.name.value.folding(options: [.caseInsensitive], locale: nil)
            guard names.insert(folded).inserted else {
                throw .duplicate(field: "groups.name", value: group.name.value)
            }
        }
    }

    private static func validate(accounts: [AccountProfile], groups: [AccountGroup]) throws(ValidationError) {
        guard accounts.count <= maximumAccounts else {
            throw .tooLong(field: "accounts", length: accounts.count, maximum: maximumAccounts)
        }
        let knownGroups = Set(groups.map(\.id))
        var ids = Set<AccountID>()
        var locations = Set<String>()
        for account in accounts {
            guard ids.insert(account.id).inserted else {
                throw .duplicate(field: "accounts.id", value: account.id.description)
            }
            let location = "\(account.provider.rawValue):\(account.directory.path)"
            guard locations.insert(location).inserted else {
                throw .duplicate(field: "accounts.directory", value: account.directory.path)
            }
            if let groupID = account.groupID, !knownGroups.contains(groupID) {
                throw .inconsistent(field: "accounts.groupID", reason: "unknown group \(groupID)")
            }
        }
    }
}

extension AppSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, accounts, groups, appearance, alerts, general
    }

    /// Repairs instead of failing: unusable accounts and groups are dropped one by one; duplicate group ids or names
    /// and duplicate account ids or profile locations keep the first; more than 16 accounts or 8 groups keep the
    /// first ones (each repair is noted); accounts referring to a missing group are loaded ungrouped. Every section
    /// is lenient. `schemaVersion` is not checked here: a newer file decodes its known keys (see `decodeFile`). Only a
    /// top level that is not an object fails.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let report = decoder.settingsDecodeReport
        let groups = Self.repairedGroups(container.decodeLossyArray(AccountGroup.self, forKey: .groups, report: report), report: report)
        let accounts = Self.repairedAccounts(
            container.decodeLossyArray(AccountProfile.self, forKey: .accounts, report: report),
            report: report
        )
        let appearance = container.decodeLenient(AppearanceSettings.self, forKey: .appearance, default: AppearanceSettings(), report: report)
        let alerts = container.decodeLenient(AlertSettings.self, forKey: .alerts, default: AlertSettings(), report: report)
        let general = container.decodeLenient(GeneralSettings.self, forKey: .general, default: GeneralSettings(), report: report)
        do throws(ValidationError) {
            self = try AppSettings(
                accounts: try Self.ungroupingUnknown(accounts, groups: groups),
                groups: groups,
                appearance: appearance,
                alerts: alerts,
                general: general
            )
        } catch {
            throw error.decodingError(at: container.codingPath)
        }
    }

    private static func repairedGroups(_ decoded: [AccountGroup], report: SettingsDecodeReport?) -> [AccountGroup] {
        var ids = Set<AccountGroupID>()
        var names = Set<String>()
        var groups: [AccountGroup] = []
        for group in decoded {
            guard ids.insert(group.id).inserted else {
                report?.note("groups.id")
                continue
            }
            guard names.insert(group.name.value.folding(options: [.caseInsensitive], locale: nil)).inserted else {
                report?.note("groups.name")
                continue
            }
            groups.append(group)
        }
        if groups.count > maximumGroups {
            report?.note("groups")
            groups.removeLast(groups.count - maximumGroups)
        }
        return groups
    }

    private static func repairedAccounts(_ decoded: [AccountProfile], report: SettingsDecodeReport?) -> [AccountProfile] {
        var ids = Set<AccountID>()
        var locations = Set<String>()
        var accounts: [AccountProfile] = []
        for account in decoded {
            guard ids.insert(account.id).inserted else {
                report?.note("accounts.id")
                continue
            }
            guard locations.insert("\(account.provider.rawValue):\(account.directory.path)").inserted else {
                report?.note("accounts.directory")
                continue
            }
            accounts.append(account)
        }
        if accounts.count > maximumAccounts {
            report?.note("accounts")
            accounts.removeLast(accounts.count - maximumAccounts)
        }
        return accounts
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(accounts, forKey: .accounts)
        try container.encode(groups, forKey: .groups)
        try container.encode(appearance, forKey: .appearance)
        try container.encode(alerts, forKey: .alerts)
        try container.encode(general, forKey: .general)
    }
}
