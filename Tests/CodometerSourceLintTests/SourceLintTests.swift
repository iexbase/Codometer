import Foundation
import Testing

/// The localization lints over the real sources. Each failure names the file and line to fix.
@Suite("Source lints")
struct SourceLintTests {
    @Test("PhraseLint: every phrase has both languages, readable, with matching interpolations")
    func phrases() throws {
        let files = try SourceLint.sourceFiles(under: "Sources/CodometerL10n")
        #expect(!files.isEmpty)
        var count = 0
        for file in files {
            let result = PhraseLint.check(file)
            count += result.phrases.count
            for problem in result.problems {
                Issue.record(Comment(rawValue: problem))
            }
        }
        #expect(count > 100, "the lint read too few phrases: \(count)")
    }

    @Test("CyrillicRatchet: Cyrillic outside CodometerL10n only with a pending or ignore marker")
    func cyrillic() throws {
        let files = try SourceLint.sourceFiles()
        #expect(files.count > 100)
        for file in files {
            for problem in CyrillicRatchet.problems(in: file) {
                Issue.record(Comment(rawValue: problem))
            }
        }
    }

    @Test("LiteralUIAPI: no literal text passed to SwiftUI or AppKit text APIs")
    func literalUIAPI() throws {
        for file in try SourceLint.sourceFiles() {
            for problem in LiteralUIAPI.problems(in: file) {
                Issue.record(Comment(rawValue: problem))
            }
        }
    }
}

/// The lints themselves, on small sources written here.
@Suite("Source lint rules")
struct SourceLintRuleTests {
    @Test("The lexer separates comments, literals, escapes and interpolations")
    func lexer() throws {
        let source = #"""
        let a = "x \(f("y")) \u{00A0}z" // comment «ё»
        /* block /* nested */ "not a literal" */
        let b = #"raw \(no) "quoted""#
        let r = /a"b/
        let c = """
            multi «»
            """
        """#
        let file = SourceFile(path: "Sources/X/A.swift", text: source)
        #expect(file.literals.count == 4)
        let first = try #require(file.literals.first)
        #expect(first.interpolations == [#"f("y")"#])
        #expect(first.visibleText == "x  \u{00A0}z")
        #expect(file.literals[1].visibleText == "y")
        #expect(file.literals[2].visibleText == #"raw \(no) "quoted""#)
        #expect(file.literals[3].isMultiline)
        #expect(!SourceLint.containsCyrillic(file.code(ofLine: 0)))
        #expect(!file.code(ofLine: 1).contains("not a literal"))
    }

    @Test("PhraseLint reads every call shape and reports each broken rule")
    func phraseLint() {
        let good = #"""
        var a: String { l.pick(en: "Resets in \(time)", ru: "сброс через \(time)") }
        func b(_ n: Int) -> String {
            l.plural(n,
                     en: (one: "\(n) agent", other: "\(n) agents"),
                     ru: ("\(n) агент", "\(n) агента", "\(n) агентов"))
        }
        var c: (prefix: String, suffix: String) { l.slot(en: ("Resets in ", ""), ru: ("", " до сброса")) }
        var d: String { l.pick(en: "Claude Code", ru: "Claude Code") }
        var e: String { l.pick(en: "\(a) \(b)", ru: "\(a), \(b)") }
        // l.pick(en: "ignored", ru: "comment")
        """#
        let clean = PhraseLint.check(SourceFile(path: "Sources/CodometerL10n/Strings/Good.swift", text: good))
        #expect(clean.phrases.count == 5)
        #expect(clean.problems.isEmpty, "\(clean.problems)")

        let bad = #"""
        var a: String { l.pick(en: "Resets in \(time)", ru: "сброс через \(other)") }
        var b: String { l.pick(en: "Не английский", ru: "русский") }
        var c: String { l.pick(en: "It's \"here\"...", ru: "тут...") }
        var d: String { l.pick(en: "Settings", ru: "Settings") }
        var e: String { l.pick(en: " padded", ru: "") }
        var f: String { l.pick(en: text, ru: "текст") }
        var g: String { l.pick(en: "Waiting for you", ru: "Ждут Вас") }
        """#
        let result = PhraseLint.check(SourceFile(path: "Sources/CodometerL10n/Strings/Bad.swift", text: bad))
        let joined = result.problems.joined(separator: "\n")
        #expect(joined.contains("Bad.swift:1:") && joined.contains("interpolates"))
        #expect(joined.contains("Bad.swift:2: Cyrillic in English"))
        #expect(joined.contains("Bad.swift:3: ASCII quotes in English"))
        #expect(joined.contains("Bad.swift:3: ASCII apostrophe"))
        #expect(joined.contains("Bad.swift:3: \"...\""))
        #expect(joined.contains("Bad.swift:4: Russian \"Settings\" has no Cyrillic"))
        #expect(joined.contains("Bad.swift:5: an empty form"))
        #expect(joined.contains("Bad.swift:5: \" padded\" starts or ends with a space"))
        #expect(joined.contains("Bad.swift:6: a `pick(…)` the lint cannot read"))
        #expect(joined.contains("Bad.swift:7: capitalised «Вы»"))
    }

    @Test("CyrillicRatchet: markers allow Cyrillic, and a marker without Cyrillic fails")
    func ratchet() {
        let plain = SourceFile(path: "Sources/CodometerUI/A.swift", text: "/// «Обзор»\nlet a = \"Обзор\"\n")
        #expect(CyrillicRatchet.problems(in: plain) == ["Sources/CodometerUI/A.swift:2: Cyrillic outside CodometerL10n; move the text into a phrase"])

        let pending = SourceFile(path: "Sources/CodometerUI/A.swift", text: "// l10n: pending\nlet a = \"Обзор\"\n")
        #expect(CyrillicRatchet.problems(in: pending).isEmpty)

        let ignored = SourceFile(path: "Sources/CodometerStorage/A.swift", text: "let a = \"сессия \" // l10n-ignore: historical migration\n")
        #expect(CyrillicRatchet.problems(in: ignored).isEmpty)

        let emptyReason = SourceFile(path: "Sources/CodometerStorage/A.swift", text: "let a = \"сессия \" // l10n-ignore:\n")
        #expect(CyrillicRatchet.problems(in: emptyReason).count == 1)

        let stale = SourceFile(path: "Sources/CodometerUI/A.swift", text: "// l10n: pending\n/// «Обзор» in a comment only\nlet a = 1\n")
        #expect(CyrillicRatchet.problems(in: stale) == ["Sources/CodometerUI/A.swift: no Cyrillic left; delete the `// l10n: pending` marker"])

        let l10n = SourceFile(path: "Sources/CodometerL10n/Strings/A.swift", text: "let a = \"Обзор\"\n")
        #expect(CyrillicRatchet.problems(in: l10n).isEmpty)
    }

    @Test("LiteralUIAPI finds literals in text APIs and allows verbatim text, brands, markers and phrases")
    func literalUIAPI() {
        let source = #"""
        Text("Overview")
        Text(verbatim: "Overview")
        Text(l10n.deck.overview)
        Text("\(count)")
        Text("Codometer")
        Button(
            "Save"
        ) { save() }
        view.help("Refresh this account")
        panel.prompt = "Choose"
        item.title == "Choose"
        menu.addItem(NSMenuItem(title: "Quit", action: nil, keyEquivalent: ""))
        Toggle("Track", isOn: $on) // l10n-ignore: fixture
        let title = "Not UI"
        Label("\(name)", systemImage: "folder")
        """#
        let file = SourceFile(path: "Sources/CodometerUI/A.swift", text: source)
        let lines = LiteralUIAPI.problems(in: file).compactMap { problem in
            problem.split(separator: ":").dropFirst().first.flatMap { Int($0) }
        }
        #expect(lines == [1, 7, 9, 10, 12])

        let pending = SourceFile(path: "Sources/CodometerUI/A.swift", text: "// l10n: pending\nText(\"Обзор\")\n")
        #expect(LiteralUIAPI.problems(in: pending).isEmpty)
        let debug = SourceFile(path: "Sources/CodometerApp/Debug/A.swift", text: "Text(\"Debug\")\n")
        #expect(LiteralUIAPI.problems(in: debug).isEmpty)
    }
}
