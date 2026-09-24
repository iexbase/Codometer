import CodometerL10n
import AppKit

/// The app's main menu.
///
/// Codometer is an agent app with no Dock icon, but it does open windows (Settings, onboarding). Without a main menu
/// AppKit has nothing to send ⌘C, ⌘V, ⌘Z, ⌘A, ⌘W or ⌘Q to, so text fields in those windows cannot be edited with the
/// keyboard at all. The menu is rebuilt whenever the language changes.
///
/// `MainMenuPlan` is the whole menu as plain values — titles come from `CodometerL10n`, actions are AppKit selectors —
/// so the tests check items, key equivalents and both languages without touching a menu bar.
struct MainMenuPlan {
    struct Item {
        /// `nil` for a separator.
        let title: String?
        let selector: Selector?
        let keyEquivalent: String
        let modifiers: NSEvent.ModifierFlags

        init(_ title: String, _ selector: Selector?, key: String = "", modifiers: NSEvent.ModifierFlags = .command) {
            self.title = title
            self.selector = selector
            keyEquivalent = key
            self.modifiers = key.isEmpty ? [] : modifiers
        }

        private init() {
            title = nil
            selector = nil
            keyEquivalent = ""
            modifiers = []
        }

        static let separator = Item()
        var isSeparator: Bool { title == nil }
    }

    struct Submenu {
        let title: String
        let items: [Item]
    }

    /// The app menu, whose title AppKit shows in bold. It is the brand name, never translated.
    static let applicationMenuTitle = "Codometer"

    let submenus: [Submenu]

    init(l10n: Localizer, aboutSelector: Selector) {
        let text = l10n.menu
        submenus = [
            Submenu(title: Self.applicationMenuTitle, items: [
                Item(text.about, aboutSelector),
                .separator,
                Item(text.settings, #selector(AppDelegate.openCodometerSettings(_:)), key: ","),
                .separator,
                Item(text.hideApp, #selector(NSApplication.hide(_:)), key: "h"),
                .separator,
                Item(text.quit, #selector(NSApplication.terminate(_:)), key: "q"),
            ]),
            Submenu(title: text.edit, items: [
                Item(text.undo, Selector(("undo:")), key: "z"),
                Item(text.redo, Selector(("redo:")), key: "z", modifiers: [.command, .shift]),
                .separator,
                Item(text.cut, #selector(NSText.cut(_:)), key: "x"),
                Item(text.copy, #selector(NSText.copy(_:)), key: "c"),
                Item(text.paste, #selector(NSText.paste(_:)), key: "v"),
                Item(text.selectAll, #selector(NSText.selectAll(_:)), key: "a"),
            ]),
            Submenu(title: text.window, items: [
                Item(text.close, #selector(NSWindow.performClose(_:)), key: "w"),
                Item(text.minimize, #selector(NSWindow.performMiniaturize(_:)), key: "m"),
            ]),
        ]
    }
}

@MainActor
enum MainMenu {
    /// The selector of the "About Codometer" item. Sent with no target, so it travels up the responder chain to
    /// `AppDelegate` and the item stays enabled whichever window is in front.
    static let aboutSelector = #selector(AppDelegate.showCodometerAboutPanel(_:))

    /// Builds the menu bar for one language.
    static func make(l10n: Localizer) -> NSMenu {
        let plan = MainMenuPlan(l10n: l10n, aboutSelector: aboutSelector)
        let bar = NSMenu()
        for submenu in plan.submenus {
            let holder = NSMenuItem()
            holder.title = submenu.title
            let menu = NSMenu(title: submenu.title)
            for item in submenu.items {
                menu.addItem(menuItem(for: item))
            }
            holder.submenu = menu
            bar.addItem(holder)
        }
        return bar
    }

    private static func menuItem(for item: MainMenuPlan.Item) -> NSMenuItem {
        guard let title = item.title else { return .separator() }
        // The title is a localized phrase; `NSMenuItem(title:)` never gets a literal (lint `LiteralUIAPI`).
        let menuItem = NSMenuItem(title: title, action: item.selector, keyEquivalent: item.keyEquivalent)
        menuItem.keyEquivalentModifierMask = item.modifiers
        return menuItem
    }
}
