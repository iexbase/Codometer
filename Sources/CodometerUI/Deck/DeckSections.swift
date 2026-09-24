import CodometerCore
import CodometerL10n
import Foundation

/// Which parts of the deck are on screen, decided from its accounts, the group filter and the attention queue.
///
/// A part is `shown`, `reserved` (laid out but invisible and inert) or `absent`. A group without accounts reserves
/// the dial row, the page switcher and the pages (footer and range picker included) under a calm empty state, so
/// switching between an empty and a non-empty group never resizes the deck — the measurement copy reserves the same
/// room. With no accounts at all there is nothing to reserve: the deck is the header and the empty state.
struct DeckSections: Equatable, Sendable {
    enum Visibility: Equatable, Sendable {
        case shown
        /// Laid out for its size only: invisible, no hits, hidden from accessibility.
        case reserved
        case absent

        var isShown: Bool { self == .shown }
        var isLaidOut: Bool { self != .absent }
    }

    /// What the deck says when it has no account to show.
    enum EmptyState: Equatable, Sendable {
        /// The group filter names a group without enabled accounts; `nil` when the group is unknown.
        case group(name: String?)
        /// No accounts in settings.
        case noAccounts
        /// Accounts exist, but every one is switched off.
        case allDisabled
        /// Settings have enabled accounts the engine has not published yet: at launch (before the first state) or right
        /// after an account is switched on. Saying "turned off" or "no accounts" here would be false.
        case loading
    }

    /// The header's group filter: whenever groups exist, so an empty group can always be switched away from.
    let groupFilter: Visibility
    /// "Waiting for you" lists waiting sessions of every group, so it stays with an empty group: the rail's attention tab
    /// (shown whatever the filter) opens the deck on it.
    let attention: Visibility
    let dials: Visibility
    /// "Overview / Timeline".
    let pageSwitcher: Visibility
    /// The selected account's page, with its footer ("Next refresh in …") and, on the Timeline page, the range picker.
    let pages: Visibility
    let emptyState: EmptyState?

    /// The sections for a deck showing `shownCount` of its `accountCount` accounts (the store's enabled accounts, every
    /// group) under `settings`.
    static func make(accountCount: Int, shownCount: Int, settings: AppSettings, attentionCount: Int, pageCount: Int) -> DeckSections {
        make(
            accountCount: accountCount,
            shownCount: shownCount,
            configuredAccountCount: settings.accounts.count,
            enabledInSettingsCount: settings.accounts.count { $0.isEnabled },
            filter: settings.appearance.railGroupFilter,
            groups: settings.groups,
            attentionCount: attentionCount,
            pageCount: pageCount
        )
    }

    /// - Parameters:
    ///   - accountCount: Enabled accounts the deck has (every group).
    ///   - shownCount: Of those, the ones the group filter shows.
    ///   - configuredAccountCount: Accounts in settings, enabled or not.
    ///   - enabledInSettingsCount: Of those, the enabled ones.
    ///   - filter: The group filter; `groups` names it.
    ///   - attentionCount: Items in the attention queue.
    ///   - pageCount: Pages the deck offers.
    static func make(
        accountCount: Int,
        shownCount: Int,
        configuredAccountCount: Int,
        enabledInSettingsCount: Int,
        filter: AccountGroupID?,
        groups: [AccountGroup],
        attentionCount: Int,
        pageCount: Int
    ) -> DeckSections {
        let groupFilter: Visibility = groups.isEmpty ? .absent : .shown
        let attention: Visibility = attentionCount > 0 ? .shown : .absent
        guard accountCount > 0 else {
            let empty: EmptyState = if configuredAccountCount == 0 {
                .noAccounts
            } else if enabledInSettingsCount == 0 {
                .allDisabled
            } else {
                .loading
            }
            return DeckSections(
                groupFilter: groupFilter,
                attention: attention,
                dials: .absent,
                pageSwitcher: .absent,
                pages: .absent,
                emptyState: empty
            )
        }
        let accounts: Visibility = shownCount > 0 ? .shown : .reserved
        return DeckSections(
            groupFilter: groupFilter,
            attention: attention,
            dials: accounts,
            pageSwitcher: pageCount > 1 ? accounts : .absent,
            pages: accounts,
            emptyState: shownCount > 0 ? nil : .group(name: groups.first { $0.id == filter }?.name.value)
        )
    }
}

extension DeckSections.EmptyState {
    func title(l10n: Localizer) -> String {
        let text = l10n.emptyState
        return switch self {
        case .group(let name?): text.groupTitle(name)
        case .group(nil): text.unknownGroupTitle
        case .noAccounts: text.noAccountsTitle
        case .allDisabled: text.allDisabledTitle
        case .loading: text.loadingTitle
        }
    }

    /// One paragraph that wraps inside the deck's fixed width (the width scales with the text).
    func message(l10n: Localizer) -> String {
        let text = l10n.emptyState
        return switch self {
        case .group: text.groupBody
        case .noAccounts: text.noAccountsBody
        case .allDisabled: text.allDisabledBody
        case .loading: text.loadingBody
        }
    }

    var systemImage: String {
        switch self {
        case .group: "square.stack.3d.up.slash"
        case .noAccounts: "person.crop.circle.badge.plus"
        case .allDisabled: "pause.circle"
        case .loading: "hourglass"
        }
    }

    /// Whether "Show All" (clearing the group filter) is offered.
    var offersShowAll: Bool {
        if case .group = self { return true }
        return false
    }

    /// Whether "Open Settings" is offered: not while loading, when there is nothing to fix.
    var offersSettings: Bool {
        self != .loading
    }

    /// Replaces the header's freshness line when there is no account to be fresh; `nil` keeps it.
    func headerSubtitle(l10n: Localizer) -> String? {
        let text = l10n.emptyState
        return switch self {
        case .group: nil
        case .noAccounts: text.noAccountsCaption
        case .allDisabled: text.allDisabledCaption
        case .loading: text.loadingCaption
        }
    }
}
