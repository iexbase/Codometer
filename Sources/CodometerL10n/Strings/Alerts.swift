import Foundation

/// Settings → Notifications: thresholds, events, quiet options, sounds and the island's peek.
public struct AlertsStrings: Sendable {
    let l: Localizer

    /// Under the pane's title.
    public var paneSubtitle: String {
        l.pick(
            en: "Choose when to get notified, keep the noise down, and decide whether your limits show themselves.",
            ru: "Когда предупреждать, как убрать лишний шум и показывать ли лимиты при событии."
        )
    }

    // MARK: Thresholds

    public var thresholdsTitle: String { l.pick(en: "Notify when usage reaches", ru: "Предупреждать при достижении") }
    /// VoiceOver for one threshold chip, with a prose percentage: "Notify at 80%".
    public func thresholdA11y(_ percent: String) -> String {
        l.pick(en: "Notify at \(percent)", ru: "Предупреждать при \(percent)")
    }
    public var thresholdsFooter: String {
        l.pick(
            en: "Every limit is checked, including weekly limits for individual models. You get one notification per threshold.",
            ru: "Проверяются все лимиты, включая недельные лимиты отдельных моделей. На каждый порог — одно уведомление."
        )
    }

    // MARK: Events

    public var eventsTitle: String { l.pick(en: "Events", ru: "События") }
    public var limitReset: String { l.pick(en: "Limit reset", ru: "Лимит сброшен") }
    public var agentFinished: String { l.pick(en: "Agent finished", ru: "Агент закончил работу") }
    public var agentWaiting: String { l.pick(en: "Agent waiting for you", ru: "Агент ждёт вас") }
    public var agentWaitingSubtitle: String {
        l.pick(en: "Approvals, questions, and other input", ru: "Подтверждение, ответ на вопрос или ввод")
    }
    public var skipShortTurns: String { l.pick(en: "Skip short turns", ru: "Не сообщать о коротких ходах") }
    /// Under “Skip short turns”; `finished` is the event's own name (`agentFinished`).
    public func skipShortTurnsSubtitle(finished: String) -> String {
        l.pick(
            en: "No “\(finished)” notification for turns shorter than this",
            ru: "Для ходов короче выбранного уведомление «\(finished)» не приходит"
        )
    }
    /// A segmented choice that turns the option off: no skipping, no peek.
    public var off: String { l.pick(en: "Off", ru: "Выкл.") }

    /// A picker's duration for VoiceOver, in words with seconds: "20 seconds", "1 minute 30 seconds" | «20 секунд».
    public func secondsA11y(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let minutes = total / 60
        let rest = total % 60
        let parts: [(Int, Duration.UnitsFormatStyle.Unit)] = [(minutes, .minutes), (rest, .seconds)]
        let spoken = parts
            .filter { $0.0 > 0 }
            .map { count, unit in
                Duration.seconds(Int64(unit == .minutes ? count * 60 : count))
                    .formatted(Duration.UnitsFormatStyle(allowedUnits: [unit], width: .wide).locale(l.locale))
            }
            .joined(separator: " ")
        return spoken.isEmpty ? off : spoken
    }

    // MARK: Less noise

    public var quietTitle: String { l.pick(en: "Less noise", ru: "Без лишнего шума") }
    public var withdrawResolved: String {
        l.pick(en: "Clear alerts once the agent continues", ru: "Убирать уведомление, когда агент продолжит работу")
    }
    public var withdrawResolvedSubtitle: String {
        l.pick(
            en: "“Waiting for you” leaves Notification Center as soon as you respond.",
            ru: "«Ждёт вас» исчезает из Центра уведомлений, как только вы ответите."
        )
    }
    public var coalesce: String { l.pick(en: "Group alerts that arrive together", ru: "Объединять несколько событий") }
    public var coalesceSubtitle: String {
        l.pick(
            en: "Events that happen almost at once arrive as one notification.",
            ru: "Почти одновременные события приходят одним уведомлением."
        )
    }
    /// `accountsPane` is the Accounts pane's name.
    public func quietFooter(accountsPane: String) -> String {
        l.pick(
            en: "To silence a whole group of accounts, turn off its notifications in \(accountsPane).",
            ru: "Уведомления можно отключить для целой группы аккаунтов в разделе «\(accountsPane)»."
        )
    }

    // MARK: Sound and island

    public var soundAndIslandTitle: String { l.pick(en: "Sound and screen", ru: "Звук и экран") }
    public var playSounds: String { l.pick(en: "Play sounds", ru: "Звуковые сигналы") }
    /// Buttons that preview each sound.
    public var soundFinished: String { l.pick(en: "Finished", ru: "Готово") }
    public var soundAttention: String { l.pick(en: "Attention", ru: "Внимание") }
    public var soundThreshold: String { l.pick(en: "Threshold", ru: "Порог") }
    /// VoiceOver for a preview button, with the button's own name.
    public func playSoundA11y(_ name: String) -> String {
        l.pick(en: "Play the “\(name)” sound", ru: "Проиграть звук «\(name)»")
    }
    /// How long the island opens by itself when something happens.
    public var peek: String { l.pick(en: "Open on events", ru: "Показывать при событии") }

    // MARK: Permission

    /// Banner at the top of the pane when macOS is set to show no notifications from Codometer.
    public var permissionDeniedTitle: String {
        l.pick(en: "Notifications are turned off", ru: "Уведомления отключены")
    }
    public var permissionDeniedBody: String {
        l.pick(
            en: "macOS won’t show Codometer’s notifications. The settings below still apply once you turn them on.",
            ru: "macOS не показывает уведомления Codometer. Настройки ниже начнут действовать, когда вы их включите."
        )
    }
    /// Opens System Settings → Notifications.
    public var openNotificationSettings: String {
        l.pick(en: "Open Notification Settings", ru: "Открыть настройки уведомлений")
    }
}

extension Localizer {
    public var alerts: AlertsStrings { AlertsStrings(l: self) }
}
