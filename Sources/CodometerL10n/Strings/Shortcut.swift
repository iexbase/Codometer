/// Settings → General → Keyboard shortcut, when the chosen combination does not reach Codometer (L3).
///
/// `keys` is always the key caps of the chosen shortcut ("⌃⌥Space"), never a translated name.
public struct ShortcutStrings: Sendable {
    let l: Localizer

    /// An enabled macOS shortcut uses the same keys, so the system answers first.
    public func unavailableMacOS(keys: String) -> String {
        l.pick(
            en: "\(keys) is used by macOS, so it won’t open Codometer.",
            ru: "Сочетание \(keys) занято macOS — Codometer его не получит."
        )
    }
    /// Another app registered the combination exclusively.
    public func unavailableApp(keys: String) -> String {
        l.pick(
            en: "\(keys) is taken by another app, so it won’t open Codometer.",
            ru: "Сочетание \(keys) занято другим приложением — Codometer его не получит."
        )
    }
    /// Registration failed for another reason; the code goes to Diagnostics, not here.
    public func unavailableFailed(keys: String) -> String {
        l.pick(
            en: "\(keys) couldn’t be registered, so it won’t open Codometer.",
            ru: "Сочетание \(keys) не удалось зарегистрировать — Codometer его не получит."
        )
    }
    /// Before the buttons that switch to a free combination.
    public var tryInstead: String { l.pick(en: "Try:", ru: "Попробуйте:") }
    /// VoiceOver for one of those buttons.
    public func tryA11y(keys: String) -> String {
        l.pick(en: "Use \(keys) instead", ru: "Использовать \(keys)")
    }
}

extension Localizer {
    public var shortcut: ShortcutStrings { ShortcutStrings(l: self) }
}
