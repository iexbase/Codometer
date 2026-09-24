# Changelog

All notable changes to Codometer are recorded here. The format follows Keep a Changelog, and version numbers follow
Semantic Versioning.

Release notes written for people rather than for this file live in `docs/release-notes/`
([English](docs/release-notes/1.0.0.en.md), [Русский](docs/release-notes/1.0.0.ru.md)).

## [1.0.0] - 2026-09-23

The first public release. Codometer watches your Claude Code and Codex limits and the agents working for you, and
keeps them one glance away. Everything below is new, because everything before this was a private build.

### Added

- **The island** — a capsule at any screen edge with one ring per limit, which expands into a card: the main window
  as a big figure with its chart, tiles for the other windows, and the live agent sessions. It snaps to edges,
  fuses with the camera notch, and closes on Esc even while another app is in front.
- **The floating card** — the second presentation style: a small window you can drop anywhere, in four themes
  (Graphite, Liquid Glass, Midnight, Light) and two sizes, which minimizes to a pill. Exactly one of the two styles
  is on screen at a time; the menu bar item stays either way.
- **The strip** — a third way to show usage, one click away in Settings → Presentation: a wide bar you can move
  anywhere, with what’s left of the binding week on the left and one chip per limit window on the right (usage,
  reset, and how many accounts share it). It covers one account, every Claude account, every Codex account, or all
  of them.
- **Essentials first** — the island and the popover open on just the limits: every window with what’s used, what’s
  left and when it resets. Settings → Appearance → “When it opens” brings back the chart, pace, sessions and the
  timeline.
- **Menu bar item and popover** — a live ring with your highest usage, the same card on click, a menu on
  Control-click.
- **Desktop widgets** — “AI Limits” in three sizes plus “Claude” and “Codex” in two, with usage rings, the next
  reset and its countdown, and **AI Limits · Strip**, **Claude · Strip** and **Codex · Strip** (medium and large)
  with the week’s remainder as one big figure and a tile with a live countdown for every other window.
- **Multiple accounts and groups** — one profile folder per account (`CLAUDE_CONFIG_DIR` / `CODEX_HOME`), up to
  eight groups with their own notification switches, and a guided way to set up a second account.
- **Notifications** — usage thresholds, limit resets, “agent finished” with its turn time, and “agent is waiting
  for you”, with in-place replacement, grouping of events that arrive together, one sound per batch, and automatic
  withdrawal once an agent continues.
- **Analytics** — a timeline of session bars under the usage curve with reset marks and gaps where nothing was
  collected, and “Who used the limit” by project over 5 hours, 24 hours or 7 days.
- **Ring visuals** — a reset ceremony, a finishing checkmark, a forecast arc showing where usage lands by the
  reset, and a colour and monogram per account.
- **English and Russian**, English by default, switched in Settings → General → Language without a restart (macOS's
  own menus follow at the next launch). Every surface, notification, widget and VoiceOver label is localized.
- **Onboarding** — a six-step welcome guide on a fresh install that asks before it probes anything.
- **Data controls** — history retention (1 week, 2 weeks, 5 weeks or 3 months), export to JSON or CSV, and a
  two-step “Erase All Data” that says exactly what goes and what stays.
- **Diagnostics** — a system check over tools, profiles, files and permissions; per-account refresh history; the
  signatures of the provider tools; storage state; and locally kept crash reports (never sent anywhere).
- **Energy awareness** — refreshes slow down on battery, in Low Power Mode and when the Mac runs hot; live effects
  pause. Automatic, Always fresh and Save battery are the three modes.
- **Service status (opt-in, off by default)** — a note in the island and on the card when Claude Code or Codex is
  having problems, from the providers' public status pages. It is the only network access in the app.
- **Accessibility** — VoiceOver labels and values everywhere, durations spoken in words, custom actions for
  drag-only operations, and support for Reduce Motion, Reduce Transparency and Increase Contrast.
- **Packaging** — a signed DMG built by `Scripts/release.sh` or by GitHub Actions, with checksums, a build manifest
  and build provenance; Developer ID signing and notarization switch on automatically when credentials exist.

### Security

- Only signature-verified vendor tools are run (`claude` by Anthropic PBC, `codex` by OpenAI), in a new process
  group with a clean environment, a fixed empty working directory, a timeout and an output cap.
- Tokens, cookies and Keychain items are never read; Codex's `auth.json` is looked at by metadata only.
- Conversation content is never decoded or stored — only identifiers, counters and event types.
- Reads are bounded, symbolic links are refused rather than followed, the app's files are `0700`/`0600`, and the
  widget extension is sandboxed with one read-only exception for its snapshot folder.
- No listening ports, no telemetry, no update check, no crash upload. See [SECURITY.md](SECURITY.md) and
  [PRIVACY.md](PRIVACY.md).

### Known issues

- **Apple silicon only.** 1.0.0 has no Intel build.
- **The build is ad-hoc signed** (no Developer ID yet), so the first launch needs the Gatekeeper steps in the
  [README](README.md#getting-past-gatekeeper-on-an-unsigned-build), once per version.
- **Codometer must live in `/Applications`.** Any bundle under `/Volumes/` is treated as a disk image, so a copy
  kept on an external drive shows the “Move Codometer to Applications” alert and quits.
- **Widgets lag behind the island by design** — WidgetKit's reload budget means important changes within a minute
  and everything else within 15 minutes.
- **History is collected live only.** Nothing is reconstructed from older logs, so periods before the first launch,
  while Codometer was closed or while the Mac slept are shown as gaps rather than filled in.
- **“Who used the limit” is an estimate** (≈), derived from token counts between two observations.
- **Codex approvals are inferred from the log**, which has no “approved” event: an already-approved long command
  looks like a pending one until its result arrives, so after a minute the wording softens to “waiting for approval
  or running a command”.
- **Erase can report that something was left behind** if another program left a file in Codometer's data folder
  (a `.DS_Store` from Finder, for example). Everything Codometer wrote is deleted; remove the folder by hand if you
  want it gone.
- **The technical detail lines in Diagnostics, and the support report, are English in both languages**, by design:
  they are meant to be pasted into a bug report.
- **No auto-update and no update check.** Watch the releases page yourself.
- **No license has been chosen yet**, so this repository ships without a `LICENSE` file.

