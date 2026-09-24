import CodometerCore
import CodometerUI
import Foundation

/// State of the presentation styles: the floating card's controller and the style switch.
@MainActor
final class PresentationCoordinator {
    /// The floating card, built once at launch. `AppController.card` holds it as a `PresentationSurface`.
    var card: FloatingCardController?

    init() {}
}

/// The floating card presentation style and switching between styles.
extension AppController {
    /// Creates the floating card surface (`card`). It shows itself only when it is the selected style.
    func installPresentationSurfaces() {
        guard presentation.card == nil else { return }
        let controller = FloatingCardController(store: store)
        presentation.card = controller
        card = controller
    }

    /// Switches between the island and the floating card. `applySurfaces()` then hides one and shows the other in one
    /// transition: the island folds and fades where it is, and the card fades in at its remembered place.
    func switchPresentationStyle(_ style: PresentationStyle) {
        guard store.settings.appearance.presentationStyle != style else { return }
        store.updateSettings { $0.appearance.presentationStyle = style }
    }

    /// Puts the floating card back at its default place: the top-right corner of the main display.
    func resetCardPosition() {
        presentation.card?.resetPosition()
    }
}
