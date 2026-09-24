@testable import CodometerApp
import CodometerCore
import Foundation
import Testing

/// "Open at login" and the version bookkeeping a launch does: both decide from plain values, so every combination is
/// covered here instead of on someone's Mac.
@Suite("Login item and version bookkeeping")
struct LoginItemReconcileTests {
    @Test("The setting and the system agree: nothing happens")
    func agreement() {
        #expect(LoginItemReconcile.action(intent: true, status: .enabled, versionChanged: false) == .none)
        #expect(LoginItemReconcile.action(intent: true, status: .enabled, versionChanged: true) == .none)
        #expect(LoginItemReconcile.action(intent: false, status: .disabled, versionChanged: false) == .none)
        #expect(LoginItemReconcile.action(intent: false, status: .notFound, versionChanged: true) == .none)
    }

    @Test("A new version registers the login item again; the same version follows the user")
    func afterAnUpdate() {
        // The rename gave the app a new bundle id, so the old registration is gone.
        #expect(LoginItemReconcile.action(intent: true, status: .disabled, versionChanged: true) == .register)
        #expect(LoginItemReconcile.action(intent: true, status: .notFound, versionChanged: true) == .register)
        // No update: the user removed it in System Settings, and the toggle follows.
        #expect(LoginItemReconcile.action(intent: true, status: .disabled, versionChanged: false) == .turnSettingOff)
        #expect(LoginItemReconcile.action(intent: true, status: .notFound, versionChanged: false) == .turnSettingOff)
    }

    @Test("A login item the system has, but the settings do not, turns the toggle on")
    func systemWins() {
        #expect(LoginItemReconcile.action(intent: false, status: .enabled, versionChanged: false) == .turnSettingOn)
        #expect(LoginItemReconcile.action(intent: false, status: .requiresApproval, versionChanged: false) == .turnSettingOn)
    }

    @Test("Waiting for approval is reported, never re-registered")
    func approval() {
        #expect(LoginItemReconcile.action(intent: true, status: .requiresApproval, versionChanged: false) == .needsApproval)
        #expect(LoginItemReconcile.action(intent: true, status: .requiresApproval, versionChanged: true) == .needsApproval)
    }

    @Test("An unreadable status (an isolated instance, an unbundled build) changes nothing")
    func unavailable() {
        for intent in [true, false] {
            for changed in [true, false] {
                #expect(LoginItemReconcile.action(intent: intent, status: .unavailable, versionChanged: changed) == .none)
            }
        }
    }

    @Test("The version bookkeeping backs settings up exactly once per new version")
    func versionPlan() throws {
        let one = try AppVersion("1.0.0")
        let two = try AppVersion("1.1.0")
        #expect(VersionBookkeeping.plan(stored: nil, current: one) == .record(one))
        #expect(VersionBookkeeping.plan(stored: one, current: one) == .none)
        #expect(VersionBookkeeping.plan(stored: one, current: two) == .upgrade(from: one, to: two))
        // A downgrade is still a change: the newer settings are backed up before the older app writes.
        #expect(VersionBookkeeping.plan(stored: two, current: one) == .upgrade(from: two, to: one))
        // No bundle version at all (`swift run`): nothing is recorded, nothing is backed up.
        #expect(VersionBookkeeping.plan(stored: one, current: nil) == .none)
        #expect(VersionBookkeeping.plan(stored: nil, current: nil) == .none)
    }

    @Test("A version is a valid settings backup tag")
    func backupTagShape() throws {
        let version = try AppVersion("10.2.13")
        #expect((try? StableIdentifier.validate(version.description, field: "tag")) == "10.2.13")
    }
}
