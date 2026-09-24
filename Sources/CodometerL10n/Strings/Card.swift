/// The floating card: its content, its context menu, its settings rows and what VoiceOver reads.
///
/// The card is one of the two presentation styles («плавающая карточка»); the other is the island. Words that already
/// exist elsewhere are reused (`l10n.menu.refreshAll`, `l10n.menu.settings`, `l10n.common.noData`), so the card never
/// invents a second wording for the same thing.
public struct CardStrings: Sendable {
    let l: Localizer

    // MARK: - Hero

    /// Under the big percentage: the card always prints the word, so the figure never has to be guessed.
    public var used: String { l.pick(en: "used", ru: "использовано") }
    public var left: String { l.pick(en: "left", ru: "осталось") }

    // MARK: - Strip

    /// The small line under the strip's hero: what is used and when the window resets. The arrow is the same glyph
    /// the chips carry before their countdown, so it reads as "resets in" wherever it appears.
    public func stripUsedLine(used: String, reset: String) -> String {
        l.pick(en: "\(used) used · ⟳ \(reset)", ru: "\(used) использовано · ⟳ \(reset)")
    }
    /// The same line for a window without a reset time.
    public func stripUsed(_ used: String) -> String {
        l.pick(en: "\(used) used", ru: "\(used) использовано")
    }
    /// A chip's countdown: "⟳ 1d 14h".
    public func stripReset(_ countdown: String) -> String {
        l.pick(en: "⟳ \(countdown)", ru: "⟳ \(countdown)")
    }
    /// The last chip when more windows exist than fit: "+3".
    public func stripMore(_ count: Int) -> String {
        l.pick(en: "+\(count)", ru: "+\(count)")
    }
    /// The header of a strip that merges several accounts: "All accounts".
    public var allAccountsTitle: String { l.pick(en: "All accounts", ru: "Все аккаунты") }

    // MARK: - Tiles

    public var untilReset: String { l.pick(en: "until reset", ru: "до сброса") }
    /// Under the reset tile while the limit is reached.
    public var backAt: String { l.pick(en: "back at", ru: "снова доступно") }
    public var atThisPace: String { l.pick(en: "at this pace", ru: "при таком темпе") }
    public var onTrack: String { l.pick(en: "On track", ru: "В норме") }
    /// The pace tile's label when there is a projection: the value above it is when the limit runs out.
    public var runsOut: String { l.pick(en: "runs out", ru: "закончится") }
    /// The same thing as one phrase, for VoiceOver, where there is room: "Runs out at 6:40 PM".
    public func runsOutA11y(_ time: String) -> String {
        l.pick(en: "Runs out \(time)", ru: "Закончится \(time)")
    }
    /// Too little of the window has passed to judge the pace.
    public var tooEarly: String { l.pick(en: "Too early", ru: "Рано судить") }
    public var out: String { l.pick(en: "Out", ru: "Исчерпан") }
    public var weeklyReset: String { l.pick(en: "weekly reset", ru: "недельный сброс") }
    public var sessionWindow: String { l.pick(en: "session · 5h", ru: "сессия · 5\u{00A0}ч") }
    /// Under "2 · 1": how many agents work and how many wait.
    public var agentsLabel: String { l.pick(en: "working · waiting", ru: "работают · ждут") }
    public var noAgents: String { l.pick(en: "no agents", ru: "агентов нет") }
    /// Placeholder for a tile with nothing to show.
    public var noValue: String { l.pick(en: "—", ru: "—") }

    // MARK: - Status pill

    public func waiting(_ count: Int) -> String {
        l.plural(
            count,
            en: (one: "\(count) waiting", other: "\(count) waiting"),
            ru: ("\(count) ждёт", "\(count) ждут", "\(count) ждут")
        )
    }
    public var limitReached: String { l.pick(en: "Limit reached", ru: "Лимит исчерпан") }
    public var justReset: String { l.pick(en: "Just reset", ru: "Лимит сброшен") }
    public var stale: String { l.pick(en: "Stale", ru: "Устарело") }
    /// The stale pill's tooltip: when the last fresh reading arrived.
    public func staleSince(_ time: String) -> String {
        l.pick(en: "No fresh data since \(time)", ru: "Нет свежих данных с \(time)")
    }
    public var degraded: String { l.pick(en: "Slowdown", ru: "Замедление") }
    public var partialOutage: String { l.pick(en: "Partial outage", ru: "Частичный сбой") }
    public var majorOutage: String { l.pick(en: "Major outage", ru: "Серьёзный сбой") }
    public var maintenance: String { l.pick(en: "Maintenance", ru: "Техработы") }

    // MARK: - Footer

    public func updated(_ time: String) -> String {
        l.pick(en: "updated \(time)", ru: "обновлено \(time)")
    }
    public var updating: String { l.pick(en: "updating…", ru: "обновление…") }

    // MARK: - Context menu (Title Case in English)

    public var minimize: String { l.pick(en: "Minimize", ru: "Свернуть") }
    public var expand: String { l.pick(en: "Expand", ru: "Развернуть") }
    public var accountMenu: String { l.pick(en: "Account", ru: "Аккаунт") }
    public var accountAuto: String { l.pick(en: "Closest to Its Limit", ru: "Ближе всех к лимиту") }
    public var accountStay: String { l.pick(en: "Stay on This Account", ru: "Закрепить этот аккаунт") }
    public var sizeMenu: String { l.pick(en: "Size", ru: "Размер") }
    /// The strip's scope submenu.
    public var scopeMenu: String { l.pick(en: "Show", ru: "Показывать") }
    public var themeMenu: String { l.pick(en: "Theme", ru: "Оформление") }
    public var keepAbove: String { l.pick(en: "Keep Above Other Windows", ru: "Поверх других окон") }
    public var snapWhileDragging: String { l.pick(en: "Snap While Dragging", ru: "Притягивать при перетаскивании") }
    public var moveTo: String { l.pick(en: "Move To", ru: "Переместить") }
    public var switchToIsland: String { l.pick(en: "Switch to Island", ru: "Показывать как остров") }
    /// "Move to “LG UltraFine”" — the display's own name, never translated.
    public func moveToDisplay(_ name: String) -> String {
        l.pick(en: "Move to “\(name)”", ru: "Переместить на «\(name)»")
    }

    // MARK: - Places

    public var topLeft: String { l.pick(en: "Top Left", ru: "Вверху слева") }
    public var topRight: String { l.pick(en: "Top Right", ru: "Вверху справа") }
    public var bottomLeft: String { l.pick(en: "Bottom Left", ru: "Внизу слева") }
    public var bottomRight: String { l.pick(en: "Bottom Right", ru: "Внизу справа") }
    public var center: String { l.pick(en: "Center", ru: "По центру") }

    // MARK: - Themes and sizes

    public var themeGraphite: String { l.pick(en: "Graphite", ru: "Графит") }
    public var themeLiquidGlass: String { l.pick(en: "Liquid Glass", ru: "Liquid Glass") }
    public var themeMidnight: String { l.pick(en: "Midnight", ru: "Полночь") }
    public var themeLight: String { l.pick(en: "Light", ru: "Светлая") }
    public var sizeCompact: String { l.pick(en: "Compact", ru: "Компактный") }
    public var sizeRegular: String { l.pick(en: "Regular", ru: "Обычный") }
    public var sizeStrip: String { l.pick(en: "Strip", ru: "Полоса") }

    // MARK: - Strip scope (menu items and the settings picker share these)

    /// The account the card follows, as the other sizes show it.
    public var scopeSelected: String { l.pick(en: "This Account", ru: "Этот аккаунт") }
    /// Brand names: every Claude account, every Codex account.
    public var scopeClaude: String { l.pick(en: "Claude", ru: "Claude") }
    public var scopeCodex: String { l.pick(en: "Codex", ru: "Codex") }
    public var scopeAll: String { l.pick(en: "All Accounts", ru: "Все аккаунты") }
    public var thirdTileWeekly: String { l.pick(en: "Weekly reset", ru: "Недельный сброс") }
    public var thirdTileSession: String { l.pick(en: "Session window", ru: "Окно сессии") }
    public var thirdTileAgents: String { l.pick(en: "Agents", ru: "Агенты") }

    // MARK: - Coach mark

    public var coachMark: String {
        l.pick(
            en: "Drag it anywhere. Double-click to minimize.",
            ru: "Перетащите куда удобно. Двойной клик — свернуть."
        )
    }

    // MARK: - Settings rows

    public var sectionTitle: String { l.pick(en: "Floating card", ru: "Плавающая карточка") }
    public var themeRow: String { l.pick(en: "Theme", ru: "Оформление") }
    public var sizeRow: String { l.pick(en: "Size", ru: "Размер") }
    public var accountRow: String { l.pick(en: "Account", ru: "Аккаунт") }
    public var thirdTileRow: String { l.pick(en: "Third tile", ru: "Третья плитка") }
    /// The strip's scope picker, shown only while the size is Strip.
    public var scopeRow: String { l.pick(en: "Show", ru: "Показывать") }
    public var scopeCaption: String {
        l.pick(
            en: "The strip lists one chip per limit window of these accounts and leads with the week that binds.",
            ru: "Полоса показывает по чипу на каждое окно лимита этих аккаунтов, а крупно — неделю, которая ограничивает."
        )
    }
    public var keepAboveRow: String { l.pick(en: "Keep above other windows", ru: "Поверх других окон") }
    /// The `IslandScale` slider. Named after what it does, so it is never mistaken for the card's own size above it.
    public var textSizeRow: String { l.pick(en: "Size of text and controls", ru: "Размер текста и элементов") }
    /// The same setting as the menu item, in a settings row: sentence case, as macOS labels are.
    public var snapRow: String { l.pick(en: "Snap while dragging", ru: "Притягивать при перетаскивании") }
    /// The row that holds the "Reset Position" button.
    public var positionRow: String { l.pick(en: "Position", ru: "Положение") }
    public var keepAboveCaption: String {
        l.pick(
            en: "Off keeps the card on the desktop, behind your windows.",
            ru: "Если выключить, карточка останется на рабочем столе, под окнами."
        )
    }
    public var snapCaption: String {
        l.pick(
            en: "Pulls to the edges, the corners and the center. Hold ⌘ while dragging to place it exactly.",
            ru: "Притягивает к краям, углам и центру. Удерживайте ⌘ при перетаскивании, чтобы поставить точно."
        )
    }
    /// The display picker.
    public var showOn: String { l.pick(en: "Show on", ru: "Показывать на") }
    public var displayWhereLeft: String { l.pick(en: "Where I leave it", ru: "Где оставлю") }
    public var displayMain: String { l.pick(en: "Main display", ru: "Основной экран") }
    public var resetPosition: String { l.pick(en: "Reset Position", ru: "Вернуть на место") }
    public var resetPositionCaption: String {
        l.pick(
            en: "Puts the card back in the top-right corner of the main display.",
            ru: "Вернёт карточку в правый верхний угол основного экрана."
        )
    }
    public var stageHint: String {
        l.pick(
            en: "The card as it will look on your desktop. Drag it right on the screen.",
            ru: "Карточка такой, какой будет на рабочем столе. Перетаскивайте её прямо на экране."
        )
    }

    // MARK: - Accessibility

    /// The expanded card as one container.
    public var cardA11y: String { l.pick(en: "Codometer card", ru: "Карточка Codometer") }
    /// The minimized card: "Codometer, minimized. Work, Claude, 64 percent used".
    public func pillA11y(_ summary: String) -> String {
        l.pick(en: "Codometer, minimized. \(summary)", ru: "Codometer, свёрнуто. \(summary)")
    }
    /// "64 percent used" (spoken, so the unit is a word).
    public func usedA11y(_ percent: String) -> String {
        l.pick(en: "\(percent) used", ru: "использовано \(percent)")
    }
    /// "64 percent left" (spoken, so the unit is a word).
    public func leftA11y(_ percent: String) -> String {
        l.pick(en: "\(percent) left", ru: "осталось \(percent)")
    }
    /// How many accounts a merged chip stands for: "2 accounts".
    public func accountsSharingA11y(_ count: Int) -> String {
        l.plural(
            count,
            en: (one: "\(count) account", other: "\(count) accounts"),
            ru: ("\(count) аккаунт", "\(count) аккаунта", "\(count) аккаунтов")
        )
    }
    /// The "+N" chip: "3 more windows".
    public func moreWindowsA11y(_ count: Int) -> String {
        l.plural(
            count,
            en: (one: "\(count) more window", other: "\(count) more windows"),
            ru: ("ещё \(count) окно", "ещё \(count) окна", "ещё \(count) окон")
        )
    }
    /// "forecast 92 percent at reset".
    public func forecastA11y(_ percent: String) -> String {
        l.pick(en: "forecast \(percent) at reset", ru: "прогноз \(percent) к сбросу")
    }
    /// "Resets in 5 days 16 hours".
    public func resetsInA11y(_ duration: String) -> String {
        l.pick(en: "Resets in \(duration)", ru: "Сброс через \(duration)")
    }
    /// "Available again in 2 hours".
    public func backInA11y(_ duration: String) -> String {
        l.pick(en: "Available again in \(duration)", ru: "Снова доступно через \(duration)")
    }
    /// "Account 1 of 3".
    public func accountPosition(_ index: Int, of total: Int) -> String {
        l.pick(en: "Account \(index) of \(total)", ru: "Аккаунт \(index) из \(total)")
    }
    public var nextAccount: String { l.pick(en: "Next account", ru: "Следующий аккаунт") }
    public var previousAccount: String { l.pick(en: "Previous account", ru: "Предыдущий аккаунт") }
    public var openStatusPage: String { l.pick(en: "Open the service status page", ru: "Открыть страницу статуса сервиса") }
    /// VoiceOver hint on the account chip in the header.
    public var switchAccountHint: String { l.pick(en: "Shows another account", ru: "Показывает другой аккаунт") }
    /// The page dots as one control.
    public var pages: String { l.pick(en: "Accounts", ru: "Аккаунты") }

    // MARK: - Templates
    //
    // Every changing value gets a hidden template of the widest realistic text, per language, so the card and the pill
    // never resize when the numbers change. `CardCopyFitTests` keeps each template at least as wide as its values.

    /// The widest percentage: "<1%" is wider than "100%", because "<" is wider than a digit.
    public var percentTemplate: String { l.pick(en: "<88%", ru: "<88%") }
    /// The widest countdown: minutes are the widest unit, so the template carries them.
    public var countdownTemplate: String { l.pick(en: "88h 88m", ru: "88\u{00A0}дн 88\u{00A0}мин") }
    /// The widest status pill text.
    public var pillTemplate: String { l.pick(en: "Partial outage", ru: "Лимит исчерпан") }
    /// The widest "+N" badge on a minimized card with several accounts.
    public var moreTemplate: String { l.pick(en: "+8", ru: "+8") }
    /// The widest line under the strip's hero: a three-digit percentage, then hours and minutes, the widest countdown.
    public var stripUsedLineTemplate: String {
        l.pick(en: "100% used · ⟳ 88h 88m", ru: "100% использовано · ⟳ 88\u{00A0}ч 88\u{00A0}мин")
    }
    /// The widest countdown a chip prints.
    public var stripResetTemplate: String { l.pick(en: "⟳ 88h 88m", ru: "⟳ 88\u{00A0}ч 88\u{00A0}мин") }
    /// The widest chip title the card writes itself; a provider's own label may be longer and truncates.
    public var stripTitleTemplate: String { l.pick(en: "Weekly · Sonnet", ru: "Неделя · Sonnet") }
}

extension Localizer {
    public var card: CardStrings { CardStrings(l: self) }
}
