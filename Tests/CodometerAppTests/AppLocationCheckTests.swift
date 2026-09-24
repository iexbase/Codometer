@testable import CodometerApp
import CodometerCore
import CodometerL10n
import Foundation
import Testing

/// Where the app may run from, and the alert that stops the launch when it may not.
@Suite("App location check")
struct AppLocationCheckTests {
    private let home = "/Users/person"

    private func kind(_ path: String, readOnly: Bool = false) -> AppLocationKind {
        AppLocationCheck.classify(bundlePath: path, isReadOnlyVolume: readOnly, homePath: home)
    }

    @Test("An installed copy is recognised, anywhere else is only noted")
    func installedLocations() {
        #expect(kind("/Applications/Codometer.app") == .applications)
        #expect(kind("/Applications/Utilities/Codometer.app") == .applications)
        #expect(kind("/Users/person/Applications/Codometer.app") == .userApplications)
        #expect(kind("/Users/person/Developer/Codometer/build/Codometer.app") == .other)
        // A folder whose name merely starts with "/Applications" is not inside it.
        #expect(kind("/ApplicationsOld/Codometer.app") == .other)
        #expect(kind("/Users/person/ApplicationsOld/Codometer.app") == .other)
    }

    @Test("A disk image, App Translocation and read-only volumes are told apart")
    func blockedLocations() {
        #expect(kind("/Volumes/Codometer 1.0.0/Codometer.app", readOnly: true) == .diskImage)
        // A writable volume under /Volumes is still a mounted volume, not an installed copy.
        #expect(kind("/Volumes/Backup/Codometer.app") == .diskImage)
        #expect(kind("/private/var/folders/x1/AppTranslocation/ABC/d/Codometer.app") == .translocated)
        // Translocation wins over everything: the path is also read-only.
        #expect(kind("/private/var/folders/x1/AppTranslocation/ABC/d/Codometer.app", readOnly: true) == .translocated)
        // `hdiutil -mountrandom` mounts outside /Volumes; `volumeIsReadOnly` still catches them.
        #expect(kind("/private/tmp/dmg.XXXX/Codometer.app", readOnly: true) == .readOnlyVolume)
    }

    @Test("Only the three unstable locations stop a launch")
    func blocking() {
        #expect(AppLocationCheck.blocksLaunch(.translocated))
        #expect(AppLocationCheck.blocksLaunch(.diskImage))
        #expect(AppLocationCheck.blocksLaunch(.readOnlyVolume))
        #expect(!AppLocationCheck.blocksLaunch(.applications))
        #expect(!AppLocationCheck.blocksLaunch(.userApplications))
        #expect(!AppLocationCheck.blocksLaunch(.other))
    }

    @Test("The alert names the actual problem, in both languages")
    func alertText() {
        for l10n in [Localizer.testEnglish, .testRussian] {
            var seen: Set<String> = []
            for kind in [AppLocationKind.diskImage, .translocated, .readOnlyVolume] {
                let text = AppLocationAlertText(kind: kind, l10n: l10n)
                #expect(text.title == l10n.lifecycle.moveToApplicationsTitle)
                #expect(text.button == l10n.notification.quit)
                #expect(text.message.contains(l10n.lifecycle.installedCopyNeeded))
                // Each situation gets its own first sentence.
                let lead = text.message.components(separatedBy: "\n\n")[0]
                #expect(!seen.contains(lead))
                seen.insert(lead)
            }
        }
        let english = AppLocationAlertText(kind: .diskImage, l10n: .testEnglish)
        let russian = AppLocationAlertText(kind: .diskImage, l10n: .testRussian)
        #expect(english.message != russian.message)
        #expect(english.title.contains("Codometer"))
        #expect(russian.title.contains("Codometer"))
    }

    @Test("The alert text never leaks a path")
    func alertTextHasNoPaths() {
        for l10n in [Localizer.testEnglish, .testRussian] {
            for kind in [AppLocationKind.diskImage, .translocated, .readOnlyVolume] {
                let text = AppLocationAlertText(kind: kind, l10n: l10n)
                #expect(!text.message.contains("/Users/"))
                #expect(!text.message.contains("/Volumes/"))
            }
        }
    }
}
