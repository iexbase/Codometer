import AppKit
@testable import CodometerApp
import Testing

@MainActor
@Suite("Activation policy", .serialized)
struct ActivationPolicyTests {
    @Test("Regular while any reason is retained; a change is reported only when the policy flips")
    func counting() {
        var ledger = ActivationPolicyLedger()
        #expect(ledger.policy == .accessory)
        #expect(ledger.retain("settings") == .regular)
        #expect(ledger.retain("onboarding") == nil)
        #expect(ledger.retain("settings") == nil)
        #expect(ledger.release("settings") == nil)
        #expect(ledger.release("onboarding") == nil)
        #expect(ledger.policy == .regular)
        #expect(ledger.release("settings") == .accessory)
        #expect(ledger.counts.isEmpty)
    }

    @Test("A release without a matching retain is ignored")
    func unbalancedRelease() {
        var ledger = ActivationPolicyLedger()
        #expect(ledger.release("settings") == nil)
        #expect(ledger.retain("onboarding") == .regular)
        #expect(ledger.release("settings") == nil)
        #expect(ledger.release("settings") == nil)
        #expect(ledger.policy == .regular)
        #expect(ledger.release("onboarding") == .accessory)
        #expect(ledger.release("onboarding") == nil)
        #expect(ledger.policy == .accessory)
    }

    @Test("Closing one window never demotes the app while the other is open")
    func sharedPolicy() {
        var applied: [NSApplication.ActivationPolicy] = []
        let original = ActivationPolicy.apply
        ActivationPolicy.resetForTesting()
        ActivationPolicy.apply = { applied.append($0) }
        defer {
            ActivationPolicy.apply = original
            ActivationPolicy.resetForTesting()
        }
        ActivationPolicy.retain("settings")
        ActivationPolicy.retain("onboarding")
        ActivationPolicy.release("settings")
        #expect(ActivationPolicy.current == .regular)
        ActivationPolicy.release("settings")
        ActivationPolicy.release("onboarding")
        #expect(applied == [.regular, .accessory])
        #expect(ActivationPolicy.current == .accessory)
    }
}
