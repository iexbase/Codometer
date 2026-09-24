@testable import CodometerApp
import CodometerCore
import Foundation
import Testing

/// Alert sounds ride on the notification, so macOS honours Focus and the per-app sound switch, and nothing sounds
/// while notifications are denied.
@Suite("Alert sound policy")
struct AlertSoundPolicyTests {
    private let everySoundExists: (String) -> Bool = { _ in true }
    private let noSoundExists: (String) -> Bool = { _ in false }

    private func settings(_ authorization: NotificationAuthorization, sound: Bool) -> NotificationDelivery {
        NotificationDelivery(authorization: authorization, soundEnabled: sound)
    }

    @Test("A silent step stays silent")
    func noSound() {
        #expect(AlertSoundPolicy.decision(
            sound: nil,
            settings: settings(.authorized, sound: true),
            isAvailable: everySoundExists
        ) == .silent)
    }

    @Test("Nothing sounds while notifications are denied or undecided")
    func deniedIsSilent() {
        for authorization in [NotificationAuthorization.denied, .notDetermined] {
            #expect(AlertSoundPolicy.decision(
                sound: .exhausted,
                settings: settings(authorization, sound: true),
                isAvailable: everySoundExists
            ) == .silent)
        }
        // The settings have not been read yet.
        #expect(AlertSoundPolicy.decision(
            sound: .exhausted,
            settings: .unknown,
            isAvailable: everySoundExists
        ) == .silent)
    }

    @Test("Sound switched off for Codometer in System Settings means silence, whatever the app setting says")
    func systemSoundOffIsSilent() {
        #expect(AlertSoundPolicy.decision(
            sound: .finished,
            settings: settings(.authorized, sound: false),
            isAvailable: everySoundExists
        ) == .silent)
    }

    @Test("An allowed sound is attached by name, and falls back to the system sound when the file is missing")
    func allowedSounds() {
        for authorization in [NotificationAuthorization.authorized, .provisional] {
            #expect(AlertSoundPolicy.decision(
                sound: .finished,
                settings: settings(authorization, sound: true),
                isAvailable: everySoundExists
            ) == .named("Glass.aiff"))
        }
        #expect(AlertSoundPolicy.decision(
            sound: .threshold,
            settings: settings(.authorized, sound: true),
            isAvailable: everySoundExists
        ) == .named("Tink.aiff"))
        #expect(AlertSoundPolicy.decision(
            sound: .waiting,
            settings: settings(.authorized, sound: true),
            isAvailable: everySoundExists
        ) == .named("Funk.aiff"))
        #expect(AlertSoundPolicy.decision(
            sound: .finished,
            settings: settings(.authorized, sound: true),
            isAvailable: noSoundExists
        ) == .systemDefault)
    }

    @Test("Every alert sound maps to a file in a folder macOS looks in")
    func everyAlertSoundHasAFile() {
        let manager = FileManager.default
        for sound in AlertSound.allCases {
            let name = sound.systemSoundName + AlertSoundPolicy.fileExtension
            let found = AlertSoundPolicy.soundDirectories.contains { manager.fileExists(atPath: $0 + "/" + name) }
            #expect(found, "no sound file for \(name)")
        }
    }

    @Test("Notification settings map to the app's own authorization values")
    func deliveryFlags() {
        #expect(!NotificationDelivery.unknown.allowsNotifications)
        #expect(!NotificationDelivery.unknown.soundEnabled)
        #expect(settings(.authorized, sound: false).allowsNotifications)
        #expect(settings(.provisional, sound: false).allowsNotifications)
        #expect(!settings(.denied, sound: true).allowsNotifications)
        #expect(!settings(.notDetermined, sound: true).allowsNotifications)
    }
}
