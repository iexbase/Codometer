# Architecture

How Codometer is put together: the modules, what flows through them, and the rules each layer follows. For the
day-to-day loop (building, scenarios, renders) see [DEVELOPMENT.md](DEVELOPMENT.md); for text and translations see
[LOCALIZATION.md](LOCALIZATION.md).

## Modules

A Swift package of eleven modules, all compiled in Swift 6 language mode (complete concurrency checking) with
`ExistentialAny`, `MemberImportVisibility` and **warnings as errors**. There are no third-party dependencies and no
resource bundles: everything ships as code.

```
CodometerL10n        English and Russian phrase tables, plural rules, locale-aware formats. Foundation only,
                     no resources, so the app and the sandboxed widget use it the same way
CodometerCore        domain model, validation, pace and forecast maths, alert rules, energy policy, widget
                     scope, geometry, diagnostics models. No I/O
CodometerPlatform    OS adapters: bounded file reads, log tailing, FSEvents, posix_spawn, code-signature
                     checks, power and network state, the status feed client, the unified log
CodometerStorage     settings.json (atomic writes, recovery) and history.sqlite (schema v4)
CodometerClaude      /usage parser, sessions/<pid>.json, turn tracking, token counts from transcripts,
                     account metadata from .claude.json, launching the CLI
CodometerCodex       rollout-log byte scanner, session state, approval waits, turns and tokens, the
                     JSON-RPC client for codex app-server
CodometerEngine      per-account monitors, scheduling and backoff, reading merge, events, history
                     recording, timeline and attribution, profile discovery, diagnostics, vendor status
CodometerUI          SwiftUI: design system, island, floating card, deck, analytics, settings, onboarding
CodometerApp         AppKit shell: panels, status item, windows, notifications, shortcut, widget export,
                     lifecycle, composition root; debug scenarios in DEBUG builds only
CodometerWidgetsUI   widget views and timeline (Sources/CodometerWidgets/UI), extension-safe APIs only
CodometerWidgets     the WidgetKit extension executable (Sources/CodometerWidgets/Extension)
```

Dependencies point one way: `L10n → Core → Platform → Storage/Claude/Codex → Engine → App`, with `UI` and
`WidgetsUI` depending only on `Core` and `L10n`. **The engine never imports `CodometerL10n`**: anything that needs
words (the `README.txt` of a CSV export, for example) receives the finished text from the App.

## Data flow

```
FSEvents / scheduled refresh ─▶ AccountMonitor (one actor per account) ─▶ MonitorEvent (readings, sessions, tokens)
                                                                             │
                     TrackerEngine (actor): merge → TrackerState ────────────┤─▶ AlertEvaluator → TrackerAlert
                                                                             │            │
   UsageHistoryStore (SQLite) ◀── HistoryRecorder (queue, 2 s batches) ◀─────┘            ▼
    readings, SegmentTracker → segments, tokens                        AlertDeliveryPlanner → AlertPresenter
                                                                             ▼
                     AppController (MainActor) ─▶ TrackerStore (@Observable) ─▶ SwiftUI surfaces
```

- A **reading** (`UsageReading`) is a set of limit buckets, each with its windows (`LimitWindow`: percentage,
  duration, reset time). Every value validates in its initialiser, so an invalid one cannot be constructed.
- **Merging** (`ReadingMerger`): a Codex log carries only the current model's bucket while `app-server` carries all
  of them, so a newer value wins and missing buckets are carried over while their windows have not reset.
- **Alerts** come only from a transition between two states, so launching the app or adding an account never
  produces a flood of old notifications.
- **Tokens** (`TokenSample`) arrive live and already deduplicated; the engine drops samples from another account,
  zero samples, samples older than the retention period, and samples more than five minutes in the future.
- `TrackerStore` is the one `@Observable` the UI reads. Views never talk to the engine; they call closures on
  `TrackerActions`, which `AppController` routes.

## Refresh schedule and energy

| Situation | Claude | Codex |
|---|---|---|
| Normal | 5 min ± 10 % | 3 min ± 10 % |
| Session running, or ≥ 90 % used | at least every 2 min | at least every 1 min |
| An agent's answer just finished | after 8 s (at most once per 90 s) | the log delivers it instantly |
| Failure | doubling up to 30 min | doubling up to 30 min |
| Not signed in | — | retry every 10 min, or when `auth.json` changes |
| Mac asleep (`willSleep` / `didWake`) | paused, refresh on wake | same |
| Display off only | no pause: agents work, history keeps recording | same |

`EnergyPolicy` (pure, in Core) turns a `PowerSnapshot` and the user's energy mode into an `EnergyDecision`:

| Situation | Factor | Urgent cap | Live effects |
|---|---|---|---|
| Always fresh (any power) | 1 | 1 | on, except in Low Power Mode |
| Plugged in, nominal or fair | 1 | 1 | on |
| On battery | 1.5 | 1 | on |
| Low battery | 2 | 1.5 | on |
| Low Power Mode | 3 | 2 | paused |
| Thermal serious | 2 | 1.5 | paused |
| Thermal critical | 4 | 2 | paused |
| Save battery | max(2, automatic) | max(1.5, automatic) | as automatic |

Conditions combine by maximum, never by product, and the factor only ever **stretches** a delay: the reset-settle
refresh and the ≥ 90 % cap still fire. A factor that drops may pull the next refresh forward (never sooner than
5 s after the change); a factor that rises never postpones a refresh that is already armed.

If `claude /usage` returns output without limit lines three times in a row, polling stops until the user asks for a
refresh by hand: the command must never turn into a model request. Diagnostics shows this as “Data format”.

## Presentation surfaces

`PresentationSurface` (App) is the protocol both styles implement — `isOnScreen`, `applyAppearance`,
`openPinned(accountID:)`, `peek`, `toggleFromShortcut`, `hide`. `PresentationRouting` decides which one is active
(the card when it is the selected style and exists, otherwise the island) and falls back to the menu bar popover
when the surface cannot handle a request. Notification clicks, peeks and the global shortcut all go through it.
Exactly one surface is on screen; the status item and its popover always stay.

`ActivationPolicy` is reference-counted: Settings and onboarding each hold a claim to `.regular`, so closing one
window never demotes the app while the other is open.

### The island

- `IslandModel` holds the shared state (expanded, dragging, selected account, layout, the frames of capsule and
  deck, the maximum deck height, requests coming from inside the island).
- `IslandInteractionState` is a pure state machine (fully tested): hover with a 130 ms intent delay and a 320 ms
  close delay, click, pin, outside click, Esc, shortcut, peek, drag. The mode comes from
  `AppearanceSettings.openTrigger` (`hover`, `click`, `hoverOrClick`). The controller turns its effects into
  timers, monitors and animations; the global click monitor exists only while a pinned deck is open.
- `IslandGeometry` is pure geometry (tested): position along an edge, anchor, capsule and deck frames, the deck's
  maximum height, the panel frame, snapping while dragging.
- `IslandRootView` is a canvas the size of the screen. Expanding flips one flag: a single transaction
  (`Motion.liquidOpen`, a 0.40 s spring, at rest by ≈0.39 s, or `Motion.liquidFold`, 0.55 s critically damped)
  drives `LiquidIslandShape`, which also clips the content, carries the glass and draws the rim.
- `LiquidMorph` (pure, tested) is that outline in a canonical frame shared by every edge and both styles: the body
  (a capsule growing into the deck, with concave shoulders when attached to the edge) and a droplet on the free
  side. Hovering raises the free side by one low arc. With Reduce Motion the outline is a rounded rectangle and
  expanding is a plain 0.2 s resize. The path is about twenty cubic segments and allocates nothing but the `Path`;
  a stress grid over every edge, style and scale finds no self-intersections.
- `IslandController` owns a non-activating panel. The panel is only a window onto the canvas, so resizing it moves
  nothing on screen: it grows once before expanding and shrinks once after the fold completes. The deck is
  pre-warmed (invisible, non-interactive) on hover or before a click, and the capsule is pre-built before a fold,
  because building either one inside the animating transaction costs ~35 ms on the first frame instead of ~12 ms.
- `RingFlight` (draw-only overlay) flies the rings between rail and deck; `EdgeSnapping` and `NotchFusion` handle
  magnetic edges and wrapping around the camera notch, where the island turns solid black whatever surface is set.
- Esc: while a **pinned** deck is open and Codometer is not the active app, a scoped Carbon hot key is armed —
  Carbon delivers only Esc and consumes it, so nothing else the user types is ever seen. While Codometer is active
  a local `NSEvent` monitor does the same job. A deck opened by hover never arms the hot key.

### The floating card

- `FloatingCardPanel` / `FloatingCardController` (App) host the SwiftUI card: expanded (Compact, Regular or Strip) or
  minimized to a pill, in four themes whose tokens live in `CardThemeTokens`. Every expanded size has a fixed frame
  from `CardMetrics`, so no value or language can resize it; a size that does not fit the display falls back
  (Strip → Regular → Compact) for that session only.
- `CardContentPlan` (pure, tested) decides everything the card says for one account. The Strip adds `CardStripPlan`:
  its scope (`CardStripScope`: the followed account, every Claude or Codex account, or all) merges the windows of
  those accounts into fixed-size chips — the same kind of window on several accounts folds into one chip showing the
  most constrained and counting the accounts — and leads with the most constrained weekly window. Chips beyond the
  strip's capacity fold into a "+N" chip; a merged strip's status pill and freshness cover its whole scope.
- Dragging snaps to corners, edges and the centre (`MagnetLaw`, shared with the island; hold ⌘ to place it
  exactly) and can play a haptic tap. Placements are remembered per display.
- `CardMenuPlan` builds the context menu as data, so its English and Russian wording is unit-tested without AppKit.
- Keyboard engagement: a click makes the card key, and only then do Esc and the arrow keys apply to it.
- Double-click minimizes (and restores); the coach mark is shown once.

## Deck and analytics

- `DeckContent` is one card shared by the island and the popover: a header with the group filter and how fresh the
  newest reading is, the “waiting for you” queue, account dials (up to three rings), and the Overview and Timeline
  pages. All accounts and pages are laid out in one stack (`PageStackLayout`, as tall as the tallest), and a hidden
  measuring copy lays them out the same way, so switching an account or a page never resizes anything.
- `DeckSections` decides, purely and testably, whether each part is `shown`, `reserved` (laid out for size but
  invisible, non-interactive and hidden from VoiceOver) or `absent`. An empty group reserves the dials and pages
  under an empty-state card, so filtering never changes the size.
- History is fetched through `AnalyticsCache` (deduplicated, at most once per minute per key) and only while the
  deck is visible (`isDeckVisible`), so a hidden or measuring copy never queries.
- `WindowHistoryChart` (Swift Charts) draws usage, the even pace, “now” and the forecast. `SessionTimelineView`
  (Canvas) draws session bars, the main window's curve, reset marks and the **gaps** where nothing was collected
  (`CollectionGaps`, from `collection_runs`). `AttributionListView` shows “Who used the limit” as shares with an
  estimate in points (`≈3.2 %`).
- Attribution counts only usage between two observations of one collection run, so usage from before the first
  launch, while the app was closed or while the Mac slept is never attributed to a project.

## Agent sessions

- **Claude.** `ClaudeSessionScanner` reads `sessions/<pid>.json` (status, what it waits for, entry point,
  timestamps). `TurnTracker` (pure) measures a turn from “working” until it returns to “ready”; an approval prompt
  mid-turn does not end it; zero-length turns and turns over 24 h are dropped; time to first token is not
  available. Writes to a transcript move `lastEventAt` in 30 s steps, so a session busy with a subagent never looks
  stalled.
- **Claude tokens.** `ClaudeTranscriptUsageReader` (actor) watches `projects/` through FSEvents (2 s latency) and
  reads only what was appended, in the main transcript and up to three levels of `subagents/`. A byte filter picks
  the lines, and only `requestId`, `message.id`, `message.model`, the four `usage` counters and `timestamp` are
  decoded. Lines over 1 MiB are skipped, symbolic links are not opened, a single read is capped at 8 MiB. Each
  request counts once (a shared ring of 4096 ids per account).
- **Codex.** `RolloutLineScanner` recognises the kind of each line from its bytes and skips prompt, reply and tool
  content without decoding it; only numeric token lines go through `JSONDecoder`. `CodexSessionState` assembles the
  session: origin and model, approval policy, pending calls, the last turn (`task_complete` / `turn_aborted`, with
  its duration and time to first token) and tokens. Subagents keep the parent session “working” while their turn is
  open.
- **Codex waits.** “Waiting for approval” means the policy is not `never`, the user approves, and a call whose
  `sandbox_permissions` precede `require_escalated` has had no result for 2 s. “Waiting for input” is a pending
  `request_user_input`. **Limitation:** the log has no “approved” event, so an approved long-running command is
  indistinguishable from a pending prompt until its result arrives; after 60 s the wording softens to “waiting for
  approval or running a command”.
- **Health.** `AgentSession.health(now:)`: `quiet` after 6 min without an event while working, `longTurn` after
  25 min, `waitingLong` after 10 min of waiting.

## History (SQLite, schema v4)

`UsageHistoryStore` owns `history.sqlite` inside the `0700` data folder. The file is created `0600` before SQLite
opens it (WAL and shared memory inherit it), existing modes are tightened on open, and a symbolic link in place of
the database, `-wal`, `-shm` or `-journal` is refused. Tables:

- `limit_samples`, `last_state` — readings, and the latest reading per account together with its identity (the one
  place an email address is stored; **never exported**);
- `session_segments` — working and waiting stretches: account, session id, label, project folder, start, end
  (`NULL` while open) and `last_seen`;
- `token_usage` — tokens in 5-minute buckets by account, session, project folder and model;
- `collection_starts` — when live collection first began for an account;
- `collection_runs` — every collection run, with (v4) `ended_at`, `last_seen` and `end_reason`
  (`quit`, `sleep`, `disabled`, `crash`, `inferred`), so the timeline can tell a quiet stretch from one where
  nothing was collected;
- `schema_meta` — `min_reader_version`. A file written by a newer Codometer that still allows version-4 writers
  stays writable; one that does not is opened **read-only** and never written.

Migrations run one transaction per version. v3 removed session titles and full project paths from older rows; v4
back-fills the end of each historical run from the last evidence inside it.

Other rules: retention is the user's setting (7, 14, 35 or 90 days; 35 by default), pruned at launch and every 6 h;
open segments are never pruned; every query returns at most 5000 rows; deleting an account deletes its history.
`SegmentTracker` (pure) turns session lists into segments and never back-dates a start before the monitor started
or the Mac woke. `HistoryRecorder` writes everything in order on a background queue in 2 s batches, so handling an
event never waits for SQLite; a query flushes the queue first. At quit, `applicationShouldTerminate` waits up to
1 s for `TrackerEngine.stop()` synchronously — a deferred `.terminateLater` reply would never arrive, because the
main queue is not serviced while AppKit waits.

**Recovery.** A database that cannot be opened or is corrupt is moved aside and a fresh one is created; the app
says so in a notice and Diagnostics shows the state (working, rebuilt after damage, read-only, writes paused).

## Notifications

- `AlertEvaluator` (Core) watches every window of every bucket, honours a group's notification switches and the
  short-turn threshold, and keeps only the turn that actually ended in a “finished” alert.
- `AlertDeliveryPlanner` (Core, pure) decides what is shown: every notification has a deterministic identifier
  (`session.<account>.<session>` or `limit.<account>.<bucket>.<window>`), so a new event replaces the old one.
  Events collect for 1.5 s from the first (never extended, at most 64); three or more become one summary; “waiting
  for you” goes out at once. One sound per step, the most important one (out > waiting > threshold > finished >
  reset), skipped when it is no more important than one played in the last 3 s.
- `AlertPresenter` (App) renders the text (account name only, never an email address) and talks to
  `UNUserNotificationCenter`. “Waiting” notifications are tagged in `userInfo`, so they can be withdrawn even after
  a relaunch, while a “finished” notification with the same identifier is left alone. A click passes only an
  account id; `AppController` opens the pinned surface on it.

## Widget

- `Core/Widget`: `WidgetScope` (which accounts a kind shows — `CodometerLimits`, `CodometerClaude`,
  `CodometerCodex`), `WidgetSnapshot` (versioned `Codable`, including the language), `WidgetSnapshotBuilder`,
  `WidgetExportPolicy` and `WidgetTimeline` (the moments a countdown or freshness changes).
- `App/Services/WidgetExporter` publishes on every new engine state, on every settings save and on the 30 s clock
  tick. Publishing means an atomic write of `Widget/snapshot.json` (`0600` in a `0700` folder) plus
  `WidgetCenter.reloadTimelines(ofKind:)` for all three kinds. Identical content is skipped; significant changes at
  most once a minute; everything else at most once every 15 minutes; never more than 12 per hour.
- The extension (`Codometer.app/Contents/PlugIns/CodometerWidgets.appex`, entry point `_NSExtensionMain`) is
  sandboxed with one temporary exception: read-only access to `/Library/Application Support/Codometer/Widget/`
  relative to the home folder. App Groups are not used — they need a team id, which an ad-hoc signature has not
  got. The extension ages readings out itself after 30 minutes and renders countdowns with date formats rather
  than timers. `WidgetDiagnostics` logs one public line per request: the read result, counts and the snapshot's
  age — no names, addresses or percentages.
- `Scripts/build-app.sh` gives both binaries a new `CFBundleVersion` (seconds since 1970) on every build, assembles
  and signs in `build/.staging`, and swaps the bundle in with two renames while stopping the extension process
  around the swap. This exists because `chronod` keeps the extension alive between requests: a half-replaced
  bundle, a registered copy that no longer exists or a process from the previous build (“Bundle version did not
  match”) make its requests fail, and after a burst of failures it refuses to reload the widget for 24 hours.

## Service status (the only network feature)

`VendorStatusService` (Engine) polls every 10 minutes ± 10 % **only** while a surface that shows status is visible
and the conditions allow it (setting on, online, not Low Power Mode, not a constrained or expensive network). The
requests go through `StatusFeedClient` (Platform), the single file in the tree allowed to use `URLSession`: an
ephemeral session, an exact host allowlist (`status.claude.com`, `status.openai.com`), HTTPS only, no redirect off
the host, at most 256 KiB read, `User-Agent: Codometer`, nothing persisted. `VendorStatusParsing` (Core) maps the
two different JSON shapes onto one `ServiceStatus`. The setting is off by default, and with it off the app opens no
socket at all.

## Launch, lifecycle and the data folder

The order at launch is load-bearing:

1. **Where are we running from?** `AppLocationCheck` — a disk image, an App Translocation path or a read-only
   volume means a localized alert and a quit, before anything is written.
2. **Legacy migration.** `AppDirectories.migrateLegacyIfNeeded()` moves a folder left by the app's former name with
   one `renamex_np(…, RENAME_EXCL)` — only when the new folder does not exist at all, refusing symbolic links, and
   leaving the old folder untouched on failure. DEBUG builds never migrate the real folder, and a folder holding
   the marker file `.codometer-no-migrate` is refused.
3. **`prepare()`** creates the root and `probe/` with `0700`.
4. **The instance lock** (`flock` on `<root>/.lock`) is taken *after* the migration — a lock file created earlier
   would make the new root “exist” and the migration would silently skip. A second copy posts a distributed
   notification derived from the data root path (so isolated test instances never reach the user's app) and quits;
   a relaunched instance (`--relaunched-after <pid>`) waits up to 5 s for that pid to exit.
5. The engine, surfaces, status item, hot key, login item and widget export start.

`CODOMETER_DATA_ROOT` names an isolated data root for development and verification (absolute, inside
`~/Library/Caches/` or a temporary folder, no symbolic links). An isolated instance exports no widget snapshot,
posts no notifications, changes no login item and registers no global shortcut unless a scenario asks. An
unacceptable value is a launch error, never a silent fall back to the real data.

`CrashCapture` subscribes to MetricKit and keeps at most five payloads in `Diagnostics/`, listed in the Diagnostics
pane and never sent anywhere. `LoginItemService` reconciles the toggle with `SMAppService.status`. `MainMenu`
provides the standard App, Edit and Window menus, so ⌘C/⌘V and ⌘Q work in text fields.

## Process safety

`ProcessSpawning` (posix_spawn):

- a new process group, reset signal handlers, `POSIX_SPAWN_CLOEXEC_DEFAULT`;
- an environment built from scratch (`HOME`, `USER`, `PATH=/usr/bin:/bin:/usr/sbin:/sbin`, the locale) plus the
  profile variable;
- the fixed working directory `<data root>/probe`;
- a timeout → `SIGTERM` to the group → `SIGKILL` after 2 s; an output size cap;
- the pids of our own children are registered, so their sessions are never shown as the user's.

`TrustedExecutableLocator` verifies the signature (`anchor apple generic and certificate leaf[subject.OU] =
TEAMID`) before every launch, caching the result by inode, size and modification time.

## Settings

`SettingsStore` writes `settings.json` atomically with `0600`. **Every** field decodes leniently: missing or null
falls back to the default silently, an unknown enum or a failed validation falls back and adds a repair note that
the app shows once, one bad account or group drops only itself. `schemaVersion` stays `1`; a file that declares a
higher version is loaded **read-only** and never written back. An unreadable file is kept as
`settings.invalid-<date>.json` and the app starts with defaults plus a notice.

## Localization

All user-facing text lives in `CodometerL10n` as typed English and Russian tables, reached as `l10n.<area>.<phrase>`
and injected into SwiftUI through the environment. Numbers, durations, times and percentages go through
`l10n.format`. The widget reads its language from the snapshot. Details and rules: [LOCALIZATION.md](LOCALIZATION.md).

## Tests and lints

`Scripts/test.sh` runs the whole suite with Swift Testing — domain validation, pace and forecast, alert rules and
delivery, file tailing, process isolation, signature checks, SQLite and migrations, settings recovery, the `/usage`
and rollout parsers on real formats, Claude turns and transcripts, Codex approvals and tokens, geometry, the liquid
outline, the island state machine, deck layout and empty states, analytics, gaps, the card's menu and copy fit,
onboarding, diagnostics, widget scope and export policy, and formatting in both languages.

`CodometerSourceLintTests` runs inside that suite and scans `Sources/**` for policy and localization violations
(`try!`, `fatalError`, `print`, per-frame animation, `Bundle.module`, `URLSession` outside `StatusFeedClient`,
fixed-region locales, `UserDefaults` outside the language shim, Cyrillic outside `CodometerL10n`, literals in UI
APIs, and more). `Scripts/lint.sh` wraps them for the release gate and adds the shell and documentation rules.
Gated suites render PNGs in both languages when `CODOMETER_SNAPSHOT_DIR` is set.
