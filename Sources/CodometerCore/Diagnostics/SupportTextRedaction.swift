import Foundation

/// Removes personal details from support text (the Diagnostics report and exported diagnostics).
///
/// In order:
/// 1. account ids become the account's label (names included) or "Account N" (names excluded), and labels become
///    "Account N" when names are excluded; labels made only of provider names ("Claude", "Codex") are not personal
///    and stay;
/// 2. e-mail addresses become `<email>`, and any other `@` becomes `(at)`;
/// 3. absolute home paths (the given home folder, any `/Users/<name>`) become `~`;
/// 4. in `~/…` paths, folders that are neither dot folders nor standard macOS folders collapse to `…`, and so does a
///    last component that is not a dot name, a file name with an extension, or a provider CLI name (project and
///    client folder names never survive);
/// 5. any remaining UUID (session ids) becomes `<id>`.
///
/// Accounts are numbered by first mention across all texts, then by id, so the output is stable.
public struct SupportTextRedaction: Sendable {
    /// Home-relative folders that say nothing personal and help support.
    static let standardFolders: Set<String> = [
        "Library", "Application Support", "Caches", "Containers", "Group Containers", "Logs", "Preferences",
        "Applications", "Downloads", "Desktop", "Documents", "bin", "lib", "share", "node_modules",
        "Codometer", "Widget", "Diagnostics", "probe",
    ]
    /// Last path components kept although they have no extension.
    static let executableNames: Set<String> = ["claude", "codex"]

    public let homeDirectory: String?
    public let labels: [AccountID: String]
    public let includeAccountNames: Bool

    public init(homeDirectory: String?, labels: [AccountID: String], includeAccountNames: Bool) {
        self.homeDirectory = homeDirectory
        self.labels = labels
        self.includeAccountNames = includeAccountNames
    }

    public func apply(to text: String) -> String {
        apply(to: [text]).first ?? ""
    }

    /// Redacts several texts with one account numbering.
    public func apply(to texts: [String]) -> [String] {
        let numbers = accountNumbers(in: texts.joined(separator: "\n"))
        return texts.map { text in
            var result = replacingAccounts(in: text, numbers: numbers)
            result = Self.replacingEmails(in: result)
            result = Self.abbreviatingHome(in: result, homeDirectory: homeDirectory)
            result = Self.collapsingHomeFolders(in: result)
            return Self.replacingUUIDs(in: result)
        }
    }

    /// Replaces the home folder and any `/Users/<name>` prefix with `~`.
    public static func abbreviatingHome(in text: String, homeDirectory: String?) -> String {
        var result = text
        if let home = homeDirectory?.trimmingCharacters(in: CharacterSet(charactersIn: "/")), !home.isEmpty,
           let pattern = try? Regex("/" + NSRegularExpression.escapedPattern(for: home) + #"(?=[/\s:;,"')\]]|$)"#) {
            // Only the whole folder: "/Users/jane" never rewrites "/Users/janet".
            result = result.replacing(pattern, with: "~")
        }
        return result.replacing(/\/Users\/[^\/\s:;,"')\]]+/, with: "~")
    }

    // MARK: - Accounts

    /// Labels worth hiding: non-empty and not made only of provider names.
    private var personalLabels: [AccountID: String] {
        labels.filter { _, label in
            let words = label.lowercased().split { !$0.isLetter && !$0.isNumber }
            return !words.isEmpty && !words.allSatisfy { ["claude", "codex", "code"].contains($0) }
        }
    }

    private func accountNumbers(in corpus: String) -> [AccountID: Int] {
        let personal = personalLabels
        let firstMentions = labels.keys.map { id -> (id: AccountID, at: String.Index?) in
            let byID = corpus.range(of: id.description, options: .caseInsensitive)?.lowerBound
            let byLabel = personal[id].flatMap { corpus.range(of: $0)?.lowerBound }
            return (id, [byID, byLabel].compactMap { $0 }.min())
        }
        let ordered = firstMentions.sorted { lhs, rhs in
            switch (lhs.at, rhs.at) {
            case let (left?, right?) where left != right: left < right
            case (.some, nil): true
            case (nil, .some): false
            default: lhs.id.description < rhs.id.description
            }
        }
        var numbers: [AccountID: Int] = [:]
        for (index, entry) in ordered.enumerated() {
            numbers[entry.id] = index + 1
        }
        return numbers
    }

    /// Ids and labels are first swapped for control-character tokens (labels never contain control characters), so a
    /// label such as "Account" cannot rewrite a placeholder inserted for another account.
    private func replacingAccounts(in text: String, numbers: [AccountID: Int]) -> String {
        var result = text
        var replacements: [(token: String, text: String)] = []
        for id in labels.keys.sorted(by: { $0.description < $1.description }) {
            let number = numbers[id] ?? 0
            let token = "\u{1}\(number)\u{1}"
            let placeholder = "Account \(number)"
            let name = includeAccountNames ? (labels[id].flatMap { DisplayText.sanitize($0, maximumLength: 60) } ?? placeholder) : placeholder
            result = result.replacingOccurrences(of: id.description, with: token, options: .caseInsensitive)
            replacements.append((token, name))
        }
        if !includeAccountNames {
            let personal = personalLabels
            // Longer labels first, so "Work" never breaks "Work laptop".
            let ordered = personal.sorted { lhs, rhs in
                lhs.value.count == rhs.value.count ? lhs.key.description < rhs.key.description : lhs.value.count > rhs.value.count
            }
            for (id, label) in ordered {
                result = result.replacingOccurrences(of: label, with: "\u{1}\(numbers[id] ?? 0)\u{1}")
            }
        }
        for replacement in replacements {
            result = result.replacingOccurrences(of: replacement.token, with: replacement.text)
        }
        // Any token left (an account missing from the numbering) must not leak control characters.
        return result.replacingOccurrences(of: "\u{1}", with: "")
    }

    // MARK: - Text patterns

    private static func replacingEmails(in text: String) -> String {
        text.replacing(/[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(\.[A-Za-z0-9\-]+)*/, with: "<email>")
            .replacingOccurrences(of: "@", with: "(at)")
    }

    private static func collapsingHomeFolders(in text: String) -> String {
        // Folders before a "/" may contain single spaces ("Application Support", "Client Work"), except before a "~"
        // that starts another path; the last component ends at the first space. Over-collapsing prose that happens to
        // contain a "/" is preferred to leaking folder names.
        text.replacing(/~\/(?:[^\s\/:;,"')\]]+(?: (?!~)[^\s\/:;,"')\]]+)*\/)*[^\s\/:;,"')\]]*/) { match in
            let components = match.output.dropFirst(2).split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            var kept: [String] = []
            for (index, name) in components.enumerated() {
                let isLast = index == components.count - 1
                let keeps = name.isEmpty
                    || name.hasPrefix(".")
                    || standardFolders.contains(name)
                    || (isLast && (name.contains(".") || executableNames.contains(name)))
                if keeps {
                    kept.append(name)
                } else if kept.last != "…" {
                    kept.append("…")
                }
            }
            return "~/" + kept.joined(separator: "/")
        }
    }

    private static func replacingUUIDs(in text: String) -> String {
        text.replacing(/[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/, with: "<id>")
    }
}
