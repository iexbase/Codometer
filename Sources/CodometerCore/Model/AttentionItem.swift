import Foundation

/// A session blocked on the user, together with the account it belongs to.
public struct AttentionItem: Hashable, Sendable, Identifiable {
    public let accountID: AccountID
    /// A session whose activity is `.waiting`; `TrackerState.attentionQueue` only ever builds such items.
    public let session: AgentSession

    public init(accountID: AccountID, session: AgentSession) {
        self.accountID = accountID
        self.session = session
    }

    public var id: String { "\(accountID)/\(session.id)" }

    public var waitingSince: Date { session.activitySince }
}

extension TrackerState {
    /// Waiting sessions of enabled accounts, longest wait first.
    ///
    /// Equal wait times keep account order, then session order, so the queue never shuffles between updates.
    public var attentionQueue: [AttentionItem] {
        var items: [AttentionItem] = []
        for account in accounts where account.profile.isEnabled {
            for session in account.sessions where session.activity == .waiting {
                items.append(AttentionItem(accountID: account.id, session: session))
            }
        }
        let ordered: [(offset: Int, element: AttentionItem)] = Array(items.enumerated())
        return ordered
            .sorted { lhs, rhs in
                if lhs.element.waitingSince != rhs.element.waitingSince {
                    return lhs.element.waitingSince < rhs.element.waitingSince
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
