/// Settings → General → Network: the one feature that makes network requests, off by default.
///
/// The explanation names both hosts and says plainly what those sites can see, so the toggle is an informed choice.
public struct NetworkStrings: Sendable {
    let l: Localizer

    public var title: String { l.pick(en: "Network", ru: "Сеть") }
    public var showServiceStatus: String { l.pick(en: "Show service status", ru: "Показывать статус сервисов") }
    /// The row's one-line explanation, under the toggle title.
    public var showServiceStatusSubtitle: String {
        l.pick(
            en: "A note in the island and on the card when Claude Code or Codex is having problems",
            ru: "Отметка на острове и карточке, когда у Claude Code или Codex сбой"
        )
    }

    /// The section footer: what is fetched, how often, and what those sites see. `hosts` comes from `format.list`.
    public func disclosure(hosts: String) -> String {
        l.pick(
            en: "While the island, the card or the menu is open, Codometer checks \(hosts) every 10 minutes and shows a note if Claude Code or Codex is having problems. These are public status pages: nothing about your accounts is sent, just the kind of request a browser makes, so those sites see your IP address. Codometer makes no other network requests.",
            ru: "Пока открыт остров, карточка или меню, Codometer раз в 10\u{00A0}минут проверяет \(hosts) и подскажет, если у Claude Code или Codex сбой. Это публичные страницы статуса: данные аккаунтов не передаются, только обычный запрос, как из браузера, поэтому эти сайты видят ваш IP-адрес. Больше Codometer никуда не обращается."
        )
    }
}

extension Localizer {
    public var network: NetworkStrings { NetworkStrings(l: self) }
}
