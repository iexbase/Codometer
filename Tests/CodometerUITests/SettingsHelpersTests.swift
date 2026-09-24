import CodometerCore
import CodometerL10n
@testable import CodometerUI
import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing

/// Settings copy in Russian (pinned to `.testRussian`, today's expectations) and English (`.testEnglish`).
@Suite("Settings copy")
struct SettingsCopyTests {
    private let en = Localizer.testEnglish
    private let ru = Localizer.testRussian
    private static let nbsp = "\u{00A0}"

    @Test("Russian plurals for account counts", arguments: [
        (0, "Нет аккаунтов"), (1, "1 аккаунт"), (3, "3 аккаунта"), (5, "5 аккаунтов"),
        (11, "11 аккаунтов"), (14, "14 аккаунтов"), (21, "21 аккаунт"), (22, "22 аккаунта"), (112, "112 аккаунтов"),
    ])
    func accountCount(count: Int, expected: String) {
        #expect(SettingsCopy.accountCount(count, l10n: .testRussian) == expected)
    }

    @Test("English account counts", arguments: [(0, "No accounts"), (1, "1 account"), (2, "2 accounts"), (21, "21 accounts")])
    func accountCountEnglish(count: Int, expected: String) {
        #expect(SettingsCopy.accountCount(count, l10n: .testEnglish) == expected)
    }

    @Test("Short-turn titles", arguments: [
        (0, "Выкл.", "Off"), (20, "20\u{00A0}с", "20s"), (60, "1\u{00A0}мин", "1m"),
        (90, "1\u{00A0}мин 30\u{00A0}с", "1m 30s"), (600, "10\u{00A0}мин", "10m"),
    ])
    func turnTitles(seconds: Int, russian: String, english: String) {
        #expect(SettingsCopy.turnThresholdTitle(seconds: seconds, l10n: .testRussian) == russian)
        #expect(SettingsCopy.turnThresholdTitle(seconds: seconds, l10n: .testEnglish) == english)
    }

    @Test("A stored short-turn length outside the offered list is still offered, in order")
    func turnOptions() throws {
        #expect(SettingsCopy.turnThresholdOptions(current: .standard) == SettingsCopy.turnThresholdChoices)
        #expect(SettingsCopy.turnThresholdOptions(current: try TurnAlertThreshold(seconds: 45)) == [0, 20, 45, 60, 180, 600])
        for seconds in SettingsCopy.turnThresholdChoices {
            #expect(TurnAlertThreshold.allowedSeconds.contains(seconds))
        }
    }

    @Test("Shortcut titles and key caps")
    func shortcuts() {
        #expect(SettingsCopy.title(.off, l10n: ru) == "Выкл.")
        #expect(SettingsCopy.title(.controlOptionCommandU, l10n: ru) == "⌃⌥⌘U")
        #expect(SettingsCopy.title(.controlOptionSpace, l10n: ru) == "⌃⌥Пробел")
        #expect(SettingsCopy.title(.off, l10n: en) == "Off")
        #expect(SettingsCopy.title(.controlOptionCommandU, l10n: en) == "⌃⌥⌘U")
        #expect(SettingsCopy.title(.controlOptionSpace, l10n: en) == "⌃⌥Space")
        #expect(SettingsCopy.keys(.off, l10n: en).isEmpty)
        #expect(SettingsCopy.keys(.controlOptionSpace, l10n: en) == ["⌃", "⌥", "Space"])
        #expect(SettingsCopy.shortcutChoices.last == .off)
        #expect(Set(SettingsCopy.shortcutChoices) == Set(GlobalShortcut.allCases))
        #expect(SettingsCopy.note(.controlOptionSpace, l10n: ru) == "В macOS это сочетание часто переключает раскладку. Если остров не открывается, выберите другое.")
        #expect(SettingsCopy.note(.controlOptionSpace, l10n: en) == "macOS often uses this shortcut to switch input sources. If the island doesn’t open, choose a different one.")
        #expect(SettingsCopy.note(.controlOptionCommandL, l10n: en) == nil)
    }

    @Test("The e-mail example follows the visibility setting")
    func emailExample() {
        let address = SettingsCopy.sampleEmail
        #expect(SettingsCopy.emailExample(address, visibility: .visible, l10n: ru) == address)
        let masked = SettingsCopy.emailExample(address, visibility: .masked, l10n: en)
        #expect(masked == DisplayText.maskEmail(address))
        #expect(!masked.contains("morgan"))
        #expect(masked.hasSuffix("@example.com"))
        #expect(SettingsCopy.emailExample(address, visibility: .hidden, l10n: ru) == "адрес не показывается")
        #expect(SettingsCopy.emailExample(address, visibility: .hidden, l10n: en) == "address not shown")
        #expect(EmailVisibility.allCases.map { SettingsCopy.title($0, l10n: en) } == ["Show", "Partially hide", "Hide"])
        #expect(EmailVisibility.allCases.map { SettingsCopy.title($0, l10n: ru) } == ["Показывать", "Частично скрывать", "Скрывать"])
    }

    @Test("Range bounds use the locale's separator and never end with one", arguments: [
        (5.0, "5", "5"), (0.75, "0,75", "0.75"), (1.5, "1,5", "1.5"), (2.001, "2", "2"), (-0.5, "-0,5", "-0.5"), (-0.001, "0", "0"),
    ])
    func rangeBounds(value: Double, russian: String, english: String) {
        let error = ValidationError.outOfRange(field: "appearance.scale", value: 9, lowerBound: value, upperBound: 10)
        #expect(SettingsCopy.settingsMessage(for: error, l10n: .testRussian) == "Введите значение от \(russian) до 10.")
        #expect(SettingsCopy.settingsMessage(for: error, l10n: .testEnglish) == "Use a value from \(english) to 10.")
    }

    @Test("Large bounds are grouped by the locale")
    func groupedBounds() {
        let error = ValidationError.outOfRange(field: "pollInterval", value: 9, lowerBound: 60, upperBound: 3_600)
        #expect(SettingsCopy.settingsMessage(for: error, l10n: en) == "Use a value from 60 to 3,600.")
        #expect(SettingsCopy.settingsMessage(for: error, l10n: ru) == "Введите значение от 60 до 3\(Self.nbsp)600.")
    }

    @Test("Validation messages name the problem in Russian")
    func messages() {
        #expect(SettingsCopy.settingsMessage(for: .tooLong(field: "groups", length: 9, maximum: 8), l10n: ru) == "Можно создать не больше 8 групп.")
        #expect(SettingsCopy.settingsMessage(for: .duplicate(field: "groups.name", value: "Работа"), l10n: ru) == "Группа «Работа» уже есть.")
        #expect(SettingsCopy.settingsMessage(for: .inconsistent(field: "appearance.bands", reason: ""), l10n: ru) == "Жёлтый порог должен быть ниже красного.")
        #expect(SettingsCopy.settingsMessage(for: .outOfRange(field: "appearance.scale", value: 2, lowerBound: 0.75, upperBound: 1.5), l10n: ru) == "Введите значение от 0,75 до 1,5.")
        #expect(SettingsCopy.groupMessage(for: .empty(field: "account.label"), l10n: ru) == "Введите название группы.")
        #expect(SettingsCopy.groupMessage(for: .tooLong(field: "account.label", length: 41, maximum: 40), l10n: ru) == "Название группы — не длиннее 40 символов.")
        #expect(SettingsCopy.accountMessage(for: .empty(field: "account.label"), l10n: ru) == "Введите название.")
        #expect(SettingsCopy.accountMessage(for: .notAbsolutePath(field: "account.directory"), l10n: ru) == "Укажите полный путь к папке профиля.")
        #expect(SettingsCopy.accountMessage(for: .duplicate(field: "accounts.directory", value: "/x"), l10n: ru) == "Этот профиль уже отслеживается.")
        #expect(SettingsCopy.accountMessage(for: .outOfRange(field: "account.pollInterval", value: 60, lowerBound: 120, upperBound: 3_600), l10n: ru) == "Слишком частое обновление для этого сервиса.")
    }

    @Test("Russian limits agree with their count")
    func russianLimitPlurals() {
        #expect(SettingsCopy.settingsMessage(for: .tooLong(field: "groups", length: 2, maximum: 1), l10n: ru) == "Можно создать не больше 1 группы.")
        #expect(SettingsCopy.settingsMessage(for: .tooLong(field: "accounts", length: 17, maximum: 16), l10n: ru) == "Можно отслеживать не больше 16 аккаунтов.")
        #expect(SettingsCopy.settingsMessage(for: .tooLong(field: "accounts", length: 22, maximum: 21), l10n: ru) == "Можно отслеживать не больше 21 аккаунта.")
        #expect(SettingsCopy.settingsMessage(for: .tooLong(field: "alerts.thresholds", length: 7, maximum: 6), l10n: ru) == "Можно выбрать не больше 6 порогов.")
        #expect(SettingsCopy.settingsMessage(for: .tooLong(field: "appVersion", length: 33, maximum: 32), l10n: ru) == "Не длиннее 32 символов.")
        #expect(SettingsCopy.accountMessage(for: .tooLong(field: "account.label", length: 22, maximum: 21), l10n: ru) == "Название — не длиннее 21 символа.")
    }

    @Test("Validation messages in English")
    func messagesEnglish() {
        #expect(SettingsCopy.settingsMessage(for: .notFinite(field: "appearance.scale"), l10n: en) == "Enter a number.")
        #expect(SettingsCopy.settingsMessage(for: .empty(field: "x"), l10n: en) == "This field can’t be empty.")
        #expect(SettingsCopy.settingsMessage(for: .tooLong(field: "groups", length: 9, maximum: 8), l10n: en) == "You can create up to 8 groups.")
        #expect(SettingsCopy.settingsMessage(for: .tooLong(field: "accounts", length: 17, maximum: 16), l10n: en) == "You can track up to 16 accounts.")
        #expect(SettingsCopy.settingsMessage(for: .tooLong(field: "alerts.thresholds", length: 7, maximum: 6), l10n: en) == "You can choose up to 6 thresholds.")
        #expect(SettingsCopy.settingsMessage(for: .tooLong(field: "appVersion", length: 2, maximum: 1), l10n: en) == "Use up to 1 character.")
        #expect(SettingsCopy.settingsMessage(for: .invalidCharacters(field: "x"), l10n: en) == "Some characters aren’t allowed.")
        #expect(SettingsCopy.settingsMessage(for: .duplicate(field: "groups.name", value: "Work"), l10n: en) == "A group named “Work” already exists.")
        #expect(SettingsCopy.settingsMessage(for: .duplicate(field: "accounts.directory", value: "/x"), l10n: en) == "You’re already tracking this profile.")
        #expect(SettingsCopy.settingsMessage(for: .duplicate(field: "x", value: "y"), l10n: en) == "This value is already in use.")
        #expect(SettingsCopy.settingsMessage(for: .inconsistent(field: "appearance.bands", reason: ""), l10n: en) == "Set the yellow threshold below the red one.")
        #expect(SettingsCopy.settingsMessage(for: .inconsistent(field: "groups.id", reason: ""), l10n: en) == "This group no longer exists.")
        #expect(SettingsCopy.settingsMessage(for: .inconsistent(field: "accounts.id", reason: ""), l10n: en) == "This account no longer exists.")
        #expect(SettingsCopy.settingsMessage(for: .inconsistent(field: "x", reason: ""), l10n: en) == "These settings conflict.")
        #expect(SettingsCopy.groupMessage(for: .empty(field: "account.label"), l10n: en) == "Enter a group name.")
        #expect(SettingsCopy.groupMessage(for: .tooLong(field: "account.label", length: 41, maximum: 40), l10n: en) == "Use up to 40 characters for the group name.")
        #expect(SettingsCopy.groupMessage(for: .invalidCharacters(field: "account.label"), l10n: en) == "Some characters in the name aren’t allowed.")
        #expect(SettingsCopy.accountMessage(for: .empty(field: "account.label"), l10n: en) == "Enter a name.")
        #expect(SettingsCopy.accountMessage(for: .tooLong(field: "account.label", length: 41, maximum: 40), l10n: en) == "Use up to 40 characters for the name.")
        #expect(SettingsCopy.accountMessage(for: .empty(field: "account.directory"), l10n: en) == "Enter the full path to the profile folder.")
        #expect(SettingsCopy.accountMessage(for: .outOfRange(field: "account.pollInterval", value: 60, lowerBound: 120, upperBound: 3_600), l10n: en) == "That’s more often than this service allows.")
    }

    @Test("Panes that don’t pass a localizer yet get English")
    func defaultLanguage() {
        #expect(SettingsCopy.settingsMessage(for: .empty(field: "x")) == "This field can’t be empty.")
        #expect(SettingsCopy.title(GlobalShortcut.off) == "Off")
        #expect(SettingsCopy.widgetNote == SettingsCopy.widgetNote(l10n: .testEnglish))
        #expect(SettingsCopy.widgetNote(l10n: ru).contains("«Нет данных»"))
        #expect(SettingsCopy.widgetNote(l10n: en).contains("“No data.”"))
    }

    @Test("Every trigger has a distinct title, an explanation and a stage hint in both languages")
    func triggers() {
        for l10n in [en, ru] {
            let titles = IslandOpenTrigger.allCases.map { SettingsCopy.title($0, l10n: l10n) }
            #expect(Set(titles).count == IslandOpenTrigger.allCases.count)
            for trigger in IslandOpenTrigger.allCases {
                #expect(!SettingsCopy.explanation(trigger, l10n: l10n).isEmpty)
                #expect(!SettingsCopy.stageHint(trigger, l10n: l10n).isEmpty)
            }
        }
        #expect(IslandOpenTrigger.allCases.map { SettingsCopy.title($0, l10n: en) } == ["Hover", "Click", "Hover or click"])
    }

    @Test("Refresh intervals read as words, with Russian agreement", arguments: [
        (60, "Every minute", "Каждую минуту"), (120, "Every 2 minutes", "Каждые 2 минуты"), (300, "Every 5 minutes", "Каждые 5 минут"),
        (1_260, "Every 21 minutes", "Каждую 21 минуту"), (3_600, "Every hour", "Каждый час"),
        (90, "Every 1m 30s", "Каждые 1\u{00A0}мин 30\u{00A0}с"),
    ])
    func refreshIntervals(seconds: Int, english: String, russian: String) {
        #expect(SettingsCopy.refreshInterval(seconds: seconds, l10n: .testEnglish) == english)
        #expect(SettingsCopy.refreshInterval(seconds: seconds, l10n: .testRussian) == russian)
    }

    @Test("An account row's caption names the folder and the refresh interval")
    func profileCaption() {
        #expect(SettingsCopy.profileCaption(path: "~/.claude", refreshSeconds: 300, l10n: en) == "~/.claude · every 5 min")
        #expect(SettingsCopy.profileCaption(path: "~/.claude", refreshSeconds: 300, l10n: ru) == "~/.claude · каждые 5\(Self.nbsp)мин")
        #expect(SettingsCopy.profileCaption(path: "~/.codex", refreshSeconds: 60, l10n: en) == "~/.codex · every minute")
        #expect(SettingsCopy.profileCaption(path: "~/.codex", refreshSeconds: 60, l10n: ru) == "~/.codex · каждую минуту")
        #expect(SettingsCopy.profileCaption(path: "~/.codex", refreshSeconds: 3_600, l10n: en) == "~/.codex · every hour")
        #expect(SettingsCopy.profileCaption(path: "~/.codex", refreshSeconds: 3_600, l10n: ru) == "~/.codex · каждый час")
        #expect(SettingsCopy.profileCaption(path: "~/.codex", refreshSeconds: 90, l10n: en) == "~/.codex · every 1m 30s")
        #expect(SettingsCopy.profileCaption(path: "~/.codex", refreshSeconds: 1_260, l10n: en) == "~/.codex · every 21 min")
        #expect(SettingsCopy.profileCaption(path: "~/.codex", refreshSeconds: 1_260, l10n: ru) == "~/.codex · каждую 21\(Self.nbsp)мин")
        #expect(SettingsCopy.profileCaption(path: "~/.codex", refreshSeconds: 1_320, l10n: ru) == "~/.codex · каждые 22\(Self.nbsp)мин")
    }

    @Test("Removing a group says what happens to its accounts, with Russian verb agreement")
    func groupRemoval() {
        #expect(ru.groups.removeMessage(accounts: 1) == "1 аккаунт останется в Codometer без группы.")
        #expect(ru.groups.removeMessage(accounts: 3) == "3 аккаунта останутся в Codometer без группы.")
        #expect(ru.groups.removeMessage(accounts: 11) == "11 аккаунтов останутся в Codometer без группы.")
        #expect(ru.groups.removeMessage(accounts: 21) == "21 аккаунт останется в Codometer без группы.")
        #expect(en.groups.removeMessage(accounts: 1) == "1 account will stay in Codometer without a group.")
        #expect(en.groups.removeMessage(accounts: 3) == "3 accounts will stay in Codometer without a group.")
        #expect(en.groups.removeTitle("Work") == "Remove the “Work” group?")
        #expect(ru.groups.removeTitle("Работа") == "Удалить группу «Работа»?")
        #expect(en.accounts.removeTitle("Work") == "Remove “Work”?")
        #expect(en.accounts.removeMessage == "The profile folder stays as it is. Only this account’s history in Codometer is deleted.")
        #expect(ru.accounts.removeMessage == "Папка профиля останется как есть — удалится только история аккаунта в Codometer.")
    }

    @Test("The editor and the second-account guide say what Codometer does, not how it reads files")
    func guideCopy() {
        #expect(en.accounts.editorSubtitle == "The profile folder determines which account Codometer tracks.")
        #expect(ru.accounts.editorSubtitle == "Папка профиля определяет, какой аккаунт отслеживает Codometer.")
        #expect(en.accounts.secondAccountFootnote == "The profile will appear under “Found on this Mac.” Codometer doesn’t switch accounts for you.")
        #expect(ru.accounts.secondAccountFootnote == "Профиль появится в разделе «Найдены на этом Mac». Codometer не переключает аккаунты автоматически.")
        #expect(SettingsCopy.widgetNote(l10n: en).contains("Email addresses follow your Appearance → Privacy setting."))
    }

    @Test("Menu items and push buttons are Title Case in English, sentence case in Russian")
    func casing() {
        #expect([en.accounts.addAccount, en.accounts.refreshNow, en.accounts.moveUp, en.accounts.moveDown, en.groups.removeGroup] == ["Add Account", "Refresh Now", "Move Up", "Move Down", "Remove Group"])
        #expect([ru.accounts.addAccount, ru.accounts.refreshNow, ru.accounts.moveUp, ru.accounts.moveDown, ru.groups.removeGroup] == ["Добавить аккаунт", "Обновить сейчас", "Переместить выше", "Переместить ниже", "Удалить группу"])
        #expect([en.accounts.newAccountTitle, en.accounts.editAccountTitle] == ["New Account", "Edit Account"])
    }

    @Test("VoiceOver labels name the account or group they act on")
    func accessibilityLabels() {
        #expect(en.accounts.actionsA11y("Work") == "Actions for Work")
        #expect(ru.accounts.actionsA11y("Work") == "Действия с аккаунтом Work")
        #expect(en.accounts.trackA11y("Work") == "Track Work")
        #expect(en.accounts.addFoundA11y("Claude") == "Add Claude")
        #expect(en.accounts.copyCommandA11y("Codex") == "Copy the Codex command")
        #expect(ru.accounts.copyCommandA11y("Codex") == "Скопировать команду для Codex")
        #expect(en.groups.removeGroupA11y("Work") == "Remove the “Work” group")
        #expect(en.groups.addSuggestedA11y("Work") == "Add group “Work”")
        #expect(ru.groups.addSuggestedA11y("Работа") == "Добавить группу «Работа»")
        #expect(en.groups.muteSessionAlertsA11y("Work") == "Mute session notifications for “Work”")
        #expect(ru.groups.muteUsageAlertsA11y("Работа") == "Без уведомлений о лимитах для группы «Работа»")
        #expect(SettingsCopy.profileCaptionA11y(path: "~/.claude", refreshSeconds: 300, l10n: en) == "~/.claude, refresh: Every 5 minutes")
        #expect(SettingsCopy.profileCaptionA11y(path: "~/.codex", refreshSeconds: 60, l10n: ru) == "~/.codex, обновление: Каждую минуту")
    }
}

/// Width checks for Settings copy with little room, measured with `NSString.size` in the fonts the views use, in both
/// languages. Budgets come from the layout at the narrowest Settings window (800 pt with a 250 pt sidebar: a 550 pt
/// detail column) or, for segmented pickers, from the Russian titles that shipped before the conversion and fit.
@MainActor
@Suite("Settings copy fit")
struct SettingsCopyFitTests {
    nonisolated private static let languages = [Localizer.testEnglish, .testRussian]
    private let callout = NSFont.preferredFont(forTextStyle: .callout)
    private let body = NSFont.preferredFont(forTextStyle: .body)
    private let captionFont = NSFont.monospacedSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .subheadline).pointSize, weight: .regular)

    private func width(_ text: String, _ font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
    }

    /// The widest stage hint that shipped on one line at the minimum window width
    /// («Клик раскрывает остров, клик мимо сворачивает. Остров можно перетащить.»).
    private var stageHintBudget: CGFloat {
        width("Клик раскрывает остров, клик мимо сворачивает. Остров можно перетащить.", callout)
    }

    @Test("Stage hints stay on one line at the minimum window width", arguments: languages)
    func stageHints(l10n: Localizer) {
        for trigger in IslandOpenTrigger.allCases {
            let hint = SettingsCopy.stageHint(trigger, l10n: l10n)
            #expect(width(hint, callout) <= stageHintBudget, "\(hint): \(width(hint, callout)) pt > \(stageHintBudget) pt")
        }
    }

    @Test("Trigger explanations fit their two reserved lines", arguments: languages)
    func explanations(l10n: Localizer) {
        // Two lines as wide as a stage hint, less a fifth for word wrapping.
        let budget = stageHintBudget * 2 * 0.8
        for trigger in IslandOpenTrigger.allCases {
            let text = SettingsCopy.explanation(trigger, l10n: l10n)
            #expect(width(text, callout) <= budget, "\(text): \(width(text, callout)) pt > \(budget) pt")
        }
    }

    @Test("A group's two mute checkboxes fit side by side in the narrowest window", arguments: languages)
    func muteCheckboxes(l10n: Localizer) {
        // Detail 550 − form insets 2×20 − row insets 2×10 − leading 34 = 456 pt; checkbox + gap 20 pt each, spacing 18 pt,
        // and 36 pt spare.
        let row = width(l10n.groups.muteSessionAlerts, callout) + width(l10n.groups.muteUsageAlerts, callout) + 2 * 20 + 18
        #expect(row <= 420, "\(row) pt")
    }

    @Test("An account row's caption fits at the default window width and its interval survives truncation", arguments: languages)
    func profileCaption(l10n: Localizer) {
        let folders: [(String, ProviderKind)] = [("~/.claude-work", .claude), ("~/.codex-work", .codex)]
        for (folder, provider) in folders {
            for seconds in [60, 120, 180, 300, 600, 900, 1_800, 3_600] where seconds >= provider.minimumPollInterval.seconds {
                let caption = SettingsCopy.profileCaption(path: folder, refreshSeconds: seconds, l10n: l10n)
                // At 920 pt the text column next to the ring and the group, actions and tracking controls is about 330 pt.
                #expect(width(caption, captionFont) <= 300, "\(caption): \(width(caption, captionFont)) pt")
                // In the narrowest window the caption truncates in the middle; the interval keeps most of the room.
                let interval = String(caption.split(separator: "·").last ?? "")
                #expect(width(interval, captionFont) <= 110, "\(interval): \(width(interval, captionFont)) pt")
            }
        }
    }

    @Test("Segmented option titles are no wider than the Russian titles that shipped", arguments: languages)
    func segmentedTitles(l10n: Localizer) {
        func total(_ titles: [String]) -> CGFloat { titles.map { width($0, body) }.reduce(0, +) }
        func widest(_ titles: [String]) -> CGFloat { titles.map { width($0, body) }.max() ?? 0 }
        let pickers: [(name: String, shipped: [String], current: [String])] = [
            ("open trigger", ["При наведении", "По клику", "Наведение или клик"], IslandOpenTrigger.allCases.map { SettingsCopy.title($0, l10n: l10n) }),
            ("e-mail", ["Показывать", "Частично скрывать", "Скрывать"], EmailVisibility.allCases.map { SettingsCopy.title($0, l10n: l10n) }),
            ("shortcut", ["⌃⌥⌘U", "⌃⌥Пробел", "⌃⌥⌘L", "Выкл."], SettingsCopy.shortcutChoices.map { SettingsCopy.title($0, l10n: l10n) }),
            ("short turns", ["всегда", "20 с", "1 мин", "3 мин", "10 мин"], SettingsCopy.turnThresholdChoices.map { SettingsCopy.turnThresholdTitle(seconds: $0, l10n: l10n) }),
        ]
        for picker in pickers {
            #expect(total(picker.current) <= total(picker.shipped), "\(picker.name): \(picker.current)")
            #expect(widest(picker.current) <= widest(picker.shipped), "\(picker.name): \(picker.current)")
        }
    }
}

@Suite("Settings group editor")
struct SettingsGroupEditorTests {
    private func settings(accounts: Int = 2) throws -> AppSettings {
        let profiles = try (0..<accounts).map { index in
            try AccountProfile(
                id: UIFixture.accountID("many/\(index)"),
                provider: .claude,
                label: try AccountLabel(validating: "Claude \(index)"),
                directory: try ProfileDirectory(validating: "/Users/me/.claude-\(index)")
            )
        }
        return try AppSettings(accounts: profiles)
    }

    @Test("Adding trims the name and rejects empty names and case-insensitive duplicates")
    func adding() throws {
        let added = try SettingsGroupEditor.adding(named: "  Работа  ", to: try settings())
        #expect(added.groups.map(\.name.value) == ["Работа"])
        #expect(throws: ValidationError.duplicate(field: "groups.name", value: "работа")) {
            try SettingsGroupEditor.adding(named: "работа", to: added)
        }
        #expect(throws: ValidationError.empty(field: "account.label")) {
            try SettingsGroupEditor.adding(named: "   ", to: added)
        }
    }

    @Test("A ninth group is rejected")
    func maximum() throws {
        var current = try settings()
        for index in 0..<AppSettings.maximumGroups {
            current = try SettingsGroupEditor.adding(named: "Группа \(index)", to: current)
        }
        let full = current
        #expect(throws: ValidationError.tooLong(field: "groups", length: AppSettings.maximumGroups + 1, maximum: AppSettings.maximumGroups)) {
            try SettingsGroupEditor.adding(named: "Ещё одна", to: full)
        }
        #expect(SettingsGroupEditor.suggestions(for: full, l10n: .testRussian).isEmpty)
        #expect(SettingsGroupEditor.suggestions(for: full, l10n: .testEnglish).isEmpty)
    }

    @Test("Assigning, renaming, muting and filtering change only what they name")
    func editing() throws {
        var current = try SettingsGroupEditor.adding(named: "Работа", to: try settings())
        current = try SettingsGroupEditor.adding(named: "Личное", to: current)
        let work = try #require(current.groups.first)
        let account = try #require(current.accounts.first)

        current = try SettingsGroupEditor.assigning(account.id, to: work.id, in: current)
        #expect(current.account(account.id)?.groupID == work.id)
        #expect(SettingsGroupEditor.accountCount(of: work.id, in: current) == 1)

        current = try SettingsGroupEditor.renaming(work.id, to: " Офис ", in: current)
        #expect(current.group(work.id)?.name.value == "Офис")
        #expect(current.account(account.id)?.groupID == work.id)

        current = try SettingsGroupEditor.settingMutes(work.id, sessions: true, in: current)
        #expect(current.group(work.id)?.mutesSessionAlerts == true)
        #expect(current.group(work.id)?.mutesUsageAlerts == false)
        current = try SettingsGroupEditor.settingMutes(work.id, usage: true, in: current)
        #expect(current.group(work.id)?.mutesSessionAlerts == true)
        #expect(current.group(work.id)?.mutesUsageAlerts == true)

        current = try SettingsGroupEditor.filteringIsland(to: work.id, in: current)
        #expect(current.appearance.railGroupFilter == work.id)

        current = try SettingsGroupEditor.assigning(account.id, to: nil, in: current)
        #expect(current.account(account.id)?.groupID == nil)
    }

    @Test("Removing a group ungroups its accounts and clears an island filter on it")
    func removing() throws {
        var current = try SettingsGroupEditor.adding(named: "Работа", to: try settings())
        let work = try #require(current.groups.first)
        let account = try #require(current.accounts.first)
        current = try SettingsGroupEditor.assigning(account.id, to: work.id, in: current)
        current = try SettingsGroupEditor.filteringIsland(to: work.id, in: current)

        let removed = try SettingsGroupEditor.removing(work.id, from: current)
        #expect(removed.groups.isEmpty)
        #expect(removed.account(account.id)?.groupID == nil)
        #expect(removed.appearance.railGroupFilter == nil)
        #expect(removed.accounts.count == current.accounts.count)
    }

    @Test("Unknown groups and accounts are rejected")
    func unknownIDs() throws {
        let current = try SettingsGroupEditor.adding(named: "Работа", to: try settings())
        let stranger = AccountGroupID()
        let account = try #require(current.accounts.first)
        #expect(throws: ValidationError.self) { try SettingsGroupEditor.removing(stranger, from: current) }
        #expect(throws: ValidationError.self) { try SettingsGroupEditor.renaming(stranger, to: "X", in: current) }
        #expect(throws: ValidationError.self) { try SettingsGroupEditor.settingMutes(stranger, sessions: true, in: current) }
        #expect(throws: ValidationError.self) { try SettingsGroupEditor.filteringIsland(to: stranger, in: current) }
        #expect(throws: ValidationError.self) { try SettingsGroupEditor.assigning(account.id, to: stranger, in: current) }
        #expect(throws: ValidationError.self) { try SettingsGroupEditor.assigning(AccountID(), to: nil, in: current) }
    }

    @Test("Suggestions disappear once used, ignoring case")
    func suggestions() throws {
        let empty = try settings()
        #expect(SettingsGroupEditor.suggestions(for: empty, l10n: .testRussian) == ["Работа", "Личное"])
        let withWork = try SettingsGroupEditor.adding(named: "работа", to: empty)
        #expect(SettingsGroupEditor.suggestions(for: withWork, l10n: .testRussian) == ["Личное"])
        let both = try SettingsGroupEditor.adding(named: "Личное", to: withWork)
        #expect(SettingsGroupEditor.suggestions(for: both, l10n: .testRussian).isEmpty)
    }

    @Test("Suggestions follow the interface language, and created groups keep their names")
    func suggestionsEnglish() throws {
        let empty = try settings()
        #expect(SettingsGroupEditor.suggestions(for: empty, l10n: .testEnglish) == ["Work", "Personal"])
        let withWork = try SettingsGroupEditor.adding(named: "work", to: empty)
        #expect(SettingsGroupEditor.suggestions(for: withWork, l10n: .testEnglish) == ["Personal"])
        // A group made from a Russian suggestion is user data: it stays «Работа» and English still offers both names.
        let russianWork = try SettingsGroupEditor.adding(named: "Работа", to: empty)
        #expect(russianWork.groups.map(\.name.value) == ["Работа"])
        #expect(SettingsGroupEditor.suggestions(for: russianWork, l10n: .testEnglish) == ["Work", "Personal"])
    }
}

@Suite("Settings stage geometry")
struct SettingsStageGeometryTests {
    private let display = CGSize(width: 520, height: 444)

    @Test("The preview keeps its preferred scale while the deck fits")
    func preferredScale() {
        #expect(SettingsStageGeometry.displayScale(display: display, deck: .zero) == SettingsStageGeometry.preferredScale)
        #expect(SettingsStageGeometry.displayScale(display: display, deck: CGSize(width: 380, height: 300)) == SettingsStageGeometry.preferredScale)
    }

    @Test("A tall deck scales the preview down in steps, never below the minimum")
    func fittedScale() {
        let scale = SettingsStageGeometry.displayScale(display: display, deck: CGSize(width: 380, height: 627))
        #expect(abs(scale - 0.6) < 1e-9)
        let steps = scale / SettingsStageGeometry.scaleStep
        #expect(abs(steps - steps.rounded()) < 1e-6)
        let needed = 627 + SettingsStageGeometry.menuBarHeight + SettingsStageGeometry.dockReserve + SettingsStageGeometry.breathingRoom * 2
        #expect(needed * scale <= display.height)
        #expect(SettingsStageGeometry.displayScale(display: display, deck: CGSize(width: 4_000, height: 4_000)) == SettingsStageGeometry.minimumScale)
    }

    @Test("The virtual screen keeps the menu bar and Dock out of its visible frame")
    func screen() {
        let screen = SettingsStageGeometry.screen(display: CGSize(width: 400, height: 300), scale: 0.5)
        #expect(screen.frame == CGRect(x: 0, y: 0, width: 800, height: 600))
        #expect(screen.visible.minY == SettingsStageGeometry.dockReserve)
        #expect(screen.visible.maxY == 600 - SettingsStageGeometry.menuBarHeight)
    }

    @Test("Rail and deck frames match the island geometry, and coordinates flip both ways")
    func frames() throws {
        let screen = SettingsStageGeometry.screen(display: CGSize(width: 400, height: 300), scale: 0.5)
        let layout = IslandLayout(edge: .top, anchor: .top, style: .attached, metrics: IslandMetrics(scale: 1))
        let rail = CGSize(width: 200, height: 40)
        let deck = CGSize(width: 400, height: 300)
        #expect(SettingsStageGeometry.windowFrame(rail: .zero, deck: deck, layout: layout, offset: 0.5, showsDeck: true, in: screen) == nil)

        let resting = try #require(SettingsStageGeometry.windowFrame(rail: rail, deck: deck, layout: layout, offset: 0.5, showsDeck: false, in: screen))
        #expect(resting == CGRect(x: 300, y: 560, width: 200, height: 40))
        let open = try #require(SettingsStageGeometry.windowFrame(rail: rail, deck: deck, layout: layout, offset: 0.5, showsDeck: true, in: screen))
        #expect(open == CGRect(x: 200, y: 300, width: 400, height: 300))
        // Not measured yet: the rail frame, never a zero-sized deck.
        #expect(SettingsStageGeometry.windowFrame(rail: rail, deck: .zero, layout: layout, offset: 0.5, showsDeck: true, in: screen) == resting)

        #expect(SettingsStageGeometry.viewRect(resting, in: screen) == CGRect(x: 300, y: 0, width: 200, height: 40))
        #expect(SettingsStageGeometry.screenPoint(CGPoint(x: 10, y: 20), in: screen) == CGPoint(x: 10, y: 580))
    }

    @Test("A carried rail stays on the screen and a drop near the right edge lands there")
    func dragging() {
        let screen = SettingsStageGeometry.screen(display: CGSize(width: 400, height: 300), scale: 0.5)
        let rail = CGSize(width: 100, height: 40)
        #expect(SettingsStageGeometry.dragFrame(center: CGPoint(x: 5, y: 5), rail: rail, in: screen).origin == .zero)
        #expect(SettingsStageGeometry.dragFrame(center: CGPoint(x: 790, y: 590), rail: rail, in: screen).origin == CGPoint(x: 700, y: 560))

        let drop = SettingsStageGeometry.dropPlacement(at: CGPoint(x: 795, y: 300), rail: rail, style: .attached, in: screen)
        #expect(drop.edge == .right)
        #expect((0...1).contains(drop.offset))
    }
}

/// The Accounts pane, its groups section and the account editor in English and Russian, drawn the way the debug
/// harness draws Settings (an `NSHostingView` in an off-screen window, `cacheDisplay`), because `ImageRenderer` cannot
/// draw a `Form`. Runs only with `CODOMETER_SNAPSHOT_DIR`; writes `settings-accounts-…-en.png` and `…-ru.png`.
@MainActor
@Suite("Accounts settings snapshots", .enabled(if: ProcessInfo.processInfo.environment["CODOMETER_SNAPSHOT_DIR"] != nil))
struct AccountsSettingsSnapshotTests {
    private let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODOMETER_SNAPSHOT_DIR"] ?? "/tmp", isDirectory: true)
    private let now = Date(timeIntervalSince1970: 1_789_590_000)
    /// The Settings detail column: the default window (920 pt) and the narrowest one (800 pt with a 250 pt sidebar).
    private static let regularWidth: CGFloat = 710
    private static let narrowWidth: CGFloat = 550

    @Test("Accounts pane with accounts, groups and a found profile; empty pane; full groups; editor")
    func renderAccounts() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        _ = NSApplication.shared
        for language in [LanguagePreference.english, .russian] {
            let suffix = language.rawValue
            let store = try makeStore(language: language)
            try await render(AccountsPane(store: store), store: store, width: Self.regularWidth, height: 1_480, name: "settings-accounts-\(suffix)")
            try await render(AccountsPane(store: store), store: store, width: Self.narrowWidth, height: 1_560, name: "settings-accounts-narrow-\(suffix)")
            try await render(
                AccountsPane(store: store),
                store: store,
                width: Self.regularWidth,
                height: 1_480,
                scheme: .dark,
                name: "settings-accounts-dark-\(suffix)"
            )

            let empty = try makeStore(language: language, empty: true)
            try await render(AccountsPane(store: empty), store: empty, width: Self.regularWidth, height: 900, name: "settings-accounts-empty-\(suffix)")

            let full = try makeStore(language: language, fullGroups: true)
            try await render(
                Form { AccountGroupsSection(store: full, pendingRemoval: .constant(nil)) }.formStyle(.grouped),
                store: full,
                width: Self.narrowWidth,
                height: 1_120,
                name: "settings-groups-full-narrow-\(suffix)"
            )

            let account = try #require(store.settings.accounts.first)
            // The editor shows full paths; keep the real home folder out of the images.
            var editing = AccountDraft(editing: account)
            editing.directory = "/Users/me/.claude-work"
            var newDraft = AccountDraft(provider: .codex)
            newDraft.directory = "/Users/me/.codex-work"
            try await render(
                AccountEditorSheet(draft: editing, store: store) {},
                store: store,
                width: 540,
                height: 760,
                name: "settings-account-editor-\(suffix)"
            )
            try await render(
                AccountEditorSheet(draft: newDraft, store: empty) {},
                store: empty,
                width: 540,
                height: 720,
                name: "settings-account-editor-new-\(suffix)"
            )
        }
    }

    @Test("The Accounts pane and the Appearance rings with two accounts of one provider")
    func renderIdentity() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        _ = NSApplication.shared
        for language in [LanguagePreference.english, .russian] {
            let store = try makeStore(language: language, sharedProvider: true)
            try await render(
                AccountsPane(store: store),
                store: store,
                width: Self.regularWidth,
                height: 1_480,
                name: "settings-accounts-shared-provider-\(language.rawValue)"
            )
            var stage = IslandStageOptions()
            try await render(
                AppearancePane(store: store, stageOptions: Binding(get: { stage }, set: { stage = $0 })),
                store: store,
                width: Self.narrowWidth,
                height: 1_500,
                name: "settings-appearance-rings-narrow-\(language.rawValue)"
            )
        }
    }

    private func render(
        _ view: some View,
        store: TrackerStore,
        width: CGFloat,
        height: CGFloat,
        scheme: ColorScheme = .light,
        name: String
    ) async throws {
        let content = view
            .frame(width: width, height: height, alignment: .top)
            .background(Color(nsColor: .windowBackgroundColor))
            // What `SettingsRootView` injects in the app.
            .environment(\.l10n, store.localizer)
            .environment(\.locale, store.localizer.locale)
            .environment(\.colorScheme, scheme)
        let host = NSHostingView(rootView: content)
        host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let window = NSWindow(
            contentRect: NSRect(x: -30_000, y: -30_000, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = host.appearance
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        // Lets `onAppear` state (found profiles) settle before drawing.
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
        }
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }

    private func makeStore(
        language: LanguagePreference,
        empty: Bool = false,
        fullGroups: Bool = false,
        sharedProvider: Bool = false
    ) throws -> TrackerStore {
        let home = NSHomeDirectory()
        let work = AccountGroup(name: try AccountLabel(validating: language == .russian ? "Работа" : "Work"), mutesSessionAlerts: true)
        let personal = AccountGroup(name: try AccountLabel(validating: language == .russian ? "Личное" : "Personal"))
        var groups = [work, personal]
        if fullGroups {
            for index in 3...AppSettings.maximumGroups {
                groups.append(AccountGroup(name: try AccountLabel(validating: "Client \(index)")))
            }
        }
        let claude = try AccountProfile(
            id: UIFixture.accountID("accounts/work"),
            provider: .claude,
            label: try AccountLabel(validating: "Work"),
            directory: try ProfileDirectory(validating: home + "/.claude-work"),
            pollInterval: try PollInterval(seconds: 300),
            groupID: work.id,
            tint: sharedProvider ? .teal : .automatic,
            monogram: sharedProvider ? try AccountMonogram(validating: "W") : nil
        )
        let codex = try AccountProfile(
            id: UIFixture.accountID("accounts/personal"),
            provider: .codex,
            label: try AccountLabel(validating: "Personal"),
            directory: try ProfileDirectory(validating: home + "/.codex"),
            pollInterval: try PollInterval(seconds: 60),
            groupID: personal.id
        )
        let side = try AccountProfile(
            id: UIFixture.accountID("accounts/side"),
            provider: .claude,
            label: try AccountLabel(validating: "Side project"),
            directory: try ProfileDirectory(validating: home + "/.claude-side"),
            isEnabled: sharedProvider,
            pollInterval: try PollInterval(seconds: 3_600),
            tint: sharedProvider ? .pink : .automatic
        )
        var general = GeneralSettings()
        general.language = language
        let settings = empty
            ? try AppSettings(accounts: [], general: general)
            : try AppSettings(accounts: [claude, codex, side], groups: groups, general: general)
        let reading = try UsageReading(
            capturedAt: now.addingTimeInterval(-90),
            source: .claudeUsageCommand,
            buckets: [try LimitBucket(id: "claude", title: nil, windows: [
                try LimitWindow(id: "session", scope: .session, used: try Percentage(validating: 64), duration: .fiveHours, resetsAt: now.addingTimeInterval(8_040)),
                try LimitWindow(id: "week", scope: .weekly(model: nil), used: try Percentage(validating: 31), duration: .oneWeek, resetsAt: now.addingTimeInterval(3 * 86_400)),
            ], isLimitReached: false)],
            credits: nil
        )
        let state = empty ? TrackerState() : TrackerState(accounts: [
            AccountStatus(profile: claude, identity: AccountIdentity(email: "alex.morgan@example.com", organization: nil, plan: "Max"), reading: reading),
            AccountStatus(profile: codex, identity: AccountIdentity(email: nil, organization: nil, plan: "Plus"), issue: TrackerIssue(kind: .signedOut, detail: "not signed in", occurredAt: now)),
            AccountStatus(profile: side, reading: sharedProvider ? reading : nil),
        ])
        let found = DiscoveredAccount(provider: .codex, directory: try ProfileDirectory(validating: home + "/.codex-work"), suggestedLabel: "Codex · work")
        let actions = TrackerActions(
            refresh: { _ in },
            persistSettings: { _ in },
            discoverProfiles: { empty ? [] : [found] },
            revealDataFolder: {},
            setLaunchAtLogin: { _ in nil },
            openSettings: {},
            quit: {}
        )
        return TrackerStore(
            state: state,
            settings: settings,
            now: now,
            actions: actions,
            preferredLanguages: { ["en-US"] },
            region: { Locale(identifier: language == .russian ? "ru_RU" : "en_US") }
        )
    }
}

/// The account editor's Look section: what the draft resolves to, and whether the row fits.
@MainActor
@Suite("Account look settings")
struct AccountLookTests {
    nonisolated private static let languages = [Localizer.testEnglish, .testRussian]
    private let body = NSFont.preferredFont(forTextStyle: .body)

    private func width(_ text: String, _ font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
    }

    private func accounts() throws -> [AccountProfile] {
        [
            try UIFixture.profile("Work"),
            try UIFixture.profile("Personal"),
            try UIFixture.profile("Side", provider: .codex),
        ]
    }

    @Test("An account keeps its place among its provider's accounts; a new one comes last")
    func ordinals() throws {
        let list = try accounts()
        #expect(AccountDraft.ordinal(of: list[0].id, provider: .claude, in: list) == 1)
        #expect(AccountDraft.ordinal(of: list[1].id, provider: .claude, in: list) == 2)
        #expect(AccountDraft.ordinal(of: list[2].id, provider: .codex, in: list) == 1)
        #expect(AccountDraft.ordinal(of: nil, provider: .claude, in: list) == 3)
        #expect(AccountDraft.ordinal(of: nil, provider: .codex, in: list) == 2)
        // An id of another provider is not found among these, so the draft counts as new.
        #expect(AccountDraft.ordinal(of: list[2].id, provider: .claude, in: list) == 3)
    }

    @Test("An empty monogram field follows the name; a typed one is validated as it is")
    func monogramDraft() throws {
        let list = try accounts()
        var draft = AccountDraft(editing: list[0])
        #expect(draft.monogramText.isEmpty)
        #expect(try draft.validatedMonogram() == nil)
        #expect(draft.automaticMonogram(in: list)?.value == "W")

        draft.label = "Work account"
        #expect(draft.automaticMonogram(in: list)?.value == "WA")
        draft.label = "Codex"
        // Nothing but the provider's own name is left, so the number decides.
        #expect(draft.automaticMonogram(in: list)?.value == "1")
        draft.label = ""
        #expect(draft.automaticMonogram(in: list) == nil)

        draft.monogramText = "wa"
        #expect(try draft.validatedMonogram()?.value == "WA")
        draft.monogramText = " 🚀 "
        #expect(try draft.validatedMonogram()?.value == "🚀")
        draft.monogramText = "a b"
        #expect(throws: ValidationError.self) { try draft.validatedMonogram() }
    }

    @Test("The colour and the monogram survive a round trip through the draft")
    func roundTrip() throws {
        let account = try AccountProfile(
            id: UIFixture.accountID("accounts/editor"),
            provider: .claude,
            label: try AccountLabel(validating: "Work"),
            directory: try ProfileDirectory(validating: "/Users/me/.claude"),
            tint: .indigo,
            monogram: try AccountMonogram(validating: "W")
        )
        let draft = AccountDraft(editing: account)
        #expect(draft.tint == .indigo)
        #expect(draft.monogramText == "W")
        let saved = try draft.validated()
        #expect(saved.tint == .indigo)
        #expect(saved.monogram?.value == "W")
        #expect(saved.id == account.id)
    }

    @Test("A new account starts with an automatic colour and no monogram of its own")
    func newDraft() throws {
        let draft = AccountDraft(provider: .claude)
        #expect(draft.tint == .automatic)
        #expect(draft.monogramText.isEmpty)
        #expect(try draft.validatedMonogram() == nil)
    }

    @Test("The Look row fits the narrowest settings window in both languages", arguments: languages)
    func lookRowFits(l10n: Localizer) {
        // Detail 550 − form insets 2×20 − row insets 2×10 = 490 pt for a row.
        let room: CGFloat = 490
        let labels = [l10n.accountStyle.monogram, l10n.accountStyle.color]
        for label in labels {
            #expect(width(label, body) <= 160, "\(label): \(width(label, body)) pt")
        }
        // The monogram row: label, field, badge and the gaps between them.
        let monogramRow = width(l10n.accountStyle.monogram, body) + AccountEditorSheet.monogramFieldWidth + 30 + 2 * 10
        #expect(monogramRow <= room, "\(monogramRow) pt")
        // Nine swatches beside the "Color" label.
        let swatches = CGFloat(AccountTint.allCases.count) * TintSwatches.hitTarget + CGFloat(AccountTint.allCases.count - 1) * 2
        #expect(width(l10n.accountStyle.color, body) + swatches <= room, "\(swatches) pt of swatches")
    }

    @Test("The row's actions menu really is a 24 pt target", arguments: languages)
    func actionsMenuHitTarget(l10n: Localizer) {
        _ = NSApplication.shared
        let menu = AccountActionsMenu(
            label: "Work",
            canRefresh: true,
            isFirst: false,
            isLast: false,
            onEdit: {},
            onRefresh: {},
            onMove: { _ in },
            onRemove: {}
        )
        let host = NSHostingView(rootView: menu.environment(\.l10n, l10n))
        let size = host.fittingSize
        #expect(size.width >= AccountActionsMenu.hitTarget, "\(size.width) pt wide")
        #expect(size.height >= AccountActionsMenu.hitTarget, "\(size.height) pt tall")
        // The control itself has to be that big, not just the room around it.
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        let control = Self.deepestControl(in: host)
        #expect(control != nil, "no AppKit control inside the menu")
        if let control {
            #expect(control.bounds.height >= AccountActionsMenu.hitTarget, "control is \(control.bounds.height) pt tall")
            #expect(control.bounds.width >= AccountActionsMenu.hitTarget, "control is \(control.bounds.width) pt wide")
        }
    }

    /// The `NSControl` a SwiftUI `Menu` is backed by, wherever it sits in the hosted hierarchy.
    private static func deepestControl(in view: NSView) -> NSView? {
        if view is NSControl { return view }
        for subview in view.subviews {
            if let found = deepestControl(in: subview) { return found }
        }
        return nil
    }

    @Test("A swatch is a pointer target, not just a dot")
    func swatchHitTarget() {
        #expect(TintSwatches.hitTarget >= 24)
        #expect(TintSwatches.swatchSize < TintSwatches.hitTarget)
    }

    @Test("Every monogram the tint row can show fits its field", arguments: ["WA", "ЛК", "中文", "🚀", "88"])
    func monogramFits(text: String) throws {
        let monogram = try AccountMonogram(validating: text)
        // The field's own insets take about 12 pt of its width.
        #expect(width(monogram.value, body) <= AccountEditorSheet.monogramFieldWidth - 12, "\(monogram.value)")
    }

    @Test("The row caption's interval half matches the one-string caption", arguments: languages)
    func intervalCaptionParity(l10n: Localizer) {
        for seconds in [60, 120, 180, 300, 600, 900, 1_800, 3_600, 90] {
            let path = "~/.claude-work"
            let composed = path + AccountsPane.intervalCaption(seconds: seconds, l10n: l10n)
            #expect(composed == SettingsCopy.profileCaption(path: path, refreshSeconds: seconds, l10n: l10n), "\(seconds) s")
        }
    }
}

/// The new Appearance rows, measured in both languages.
@MainActor
@Suite("Appearance ring copy")
struct AppearanceRingCopyTests {
    nonisolated private static let languages = [Localizer.testEnglish, .testRussian]
    private let body = NSFont.preferredFont(forTextStyle: .body)
    private let subheadline = NSFont.preferredFont(forTextStyle: .subheadline)

    private func width(_ text: String, _ font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
    }

    @Test("Titles fit beside the switch at the narrowest window", arguments: languages)
    func titles(l10n: Localizer) {
        // Detail 550 − form insets 2×20 − row insets 2×10 − icon tile 34 − switch 60 = 396 pt.
        let room: CGFloat = 396
        for title in [l10n.appearance.forecast, l10n.appearance.resets] {
            #expect(width(title, body) <= room, "\(title): \(width(title, body)) pt")
        }
    }

    @Test("Subtitles wrap inside two lines at the narrowest window", arguments: languages)
    func subtitles(l10n: Localizer) {
        // Two lines of 396 pt, less a fifth for word wrapping.
        let budget: CGFloat = 396 * 2 * 0.8
        for subtitle in [l10n.appearance.forecastSubtitle, l10n.appearance.resetsSubtitle] {
            #expect(width(subtitle, subheadline) <= budget, "\(subtitle): \(width(subtitle, subheadline)) pt")
        }
    }

    @Test("The Look section's footer wraps inside two lines", arguments: languages)
    func lookFooter(l10n: Localizer) {
        let budget: CGFloat = 490 * 2 * 0.8
        for note in [l10n.accountStyle.colorFooter, l10n.accountStyle.monogramFooter, l10n.accountStyle.monogramInvalid] {
            #expect(width(note, subheadline) <= budget, "\(note): \(width(note, subheadline)) pt")
        }
    }
}
