/// Launch safety and the app's own lifecycle: the alert that stops a launch from the wrong place, the message a
/// second copy leaves behind, and the About panel.
///
/// The launch texts are shown before settings are read, so they follow the macOS language order
/// (`Language.resolve(.system)`).
public struct LifecycleStrings: Sendable {
    let l: Localizer

    // MARK: Where the app runs from

    /// Title of the critical alert shown when Codometer starts from a disk image, a temporary copy or a read-only
    /// volume. An alert title is a sentence, so English keeps sentence case here.
    public var moveToApplicationsTitle: String {
        l.pick(en: "Move Codometer to Applications", ru: "Переместите Codometer в «Программы»")
    }

    /// The alert's text when Codometer was opened straight from the mounted disk image.
    public var runningFromDiskImage: String {
        l.pick(
            en: "Codometer is running from a disk image. Drag Codometer to your Applications folder and open it from there.",
            ru: "Codometer запущен с образа диска. Перетащите Codometer в папку «Программы» и откройте его оттуда."
        )
    }

    /// The alert's text when macOS opened a quarantined copy from a temporary read-only location (App Translocation).
    public var runningTranslocated: String {
        l.pick(
            en: "macOS is running Codometer from a temporary copy. Drag Codometer to your Applications folder and open it from there.",
            ru: "macOS запустил Codometer из временной копии. Перетащите Codometer в папку «Программы» и откройте его оттуда."
        )
    }

    /// The alert's text when the bundle sits on any other read-only volume.
    public var runningFromReadOnlyVolume: String {
        l.pick(
            en: "Codometer is on a read-only volume. Drag Codometer to your Applications folder and open it from there.",
            ru: "Codometer находится на томе только для чтения. Перетащите Codometer в папку «Программы» и откройте его оттуда."
        )
    }

    /// The second paragraph of that alert: why an installed copy matters. Nothing has been written at this point.
    public var installedCopyNeeded: String {
        l.pick(
            en: "Widgets, notifications and “Open at login” only work from an installed copy. Nothing has been saved.",
            ru: "Виджеты, уведомления и «Открывать при входе в систему» работают только у установленной копии. Ничего не сохранено."
        )
    }

    // MARK: About

    /// Under the app name in the About panel. Says what the app is, in one line.
    public var aboutCredits: String {
        l.pick(
            en: "Keeps an eye on your Claude Code and Codex limits, right in the menu bar.",
            ru: "Следит за лимитами Claude Code и Codex прямо в строке меню."
        )
    }
}

extension Localizer {
    public var lifecycle: LifecycleStrings { LifecycleStrings(l: self) }
}
