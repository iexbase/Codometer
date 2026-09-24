import CodometerL10n
import Testing

@Suite("Plural rules")
struct PluralRuleTests {
    private static let russian: [(Int, PluralCategory)] = [
        (0, .many), (1, .one), (2, .few), (4, .few), (5, .many), (11, .many), (12, .many), (14, .many),
        (21, .one), (22, .few), (25, .many), (101, .one), (111, .many), (112, .many), (1_001, .one), (-1, .one), (-3, .few),
    ]

    @Test("Russian: one, few and many by the last two digits", arguments: russian)
    func russianCategories(count: Int, expected: PluralCategory) {
        #expect(Language.ru.pluralCategory(count) == expected)
    }

    @Test("English: one only for exactly one", arguments: [(0, PluralCategory.other), (1, .one), (2, .other), (11, .other), (21, .other), (-1, .one)])
    func englishCategories(count: Int, expected: PluralCategory) {
        #expect(Language.en.pluralCategory(count) == expected)
    }

    @Test("The plural form carries the number, with the right noun in each language")
    func forms() {
        func agents(_ l: Localizer, _ count: Int) -> String {
            l.plural(count, en: ("\(count) agent", "\(count) agents"), ru: ("\(count) агент", "\(count) агента", "\(count) агентов"))
        }
        #expect(agents(.testEnglish, 1) == "1 agent")
        #expect(agents(.testEnglish, 0) == "0 agents")
        #expect(agents(.testEnglish, 21) == "21 agents")
        #expect(agents(.testRussian, 1) == "1 агент")
        #expect(agents(.testRussian, 3) == "3 агента")
        #expect(agents(.testRussian, 5) == "5 агентов")
        #expect(agents(.testRussian, 11) == "11 агентов")
        #expect(agents(.testRussian, 21) == "21 агент")
        #expect(agents(.testRussian, 22) == "22 агента")
        #expect(agents(.testRussian, 111) == "111 агентов")
    }

    @Test("Areas use the rule: alert summaries and agent counts")
    func areas() {
        #expect(Localizer.testEnglish.alertSummary.title(count: 3) == "3 alerts")
        #expect(Localizer.testEnglish.alertSummary.title(count: 1) == "1 alert")
        #expect(Localizer.testRussian.alertSummary.title(count: 1) == "1 событие")
        #expect(Localizer.testRussian.alertSummary.title(count: 3) == "3 события")
        #expect(Localizer.testRussian.alertSummary.title(count: 5) == "5 событий")
        #expect(Localizer.testRussian.alertSummary.title(count: 21) == "21 событие")
        #expect(Localizer.testRussian.alertSummary.title(count: 112) == "112 событий")
        #expect(Localizer.testEnglish.analyticsFormat.agents(0) == "no agents")
        #expect(Localizer.testEnglish.analyticsFormat.agents(2) == "2 agents")
        #expect(Localizer.testRussian.analyticsFormat.agents(0) == "нет агентов")
        #expect(Localizer.testRussian.analyticsFormat.agents(2) == "2 агента")
        #expect(Localizer.testRussian.analyticsFormat.agents(14) == "14 агентов")
    }
}
