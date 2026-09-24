import CodometerCore
import CodometerL10n
import AppKit
import SwiftUI

/// The menu bar popover: the same deck as the island, inside the system's glass popover, with any notice about
/// Codometer's own data above it.
public struct StatusPopoverView: View {
    /// Room kept free above and below the popover on the screen.
    static let screenMargin: CGFloat = 60

    let store: TrackerStore
    let maxHeight: CGFloat?
    /// The owner's model, so it can choose the account the deck shows; `nil` uses the view's own.
    let sharedModel: IslandModel?
    @State private var ownModel = StatusPopoverView.makeModel()
    /// Whether the popover is open. Its hosting view lives on (and keeps updating) while it is closed.
    @State private var isOnScreen = false
    @Environment(\.liveEffectsEnabled) private var inheritedLiveEffects

    /// - Parameters:
    ///   - model: The deck's selection and layout, e.g. from `makeModel()`, kept by the owner so it can select an
    ///     account from outside; `nil` keeps a private one.
    ///   - maxHeight: The tallest the popover's deck may be; `nil` fits the main screen's visible height.
    public init(store: TrackerStore, model: IslandModel? = nil, maxHeight: CGFloat? = nil) {
        self.store = store
        sharedModel = model
        self.maxHeight = maxHeight
    }

    /// A model laid out the way the popover shows the deck.
    public static func makeModel() -> IslandModel {
        IslandModel(layout: IslandLayout(
            edge: .top,
            anchor: .top,
            style: .floating,
            metrics: IslandMetrics(scale: 1)
        ))
    }

    private var model: IslandModel { sharedModel ?? ownModel }

    public var body: some View {
        let metrics = model.layout.metrics
        VStack(spacing: 0) {
            if !store.notices.isEmpty {
                AppNoticeBanner(store: store, placement: .deck(metrics))
                    .frame(width: metrics.deckWidth, alignment: .leading)
                    .padding(.horizontal, metrics.deckPadding)
                    .padding(.top, metrics.deckPadding)
            }
            DeckContent(
                store: store,
                model: model,
                accounts: store.presentations,
                context: .popover,
                maxHeight: maxHeight ?? Self.screenLimit
            )
        }
        // History loads only while the popover is actually open.
        .environment(\.isDeckVisible, isOnScreen)
        .environment(\.l10n, store.localizer)
        .environment(\.locale, store.localizer.locale)
        .environment(\.liveEffectsEnabled, inheritedLiveEffects && store.allowsLiveEffects)
        .background {
            WindowVisibilityReader { visible in
                isOnScreen = visible
                // The status chip in the deck header is a status surface: the check runs only while one is on screen.
                store.setStatusSurface(.popover, visible: visible)
            }
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
        .onDisappear {
            store.setStatusSurface(.popover, visible: false)
        }
    }

    private static var screenLimit: CGFloat {
        guard let screen = NSScreen.main else { return .infinity }
        return max(320, screen.visibleFrame.height - screenMargin)
    }
}
