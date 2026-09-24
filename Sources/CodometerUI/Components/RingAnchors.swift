import CodometerCore
import SwiftUI

/// Where the island's live dials are, for the ring flight between the rail and the deck.
///
/// `RingGauge` writes each ring box (its frame without the orbit margin, in the `coordinateSpace` named on the island's
/// stage) here when a sink is in the environment and the gauge is on the rail or the deck. Writing never invalidates a
/// view: the sink is a plain class nobody observes. Only the live island sets a sink; measurement copies, the popover,
/// settings previews and static renders do not, so measuring is unaffected.
@MainActor
public final class RingAnchorSink {
    /// The coordinate space name the island's stage declares and gauges report in.
    public nonisolated static let coordinateSpace = "island.stage"

    /// Rail ring boxes by account.
    public var rail: [AccountID: CGRect] = [:]
    /// Deck dial ring boxes by account.
    public var deck: [AccountID: CGRect] = [:]
    /// The deck body's visible viewport; a dial outside it does not fly.
    public var deckViewport: CGRect?

    public init() {}

    /// Records a ring box for a rail or deck gauge; other surfaces are ignored.
    public func report(_ box: CGRect, accountID: AccountID, surface: CeremonySurface) {
        switch surface {
        case .rail: rail[accountID] = box
        case .deck: deck[accountID] = box
        case .card, .popover: break
        }
    }

    /// Forgets a gauge that left the view hierarchy.
    public func remove(accountID: AccountID, surface: CeremonySurface) {
        switch surface {
        case .rail: rail[accountID] = nil
        case .deck: deck[accountID] = nil
        case .card, .popover: break
        }
    }
}

extension EnvironmentValues {
    /// Set on the live island only; gauges on the rail and in the deck report their ring boxes to it.
    @Entry public var ringAnchorSink: RingAnchorSink? = nil
    /// Accounts whose real rings are hidden while flying copies take their place (set by the island root). The rail's
    /// dials and the deck's dials pass `hidesRings` for these accounts.
    @Entry public var ringFlightHiddenAccounts: Set<AccountID> = []
}

/// Reports a gauge's ring box to the environment's anchor sink while the gauge is on screen.
///
/// Nothing is removed when a gauge leaves: SwiftUI does not order a departing view's `onDisappear` after the
/// replacing view's `onGeometryChange`, so rebuilding the island's content (its first placement, a surface change,
/// a rail turning from a row into a column) would clear the boxes the replacing dials have just reported — for good,
/// because the boxes are unchanged and nothing re-fires. A box nobody draws any more is never used either:
/// `RingFlightPlanner.pairs` only flies the accounts the rail and the deck are showing right now.
struct RingAnchorReporter: ViewModifier {
    let accountID: AccountID
    let surface: CeremonySurface?
    /// The orbit margin around the rings inside the gauge's frame.
    let inset: CGFloat

    @Environment(\.ringAnchorSink) private var sink

    func body(content: Content) -> some View {
        if let sink, let surface, surface == .rail || surface == .deck {
            content
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named(RingAnchorSink.coordinateSpace))
                } action: { frame in
                    sink.report(frame.insetBy(dx: inset, dy: inset), accountID: accountID, surface: surface)
                }
        } else {
            content
        }
    }
}
