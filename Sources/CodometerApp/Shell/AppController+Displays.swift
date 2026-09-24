import CodometerCore
import CodometerUI
import Foundation

/// Connected displays and moving the island between them.
extension AppController {
    /// Re-reads the connected displays and publishes them to `store.displays` (the Presentation pane's picker and
    /// the island's "Move to Display" menu read it).
    ///
    /// Called at start and on every screen-parameter change; `applySurfaces()` runs right after, so a surface on a
    /// display that just went away moves to the main one.
    func refreshDisplays() {
        // The island resolves its own display through the same catalog (`AppController.swift` cannot hand it over).
        if island.screenCatalog !== screens {
            island.screenCatalog = screens
        }
        guard screens.refresh() else { return }
        store.setDisplays(screens.displays)
    }

    /// Moves the island to another display and remembers it, so it returns there after a reconnect.
    func moveIslandToDisplay(_ display: DisplayID) {
        guard let descriptor = screens.displays.first(where: { $0.id == display }) else { return }
        store.updateSettings { settings in
            settings.appearance.islandDisplayPolicy = .whereLeft
            settings.appearance.islandDisplay = descriptor.remembered
        }
        island.applyAppearance()
    }
}
