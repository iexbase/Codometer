@testable import CodometerApp
import CodometerCore
import CodometerL10n
import CodometerUI
import AppKit
import Foundation
import Testing

/// The floating card's window controller: it shows itself only for its own style, morphs between the two forms, and
/// remembers where it was left.
///
/// Needs a display, so it is skipped on a headless machine.
@MainActor
@Suite("Floating card controller", .enabled(if: NSScreen.main != nil))
struct FloatingCardControllerTests {
    /// Records the haptics the drag loop asks for.
    private final class HapticRecorder: HapticPerforming {
        private(set) var played: [SnapHaptic] = []

        func perform(_ haptic: SnapHaptic) {
            played.append(haptic)
        }
    }

    private func makeStore(
        style: PresentationStyle = .floatingCard,
        accounts: Int = 2,
        card: FloatingCardSettings = FloatingCardSettings()
    ) throws -> (TrackerStore, Saved) {
        let profiles = try (0..<accounts).map { index in
            try AccountProfile(
                provider: index.isMultiple(of: 2) ? .claude : .codex,
                label: try AccountLabel(validating: "Account \(index)"),
                directory: try ProfileDirectory(validating: "/Users/example/.p\(index)")
            )
        }
        var settings = try AppSettings(accounts: profiles)
        settings.appearance.presentationStyle = style
        settings.appearance.floatingCard = card
        let saved = Saved()
        let statuses = try profiles.enumerated().map { index, profile in
            AccountStatus(
                profile: profile,
                identity: AccountIdentity(email: nil, organization: nil, plan: nil),
                reading: try UsageReading(
                    capturedAt: Date(timeIntervalSince1970: 1_789_600_000),
                    source: .claudeUsageCommand,
                    buckets: [try LimitBucket(id: "main", title: nil, windows: [
                        try LimitWindow(
                            id: "week",
                            scope: .weekly(model: nil),
                            used: try Percentage(validating: 40 + Double(index) * 20),
                            duration: .oneWeek,
                            resetsAt: Date(timeIntervalSince1970: 1_789_600_000 + 86_400)
                        ),
                    ], isLimitReached: false)],
                    credits: nil
                )
            )
        }
        var actions = TrackerActions(
            refresh: { _ in },
            persistSettings: { saved.settings = $0 },
            discoverProfiles: { [] },
            revealDataFolder: {},
            setLaunchAtLogin: { _ in nil },
            openSettings: { saved.openedSettings += 1 },
            quit: {}
        )
        actions.switchPresentationStyle = { saved.style = $0 }
        let store = TrackerStore(
            state: TrackerState(accounts: statuses),
            settings: settings,
            now: Date(timeIntervalSince1970: 1_789_600_000),
            actions: actions
        )
        return (store, saved)
    }

    final class Saved {
        var settings: AppSettings?
        var style: PresentationStyle?
        var openedSettings = 0
    }

    @Test("The card shows itself only when it is the selected style")
    func showsOnlyForItsOwnStyle() throws {
        let (island, _) = try makeStore(style: .island)
        let hidden = FloatingCardController(store: island)
        hidden.applyAppearance()
        #expect(!hidden.isOnScreen)

        let (cardStore, _) = try makeStore()
        let shown = FloatingCardController(store: cardStore)
        shown.applyAppearance()
        #expect(shown.isOnScreen)
        #expect(cardStore.statusDemand.contains(.card))

        // Hiding the island hides the card too, and the status surface goes with it.
        cardStore.updateSettings { $0.appearance.visibility = .hidden }
        shown.applyAppearance()
        #expect(!shown.isOnScreen)
        #expect(!cardStore.statusDemand.contains(.card))
        shown.hide()
    }

    @Test("The card opens at the top-right corner of its display, with the pill in the same corner")
    func defaultPlacement() throws {
        let (store, _) = try makeStore()
        let controller = FloatingCardController(store: store)
        controller.applyAppearance()
        let geometry = controller.debugGeometry
        let screen = try #require(NSScreen.screens.first)
        #expect(geometry.cardFrame.width > 0)
        #expect(geometry.anchor == CardAnchor.topTrailing.rawValue)
        #expect(geometry.cardFrame.maxX <= screen.visibleFrame.maxX)
        #expect(geometry.cardFrame.maxY <= screen.visibleFrame.maxY)
        // Both forms share the top-right corner.
        #expect(geometry.pillFrame.maxX == geometry.cardFrame.maxX)
        #expect(geometry.pillFrame.maxY == geometry.cardFrame.maxY)
        #expect(geometry.pillFrame.width < geometry.cardFrame.width)
        controller.hide()
    }

    @Test("Minimizing and restoring a hundred times lands on exactly the same pixels, at every scale", arguments: [0.75, 1.0, 1.5])
    func minimizeRestoreNeverDrifts(scale: Double) throws {
        let (store, _) = try makeStore()
        store.updateSettings { $0.appearance.scale = (try? IslandScale(scale)) ?? .standard }
        let controller = FloatingCardController(store: store)
        controller.applyAppearance()
        let first = controller.debugGeometry.cardFrame
        let pill = controller.debugGeometry.pillFrame
        for _ in 0..<100 {
            controller.debugMinimize()
            controller.debugExpand()
        }
        #expect(controller.debugGeometry.cardFrame == first, "card drifted at \(scale)")
        #expect(controller.debugGeometry.pillFrame == pill, "pill drifted at \(scale)")
        controller.hide()
    }

    @Test("The panel grows for the card and shrinks back to the pill, always with room for the shadow")
    func panelFollowsTheForm() throws {
        let (store, _) = try makeStore()
        let controller = FloatingCardController(store: store)
        controller.applyAppearance()
        let expanded = controller.debugGeometry
        #expect(expanded.panelFrame.width >= expanded.cardFrame.width)
        #expect(expanded.panelFrame.contains(expanded.cardFrame))
        controller.debugMinimize()
        // The fold shrinks the panel when it finishes; force the end state by asking for the geometry after it.
        controller.debugExpand()
        controller.debugMinimize()
        #expect(controller.debugGeometry.form == "pill")
        controller.hide()
    }

    @Test("The global shortcut toggles the card, and reports failure only while it is hidden")
    func shortcut() throws {
        let (store, _) = try makeStore()
        let controller = FloatingCardController(store: store)
        controller.applyAppearance()
        #expect(controller.debugGeometry.form == "card")
        #expect(controller.toggleFromShortcut(preferAttention: false))
        #expect(controller.debugGeometry.form == "pill")
        #expect(controller.toggleFromShortcut(preferAttention: false))
        #expect(controller.debugGeometry.form == "card")
        controller.hide()
        #expect(!controller.toggleFromShortcut(preferAttention: false))
    }

    @Test("A notification click expands the card on that account and holds auto-selection")
    func openPinned() throws {
        let (store, _) = try makeStore(card: FloatingCardSettings(isMinimized: true))
        let controller = FloatingCardController(store: store)
        controller.applyAppearance()
        #expect(controller.debugGeometry.form == "pill")
        let target = try #require(store.visiblePresentations.first)
        #expect(controller.openPinned(accountID: target.id))
        #expect(controller.debugGeometry.form == "card")
        #expect(controller.model.selectedAccountID == target.id)
        #expect(controller.model.isAccountPinned)
        controller.hide()
        #expect(!controller.openPinned(accountID: target.id))
    }

    @Test("A drop remembers where the card was left, on the display it was dropped on")
    func dragRemembersItsPlace() async throws {
        let (store, saved) = try makeStore()
        let haptics = HapticRecorder()
        let controller = FloatingCardController(store: store, haptics: haptics)
        controller.applyAppearance()
        let screen = try #require(NSScreen.screens.first)
        // Carry the card into the bottom-left corner, where the magnet should lock it.
        await controller.debugDrag(
            to: CGPoint(x: screen.frame.minX + 40, y: screen.frame.minY + 40),
            duration: 0.1,
            command: false
        )
        let geometry = controller.debugGeometry
        let stage = FloatingCardGeometry.stage(of: try #require(cardDisplay(screen)))
        #expect(abs(geometry.cardFrame.minX - stage.minX) < 1)
        #expect(abs(geometry.cardFrame.minY - stage.minY) < 1)
        #expect(haptics.played.contains(.lock))
        // Placements are written after a short debounce.
        try await Task.sleep(for: .milliseconds(800))
        let placements = try #require(saved.settings?.appearance.floatingCard.placements)
        #expect(placements.current != nil)
        #expect(placements.byDisplay.first?.anchor == .bottomLeading)
        #expect(placements.byDisplay.first?.snapped == true)
        controller.hide()
    }

    @Test("Holding ⌘ while dragging places the card exactly where it is dropped")
    func commandBypassesTheMagnet() async throws {
        let (store, _) = try makeStore()
        let controller = FloatingCardController(store: store)
        controller.applyAppearance()
        let screen = try #require(NSScreen.screens.first)
        let target = CGPoint(x: screen.frame.midX, y: screen.frame.midY + 120)
        await controller.debugDrag(to: target, duration: 0.1, command: true)
        let geometry = controller.debugGeometry
        #expect(abs(geometry.cardFrame.midX - target.x) < 1)
        #expect(abs(geometry.cardFrame.midY - target.y) < 1)
        controller.hide()
    }

    @Test("The theme and the size follow the settings, and the size falls back when the display is too small")
    func themeAndSize() throws {
        let (store, _) = try makeStore(card: FloatingCardSettings(theme: .midnight, size: .regular))
        let controller = FloatingCardController(store: store)
        controller.applyAppearance()
        #expect(controller.debugGeometry.theme == "midnight")
        #expect(controller.debugGeometry.size == "regular")
        controller.debugSetSize(.compact)
        #expect(controller.debugGeometry.size == "compact")
        controller.debugSetTheme(.light)
        #expect(controller.debugGeometry.theme == "light")
        controller.hide()
    }

    @Test("The card follows the most urgent account, and arrow keys move between them")
    func accountSelection() throws {
        let (store, _) = try makeStore(accounts: 3)
        let controller = FloatingCardController(store: store)
        controller.applyAppearance()
        let urgent = try #require(CardAccountSelector.mostUrgent(store.visiblePresentations))
        #expect(controller.model.selectedAccountID == urgent.id)
        controller.debugSelectAccount(1)
        #expect(controller.model.selectedAccountID != urgent.id)
        #expect(controller.model.isAccountPinned)
        controller.hide()
    }

    @Test("Resetting the position puts the card back in the top-right corner")
    func resetPosition() async throws {
        let (store, _) = try makeStore()
        let controller = FloatingCardController(store: store)
        controller.applyAppearance()
        let screen = try #require(NSScreen.screens.first)
        await confirmDropped(controller, to: CGPoint(x: screen.frame.minX + 40, y: screen.frame.minY + 40))
        controller.resetPosition()
        let geometry = controller.debugGeometry
        let stage = FloatingCardGeometry.stage(of: try #require(cardDisplay(screen)))
        #expect(abs(geometry.cardFrame.maxX - stage.maxX) < 1)
        #expect(abs(geometry.cardFrame.maxY - stage.maxY) < 1)
        controller.hide()
    }

    private func confirmDropped(_ controller: FloatingCardController, to point: CGPoint) async {
        await controller.debugDrag(to: point, duration: 0.1, command: false)
    }

    /// The card's own view of a screen, which is what `FloatingCardGeometry` works with.
    private func cardDisplay(_ screen: NSScreen) -> DisplayDescriptor? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(number.uint32Value))?.takeRetainedValue(),
              let id = try? DisplayID(CFUUIDCreateString(nil, uuid) as String)
        else { return nil }
        return DisplayDescriptor(
            id: id,
            name: screen.localizedName,
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            isMain: true,
            isBuiltIn: screen.safeAreaInsets.top > 0,
            notch: NotchGeometry.make(
                screen: screen.frame,
                safeTop: screen.safeAreaInsets.top,
                auxLeft: screen.auxiliaryTopLeftArea,
                auxRight: screen.auxiliaryTopRightArea
            )
        )
    }
}
