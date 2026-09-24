# Security

Codometer reads the local files of two AI coding tools and runs their own commands. That is a sensitive place to
stand, so this page says what the app does to stay trustworthy, what it deliberately does not do, and how to report
a problem.

## Supported versions

| Version | Supported |
|---|---|
| The latest release | Yes |
| Anything older | No — upgrade first |

There is only one active line. Fixes go into the next release; there are no backports.

## Reporting a vulnerability

**Please report privately first, not in a public issue.**

1. Use GitHub's private vulnerability reporting on this repository: the **Security** tab → **Report a
   vulnerability**. It creates a private advisory that only the maintainer can see.
2. If that is not available to you, open a public issue that says only *“I have a security report, how can I send
   it privately?”* — with no details, no proof of concept and no paths.

Useful in a report: what an attacker needs (local account, a file they control, a downloaded build), what they get,
the Codometer version and build number (Settings → General → About), your macOS version, and the smallest set of
steps that shows it. A sanitized **Copy Report** from Settings → Diagnostics is welcome; it contains no email
addresses, project names or home folder paths.

What to expect: this is a small project maintained by one person, so the honest promise is an acknowledgement as
soon as it is seen and a fix in the next release for anything real. Please give a fix a reasonable chance to ship
before publishing details. There is no bounty programme.

## Threat model

**Codometer assumes** that your user account and the tools it reads are not already compromised, and that macOS's
own protections (file permissions, TCC, Gatekeeper, the app sandbox for the widget) are intact.

**It defends against**

- *A look-alike CLI on your `PATH`.* Every executable is signature-verified before it is run: `claude` must be
  signed by Anthropic PBC (team `Q6L2SF6YDW`), `codex` by OpenAI (team `2DC432GLL2`). The check is per launch and
  keyed to the file's inode, size and modification time, so a swapped file is re-checked.
- *A hostile or corrupt file in a profile folder.* Reads are bounded (single lines over 1 MiB are skipped, reads
  are capped, a `.claude.json` over 16 MiB is refused), decoding is limited to a whitelist of numeric and
  identifier fields, and malformed input degrades to “no data” rather than to a crash or to a partial write.
- *Symlink tricks.* Codometer does not follow symbolic links when it reads profiles, migrates its data folder,
  exports, or erases. A symlink where a folder or a database file is expected is refused, and the operation stops.
- *Data leaking out sideways.* Its own files are `0700`/`0600`. Exports and the diagnostics report exclude email
  addresses, session titles and home folder paths by construction, not by filtering after the fact. Logs carry
  counters and states, never content.
- *A second copy or a stale registration causing surprises.* One instance at a time (an `flock` on `.lock`,
  taken after the data folder is in place); a second copy tells the first to open Settings — through a
  notification name derived from the data folder path, so isolated test instances can never reach your app — and
  quits.
- *Running from the wrong place.* Started from a disk image, a translocated copy or a read-only volume, Codometer
  shows an alert and quits before it migrates, locks, polls, writes a widget snapshot or registers a login item.

**It does not defend against**

- An attacker who already runs code as your user. They can read the same files Codometer reads, and more.
- Anything inside Claude Code or Codex themselves. Report those to Anthropic or OpenAI.
- A malicious build you downloaded from somewhere other than this repository's releases — see below.
- Someone reading your screen. That is what the email masking setting is for (Settings → Appearance → Privacy).

## Design commitments

- **No network unless you ask.** With Settings → General → Network → Show service status off (the default), the app
  opens no socket. With it on, HTTPS to exactly `status.claude.com` and `status.openai.com`, ephemeral session, no
  cookies, redirects off the host refused, at most 256 KiB read, nothing persisted. No telemetry, no update check,
  no crash upload. Details in [PRIVACY.md](PRIVACY.md).
- **No listening ports, ever.** The Codex app server is a child process spoken to over pipes, not a socket.
- **No credentials.** Tokens, cookies and Keychain items are never read; `auth.json` is looked at by metadata only.
- **Child processes are contained.** New process group, environment built from scratch, a fixed empty working
  directory, a timeout, an output cap, and the whole group is terminated when the run ends.
- **The widget extension is sandboxed** with one temporary exception: read-only access to
  `~/Library/Application Support/Codometer/Widget/`. It has no network entitlement and no other file access.
- **No code is loaded from outside the bundle.** There are no plug-ins, no scripting bridge, no `eval`-like path,
  and no third-party dependencies in the build.
- **Release builds** are signed with the hardened runtime and — once a Developer ID exists — notarized and stapled.

## Verifying a download

Get the DMG from this repository's releases and nowhere else. Each release carries `SHA256SUMS.txt`:

```bash
cd ~/Downloads && shasum -a 256 -c SHA256SUMS.txt --ignore-missing
```

Builds produced by the release workflow also carry a GitHub build provenance attestation:

```bash
gh attestation verify Codometer-1.0.0.dmg --repo iexbase/Codometer
```

**1.0.0 is ad-hoc signed**: it has no Developer ID and is not notarized, so macOS cannot tell you who built it and
the first launch needs the steps in the [README](README.md#getting-past-gatekeeper-on-an-unsigned-build). That is a
real reduction in what Gatekeeper can do for you — the checksum and the provenance attestation are what stands in
its place until a Developer ID is in use. Never bypass quarantine on a build whose checksum you have not compared.
