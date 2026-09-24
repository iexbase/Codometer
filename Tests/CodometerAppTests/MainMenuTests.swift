@testable import CodometerApp
import CodometerL10n
import AppKit
import Foundation
import Testing

/// The main menu: the items the Settings and onboarding windows need, their key equivalents, and both languages.
@MainActor
@Suite("Main menu")
struct MainMenuTests {
    private func plan(_ l10n: Localizer) -> MainMenuPlan {
        MainMenuPlan(l10n: l10n, aboutSelector: MainMenu.aboutSelector)
    }

    @Test("Three menus, in the order macOS expects")
    func structure() {
        let english = plan(.testEnglish)
        #expect(english.submenus.map(\.title) == ["Codometer", "Edit", "Window"])
        let russian = plan(.testRussian)
        #expect(russian.submenus.map(\.title) == ["Codometer", "Правка", "Окно"])
        // The app menu keeps the brand name in every language.
        #expect(MainMenuPlan.applicationMenuTitle == "Codometer")
    }

    @Test("Every item the spec lists is there, with its key equivalent")
    func items() {
        let english = plan(.testEnglish)
        let keys = english.submenus.flatMap(\.items)
            .filter { !$0.isSeparator }
            .map { ($0.title ?? "", $0.keyEquivalent, $0.modifiers) }

        #expect(keys.map(\.0) == [
            "About Codometer", "Settings…", "Hide Codometer", "Quit Codometer",
            "Undo", "Redo", "Cut", "Copy", "Paste", "Select All",
            "Close", "Minimize",
        ])
        let byTitle = Dictionary(uniqueKeysWithValues: keys.map { ($0.0, ($0.1, $0.2)) })
        #expect(byTitle["Settings…"]?.0 == ",")
        #expect(byTitle["Quit Codometer"]?.0 == "q")
        #expect(byTitle["Hide Codometer"]?.0 == "h")
        #expect(byTitle["Cut"]?.0 == "x")
        #expect(byTitle["Copy"]?.0 == "c")
        #expect(byTitle["Paste"]?.0 == "v")
        #expect(byTitle["Select All"]?.0 == "a")
        #expect(byTitle["Undo"]?.0 == "z")
        #expect(byTitle["Redo"]?.0 == "z")
        #expect(byTitle["Redo"]?.1 == [.command, .shift])
        #expect(byTitle["Undo"]?.1 == [.command])
        #expect(byTitle["Close"]?.0 == "w")
        #expect(byTitle["Minimize"]?.0 == "m")
        // About has no shortcut, so no modifier is claimed for it either.
        #expect(byTitle["About Codometer"]?.0 == "")
        #expect(byTitle["About Codometer"]?.1 == [])
    }

    @Test("Every item is translated, and no two items in one menu share a key equivalent")
    func localizedAndUnambiguous() {
        for l10n in [Localizer.testEnglish, .testRussian] {
            let menus = plan(l10n).submenus
            for menu in menus {
                #expect(!menu.title.isEmpty)
                for item in menu.items where !item.isSeparator {
                    #expect(item.title?.isEmpty == false)
                    #expect(item.selector != nil)
                }
            }
            let shortcuts = menus.flatMap(\.items)
                .filter { !$0.isSeparator && !$0.keyEquivalent.isEmpty }
                .map { "\($0.keyEquivalent)-\($0.modifiers.rawValue)" }
            #expect(Set(shortcuts).count == shortcuts.count)
        }
        let english = plan(.testEnglish).submenus.flatMap(\.items).compactMap(\.title)
        let russian = plan(.testRussian).submenus.flatMap(\.items).compactMap(\.title)
        #expect(english.count == russian.count)
        // Every item really is translated: no English title survives into the Russian menu.
        #expect(Set(english).isDisjoint(with: russian))
    }

    @Test("The built menu bar matches the plan")
    func builtMenu() {
        for l10n in [Localizer.testEnglish, .testRussian] {
            let bar = MainMenu.make(l10n: l10n)
            let plan = plan(l10n)
            #expect(bar.items.count == plan.submenus.count)
            for (item, submenu) in zip(bar.items, plan.submenus) {
                #expect(item.title == submenu.title)
                let menu = item.submenu
                #expect(menu?.title == submenu.title)
                #expect(menu?.items.count == submenu.items.count)
                for (built, planned) in zip(menu?.items ?? [], submenu.items) {
                    #expect(built.isSeparatorItem == planned.isSeparator)
                    guard !planned.isSeparator else { continue }
                    #expect(built.title == planned.title)
                    #expect(built.action == planned.selector)
                    #expect(built.keyEquivalent == planned.keyEquivalent)
                    #expect(built.keyEquivalentModifierMask == planned.modifiers)
                    // No explicit target: the item travels up the responder chain, so it works in every window.
                    #expect(built.target == nil)
                }
            }
        }
    }

    @Test("About credits are localized, and a repository link only appears for a valid GitHub address")
    func aboutCredits() {
        for l10n in [Localizer.testEnglish, .testRussian] {
            let plain = AboutPanelText.credits(l10n: l10n, repository: nil)
            #expect(plain.string == l10n.lifecycle.aboutCredits)
            let url = AboutPanelText.validatedRepositoryURL("https://github.com/owner/codometer")
            #expect(url != nil)
            let linked = AboutPanelText.credits(l10n: l10n, repository: url)
            #expect(linked.string.contains(l10n.lifecycle.aboutCredits))
            #expect(linked.string.contains("https://github.com/owner/codometer"))
        }
    }

    @Test("Only a plain https://github.com/<owner>/<repo> address is shown")
    func repositoryValidation() {
        #expect(AboutPanelText.validatedRepositoryURL("https://github.com/owner/repo") != nil)
        #expect(AboutPanelText.validatedRepositoryURL("https://github.com/owner-1/repo.name_2") != nil)
        #expect(AboutPanelText.validatedRepositoryURL("http://github.com/owner/repo") == nil)
        #expect(AboutPanelText.validatedRepositoryURL("https://github.com.evil.example/owner/repo") == nil)
        #expect(AboutPanelText.validatedRepositoryURL("https://github.com/owner") == nil)
        #expect(AboutPanelText.validatedRepositoryURL("https://github.com/owner/repo/issues") == nil)
        #expect(AboutPanelText.validatedRepositoryURL("https://github.com/owner/repo?x=1") == nil)
        #expect(AboutPanelText.validatedRepositoryURL("https://github.com/owner/repo#top") == nil)
        #expect(AboutPanelText.validatedRepositoryURL("https://user:pass@github.com/owner/repo") == nil)
        #expect(AboutPanelText.validatedRepositoryURL("https://github.com:8443/owner/repo") == nil)
        #expect(AboutPanelText.validatedRepositoryURL("https://github.com/owner/../../etc") == nil)
        #expect(AboutPanelText.validatedRepositoryURL("javascript:alert(1)") == nil)
        #expect(AboutPanelText.validatedRepositoryURL("") == nil)
        #expect(AboutPanelText.repositoryKey == "CodometerRepositoryURL")
    }
}
