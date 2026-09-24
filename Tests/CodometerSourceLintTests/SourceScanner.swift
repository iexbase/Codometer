import Foundation

/// A Swift source file split into code, comments and string literals, for the policy lints.
///
/// The lexer knows line and block comments (nested), single-line, multi-line and raw string literals, escapes and
/// interpolations (which may contain strings and comments of their own). It does not parse Swift: the lints look at
/// the code around a literal, which is enough for the patterns they check.
struct SourceFile {
    /// The path relative to the package root, e.g. `Sources/CodometerUI/Deck/DeckLayout.swift`.
    let path: String
    let scalars: [Unicode.Scalar]
    /// `true` for every scalar inside a comment (including the comment markers).
    let isComment: [Bool]
    /// Every string literal, in source order; literals inside interpolations come after their outer literal.
    let literals: [StringLiteral]
    /// Scalar offset of the first scalar of each line; line `n` (1-based) starts at `lineStarts[n - 1]`.
    let lineStarts: [Int]
    private let literalsByStart: [Int: StringLiteral]

    init(path: String, text: String) {
        self.path = path
        let scalars = Array(text.unicodeScalars)
        self.scalars = scalars
        var lexer = Lexer(scalars: scalars)
        lexer.lexCode(from: 0, closingParenthesis: false)
        isComment = lexer.isComment
        literals = lexer.literals.sorted { $0.start < $1.start }
        literalsByStart = Dictionary(lexer.literals.map { ($0.start, $0) }, uniquingKeysWith: { first, _ in first })
        var starts = [0]
        for (index, scalar) in scalars.enumerated() where scalar == "\n" {
            starts.append(index + 1)
        }
        lineStarts = starts
    }

    var lines: [String] {
        (0..<lineStarts.count).map(line)
    }

    /// The text of a 0-based line, without its newline.
    func line(_ index: Int) -> String {
        let start = lineStarts[index]
        let end = index + 1 < lineStarts.count ? lineStarts[index + 1] - 1 : scalars.count
        return String(String.UnicodeScalarView(scalars[start..<max(start, end)]))
    }

    /// The 1-based line of a scalar offset.
    func lineNumber(of offset: Int) -> Int {
        var low = 0
        var high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= offset { low = mid } else { high = mid - 1 }
        }
        return low + 1
    }

    /// The 0-based line's scalars that are not part of a comment.
    func code(ofLine index: Int) -> String {
        let start = lineStarts[index]
        let end = index + 1 < lineStarts.count ? lineStarts[index + 1] - 1 : scalars.count
        var view = String.UnicodeScalarView()
        for offset in start..<max(start, end) where !isComment[offset] {
            view.append(scalars[offset])
        }
        return String(view)
    }

    /// The reason of a trailing `// l10n-ignore: <reason>` comment on the 0-based line, if any.
    func ignoreReason(ofLine index: Int) -> String? {
        let text = line(index)
        guard let range = text.range(of: "// l10n-ignore:", options: .backwards) else { return nil }
        let offset = lineStarts[index] + text.unicodeScalars.distance(from: text.unicodeScalars.startIndex, to: range.lowerBound)
        guard offset < isComment.count, isComment[offset] else { return nil }
        let reason = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
        return reason.isEmpty ? nil : reason
    }

    /// Whether the first line is exactly the pending marker.
    var hasPendingMarker: Bool {
        line(0).trimmingCharacters(in: .whitespaces) == SourceLint.pendingMarker
    }

    /// The literal whose opening delimiter (or leading `#`) starts at `offset`.
    func literal(startingAt offset: Int) -> StringLiteral? {
        literalsByStart[offset]
    }

    /// Whether `offset` lies inside a string literal's delimiters (interpolations included).
    func isInsideLiteral(_ offset: Int) -> Bool {
        literals.contains { $0.start <= offset && offset < $0.end }
    }
}

/// One string literal.
struct StringLiteral: Equatable {
    /// Offset of the first `#` or opening quote.
    let start: Int
    /// Offset just past the closing delimiter.
    let end: Int
    /// The source between the delimiters, escapes and interpolations as written.
    let rawContent: String
    /// What the literal shows apart from its interpolations: escapes decoded, interpolations removed.
    let visibleText: String
    /// The source of each interpolation, trimmed, in order.
    let interpolations: [String]
    let isMultiline: Bool
}

private struct Lexer {
    let scalars: [Unicode.Scalar]
    var isComment: [Bool]
    var literals: [StringLiteral] = []

    init(scalars: [Unicode.Scalar]) {
        self.scalars = scalars
        isComment = Array(repeating: false, count: scalars.count)
    }

    private func at(_ index: Int) -> Unicode.Scalar? {
        index < scalars.count ? scalars[index] : nil
    }

    private func matches(_ text: String, at index: Int) -> Bool {
        var offset = index
        for scalar in text.unicodeScalars {
            guard at(offset) == scalar else { return false }
            offset += 1
        }
        return true
    }

    /// Lexes code from `index`; with `closingParenthesis`, stops after the `)` that closes an interpolation and
    /// returns the offset past it. Otherwise runs to the end.
    @discardableResult
    mutating func lexCode(from index: Int, closingParenthesis: Bool) -> Int {
        var i = index
        var depth = 0
        while i < scalars.count {
            let scalar = scalars[i]
            if matches("//", at: i) {
                while i < scalars.count, scalars[i] != "\n" {
                    isComment[i] = true
                    i += 1
                }
                continue
            }
            if matches("/*", at: i) {
                i = lexBlockComment(from: i)
                continue
            }
            if scalar == "#" || scalar == "\"" {
                var hashes = 0
                while at(i + hashes) == "#" { hashes += 1 }
                if at(i + hashes) == "\"" {
                    i = lexString(from: i, hashes: hashes)
                    continue
                }
            }
            if scalar == "/", isRegexStart(at: i) {
                i = skipRegex(from: i)
                continue
            }
            if closingParenthesis {
                if scalar == "(" {
                    depth += 1
                } else if scalar == ")" {
                    if depth == 0 { return i + 1 }
                    depth -= 1
                }
            }
            i += 1
        }
        return i
    }

    /// A bare regex literal (`/…/`) directly after `=`, `(`, `,` or `:`: its contents are neither code nor comment.
    private func isRegexStart(at index: Int) -> Bool {
        guard let next = at(index + 1), next != " ", next != "/", next != "*", next != "\n", next != "=" else { return false }
        var j = index - 1
        while j >= 0, scalars[j] == " " { j -= 1 }
        guard j >= 0 else { return false }
        return ["=", "(", ",", ":"].contains(scalars[j])
    }

    private func skipRegex(from index: Int) -> Int {
        var i = index + 1
        while i < scalars.count, scalars[i] != "\n" {
            if scalars[i] == "\\" {
                i += 2
                continue
            }
            if scalars[i] == "/" { return i + 1 }
            i += 1
        }
        return i
    }

    private mutating func lexBlockComment(from index: Int) -> Int {
        var i = index
        var depth = 0
        while i < scalars.count {
            if matches("/*", at: i) {
                depth += 1
                isComment[i] = true
                isComment[i + 1] = true
                i += 2
                continue
            }
            if matches("*/", at: i) {
                depth -= 1
                isComment[i] = true
                isComment[i + 1] = true
                i += 2
                if depth == 0 { return i }
                continue
            }
            isComment[i] = true
            i += 1
        }
        return i
    }

    /// Lexes the literal whose `#`s or opening quote start at `index`; returns the offset past it.
    private mutating func lexString(from index: Int, hashes: Int) -> Int {
        let hashText = String(repeating: "#", count: hashes)
        let quoteStart = index + hashes
        let isMultiline = matches("\"\"\"", at: quoteStart)
        var i = quoteStart + (isMultiline ? 3 : 1)
        let closing = (isMultiline ? "\"\"\"" : "\"") + hashText
        let escape = "\\" + hashText
        var raw = String.UnicodeScalarView()
        var visible = String.UnicodeScalarView()
        var interpolations: [String] = []
        let contentStart = i
        while i < scalars.count {
            if matches(closing, at: i) {
                raw = String.UnicodeScalarView(scalars[contentStart..<i])
                let end = i + closing.unicodeScalars.count
                literals.append(StringLiteral(
                    start: index,
                    end: end,
                    rawContent: String(raw),
                    visibleText: String(visible),
                    interpolations: interpolations,
                    isMultiline: isMultiline
                ))
                return end
            }
            if !isMultiline, scalars[i] == "\n" {
                break
            }
            if matches(escape, at: i) {
                let next = i + escape.unicodeScalars.count
                guard let kind = at(next) else { break }
                switch kind {
                case "(":
                    let end = lexCode(from: next + 1, closingParenthesis: true)
                    let expression = String(String.UnicodeScalarView(scalars[(next + 1)..<max(next + 1, end - 1)]))
                    interpolations.append(expression.trimmingCharacters(in: .whitespacesAndNewlines))
                    i = end
                case "u":
                    var j = next + 1
                    var hex = ""
                    if at(j) == "{" {
                        j += 1
                        while let digit = at(j), digit != "}" {
                            hex.unicodeScalars.append(digit)
                            j += 1
                        }
                        j += 1
                    }
                    if let value = UInt32(hex, radix: 16), let decoded = Unicode.Scalar(value) {
                        visible.append(decoded)
                    }
                    i = j
                case "n", "r", "t":
                    visible.append(" ")
                    i = next + 1
                case "0":
                    i = next + 1
                default:
                    visible.append(kind)
                    i = next + 1
                }
                continue
            }
            visible.append(scalars[i])
            i += 1
        }
        // Unterminated: record what there is, so the lints still see it.
        literals.append(StringLiteral(
            start: index,
            end: i,
            rawContent: String(String.UnicodeScalarView(scalars[contentStart..<min(i, scalars.count)])),
            visibleText: String(visible),
            interpolations: interpolations,
            isMultiline: isMultiline
        ))
        return i
    }
}

/// Shared rules and the files the lints read.
enum SourceLint {
    static let pendingMarker = "// l10n: pending"
    /// Brand and product names that appear as they are in every language.
    static let brandNames: Set<String> = ["Codometer", "Claude", "Claude Code", "Codex", "Liquid Glass"]

    /// The package root, found from this file's path.
    static let packageRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// Every `.swift` file under `Sources/`, sorted by path.
    static func sourceFiles(under relativeDirectory: String = "Sources") throws -> [SourceFile] {
        let directory = packageRoot.appendingPathComponent(relativeDirectory, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }
        var files: [SourceFile] = []
        let rootPath = packageRoot.standardizedFileURL.path + "/"
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            let path = url.standardizedFileURL.path.replacingOccurrences(of: rootPath, with: "")
            files.append(SourceFile(path: path, text: text))
        }
        return files.sorted { $0.path < $1.path }
    }

    static func containsCyrillic(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
    }

    static func containsLetters(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.properties.isAlphabetic }
    }

    static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isWhitespace
    }
}
