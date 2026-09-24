import CodometerCore
import CodometerL10n
import CodometerUI
import AppKit
import SwiftUI

/// Menu bar item: a live ring icon and the highest headline percentage; left click opens a glass popover
/// with the deck, right click opens a short menu.
@MainActor
final class StatusItemController: NSObject {
    private let store: TrackerStore
    /// Opens the standard About panel; set by `AppController.startLifecycleServices()`.
    var onAbout: (() -> Void)?
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    fileprivate let popover = NSPopover()
    /// The popover deck's selection, so a notification click can show its account.
    private let popoverModel = StatusPopoverView.makeModel()
    private var menu: NSMenu?
    /// The key the current icon was drawn for; the icon is redrawn only when it changes.
    private var ringKey: MenuBarRing.Key?

    init(store: TrackerStore) {
        self.store = store
        super.init()

        if let button = statusItem.button {
            button.imagePosition = .imageLeading
            // Digits of equal width, so the item never changes width as the percentage changes.
            button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
            button.target = self
            button.action = #selector(buttonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let controller = NSHostingController(rootView: StatusPopoverView(store: store, model: popoverModel))
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = true
    }

    /// Redraws the icon and title when what they show changed; also follows a language or region change, which
    /// `AppController` reports through this call.
    func update() {
        guard let button = statusItem.button else { return }
        let l10n = store.localizer
        let presentations = store.visiblePresentations
        let highest = presentations
            .compactMap(\.headline?.primary)
            .max { $0.used < $1.used }
        let key = MenuBarRing.Key(window: highest, waitingCount: store.attentionQueue.count, now: store.now, l10n: l10n)
        if key != ringKey {
            ringKey = key
            button.image = MenuBarRing.image(for: key)
            button.setAccessibilityLabel(key.accessibilityText)
        }
        let help = l10n.statusItem.help
        if button.toolTip != help {
            button.toolTip = help
        }
        let title = highest.map { " " + UsageFormat.percent($0.used, l10n: l10n) } ?? ""
        if button.title != title {
            button.title = title
        }
    }

    @objc private func buttonClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopover(from: sender)
        }
    }

    /// Opens or closes the popover without a click, e.g. from the global shortcut while the island is hidden.
    func togglePopover() {
        guard let button = statusItem.button else { return }
        togglePopover(from: button)
    }

    /// Opens the popover on one account (or selects it in the open popover), e.g. after a click on a notification
    /// while the island is hidden.
    func showPopover(selecting accountID: AccountID) {
        popoverModel.selectedAccountID = accountID
        guard !popover.isShown, let button = statusItem.button else { return }
        showPopover(from: button)
    }

    private func togglePopover(from button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        showPopover(from: button)
    }

    private func showPopover(from button: NSStatusBarButton) {
        store.tick(Date())
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        #if DEBUG
        if let window = popover.contentViewController?.view.window {
            DebugWindows.register(window, name: DebugWindows.popover)
        }
        #endif
    }

    /// Built on every right click, so the titles follow the current language.
    private func showMenu() {
        let text = store.localizer.menu
        let menu = NSMenu()
        menu.addItem(ActionMenuItem(text.refreshAll, systemImage: "arrow.clockwise", key: "r") { [weak self] in
            self?.store.refresh()
        })
        menu.addItem(ActionMenuItem(text.settings, systemImage: "gearshape", key: ",") { [weak self] in
            self?.store.actions.openSettings()
        })
        let visible = store.settings.appearance.visibility == .always
        menu.addItem(ActionMenuItem(visible ? text.hideIsland : text.showIsland, systemImage: visible ? "eye.slash" : "eye") { [weak self] in
            self?.store.updateSettings { $0.appearance.visibility = visible ? .hidden : .always }
        })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(text.about, systemImage: "info.circle") { [weak self] in
            self?.onAbout?()
        })
        menu.addItem(ActionMenuItem(text.quit, systemImage: "power", key: "q") { [weak self] in
            self?.store.actions.quit()
        })
        // Retained until the next menu so the chosen item's action is never sent to a released target.
        self.menu = menu
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }
}

#if DEBUG
extension StatusItemController {
    /// Opens or closes the popover for the debug harness.
    func debugSetPopoverShown(_ shown: Bool) {
        guard shown != popover.isShown else { return }
        togglePopover()
    }
}
#endif

/// The menu bar icon: a 16 pt template ring with the highest headline usage as its arc, a notch cut where
/// the window's time stands, and a dot while an agent waits.
enum MenuBarRing {
    /// Everything the icon and its VoiceOver text depend on, rounded so small changes do not redraw it.
    struct Key: Equatable {
        /// Whole percent used; `nil` without data.
        let usedPercent: Int?
        /// Elapsed share of the window in 1/64 steps; `nil` when unknown.
        let elapsedStep: Int?
        /// Agents waiting for the user; the icon shows a dot for any.
        let waitingCount: Int
        /// The language and region of the VoiceOver text.
        let l10n: Localizer

        static let elapsedSteps = 64

        var waiting: Bool { waitingCount > 0 }

        init(usedPercent: Int?, elapsedStep: Int?, waitingCount: Int, l10n: Localizer) {
            self.usedPercent = usedPercent
            self.elapsedStep = elapsedStep
            self.waitingCount = max(0, waitingCount)
            self.l10n = l10n
        }

        init(window: LimitWindow?, waitingCount: Int, now: Date, l10n: Localizer) {
            guard let window else {
                self.init(usedPercent: nil, elapsedStep: nil, waitingCount: waitingCount, l10n: l10n)
                return
            }
            let progress = WindowProgress(window: window, now: now)
            self.init(
                usedPercent: Int((progress.used * 100).rounded()),
                elapsedStep: progress.elapsed.map { Int(($0 * Double(Self.elapsedSteps)).rounded()) },
                waitingCount: waitingCount,
                l10n: l10n
            )
        }

        /// "Codometer, 64% used, 2 agents are waiting for you".
        var accessibilityText: String {
            l10n.statusItem.iconA11y(percent: usedPercent.map { l10n.format.percent(Double($0)) }, waitingCount: waitingCount)
        }
    }

    static func image(for key: Key) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(key, in: context)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = key.accessibilityText
        return image
    }

    private static func draw(_ key: Key, in context: CGContext) {
        let center = CGPoint(x: 8, y: 8)
        let radius: CGFloat = 5.9
        let line: CGFloat = 2.1
        let top = CGFloat.pi / 2

        context.setLineWidth(line)
        context.setLineCap(.butt)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.3).cgColor)
        if key.usedPercent == nil {
            // No data yet: a calm dotted track.
            context.setLineDash(phase: 0, lengths: [1.6, 1.9])
        }
        context.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        context.strokePath()
        context.setLineDash(phase: 0, lengths: [])

        if let usedPercent = key.usedPercent, usedPercent > 0 {
            let fraction = CGFloat(min(usedPercent, 100)) / 100
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineCap(fraction < 1 ? .round : .butt)
            context.addArc(center: center, radius: radius, startAngle: top, endAngle: top - fraction * .pi * 2, clockwise: true)
            context.strokePath()
        }

        if let step = key.elapsedStep, step > 0, step < Key.elapsedSteps {
            // The "now" notch: a short cut straight through the ring.
            let angle = top - CGFloat(step) / CGFloat(Key.elapsedSteps) * .pi * 2
            let inner = radius - line
            let outer = radius + line
            context.setBlendMode(.clear)
            context.setLineWidth(1.3)
            context.setLineCap(.butt)
            context.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
            context.addLine(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
            context.strokePath()
            context.setBlendMode(.normal)
        }

        if key.waiting {
            let dot = CGPoint(x: 13.3, y: 13.3)
            context.setBlendMode(.clear)
            context.fillEllipse(in: CGRect(x: dot.x - 3.4, y: dot.y - 3.4, width: 6.8, height: 6.8))
            context.setBlendMode(.normal)
            context.setFillColor(NSColor.black.cgColor)
            context.fillEllipse(in: CGRect(x: dot.x - 2.3, y: dot.y - 2.3, width: 4.6, height: 4.6))
        }
    }
}
