import CodometerCore
@testable import CodometerUI
import Foundation
import Testing

@MainActor
@Suite("Store app state")
struct StatusDemandTests {
    @MainActor
    private final class Recorder {
        var demands: [Set<StatusSurface>] = []
    }

    private func store(celebrates: Bool = true) throws -> TrackerStore {
        var appearance = AppearanceSettings()
        appearance.celebratesResets = celebrates
        return TrackerStore(
            state: .empty,
            settings: try AppSettings(accounts: [], appearance: appearance),
            now: UIFixture.now,
            actions: UIFixture.actions()
        )
    }

    @Test("Status surfaces add and remove demand; every change and only a change is reported")
    func demand() throws {
        let store = try store()
        let recorder = Recorder()
        store.onStatusDemandChange = { recorder.demands.append($0) }
        #expect(store.statusDemand.isEmpty)

        store.setStatusSurface(.islandDeck, visible: true)
        store.setStatusSurface(.islandDeck, visible: true)
        store.setStatusSurface(.popover, visible: true)
        store.setStatusSurface(.card, visible: false)
        store.setStatusSurface(.islandDeck, visible: false)
        store.setStatusSurface(.popover, visible: false)

        #expect(recorder.demands == [[.islandDeck], [.islandDeck, .popover], [.popover], []])
        #expect(store.statusDemand.isEmpty)
    }

    @Test("Live effects follow the energy decision")
    func liveEffects() throws {
        let store = try store()
        #expect(store.allowsLiveEffects)
        let lowPower = EnergyPolicy.decide(
            PowerSnapshot(lowPowerMode: true, onBattery: true, batteryPercent: nil, thermal: .nominal),
            mode: .automatic
        )
        #expect(lowPower.pausesLiveEffects)
        store.setEnergy(lowPower)
        #expect(store.energy == lowPower && !store.allowsLiveEffects)
        store.setEnergy(.normal)
        #expect(store.allowsLiveEffects)
    }

    @Test("Notices are set and dismissed by id; read-only, shortcut, displays and service status are stored")
    func appState() throws {
        let store = try store()
        store.setNotices([.settingsRepaired(count: 2), .history(.unavailable(reason: "locked")), .settingsRecovered(backupFileName: "settings.json.bak")])
        #expect(store.notices.map(\.id) == ["settingsRepaired", "history", "settingsRecovered"])
        store.dismissNotice("history")
        store.dismissNotice("unknown")
        #expect(store.notices == [.settingsRepaired(count: 2), .settingsRecovered(backupFileName: "settings.json.bak")])

        store.setSettingsReadOnly(true)
        #expect(store.isSettingsReadOnly)
        store.setShortcutStatus(.active(.controlOptionCommandU))
        #expect(store.shortcutStatus == .active(.controlOptionCommandU))
        store.setServiceStatus(.empty)
        #expect(store.serviceStatus == .empty)
        store.setDisplays([])
        #expect(store.displays.isEmpty)
    }

    @Test("Celebrations honour the setting and fill the ceremony board")
    func celebrate() throws {
        let reset = try WindowResetEvent(
            accountID: AccountID(),
            bucketID: "main",
            windowID: "primary",
            previousUsed: try Percentage(validating: 80),
            newUsed: try Percentage(validating: 2),
            detectedAt: UIFixture.now
        )
        let quiet = try store(celebrates: false)
        quiet.celebrate([reset], now: UIFixture.now)
        #expect(quiet.ceremonies.isEmpty)

        let store = try store()
        store.celebrate([reset], now: UIFixture.now)
        let ceremony = try #require(store.ceremonies.unplayed(on: .rail, now: UIFixture.now).first)
        #expect(ceremony.previousFraction == 0.8)
        #expect(store.ceremonies.justReset(accountID: reset.accountID, now: UIFixture.now) == UIFixture.now)
        store.markCeremonyPlayed(ceremony.id, on: .rail)
        #expect(store.ceremonies.unplayed(on: .rail, now: UIFixture.now).isEmpty)
        #expect(store.ceremonies.unplayed(on: .deck, now: UIFixture.now).count == 1)
    }
}
