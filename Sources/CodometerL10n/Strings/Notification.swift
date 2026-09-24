/// System notifications about limits and agents, plus the few messages the app shell shows outside its views: the
/// launch alert and a failed login item change.
///
/// Titles start with the account's label, which is user data: "Work: 80% used". Bodies are sentences; the presenter
/// adds the periods. Percentages come from `format.percent`, window and session names from `UsageFormat`.
public struct NotificationStrings: Sendable {
    let l: Localizer

    // MARK: Titles

    public func limitReached(account: String) -> String {
        l.pick(en: "\(account): limit reached", ru: "\(account): лимит исчерпан")
    }
    /// A usage threshold was crossed: "Work: 80% used".
    public func thresholdReached(account: String, percent: String) -> String {
        l.pick(en: "\(account): \(percent) used", ru: "\(account): использовано \(percent)")
    }
    public func limitReset(account: String) -> String {
        l.pick(en: "\(account): limit reset", ru: "\(account): лимит сброшен")
    }
    public func agentFinished(account: String) -> String {
        l.pick(en: "\(account): agent finished", ru: "\(account): агент закончил")
    }
    public func needsApproval(account: String) -> String {
        l.pick(en: "\(account): needs approval", ru: "\(account): ждёт подтверждения")
    }
    public func needsInput(account: String) -> String {
        l.pick(en: "\(account): needs input", ru: "\(account): ждёт ввода")
    }
    public func waitingForYou(account: String) -> String {
        l.pick(en: "\(account): waiting for you", ru: "\(account): ждёт вас")
    }

    // MARK: Bodies

    /// The first sentence of a threshold notification: "Weekly · All models is at 82%". The title already says
    /// "80% used", so the body leads with the window and never repeats the word.
    public func windowUsage(window: String, percent: String) -> String {
        l.pick(en: "\(window) is at \(percent)", ru: "\(window) — \(percent)")
    }
    /// A reset notification's body: "Weekly · All models is available again".
    public func availableAgain(window: String) -> String {
        l.pick(en: "\(window) is available again", ru: "\(window) — лимит снова доступен")
    }

    // MARK: Summary lines

    // One notification sums up a burst of alerts; each alert becomes one of these, joined by `AlertSummary`.

    /// "Work: limit reached (Weekly · All models)".
    public func limitReachedLine(account: String, window: String) -> String {
        l.pick(en: "\(account): limit reached (\(window))", ru: "\(account): лимит исчерпан (\(window))")
    }
    /// "Work: 82% used (Weekly · All models)".
    public func usageLine(account: String, percent: String, window: String) -> String {
        l.pick(en: "\(account): \(percent) used (\(window))", ru: "\(account): использовано \(percent) (\(window))")
    }
    /// "Work: limit reset (Session · 5h)".
    public func limitResetLine(account: String, window: String) -> String {
        l.pick(en: "\(account): limit reset (\(window))", ru: "\(account): лимит сброшен (\(window))")
    }
    /// "Work: agent finished (codometer)", with the session's project folder.
    public func agentFinishedLine(account: String, session: String) -> String {
        l.pick(en: "\(account): agent finished (\(session))", ru: "\(account): агент закончил (\(session))")
    }
    public func needsApprovalLine(account: String, session: String) -> String {
        l.pick(en: "\(account): needs approval (\(session))", ru: "\(account): ждёт подтверждения (\(session))")
    }
    public func needsInputLine(account: String, session: String) -> String {
        l.pick(en: "\(account): needs input (\(session))", ru: "\(account): ждёт ввода (\(session))")
    }
    public func waitingForYouLine(account: String, session: String) -> String {
        l.pick(en: "\(account): waiting for you (\(session))", ru: "\(account): ждёт вас (\(session))")
    }

    // MARK: App messages

    /// The title of the alert shown when Codometer cannot start (before settings load, so in the system language).
    /// An alert's message text is a sentence, so it is sentence case even in English.
    public var launchFailedTitle: String { l.pick(en: "Codometer can’t start", ru: "Не удалось запустить Codometer") }
    /// The alert's text when the data folder cannot be created, followed by the technical `detail` (English).
    public func dataFolderFailedMessage(detail: String) -> String {
        l.pick(
            en: "Codometer couldn’t create the folder where it keeps its settings and history.\n\n\(detail)",
            ru: "Не удалось создать папку, в которой Codometer хранит настройки и историю.\n\n\(detail)"
        )
    }
    /// The alert's only button: Codometer quits.
    public var quit: String { l.pick(en: "Quit", ru: "Выйти") }

    /// Shown under the "Open at login" toggle when macOS refused the change; `reason` is the system's own
    /// description. Both languages name the setting the way the toggle does.
    public func loginItemFailed(reason: String) -> String {
        l.pick(en: "Couldn’t change “Open at login”: \(reason)", ru: "Не удалось изменить «Открывать при входе в систему»: \(reason)")
    }
}

extension Localizer {
    public var notification: NotificationStrings { NotificationStrings(l: self) }
}
