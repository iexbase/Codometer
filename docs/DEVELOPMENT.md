# Development

Everything you need to build Codometer, run it safely against test data, drive it through scripted scenarios, and
check your work before a pull request. The shape of the code is in [ARCHITECTURE.md](ARCHITECTURE.md), text and
translations in [LOCALIZATION.md](LOCALIZATION.md), and shipping in [RELEASING.md](RELEASING.md).

## Toolchain

- macOS 26 and **Xcode 26** (the pinned version is in `Packaging/toolchain.env`).
- Nothing else. There are no third-party dependencies and no package manager to bootstrap.

The scripts resolve the toolchain themselves, so you never have to `xcode-select` globally:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer   # what the scripts default to
```

## The loop

```bash
Scripts/test.sh                       # the whole suite (Swift Testing)
Scripts/test.sh --filter CardMenuPlan # one suite
Scripts/build-app.sh debug            # assembles build/Codometer.app
Scripts/build-app.sh release          # release configuration, ad-hoc signed
Scripts/build-app.sh debug --output /tmp/x   # assemble elsewhere; nothing in build/ is touched
Scripts/lint.sh                       # the policy and documentation lints the release gate runs
Scripts/lint.sh --advisory            # plus the informational inventory (public log sites)
```

`swift build`, `swift test` and Xcode all work directly on the package too. `Scripts/build-app.sh` is what turns
the two products into an app bundle with the widget extension inside it, the version numbers, the icon and a
signature.

## Running a build safely

**Always run a development build against an isolated data folder.** Without one it uses
`~/Library/Application Support/Codometer` — your real data — and performs the one-time migration of the folder the
app had under its former name. That has cost real data once already.

```bash
CODOMETER_DATA_ROOT=~/Library/Caches/CodometerDev/run Scripts/run.sh
```

`Scripts/run.sh` exists to enforce two rules, and it refuses to start without them:

1. it never launches without an isolated `CODOMETER_DATA_ROOT`;
2. it stops only a copy whose executable lives inside this tree's `build/` — never `pkill -x Codometer`, which
   would also kill the copy you have installed.

It launches the executable directly rather than through `open`, because `open` hands the app to LaunchServices,
which drops the environment and would run it against the real folder.

### `CODOMETER_DATA_ROOT`

An absolute path inside `~/Library/Caches/` or a temporary folder, with no symbolic links. An unacceptable value is
a launch error, not a silent fall back to real data. An isolated instance:

- writes no widget snapshot,
- posts no notifications,
- never changes the login item,
- registers no global shortcut unless a scenario turns one on,
- keeps its `CODOMETER_*` environment across an in-app relaunch.

Delete an isolated root when you are done with it, and check afterwards that
`~/Library/Application Support/Codometer` is still the only real data folder you have.

### Registration, widgets and `chronod`

WidgetKit keys desktop widgets by bundle identifier, and `chronod` launches whichever copy LaunchServices has on
file. When that copy is a stale path — a deleted build folder, a mounted disk image, a copy under the app's former
identifier — its requests fail, and after a burst of failures it logs *“Disallowing reload due to bad extension”*
and stops reloading the widget **for 24 hours** (or until `chronod` restarts).

So, when you need widgets to actually work from a development build:

```bash
Scripts/build-app.sh release
Scripts/dev-register.sh build/Codometer.app     # registers this copy, unregisters every other one
Scripts/dev-register.sh --dry-run               # prints what it would do and touches nothing
```

Registration changes
LaunchServices state on your Mac, so run it deliberately — and note that `Scripts/build-app.sh` in **release** mode
never registers anything, never stops a process and never writes outside its output folder.

Checking what macOS knows:

```bash
pluginkit -m -v -i com.codometer.Codometer.Widgets
log stream --predicate 'subsystem == "com.codometer.widgets"' --level info
```

Every build gets a new `CFBundleVersion` (seconds since 1970), is assembled in `build/.staging` and swapped in with
two renames, with the extension process stopped around the swap. Do not try to shortcut that: it is what keeps
`chronod` from blacklisting the extension.

## Debug scenarios

A DEBUG build can play a scripted scenario: override settings in memory, replace the data with a fixture, hover,
click, drag, switch language, open panes, and record PNG frames plus a geometry line per frame. The code is in
`Sources/CodometerApp/Debug/` and compiles only under `#if DEBUG`; its file header is the authoritative reference.

```bash
Scripts/build-app.sh debug
CODOMETER_DATA_ROOT=~/Library/Caches/CodometerDev/data \
CODOMETER_DEBUG_SCENARIO=/absolute/path/scenario.json \
CODOMETER_DEBUG_OUT=/absolute/path/out \
build/Codometer.app/Contents/MacOS/Codometer
```

A scenario is a JSON array of steps (or `{"steps": [...]}`); each step object has exactly one key.

| Step | What it does |
|---|---|
| `{"fixture": "multi"}` | Replaces accounts, state and analytics with synthetic data in memory (`single`, `standard`, `multi`, `limits`, `empty`) and ignores engine updates from then on. **Every capture used for review, docs or screenshots uses a fixture** — real accounts never appear in an image |
| `{"language": "en"\|"ru"\|"system"}` | The interface language, in memory |
| `{"settings": {…}}` | Any `AppearanceSettings` or `GeneralSettings` key, validated by the settings' own decoders, never saved |
| `{"settingsPane": "diagnostics"}` | Opens Settings on a pane (window name `settings`) |
| `{"popover": true\|false}` | Opens or closes the menu bar popover (window `popover`) |
| `{"page": "timeline"}`, `{"range": "day"}` | The deck's page and the timeline range |
| `{"expand"}`, `{"collapse"}`, `{"hover"}`, `{"click"}`, `{"outsideClick"}`, `{"drag": {…}}`, `{"press"}`, `{"notch": {…}}`, `{"display": "next"}` | Island interaction |
| `{"style": "floatingCard"}`, `{"cardExpand"}`, `{"cardMinimize"}`, `{"cardDrag": {…}}`, `{"cardAccount": "next"}`, `{"cardTheme": …}`, `{"cardSize": …}`, `{"displayChange": "simulate"}` | The floating card |
| `{"reset": {…}}`, `{"finishTurn": {…}}` | A limit reset ceremony, a turn finishing |
| `{"onboarding": {"step": 3, "fixture": true}}`, `{"finishOnboarding"}`, `{"eraseSheet"}`, `{"exportSheet"}`, `{"relaunch"}` | Onboarding and the data controls |
| `{"power": {…}}`, `{"energyFixture": …}`, `{"diagnosticsFixture": …}`, `{"shortcutStatus": …}`, `{"serviceStatus": {…}}` | Fake power, energy, diagnostics, shortcut and vendor-status state — no network is used |
| `{"reduceMotion": true\|false\|"system"}` | Overrides Reduce Motion for the island's motion |
| `{"wait": 1.5}`, `{"monitor": 10}` | Waits; logs every main-thread stall over 24 ms for that long |
| `{"capture": {"name": "top-expand", "frames": 24, "interval": 0.033, "window": "island"}}` | PNG frames of `island`, `card`, `popover`, `settings` or `onboarding` |
| `{"trace": {…}}` | The same, but geometry lines only — no image, so it never stalls the main thread. Use it for timing |
| `{"axdump": {"name": …, "window": …}}` | Writes the accessibility tree as VoiceOver reads it |
| `{"quit": true}` | Waits for pending captures, then quits |

Notes that will save you an hour:

- The liquid morph settles in about 0.4 s; review it at 30 fps (`"interval": 0.033`, `"frames": 24`).
- Captures use ScreenCaptureKit for this process's own windows. When it fails (error −3811, logged as
  `captureFallback`), set `CODOMETER_DEBUG_CAPTURE=view` to draw each frame synchronously — that path shows content
  and the rim but **not** Liquid Glass, so check content with `"surface": "solid"` and judge timing from `trace`.
- **Never `axdump` an expanded deck or the popover.** Swift Charts evaluates the usage chart's accessibility off
  the main thread and the dump crashes debug builds. Dump rails, settings panes, the card and onboarding.
- With a scenario set, first-run onboarding is skipped unless the scenario contains an `onboarding` step, and an
  isolated root starts with no discovered accounts.
- Every frame appends a line to `frames.jsonl`: time, step, panel frame, island shape frame, measured sizes, state
  flags, anchor, language and the fields each domain handler adds.

## Renders and pseudo-localization

Snapshot suites are gated on an environment variable, so a normal test run never writes files:

```bash
CODOMETER_SNAPSHOT_DIR=/tmp/codometer-shots Scripts/test.sh --filter Snapshot
CODOMETER_SNAPSHOT_DIR=/tmp/codometer-shots Scripts/test.sh --filter WidgetRender
```

Each suite writes `…-en.png` and `…-ru.png`, because a layout that fits in one language is not evidence for the
other. Start a debug build with `CODOMETER_L10N_PSEUDO=1` to wrap every phrase as `⟦text···⟧`, about a third
longer, which reveals truncation and text that is still hard-coded.

## Before a pull request

1. `Scripts/test.sh` is green and the test count has not dropped.
2. `Scripts/lint.sh` passes, and `grep -rn "l10n: pending" Sources` is empty.
3. `swift build -c release --product Codometer` and `--product CodometerWidgets` build with **no warnings**
   (warnings are errors in this package, so this is mostly a check that you did not add `#if` paths that only
   compile in debug).
4. New user-facing text is in `CodometerL10n` in both languages, with a fit test if it has a reserved width.
5. New interactive elements have a localized accessibility label, a hit target of at least 24 pt, and do not use
   colour as the only signal.
6. Anything that renders differently in English and Russian has both renders, and you have looked at them.

House rules that the lints enforce, so you find out early: no `try!`, no `fatalError` outside an unavailable
`init(coder:)`, no `print` (use `AppLog`), no per-frame SwiftUI loops (`TimelineView(.animation)`,
`.repeatForever`, repeating `symbolEffect`), no `Bundle.module`, no `URLSession` outside `StatusFeedClient.swift`,
no `UserDefaults` outside the language shim, no `posix_spawn`/`Process(` outside `Platform/Process`, no Cyrillic
outside `CodometerL10n`, no string literals in UI APIs, and every file under a `Debug/` folder starts with
`#if DEBUG`.

Beyond the lints: idle CPU must stay at about zero (no timers while nothing is visible), nothing may resize or jump
after an interaction, and changing text reserves the widest template **per language**.

## Performance

```bash
Scripts/perf-smoke.sh --style island --duration 120
```

It measures the performance budgets — idle CPU (avg ≤ 0.5 %, p95 ≤ 2 %), idle wakeups (≤ 1/s), RSS (steady
≤ 120 MB, peak ≤ 160 MB) — against a built app. It requires an isolated `CODOMETER_DATA_ROOT`, runs the executable
directly, stops only the process it started, and deletes its data root at the end.

## Repository layout

```
Packaging/     Info.plists, entitlements, VERSION, identity.env, toolchain.env, the icon document
Scripts/       build, run, test, lint, icon, register, perf, release, and the shared lib/
Sources/       the eleven modules
Tests/         one test target per module, plus CodometerSourceLintTests
docs/          this guide, architecture, localization, releasing, images, release notes
.github/       ci.yml (every push) and release.yml (tags)
```

Two folders are deliberately ignored and never committed: `build/` (local bundles) and `dist/` (release artifacts).
