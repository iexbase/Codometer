import CodometerCore
import CodometerL10n
@testable import CodometerUI
import AppKit
import Foundation
import Testing

/// Every value the card can print has to fit the slot it is drawn in, in both languages and at every scale, and every
/// hidden template has to be at least as wide as the values it reserves room for.
///
/// Widths are measured with `NSString.size` in exactly the font the views use (`CardMetrics.nsFont`), so a phrase that
/// passes here cannot truncate on screen.
@Suite("Card copy fits")
struct CardCopyFitTests {
    static let scales: [CGFloat] = [0.75, 1, 1.5]
    static let languages: [Localizer] = [.testEnglish, .testRussian]
    static let now = UIFixture.now

    private func each(_ body: (CardMetrics, Localizer) throws -> Void) rethrows {
        for scale in Self.scales {
            for l10n in Self.languages {
                try body(CardMetrics(scale: scale), l10n)
            }
        }
    }

    // MARK: - Templates

    @Test("The percentage template is at least as wide as every percentage")
    func percentTemplate() {
        each { metrics, l10n in
            let template = metrics.width(of: l10n.card.percentTemplate, role: .pill)
            for value in [0.0, 0.4, 7, 42, 99, 100] {
                let text = l10n.format.percentCompact(value)
                #expect(metrics.width(of: text, role: .pill) <= template, "\(l10n.language) \(text)")
            }
        }
    }

    @Test("The countdown template is at least as wide as every countdown")
    func countdownTemplate() {
        let durations: [TimeInterval] = [
            30, 60, 59 * 60, 3_600, 2 * 3_600 + 14 * 60, 23 * 3_600 + 59 * 60,
            86_400, 5 * 86_400 + 16 * 3_600, 99 * 86_400 + 23 * 3_600,
        ]
        each { metrics, l10n in
            let template = metrics.width(of: l10n.card.countdownTemplate, role: .pill)
            for seconds in durations {
                let text = l10n.format.durationCompact(seconds)
                #expect(metrics.width(of: text, role: .pill) <= template, "\(l10n.language) \(text)")
            }
        }
    }

    @Test("The “+N” template covers every account count the pill can show")
    func moreTemplate() {
        each { metrics, l10n in
            let template = metrics.width(of: l10n.card.moreTemplate, role: .pill)
            for count in 1...8 {
                #expect(metrics.width(of: "+\(count)", role: .pill) <= template, "+\(count)")
            }
        }
    }

    @Test("The status pill's slot is at least as wide as every reason it can show")
    func statusPillTemplate() {
        each { metrics, l10n in
            let template = metrics.width(of: l10n.card.pillTemplate, role: .pill)
            let phrases = [
                l10n.card.waiting(1), l10n.card.waiting(2), l10n.card.waiting(5), l10n.card.waiting(21),
                l10n.card.limitReached, l10n.card.justReset, l10n.card.stale,
                l10n.card.degraded, l10n.card.partialOutage, l10n.card.majorOutage, l10n.card.maintenance,
            ]
            for phrase in phrases {
                #expect(metrics.width(of: phrase, role: .pill) <= template, "\(l10n.language) \(phrase)")
            }
        }
    }

    // MARK: - Slots

    @Test("Every tile value fits its tile, in both languages and at every scale")
    func tileValuesFit() {
        let clock = Self.now.addingTimeInterval(11 * 3_600 + 5 * 60)
        // Only the Regular card has tiles; the Compact one shows the ring and a caption.
        each { metrics, l10n in
            for size in [CardSize.regular] {
                let available = metrics.tileContentWidth(size)
                var values = [
                    l10n.card.onTrack, l10n.card.tooEarly, l10n.card.out, l10n.card.noValue,
                    l10n.format.percentCompact(100), "88 · 88",
                    CardContentPlan.weeklyValue(clock, now: Self.now, l10n: l10n),
                    CardContentPlan.weeklyValue(clock.addingTimeInterval(3 * 86_400), now: Self.now, l10n: l10n),
                ]
                // Every countdown a reset tile can print, from the longest to the shortest.
                for seconds in [99 * 86_400 + 23 * 3_600, 23 * 3_600 + 59 * 60, 5 * 86_400 + 16 * 3_600, 59 * 60, 30] {
                    values.append(l10n.format.durationCompact(TimeInterval(seconds)))
                }
                for value in values {
                    let width = metrics.width(of: value, role: .tileValue)
                    #expect(width <= available, "\(l10n.language) scale \(metrics.scale) \(size) “\(value)” \(width) > \(available)")
                }
            }
        }
    }

    @Test("Every tile label fits its tile beside the icon")
    func tileLabelsFit() {
        each { metrics, l10n in
            for size in [CardSize.regular] {
                // The label shares its line with a glyph of about one line height, plus 4 pt of spacing.
                let available = metrics.tileContentWidth(size) - metrics.textSize(TextSize.badge) - 4
                let labels = [
                    l10n.card.untilReset, l10n.card.backAt, l10n.card.atThisPace, l10n.card.runsOut,
                    l10n.card.weeklyReset, l10n.card.sessionWindow, l10n.card.agentsLabel, l10n.card.noAgents,
                    // A provider without a session scope shows that window's own title, which is provider data:
                    // short titles fit, and a long one truncates like an account name does.
                    l10n.window.session(length: l10n.format.durationCompact(5 * 3_600)),
                ]
                for label in labels {
                    let width = metrics.width(of: label, role: .tileLabel) * 0.65
                    #expect(width <= available, "\(l10n.language) scale \(metrics.scale) \(size) “\(label)”")
                }
            }
        }
    }

    @Test("The hero figure and its unit fit the hero column")
    func heroFits() {
        each { metrics, l10n in
            // The hero column is the card minus its padding, the ring and the gap between them.
            let ring = metrics.heroRing(.regular)
            let available = metrics.cardSize(.regular).width
                - metrics.padding * 2
                - ring
                - max(2, ring / 7) * 2
                - metrics.tileSpacing * 2
            #expect(metrics.width(of: l10n.format.percentCompact(100), role: .hero) <= available, "\(l10n.language) figure")
            #expect(metrics.width(of: l10n.card.used, role: .heroUnit) <= available, "\(l10n.language) unit")
            #expect(metrics.width(of: l10n.card.left, role: .heroUnit) <= available, "\(l10n.language) unit")
        }
    }

    @Test("The header leaves room for an account name beside the status pill")
    func headerFits() {
        each { metrics, l10n in
            for size in CardSize.allCases {
                // Only the compact card shrinks the pill to a dot; the regular card and the strip spell it out.
                let slot = size == .compact ? metrics.pageDot * 1.6 : metrics.statusSlotWidth(template: l10n.card.pillTemplate)
                let remaining = metrics.headerWidth(size) - slot - metrics.badge - 10
                // A ten-character account name is what the fixtures and the docs use; longer ones truncate on purpose.
                let sample = l10n.language == .ru ? "Работа" : "Work"
                #expect(metrics.width(of: sample, role: .header) <= remaining, "\(l10n.language) \(size)")
                #expect(remaining > 0, "\(l10n.language) \(size) leaves no room for a name")
            }
        }
    }

    @Test("The compact card's caption fits its width")
    func compactCaptionFits() throws {
        try each { metrics, l10n in
            let available = metrics.cardSize(.compact).width - metrics.padding * 2
            let presentation = try CardContentPlanTests.presentation(
                windows: [
                    try UIFixture.window("session", .session, used: 42, duration: .fiveHours, resetsIn: 7_200),
                    try UIFixture.window("week", .weekly(model: nil), used: 64, duration: .oneWeek, resetsIn: 5 * 86_400 + 16 * 3_600),
                ],
                l10n: l10n
            )
            let plan = CardContentPlanTests.plan(presentation, l10n: l10n)
            let caption = [plan.hero?.caption, plan.tiles.first { $0.kind == .reset }?.value]
                .compactMap { $0 }
                .joined(separator: " · ")
            // The caption may shrink to 75 % before it would truncate.
            #expect(metrics.width(of: caption, role: .footer) * 0.75 <= available, "\(l10n.language) “\(caption)”")
        }
    }

    // MARK: - Strip

    @Test("The strip's hero column holds the widest figure, its unit and the used line, in both languages")
    func stripHeroFits() {
        each { metrics, l10n in
            let column = metrics.stripHeroWidth
            let figure = metrics.width(of: l10n.card.percentTemplate, role: .hero) + 5 + metrics.width(of: l10n.card.left, role: .heroUnit)
            #expect(figure <= column, "\(l10n.language) scale \(metrics.scale) figure \(figure) > \(column)")
            let line = metrics.width(of: l10n.card.stripUsedLineTemplate, role: .footer)
            #expect(line <= column, "\(l10n.language) scale \(metrics.scale) used line \(line) > \(column)")
            // The caption may be longer than the column (a model week on a named account); it truncates on purpose.
            #expect(metrics.width(of: l10n.window.weekly, role: .footer) <= column)
        }
    }

    @Test("The used-line template is at least as wide as every line the hero can print")
    func stripUsedLineTemplate() {
        let durations: [TimeInterval] = [30, 59 * 60, 3_600, 2 * 3_600 + 14 * 60, 23 * 3_600 + 59 * 60, 86_400, 5 * 86_400 + 16 * 3_600, 99 * 86_400 + 23 * 3_600]
        each { metrics, l10n in
            let template = metrics.width(of: l10n.card.stripUsedLineTemplate, role: .footer)
            for used in [0.0, 0.4, 7, 42, 99, 100] {
                let percent = l10n.format.percentCompact(used)
                for seconds in durations {
                    let line = l10n.card.stripUsedLine(used: percent, reset: l10n.format.durationCompact(seconds))
                    #expect(metrics.width(of: line, role: .footer) <= template, "\(l10n.language) “\(line)”")
                }
                #expect(metrics.width(of: l10n.card.stripUsed(percent), role: .footer) <= template)
            }
        }
    }

    @Test("A chip holds its title, its percentage beside the accounts badge, and every countdown")
    func stripChipsFit() {
        let durations: [TimeInterval] = [30, 59 * 60, 2 * 3_600 + 14 * 60, 23 * 3_600 + 59 * 60, 5 * 86_400 + 16 * 3_600, 99 * 86_400 + 23 * 3_600]
        each { metrics, l10n in
            let content = metrics.chipContentWidth
            #expect(content > 0)
            // The countdown template covers every countdown, and fits the chip at full size.
            let template = metrics.width(of: l10n.card.stripResetTemplate, role: .tileLabel)
            #expect(template <= content, "\(l10n.language) scale \(metrics.scale) countdown \(template) > \(content)")
            for seconds in durations {
                let text = l10n.card.stripReset(l10n.format.durationCompact(seconds))
                #expect(metrics.width(of: text, role: .tileLabel) <= template, "\(l10n.language) “\(text)”")
            }
            // The percentage shares its line with the badge ("⊞ 8": a glyph of about one line height plus the count).
            let badge = metrics.textSize(TextSize.badge) + 2 + metrics.width(of: "8", role: .plan)
            #expect(metrics.width(of: l10n.card.percentTemplate, role: .tileValue) + 4 + badge <= content, "\(l10n.language) scale \(metrics.scale)")
            // The titles Claude and Codex actually produce fit at full size; the widest the card can write shrinks
            // by at most the 20 % the chip allows. A provider's own label truncates like an account name does.
            let plain = [
                l10n.window.weekly, l10n.window.weekly(model: "Opus"),
                l10n.window.session(length: l10n.format.durationCompact(5 * 3_600)), l10n.window.extraLimit,
            ]
            for title in plain {
                let width = metrics.width(of: title, role: .tileLabel)
                #expect(width <= content, "\(l10n.language) scale \(metrics.scale) “\(title)” \(width) > \(content)")
            }
            for title in [l10n.card.stripTitleTemplate, l10n.window.weekly(model: "Haiku"), l10n.window.mainLimit] {
                let width = metrics.width(of: title, role: .tileLabel)
                #expect(width * 0.8 <= content, "\(l10n.language) scale \(metrics.scale) “\(title)” \(width) > \(content)")
            }
            // The "+N" chip.
            #expect(metrics.width(of: l10n.card.stripMore(88), role: .tileValue) <= content)
        }
    }

    @Test("The strip's rows and chips add up to its fixed frame at every scale")
    func stripGeometryAddsUp() {
        for scale in Self.scales {
            let metrics = CardMetrics(scale: scale)
            let inner = metrics.innerWidth(.strip)
            let chips = CGFloat(CardMetrics.stripChipCapacity) * metrics.chipWidth + CGFloat(CardMetrics.stripChipCapacity - 1) * metrics.chipSpacing
            #expect(metrics.stripHeroWidth + metrics.stripGap + chips <= inner, "scale \(scale)")
            #expect(inner - (metrics.stripHeroWidth + metrics.stripGap + chips) < CGFloat(CardMetrics.stripChipCapacity), "scale \(scale) wastes width")
            #expect(metrics.chipHeight <= metrics.stripBodyHeight, "scale \(scale) chips taller than the body")
            // The hero's three lines: two captions and the hero numeral, each about 1.2 line heights.
            let hero = (metrics.textSize(TextSize.caption) * 2 + metrics.textSize(TextSize.hero)) * 1.22
            #expect(hero <= metrics.stripBodyHeight, "scale \(scale) hero \(hero) > body \(metrics.stripBodyHeight)")
            #expect(metrics.cardSize(.strip) == metrics.cardSize(.strip), "stable")
        }
    }

    @Test("The minimized pill is the same width whatever the numbers say, and wide enough for its content")
    func pillWidthIsStable() {
        for scale in Self.scales {
            let metrics = CardMetrics(scale: scale)
            for l10n in Self.languages {
                let templates = CardPillTemplates(l10n)
                let single = metrics.pillSize(accounts: 1, templates: templates)
                #expect(single == metrics.pillSize(accounts: 0, templates: templates))
                let content = metrics.pillPadding * 2 + metrics.pillRing
                    + metrics.width(of: templates.percent, role: .pill)
                    + metrics.width(of: templates.countdown, role: .pill)
                #expect(single.width >= content)
                #expect(single.height == metrics.pillHeight)
                // More accounts never make the pill narrower than one.
                #expect(metrics.pillSize(accounts: 5, templates: templates).width > 0)
            }
        }
    }

    @Test("English and Russian give exactly the same card and pill geometry")
    func languagesNeverChangeTheFrame() {
        let en = CardPillTemplates(Localizer.testEnglish)
        let ru = CardPillTemplates(Localizer.testRussian)
        for scale in Self.scales {
            let metrics = CardMetrics(scale: scale)
            for size in CardSize.allCases {
                #expect(metrics.cardSize(size).width > 0)
            }
            // What the card actually reserves: every language at once, so a language step never resizes either form.
            let shared = CardPillTemplates.everyLanguage
            for count in [1, 2, 3, 5] {
                let reserved = metrics.pillSize(accounts: count, templates: shared)
                #expect(reserved == metrics.pillSize(accounts: count, templates: shared.reversed()), "order")
                #expect(reserved.width >= metrics.pillSize(accounts: count, templates: en).width, "en fits")
                #expect(reserved.width >= metrics.pillSize(accounts: count, templates: ru).width, "ru fits")
            }
            #expect(metrics.pillSize(accounts: 1, templates: en).height == metrics.pillSize(accounts: 1, templates: ru).height)
        }
    }

    @Test("Both languages are among the pill's reserved templates")
    func everyLanguageIsReserved() {
        let reserved = Set(CardPillTemplates.everyLanguage)
        #expect(reserved.contains(CardPillTemplates(Localizer(language: .en))))
        #expect(reserved.contains(CardPillTemplates(Localizer(language: .ru))))
        #expect(reserved.count == Language.allCases.count)
    }

    @Test("Every phrase in the Card area is filled in in both languages")
    func everyPhraseIsPresent() {
        for l10n in Self.languages {
            let card = l10n.card
            let phrases: [String] = [
                card.used, card.left, card.untilReset, card.backAt, card.atThisPace, card.onTrack, card.runsOut,
                card.tooEarly, card.out, card.weeklyReset, card.sessionWindow, card.agentsLabel, card.noAgents,
                card.noValue, card.limitReached, card.justReset, card.stale, card.degraded, card.partialOutage,
                card.majorOutage, card.maintenance, card.updating, card.minimize, card.expand, card.accountMenu,
                card.accountAuto, card.accountStay, card.sizeMenu, card.themeMenu, card.keepAbove,
                card.snapWhileDragging, card.moveTo, card.switchToIsland, card.topLeft, card.topRight,
                card.bottomLeft, card.bottomRight, card.center, card.themeGraphite, card.themeLiquidGlass,
                card.themeMidnight, card.themeLight, card.sizeCompact, card.sizeRegular, card.sizeStrip, card.thirdTileWeekly,
                card.thirdTileSession, card.thirdTileAgents, card.coachMark, card.sectionTitle, card.themeRow,
                card.sizeRow, card.accountRow, card.thirdTileRow, card.keepAboveRow, card.keepAboveCaption,
                card.scopeMenu, card.scopeRow, card.scopeCaption, card.scopeSelected, card.scopeClaude, card.scopeCodex,
                card.scopeAll, card.allAccountsTitle, card.stripUsedLineTemplate, card.stripResetTemplate,
                card.stripTitleTemplate, card.stripUsedLine(used: "64%", reset: "5d 16h"), card.stripUsed("64%"),
                card.stripReset("5d 16h"), card.stripMore(3), card.leftA11y("64 %"), card.accountsSharingA11y(2),
                card.moreWindowsA11y(3),
                card.snapCaption, card.snapRow, card.positionRow, card.showOn, card.displayWhereLeft, card.displayMain, card.resetPosition,
                card.resetPositionCaption, card.stageHint, card.cardA11y, card.nextAccount, card.previousAccount,
                card.openStatusPage, card.switchAccountHint, card.pages, card.percentTemplate,
                card.countdownTemplate, card.pillTemplate, card.moreTemplate,
                card.waiting(1), card.waiting(3), card.staleSince("13:10"), card.updated("14:32"),
                card.moveToDisplay("LG UltraFine"), card.pillA11y("Work"), card.usedA11y("64 %"),
                card.forecastA11y("92 %"), card.resetsInA11y("2 hours"), card.backInA11y("2 hours"),
                card.accountPosition(1, of: 3), card.runsOutA11y("at 6:40 PM"),
            ]
            for phrase in phrases {
                #expect(!phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(l10n.language)")
            }
        }
    }
}
