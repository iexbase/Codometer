import Foundation

/// The first-run welcome flow: six steps, the optional second-account wizard, and the window's chrome.
///
/// Edge, trigger and group names come from the areas that own them (`placement`, `accounts`, `groups`), so the flow
/// never invents a second name for something Settings already names.
public struct OnboardingStrings: Sendable {
    let l: Localizer

    // MARK: Window and chrome

    public var windowTitle: String { l.pick(en: "Welcome to Codometer", ru: "Знакомство с Codometer") }
    /// Announced on every step change and read as the indicator's value.
    public func step(_ index: Int, of total: Int) -> String {
        l.pick(en: "Step \(index) of \(total)", ru: "Шаг \(index) из \(total)")
    }
    public var back: String { l.pick(en: "Back", ru: "Назад") }
    public var continueAction: String { l.pick(en: "Continue", ru: "Продолжить") }
    public var skip: String { l.pick(en: "Skip", ru: "Пропустить") }
    /// The width the footer reserves for its primary button, so the button never resizes between steps.
    public var primaryButtonTemplate: String { l.pick(en: "Start Using Codometer", ru: "Начать пользоваться") }

    // MARK: 1 — Welcome

    public var welcomeTitle: String { l.pick(en: "Your AI limits, always in sight", ru: "Лимиты AI всегда перед глазами") }
    public var welcomeBody: String {
        l.pick(
            en: "Codometer watches your Claude Code and Codex limits and the agents working for you, and keeps them one glance away.",
            ru: "Codometer следит за лимитами Claude Code и Codex и за агентами, которые работают на вас, — и держит их в поле зрения."
        )
    }
    public var promiseLocal: String { l.pick(en: "Everything stays on this Mac", ru: "Всё остаётся на этом Mac") }
    public var promiseLocalDetail: String {
        l.pick(
            en: "Usage is read from the files Claude Code and Codex already write. Nothing is uploaded.",
            ru: "Расход читается из файлов, которые Claude Code и Codex и так пишут. Ничего никуда не отправляется."
        )
    }
    public var promiseNoSecrets: String { l.pick(en: "Never your tokens or conversations", ru: "Никаких токенов и переписки") }
    public var promiseNoSecretsDetail: String {
        l.pick(
            en: "Codometer doesn’t open token files and never stores what you and the agents say.",
            ru: "Codometer не открывает файлы с токенами и не сохраняет то, что вы и агенты пишете."
        )
    }
    public var promiseNoChanges: String { l.pick(en: "Never changes your setup", ru: "Ничего у вас не меняет") }
    public var promiseNoChangesDetail: String {
        l.pick(
            en: "Your Claude Code and Codex settings and profile folders are only ever read.",
            ru: "Настройки и папки профилей Claude Code и Codex только читаются."
        )
    }

    // MARK: 2 — Found on this Mac

    /// The same name the Accounts pane uses for the section.
    public var foundTitle: String { l.pick(en: "Found on this Mac", ru: "Найдены на этом Mac") }
    public var foundBody: String {
        l.pick(
            en: "Turn on the accounts you want Codometer to watch. You can change this later in Settings.",
            ru: "Включите аккаунты, за которыми Codometer будет следить. Это можно изменить позже в настройках."
        )
    }
    public var track: String { l.pick(en: "Track", ru: "Отслеживать") }
    /// VoiceOver for one account's switch: "Track Work".
    public func trackA11y(_ account: String) -> String {
        l.pick(en: "Track \(account)", ru: "Отслеживать «\(account)»")
    }
    public var signedIn: String { l.pick(en: "Signed in", ru: "Вход выполнен") }
    /// "Signed in · Pro 20x".
    public func signedInPlan(_ plan: String) -> String {
        l.pick(en: "Signed in · \(plan)", ru: "Вход выполнен · \(plan)")
    }
    public var notSignedIn: String { l.pick(en: "Not signed in yet", ru: "Вход ещё не выполнен") }
    /// "Claude Code isn’t installed".
    public func notInstalled(_ provider: String) -> String {
        l.pick(en: "\(provider) isn’t installed", ru: "\(provider) не установлен")
    }
    public var notAProfile: String { l.pick(en: "Not a profile folder yet", ru: "Это ещё не папка профиля") }
    public var symlinkRefused: String {
        l.pick(en: "This folder is a link, so Codometer leaves it alone", ru: "Это ссылка — Codometer её не трогает")
    }
    public var noProfilesTitle: String { l.pick(en: "No Claude Code or Codex profiles yet", ru: "Профилей Claude Code и Codex пока нет") }
    public var noProfilesBody: String {
        l.pick(
            en: "Install Claude Code or Codex and sign in. Codometer finds the profile on its own the next time you open it.",
            ru: "Установите Claude Code или Codex и войдите. Codometer сам найдёт профиль при следующем запуске."
        )
    }
    public var checkAgain: String { l.pick(en: "Check Again", ru: "Проверить снова") }

    // MARK: 3 — Presentation

    public var presentationTitle: String { l.pick(en: "Where your limits live", ru: "Где живут ваши лимиты") }
    public var presentationBody: String {
        l.pick(
            en: "The island sits on a screen edge and opens when you reach it. The floating card goes anywhere you drop it.",
            ru: "Остров стоит у края экрана и раскрывается, когда вы к нему тянетесь. Плавающую карточку можно положить где угодно."
        )
    }
    public var style: String { l.pick(en: "Style", ru: "Стиль") }
    public var styleIsland: String { l.pick(en: "Island", ru: "Остров") }
    public var styleFloatingCard: String { l.pick(en: "Floating card", ru: "Плавающая карточка") }
    public var edge: String { l.pick(en: "Edge", ru: "Край") }
    public var notchFusion: String { l.pick(en: "Blend with the camera notch", ru: "Сливаться с вырезом камеры") }
    public var notchFusionDetail: String {
        l.pick(
            en: "At the top center of a display with a notch, the island draws solid black and looks like part of it.",
            ru: "Наверху по центру экрана с вырезом остров становится чёрным и выглядит его частью."
        )
    }
    public var previewA11y: String { l.pick(en: "Preview of the chosen style", ru: "Предпросмотр выбранного стиля") }

    // MARK: 4 — Second account

    public var secondAccountTitle: String { l.pick(en: "A second account?", ru: "Второй аккаунт?") }
    public var secondAccountBody: String {
        l.pick(
            en: "Claude Code and Codex keep one sign-in per profile folder, so a second account needs a folder of its own.",
            ru: "Claude Code и Codex держат один вход на папку профиля, поэтому второму аккаунту нужна своя папка."
        )
    }
    public var secondAccountStart: String { l.pick(en: "Set Up a Second Account", ru: "Настроить второй аккаунт") }
    /// Next to the button, as a sentence: it reads as a note, not as a second button nobody can press.
    public var secondAccountOptional: String { l.pick(en: "This step is optional.", ru: "Этот шаг необязательный.") }
    public var chooseService: String { l.pick(en: "Which service is it for?", ru: "Для какого сервиса?") }
    public var profileName: String { l.pick(en: "Profile name", ru: "Название профиля") }
    /// Under the field: "The folder will be ~/.claude-work."
    public func profileFolderNote(_ folder: String) -> String {
        l.pick(en: "The folder will be \(folder).", ru: "Папка будет \(folder).")
    }
    /// The rule, under the step's title: what a profile name may contain.
    public var profileNameRule: String {
        l.pick(
            en: "Use letters, digits, underscores or dots, up to 24 characters.",
            ru: "Используйте буквы, цифры, подчёркивания и точки — не больше 24 символов."
        )
    }
    /// Under the field, in place of the folder line, when the typed name breaks the rule above it.
    public var profileNameInvalid: String {
        l.pick(en: "That name can’t be used.", ru: "Такое название не подойдёт.")
    }
    public var profileFolderTaken: String {
        l.pick(en: "That folder already exists, so Codometer will just watch it.", ru: "Такая папка уже есть — Codometer просто будет за ней следить.")
    }
    public var signInTitle: String { l.pick(en: "Sign in to the new profile", ru: "Войдите в новый профиль") }
    public var signInClaudeNote: String {
        l.pick(
            en: "Run this in Terminal, then type /login in Claude Code. Start Claude this way whenever you work in this account.",
            ru: "Выполните это в Терминале, затем введите /login в Claude Code. Запускайте Claude так каждый раз, когда работаете в этом аккаунте."
        )
    }
    public var signInCodexNote: String {
        l.pick(
            en: "Run this in Terminal and finish the sign-in in your browser.",
            ru: "Выполните это в Терминале и завершите вход в браузере."
        )
    }
    public var signInNoAutomation: String {
        l.pick(
            en: "Codometer never runs commands for you and never writes into a profile folder.",
            ru: "Codometer не выполняет команды за вас и ничего не пишет в папки профилей."
        )
    }
    public var waitingTitle: String { l.pick(en: "Waiting for you to sign in…", ru: "Ожидание входа…") }
    public var waitingBody: String {
        l.pick(
            en: "Codometer checks the folder every couple of seconds. Leave this window open.",
            ru: "Codometer проверяет папку каждые пару секунд. Оставьте это окно открытым."
        )
    }
    public var detectedTitle: String { l.pick(en: "Found the new profile", ru: "Новый профиль найден") }
    public var accountName: String { l.pick(en: "Name", ru: "Название") }

    // MARK: 5 — Notifications and startup

    public var notificationsTitle: String { l.pick(en: "Notifications and startup", ru: "Уведомления и запуск") }
    public var notificationsBody: String {
        l.pick(
            en: "Codometer can tell you when an agent needs you, when a limit is close, and when it resets.",
            ru: "Codometer может сообщать, когда агент ждёт вас, когда лимит близко и когда он сбросился."
        )
    }
    public var allowNotifications: String { l.pick(en: "Allow Notifications", ru: "Разрешить уведомления") }
    public var notificationsOn: String { l.pick(en: "Notifications are on", ru: "Уведомления включены") }
    public var notificationsOff: String { l.pick(en: "Notifications are off in System Settings", ru: "Уведомления выключены в системных настройках") }
    /// The summary line when the permission was never asked for: nothing is switched off anywhere yet.
    public var notificationsNotAsked: String { l.pick(en: "Notifications are not turned on", ru: "Уведомления не включены") }
    public var openNotificationSettings: String { l.pick(en: "Open Notification Settings", ru: "Открыть настройки уведомлений") }

    // MARK: 6 — Done

    public var doneTitle: String { l.pick(en: "You’re all set", ru: "Всё готово") }
    public func doneAccounts(_ count: Int) -> String {
        l.plural(
            count,
            en: (one: "Codometer is watching \(count) account.", other: "Codometer is watching \(count) accounts."),
            ru: ("Codometer следит за \(count) аккаунтом.", "Codometer следит за \(count) аккаунтами.", "Codometer следит за \(count) аккаунтами.")
        )
    }
    public var doneNoAccounts: String {
        l.pick(
            en: "No accounts yet. Add one in Settings whenever you’re ready.",
            ru: "Аккаунтов пока нет. Добавьте аккаунт в настройках, когда будете готовы."
        )
    }
    public var doneBody: String {
        l.pick(
            en: "Everything here lives in Settings, and the menu bar icon is always there.",
            ru: "Всё это есть в настройках, а значок в строке меню всегда на месте."
        )
    }
    public var start: String { l.pick(en: "Start Using Codometer", ru: "Начать пользоваться") }
}

extension Localizer {
    public var onboarding: OnboardingStrings { OnboardingStrings(l: self) }
}
