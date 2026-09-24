import CodometerCore
import Foundation
import Observation
import SwiftUI

/// Something inside the floating card asks its window controller to act.
public enum CardRequest: Equatable, Sendable {
    /// The minimize button.
    case minimize
    /// A click on the pill.
    case expand
    /// The header's account chip was clicked: the controller pops up the account menu.
    case accountMenu
    /// The header's account chip or a page dot.
    case selectAccount(AccountID)
    case nextAccount
    case previousAccount
    /// The status pill of a vendor with a problem.
    case openStatusPage(ProviderKind)
    case refresh
    case openSettings
    /// The card moves itself to one of the nine places (a VoiceOver action).
    case move(CardAnchor)
}

/// What the floating card's views draw, owned by `FloatingCardController` and read by SwiftUI.
///
/// The controller decides frames and forms; the views only render them. Frames are in canvas coordinates (the hosting
/// view's own space), so moving the window never moves anything inside it.
@MainActor
@Observable
public final class FloatingCardModel {
    /// The card's rect inside the canvas. The pill is always inside it, aligned on the same anchor point.
    public var cardFrame: CGRect = .zero
    public var pillFrame: CGRect = .zero
    /// The point both forms share, which is what makes minimize → restore land on the same pixels.
    public var anchor: CardAnchor = .topTrailing
    /// The size actually drawn: the setting, or the next smaller one when it does not fit (never saved).
    public var size: CardSize = .regular
    public var metrics = CardMetrics(scale: 1)
    public var theme: CardThemeTokens = .resolve(theme: .graphite, scheme: .dark, reducesTransparency: false, increasesContrast: false)

    public var isExpanded = true
    public var isDragging = false
    /// The pointer rests on the card, which reveals the minimize button and holds auto-selection still.
    public var isHovered = false
    /// The contour is travelling between the two forms; the shadow steps aside so no path is rebuilt per frame.
    public var isMorphing = false
    /// The user chose this account by hand, so the card is not following the most urgent one right now.
    public var isAccountPinned = false
    /// Builds the card invisibly while the pill is shown, so restoring costs one cheap frame.
    public var prewarmsCard = false
    /// Builds the pill invisibly while the card is shown, so minimizing costs one cheap frame.
    public var prewarmsPill = false
    /// The panel may take key events: Esc, arrows, Space and ⌘, work without activating the app.
    public var isKeyboardEngaged = false
    /// Shown once, for a few seconds, the first time the card appears.
    public var showsCoachMark = false
    /// The coach mark hangs under the card, unless the card is pinned to the bottom of the screen.
    public var coachMarkBelow = true

    public var selectedAccountID: AccountID?
    /// The card's own third-tile choice, kept here so the views never reach into the settings.
    public var thirdTile: CardThirdTile = .weeklyReset
    /// Which accounts the Strip size covers, for the same reason.
    public var stripScope: CardStripScope = .selectedAccount

    @ObservationIgnored public var onRequest: ((CardRequest) -> Void)?

    public init() {}

    /// 1 while the card is shown, 0 while the pill is.
    public var morphProgress: CGFloat { isExpanded ? 1 : 0 }

    public func send(_ request: CardRequest) {
        onRequest?(request)
    }
}

extension CardAnchor {
    /// The SwiftUI alignment that pins this anchor.
    public var alignment: Alignment {
        switch self {
        case .topLeading: .topLeading
        case .top: .top
        case .topTrailing: .topTrailing
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        case .bottomLeading: .bottomLeading
        case .bottom: .bottom
        case .bottomTrailing: .bottomTrailing
        }
    }

    public var unitPoint: UnitPoint {
        switch self {
        case .topLeading: .topLeading
        case .top: .top
        case .topTrailing: .topTrailing
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        case .bottomLeading: .bottomLeading
        case .bottom: .bottom
        case .bottomTrailing: .bottomTrailing
        }
    }
}

extension EnvironmentValues {
    /// The floating card's resolved colours. Views read it instead of resolving a theme themselves.
    @Entry public var cardTheme = CardThemeTokens.resolve(
        theme: .graphite,
        scheme: .dark,
        reducesTransparency: false,
        increasesContrast: false
    )

    /// The card's sizes at the user's scale.
    @Entry public var cardMetrics = CardMetrics(scale: 1)
}
