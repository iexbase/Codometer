#!/usr/bin/env bash
# Makes one copy of Codometer the copy macOS knows about.
#
#   Scripts/dev-register.sh [<app>] [--dry-run] [--unregister-only]
#
# Default app: build/Codometer.app.
#
# WidgetKit keys desktop widgets by bundle identifier, and chronod launches whichever copy LaunchServices
# has on file. When that copy is a stale path — a deleted build folder, a mounted disk image — chronod's requests fail, and after a burst of
# failures it stops reloading the widget for 24 hours ("Disallowing reload due to bad extension"). So before
# testing a release copy, unregister every other one.
#
# This script changes LaunchServices state. Run it deliberately: `--dry-run` prints exactly what it would do
# and touches nothing.
set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck source=lib/common.sh
source Scripts/lib/common.sh
# shellcheck source=../Packaging/identity.env
source Packaging/identity.env

APP="build/Codometer.app"
DRY_RUN=0
UNREGISTER_ONLY=0

while (($# > 0)); do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --unregister-only) UNREGISTER_ONLY=1; shift ;;
    -h|--help) print_header_help "$0"; exit 0 ;;
    -*) die "unknown option: $1" 64 ;;
    *) APP="$1"; shift ;;
  esac
done

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[[ -x "$LSREGISTER" ]] || die "lsregister not found at $LSREGISTER"

# The identifiers of this app and of the app under its former name.

if ((UNREGISTER_ONLY == 0)); then
  [[ -d "$APP" ]] || die "no bundle at $APP (build one with Scripts/build-app.sh)" 66
  APP="$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")"
  APPEX="$APP/Contents/PlugIns/CodometerWidgets.appex"
else
  APP=""
  APPEX=""
fi

run() {
  if ((DRY_RUN == 1)); then
    printf '  would run: %s\n' "$*"
  else
    "$@" >/dev/null 2>&1 || true
  fi
}

heading "Registered copies"

copies="$(
  {
    "$LSREGISTER" -dump 2>/dev/null | awk \
      -v app="$CODOMETER_BUNDLE_ID" -v widgets="$CODOMETER_WIDGETS_BUNDLE_ID" \
      '
      /^path:/ { sub(/^path:[ \t]+/, ""); sub(/ \(0x[0-9a-f]+\)$/, ""); path = $0 }
      /^identifier:/ && ($2 == app || $2 == widgets) { print path }
    '
    for widgets_id in "$CODOMETER_WIDGETS_BUNDLE_ID"; do
      pluginkit -m -A -D -v -i "$widgets_id" 2>/dev/null | awk -F '\t' 'NF >= 4 { print $4 }'
    done
  } | LC_ALL=C sort -u
)"

if [[ -z "$copies" ]]; then
  note "none"
else
  printf '%s\n' "$copies" | sed 's/^/  /'
fi

heading "Unregistering every copy except the one to keep"
kept=0
while IFS= read -r stale; do
  [[ -n "$stale" ]] || continue
  if [[ -n "$APP" && ( "$stale" == "$APP" || "$stale" == "$APPEX" ) ]]; then
    note "keeping $stale"
    kept=1
    continue
  fi
  printf '  %s\n' "$stale"
  if [[ "$stale" == *.appex ]]; then
    run pluginkit -r "$stale"
  fi
  run "$LSREGISTER" -u "$stale"
done <<< "$copies"

if ((UNREGISTER_ONLY == 1)); then
  heading "Done (--unregister-only)"
  exit 0
fi

heading "Registering $APP"
if ((DRY_RUN == 1)); then
  printf '  would run: %s -f -R -trusted %s\n' "$LSREGISTER" "$APP"
else
  "$LSREGISTER" -f -R -trusted "$APP"
  # The extension of the copy just registered may still be running from the previous bundle.
  pkill -f "^$APPEX/Contents/MacOS/CodometerWidgets$" 2>/dev/null || true
  printf '  registered (kept: %d)\n' "$kept"
fi
