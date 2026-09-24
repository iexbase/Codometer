# Releasing Codometer

How a Codometer version gets from the repository to a published GitHub release: what the two GitHub Actions
workflows do, what you run locally when the runner cannot do it, which secrets exist, and how to check that the
DMG built in CI is the same app you would have built on your Mac.

Codometer ships outside the Mac App Store: a DMG attached to a GitHub release, which people download and drag to
Applications. There is no auto-update and no telemetry, so a release is a file and a set of notes — nothing else
phones home afterwards.

- Install and Gatekeeper instructions for users live in the [README](../README.md).
- Everything the build itself does is in `Scripts/release.sh`; this document describes the release *process*
  around it.

---

## 1. The moving parts

| Piece | What it does |
|---|---|
| `Packaging/VERSION` | The single source of the version. `1.0.0` today. |
| `Packaging/toolchain.env` | Pins the Xcode a build uses. Both workflows read it. |
| `Scripts/release.sh` | The whole build, locally and on the runner: preflight, lints, tests, release products, bundle, signing, notarization, DMG, verification, artifacts. Twelve stages, each `PASS` / `FAIL` / `SKIP (reason)`. |
| `.github/workflows/ci.yml` | Runs on GitHub for every push and pull request: `Scripts/release.sh --ci --skip-dmg --allow-dirty`. No secrets, no DMG. |
| `.github/workflows/release.yml` | Runs on GitHub for every `v*.*.*` tag (and manual runs): the full build, then a published GitHub release. |

`Scripts/release.sh` writes everything into `dist/<version>/`:

| File | Public asset? | Notes |
|---|---|---|
| `Codometer-<version>.dmg` | yes | The same name in every signing mode. The mode is recorded inside `build-info.json` and in the release notes, not in the file name. |
| `SHA256SUMS.txt` | yes | Plain `shasum -a 256` format, so `shasum -c SHA256SUMS.txt` works. |
| `release-notes.md` | body | Used as the GitHub release body (English, Russian under a `<details>` block). |
| `build-info.json` | no | Version, build number, signing mode, notarization, Xcode and Swift versions, SDK, commit, architecture, sizes. |
| `bundle-manifest.txt` | no | Relative path + SHA-256 of every file in the app except `_CodeSignature`. This is what "identical build" is measured on (§7). |
| `Codometer-<version>-*dSYMs.zip` | **no** | Keep it for symbolicating crash and MetricKit reports. Never a release asset: a locally built dSYM embeds `/Users/<name>/…` paths. The CI copy rides along as a workflow artifact, which on a public repository is *not* a private place (§4). |
| `logs/` | no | One log per stage, including the notary JSON. |

---

## 2. Before you tag

1. `Packaging/VERSION` holds the new version (`MAJOR.MINOR.PATCH`).
2. `CHANGELOG.md` has a `## [<version>]` heading, and `docs/release-notes/<version>.en.md` and
   `docs/release-notes/<version>.ru.md` exist and are not empty. `release.sh` checks all three and fails without them.
3. `Scripts/test.sh` is green and `Scripts/lint.sh` passes locally.
4. The working tree is clean. The release workflow builds the tagged commit, not your desktop.
5. Decide the open questions that end up in the artifacts: the license (`LICENSE`, currently absent — `release.sh`
   warns), the bundle identifiers in `Packaging/identity.env` (they key widgets, notifications, the login item and
   preferences; changing them after 1.0.0 orphans all four), and `CODOMETER_REPOSITORY` in the same file.
6. Push the commit, wait for CI to be green, then tag:

   ```bash
   git tag -a v1.0.0 -m "Codometer 1.0.0"
   git push origin v1.0.0
   ```

   The tag must match `Packaging/VERSION`; the workflow refuses `v1.0.1` when VERSION says `1.0.0`.

---

## 3. What CI does on every push

`.github/workflows/ci.yml`, on `macos-26`:

1. Checks out the repository.
2. Selects the Xcode pinned in `Packaging/toolchain.env` (§6).
3. Prints `sw_vers`, `xcodebuild -version` and `swift --version`.
4. Runs the one command a maintainer runs locally:

   ```bash
   Scripts/release.sh --ci --skip-dmg --allow-dirty
   ```

   That is preflight, plist and shell lints, the policy lint, the full Swift Testing suite, both release products,
   the assembled bundle, ad-hoc signing and the bundle gates — everything except the DMG, notarization and the
   performance smoke test.
5. Uploads `dist/*/logs/**`, `bundle-manifest.txt` and `build-info.json` as a workflow artifact (14 days).

CI never sees a secret, never creates a release and never touches a keychain. The performance smoke test
(`Scripts/perf-smoke.sh`) stays local: a runner has no Claude Code or Codex data to poll.

---

## 4. Releasing from CI

`.github/workflows/release.yml` runs on a `v*.*.*` tag, or manually from the Actions tab (choose a tag there to
publish; a manual run on a branch builds artifacts only and creates no release). One release runs at a time
(`concurrency: release`).

1. Checkout with full history — `release.sh` reads the tag and the tagged commit's time for the build number.
2. Xcode selection, **strict**: no pinned Xcode on the image means the run fails (§6).
3. Version resolution: `Packaging/VERSION`, and for a tag, that the tag is `v<version>`.
4. Secret detection. Only booleans leave this step; nothing is printed.
5. With a certificate secret: a temporary keychain in `$RUNNER_TEMP` with a random password, the `.p12` decoded
   with `umask 077`, imported for `codesign`, and deleted right after the import.
6. With an API key secret: the `.p8` written to `$RUNNER_TEMP` (mode 0600) and its path handed to `release.sh`.
7. The build:

   ```bash
   Scripts/release.sh --ci [--require-notarization] [--allow-toolchain-mismatch]
   ```

   `--require-notarization` is added when a certificate **and** a set of notary credentials exist, so a silent
   "SKIP (no credentials)" can never slip into a signed release.
8. Artifact collection: exactly one DMG in `dist/<version>/`, plus `SHA256SUMS.txt`, `release-notes.md` and
   `bundle-manifest.txt`. The checksums and `build-info.json` are copied into the run summary.
9. `actions/attest-build-provenance` signs a provenance statement for the DMG (§8).
10. `gh release create "$TAG" --latest …` with the DMG and `SHA256SUMS.txt`, published at once. A re-run of the
    same tag replaces the assets instead of failing.
11. dSYMs, logs, `bundle-manifest.txt` and `build-info.json` go up as a workflow artifact (90 days), never as
    release assets. On a **public** repository a workflow artifact is not private: anyone with a GitHub
    account can download it. No credential is written into any of these files — `release.sh` keeps notary
    arguments in memory and the workflow never writes a secret to disk outside `$RUNNER_TEMP` — but treat the
    contents as published, and download the dSYM before it expires rather than leaving it as your only copy.
12. `if: always()`: the temporary keychain is deleted, the search list restored, and the `.p12`/`.p8` files removed.

### Checking the release

1. Open the release. Check the title, the notes (English and Russian) and that exactly the DMG and
   `SHA256SUMS.txt` are attached.
2. Download the DMG, verify it, and install it once from `/Applications`:

   ```bash
   shasum -c SHA256SUMS.txt
   gh attestation verify Codometer-1.0.0.dmg -R iexbase/Codometer
   hdiutil attach -readonly -nobrowse Codometer-1.0.0.dmg     # prints the mount point, e.g. /Volumes/Codometer 1.0.0
   volume="/Volumes/…"                                        # what the line above printed
   codesign --verify --strict --deep --verbose=2 "$volume/Codometer.app"
   spctl -a -t exec -vv "$volume/Codometer.app"                # "rejected" is expected for an ad-hoc build
   hdiutil detach "$volume"
   ```

   Do not launch the app from the mounted image: Codometer refuses to run from a disk image or a translocated
   path on purpose. Drag it to `/Applications` first.

3. Optionally diff the manifest against a local build (§7).
4. Publish. Keep the dSYM artifact somewhere private before it expires.

---

## 5. Releasing locally (the fallback)

Use this when the runner image has no usable Xcode, when the GitHub Actions status page is unhappy, or when you
simply want the release on your own Mac.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer   # or the pinned Xcode
Scripts/release.sh                                                # add --require-notarization with credentials
```

The result lands in `dist/<version>/`. Then create the same release by hand:

```bash
gh release create v1.0.0 --latest --title "Codometer 1.0.0" \
  --notes-file dist/1.0.0/release-notes.md \
  dist/1.0.0/Codometer-1.0.0.dmg dist/1.0.0/SHA256SUMS.txt
```

A locally built DMG carries no GitHub provenance attestation, so say in the release notes that the checksums are
the only verification for that build.

Useful flags:

| Flag | Meaning |
|---|---|
| `--version X.Y.Z` | Build a version other than `Packaging/VERSION` (rare; the file stays the source of truth). |
| `--out <dir>` | Write artifacts somewhere other than `dist/`. |
| `--skip-dmg` | Stop after the bundle gates. What CI uses. |
| `--allow-dirty` | Do not require a clean tree. What CI uses. |
| `--allow-toolchain-mismatch` | Build with an Xcode other than the pinned one. |
| `--require-notarization` | Turn every notarization skip into a failure. |
| `--perf` | Run the performance smoke test (local only). |
| `--ci` | Non-interactive output, no colours, no prompts. |

`Scripts/release.sh --help` is the authoritative list. The workflows depend on five of these only: `--ci`,
`--skip-dmg`, `--allow-dirty`, `--allow-toolchain-mismatch` and `--require-notarization`.

---

## 6. The pinned toolchain

`Packaging/toolchain.env` pins the toolchain a release is built with. The workflows read (they parse the file,
they never source it):

| Key | Example | Used for |
|---|---|---|
| `XCODE_APP` | `/Applications/Xcode_26.6.app` | First choice of Xcode. Optional: without it the workflows look for `/Applications/Xcode_<version>.app`. |
| `XCODE_VERSION` | `26.6` | Must match `xcodebuild -version`. |
| `XCODE_BUILD` | `17F113` | Must match the build line of `xcodebuild -version`. |
| `SWIFT_MIN` | `6.2` | Checked by `Scripts/release.sh` in its preflight stage, not by the workflows. |

The workflows read the three `XCODE_*` keys with or without a `CODOMETER_` prefix (`CODOMETER_XCODE_VERSION`
works as well). Any other key in the file — deployment target, architectures, the runner image — belongs to
`Scripts/release.sh` and is ignored here.

| Situation | `ci.yml` | `release.yml` |
|---|---|---|
| Pinned Xcode present | uses it | uses it |
| Pinned Xcode missing, another Xcode 26.x present | uses the newest 26.x and prints a **warning** | **fails**, pointing here |
| `toolchain.env` pins no Xcode at all | uses the newest 26.x and prints a **warning** | **fails**: a release names its toolchain |
| No Xcode 26.x at all | fails (Codometer needs the macOS 26 SDK) | fails |

To release anyway from a runner without the pinned Xcode, start `release.yml` from the Actions tab with
**allow_toolchain_mismatch** enabled. The run then warns, passes `--allow-toolchain-mismatch` to `release.sh`, and
its artifacts are no longer comparable with a local build (§7). The cleaner path is the local fallback in §5.

---

## 7. What "the same DMG" means

The pipeline aims for *the same app*, not a byte-identical container: build paths enter Mach-O debug maps, ad-hoc
and Developer ID signatures differ by design, and `hdiutil` stamps every image with fresh UUIDs and timestamps.

The contract is: **the same `bundle-manifest.txt`, for the same commit, the same `Packaging/VERSION` and the same
build number, with binaries and signatures excepted.** `release.yml` uploads its manifest as a workflow artifact
for exactly this comparison.

```bash
# 1. Read the build number the CI run used (build-info.json comes with the CI artifact).
jq . dist/1.0.0/build-info.json                # it records the build number release.sh used

# 2. Build the same commit locally with that build number.
git checkout v1.0.0
CODOMETER_BUILD_NUMBER=<that number> Scripts/release.sh --out /tmp/codometer-local

# 3. Compare.
diff <(sort ci-artifact/bundle-manifest.txt) <(sort /tmp/codometer-local/1.0.0/bundle-manifest.txt)
```

Resources, plists, the icon and the localizations must match exactly. Differences limited to
`Contents/MacOS/Codometer` and `…/CodometerWidgets` are expected. Anything else — a missing `.lproj`, a different
`Assets.car`, an extra file — is a real difference worth investigating before publishing.

---

## 8. Provenance

For an ad-hoc build there is no Apple signature to trust, so `release.yml` attests the DMG with
`actions/attest-build-provenance`: a signed statement that this artifact came from this repository, workflow and
commit. Anyone can check it:

```bash
gh attestation verify Codometer-1.0.0.dmg -R iexbase/Codometer
```

This needs `id-token: write` and `attestations: write`, which the workflow declares and nothing else uses.

---

## 9. Secrets

All optional. Missing secrets simply mean an ad-hoc build, which is the mode Codometer ships in until there is a
Developer ID. Add them under **Settings → Secrets and variables → Actions → New repository secret**. They are
never committed, never printed, never written to the workflow log, and every step that touches one runs with
`set +x`; derived values (the temporary keychain password) are registered with `::add-mask::`.

| Secret | What it is | Needed for |
|---|---|---|
| `CODOMETER_DEVELOPER_ID_P12_BASE64` | `base64 -i DeveloperID.p12` — the Developer ID Application certificate **and** its private key | Developer ID signing |
| `CODOMETER_DEVELOPER_ID_P12_PASSWORD` | The password you chose when exporting the `.p12` | Developer ID signing |
| `CODOMETER_SIGN_IDENTITY` | Optional. The exact identity string, e.g. `Developer ID Application: Jane Doe (ABCDE12345)`. Set it when the keychain holds more than one; if it is set and not found, the build **fails** instead of silently signing ad hoc | Developer ID signing |
| `CODOMETER_NOTARY_KEY_ID` | App Store Connect API key id | Notarization (API key) |
| `CODOMETER_NOTARY_ISSUER_ID` | App Store Connect issuer id (a UUID) | Notarization (API key) |
| `CODOMETER_NOTARY_KEY_P8_BASE64` | `base64 -i AuthKey_XXXX.p8` | Notarization (API key) |
| `CODOMETER_NOTARY_APPLE_ID` | Apple ID e-mail | Notarization (Apple ID, alternative) |
| `CODOMETER_NOTARY_APP_PASSWORD` | App-specific password for that Apple ID | Notarization (Apple ID, alternative) |
| `CODOMETER_NOTARY_TEAM_ID` | Team id | Notarization (Apple ID, alternative) |

Either notary set works; the API key is preferred (it is revocable and not tied to a person). Notarization is
*required* by the workflow only when a certificate and a full notary set are both present.

Half-configured repositories are called out instead of quietly downgrading the build:

- `CODOMETER_DEVELOPER_ID_P12_BASE64` present, its password secret absent → the run warns and imports the
  `.p12` with an empty password (a legitimate export option). A wrong password fails the import step; it never
  falls back to an ad-hoc signature.
- Notary secrets present, the certificate secret absent → the run warns and stays ad hoc. Apple notarizes
  Developer ID signed code only, so there is nothing to notarize.

Locally you do not need any of this in the environment: keep the certificate in your login keychain and store the
notary credentials once with

```bash
xcrun notarytool store-credentials Codometer --apple-id <you> --team-id <team> --password <app-specific>
export CODOMETER_NOTARY_PROFILE=Codometer
```

### Getting a Developer ID (when you decide to)

1. Join the Apple Developer Program. The Account Holder creates the **Developer ID Application** certificate.
2. Export it with its private key as a `.p12`.
3. Create an App Store Connect API key with the Developer role (or an app-specific password).
4. Add the secrets above. Nothing in the scripts or workflows changes: the mode resolves automatically.

Until then the DMG is ad hoc, users see Gatekeeper's "Apple could not verify…" dialog, and the README explains the
"Open Anyway" route honestly.

---

## 10. Troubleshooting

| Symptom | What happened | What to do |
|---|---|---|
| `Pinned toolchain missing` in `release.yml` | The runner image moved on from the pinned Xcode | Re-run with **allow_toolchain_mismatch**, or release locally (§5), or update `Packaging/toolchain.env` after checking the new Xcode locally |
| `Tag does not match VERSION` | The tag and `Packaging/VERSION` disagree | Fix one of them; delete and re-push the tag |
| `Unexpected DMG count` | `dist/<version>/` holds zero or several DMGs | Look at the `08-dmg` stage log in the run artifact |
| Notarization `Invalid` | Apple rejected the submission | `xcrun notarytool log <submission-id>` — the stage log holds the id; usual causes are a missing hardened runtime or an unsigned nested binary |
| `No Developer ID identity` | The `.p12` decoded but holds no signing identity | Re-export the certificate **with** its private key |
| The DMG came out ad hoc although the secrets exist | `CODOMETER_DEVELOPER_ID_P12_BASE64` is missing or empty | The `Detect signing and notary secrets` step prints the mode it chose and warns about a half-configured set (§9) |
| The release run finished but there is no release | The run was not on a tag | Dispatch it again with a tag selected, or push the tag |
| `gh release create` says the release exists | A previous run already created the release | Nothing: the workflow uploads over it. Delete the release to start clean |
| CI fails only on the runner | Almost always the toolchain warning above it, or a test that depends on the system language | Reproduce with `Scripts/release.sh --ci --skip-dmg --allow-dirty` locally |

---

## 11. House rules

- A green release run publishes the release; check it right after (see “Checking the release”).
- dSYMs are never a release asset — and a workflow artifact on a public repository is not a private place
  either (§4).
- The DMG keeps the same public name in every signing mode; the mode lives in `build-info.json` and the notes.
- Tags are created by a person, never by a script or an agent.
- No secret is ever echoed, written into a file that is uploaded, or put into a step output.
