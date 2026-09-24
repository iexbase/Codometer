#!/usr/bin/env bash
# Everything that must be true of a Codometer.app before it may leave this machine.
#
#   Scripts/verify-bundle.sh <app> [--mode adhoc|developer-id|developer-id-unnotarized] [--arch arm64]
#                                  [--allow-missing-icon]
#
# Run on its own, or as stage 6 of Scripts/release.sh. It reads the bundle and never writes to it.
set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck source=lib/common.sh
source Scripts/lib/common.sh
resolve_developer_dir

APP=""
MODE="adhoc"
EXPECT_ARCH=""
ALLOW_MISSING_ICON=0

while (($# > 0)); do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --arch) EXPECT_ARCH="${2:-}"; shift 2 ;;
    --allow-missing-icon) ALLOW_MISSING_ICON=1; shift ;;
    -h|--help) print_header_help "$0"; exit 0 ;;
    -*) die "unknown option: $1" 64 ;;
    *) APP="$1"; shift ;;
  esac
done

[[ -n "$APP" && -d "$APP" ]] || die "usage: $0 <app> [--mode <mode>] [--arch <arch>]" 64
APP="$(cd "$APP" && pwd)"

# shellcheck source=../Packaging/toolchain.env
source Packaging/toolchain.env
EXPECT_ARCH="${EXPECT_ARCH:-$ARCHS}"

APPEX="$APP/Contents/PlugIns/CodometerWidgets.appex"
APP_PLIST="$APP/Contents/Info.plist"
APPEX_PLIST="$APPEX/Contents/Info.plist"
APP_BIN="$APP/Contents/MacOS/Codometer"
APPEX_BIN="$APPEX/Contents/MacOS/CodometerWidgets"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/codometer-verify-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

heading "verify-bundle: $APP (mode $MODE)"

for path in "$APPEX" "$APP_PLIST" "$APPEX_PLIST" "$APP_BIN" "$APPEX_BIN"; do
  if [[ -e "$path" ]]; then
    check_pass "present: ${path#$APP/}"
  else
    check_fail "missing: ${path#$APP/}"
  fi
done

# --- signature ------------------------------------------------------------------------------------

if codesign --verify --strict --deep --verbose=2 "$APP" >"$WORK/verify.txt" 2>&1; then
  check_pass "codesign --verify --strict --deep"
else
  check_fail "codesign --verify --strict --deep: $(sed -n '1,3p' "$WORK/verify.txt" | tr '\n' ' ')"
fi

# The hardened runtime is what lets a Developer ID build be notarized, and it is cheap insurance in ad-hoc
# mode too. `codesign -dv` prints it in the flags line as "runtime".
for target in "$APP" "$APPEX"; do
  flags="$(codesign -dv "$target" 2>&1 | sed -n 's/^CodeDirectory .*flags=\([^ ]*\).*/\1/p')"
  if [[ "$flags" == *runtime* ]]; then
    check_pass "hardened runtime: $(basename "$target") ($flags)"
  else
    check_fail "hardened runtime missing: $(basename "$target") (flags=${flags:-none})"
  fi
done

# The host has no entitlements at all. An entitlement added "just in case" is an entitlement an attacker
# inherits, and the App Sandbox on the host would break the CLI probes.
codesign -d --entitlements - --xml "$APP" > "$WORK/app-ent.plist" 2>/dev/null || : > "$WORK/app-ent.plist"
if [[ ! -s "$WORK/app-ent.plist" ]]; then
  check_pass "host entitlements: none"
else
  plutil -convert xml1 "$WORK/app-ent.plist" >/dev/null 2>&1 || true
  check_fail "host entitlements are not empty: $(tr -d '\n\t ' < "$WORK/app-ent.plist" | cut -c1-200)"
fi

# The appex keeps exactly the entitlements in Packaging/Widgets.entitlements: sandbox plus one read-only
# path. Comparing the normalized XML catches both a dropped sandbox and a widened exception.
if codesign -d --entitlements - --xml "$APPEX" > "$WORK/appex-ent.plist" 2>/dev/null && [[ -s "$WORK/appex-ent.plist" ]]; then
  plutil -convert xml1 "$WORK/appex-ent.plist" >/dev/null
  cp Packaging/Widgets.entitlements "$WORK/expected-ent.plist"
  plutil -convert xml1 "$WORK/expected-ent.plist" >/dev/null
  if diff -q <(tr -d ' \t\n' < "$WORK/appex-ent.plist") <(tr -d ' \t\n' < "$WORK/expected-ent.plist") >/dev/null; then
    check_pass "appex entitlements equal Packaging/Widgets.entitlements"
  else
    check_fail "appex entitlements differ from Packaging/Widgets.entitlements"
    diff <(plutil -p "$WORK/expected-ent.plist") <(plutil -p "$WORK/appex-ent.plist") | sed 's/^/        /' >&2 || true
  fi
else
  check_fail "appex has no entitlements"
fi

if grep -q 'get-task-allow' "$WORK/app-ent.plist" "$WORK/appex-ent.plist" 2>/dev/null; then
  check_fail "get-task-allow is set: this is a debug-signed bundle"
else
  check_pass "no get-task-allow"
fi

# --- Info.plist -----------------------------------------------------------------------------------

app_short="$(plist_get "$APP_PLIST" CFBundleShortVersionString || true)"
app_build="$(plist_get "$APP_PLIST" CFBundleVersion || true)"
appex_short="$(plist_get "$APPEX_PLIST" CFBundleShortVersionString || true)"
appex_build="$(plist_get "$APPEX_PLIST" CFBundleVersion || true)"

if is_semver "${app_short:-}" && [[ "$app_short" != "0.0.0" ]]; then
  check_pass "CFBundleShortVersionString $app_short"
else
  check_fail "CFBundleShortVersionString is \"${app_short:-}\": the version was never injected"
fi
if [[ -n "$app_build" && "$app_build" =~ ^[0-9]+$ && "$app_build" != "0" ]]; then
  check_pass "CFBundleVersion $app_build"
else
  check_fail "CFBundleVersion is \"${app_build:-}\": the build number was never injected"
fi
if [[ "$app_short" == "$appex_short" && "$app_build" == "$appex_build" ]]; then
  check_pass "app and widget versions match"
else
  check_fail "version mismatch: app $app_short ($app_build) vs widget $appex_short ($appex_build)"
fi

for plist in "$APP_PLIST" "$APPEX_PLIST"; do
  name="$(basename "$(dirname "$(dirname "$plist")")")"
  localizations=""
  minimum="$(plist_get "$plist" LSMinimumSystemVersion || true)"
  if [[ "$minimum" == "$MACOS_DEPLOYMENT_TARGET" ]]; then
    check_pass "$name LSMinimumSystemVersion $minimum"
  else
    check_fail "$name LSMinimumSystemVersion is \"${minimum:-}\", expected $MACOS_DEPLOYMENT_TARGET"
  fi
  region="$(plist_get "$plist" CFBundleDevelopmentRegion || true)"
  if [[ "$region" == "en" ]]; then
    check_pass "$name CFBundleDevelopmentRegion en"
  else
    check_fail "$name CFBundleDevelopmentRegion is \"${region:-}\", expected en (English is the default language)"
  fi
  localizations="$(plutil -extract CFBundleLocalizations json -o - "$plist" 2>/dev/null || true)"
  if [[ "$localizations" == *'"en"'* && "$localizations" == *'"ru"'* ]]; then
    check_pass "$name CFBundleLocalizations [en, ru]"
  else
    check_fail "$name CFBundleLocalizations does not list en and ru"
  fi
  copyright="$(plist_get "$plist" NSHumanReadableCopyright || true)"
  case "$copyright" in
    ©*) check_pass "$name NSHumanReadableCopyright starts with ©" ;;
    *) check_fail "$name NSHumanReadableCopyright is \"${copyright:-}\", expected it to start with ©" ;;
  esac
done

icon_name="$(plist_get "$APP_PLIST" CFBundleIconName || true)"
icon_file="$(plist_get "$APP_PLIST" CFBundleIconFile || true)"
if [[ -n "$icon_name" && -n "$icon_file" && -f "$APP/Contents/Resources/Assets.car" && -f "$APP/Contents/Resources/AppIcon.icns" ]]; then
  check_pass "icon: CFBundleIconName=$icon_name, Assets.car and AppIcon.icns present"
elif ((ALLOW_MISSING_ICON == 1)); then
  check_warn "no app icon: Finder, the Dock, the DMG and notifications will show the generic placeholder (see Scripts/build-icon.sh)"
else
  check_fail "no app icon: CFBundleIconName/CFBundleIconFile, Assets.car or AppIcon.icns is missing"
fi

if plist_get "$APP_PLIST" LSUIElement >/dev/null 2>&1; then
  check_pass "LSUIElement: the app has no Dock tile until Settings opens"
else
  check_fail "LSUIElement is missing"
fi
if plist_get "$APP_PLIST" LSMultipleInstancesProhibited >/dev/null 2>&1; then
  check_fail "LSMultipleInstancesProhibited is set: it blocks other macOS users; the single-instance guard is the data-root lock"
else
  check_pass "no LSMultipleInstancesProhibited"
fi

# --- binaries -------------------------------------------------------------------------------------

for binary in "$APP_BIN" "$APPEX_BIN"; do
  name="$(basename "$binary")"
  archs="$(lipo -archs "$binary" 2>/dev/null | tr -s ' ' || true)"
  if [[ "$archs" == "$EXPECT_ARCH" ]]; then
    check_pass "$name architecture: $archs"
  else
    check_fail "$name architecture is \"${archs:-unknown}\", expected \"$EXPECT_ARCH\""
  fi

  foreign="$(otool -L "$binary" | tail -n +2 | awk '{ print $1 }' | grep -vE '^(/System/Library|/usr/lib)' || true)"
  if [[ -z "$foreign" ]]; then
    check_pass "$name links only system libraries"
  else
    check_fail "$name links non-system libraries: $(printf '%s' "$foreign" | tr '\n' ' ')"
  fi

  minos="$(otool -l "$binary" | awk '/LC_BUILD_VERSION/ { found = 1 } found && /minos/ { print $2; exit }')"
  if [[ "$minos" == "$MACOS_DEPLOYMENT_TARGET" ]]; then
    check_pass "$name LC_BUILD_VERSION minos $minos"
  else
    check_fail "$name LC_BUILD_VERSION minos is \"${minos:-none}\", expected $MACOS_DEPLOYMENT_TARGET"
  fi
done

# The debug harness must not exist in a shipped binary: it can replace the whole store with fixture data
# and dump the accessibility tree. Build paths must not either — they carry the builder's home folder.
leaks=''
for binary in "$APP_BIN" "$APPEX_BIN"; do
  for needle in 'CODOMETER_DEBUG' 'DebugScenario' '/Users/' '/private/tmp' '.build/'; do
    if strings -a "$binary" | stream_has "$needle"; then
      leaks="${leaks}$(basename "$binary"): $needle"$'\n'
    fi
  done
  if nm -a "$binary" 2>/dev/null | stream_has 'DebugScenario'; then
    leaks="${leaks}$(basename "$binary"): DebugScenario symbol"$'\n'
  fi
done
if [[ -z "$leaks" ]]; then
  check_pass "no debug harness or build paths in the binaries"
else
  check_fail "debug or build-path strings in the binaries:"
  printf '%s' "$leaks" | sed 's/^/        /' >&2
fi

# --- layout ---------------------------------------------------------------------------------------

# A SwiftPM resource bundle at the app root cannot be sealed ("unsealed contents present in the bundle
# root") and would not be found on a user's Mac anyway. Nothing should ever put one there.
#
# One `-maxdepth`, before the tests: `find <dir> -maxdepth 1 -name X -o -maxdepth 2 -path Y` looks like two
# scopes but is not — `-maxdepth` is a global option, the last one wins, and the `-path` clause then sits
# one level below the depth that would let it match, so it can never fire. Depth 3 is the app root,
# Contents/ and Contents/{MacOS,Resources,Frameworks}/ — everywhere SwiftPM drops a resource bundle.
stray="$(find "$APP" -maxdepth 3 -name '*.bundle' 2>/dev/null || true)"
if [[ -z "$stray" ]]; then
  check_pass "no resource bundles in the app root, Contents or its immediate subfolders"
else
  check_fail "resource bundle(s) present: $(printf '%s' "$stray" | tr '\n' ' ')"
fi

# --- size -----------------------------------------------------------------------------------------

app_bytes="$(dir_size_bytes "$APP")"
app_limit=$((25 * 1024 * 1024))
if ((app_bytes <= app_limit)); then
  check_pass "bundle size $(human_bytes "$app_bytes") (budget 25 MB)"
else
  check_fail "bundle size $(human_bytes "$app_bytes") exceeds the 25 MB budget"
fi

# --- Gatekeeper expectation -----------------------------------------------------------------------

spctl_out="$(spctl -a -t exec -vv "$APP" 2>&1 || true)"
case "$MODE" in
  adhoc)
    if [[ "$spctl_out" == *rejected* ]]; then
      check_pass "spctl: rejected, as expected for an ad-hoc signature"
    else
      check_fail "spctl did not reject an ad-hoc build: $spctl_out"
    fi
    ;;
  developer-id)
    if [[ "$spctl_out" == *accepted* ]]; then
      check_pass "spctl: accepted ($(printf '%s' "$spctl_out" | sed -n 's/.*source=\(.*\)/\1/p' | sed -n '1p'))"
    else
      check_fail "spctl did not accept a notarized build: $spctl_out"
    fi
    ;;
  *)
    check_skip "spctl expectation: mode $MODE is signed but not notarized ($(printf '%s' "$spctl_out" | sed -n '1p'))"
    ;;
esac

if [[ "$MODE" == developer-id* ]]; then
  if command -v syspolicy_check >/dev/null 2>&1; then
    if syspolicy_check notary-submission "$APP" >"$WORK/syspolicy.txt" 2>&1; then
      check_pass "syspolicy_check notary-submission"
    else
      check_fail "syspolicy_check notary-submission: $(sed -n '1,4p' "$WORK/syspolicy.txt" | tr '\n' ' ')"
    fi
  else
    check_skip "syspolicy_check is not installed"
  fi
else
  check_skip "syspolicy_check notary-submission: only meaningful for a Developer ID signature"
fi

heading "verify-bundle summary"
printf '  %d passed, %d failed, %d skipped, %d warnings\n' \
  "$CHECKS_PASSED" "$CHECKS_FAILED" "$CHECKS_SKIPPED" "$CHECKS_WARNED"
((CHECKS_FAILED == 0)) || exit 1
