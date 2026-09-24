import Foundation

/// The floating card's colour theme.
public enum CardTheme: String, Codable, Sendable, CaseIterable, Identifiable {
    case graphite
    case liquidGlass
    case midnight
    case light

    public var id: String { rawValue }
}

/// The expanded card's size.
public enum CardSize: String, Codable, Sendable, CaseIterable, Identifiable {
    case compact
    case regular
    /// A wide, short bar: the binding week on the left, one chip per limit window on the right.
    case strip

    public var id: String { rawValue }
}

/// Which accounts the Strip card covers.
///
/// The other sizes always show one account; the strip can merge the windows of several, so it has a scope of its own.
public enum CardStripScope: String, Codable, Sendable, CaseIterable, Identifiable {
    /// The account the card follows (`FloatingCardSettings.accountSelection`), as the other sizes do (default).
    case selectedAccount
    /// Every enabled Claude account.
    case claude
    /// Every enabled Codex account.
    case codex
    /// Every enabled account.
    case allAccounts

    public var id: String { rawValue }
}

/// What the card's third tile shows.
public enum CardThirdTile: String, Codable, Sendable, CaseIterable, Identifiable {
    case weeklyReset
    case sessionWindow
    case agents

    public var id: String { rawValue }
}

/// Which account the card follows.
public enum CardAccountSelection: Hashable, Sendable {
    /// The account closest to a limit (default).
    case mostUrgent
    /// One account. `AppSettings` resets it to `mostUrgent` when that account is removed.
    case fixed(AccountID)
}

extension CardAccountSelection: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, id
    }

    private enum Kind: String, Codable {
        case mostUrgent, fixed
    }

    /// `{"kind": "mostUrgent"}` or `{"kind": "fixed", "id": "…"}`. Never fails: anything else decodes as
    /// `.mostUrgent` with a repair note.
    public init(from decoder: any Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(Kind.self, forKey: .kind) {
            case .mostUrgent:
                self = .mostUrgent
            case .fixed:
                self = .fixed(try container.decode(AccountID.self, forKey: .id))
            }
        } catch {
            decoder.settingsDecodeReport?.note(SettingsDecodeReport.path(decoder.codingPath))
            self = .mostUrgent
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .mostUrgent:
            try container.encode(Kind.mostUrgent, forKey: .kind)
        case .fixed(let id):
            try container.encode(Kind.fixed, forKey: .kind)
            try container.encode(id, forKey: .id)
        }
    }
}

/// The point of the card that stays put: the corner, edge midpoint or centre nearest the display's matching point.
/// Card and pill align the same point, so minimizing and restoring never drifts.
public enum CardAnchor: String, Codable, Sendable, CaseIterable {
    case topLeading, top, topTrailing
    case leading, center, trailing
    case bottomLeading, bottom, bottomTrailing
}

/// A fraction within 0…1.
public struct UnitInterval: Hashable, Sendable, Comparable {
    public let value: Double

    public init(_ value: Double) throws(ValidationError) {
        guard value.isFinite else { throw .notFinite(field: "unitInterval") }
        guard (0...1).contains(value) else {
            throw .outOfRange(field: "unitInterval", value: value, lowerBound: 0, upperBound: 1)
        }
        self.value = value
    }

    private init(trusted value: Double) {
        self.value = value
    }

    public static let zero = UnitInterval(trusted: 0)
    public static let half = UnitInterval(trusted: 0.5)
    public static let one = UnitInterval(trusted: 1)

    /// Clamps any finite value into range; a non-finite value becomes 0.5.
    public static func clamped(_ value: Double) -> UnitInterval {
        UnitInterval(trusted: value.isFinite ? min(max(value, 0), 1) : 0.5)
    }

    public static func < (lhs: UnitInterval, rhs: UnitInterval) -> Bool { lhs.value < rhs.value }
}

extension UnitInterval: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try Double(from: decoder)
        do throws(ValidationError) {
            self = try UnitInterval(raw)
        } catch {
            throw error.decodingError(at: decoder.codingPath)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        try value.encode(to: encoder)
    }
}

/// Where the card sits on one display.
public struct CardPlacement: Hashable, Sendable {
    public let displayID: DisplayID
    public let anchor: CardAnchor
    /// Exactly on the anchor's snap target; `x` and `y` are then ignored when resolving the frame.
    public let snapped: Bool
    /// The anchor point as fractions of the display's inset visible frame (0 = leading/top, 1 = trailing/bottom).
    public let x: UnitInterval
    public let y: UnitInterval

    public init(displayID: DisplayID, anchor: CardAnchor, snapped: Bool, x: UnitInterval, y: UnitInterval) {
        self.displayID = displayID
        self.anchor = anchor
        self.snapped = snapped
        self.x = x
        self.y = y
    }
}

extension CardPlacement: Codable {
    private enum CodingKeys: String, CodingKey {
        case displayID, anchor, snapped, x, y
    }

    /// The display id and anchor are required. Fractions slightly out of range (rounding, a hand edit) are clamped with
    /// a repair note; a missing or non-numeric fraction fails the placement.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let report = decoder.settingsDecodeReport
        displayID = try container.decode(DisplayID.self, forKey: .displayID)
        anchor = try container.decode(CardAnchor.self, forKey: .anchor)
        snapped = container.decodeLenient(Bool.self, forKey: .snapped, default: false, report: report)
        x = try Self.fraction(in: container, forKey: .x, report: report)
        y = try Self.fraction(in: container, forKey: .y, report: report)
    }

    private static func fraction(
        in container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys,
        report: SettingsDecodeReport?
    ) throws -> UnitInterval {
        let raw = try container.decode(Double.self, forKey: key)
        let clamped = UnitInterval.clamped(raw)
        if clamped.value != raw {
            report?.note(SettingsDecodeReport.path(container.codingPath + [key]))
        }
        return clamped
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(displayID, forKey: .displayID)
        try container.encode(anchor, forKey: .anchor)
        try container.encode(snapped, forKey: .snapped)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
    }
}

/// The card's remembered placement per display: most recent first, at most eight, one per display.
public struct FloatingCardPlacements: Hashable, Sendable {
    public static let maximumCount = 8
    public static let empty = FloatingCardPlacements()

    public private(set) var byDisplay: [CardPlacement]
    /// The display the card is on now.
    public var current: DisplayID?
    /// The display the card was moved away from because it disconnected; it returns there on reconnect.
    public var displacedFrom: DisplayID?

    /// Keeps the first placement per display and at most `maximumCount`.
    public init(byDisplay: [CardPlacement] = [], current: DisplayID? = nil, displacedFrom: DisplayID? = nil) {
        self.byDisplay = Self.normalized(byDisplay)
        self.current = current
        self.displacedFrom = displacedFrom
    }

    public func placement(for id: DisplayID) -> CardPlacement? {
        byDisplay.first { $0.displayID == id }
    }

    /// Makes `placement` the most recent one: replaces that display's previous placement and drops the oldest beyond eight.
    public mutating func remember(_ placement: CardPlacement) {
        byDisplay = Self.normalized([placement] + byDisplay)
    }

    private static func normalized(_ placements: [CardPlacement]) -> [CardPlacement] {
        var seen = Set<DisplayID>()
        var result: [CardPlacement] = []
        for placement in placements where result.count < maximumCount && seen.insert(placement.displayID).inserted {
            result.append(placement)
        }
        return result
    }
}

extension FloatingCardPlacements: Codable {
    private enum CodingKeys: String, CodingKey {
        case byDisplay, current, displacedFrom
    }

    /// Unusable placements are dropped; duplicates and placements beyond eight are removed with a repair note.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let report = decoder.settingsDecodeReport
        let placements = container.decodeLossyArray(CardPlacement.self, forKey: .byDisplay, report: report)
        self.init(
            byDisplay: placements,
            current: container.decodeLenientIfPresent(DisplayID.self, forKey: .current, report: report),
            displacedFrom: container.decodeLenientIfPresent(DisplayID.self, forKey: .displacedFrom, report: report)
        )
        if byDisplay.count != placements.count {
            report?.note(SettingsDecodeReport.path(container.codingPath + [CodingKeys.byDisplay]))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(byDisplay, forKey: .byDisplay)
        try container.encodeIfPresent(current, forKey: .current)
        try container.encodeIfPresent(displacedFrom, forKey: .displacedFrom)
    }
}

/// Everything the floating card remembers. Every key decodes leniently.
public struct FloatingCardSettings: Hashable, Sendable {
    public var theme: CardTheme
    public var size: CardSize
    public var accountSelection: CardAccountSelection
    public var thirdTile: CardThirdTile
    /// Which accounts the Strip size covers; the other sizes ignore it.
    public var stripScope: CardStripScope
    /// Shown as the pill.
    public var isMinimized: Bool
    /// Floats above other windows; otherwise sits just above the desktop icons.
    public var keepsAboveWindows: Bool
    public var displayPolicy: DisplayPolicy
    public var placements: FloatingCardPlacements
    public var hasShownCoachMark: Bool

    public init(
        theme: CardTheme = .graphite,
        size: CardSize = .regular,
        accountSelection: CardAccountSelection = .mostUrgent,
        thirdTile: CardThirdTile = .weeklyReset,
        stripScope: CardStripScope = .selectedAccount,
        isMinimized: Bool = false,
        keepsAboveWindows: Bool = true,
        displayPolicy: DisplayPolicy = .whereLeft,
        placements: FloatingCardPlacements = .empty,
        hasShownCoachMark: Bool = false
    ) {
        self.theme = theme
        self.size = size
        self.accountSelection = accountSelection
        self.thirdTile = thirdTile
        self.stripScope = stripScope
        self.isMinimized = isMinimized
        self.keepsAboveWindows = keepsAboveWindows
        self.displayPolicy = displayPolicy
        self.placements = placements
        self.hasShownCoachMark = hasShownCoachMark
    }
}

extension FloatingCardSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case theme, size, accountSelection, thirdTile, stripScope, isMinimized, keepsAboveWindows, displayPolicy
        case placements, hasShownCoachMark
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let report = decoder.settingsDecodeReport
        let defaults = FloatingCardSettings()
        theme = container.decodeLenient(CardTheme.self, forKey: .theme, default: defaults.theme, report: report)
        size = container.decodeLenient(CardSize.self, forKey: .size, default: defaults.size, report: report)
        accountSelection = container.decodeLenient(
            CardAccountSelection.self,
            forKey: .accountSelection,
            default: defaults.accountSelection,
            report: report
        )
        thirdTile = container.decodeLenient(CardThirdTile.self, forKey: .thirdTile, default: defaults.thirdTile, report: report)
        stripScope = container.decodeLenient(CardStripScope.self, forKey: .stripScope, default: defaults.stripScope, report: report)
        isMinimized = container.decodeLenient(Bool.self, forKey: .isMinimized, default: defaults.isMinimized, report: report)
        keepsAboveWindows = container.decodeLenient(
            Bool.self,
            forKey: .keepsAboveWindows,
            default: defaults.keepsAboveWindows,
            report: report
        )
        displayPolicy = container.decodeLenient(
            DisplayPolicy.self,
            forKey: .displayPolicy,
            default: defaults.displayPolicy,
            report: report
        )
        placements = container.decodeLenient(
            FloatingCardPlacements.self,
            forKey: .placements,
            default: defaults.placements,
            report: report
        )
        hasShownCoachMark = container.decodeLenient(
            Bool.self,
            forKey: .hasShownCoachMark,
            default: defaults.hasShownCoachMark,
            report: report
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(theme, forKey: .theme)
        try container.encode(size, forKey: .size)
        try container.encode(accountSelection, forKey: .accountSelection)
        try container.encode(thirdTile, forKey: .thirdTile)
        try container.encode(stripScope, forKey: .stripScope)
        try container.encode(isMinimized, forKey: .isMinimized)
        try container.encode(keepsAboveWindows, forKey: .keepsAboveWindows)
        try container.encode(displayPolicy, forKey: .displayPolicy)
        try container.encode(placements, forKey: .placements)
        try container.encode(hasShownCoachMark, forKey: .hasShownCoachMark)
    }
}
