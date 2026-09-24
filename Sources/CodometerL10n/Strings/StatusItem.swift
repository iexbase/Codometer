/// The menu bar item: its tooltip and what VoiceOver says about its ring icon. Its menu uses `Menu`.
public struct StatusItemStrings: Sendable {
    let l: Localizer

    /// The tooltip over the menu bar item.
    public var help: String { l.pick(en: "Codometer: Claude and Codex limits", ru: "Codometer — лимиты Claude и Codex") }

    /// VoiceOver for the ring icon: the highest usage (`percent` from `format.percent`, `nil` without data) and how many
    /// agents wait: "Codometer, 64% used, 2 agents are waiting for you".
    public func iconA11y(percent: String?, waitingCount: Int) -> String {
        switch (percent, waitingCount > 0) {
        case (nil, false):
            return l.pick(en: "Codometer, no data", ru: "Codometer, нет данных")
        case (let percent?, false):
            return l.pick(en: "Codometer, \(percent) used", ru: "Codometer, использовано \(percent)")
        case (nil, true):
            return l.plural(
                waitingCount,
                en: ("Codometer, \(waitingCount) agent is waiting for you", "Codometer, \(waitingCount) agents are waiting for you"),
                ru: ("Codometer, вас ждёт \(waitingCount) агент", "Codometer, вас ждут \(waitingCount) агента", "Codometer, вас ждут \(waitingCount) агентов")
            )
        case (let percent?, true):
            return l.plural(
                waitingCount,
                en: (
                    "Codometer, \(percent) used, \(waitingCount) agent is waiting for you",
                    "Codometer, \(percent) used, \(waitingCount) agents are waiting for you"
                ),
                ru: (
                    "Codometer, использовано \(percent), вас ждёт \(waitingCount) агент",
                    "Codometer, использовано \(percent), вас ждут \(waitingCount) агента",
                    "Codometer, использовано \(percent), вас ждут \(waitingCount) агентов"
                )
            )
        }
    }
}

extension Localizer {
    public var statusItem: StatusItemStrings { StatusItemStrings(l: self) }
}
