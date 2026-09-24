#!/usr/bin/env bash
# Builds and launches a development copy of Codometer against an isolated data folder.
#
#   CODOMETER_DATA_ROOT=~/Library/Caches/CodometerDev/run Scripts/run.sh [debug]
#   Scripts/run.sh --data-root ~/Library/Caches/CodometerDev/run
#
# Two rules this script exists to enforce:
#
#  1. It never launches without an isolated `CODOMETER_DATA_ROOT`. A build started without one uses the real
#     `~/Library/Application Support` folder and performs the one-time migration of the folder the app had
#     under its former name. That happened once during development and cost the user their running app's data.
#  2. It stops only a copy whose executable lives inside this tree's `build/`. `pkill -x Codometer` would
#     also kill the copy the user has installed.
#
# It launches the executable directly rather than through `open`, because `open` hands the app to
# LaunchServices, which drops the environment and would run it against the real data folder.
set -euo pipefail

cd "$(dirname "$0")/.."
TREE="$(pwd)"
# shellcheck source=lib/common.sh
source Scripts/lib/common.sh

configuration="debug"
if (($# > 0)); then
  case "$1" in
    debug|release) configuration="$1"; shift ;;
  esac
fi
while (($# > 0)); do
  case "$1" in
    --data-root) export CODOMETER_DATA_ROOT="${2:-}"; shift 2 ;;
    -h|--help) print_header_help "$0"; exit 0 ;;
    *) die "usage: $0 [debug|release] [--data-root <dir>]" 64 ;;
  esac
done

if [[ "$configuration" == "release" && "${CODOMETER_ALLOW_RELEASE_RUN:-0}" != "1" ]]; then
  die "refusing to run a release build. Release configuration may be built and inspected, not run: the release
  launch path performs the legacy data migration. Build it with Scripts/build-app.sh release, or set
  CODOMETER_ALLOW_RELEASE_RUN=1 if you really mean it (an isolated data root is still required)." 64
fi

require_isolated_data_root
mkdir -p "$CODOMETER_DATA_ROOT"
chmod 700 "$CODOMETER_DATA_ROOT"

# Spelled out as two calls rather than an argument array: macOS ships bash 3.2, where expanding an empty
# array under `set -u` is an "unbound variable" error, so `"${flags[@]}"` would break this script the day
# Scripts/build-icon.sh appears.
if [[ -x Scripts/build-icon.sh ]]; then
  Scripts/build-app.sh "$configuration"
else
  Scripts/build-app.sh "$configuration" --allow-missing-icon
fi

app="$TREE/build/Codometer.app"
executable="$app/Contents/MacOS/Codometer"
[[ -x "$executable" ]] || die "no executable at $executable"

# Only this tree's copy, matched on the full executable path.
if pgrep -f "^$executable$" >/dev/null 2>&1; then
  echo "Stopping the previous copy from $app"
  pkill -f "^$executable$" || true
  sleep 1
fi

echo "Launching $executable"
echo "  CODOMETER_DATA_ROOT=$CODOMETER_DATA_ROOT"
env | grep '^CODOMETER_DATA_ROOT=' >/dev/null || die "CODOMETER_DATA_ROOT is not exported"
exec "$executable"
