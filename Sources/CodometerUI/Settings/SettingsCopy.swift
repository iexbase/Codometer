import CodometerCore
import CodometerL10n
import Foundation

/// Settings-window text worth testing on its own: validation messages, option titles, hints and counts.
///
/// Every function takes the `Localizer` of the view that shows the text. Functions other panes call keep a default
/// (English, like `\.l10n`'s default) so those panes compile while they are converted; pass the environment's `l10n`.
enum SettingsCopy {
    /// What a caller that has not passed its own `Localizer` yet gets.
    static let defaultLocalizer = Localizer(language: .en)

    // MARK: - Validation

    /// Why a settings change was rejected, in a full sentence.
    static func settingsMessage(for error: ValidationError, l10n: Localizer) -> String {
        let text = l10n.validation
        switch error {
        case .notFinite:
            return text.notANumber
        case let .outOfRange(_, _, lowerBound, upperBound):
            return text.outOfRange(lower: lowerBound, upper: upperBound)
        case .empty:
            return text.empty
        case let .tooLong(field, _, maximum):
            switch field {
            case "groups": return text.tooManyGroups(maximum)
            case "accounts": return text.tooManyAccounts(maximum)
            case "alerts.thresholds": return text.tooManyThresholds(maximum)
            default: return text.tooLong(maximum)
            }
        case .invalidCharacters:
            return text.invalidCharacters
        case .notAbsolutePath:
            return text.notAbsolutePath
        case let .duplicate(field, value):
            switch field {
            case "groups.name": return text.duplicateGroup(value)
            case "accounts.directory": return text.duplicateProfile
            default: return text.duplicateValue
            }
        case let .inconsistent(field, _):
            switch field {
            case "appearance.bands": return text.bandsOrder
            case "accounts.groupID", "groups.id": return text.groupGone
            case "accounts.id": return text.accountGone
            default: return text.conflictingSettings
            }
        }
    }

    /// `settingsMessage(for:l10n:)` in English, for panes that still pass `SettingsCopy.settingsMessage(for:)`.
    static func settingsMessage(for error: ValidationError) -> String {
        settingsMessage(for: error, l10n: defaultLocalizer)
    }

    /// Messages for a group name typed by the user.
    static func groupMessage(for error: ValidationError, l10n: Localizer) -> String {
        switch error {
        case .empty: l10n.validation.groupNameEmpty
        case let .tooLong(field, _, maximum) where field.hasSuffix("label"): l10n.validation.groupNameTooLong(maximum)
        case .invalidCharacters: l10n.validation.nameInvalidCharacters
        default: settingsMessage(for: error, l10n: l10n)
        }
    }

    /// Messages for the account editor's fields.
    static func accountMessage(for error: ValidationError, l10n: Localizer) -> String {
        switch error {
        case .empty(let field) where field.hasSuffix("label"): l10n.validation.accountNameEmpty
        case .tooLong(let field, _, let maximum) where field.hasSuffix("label"): l10n.validation.accountNameTooLong(maximum)
        case .invalidCharacters(let field) where field.hasSuffix("label"): l10n.validation.nameInvalidCharacters
        case .notAbsolutePath, .empty: l10n.validation.notAbsolutePath
        case .outOfRange(let field, _, _, _) where field.hasSuffix("pollInterval"): l10n.validation.refreshTooFrequent
        default: settingsMessage(for: error, l10n: l10n)
        }
    }

    // MARK: - Open trigger

    static func title(_ trigger: IslandOpenTrigger, l10n: Localizer = SettingsCopy.defaultLocalizer) -> String {
        switch trigger {
        case .hover: l10n.validation.openOnHover
        case .click: l10n.validation.openOnClick
        case .hoverOrClick: l10n.validation.openOnHoverOrClick
        }
    }

    /// At most two lines under the trigger picker.
    static func explanation(_ trigger: IslandOpenTrigger, l10n: Localizer = SettingsCopy.defaultLocalizer) -> String {
        switch trigger {
        case .hover: l10n.validation.hoverExplanation
        case .click: l10n.validation.clickExplanation
        case .hoverOrClick: l10n.validation.hoverOrClickExplanation
        }
    }

    /// The hint under the live preview; short enough for one line at the settings window's minimum width.
    static func stageHint(_ trigger: IslandOpenTrigger, l10n: Localizer = SettingsCopy.defaultLocalizer) -> String {
        switch trigger {
        case .hover: l10n.validation.hoverStageHint
        case .click: l10n.validation.clickStageHint
        case .hoverOrClick: l10n.validation.hoverOrClickStageHint
        }
    }

    // MARK: - E-mail

    static let sampleEmail = "alex.morgan@example.com"

    static func title(_ visibility: EmailVisibility, l10n: Localizer = SettingsCopy.defaultLocalizer) -> String {
        switch visibility {
        case .visible: l10n.validation.showEmail
        case .masked: l10n.validation.maskEmail
        case .hidden: l10n.validation.hideEmail
        }
    }

    /// How `address` reads with the setting: as is, masked, or a note that it is not shown.
    static func emailExample(_ address: String, visibility: EmailVisibility, l10n: Localizer = SettingsCopy.defaultLocalizer) -> String {
        UsageFormat.email(address, visibility: visibility) ?? l10n.validation.emailHidden
    }

    // MARK: - Global shortcut

    /// Shortcuts in the order the picker offers them: combinations first, "Off" last.
    static let shortcutChoices: [GlobalShortcut] = [.controlOptionCommandU, .controlOptionSpace, .controlOptionCommandL, .off]

    /// The key caps of a shortcut; empty when it is off.
    static func keys(_ shortcut: GlobalShortcut, l10n: Localizer = SettingsCopy.defaultLocalizer) -> [String] {
        switch shortcut {
        case .off: []
        case .controlOptionCommandU: ["⌃", "⌥", "⌘", "U"]
        case .controlOptionSpace: ["⌃", "⌥", l10n.validation.spaceKey]
        case .controlOptionCommandL: ["⌃", "⌥", "⌘", "L"]
        }
    }

    static func title(_ shortcut: GlobalShortcut, l10n: Localizer = SettingsCopy.defaultLocalizer) -> String {
        shortcut == .off ? l10n.validation.shortcutOff : keys(shortcut, l10n: l10n).joined()
    }

    /// A warning for shortcuts macOS often uses itself.
    static func note(_ shortcut: GlobalShortcut, l10n: Localizer = SettingsCopy.defaultLocalizer) -> String? {
        switch shortcut {
        case .controlOptionSpace: l10n.validation.inputSourceShortcutNote
        case .off, .controlOptionCommandU, .controlOptionCommandL: nil
        }
    }

    // MARK: - Widget

    /// Under the widget toggle. The exporter writes at most once a minute unless the change matters, and deletes
    /// the file when the export is turned off.
    static func widgetNote(l10n: Localizer) -> String {
        l10n.validation.widgetNote
    }

    /// `widgetNote(l10n:)` in English, for panes that still read `SettingsCopy.widgetNote`.
    static var widgetNote: String { widgetNote(l10n: defaultLocalizer) }

    // MARK: - Short turns

    /// The offered "skip short turns" lengths, in seconds; 0 notifies about every turn.
    static let turnThresholdChoices = [0, 20, 60, 180, 600]

    /// The offered lengths plus the stored one when it is not among them, sorted.
    static func turnThresholdOptions(current: TurnAlertThreshold) -> [Int] {
        guard !turnThresholdChoices.contains(current.seconds) else { return turnThresholdChoices }
        return (turnThresholdChoices + [current.seconds]).sorted()
    }

    /// "Off", "20s", "1m", "1m 30s" | «Выкл.», «20 с», «1 мин», «1 мин 30 с».
    static func turnThresholdTitle(seconds: Int, l10n: Localizer = SettingsCopy.defaultLocalizer) -> String {
        guard seconds > 0 else { return l10n.validation.shortTurnsOff }
        return l10n.format.durationPrecise(TimeInterval(seconds))
    }

    // MARK: - Refresh interval

    /// A refresh interval in the editor's picker: "Every minute", "Every 5 minutes", "Every hour", "Every 1m 30s".
    static func refreshInterval(seconds: Int, l10n: Localizer) -> String {
        switch RefreshIntervalShape(seconds: seconds) {
        case .minute: l10n.accounts.everyMinute
        case .hour: l10n.accounts.everyHour
        case .minutes(let minutes): l10n.accounts.every(minutes: minutes)
        case .other: l10n.accounts.every(duration: l10n.format.durationPrecise(TimeInterval(seconds)))
        }
    }

    /// An account row's caption: its profile folder and how often it refreshes, "~/.claude · every 5 min".
    static func profileCaption(path: String, refreshSeconds seconds: Int, l10n: Localizer) -> String {
        let interval = switch RefreshIntervalShape(seconds: seconds) {
        case .minute: l10n.accounts.everyMinuteShort
        case .hour: l10n.accounts.everyHourShort
        case .minutes(let minutes): l10n.accounts.everyShort(minutes: minutes)
        case .other: l10n.accounts.everyShort(duration: l10n.format.durationPrecise(TimeInterval(seconds)))
        }
        return "\(path) · \(interval)"
    }

    /// `profileCaption` for VoiceOver, with the interval in words: "~/.claude, refresh: Every 5 minutes".
    static func profileCaptionA11y(path: String, refreshSeconds seconds: Int, l10n: Localizer) -> String {
        l10n.accounts.profileCaptionA11y(path: path, interval: refreshInterval(seconds: seconds, l10n: l10n))
    }

    /// How an interval reads: a whole minute or hour, whole minutes, or anything else.
    private enum RefreshIntervalShape {
        case minute, hour, minutes(Int), other

        init(seconds: Int) {
            self = switch seconds {
            case 60: .minute
            case 3_600: .hour
            case let value where value > 0 && value % 60 == 0: .minutes(value / 60)
            default: .other
            }
        }
    }

    // MARK: - Counts

    /// "No accounts", "1 account", "3 accounts" | «Нет аккаунтов», «1 аккаунт», «3 аккаунта».
    static func accountCount(_ count: Int, l10n: Localizer) -> String {
        l10n.groups.accountCount(count)
    }
}
