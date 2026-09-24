#!/usr/bin/env bash
# Measures idle CPU, memory and wakeups of a built Codometer.app against the performance budgets.
#
#   Scripts/perf-smoke.sh [--app <app>] [--duration <seconds>] [--style island|floatingCard]
#                         [--data-root <dir>] [--keep-data-root]
#
# Budgets (release build; a debug build is measured but reported as indicative only):
#   idle CPU over the sample window   avg ≤ 0.5 %, p95 ≤ 2 %
#   idle wakeups                      ≤ 1 per second on average
#   RSS                               steady ≤ 120 MB, peak ≤ 160 MB
#   launch → surface visible          ≤ 1.0 s   (needs os_signpost; skipped while none are emitted)
#
# Safety, because this is the one release script that starts the app:
#   · an isolated CODOMETER_DATA_ROOT under ~/Library/Caches is required and is created here, so the run
#     never touches the real data folder;
#   · the executable is run directly — never `open`, which would drop the environment;
#   · only the process this script started is stopped, by pid, never `pkill` by name;
#   · the harness lock serializes this against every other GUI run;
#   · the data root is deleted at the end, and the real folders are checked afterwards.
set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck source=lib/common.sh
source Scripts/lib/common.sh

APP="build/Codometer.app"
DURATION=120
STYLE=""
KEEP_ROOT=0

while (($# > 0)); do
  case "$1" in
    --app) APP="${2:-}"; shift 2 ;;
    --duration) DURATION="${2:-}"; shift 2 ;;
    --style) STYLE="${2:-}"; shift 2 ;;
    --data-root) export CODOMETER_DATA_ROOT="${2:-}"; shift 2 ;;
    --keep-data-root) KEEP_ROOT=1; shift ;;
    -h|--help) print_header_help "$0"; exit 0 ;;
    *) die "unknown option: $1" 64 ;;
  esac
done

[[ "$DURATION" =~ ^[0-9]+$ ]] || die "--duration must be a whole number of seconds" 64
[[ -d "$APP" ]] || die "no bundle at $APP" 66
APP="$(cd "$APP" && pwd)"
EXECUTABLE="$APP/Contents/MacOS/Codometer"
[[ -x "$EXECUTABLE" ]] || die "no executable at $EXECUTABLE" 66

: "${CODOMETER_DATA_ROOT:=$HOME/Library/Caches/CodometerDev/data/perf-smoke-$$}"
export CODOMETER_DATA_ROOT
require_isolated_data_root

PID=""
LOCK_TAKEN=0
cleanup() {
  local status=$?
  set +e
  if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null
    local waited=0
    while kill -0 "$PID" 2>/dev/null && ((waited < 10)); do sleep 1; waited=$((waited + 1)); done
    kill -9 "$PID" 2>/dev/null
  fi
  if ((KEEP_ROOT == 0)) && [[ -n "${CODOMETER_DATA_ROOT:-}" && -d "$CODOMETER_DATA_ROOT" ]]; then
    rm -rf "$CODOMETER_DATA_ROOT"
  fi
  ((LOCK_TAKEN == 1)) && release_harness_lock
  exit "$status"
}
trap cleanup EXIT

heading "perf-smoke"
note "app        $APP"
note "data root  $CODOMETER_DATA_ROOT"
note "duration   ${DURATION}s"

# Release or debug? The budgets are release numbers; a debug build carries assertions and no optimizer.
CONFIGURATION="release"
if strings -a "$EXECUTABLE" | stream_has 'CODOMETER_DEBUG_SCENARIO'; then
  CONFIGURATION="debug"
  check_warn "this is a debug build: the numbers below are indicative, not a budget result"
fi

take_harness_lock 900
LOCK_TAKEN=1
note "harness lock held"

mkdir -p "$CODOMETER_DATA_ROOT"
chmod 700 "$CODOMETER_DATA_ROOT"

# An isolated root starts empty, so the app creates its own defaults and discovers nothing. A presentation
# style can be pre-set because settings decoding is lenient: an unknown value falls back to the default.
if [[ -n "$STYLE" ]]; then
  printf '{"schemaVersion":1,"appearance":{"presentationStyle":"%s"}}\n' "$STYLE" > "$CODOMETER_DATA_ROOT/settings.json"
  chmod 600 "$CODOMETER_DATA_ROOT/settings.json"
  note "presentation style: $STYLE"
fi

env | stream_has_re '^CODOMETER_DATA_ROOT=' || die "CODOMETER_DATA_ROOT is not exported"

SAMPLES="$(mktemp "${TMPDIR:-/tmp}/codometer-perf-XXXXXX")"
WAKEUPS="$(mktemp "${TMPDIR:-/tmp}/codometer-wake-XXXXXX")"

"$EXECUTABLE" > "$CODOMETER_DATA_ROOT/stdout.log" 2>&1 &
PID=$!
# Out of the job table, so the shell does not print "Terminated" over the results when it is stopped.
disown %+ 2>/dev/null || true
note "pid $PID"

# Give the app time to reach its steady state before sampling: launch work is measured separately.
sleep 5
kill -0 "$PID" 2>/dev/null || die "the app exited during launch; see $CODOMETER_DATA_ROOT/stdout.log"

heading "Sampling"
elapsed=0
while ((elapsed < DURATION)); do
  if ! kill -0 "$PID" 2>/dev/null; then
    check_fail "the app exited after ${elapsed}s"
    break
  fi
  ps -o %cpu=,rss= -p "$PID" | awk '{ print $1, $2 }' >> "$SAMPLES"
  sleep 2
  elapsed=$((elapsed + 2))
done

# Idle wakeups: one `top` sample over the window, which reports the per-process counter.
top -l 2 -s 1 -pid "$PID" -stats pid,cpu,idlew 2>/dev/null | awk -v pid="$PID" '$1 == pid { print $3 }' > "$WAKEUPS" || true

heading "Results ($CONFIGURATION build)"

read -r CPU_AVG CPU_P95 RSS_AVG RSS_PEAK SAMPLE_COUNT <<< "$(
  awk '{ cpu[NR] = $1; rss[NR] = $2; cpuSum += $1; rssSum += $2; if ($2 > rssMax) rssMax = $2 }
       END {
         n = NR
         if (n == 0) { print "0 0 0 0 0"; exit }
         # p95 of the CPU samples
         for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++) if (cpu[j] < cpu[i]) { t = cpu[i]; cpu[i] = cpu[j]; cpu[j] = t }
         idx = int(n * 0.95); if (idx < 1) idx = 1
         printf "%.2f %.2f %.1f %.1f %d", cpuSum / n, cpu[idx], rssSum / n / 1024, rssMax / 1024, n
       }' "$SAMPLES"
)"

note "$SAMPLE_COUNT samples over ${elapsed}s"

budget() { # budget <name> <value> <limit> <unit>
  if awk -v v="$2" -v l="$3" 'BEGIN { exit !(v <= l) }'; then
    check_pass "$1: $2 $4 (budget $3 $4)"
  elif [[ "$CONFIGURATION" == "debug" ]]; then
    check_warn "$1: $2 $4 over the $3 $4 budget — debug build, not a release result"
  else
    check_fail "$1: $2 $4 exceeds the $3 $4 budget"
  fi
}

budget "idle CPU average" "$CPU_AVG" 0.5 "%"
budget "idle CPU p95" "$CPU_P95" 2 "%"
budget "RSS steady" "$RSS_AVG" 120 "MB"
budget "RSS peak" "$RSS_PEAK" 160 "MB"

if [[ -s "$WAKEUPS" ]]; then
  wakes="$(sed -n '$p' "$WAKEUPS")"
  budget "idle wakeups" "$wakes" 1 "per second"
else
  check_skip "idle wakeups: top reported no counter for this process"
fi

# The launch budget needs os_signpost intervals (`launch` → the first visible surface). Nothing emits them
# yet, so this is reported as missing rather than guessed from wall-clock time.
if log show --last 2m --signpost --predicate 'subsystem == "com.codometer.app"' 2>/dev/null | stream_has 'railVisible'; then
  check_skip "launch → surface: signposts found but not yet parsed by this script"
else
  check_skip "launch → surface visible: the app emits no os_signpost intervals yet (needs \`launch\`/\`railVisible\` signposts)"
fi

note "power state at the end:"
pmset -g batt 2>/dev/null | sed 's/^/        /' || true
pmset -g therm 2>/dev/null | sed -n '1,3p' | sed 's/^/        /' || true

heading "Shutting down"
kill "$PID" 2>/dev/null || true
waited=0
while kill -0 "$PID" 2>/dev/null && ((waited < 10)); do sleep 1; waited=$((waited + 1)); done
PID=""
check_pass "stopped the process this script started (by pid, never by name)"

rm -f "$SAMPLES" "$WAKEUPS"

# The two facts that must hold after any run that started the app.
assert_real_data_untouched
check_pass "the real data folder was not touched"

heading "perf-smoke summary"
printf '  %d passed, %d failed, %d skipped, %d warnings\n' \
  "$CHECKS_PASSED" "$CHECKS_FAILED" "$CHECKS_SKIPPED" "$CHECKS_WARNED"
((CHECKS_FAILED == 0)) || exit 1
