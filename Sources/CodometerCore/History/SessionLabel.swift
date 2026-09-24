import Foundation

/// Names for sessions that never use the session's own title.
///
/// Claude Code names desktop and automatically named sessions after the conversation, so a session title can carry
/// conversation content. Everything that outlives the running app — history rows, the timeline built from them,
/// attribution and notifications (which macOS keeps in its own database) — names a session by its project folder
/// and the end of its id instead. Only the live deck shows a session's own title, from memory.
///
/// History and the engine keep only the language-neutral machine form (`neutral`); views and notifications render
/// `SessionLabelParts` in the interface language.
public enum SessionLabel {
    public static let maximumFolderLength = 80
    /// Characters of the session id shown after the folder: random for both providers' ids.
    public static let idSuffixLength = 6

    /// The last path component of a project path, sanitised; `nil` without a usable one.
    ///
    /// Taken before the length cap, so a long path never turns into a truncated tail.
    public static func folder(of project: String?) -> String? {
        guard let path = DisplayText.sanitize(project, maximumLength: .max) else { return nil }
        let component = (path as NSString).lastPathComponent
        guard component != "/" else { return nil }
        return DisplayText.sanitize(component, maximumLength: maximumFolderLength)
    }

    /// The parts a session's label is made of. `projectFolder` may be a full project path or just its folder.
    public static func parts(sessionID: String, projectFolder: String?) -> SessionLabelParts {
        SessionLabelParts(folder: folder(of: projectFolder), idSuffix: idSuffix(sessionID))
    }

    /// The machine form stored in history: «Codometer · 3f9a1c», or only «3f9a1c» without a project.
    public static func neutral(sessionID: String, project: String?) -> String {
        parts(sessionID: sessionID, projectFolder: project).machineForm
    }

    private static func idSuffix(_ sessionID: String) -> String {
        DisplayText.sanitize(String(sessionID.suffix(idSuffixLength)), maximumLength: idSuffixLength + 1) ?? "—"
    }
}

/// A session's label before it is put into words: its project folder, if any, and the end of its id.
public struct SessionLabelParts: Hashable, Sendable {
    /// Sanitised, at most `SessionLabel.maximumFolderLength` characters.
    public let folder: String?
    public let idSuffix: String

    public init(folder: String?, idSuffix: String) {
        self.folder = folder
        self.idSuffix = idSuffix
    }

    /// «Codometer · 3f9a1c», or «3f9a1c» without a project: no words, so it reads the same in every language.
    public var machineForm: String {
        folder.map { "\($0) · \(idSuffix)" } ?? idSuffix
    }
}
