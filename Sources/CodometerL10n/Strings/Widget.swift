/// The desktop widgets: gallery names, empty states, the reset and freshness lines, badges and VoiceOver.
///
/// Status lines are captions: sentence case in English, lowercase in Russian. Countdowns are live system text, so the
/// phrases around them are slots: `Text("\(slot.prefix)\(countdown)\(slot.suffix)")`.
public struct WidgetStrings: Sendable {
    let l: Localizer

    // MARK: Gallery

    /// The widget with every account.
    public var allName: String { l.pick(en: "AI Limits", ru: "Лимиты AI") }
    public var allDescription: String {
        l.pick(
            en: "Claude and Codex limits at a glance: usage rings, reset times, and agents waiting for you.",
            ru: "Лимиты Claude и Codex: кольца расхода, время сброса и агенты, которые ждут вас."
        )
    }
    /// The strip widgets: "AI Limits · Strip", "Claude · Strip", "Codex · Strip".
    public func stripName(_ scope: String) -> String {
        l.pick(en: "\(scope) · Strip", ru: "\(scope) · полоса")
    }
    public var stripDescription: String {
        l.pick(
            en: "A wide strip: what’s left of the week in one big figure, and every limit with its reset.",
            ru: "Широкая полоса: сколько осталось за неделю — крупно, и каждый лимит со своим сбросом."
        )
    }

    /// The Claude or Codex widget; its name is the provider's name.
    public func providerDescription(_ provider: String) -> String {
        l.pick(
            en: "Your busiest \(provider) account: usage rings, reset times, and agent activity.",
            ru: "Самый загруженный аккаунт \(provider): кольца расхода, время сброса и работа агентов."
        )
    }

    // MARK: Empty states

    /// Under "No data" in the small widget.
    public var openApp: String { l.pick(en: "Open Codometer", ru: "Откройте Codometer") }
    /// Under "No data" in the medium and large widgets.
    public var openAppToSeeLimits: String {
        l.pick(en: "Open Codometer to see your limits", ru: "Откройте Codometer, чтобы увидеть лимиты")
    }
    /// A provider widget without an account of that provider: "No Codex account".
    public func noAccount(_ provider: String) -> String { l.pick(en: "No \(provider) account", ru: "Нет аккаунта \(provider)") }
    /// Under "No Codex account" in the small widget.
    public var addOne: String { l.pick(en: "Add one in Codometer", ru: "Добавьте его в Codometer") }
    /// Under "No Codex account" in the medium widget. The menu path never breaks across lines (no-break spaces).
    public func addProfile(_ provider: String) -> String {
        l.pick(
            en: "Add a \(provider) profile in Codometer\u{00A0}→\u{00A0}Settings\u{00A0}→\u{00A0}Accounts",
            ru: "Добавьте профиль \(provider) в Codometer\u{00A0}→\u{00A0}Настройки\u{00A0}→\u{00A0}Аккаунты"
        )
    }

    // MARK: Status lines

    /// An account whose first numbers have not arrived yet.
    public var waitingForData: String { l.pick(en: "Waiting for data", ru: "ожидание данных") }
    /// A blocked account whose countdown is the headline.
    public var limitReached: String { l.pick(en: "Limit reached", ru: "лимит исчерпан") }
    /// A window without a known reset time.
    public var noResetTime: String { l.pick(en: "No reset time", ru: "без времени сброса") }
    /// Around a live countdown: "Resets in 2 hr, 13 min".
    public var resetsIn: (prefix: String, suffix: String) {
        l.slot(en: ("Resets in ", ""), ru: ("сброс через ", ""))
    }
    /// Around a live countdown under a title that already names the window: "Resets in 2 hr" | «через 2 ч».
    public var resetsInShort: (prefix: String, suffix: String) {
        l.slot(en: ("Resets in ", ""), ru: ("через ", ""))
    }
    /// Around a blocked account's live countdown: "Back in 2 hr, 13 min".
    public var backIn: (prefix: String, suffix: String) {
        l.slot(en: ("Back in ", ""), ru: ("через ", ""))
    }
    /// Around the live time of a stale reading: "As of 2:32 PM", "As of Sep 15".
    public var staleAsOf: (prefix: String, suffix: String) {
        l.slot(en: ("As of ", ""), ru: ("данные от ", ""))
    }
    /// Around the live time of the newest reading, at the bottom of the large widget: "As of 2:32 PM".
    public var latestAsOf: (prefix: String, suffix: String) {
        l.slot(en: ("As of ", ""), ru: ("данные на ", ""))
    }

    // MARK: Strip layout

    /// The unit after the strip's headline number, which counts what is left: "64% left".
    public var leftUnit: String { l.pick(en: "left", ru: "осталось") }
    /// Under the headline, around the live reset countdown, with `used` from `format.percent`: "36% used · in 5 days".
    public func usedResetsIn(_ used: String) -> (prefix: String, suffix: String) {
        l.slot(en: ("\(used) used · in ", ""), ru: ("расход \(used) · через ", ""))
    }
    /// Under the headline when the window has no known reset time: "36% used".
    public func usedNoReset(_ used: String) -> String { l.pick(en: "\(used) used", ru: "расход \(used)") }
    /// The overflow tile at the end of the chips, spoken: "2 more windows".
    public func moreWindows(_ count: Int) -> String {
        l.plural(count, en: ("\(count) more window", "\(count) more windows"), ru: ("ещё \(count) окно", "ещё \(count) окна", "ещё \(count) окон"))
    }
    /// The badge on a chip that stands for several accounts, spoken: "2 accounts".
    public func accountsSharing(_ count: Int) -> String {
        l.plural(count, en: ("\(count) account", "\(count) accounts"), ru: ("\(count) аккаунт", "\(count) аккаунта", "\(count) аккаунтов"))
    }

    // MARK: Counts

    /// The large widget's footer when accounts did not fit: "2 more accounts".
    public func moreAccounts(_ count: Int) -> String {
        l.plural(count, en: ("\(count) more account", "\(count) more accounts"), ru: ("ещё \(count) аккаунт", "ещё \(count) аккаунта", "ещё \(count) аккаунтов"))
    }
    /// Agents at work, at the bottom of the large widget: "2 working".
    public func working(_ count: Int) -> String { l.pick(en: "\(count) working", ru: "в работе: \(count)") }
    /// The attention badge with its label: "2 waiting". The Russian verb agrees with the count.
    public func waiting(_ count: Int) -> String {
        l.plural(
            count,
            en: ("\(count) waiting", "\(count) waiting"),
            ru: ("ждёт вас: \(count)", "ждут вас: \(count)", "ждут вас: \(count)")
        )
    }

    // MARK: VoiceOver

    /// The attention badge: "2 agents are waiting for you".
    public func waitingA11y(_ count: Int) -> String {
        l.plural(
            count,
            en: ("\(count) agent is waiting for you", "\(count) agents are waiting for you"),
            ru: ("Вас ждёт \(count) агент", "Вас ждут \(count) агента", "Вас ждут \(count) агентов")
        )
    }
    /// The working badge: "2 agents are working".
    public func workingA11y(_ count: Int) -> String {
        l.plural(
            count,
            en: ("\(count) agent is working", "\(count) agents are working"),
            ru: ("Работает \(count) агент", "Работают \(count) агента", "Работают \(count) агентов")
        )
    }
    /// A usage number, with `percent` from `format.percent`: "64% used".
    public func percentUsedA11y(_ percent: String) -> String {
        l.pick(en: "\(percent) used", ru: "использовано \(percent)")
    }
    /// The strip's headline, with both numbers from `format.percent`: "Weekly: 64% left, 36% used".
    public func percentLeftA11y(_ title: String, left: String, used: String) -> String {
        l.pick(en: "\(title): \(left) left, \(used) used", ru: "\(title): осталось \(left), использовано \(used)")
    }
    /// A chip, with `percent` from `format.percent`: "Session · 5h: 42% used".
    public func chipA11y(_ title: String, used: String) -> String {
        l.pick(en: "\(title): \(used) used", ru: "\(title): использовано \(used)")
    }
    /// A usage number whose ring also shows the forecast ghost: "64% used, at this pace about 92% by reset". Both
    /// numbers come from `format.percent`.
    public func percentUsedForecastA11y(_ percent: String, projected: String) -> String {
        l.pick(
            en: "\(percent) used, at this pace about \(projected) by reset",
            ru: "использовано \(percent), при таком темпе к сбросу около \(projected)"
        )
    }
    /// A usage number whose forecast runs into the limit: "64% used, at this pace it runs out before the reset".
    public func percentUsedForecastLimitA11y(_ percent: String) -> String {
        l.pick(
            en: "\(percent) used, at this pace it runs out before the reset",
            ru: "использовано \(percent), при таком темпе лимит кончится до сброса"
        )
    }
}

extension Localizer {
    public var widget: WidgetStrings { WidgetStrings(l: self) }
}
