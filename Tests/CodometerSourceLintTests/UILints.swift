import Foundation

/// Cyrillic outside `Sources/CodometerL10n` is allowed only in comments, in a file whose first line is
/// `// l10n: pending`, or on a line ending with `// l10n-ignore: <reason>`. A pending marker on a file that no longer
/// needs it is an error too, so conversions always delete it.
enum CyrillicRatchet {
    static func appliesTo(_ path: String) -> Bool {
        path.hasPrefix("Sources/") && !path.hasPrefix("Sources/CodometerL10n/")
    }

    /// 1-based lines with Cyrillic in code or string literals and no ignore marker.
    static func unmarkedLines(in file: SourceFile) -> [Int] {
        (0..<file.lineStarts.count).compactMap { index in
            guard SourceLint.containsCyrillic(file.code(ofLine: index)), file.ignoreReason(ofLine: index) == nil else { return nil }
            return index + 1
        }
    }

    static func problems(in file: SourceFile) -> [String] {
        guard appliesTo(file.path) else { return [] }
        let lines = unmarkedLines(in: file)
        if file.hasPendingMarker {
            return lines.isEmpty ? ["\(file.path): no Cyrillic left; delete the `\(SourceLint.pendingMarker)` marker"] : []
        }
        return lines.map { "\(file.path):\($0): Cyrillic outside CodometerL10n; move the text into a phrase" }
    }
}

/// No string literal with letters goes straight into a UI text API: SwiftUI views and modifiers, AppKit menu items,
/// tooltips, alerts and panels. Catches the English literals the Cyrillic ratchet cannot see.
enum LiteralUIAPI {
    /// Initialisers whose first unlabelled argument is shown text (`Text(verbatim:)` is exempt by its label).
    static let initializers: Set<String> = [
        "Text", "Button", "Toggle", "Label", "Section", "Picker", "LabeledContent", "TextField", "Menu", "ActionMenuItem",
    ]
    /// Modifiers whose first argument is shown or spoken text.
    static let modifiers: Set<String> = [
        "help", "accessibilityLabel", "accessibilityValue", "accessibilityHint", "navigationTitle",
    ]
    /// Properties whose assigned value is shown text.
    static let properties: Set<String> = ["toolTip", "messageText", "informativeText", "prompt", "title"]

    static func appliesTo(_ file: SourceFile) -> Bool {
        file.path.hasPrefix("Sources/")
            && !file.path.hasPrefix("Sources/CodometerL10n/")
            && !file.path.hasPrefix("Sources/CodometerApp/Debug/")
            && !file.hasPendingMarker
    }

    static func problems(in file: SourceFile) -> [String] {
        guard appliesTo(file) else { return [] }
        var problems: [String] = []
        for literal in file.literals {
            guard let api = api(before: literal.start, in: file) else { continue }
            let text = literal.visibleText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard SourceLint.containsLetters(text), !SourceLint.brandNames.contains(text) else { continue }
            let line = file.lineNumber(of: literal.start)
            guard file.ignoreReason(ofLine: line - 1) == nil else { continue }
            problems.append("\(file.path):\(line): literal \"\(literal.rawContent)\" passed to \(api); use a phrase from CodometerL10n")
        }
        return problems
    }

    /// The UI API a literal starting at `offset` is passed to, if any.
    static func api(before offset: Int, in file: SourceFile) -> String? {
        var i = offset - 1
        skipBackSpace(&i, in: file)
        guard i >= 0 else { return nil }
        switch file.scalars[i] {
        case "(":
            i -= 1
            let name = identifier(endingAt: &i, in: file)
            guard !name.isEmpty else { return nil }
            let isMember = i >= 0 && file.scalars[i] == "."
            if isMember, modifiers.contains(name) { return ".\(name)(" }
            if !isMember, initializers.contains(name) { return "\(name)(" }
            return nil
        case ":":
            // `NSMenuItem(title: "…"`
            i -= 1
            let label = identifier(endingAt: &i, in: file)
            guard label == "title" else { return nil }
            skipBackSpace(&i, in: file)
            guard i >= 0, file.scalars[i] == "(" else { return nil }
            i -= 1
            return identifier(endingAt: &i, in: file) == "NSMenuItem" ? "NSMenuItem(title:" : nil
        case "=":
            guard i >= 1, !["=", "!", "<", ">", "+", "-", "*", "/"].contains(file.scalars[i - 1]) else { return nil }
            i -= 1
            skipBackSpace(&i, in: file)
            let name = identifier(endingAt: &i, in: file)
            guard properties.contains(name), i >= 0, file.scalars[i] == "." else { return nil }
            return ".\(name) ="
        default:
            return nil
        }
    }

    private static func skipBackSpace(_ i: inout Int, in file: SourceFile) {
        while i >= 0, SourceLint.isWhitespace(file.scalars[i]) || file.isComment[i] {
            i -= 1
        }
    }

    /// The identifier ending at `i`, moving `i` to the scalar before it.
    private static func identifier(endingAt i: inout Int, in file: SourceFile) -> String {
        skipBackSpace(&i, in: file)
        var view = String.UnicodeScalarView()
        while i >= 0, file.scalars[i].properties.isAlphabetic || file.scalars[i] == "_" || ("0"..."9").contains(file.scalars[i]) {
            view.append(file.scalars[i])
            i -= 1
        }
        return String(String.UnicodeScalarView(view.reversed()))
    }
}
