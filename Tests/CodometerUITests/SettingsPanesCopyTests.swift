import CodometerCore
import CodometerL10n
@testable import CodometerUI
import AppKit
import Foundation
import Testing

/// Text of the General, Notifications, Appearance and Presentation panes in both languages: the phrases the views
/// compose, and whether text fits the room the layout gives it, measured with `NSString.size` in the real fonts.
///
/// Layout facts, read off `SettingsPanesRenderTests` images: a grouped section sits 20 pt in from each side of the detail
/// column and its rows another 10 pt; a row label's icon tile and spacing take 34 pt; the island stage adds 14 pt of padding
/// on each side; a `Label`'s icon and spacing take 36 pt at the callout size; a segmented control's segments are all as
/// wide as the widest title plus 20 pt.
@MainActor
@Suite("Settings panes copy")
struct SettingsPanesCopyTests {
    static let languages: [Localizer] = [.testEnglish, .testRussian]
    /// The detail column when the window opens (920 pt wide, 210 pt sidebar) and at its narrowest (800 pt, 250 pt).
    static let defaultDetailWidth: CGFloat = 710
    static let narrowestDetailWidth: CGFloat = 550

    static let body = NSFont.systemFont(ofSize: 13)
    static let callout = NSFont.systemFont(ofSize: 12)
    static let monospacedDigits = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    static let code = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    static func width(_ text: String, _ font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    /// Lines `text` takes when wrapped to `width`.
    static func lines(_ text: String, _ font: NSFont, width: CGFloat) -> Int {
        let height = (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        ).height
        let line = NSLayoutManager().defaultLineHeight(for: font)
        return Int((height / line).rounded(.up))
    }

    /// A row's content width inside a grouped section.
    static func rowWidth(_ detail: CGFloat) -> CGFloat { detail - 2 * 20 - 2 * 10 }

    // MARK: - Fixed widths

    @Test("Slider values fit their fixed columns in both languages")
    func sliderValues() {
        for l10n in Self.languages {
            let percent = l10n.format.percentCompact(AppearancePane.percentValueTemplate)
            #expect(Self.width(percent, Self.monospacedDigits) <= AppearancePane.percentValueWidth, "\(l10n.language): \(percent)")
            let scale = l10n.format.percentCompact(IslandScale.allowedRange.upperBound * 100)
            #expect(Self.width(scale, Self.monospacedDigits) <= PlacementPane.scaleValueWidth, "\(l10n.language): \(scale)")
        }
    }

    @Test("Each open-trigger explanation fits the two lines reserved for it at the narrowest width")
    func triggerExplanations() {
        for l10n in Self.languages {
            for trigger in IslandOpenTrigger.allCases {
                let text = PlacementPane.explanation(trigger, l10n: l10n)
                #expect(Self.lines(text, Self.callout, width: Self.rowWidth(Self.narrowestDetailWidth)) <= 2, "\(l10n.language): \(text)")
            }
        }
    }

    @Test("Each stage hint stays on one line at the narrowest width")
    func stageHints() {
        let room = Self.narrowestDetailWidth - 2 * 20 - 2 * 14 - 36
        for l10n in Self.languages {
            for trigger in IslandOpenTrigger.allCases {
                let hint = IslandStage.hint(trigger, l10n: l10n)
                #expect(Self.width(hint, Self.callout) <= room, "\(l10n.language): \(hint)")
            }
        }
    }

    @Test("The stage toolbar fits the narrowest width")
    func stageToolbar() {
        // Around the text: three swatches (13 pt + 6 pt spacing), glass button padding (14 pt a side), the buttons'
        // spacing (2 × 6 pt), the toolbar's spacing (3 × 8 pt), the spacer's minimum (12 pt) and a small switch (32 pt).
        let chrome: CGFloat = 3 * (13 + 6) + 3 * 2 * 14 + 2 * 6 + 3 * 8 + 12 + 32
        let room = Self.narrowestDetailWidth - 2 * 20 - 2 * 14 - chrome
        for l10n in Self.languages {
            let titles = StageBackdrop.allCases.map { $0.title(l10n) } + [l10n.stage.showExpanded]
            let text = titles.map { Self.width($0, Self.body) }.reduce(0, +)
            #expect(text <= room, "\(l10n.language): \(titles) take \(text) pt of \(room)")
        }
    }

    @Test("The shortcut-off hint stays on one line at the narrowest width, so turning the shortcut off keeps the row height")
    func shortcutOffHint() {
        let room = Self.rowWidth(Self.narrowestDetailWidth) - 36
        for l10n in Self.languages {
            #expect(Self.width(l10n.general.shortcutOffHint, Self.callout) <= room, "\(l10n.language)")
        }
    }

    @Test("Info rows keep label and detail on one line at the narrowest width")
    func infoRows() {
        // Label icon and spacing (34 pt) and the gap LabeledContent keeps between label and content (at most 40 pt).
        let room = Self.rowWidth(Self.narrowestDetailWidth) - 34 - 40
        for l10n in Self.languages {
            let general = l10n.general
            let rows = [
                ("Claude", general.claudeSource), ("Codex", general.codexSource),
                (general.signatureCheck, general.signatureCheckDetail),
                (general.tokens, general.tokensDetail), (general.network, general.networkDetail),
                (general.conversations, general.conversationsDetail),
            ]
            for (label, detail) in rows {
                let total = Self.width(label, Self.body) + Self.markdownWidth(detail)
                #expect(total <= room, "\(l10n.language): \(label) · \(detail) takes \(total) pt of \(room)")
            }
        }
    }

    @Test("Segmented pickers stay beside their labels at the default width")
    func segmentedPickers() {
        let room = Self.rowWidth(Self.defaultDetailWidth)
        for l10n in Self.languages {
            let rows: [(String, [String])] = [
                (l10n.general.shortcut, SettingsCopy.shortcutChoices.map { ShortcutKeys.title($0, l10n: l10n) }),
                (l10n.placement.expandOn, IslandOpenTrigger.allCases.map { PlacementPane.title($0, l10n: l10n) }),
                (l10n.placement.style, [l10n.placement.attached, l10n.placement.floating]),
                (l10n.placement.surface, [l10n.placement.liquidGlass, l10n.placement.darkGlass, l10n.placement.black]),
                (l10n.appearance.resetTime, [
                    l10n.appearance.countdownSample(l10n.format.durationCompact(AppearancePane.sampleCountdown)),
                    l10n.appearance.clockSample(AppearancePane.sampleResetDate(in: l10n.calendar)),
                ]),
                (l10n.appearance.emailAddress, [l10n.appearance.emailShow, l10n.appearance.emailMask, l10n.appearance.emailHide]),
                (l10n.alerts.peek, [l10n.alerts.off] + [3, 5, 10].map { l10n.format.durationPrecise(TimeInterval($0)) }),
            ]
            for (label, segments) in rows {
                let widest = segments.map { Self.width($0, Self.body) }.max() ?? 0
                let total = 34 + Self.width(label, Self.body) + 16 + CGFloat(segments.count) * (widest + 20)
                #expect(total <= room, "\(l10n.language): \(label) \(segments) takes \(total) pt of \(room)")
            }
        }
    }

    /// Width of inline Markdown with code spans in the monospaced font.
    static func markdownWidth(_ text: String) -> CGFloat {
        text.split(separator: "`", omittingEmptySubsequences: false).enumerated().reduce(0) { total, part in
            total + width(String(part.element), part.offset.isMultiple(of: 2) ? body : code)
        }
    }

    // MARK: - Phrases

    @Test("Pane titles in both languages")
    func paneTitles() {
        #expect(SettingsPane.allCases.map { $0.title(.testEnglish) } == ["Accounts", "Presentation", "Appearance", "Notifications", "General", "Diagnostics"])
        #expect(SettingsPane.allCases.map { $0.title(.testRussian) } == ["Аккаунты", "Отображение", "Внешний вид", "Уведомления", "Общие", "Диагностика"])
    }

    @Test("Shortcut titles, key names and warnings")
    func shortcuts() {
        #expect(SettingsCopy.shortcutChoices.map { ShortcutKeys.title($0, l10n: .testEnglish) } == ["⌃⌥⌘U", "⌃⌥Space", "⌃⌥⌘L", "Off"])
        #expect(SettingsCopy.shortcutChoices.map { ShortcutKeys.title($0, l10n: .testRussian) } == ["⌃⌥⌘U", "⌃⌥Пробел", "⌃⌥⌘L", "Выкл."])
        #expect(ShortcutKeys.keys(.off, l10n: .testEnglish).isEmpty)
        #expect(ShortcutKeys.spoken(.controlOptionCommandU, l10n: .testEnglish) == "Control-Option-Command-U")
        #expect(Localizer.testEnglish.general.shortcutA11y(keys: ShortcutKeys.spoken(.controlOptionSpace, l10n: .testEnglish))
            == "Control-Option-Space, from any app")
        #expect(Localizer.testRussian.general.shortcutA11y(keys: ShortcutKeys.spoken(.controlOptionSpace, l10n: .testRussian))
            == "Control-Option-Пробел, из любого приложения")
        #expect(ShortcutKeys.warning(.controlOptionSpace, l10n: .testEnglish)?.hasPrefix("macOS often uses this shortcut") == true)
        #expect(ShortcutKeys.warning(.controlOptionCommandU, l10n: .testEnglish) == nil)
        #expect(ShortcutKeys.warning(.off, l10n: .testRussian) == nil)
    }

    @Test("Reset-time examples come from the formatters in the user's clock")
    func resetTimeSamples() {
        let en = Localizer.testEnglish, ru = Localizer.testRussian
        #expect(en.appearance.countdownSample(en.format.durationCompact(AppearancePane.sampleCountdown)) == "In 2h 14m")
        #expect(ru.appearance.countdownSample(ru.format.durationCompact(AppearancePane.sampleCountdown)) == "Через 2\u{00A0}ч 14\u{00A0}мин")
        #expect(en.appearance.clockSample(AppearancePane.sampleResetDate(in: en.calendar)) == "Fri 12:10\u{202F}PM")
        #expect(ru.appearance.clockSample(AppearancePane.sampleResetDate(in: ru.calendar)) == "Пт, 12:10")
        #expect(en.stage.menuBarClock(StageMenuBar.clockDate(in: en.calendar)) == "Thu 12:10\u{202F}PM")
        #expect(ru.stage.menuBarClock(StageMenuBar.clockDate(in: ru.calendar)) == "Чт 12:10")
    }

    @Test("Durations read as words for VoiceOver, and zero is Off")
    func spokenSeconds() {
        #expect(Localizer.testEnglish.alerts.secondsA11y(3) == "3 seconds")
        #expect(Localizer.testEnglish.alerts.secondsA11y(60) == "1 minute")
        #expect(Localizer.testEnglish.alerts.secondsA11y(90) == "1 minute 30 seconds")
        #expect(Localizer.testEnglish.alerts.secondsA11y(0) == "Off")
        #expect(Localizer.testRussian.alerts.secondsA11y(3) == "3 секунды")
        #expect(Localizer.testRussian.alerts.secondsA11y(20) == "20 секунд")
        #expect(Localizer.testRussian.alerts.secondsA11y(600) == "10 минут")
        #expect(Localizer.testRussian.alerts.secondsA11y(0) == "Выкл.")
    }

    @Test("Composed notices name the right panes and values")
    func composedNotices() {
        let en = Localizer.testEnglish, ru = Localizer.testRussian
        let enFooter = en.general.widgetFooter(appearancePane: en.settingsPanes.appearance, privacySection: en.appearance.privacyTitle, noData: en.common.noData)
        #expect(enFooter.contains("Email addresses follow your Appearance → Privacy setting."))
        #expect(enFooter.hasSuffix("the widget shows “No data.”"))
        let ruFooter = ru.general.widgetFooter(appearancePane: ru.settingsPanes.appearance, privacySection: ru.appearance.privacyTitle, noData: ru.common.noData)
        #expect(ruFooter.contains("по настройке «Внешний вид → Приватность»"))
        #expect(ruFooter.hasSuffix("виджет покажет «Нет данных»."))
        #expect(en.alerts.quietFooter(accountsPane: en.settingsPanes.accounts).hasSuffix("in Accounts."))
        #expect(ru.alerts.quietFooter(accountsPane: ru.settingsPanes.accounts).hasSuffix("в разделе «Аккаунты»."))
        #expect(en.alerts.skipShortTurnsSubtitle(finished: en.alerts.agentFinished) == "No “Agent finished” notification for turns shorter than this")
        #expect(en.alerts.thresholdA11y(en.format.percent(80)) == "Notify at 80%")
        #expect(ru.alerts.thresholdA11y(ru.format.percent(80)) == "Предупреждать при 80\u{00A0}%")
        #expect(en.appearance.bandsA11y(watch: en.format.percent(60), critical: en.format.percent(85)) == "Green up to 60%, yellow up to 85%, red above that")
        #expect(ru.appearance.bandRange(from: ru.format.decimal(60, fractionDigits: 0), to: ru.format.percentCompact(85)) == "60–85%")
        #expect(en.appearance.bandAbove(en.format.percentCompact(85)) == "85%+")
    }

    @Test("Commands keep their code style and are never translated")
    func inlineCommands() {
        for l10n in Self.languages {
            let claude = GeneralPane.inlineMarkdown(l10n.general.claudeSource)
            #expect(String(claude.characters).contains("claude /usage"))
            #expect(!String(claude.characters).contains("`"))
            #expect(claude.runs.contains { $0.inlinePresentationIntent?.contains(.code) == true })
            #expect(String(GeneralPane.inlineMarkdown(l10n.general.codexSource).characters).hasPrefix("codex app-server"))
        }
    }

    @Test("Every choice has its own title, tooltip and VoiceOver name in each language")
    func choiceTitles() {
        for l10n in Self.languages {
            let triggers = IslandOpenTrigger.allCases
            #expect(Set(triggers.map { PlacementPane.title($0, l10n: l10n) }).count == triggers.count)
            #expect(Set(triggers.map { PlacementPane.explanation($0, l10n: l10n) }).count == triggers.count)
            #expect(Set(triggers.map { IslandStage.hint($0, l10n: l10n) }).count == triggers.count)
            #expect(Set(StageBackdrop.allCases.map { $0.title(l10n) }).count == StageBackdrop.allCases.count)
            #expect(Set(StageBackdrop.allCases.map { $0.help(l10n) }).count == StageBackdrop.allCases.count)
            #expect(Set(ScreenEdge.allCases.map { $0.title(l10n) }).count == ScreenEdge.allCases.count)
            #expect(Set(ScreenEdge.allCases.map { $0.moveA11y(l10n) }).count == ScreenEdge.allCases.count)
        }
        #expect(ScreenEdge.allCases.map { $0.title(.testEnglish) } == ["Top", "Bottom", "Left", "Right"])
        #expect(ScreenEdge.top.moveA11y(.testRussian) == "Переместить к верхнему краю")
        #expect(StageBackdrop.colorful.help(.testEnglish) == "Preview on a colorful background")
    }
}
