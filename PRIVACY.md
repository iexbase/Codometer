# Privacy

**Codometer 1.0.0 · [Русская версия](PRIVACY.ru.md)**

Codometer is a local app. It reads what Claude Code and Codex already write on your Mac, keeps a small history of
it on the same Mac, and shows it to you. There is no account, no sign-up, no server of ours, no analytics and no
crash reporting. This page says exactly what that means, file by file.

If anything here disagrees with what the app tells you, the app is the one that is wrong — please report it.

---

## 1. What Codometer reads

### Claude Code profiles (`~/.claude`, `~/.claude-<name>`)

| File | What is read | What is ignored |
|---|---|---|
| `.claude.json` | The account metadata Claude Code stores: email address, organisation name, plan tier. This is what the account badge and the plan label show. | Everything else in the file. Credentials are not in it — they are in the Keychain, which Codometer never touches. |
| `sessions/<pid>.json` | Session status (working, waiting, ready), what it is waiting for, whether it started in a terminal or an app, and the timestamps. | — |
| `projects/**/*.jsonl` (transcripts, including `subagents/`) | Only `requestId`, `message.id`, `message.model`, the four `message.usage` counters (input, output, cache creation, cache read) and `timestamp`. | The message text. Prompts, replies, tool input and tool output are never decoded: a byte filter skips those lines before any JSON parsing happens. Lines longer than 1 MiB are skipped entirely. |

### Codex profiles (`~/.codex`, `~/.codex-<name>`)

| File | What is read | What is ignored |
|---|---|---|
| `sessions/**/rollout-*.jsonl` | Event types and numbers: rate limits, session status, turn start and end, the approval policy, pending calls, token counts. Only newly appended bytes are read. | Prompt, reply, reasoning and tool-call content. The line scanner recognises the kind of line from its bytes and skips the ones it does not need without decoding them. |
| `auth.json` | Nothing. Only its metadata (does it exist, when did it change) — the file is never opened. | The credentials in it. |
| `config.toml`, `sessions/` | Their existence, to recognise a profile folder. | — |

Codometer also asks the two CLIs for the numbers they publish for exactly this purpose: Claude Code's `/usage`
command and `codex app-server`'s `account/rateLimits/read` request (§5 has the exact command lines). The Codex
reply carries the account email and plan; the Claude command returns only limits.

### Everything else

Codometer reads its own settings and history file, the list of connected displays, the system's power and thermal
state, whether the network is reachable, and the notification and login-item permissions macOS reports. That is
all.

---

## 2. What Codometer never reads or stores

- **Tokens, API keys, passwords, cookies, Keychain items.** They are never opened, never copied and never sent.
  Requests to Anthropic and OpenAI are made by their own CLIs, with their own credentials, over their own
  connections.
- **Conversation content.** Not prompts, not replies, not reasoning, not tool input or output, not file contents
  quoted inside a session. Nothing of that kind is decoded, held in memory or written down.
- **Session titles.** Claude derives a session's title from the conversation, so it can repeat what you wrote.
  Codometer never stores one. In history a session is `<project folder> · <last six characters of its id>`. A
  title you see in the live card comes from memory and is never written to disk.
- **Absolute paths of your projects.** History stores only the last path component (the project folder's name), so
  your home folder name is not in the file.
- **Anything outside the folders above.** No Spotlight, no browser data, no other app's files, no screen contents.

Codometer also never writes into a Claude Code or Codex profile folder, and never changes their configuration.

---

## 3. What is stored, where, and for how long

Everything lives in `~/Library/Application Support/Codometer`. The folder is created with `0700` permissions and
files with `0600`, so only your user account can read them. Symbolic links in these paths are refused rather than
followed.

| Path | Contents | Kept for |
|---|---|---|
| `settings.json` | Accounts (your names for them and their profile paths), groups, and every preference. Not passwords, not emails. | Until you change or erase them |
| `settings.invalid-<date>.json` | A copy of a settings file that could not be read, kept so nothing is lost silently. | Until you delete it |
| `history.sqlite` (+ `-wal`, `-shm`) | Limit readings; session segments (account, session id, project folder name, working or waiting, start and end); token counts in 5-minute buckets (session, project folder, model, numbers); when collection was running. Plus one `last_state` row per account with its most recent reading **and its identity (name, email, plan)**, so the app can show something before the first refresh. | **Your retention setting**: 1 week, 2 weeks, 5 weeks (the default) or 3 months. Older rows are deleted automatically; shortening the setting deletes them at once. Removing an account deletes its history. |
| `Widget/snapshot.json` | Exactly what the widget draws: account names, limit windows, counts, and the email address only if your privacy setting shows it. | Replaced on each publish; deleted when you turn the widget data off |
| `Diagnostics/*.json` | MetricKit crash and hang payloads (binary UUIDs, addresses, stack traces of Codometer itself). | The 5 most recent, then the oldest is deleted |
| `probe/` | An empty working folder the CLI commands are run in, so they never leave project state behind. | Always empty |
| `.lock` | The single-instance lock file. | — |

Two more things belong to macOS rather than to Codometer:

- `~/Library/Containers/com.codometer.Codometer.Widgets/` — the sandbox container of the widget extension, with
  WidgetKit's rendered archives. macOS removes it with the app's data on its own schedule; you can delete it by
  hand.
- The app's preferences domain (`com.codometer.Codometer`) — the interface language and the Settings window
  position. `defaults delete com.codometer.Codometer` removes it.

One side effect worth naming: Claude Code creates an empty folder for every working directory it is started in, so
you will find an empty `…-Codometer-probe` folder under `~/.claude*/projects/`. It holds nothing and can be
deleted.

---

## 4. Network

**Codometer makes no network requests at all** unless you turn on one setting:

> Settings → General → Network → **Show service status** — off by default.

With it on:

- The two hosts asked are `status.claude.com` (`/api/v2/summary.json`) and `status.openai.com`
  (`/api/v2/components.json`) — the providers' public status pages, the same ones a browser would load.
- A check happens every 10 minutes (± a little), **and only while a surface that shows the status is visible**: the
  expanded island, the card, or the menu bar popover. Nothing polls in the background.
- Checks stop in Low Power Mode, when the Mac is offline, and on networks macOS marks as constrained or expensive.
- The request is an ordinary HTTPS GET with the `User-Agent: Codometer` header — no version, no identifier, no
  query parameters, no cookies (the session is ephemeral), nothing about your accounts, your usage or your Mac.
  Those sites see the request and, like every web server, the IP address it came from.
- Only HTTPS to those two exact hosts is allowed, redirects that leave the host are refused, at most 256 KiB of the
  answer is read, and nothing from it is written to disk.

There is **no telemetry, no analytics, no update check, no crash upload and no license or activation call** — with
the status check off, Codometer opens no socket at all, which you can verify with `nettop` or `lsof`.

The only other way Codometer touches the network is when you ask it to: a link in the app (a provider's status
page, for example) opens in your browser.

---

## 5. Processes Codometer runs

Codometer runs two commands, both of them yours:

- `claude --print --no-session-persistence --strict-mcp-config /usage` — Claude Code's own usage command, which is
  local and does not consume model usage
- `codex app-server` — the local JSON-RPC server Codex ships, asked for `account/rateLimits/read`

Before each launch the executable's code signature is verified: `claude` must be signed by Anthropic PBC (team
`Q6L2SF6YDW`), `codex` by OpenAI (team `2DC432GLL2`). A look-alike binary placed earlier in your `PATH` is not
executed. Each run gets a new process group, a clean environment (`HOME`, `USER`, a fixed `PATH`, the locale and
the profile variable), the empty `probe/` working folder, a timeout and an output limit, and is terminated as a
group when it ends or overruns.

If Claude Code's usage output stops looking like usage output three times in a row, Codometer stops running the
command until you ask for a refresh by hand — so it can never turn into a model request that costs you tokens.

---

## 6. Logs

Codometer writes to the macOS unified log under the subsystems `com.codometer.app` and `com.codometer.widgets`.
These entries stay on your Mac like any other system log, and they are written to be safe to share: counters,
states and error kinds, with no email addresses, session titles, prompts, project paths or home folder names. The
widget's line, for example, says whether the snapshot was loaded, missing, denied or invalid, how many accounts it
had, and how old it was — nothing about their contents.

---

## 7. What you can take out, and how to remove everything

**Export** — Settings → General → History & Data → **Export History…** writes either one JSON file or a folder of
CSV files (`limits.csv`, `sessions.csv`, `tokens.csv`, `collection-runs.csv`, plus a `README.txt` that explains
them). Times are ISO 8601 with your time zone's offset, numbers use a dot, column names are English. **Email
addresses are never exported**, and neither are session titles or prompts: the `last_state` row that holds the
account identity is not part of an export.

**Diagnostics** — Settings → Diagnostics → **Copy Report** and **Export Diagnostics…** produce an English support
text with no email addresses, no project or session names and no home folder path (`~` is used instead). A saved
file never carries account names at all; copy the report if you need them for a bug report.

**Erase** — Settings → General → History & Data → **Erase All Data…** deletes everything Codometer stored: the
history and the timeline, settings, accounts and groups, the widget data, the notifications it has delivered, and
the login item. It leaves your Claude Code and Codex profiles, your sign-ins and logs, anything you already
exported, and the app itself. It then quits or starts over as a fresh install, whichever you choose. It cannot be
undone, and the sheet offers to export first.

Deleting the app itself and its leftovers is described in the [README](README.md#uninstall).

---

## 8. Who sees anything

Nobody but you, unless you share it.

- Codometer has no server and no account system. The author receives nothing — no usage data, no crash reports, no
  email addresses.
- The only third parties in the picture are Anthropic and OpenAI, who see what their own CLIs do with your account
  as they always have, and — only if you turn the status check on — the two public status pages, which see a
  request from your IP address.
- What leaves your Mac is what you export or copy and then send somewhere yourself.

---

## 9. Changes

This document describes Codometer 1.0.0. Any change to what is read, stored or sent will be listed in
[CHANGELOG.md](CHANGELOG.md) and in the release notes for the version that changes it.

Questions or a mistake in this page: see [SECURITY.md](SECURITY.md) for how to reach us.
