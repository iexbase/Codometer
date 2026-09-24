import AppKit

/// The app's activation policy, shared by every window that needs the app to be a regular app while open (Settings,
/// onboarding). The app is an agent otherwise: no Dock icon, no main menu.
///
/// Reference-counted by reason, so closing one window never demotes the app while another is still open. A release
/// without a matching retain is ignored.
@MainActor
enum ActivationPolicy {
    /// Applies a policy change; replaced in tests.
    static var apply: @MainActor (NSApplication.ActivationPolicy) -> Void = { policy in
        NSApplication.shared.setActivationPolicy(policy)
    }

    private static var ledger = ActivationPolicyLedger()

    /// `.regular` while any reason is retained.
    static var current: NSApplication.ActivationPolicy { ledger.policy }

    static func retain(_ reason: String) {
        if let change = ledger.retain(reason) {
            apply(change)
        }
    }

    static func release(_ reason: String) {
        if let change = ledger.release(reason) {
            apply(change)
        }
    }

    /// Forgets every retain without applying anything (tests only).
    static func resetForTesting() {
        ledger = ActivationPolicyLedger()
    }
}

/// The counting behind `ActivationPolicy`: how many times each reason is retained, and which policy that means.
struct ActivationPolicyLedger: Equatable, Sendable {
    private(set) var counts: [String: Int] = [:]

    /// `.regular` while any reason is retained, else `.accessory`.
    var policy: NSApplication.ActivationPolicy {
        counts.isEmpty ? .accessory : .regular
    }

    /// Counts one more retain; returns the policy to apply when it changes.
    mutating func retain(_ reason: String) -> NSApplication.ActivationPolicy? {
        let before = policy
        counts[reason, default: 0] += 1
        return policy == before ? nil : policy
    }

    /// Counts one release; a reason that is not retained is ignored. Returns the policy to apply when it changes.
    mutating func release(_ reason: String) -> NSApplication.ActivationPolicy? {
        guard let count = counts[reason] else { return nil }
        let before = policy
        counts[reason] = count > 1 ? count - 1 : nil
        return policy == before ? nil : policy
    }
}
