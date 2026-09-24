import CodometerCore
import Foundation

/// A surface that can play a reset ceremony on its rings. Each plays a ceremony at most once.
public enum CeremonySurface: Hashable, Sendable, CaseIterable {
    case rail
    case deck
    case card
    case popover
}

/// One limit window's reset, waiting to be celebrated on the surfaces that show it.
public struct ResetCeremony: Hashable, Sendable, Identifiable {
    /// A ceremony can start this long after its reset was detected; a surface shown later plays nothing.
    public static let lifetime: TimeInterval = 60

    public let id: UUID
    public let event: WindowResetEvent
    /// The ring's fill before the reset (0…1): where the arc unwinds from.
    public let previousFraction: Double
    public let startedAt: Date
    public var playedOn: Set<CeremonySurface>

    public init(id: UUID = UUID(), event: WindowResetEvent, previousFraction: Double, startedAt: Date, playedOn: Set<CeremonySurface> = []) {
        self.id = id
        self.event = event
        self.previousFraction = previousFraction.isFinite ? min(max(previousFraction, 0), 1) : 0
        self.startedAt = startedAt
        self.playedOn = playedOn
    }

    /// When a surface can no longer start this ceremony.
    public var expiresAt: Date { startedAt.addingTimeInterval(Self.lifetime) }

    public func isAlive(at now: Date) -> Bool {
        now < expiresAt
    }
}

/// Resets waiting to be celebrated, one per limit window, plus when each account last reset (for "Just reset").
///
/// A value type held by `TrackerStore`. Entries expire on their own: `nextExpiry` tells the store when to `prune`, so
/// one sleeping task replaces any polling.
public struct CeremonyBoard: Hashable, Sendable {
    /// How long an account counts as "just reset" after its latest reset.
    public static let justResetDuration: TimeInterval = 600

    private struct Key: Hashable, Sendable {
        let accountID: AccountID
        let bucketID: String
        let windowID: String

        init(_ event: WindowResetEvent) {
            self.init(accountID: event.accountID, bucketID: event.bucketID, windowID: event.windowID)
        }

        init(accountID: AccountID, bucketID: String, windowID: String) {
            self.accountID = accountID
            self.bucketID = bucketID
            self.windowID = windowID
        }
    }

    private var ceremonies: [Key: ResetCeremony] = [:]
    /// The latest reset per account.
    private var lastResets: [AccountID: Date] = [:]

    public init() {}

    public var isEmpty: Bool { ceremonies.isEmpty && lastResets.isEmpty }

    /// The live ceremony of one window, if any.
    public func ceremony(accountID: AccountID, bucketID: String, windowID: String, now: Date) -> ResetCeremony? {
        guard let ceremony = ceremonies[Key(accountID: accountID, bucketID: bucketID, windowID: windowID)],
              ceremony.isAlive(at: now)
        else { return nil }
        return ceremony
    }

    /// Live ceremonies the surface has not played yet, oldest first.
    public func unplayed(on surface: CeremonySurface, now: Date) -> [ResetCeremony] {
        ceremonies.values
            .filter { $0.isAlive(at: now) && !$0.playedOn.contains(surface) }
            .sorted { lhs, rhs in lhs.startedAt == rhs.startedAt ? lhs.event.id < rhs.event.id : lhs.startedAt < rhs.startedAt }
    }

    /// When the account's latest reset was detected, while that was at most `justResetDuration` ago.
    public func justReset(accountID: AccountID, now: Date) -> Date? {
        guard let date = lastResets[accountID], now.timeIntervalSince(date) < Self.justResetDuration else { return nil }
        return date
    }

    /// The earliest moment an entry expires; `nil` when the board is empty.
    public var nextExpiry: Date? {
        let ceremonyExpiries = ceremonies.values.map(\.expiresAt)
        let resetExpiries = lastResets.values.map { $0.addingTimeInterval(Self.justResetDuration) }
        return (ceremonyExpiries + resetExpiries).min()
    }

    /// Adds a ceremony per event. The same event again changes nothing (no replay); a newer reset of the same window
    /// replaces the older ceremony, an older one is ignored. `previousFractions` maps `WindowResetEvent.id` to the ring's
    /// fill before the reset; events without an entry unwind from their `previousUsed`.
    public mutating func insert(_ events: [WindowResetEvent], previousFractions: [String: Double], now: Date) {
        for event in events {
            let key = Key(event)
            if let existing = ceremonies[key],
               existing.event.id == event.id || existing.event.detectedAt > event.detectedAt {
                continue
            }
            ceremonies[key] = ResetCeremony(
                event: event,
                previousFraction: previousFractions[event.id] ?? event.previousUsed.value / 100,
                startedAt: now
            )
            if lastResets[event.accountID].map({ $0 < event.detectedAt }) ?? true {
                lastResets[event.accountID] = event.detectedAt
            }
        }
    }

    public mutating func markPlayed(_ id: UUID, on surface: CeremonySurface) {
        guard let key = ceremonies.first(where: { $0.value.id == id })?.key else { return }
        ceremonies[key]?.playedOn.insert(surface)
    }

    /// Drops expired ceremonies and resets older than `justResetDuration`.
    public mutating func prune(now: Date) {
        ceremonies = ceremonies.filter { $0.value.isAlive(at: now) }
        lastResets = lastResets.filter { now.timeIntervalSince($0.value) < Self.justResetDuration }
    }
}
