import Foundation

/// Checks every `pick`, `plural` and `slot` phrase in `Sources/CodometerL10n/**`: both languages present and readable,
/// no empty forms, the same interpolations in every form, and each language's typography.
enum PhraseLint {
    enum Kind: String {
        case pick, plural, slot
    }

    /// One parsed phrase: its forms per language (a slot's prefix and suffix are two forms).
    struct Phrase {
        let kind: Kind
        let line: Int
        let english: [StringLiteral]
        let russian: [StringLiteral]
    }

    struct Result {
        var phrases: [Phrase] = []
        var problems: [String] = []
    }

    static func check(_ file: SourceFile) -> Result {
        var result = Result()
        for kind in [Kind.pick, .plural, .slot] {
            for offset in callOffsets(of: kind, in: file) {
                let line = file.lineNumber(of: offset)
                var parser = CallParser(file: file, index: offset)
                guard let phrase = parser.parse(kind, line: line) else {
                    result.problems.append("\(file.path):\(line): a `\(kind.rawValue)(…)` the lint cannot read; write every form as one plain string literal")
                    continue
                }
                result.phrases.append(phrase)
                result.problems += problems(in: phrase, path: file.path)
            }
        }
        return result
    }

    /// Offsets just past the `(` of every `.kind(` call in code.
    static func callOffsets(of kind: Kind, in file: SourceFile) -> [Int] {
        let needle = Array(".\(kind.rawValue)(".unicodeScalars)
        var offsets: [Int] = []
        var i = 0
        while i + needle.count <= file.scalars.count {
            if file.scalars[i] == "." && Array(file.scalars[i..<(i + needle.count)]) == needle,
               !file.isComment[i], !file.isInsideLiteral(i) {
                offsets.append(i + needle.count)
                i += needle.count
            } else {
                i += 1
            }
        }
        return offsets
    }

    static func problems(in phrase: Phrase, path: String) -> [String] {
        var problems: [String] = []
        let place = "\(path):\(phrase.line)"
        let forms = phrase.english + phrase.russian

        // Empty forms and edge spaces (slots may be empty on one side and end in a space before the live text).
        if phrase.kind == .slot {
            if phrase.english.map(\.visibleText).joined().trimmingCharacters(in: .whitespaces).isEmpty
                || phrase.russian.map(\.visibleText).joined().trimmingCharacters(in: .whitespaces).isEmpty {
                problems.append("\(place): a slot needs text in both languages")
            }
        } else {
            for form in forms {
                let text = form.visibleText
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && form.interpolations.isEmpty {
                    problems.append("\(place): an empty form")
                } else if let first = form.rawContent.unicodeScalars.first, let last = form.rawContent.unicodeScalars.last,
                          SourceLint.isWhitespace(first) || SourceLint.isWhitespace(last) {
                    problems.append("\(place): \"\(form.rawContent)\" starts or ends with a space; use a slot instead of glued fragments")
                }
            }
        }
        for form in forms where form.rawContent.contains("  ") {
            problems.append("\(place): \"\(form.rawContent)\" has a double space")
        }

        // The same interpolations in every form.
        let expected = phrase.kind == .slot
            ? phrase.english.flatMap(\.interpolations).sorted()
            : (forms.first?.interpolations.sorted() ?? [])
        let groups: [[StringLiteral]] = phrase.kind == .slot ? [phrase.english, phrase.russian] : forms.map { [$0] }
        for group in groups where group.flatMap(\.interpolations).sorted() != expected {
            problems.append("\(place): \"\(group.map(\.rawContent).joined(separator: "|"))\" interpolates \(group.flatMap(\.interpolations).sorted()), expected \(expected)")
        }

        // English typography.
        for form in phrase.english {
            let text = form.visibleText
            if SourceLint.containsCyrillic(text) { problems.append("\(place): Cyrillic in English \"\(text)\"") }
            if text.contains("«") || text.contains("»") { problems.append("\(place): «» in English \"\(text)\"; use “ ”") }
            if text.contains("\"") { problems.append("\(place): ASCII quotes in English \"\(text)\"; use “ ”") }
            if text.contains("'") { problems.append("\(place): ASCII apostrophe in English \"\(text)\"; use ’") }
            if text.contains("...") { problems.append("\(place): \"...\" in \"\(text)\"; use …") }
        }

        // Russian typography.
        let englishTexts = Set(phrase.english.map(\.visibleText))
        for form in phrase.russian {
            let text = form.visibleText
            if text.contains("\"") { problems.append("\(place): ASCII quotes in Russian \"\(text)\"; use «»") }
            if text.contains("...") { problems.append("\(place): \"...\" in \"\(text)\"; use …") }
            if text.firstMatch(of: /[\p{Ll},;:—–]\s+(Вы|Вас|Вам|Вами|Ваш\p{L}*)\b/) != nil {
                problems.append("\(place): capitalised «Вы» inside a sentence in \"\(text)\"")
            }
            if SourceLint.containsLetters(text), !SourceLint.containsCyrillic(text) {
                let isBrand = englishTexts.contains(text)
                    && SourceLint.brandNames.contains(text.trimmingCharacters(in: .whitespacesAndNewlines))
                if !isBrand {
                    problems.append("\(place): Russian \"\(text)\" has no Cyrillic")
                }
            }
        }
        return problems
    }
}

/// Reads the arguments of one phrase call from just past its `(`.
private struct CallParser {
    let file: SourceFile
    var index: Int

    mutating func parse(_ kind: PhraseLint.Kind, line: Int) -> PhraseLint.Phrase? {
        switch kind {
        case .pick:
            guard label("en"), let en = literal(), comma(), label("ru"), let ru = literal(), close() else { return nil }
            return PhraseLint.Phrase(kind: kind, line: line, english: [en], russian: [ru])
        case .plural:
            guard skipExpression(), comma(), label("en"), let en = tuple(count: 2), comma(),
                  label("ru"), let ru = tuple(count: 3), close() else { return nil }
            return PhraseLint.Phrase(kind: kind, line: line, english: en, russian: ru)
        case .slot:
            guard label("en"), let en = tuple(count: 2), comma(), label("ru"), let ru = tuple(count: 2), close() else { return nil }
            return PhraseLint.Phrase(kind: kind, line: line, english: en, russian: ru)
        }
    }

    private mutating func skipSpace() {
        while index < file.scalars.count, SourceLint.isWhitespace(file.scalars[index]) || file.isComment[index] {
            index += 1
        }
    }

    private mutating func consume(_ text: String) -> Bool {
        skipSpace()
        let scalars = Array(text.unicodeScalars)
        guard index + scalars.count <= file.scalars.count, Array(file.scalars[index..<(index + scalars.count)]) == scalars else {
            return false
        }
        index += scalars.count
        return true
    }

    private mutating func label(_ name: String) -> Bool {
        consume(name) && consume(":")
    }

    private mutating func comma() -> Bool { consume(",") }
    private mutating func close() -> Bool { consume(")") }

    private mutating func literal() -> StringLiteral? {
        skipSpace()
        guard let literal = file.literal(startingAt: index), !literal.isMultiline else { return nil }
        index = literal.end
        return literal
    }

    /// `(a, b)` or `(one: a, other: b)`.
    private mutating func tuple(count: Int) -> [StringLiteral]? {
        guard consume("(") else { return nil }
        var items: [StringLiteral] = []
        for position in 0..<count {
            if position > 0, !comma() { return nil }
            skipSpace()
            // An optional element label.
            var probe = index
            while probe < file.scalars.count, file.scalars[probe].properties.isAlphabetic { probe += 1 }
            if probe > index, probe < file.scalars.count, file.scalars[probe] == ":" {
                index = probe + 1
            }
            guard let item = literal() else { return nil }
            items.append(item)
        }
        return close() ? items : nil
    }

    /// Skips the count expression up to the top-level comma.
    private mutating func skipExpression() -> Bool {
        skipSpace()
        var depth = 0
        let start = index
        while index < file.scalars.count {
            if let literal = file.literal(startingAt: index) {
                index = literal.end
                continue
            }
            let scalar = file.scalars[index]
            if scalar == "(" || scalar == "[" { depth += 1 }
            if scalar == ")" || scalar == "]" {
                if depth == 0 { return false }
                depth -= 1
            }
            if scalar == ",", depth == 0 { return index > start }
            index += 1
        }
        return false
    }
}
