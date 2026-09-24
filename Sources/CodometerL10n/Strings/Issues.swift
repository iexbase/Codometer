/// Why an account has no fresh numbers, as a banner or settings row names it. `name` is a provider name.
public struct IssuesStrings: Sendable {
    let l: Localizer

    public var claudeCodeMissing: String { l.pick(en: "Can’t find Claude Code", ru: "Claude Code не найден") }
    public var codexMissing: String {
        l.pick(en: "Can’t find Codex (install ChatGPT.app or the codex CLI)", ru: "Codex не найден (нужен ChatGPT.app или codex CLI)")
    }
    public func untrusted(_ name: String) -> String {
        l.pick(en: "\(name) didn’t pass the code signature check", ru: "\(name) не прошёл проверку подписи")
    }
    public func signedOut(_ name: String) -> String {
        l.pick(en: "You’re not signed in to \(name) in this profile", ru: "Вы не вошли в \(name) в этом профиле")
    }
    public func unexpectedOutput(_ name: String) -> String {
        l.pick(en: "\(name) returned data in an unfamiliar format", ru: "\(name) вернул данные в незнакомом формате")
    }
    public func commandFailed(_ name: String) -> String {
        l.pick(en: "The request to \(name) failed", ru: "Запрос к \(name) завершился ошибкой")
    }
    public func timedOut(_ name: String) -> String {
        l.pick(en: "\(name) didn’t respond in time", ru: "\(name) не ответил вовремя")
    }
    public var profileMissing: String { l.pick(en: "Can’t find the profile folder", ru: "Папка профиля не найдена") }
    public var offline: String { l.pick(en: "No internet connection", ru: "Нет подключения к сети") }
    public var internalFailure: String { l.pick(en: "Something went wrong inside Codometer", ru: "Что-то пошло не так в Codometer") }
}

extension Localizer {
    public var issues: IssuesStrings { IssuesStrings(l: self) }
}
