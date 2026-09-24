import AppKit
import CodometerCore
import CodometerEngine
import CodometerPlatform
import CodometerUI
import Foundation
import Observation

/// State of the opt-in vendor service status checks.
///
/// Everything here stays switched off until the user turns the setting on: no service, no network monitor and no
/// observation of anything but the settings themselves.
@MainActor
final class StatusCoordinator {
    init() {}

    var service: VendorStatusService?
    /// Started with the feature, cancelled with it: `NWPathMonitor` costs nothing while it runs, but an app that
    /// never uses the network should not watch it either.
    var network: NetworkStatusMonitor?
    /// Whether `observeSettings` is already tracking a change.
    var isObservingSettings = false
    #if DEBUG
    /// A debug scenario set the board by hand; live checks stay out of the way so captures are deterministic.
    var isOverriddenByScenario = false
    #endif
}

/// Vendor service status (opt-in network access, off by default).
extension AppController {
    /// Starts watching the two things that decide whether status checks run: a surface that shows status being
    /// visible, and the settings that allow the check at all.
    func startStatusService() {
        store.onStatusDemandChange = { [weak self] _ in
            self?.updateStatusService()
        }
        observeStatusSettings()
        updateStatusService()
    }

    /// Opens the vendor's status page in the browser. The URL is fixed in code and never comes from a feed.
    func openStatusPage(_ provider: ProviderKind) {
        NSWorkspace.shared.open(VendorStatusFeed.statusPage(for: provider))
    }

    /// Re-reads the conditions and tells the service; it starts, keeps going or stops on its own.
    func updateStatusService() {
        let conditions = statusConditions()
        guard conditions.isEnabled else {
            // Off: tear the whole feature down, including the ETags and the path monitor.
            statusCoordinator.network?.stop()
            statusCoordinator.network = nil
            if let service = statusCoordinator.service {
                statusCoordinator.service = nil
                Task { await service.stop() }
            }
            return
        }
        let service = statusService()
        Task { await service.update(conditions) }
    }

    /// The service, created the first time the feature is switched on.
    private func statusService() -> VendorStatusService {
        if let service = statusCoordinator.service { return service }
        let store = store
        let service = VendorStatusService(
            fetcher: LiveVendorStatusFetcher(),
            publish: { board in
                Task { @MainActor in
                    store.setServiceStatus(board)
                }
            }
        )
        statusCoordinator.service = service
        return service
    }

    private func statusConditions() -> VendorStatusConditions {
        #if DEBUG
        guard !statusCoordinator.isOverriddenByScenario else { return .off }
        #endif
        let settings = store.settings
        guard settings.general.showsVendorStatus else { return .off }
        let monitor = statusNetworkMonitor()
        let reachability = monitor.reachability
        return VendorStatusConditions(
            isEnabled: true,
            hasDemand: !store.statusDemand.isEmpty,
            providers: Set(settings.accounts.filter(\.isEnabled).map(\.provider)),
            // Read at decision time: `ProcessInfo` answers from a cached value, so this costs nothing and polls nothing.
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            isOnline: reachability.isOnline,
            isConstrained: reachability.isConstrained,
            isExpensive: reachability.isExpensive
        )
    }

    private func statusNetworkMonitor() -> NetworkStatusMonitor {
        if let monitor = statusCoordinator.network { return monitor }
        let monitor = NetworkStatusMonitor()
        monitor.start()
        statusCoordinator.network = monitor
        return monitor
    }

    /// Settings changes reach the service without a timer: one observation of the store's settings, re-armed after
    /// every change (the toggle, an account being enabled or removed).
    private func observeStatusSettings() {
        guard !statusCoordinator.isObservingSettings else { return }
        statusCoordinator.isObservingSettings = true
        withObservationTracking {
            _ = store.settings
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.statusCoordinator.isObservingSettings = false
                self.observeStatusSettings()
                self.updateStatusService()
            }
        }
    }

    #if DEBUG
    /// A debug scenario writes the board directly (no network). `nil` clears it and lets live checks resume.
    ///
    /// A scenario that sets a status wants to see it, so the setting that shows status is turned on in memory too
    /// (never saved). Clearing the board leaves that setting where it is.
    func setDebugServiceStatus(_ board: ServiceStatusBoard?) {
        statusCoordinator.isOverriddenByScenario = board != nil
        if board != nil {
            store.debugOverrideSettings { $0.general.showsVendorStatus = true }
        }
        store.setServiceStatus(board ?? .empty)
        updateStatusService()
    }
    #endif
}
