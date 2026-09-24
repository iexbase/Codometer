# Localization

Codometer speaks English (the default) and Russian. Users switch in **Settings → General → Language**: English, Русский or
System Language. Our own text switches at once. Text drawn by macOS (menus, open panels, alert buttons) follows from the
next launch.

## How it works

All user-facing text lives in the leaf module `CodometerL10n` (Foundation only). It uses no `.xcstrings`, resource
bundles or `Bundle.module`, so `swift build`, the packaged app and the sandboxed widget extension behave the same way.

```swift
// Sources/CodometerL10n/Strings/Deck.swift — one file per area
public struct DeckStrings: Sendable {
    let l: Localizer
    public var overview: String { l.pick(en: "Overview", ru: "Обзор") }
    public func updated(ago: String) -> String { l.pick(en: "Updated \(ago)", ru: "Обновлено \(ago)") }
    public func moreSessions(_ n: Int) -> String {
        l.plural(n, en: ("\(n) more session", "\(n) more sessions"),
                    ru: ("ещё \(n) сессия", "ещё \(n) сессии", "ещё \(n) сессий"))
    }
}
extension Localizer { public var deck: DeckStrings { DeckStrings(l: self) } }
```

- **`Localizer`** holds the `Language` (words) plus a `Locale` and `Calendar`. The locale combines that language with
  the user's region, hour cycle and first weekday. `Localizer.testEnglish` (en_US, 12-hour, GMT) and
  `Localizer.testRussian` (ru_RU, 24-hour, GMT) are fixed for tests and renders.
- **`pick(en:ru:)`** takes both languages, so a missing translation doesn't compile. Only the chosen branch runs.
- **`plural(_:en:ru:)`** uses the CLDR rule: English has one/other, Russian has one/few/many. Every form contains the number.
  Give zero its own phrase when the wording differs (“No accounts”).
- **`slot(en:ru:)`** returns `(prefix, suffix)` around one live `Text`:
  `Text("\(slot.prefix)\(Text(date, style: .relative))\(slot.suffix)")`. `Text + Text` is deprecated in the macOS 26 SDK.
- **`l10n.format`** formats numbers, durations, times and percentages. Never format them yourself:
  `durationCompact` (2h 14m | 2 ч 14 мин), `durationShort` (12 min), `durationPrecise` (4m 12s),
  `durationSpoken` (VoiceOver), `latency` (2.8s), `railCountdown` (47m, 2:14, 3d), `percentCompact` (64%, drawn numerals),
  `percent` (prose: 64% | 64 %), `approxPercent` (≈3.2%), `decimal`, `clock` (the user's 12/24-hour clock),
  `moment` (at 6:40 PM, tomorrow at 9:00 AM), `ago` (just now, 2 min ago), `weekdayShort`, `list`.

## Where the localizer comes from

| Place | Localizer |
|---|---|
| SwiftUI views | `@Environment(\.l10n) private var l10n`. Every hosting root injects `.environment(\.l10n, store.localizer).environment(\.locale, store.localizer.locale)`. Every new root must do the same |
| AppKit menus, tooltips, notifications | `store.localizer`, read when the text is built |
| Widget extension | `@Environment(\.widgetL10n)`, built from `WidgetSnapshot.language` (`LimitsEntry.localizer`) |
| Tests | `Localizer.testEnglish` / `.testRussian` |
| Before settings load (fatal launch alert) | `Localizer(language: Language.resolve(.system))` |

`TrackerStore.localizer` changes only when `general.language`, the macOS language order or the region changes. The app
calls `store.refreshLocale()` on `NSLocale.currentLocaleDidChangeNotification`. `.system` follows the global macOS
language order, not the app's own `AppleLanguages`. `LanguageDefaults.apply(_:)` writes that value at launch and on every
change (English or Russian), or removes it (System).

The engine never imports `CodometerL10n`. History stores language-neutral machine forms (for example
`SessionLabel.neutral`: “Codometer · 3f9a1c”, or just “3f9a1c”) and never shows them. Views and notifications build
`SessionLabelParts` with `SessionLabel.parts(sessionID:projectFolder:)` and put them into words with
`UsageFormat.sessionLabel` (“Session 3f9a1c” | «сессия 3f9a1c»).
Attribution reports carry `AttributionSubject` values, never words.

## Rules

1. **No string literals in UI APIs.** Add a phrase to your own area file. The lints check `Text(`, `Button(`, `Toggle(`,
   `Label(`, `Section(`, `Picker(`, `LabeledContent(`, `TextField(`, `Menu(`, `.help(`, `.accessibilityLabel/Value/Hint(`,
   `.navigationTitle(`, `ActionMenuItem(`, `NSMenuItem(title:` and `.toolTip/.messageText/.informativeText/.prompt/.title =`.
   Use `Text(verbatim:)` only for user data and symbols.
2. **One area file per surface.** An area is one file in `Sources/CodometerL10n/Strings/`, named after the surface it
   serves (`Deck.swift`, `Card.swift`, `Onboarding.swift`, `Diagnostics.swift`, …). A phrase lives in the area of the
   surface that shows it; shared words go to `Common.swift`. `Localizer`, `Formats` and `Language` change rarely: if a
   format is missing, start with a private helper inside the area struct (it may use `l.locale` and `l.calendar`) and
   move it to `Formats` once a second area needs it.
3. **English first, native in both.** English uses sentence case, with Title Case only for menu items, push buttons and
   window titles. Use contractions, curly quotes and apostrophes (“ ” ’), `…` never `...`, no “please”, no “Error:”. Russian:
   «вы», ё, «ёлочки», a no-break space between a number and its unit (`\u{00A0}`), infinitive buttons, no officialese.
   Brand names stay as they are: Codometer, Claude, Claude Code, Codex, Liquid Glass. Keep to the glossary below, so
   the same thing is never called two things.
4. **Whole phrases with interpolation.** Never glue fragments (`"Resets in " + x`). Pass pre-formatted strings from
   `l10n.format` for durations, times and percentages, and pass `Int` counts for plurals.
5. **Reserved widths per language.** A `…Template` phrase must be the widest realistic value *in each language*, and
   gets a fit test in both languages (`NSString.size` in the real font).
6. **VoiceOver text** (`…A11y`) speaks durations in words (`format.durationSpoken`) and avoids ` · ` and `≈`.
7. **Never translate** user data (account labels, group names, folder names), provider data (plan badges, model and
   bucket names), Terminal commands, technical `TrackerIssue.detail`, or the English diagnostics support report.

## Naming

Access path `l10n.<area>.<name>`, meaning-based `lowerCamelCase`: `deck.loadingLimits`, `resetsIn(_ countdown:)`,
`accounts(count:)`. Suffixes: `…Title`, `…Footer`, `…Hint`, `…Help` (tooltip), `…A11y`, `…Placeholder`, `…Template`,
`…Message`. Buttons and menu items have no suffix: `refreshAll`. The Language area is reached as
`l10n.languageSettings` because `l10n.language` is the localizer's own language.

## Lints (`Tests/CodometerSourceLintTests`, run with every `Scripts/test.sh`)

- **PhraseLint** reads every `.pick(`, `.plural(` and `.slot(` in `Sources/CodometerL10n`. It checks that every call is
  readable (plain one-line literals), no form is empty or has edge spaces or double spaces, and all forms have the same
  interpolations. English may not contain Cyrillic, `«»`, ASCII quotes or apostrophes, or `...`. Russian needs Cyrillic
  (unless it is the same brand name as English), and may not contain ASCII quotes, `...` or a capitalised «Вы»
  mid-sentence.
- **CyrillicRatchet**: Cyrillic in code or string literals outside `Sources/CodometerL10n` fails, unless the file's first
  line is `// l10n: pending` or the line ends with `// l10n-ignore: <reason>`. A pending marker on a file without Cyrillic
  also fails, so delete the marker when you convert a file. The release gate is zero markers:
  `grep -rn "l10n: pending" Sources`.
- **LiteralUIAPI**: no literal with letters in the UI APIs above, outside `CodometerL10n`, `CodometerApp/Debug` and files
  with the pending marker. The brand allowlist and `// l10n-ignore:` apply.

If you own a file that starts with `// l10n: pending`, convert the whole file and delete the marker.

## Tests and renders

- Pin expectations to `.testRussian` or `.testEnglish`. Never depend on the machine's language or region.
- Gated renders (`CODOMETER_SNAPSHOT_DIR=… Scripts/test.sh --filter Snapshot`) write `…-en.png` and `…-ru.png`, for
  example `L10nSnapshotTests`.
- Debug builds started with `CODOMETER_L10N_PSEUDO=1` wrap every phrase as `⟦text···⟧`, about a third longer, to reveal
  truncation and text that is still hard-coded.

## System chrome and the widget

- Both `Info.plist` files declare `CFBundleDevelopmentRegion = en` and `CFBundleLocalizations = [en, ru]`, so AppKit
  follows `AppleLanguages`.
- `WidgetSnapshot.language` carries the app's resolved language. It is part of `hasSameContent` and of the export
  significance, so a language change is published at once. A snapshot without the key decodes as English. The extension
  renders its own text in that language. WidgetKit may keep showing the old gallery name until it restarts the extension.

## Glossary

The word on the left is what the interface calls it in English; on the right is the only Russian word for it. Use
both exactly, in the app **and** in the documentation.

| English | Русский |
|---|---|
| island | остров |
| expanded island | раскрытый остров |
| floating card | плавающая карточка |
| rail (the resting capsule) | капсула |
| deck (the card's content) | карточка |
| menu bar item / popover | значок в строке меню / всплывающее окно |
| widget | виджет |
| limit window | окно лимита |
| usage | расход |
| reset | сброс |
| agent session | сессия агента |
| waiting for you | ждёт вас |
| account | аккаунт |
| profile folder | папка профиля |
| group | группа |
| history | история |
| timeline | хронология |
| welcome guide | знакомство |
| Claude Code, Codex, Codometer, Liquid Glass | как есть, без перевода |

Never translate user data (account names, group names, folder names), provider data (plan badges, model and bucket
names), Terminal commands, or the English support report.

## Documentation

The docs are bilingual where it matters to a user: `README.md` / `README.ru.md`, `PRIVACY.md` / `PRIVACY.ru.md`,
and `docs/release-notes/<version>.{en,ru}.md`. `SECURITY.md`, `CHANGELOG.md` and everything under `docs/` for
contributors are English only.

Two rules for them:

1. **Write the Russian version, do not translate it.** Same structure and same facts, natural sentences, with the
   typographic rules above (`«ёлочки»`, ё, a no-break space before a unit).
2. **Quote the interface exactly.** When a document names a setting, use the phrase from the area file in that
   language — «Открывать при входе в систему», not a paraphrase. If a phrase changes in
   `Sources/CodometerL10n/Strings/`, grep the docs for the old wording in the same commit.

Screenshots follow the same split: `docs/images/en/` and `docs/images/ru/`, the same file names in both, rendered
from fixture data so no real account, email address or project name is ever in an image.
