#!/usr/bin/env bash
# The single gate between the working tree and a public Codometer release.
#
#   Scripts/release.sh [--version X.Y.Z] [--out <dir>] [--require-notarization] [--allow-dirty]
#                      [--allow-toolchain-mismatch] [--skip-dmg] [--perf] [--ci]
#                      [--allow-missing-icon] [--allow-missing-docs]
#
# Twelve stages, each one printing PASS, FAIL, SKIP (with a reason) or WARN per check and writing its own
# log under <out>/<version>/logs. The first failing stage stops the run; a warning never does, but every
# warning is repeated in the summary, because a release note nobody reads is the same as no release note.
#
# The signing mode is resolved from the machine, not chosen here: no identity gives an ad-hoc build, an
# identity without notary credentials gives a signed-but-not-notarized build, and both together give the
# real thing. `--require-notarization` turns every skip in the signing and notarization stages into a
# failure, which is what the release workflow uses once the secrets exist.
#
# Secrets are read into memory and never printed: `set +x` guards every command that receives them, and no
# credential is ever written to a stage log.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
# shellcheck source=lib/common.sh
source Scripts/lib/common.sh
# shellcheck source=lib/sign.sh
source Scripts/lib/sign.sh
# shellcheck source=lib/notarize.sh
source Scripts/lib/notarize.sh
# shellcheck source=lib/dmg.sh
source Scripts/lib/dmg.sh
resolve_developer_dir
# shellcheck source=../Packaging/identity.env
source Packaging/identity.env

# --- options --------------------------------------------------------------------------------------

OUT="dist"
VERSION_OVERRIDE=""
REQUIRE_NOTARIZATION=0
ALLOW_DIRTY=0
ALLOW_TOOLCHAIN_MISMATCH=0
SKIP_DMG=0
RUN_PERF=0
CI_MODE=0
ALLOW_MISSING_ICON=0
ALLOW_MISSING_DOCS=0

while (($# > 0)); do
  case "$1" in
    --version) VERSION_OVERRIDE="${2:-}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    --require-notarization) REQUIRE_NOTARIZATION=1; shift ;;
    --allow-dirty) ALLOW_DIRTY=1; shift ;;
    --allow-toolchain-mismatch) ALLOW_TOOLCHAIN_MISMATCH=1; shift ;;
    --skip-dmg) SKIP_DMG=1; shift ;;
    --perf) RUN_PERF=1; shift ;;
    --ci) CI_MODE=1; shift ;;
    --allow-missing-icon) ALLOW_MISSING_ICON=1; shift ;;
    --allow-missing-docs) ALLOW_MISSING_DOCS=1; shift ;;
    -h|--help) print_header_help "$0"; exit 0 ;;
    *) die "unknown option: $1" 64 ;;
  esac
done

if ((REQUIRE_NOTARIZATION == 1)); then
  # These two flags are for trial builds of an unfinished release. A build that is going to be notarized and
  # published is not allowed to use them.
  ((ALLOW_MISSING_ICON == 0)) || die "--allow-missing-icon cannot be combined with --require-notarization" 64
  ((ALLOW_MISSING_DOCS == 0)) || die "--allow-missing-docs cannot be combined with --require-notarization" 64
fi
if ((CI_MODE == 1)); then
  # Non-interactive: no colour (a log file is not a terminal) and no performance run — a runner has no
  # Claude or Codex data to measure against.
  RUN_PERF=0
  C_RESET=''; C_BOLD=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_DIM=''
fi

VERSION="${VERSION_OVERRIDE:-$(read_version "$ROOT")}"
is_semver "$VERSION" || die "--version: \"$VERSION\" is not X.Y.Z"
BUILD_NUMBER="$(resolve_build_number "$ROOT")"

case "$OUT" in /*) DIST="$OUT/$VERSION" ;; *) DIST="$ROOT/$OUT/$VERSION" ;; esac
LOGS="$DIST/logs"
WORK="$DIST/.work"
rm -rf "$WORK"
mkdir -p "$DIST" "$LOGS" "$WORK"

APP="$WORK/stage/Codometer.app"
ICON_SOURCE="unknown"
DMG_NAME="Codometer-$VERSION.dmg"
DMG="$DIST/$DMG_NAME"
MANIFEST="$DIST/bundle-manifest.txt"
NOTARIZED="no"
MOUNT_POINT=""
STARTED_AT="$(timestamp_utc)"

cleanup() {
  local status=$?
  set +e
  [[ -n "$MOUNT_POINT" ]] && detach_dmg "$MOUNT_POINT"
  cleanup_notary_credentials
  rm -rf "$WORK"
  exit "$status"
}
trap cleanup EXIT

# --- stage plumbing -------------------------------------------------------------------------------

STAGE_NUMBER=0
FAILED_STAGE=""

# run_stage <name> <function>
run_stage() {
  local name="$1" fn="$2"
  STAGE_NUMBER=$((STAGE_NUMBER + 1))
  local label
  label="$(printf '%02d-%s' "$STAGE_NUMBER" "$name")"
  STAGE_LOG="$LOGS/$label.log"
  : > "$STAGE_LOG"
  local before_failed="$CHECKS_FAILED"
  heading "Stage $STAGE_NUMBER — $name"
  "$fn"
  if ((CHECKS_FAILED > before_failed)); then
    FAILED_STAGE="$name"
    printf '\n%sStage %d (%s) FAILED — see %s%s\n' "$C_RED" "$STAGE_NUMBER" "$name" "$STAGE_LOG" "$C_RESET" >&2
    STAGE_LOG=''
    exit 1
  fi
  printf '  %s→ stage %d PASS%s\n' "$C_GREEN" "$STAGE_NUMBER" "$C_RESET"
  STAGE_LOG=''
}

# Runs a command, keeps its raw output in the stage's own log file and reports one line.
run_logged() {
  local title="$1" logfile="$2"; shift 2
  if "$@" > "$logfile" 2>&1; then
    check_pass "$title"
    return 0
  fi
  check_fail "$title — see $logfile"
  tail -20 "$logfile" | sed 's/^/        /' >&2
  return 1
}

# --- 1. preflight ---------------------------------------------------------------------------------

stage_preflight() {
  [[ -f Packaging/toolchain.env ]] || { check_fail "Packaging/toolchain.env is missing"; return 0; }
  # shellcheck source=../Packaging/toolchain.env
  source Packaging/toolchain.env
  check_pass "Packaging/VERSION $VERSION, build $BUILD_NUMBER"

  local have_build have_version have_swift
  have_build="$(xcode_build)"
  have_version="$(xcode_version)"
  have_swift="$(swift_version)"
  if [[ "$have_build" == "$XCODE_BUILD" ]]; then
    check_pass "Xcode $have_version ($have_build)"
  elif ((ALLOW_TOOLCHAIN_MISMATCH == 1)); then
    check_warn "Xcode $have_version ($have_build), expected $XCODE_VERSION ($XCODE_BUILD) — allowed by --allow-toolchain-mismatch"
  elif ((CI_MODE == 1)) && [[ "$have_version" == 26.* ]]; then
    check_warn "Xcode $have_version ($have_build), expected $XCODE_VERSION ($XCODE_BUILD) — the runner image drifted; CI continues"
  else
    check_fail "Xcode $have_version ($have_build), expected $XCODE_VERSION ($XCODE_BUILD). Select the pinned Xcode or pass --allow-toolchain-mismatch"
  fi
  if version_at_least "${have_swift:-0}" "$SWIFT_MIN"; then
    check_pass "Swift $have_swift (minimum $SWIFT_MIN)"
  else
    check_fail "Swift ${have_swift:-unknown} is older than $SWIFT_MIN"
  fi

  # Release documentation. Until these files exist the gate says so out loud rather than
  # pretending a release is ready, and --allow-missing-docs is refused for a notarized build.
  local docs_missing=0
  if [[ -f CHANGELOG.md ]]; then
    if grep -q "^## \[$VERSION\]" CHANGELOG.md; then
      check_pass "CHANGELOG.md has ## [$VERSION]"
    else
      check_fail "CHANGELOG.md has no \"## [$VERSION]\" heading"
    fi
  else
    docs_missing=1
  fi
  local notes lang
  for lang in en ru; do
    notes="docs/release-notes/$VERSION.$lang.md"
    if [[ -s "$notes" ]]; then
      check_pass "$notes"
    elif [[ -e "$notes" ]]; then
      check_fail "$notes is empty"
    else
      docs_missing=1
    fi
  done
  if ((docs_missing == 1)); then
    if ((ALLOW_MISSING_DOCS == 1)); then
      check_warn "CHANGELOG.md and/or docs/release-notes/$VERSION.{en,ru}.md are missing — allowed by --allow-missing-docs; the release notes body will be a placeholder"
    else
      check_fail "CHANGELOG.md and docs/release-notes/$VERSION.{en,ru}.md must exist before a release. Pass --allow-missing-docs for a trial build"
    fi
  fi

  # Without a licence the gate warns and never fails: choosing one is the maintainer's call.
  if [[ -f LICENSE ]]; then
    check_pass "LICENSE ($(grep -m1 -vE '^[[:space:]]*$' LICENSE | cut -c1-40))"
  else
    check_warn "no LICENSE file: a public repository without one means nobody may legally reuse the code"
  fi

  # Git. The repository has no commits yet, so this is a skip rather than a failure.
  if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    if git -C "$ROOT" rev-parse HEAD >/dev/null 2>&1; then
      if [[ -z "$(git -C "$ROOT" status --porcelain)" ]]; then
        check_pass "git: the working tree is clean"
      elif ((ALLOW_DIRTY == 1)); then
        check_warn "git: the working tree has uncommitted changes — allowed by --allow-dirty"
      else
        check_fail "git: the working tree has uncommitted changes; commit them or pass --allow-dirty"
      fi
      local tag
      tag="$(git -C "$ROOT" tag --points-at HEAD 2>/dev/null | grep -E "^v[0-9]" | sed -n '1p' || true)"
      if [[ -z "$tag" ]]; then
        check_skip "git: HEAD carries no v* tag (a tag is only needed for a published release)"
      elif [[ "$tag" == "v$VERSION" ]]; then
        check_pass "git: HEAD is tagged $tag"
      else
        check_fail "git: HEAD is tagged $tag but Packaging/VERSION says $VERSION"
      fi
    else
      check_skip "git: the repository has no commits yet, so there is nothing to check"
    fi
  else
    check_skip "git: not a repository"
  fi

  local free
  free="$(free_disk_gb "$DIST")"
  if ((free >= 2)); then
    check_pass "free disk ${free} GB"
  else
    check_fail "only ${free} GB free; the release needs at least 2 GB"
  fi

  local plist
  for plist in Packaging/Info.plist Packaging/Widgets-Info.plist Packaging/Widgets.entitlements Packaging/identity.env; do
    [[ -f "$plist" ]] && check_pass "$plist" || check_fail "$plist is missing"
  done
}

# --- 2. lint --------------------------------------------------------------------------------------

stage_lint() {
  local plists=(Packaging/Info.plist Packaging/Widgets-Info.plist Packaging/Widgets.entitlements)
  if plutil -lint "${plists[@]}" > "$LOGS/02-plutil.log" 2>&1; then
    check_pass "plutil -lint on ${#plists[@]} property lists"
  else
    check_fail "plutil -lint failed"
    sed 's/^/        /' "$LOGS/02-plutil.log" >&2
  fi

  local script bad=0
  for script in Scripts/*.sh Scripts/lib/*.sh; do
    [[ -f "$script" ]] || continue
    if ! bash -n "$script" 2>>"$LOGS/02-bash-n.log"; then
      bad=$((bad + 1))
    fi
  done
  if ((bad == 0)); then
    check_pass "bash -n on every script"
  else
    check_fail "$bad script(s) do not parse"
    sed 's/^/        /' "$LOGS/02-bash-n.log" >&2
  fi

  if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck -x Scripts/*.sh Scripts/lib/*.sh > "$LOGS/02-shellcheck.log" 2>&1; then
      check_pass "shellcheck"
    else
      check_warn "shellcheck reported findings (advisory, see $LOGS/02-shellcheck.log)"
    fi
  else
    check_skip "shellcheck is not installed (optional)"
  fi

  # Scripts/lint.sh covers the policy greps, the `l10n: pending` check and CodometerSourceLintTests.
  run_logged "Scripts/lint.sh (policy rules, l10n markers, CodometerSourceLintTests)" \
    "$LOGS/02-policy-lint.log" env NO_COLOR=1 Scripts/lint.sh || true
}

# --- 3. test --------------------------------------------------------------------------------------

stage_test() {
  if swift test > "$LOGS/03-swift-test.log" 2>&1; then
    local line
    line="$(grep -E 'Test run with [0-9]+ tests' "$LOGS/03-swift-test.log" | sed -n '$p' || true)"
    check_pass "swift test${line:+ — ${line#*] }}"
  else
    check_fail "swift test failed — see $LOGS/03-swift-test.log"
    grep -E '(✘|error:|warning:)' "$LOGS/03-swift-test.log" | sed -n '1,20p' | sed 's/^/        /' >&2 || true
    return 0
  fi
  # Both release products, because the #if DEBUG paths differ from the ones the tests compile.
  run_logged "swift build -c release --product Codometer" "$LOGS/03-release-app.log" \
    swift build -c release --product Codometer || return 0
  run_logged "swift build -c release --product CodometerWidgets" "$LOGS/03-release-widgets.log" \
    swift build -c release --product CodometerWidgets || return 0
  local warnings
  warnings="$( { grep -c 'warning:' "$LOGS/03-release-app.log" "$LOGS/03-release-widgets.log" || true; } | awk -F: '{ s += $2 } END { print s + 0 }')"
  if ((warnings == 0)); then
    check_pass "both release products build without warnings"
  else
    check_fail "$warnings compiler warning(s) in the release build (warnings are errors for this project)"
  fi
}

# --- 4. assemble ----------------------------------------------------------------------------------

stage_assemble() {
  local args=(release --output "$WORK/stage" --version "$VERSION" --build "$BUILD_NUMBER" --no-sign)
  ((ALLOW_MISSING_ICON == 1)) && args+=(--allow-missing-icon)
  if Scripts/build-app.sh "${args[@]}" > "$LOGS/04-build-app.log" 2>&1; then
    ICON_SOURCE="$(sed -n 's/.*icon: \([a-zA-Z0-9.-]*\))$/\1/p' "$LOGS/04-build-app.log" | sed -n '1p')"
    check_pass "$(tail -1 "$LOGS/04-build-app.log")"
  else
    check_fail "Scripts/build-app.sh failed — see $LOGS/04-build-app.log"
    tail -20 "$LOGS/04-build-app.log" | sed 's/^/        /' >&2
    return 0
  fi
  if grep -q '^warning:' "$LOGS/04-build-app.log"; then
    check_warn "$(grep '^warning:' "$LOGS/04-build-app.log" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  fi
  [[ -d "$APP" ]] && check_pass "assembled $APP" || check_fail "no bundle at $APP"
}

# --- 5. sign --------------------------------------------------------------------------------------

stage_sign() {
  set +x
  local have_notary=0
  if resolve_notary_credentials; then have_notary=1; fi
  if ! resolve_sign_mode "$have_notary"; then
    check_fail "$SIGN_ERROR"
    return 0
  fi

  case "$SIGN_MODE" in
    adhoc)
      if ((REQUIRE_NOTARIZATION == 1)); then
        check_fail "--require-notarization was given but there is no signing identity ($SIGN_MODE_REASON)"
        return 0
      fi
      check_warn "signing ad hoc: $SIGN_MODE_REASON. Users will have to allow the app in System Settings the first time"
      ;;
    developer-id)
      check_pass "signing with a Developer ID ($SIGN_MODE_REASON), notary credentials from the $NOTARY_SOURCE"
      ;;
    developer-id-unnotarized)
      if ((REQUIRE_NOTARIZATION == 1)); then
        check_fail "--require-notarization was given but no notary credentials are set (CODOMETER_NOTARY_PROFILE, an API key, or an Apple ID)"
        return 0
      fi
      check_warn "signing with a Developer ID ($SIGN_MODE_REASON) but NOT notarizing: no notary credentials"
      ;;
  esac

  if sign_app "$APP" Packaging/Widgets.entitlements > "$LOGS/05-codesign.log" 2>&1; then
    check_pass "signed the widget extension, then the app, and verified --strict --deep"
  else
    check_fail "signing failed — see $LOGS/05-codesign.log"
    tail -20 "$LOGS/05-codesign.log" | sed 's/^/        /' >&2
  fi
}

# --- 6. verify-bundle -----------------------------------------------------------------------------

stage_verify_bundle() {
  local args=("$APP" --mode "$SIGN_MODE")
  ((ALLOW_MISSING_ICON == 1)) && args+=(--allow-missing-icon)
  if env NO_COLOR=1 Scripts/verify-bundle.sh "${args[@]}" > "$LOGS/06-gates.log" 2>&1; then
    check_pass "verify-bundle: $(grep -E '^  [0-9]+ passed' "$LOGS/06-gates.log" | sed 's/^ *//')"
    # Repeat the sub-script's warnings here, so they reach this stage's log and the final summary.
    # The loop reads from a process substitution rather than a pipe, or the counters would be updated in
    # a subshell and thrown away.
    local w
    while IFS= read -r w; do
      [[ -n "$w" ]] || continue
      check_warn "$w"
    done < <(grep -E '^  WARN' "$LOGS/06-gates.log" | sed 's/^  WARN  //' || true)
  else
    check_fail "verify-bundle failed — see $LOGS/06-gates.log"
    grep -E '^  FAIL' "$LOGS/06-gates.log" | sed 's/^/        /' >&2 || true
    return 0
  fi

  bundle_manifest "$APP" > "$MANIFEST"
  check_pass "bundle-manifest.txt: $(grep -c . "$MANIFEST") files"
}

# --- 7. notarize ----------------------------------------------------------------------------------

stage_notarize() {
  if [[ "$SIGN_MODE" != "developer-id" ]]; then
    check_skip "notarization: mode is $SIGN_MODE"
    return 0
  fi
  set +x
  local zip="$WORK/Codometer.zip"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$zip"
  if notarize_artifact "$zip" "$LOGS" app; then
    check_pass "notarized the app"
  else
    check_fail "notarization was not accepted — see $LOGS/notary-app.json and notary-app-log.json"
    return 0
  fi
  if staple_and_validate "$APP" > "$LOGS/07-staple.log" 2>&1; then
    check_pass "stapled the ticket to the app (it works offline after a copy out of the DMG)"
    NOTARIZED="yes"
  else
    check_fail "stapling failed — see $LOGS/07-staple.log"
  fi
}

# --- 8. dmg ---------------------------------------------------------------------------------------

stage_dmg() {
  if ((SKIP_DMG == 1)); then
    check_skip "--skip-dmg"
    return 0
  fi
  if make_dmg "$APP" "$WORK" "$DMG" "Codometer $VERSION" > "$LOGS/08-hdiutil.log" 2>&1; then
    check_pass "created $DMG_NAME ($(human_bytes "$(file_size_bytes "$DMG")"))"
  else
    check_fail "hdiutil create failed — see $LOGS/08-hdiutil.log"
    tail -20 "$LOGS/08-hdiutil.log" | sed 's/^/        /' >&2
    return 0
  fi

  local bytes limit
  bytes="$(file_size_bytes "$DMG")"
  limit=$((15 * 1024 * 1024))
  if ((bytes <= limit)); then
    check_pass "DMG size $(human_bytes "$bytes") (budget 15 MB)"
  else
    check_fail "DMG size $(human_bytes "$bytes") exceeds the 15 MB budget"
  fi

  case "$SIGN_MODE" in
    developer-id)
      sign_file "$DMG"
      if notarize_artifact "$DMG" "$LOGS" dmg && staple_and_validate "$DMG" > "$LOGS/08-staple-dmg.log" 2>&1; then
        check_pass "signed, notarized and stapled the disk image"
      else
        check_fail "the disk image was not notarized — see $LOGS/notary-dmg.json"
      fi
      ;;
    developer-id-unnotarized)
      sign_file "$DMG"
      check_warn "the disk image is signed but not notarized: macOS will still warn on first open"
      ;;
    *)
      # An ad-hoc signature on the image proves nothing and is not what users check; the checksums are.
      check_skip "DMG signing and notarization: mode is $SIGN_MODE"
      ;;
  esac
}

# --- 9. verify-dmg --------------------------------------------------------------------------------

stage_verify_dmg() {
  if ((SKIP_DMG == 1)); then
    check_skip "--skip-dmg"
    return 0
  fi
  if hdiutil verify "$DMG" > "$LOGS/09-hdiutil-verify.log" 2>&1; then
    check_pass "hdiutil verify"
  else
    check_fail "hdiutil verify failed — see $LOGS/09-hdiutil-verify.log"
    return 0
  fi

  # Read-only, not browsable, not auto-opened and at a random mount point, so Finder never shows it and
  # LaunchServices never latches on to a second copy of the app.
  if ! MOUNT_POINT="$(mount_dmg "$DMG" "$WORK" 2>"$LOGS/09-attach.log")"; then
    check_fail "could not attach the disk image — see $LOGS/09-attach.log"
    MOUNT_POINT=""
    return 0
  fi
  check_pass "attached read-only at $MOUNT_POINT"

  local mounted="$MOUNT_POINT/Codometer.app"
  if [[ -d "$mounted" ]]; then
    check_pass "the image contains Codometer.app"
  else
    check_fail "no Codometer.app inside the image"
  fi
  if [[ -L "$MOUNT_POINT/Applications" ]]; then
    check_pass "the image has the Applications symlink to drag onto"
  else
    check_fail "the image has no Applications symlink"
  fi

  if codesign --verify --strict --deep --verbose=2 "$mounted" > "$LOGS/09-codesign.log" 2>&1; then
    check_pass "the mounted app verifies"
  else
    check_fail "the mounted app does not verify — see $LOGS/09-codesign.log"
  fi

  bundle_manifest "$mounted" > "$WORK/mounted-manifest.txt"
  if diff -q "$MANIFEST" "$WORK/mounted-manifest.txt" >/dev/null; then
    check_pass "the mounted app matches bundle-manifest.txt file for file"
  else
    check_fail "the mounted app differs from the one that was verified"
    diff "$MANIFEST" "$WORK/mounted-manifest.txt" | sed -n '1,20p' | sed 's/^/        /' >&2 || true
  fi

  local spctl_out
  spctl_out="$(spctl -a -t open --context context:primary-signature -vv "$DMG" 2>&1 || true)"
  case "$SIGN_MODE" in
    developer-id)
      if [[ "$spctl_out" == *accepted* ]]; then
        check_pass "spctl accepts the image"
      else
        check_fail "spctl rejects a notarized image: $spctl_out"
      fi
      ;;
    *)
      if [[ "$spctl_out" == *rejected* ]]; then
        check_pass "spctl rejects the image, as expected without a Developer ID (users get the \"Open Anyway\" flow)"
      else
        check_warn "spctl said: $(printf '%s' "$spctl_out" | sed -n '1p')"
      fi
      ;;
  esac

  # A precaution, never a registration: if LaunchServices noticed the mounted copy, drop it again before
  # the image is detached, so the widget's bundle identifier keeps pointing at a path that exists.
  local lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
  [[ -x "$lsregister" ]] && "$lsregister" -u "$mounted" >/dev/null 2>&1 || true

  detach_dmg "$MOUNT_POINT"
  MOUNT_POINT=""
  check_pass "detached"
}

# --- 10. artifacts --------------------------------------------------------------------------------

stage_artifacts() {
  local notes="$DIST/release-notes.md"
  # The GitHub release page is read by users, so it carries both languages: English first, Russian folded
  # underneath. The build footer is written in both too, because the Gatekeeper instructions are the part
  # people actually need on an unsigned build.
  {
    printf '# Codometer %s\n\n' "$VERSION"
    if [[ -s "docs/release-notes/$VERSION.en.md" ]]; then
      cat "docs/release-notes/$VERSION.en.md"
    else
      printf '_Release notes for %s have not been written yet (docs/release-notes/%s.en.md)._\n' "$VERSION" "$VERSION"
    fi
    printf '\n---\n\n'
    printf 'Build mode `%s`, notarized: %s, architecture `%s`, build `%s`.\n' \
      "$SIGN_MODE" "$([[ "$NOTARIZED" == "yes" ]] && printf 'yes' || printf 'no')" "${ARCHS:-arm64}" "$BUILD_NUMBER"
    if [[ "$SIGN_MODE" != "developer-id" ]]; then
      printf '\nThis build is not notarized, so macOS refuses to open it the first time. Open System Settings →\n'
      printf 'Privacy & Security and choose **Open Anyway**, or run\n'
      printf '`xattr -dr com.apple.quarantine /Applications/Codometer.app`. Check the download against\n'
      printf '`SHA256SUMS.txt` before you do either.\n'
    fi
    printf '\n<details>\n<summary>Русский</summary>\n\n'
    if [[ -s "docs/release-notes/$VERSION.ru.md" ]]; then
      cat "docs/release-notes/$VERSION.ru.md"
    else
      printf '_Заметки о выпуске %s ещё не написаны (docs/release-notes/%s.ru.md)._\n' "$VERSION" "$VERSION"
    fi
    printf '\n---\n\n'
    printf 'Режим сборки «%s», нотаризация: %s, архитектура «%s», сборка «%s».\n' \
      "$SIGN_MODE" "$([[ "$NOTARIZED" == "yes" ]] && printf 'есть' || printf 'нет')" "${ARCHS:-arm64}" "$BUILD_NUMBER"
    if [[ "$SIGN_MODE" != "developer-id" ]]; then
      printf '\nСборка не нотаризована, поэтому macOS не откроет её с первого раза. Зайдите в «Системные настройки»\n'
      printf '→ «Конфиденциальность и безопасность» и нажмите **«Всё равно открыть»** или выполните\n'
      printf '`xattr -dr com.apple.quarantine /Applications/Codometer.app`. Перед этим сверьте загруженный файл\n'
      printf 'с `SHA256SUMS.txt`.\n'
    fi
    printf '\n</details>\n'
  } > "$notes"
  if [[ -s "docs/release-notes/$VERSION.en.md" && -s "docs/release-notes/$VERSION.ru.md" ]]; then
    check_pass "release-notes.md (English, Russian under a fold)"
  else
    check_warn "release-notes.md was written with a placeholder body: docs/release-notes/$VERSION.{en,ru}.md are missing"
  fi

  # build-info.json: everything needed to reproduce or explain this exact artefact.
  local git_sha app_bytes dmg_bytes
  # `rev-parse --verify --quiet` is the form that stays silent: plain `rev-parse HEAD` in a repository
  # with no commits prints "HEAD" on stdout *and* exits 128, so an `|| printf` fallback lands a two-line
  # value in the file and the JSON is then invalid.
  git_sha="$(git -C "$ROOT" rev-parse --verify --quiet HEAD 2>/dev/null || true)"
  git_sha="$(printf '%s' "$git_sha" | tr -d '\r\n')"
  [[ -n "$git_sha" ]] || git_sha="nogit"
  app_bytes="$(dir_size_bytes "$APP")"
  dmg_bytes=0
  [[ -f "$DMG" ]] && dmg_bytes="$(file_size_bytes "$DMG")"
  cat > "$DIST/build-info.json" <<EOF
{
  "product": "Codometer",
  "version": "$VERSION",
  "build": "$BUILD_NUMBER",
  "mode": "$SIGN_MODE",
  "notarized": $([[ "$NOTARIZED" == "yes" ]] && printf 'true' || printf 'false'),
  "architecture": "${ARCHS:-arm64}",
  "bundleIdentifier": "$(json_escape "${CODOMETER_BUNDLE_ID:-com.codometer.Codometer}")",
  "xcode": "$(json_escape "$(xcode_version) ($(xcode_build))")",
  "swift": "$(json_escape "$(swift_version)")",
  "sdk": "$(json_escape "$(xcrun --show-sdk-version 2>/dev/null || printf unknown)")",
  "deploymentTarget": "${MACOS_DEPLOYMENT_TARGET:-26.0}",
  "git": "$(json_escape "$git_sha")",
  "startedAt": "$STARTED_AT",
  "finishedAt": "$(timestamp_utc)",
  "appBytes": $app_bytes,
  "dmgBytes": $dmg_bytes,
  "icon": "$(json_escape "$ICON_SOURCE")",
  "releaseNotes": $([[ -s "docs/release-notes/$VERSION.en.md" ]] && printf 'true' || printf 'false')
}
EOF
  # `plutil -lint` decides the format from the extension and refuses a .json file, so the check uses a real
  # JSON parser: jq ships with macOS 15 and later, python3 is the fallback.
  if command -v jq >/dev/null 2>&1; then
    if jq empty < "$DIST/build-info.json" 2>"$LOGS/10-build-info.log"; then
      check_pass "build-info.json (mode $SIGN_MODE, icon $ICON_SOURCE)"
    else
      check_fail "build-info.json is not valid JSON: $(sed -n '1p' "$LOGS/10-build-info.log")"
    fi
  elif command -v python3 >/dev/null 2>&1; then
    if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$DIST/build-info.json" 2>"$LOGS/10-build-info.log"; then
      check_pass "build-info.json (mode $SIGN_MODE, icon $ICON_SOURCE)"
    else
      check_fail "build-info.json is not valid JSON: $(sed -n '$p' "$LOGS/10-build-info.log")"
    fi
  else
    check_skip "build-info.json was written but not validated: neither jq nor python3 is installed"
  fi

  # Checksums over the public assets only: the dSYM archive is not published.
  ( cd "$DIST" && : > SHA256SUMS.txt
    for asset in "$DMG_NAME" build-info.json bundle-manifest.txt release-notes.md; do
      [[ -f "$asset" ]] && shasum -a 256 "$asset" >> SHA256SUMS.txt
    done )
  if [[ -s "$DIST/SHA256SUMS.txt" ]]; then
    check_pass "SHA256SUMS.txt ($(grep -c . "$DIST/SHA256SUMS.txt") assets, plain \`shasum -c\` format)"
  else
    check_fail "SHA256SUMS.txt is empty"
  fi

  # dSYMs stay private: built locally they embed the builder's home folder in the debug map.
  local bin_dir dsyms
  bin_dir="$(swift build -c release --show-bin-path 2>/dev/null || true)"
  dsyms=""
  [[ -n "$bin_dir" ]] && dsyms="$(find "$bin_dir" -maxdepth 1 -name '*.dSYM' 2>/dev/null || true)"
  if [[ -n "$dsyms" ]]; then
    local zip="$DIST/Codometer-$VERSION-dSYMs.zip" collected="$WORK/dSYMs" one
    rm -f "$zip"
    rm -rf "$collected"
    mkdir -p "$collected"
    while IFS= read -r one; do
      [[ -n "$one" ]] && ditto "$one" "$collected/$(basename "$one")"
    done <<< "$dsyms"
    ditto -c -k --sequesterRsrc "$collected" "$zip"
    check_pass "dSYM archive $(basename "$zip") ($(human_bytes "$(file_size_bytes "$zip")")) — private, never a release asset"
  else
    check_skip "no dSYM bundles next to the release binaries"
  fi

  check_pass "artifacts in $DIST"
}

# --- 11. perf -------------------------------------------------------------------------------------

stage_perf() {
  if ((RUN_PERF == 0)); then
    check_skip "--perf was not requested"
    return 0
  fi
  if ((CI_MODE == 1)); then
    check_skip "performance is never measured on CI (no Claude or Codex data there)"
    return 0
  fi
  if Scripts/perf-smoke.sh --app "$APP" > "$LOGS/11-perf-smoke.log" 2>&1; then
    check_pass "perf-smoke within the Appendix D budgets"
    grep -E '^  (PASS|WARN|FAIL)' "$LOGS/11-perf-smoke.log" | sed 's/^/        /' || true
  else
    check_fail "perf-smoke exceeded a budget — see $LOGS/11-perf-smoke.log"
    tail -20 "$LOGS/11-perf-smoke.log" | sed 's/^/        /' >&2
  fi
}

# --- 12. summary ----------------------------------------------------------------------------------

stage_summary() {
  note "version       $VERSION (build $BUILD_NUMBER)"
  note "mode          $SIGN_MODE, notarized: $NOTARIZED"
  note "architecture  ${ARCHS:-arm64}"
  note "output        $DIST"
  if [[ -f "$DMG" ]]; then
    note "disk image    $DMG_NAME  $(human_bytes "$(file_size_bytes "$DMG")")"
    note "              $(shasum -a 256 "$DMG" | awk '{ print $1 }')"
  fi
  note "app bundle    $(human_bytes "$(dir_size_bytes "$APP")")"

  local warnings
  warnings="$(warnings_list)"
  if [[ -n "$warnings" ]]; then
    printf '\n  %s%d warning(s) to resolve before this build is published:%s\n' "$C_YELLOW" "$CHECKS_WARNED" "$C_RESET"
    printf '%s\n' "$warnings" | sed 's/^/    · /'
  fi
  check_pass "all stages completed"
}

# --- run ------------------------------------------------------------------------------------------

heading "Codometer $VERSION — release gate"
note "root   $ROOT"
note "output $DIST"

run_stage preflight     stage_preflight
run_stage lint          stage_lint
run_stage test          stage_test
run_stage assemble      stage_assemble
run_stage sign          stage_sign
run_stage verify-bundle stage_verify_bundle
run_stage notarize      stage_notarize
run_stage dmg           stage_dmg
run_stage verify-dmg    stage_verify_dmg
run_stage artifacts     stage_artifacts
run_stage perf          stage_perf
run_stage summary       stage_summary

printf '\n%s%s%s\n' "$C_GREEN$C_BOLD" "Release gate passed: $CHECKS_PASSED checks, $CHECKS_SKIPPED skipped, $CHECKS_WARNED warnings." "$C_RESET"
