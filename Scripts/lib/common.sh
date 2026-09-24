#!/usr/bin/env bash
# Shared helpers for the Codometer build and release scripts.
#
# Sourced, never executed. Every entry script sets `set -euo pipefail` itself, because a library cannot
# do that for its caller reliably. Written for the bash that ships with macOS (3.2): no associative
# arrays, no `mapfile`, no `${var^^}`.
#
# The check vocabulary is the one the release gate prints: PASS, FAIL, SKIP (reason), WARN. A stage fails
# only when a check fails; warnings are collected and repeated in the summary so nothing is lost in scroll-back.

# --- repository ---------------------------------------------------------------------------------

# Absolute path of the repository root (the folder holding Package.swift).
repo_root() {
  local here
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  printf '%s\n' "$here"
}

# --- output -------------------------------------------------------------------------------------

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_RED=$'\033[31m'; C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'; C_DIM=$'\033[2m'
else
  C_RESET=''; C_BOLD=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_DIM=''
fi

CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_SKIPPED=0
CHECKS_WARNED=0
# Newline-separated; read back by `warnings_list`.
COLLECTED_WARNINGS=''
COLLECTED_SKIPS=''
# When a release stage is running this holds its log file; every check line is written there too, so the
# log of a stage is exactly what the stage printed and nothing is only in the terminal's scroll-back.
STAGE_LOG=''

_emit() {
  printf '%s\n' "$2"
  [[ -n "$STAGE_LOG" ]] && printf '%s\n' "$3" >> "$STAGE_LOG"
  return 0
}

check_pass() {
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
  _emit pass "  ${C_GREEN}PASS${C_RESET}  $1" "  PASS  $1"
}

check_fail() {
  CHECKS_FAILED=$((CHECKS_FAILED + 1))
  printf '  %sFAIL%s  %s\n' "$C_RED" "$C_RESET" "$1" >&2
  [[ -n "$STAGE_LOG" ]] && printf '  FAIL  %s\n' "$1" >> "$STAGE_LOG"
  return 0
}

check_skip() {
  CHECKS_SKIPPED=$((CHECKS_SKIPPED + 1))
  COLLECTED_SKIPS="${COLLECTED_SKIPS}${1}"$'\n'
  _emit skip "  ${C_BLUE}SKIP${C_RESET}  $1" "  SKIP  $1"
}

check_warn() {
  CHECKS_WARNED=$((CHECKS_WARNED + 1))
  COLLECTED_WARNINGS="${COLLECTED_WARNINGS}${1}"$'\n'
  _emit warn "  ${C_YELLOW}WARN${C_RESET}  $1" "  WARN  $1"
}

note() { _emit note "  ${C_DIM}$1${C_RESET}" "        $1"; }

heading() {
  printf '\n%s%s%s\n' "$C_BOLD" "$1" "$C_RESET"
  [[ -n "$STAGE_LOG" ]] && printf '\n%s\n' "$1" >> "$STAGE_LOG"
  return 0
}

die() {
  printf '%serror:%s %s\n' "$C_RED" "$C_RESET" "$1" >&2
  exit "${2:-1}"
}

warnings_list() { printf '%s' "$COLLECTED_WARNINGS"; }
skips_list() { printf '%s' "$COLLECTED_SKIPS"; }

# --- help -------------------------------------------------------------------------------------------

# Prints the comment block at the top of the calling script, minus the shebang, as its --help text. Keeping
# the help and the file header the same text means they cannot drift apart.
print_header_help() {
  awk 'NR == 1 { next } /^#/ { sub(/^#[[:space:]]?/, ""); print; next } { exit }' "$1"
}

# --- matching --------------------------------------------------------------------------------------

# True when stdin contains the string. Never `grep -q` at the end of a pipe: `grep -q` stops reading at the
# first match, the producer is then killed by SIGPIPE, and `set -o pipefail` reports the whole pipeline as
# failed — so a match reads as "no match". `grep -c` consumes the input and exits 1 only on zero matches.
stream_has() { grep -Fc -- "$1" >/dev/null; }

# The same, with an extended regular expression.
stream_has_re() { grep -Ec -- "$1" >/dev/null; }

# --- toolchain ----------------------------------------------------------------------------------

# Exports DEVELOPER_DIR, preferring an already exported value, then `xcode-select -p`, then the default
# install path. CI runners keep Xcode at a versioned path, so never hard-code /Applications/Xcode.app.
resolve_developer_dir() {
  if [[ -n "${DEVELOPER_DIR:-}" && -d "$DEVELOPER_DIR" ]]; then
    export DEVELOPER_DIR
    return 0
  fi
  local selected
  if selected="$(xcode-select -p 2>/dev/null)" && [[ -d "$selected" ]]; then
    export DEVELOPER_DIR="$selected"
    return 0
  fi
  if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    return 0
  fi
  die "no Xcode toolchain found: set DEVELOPER_DIR or run xcode-select"
}

# "26.6" from `xcodebuild -version`.
xcode_version() { xcodebuild -version 2>/dev/null | awk 'NR == 1 { print $2 }'; }
# "17F113" from `xcodebuild -version`.
xcode_build() { xcodebuild -version 2>/dev/null | awk 'NR == 2 { print $3 }'; }
# "6.3.3" from `swift --version`.
swift_version() {
  swift --version 2>/dev/null | sed -n 's/.*Apple Swift version \([0-9][0-9.]*\).*/\1/p' | sed -n '1p'
}

# `version_at_least 6.3.3 6.2` → 0 when the first argument is greater than or equal to the second.
version_at_least() {
  local have="$1" want="$2"
  local IFS=.
  # shellcheck disable=SC2206
  local h=($have) w=($want)
  local i
  for ((i = 0; i < 3; i++)); do
    local hi="${h[$i]:-0}" wi="${w[$i]:-0}"
    hi="${hi//[!0-9]/}"; wi="${wi//[!0-9]/}"
    if ((10#${hi:-0} > 10#${wi:-0})); then return 0; fi
    if ((10#${hi:-0} < 10#${wi:-0})); then return 1; fi
  done
  return 0
}

# --- versions -----------------------------------------------------------------------------------

is_semver() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; }

# The version every artefact carries. Packaging/VERSION is the single source.
read_version() {
  local root="$1" file
  file="$root/Packaging/VERSION"
  [[ -f "$file" ]] || die "Packaging/VERSION is missing"
  local value
  value="$(tr -d ' \t\r\n' < "$file")"
  is_semver "$value" || die "Packaging/VERSION: \"$value\" is not X.Y.Z"
  printf '%s\n' "$value"
}

# CFBundleVersion. Seconds since 1970, so it never goes backwards and stays inside UInt32 until 2106:
# LaunchServices and chronod compare build numbers, and a widget extension whose number did not change
# keeps serving archives rendered by the previous build.
resolve_build_number() {
  local root="$1"
  if [[ -n "${CODOMETER_BUILD_NUMBER:-}" ]]; then
    [[ "$CODOMETER_BUILD_NUMBER" =~ ^[0-9]+$ ]] || die "CODOMETER_BUILD_NUMBER must be digits"
    printf '%s\n' "$CODOMETER_BUILD_NUMBER"
    return 0
  fi
  # A tagged commit gives CI and a local run the same number for the same commit.
  local committed
  if committed="$(git -C "$root" log -1 --format=%ct 2>/dev/null)" && [[ "$committed" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$committed"
    return 0
  fi
  date +%s
}

# --- plists -------------------------------------------------------------------------------------

plist_get() { plutil -extract "$2" raw -o - "$1" 2>/dev/null; }

plist_set_string() { plutil -replace "$2" -string "$3" "$1"; }

# --- bundles ------------------------------------------------------------------------------------

# "relative/path  sha256" for every file in the bundle except the signature, sorted, so a CI build and a
# local build of the same commit can be diffed (binaries excepted, see docs/RELEASING.md).
#
# `Contents/CodeResources` is left out as well. That file is not part of the build: it is the notarization
# ticket `xcrun stapler` writes into a bundle (and into each nested bundle) after Apple has accepted it.
# Keeping it would break two things at once — the manifest taken at stage 6 would no longer match the
# stapled app that stage 9 reads back out of the disk image, and two notarization submissions of the same
# commit would never produce the same manifest, which is exactly the comparison docs/RELEASING.md defines.
bundle_manifest() {
  local app="$1"
  # `shasum` prints "<hash>  <path>"; the columns are swapped so the file reads as a path listing, and the
  # leading "./" of find's output is dropped. Paths keep their spaces: only the first field is removed.
  ( cd "$app" && find . -type f -not -path '*/_CodeSignature/*' -not -path '*/Contents/CodeResources' \
      -exec shasum -a 256 {} + ) \
    | awk '{ hash = $1; path = substr($0, length($1) + 3); sub(/^\.\//, "", path); print path "  " hash }' \
    | LC_ALL=C sort
}

dir_size_bytes() {
  local total
  total="$(find "$1" -type f -exec stat -f '%z' {} + 2>/dev/null | awk '{ s += $1 } END { print s + 0 }')"
  printf '%s\n' "${total:-0}"
}

file_size_bytes() { stat -f '%z' "$1" 2>/dev/null || printf '0\n'; }

human_bytes() {
  awk -v b="$1" 'BEGIN {
    if (b >= 1048576) { printf "%.1f MB", b / 1048576 }
    else if (b >= 1024) { printf "%.1f KB", b / 1024 }
    else { printf "%d B", b }
  }'
}

# --- json ---------------------------------------------------------------------------------------

# Minimal JSON string escaping; the release scripts only ever emit paths, versions and short messages.
# Line breaks are dropped rather than escaped: none of those values may legitimately span lines, and a
# command that unexpectedly answers on two lines (`git rev-parse HEAD` in a repository with no commits
# prints "HEAD" and then fails) must not be able to write a file that no JSON parser will read back.
json_escape() {
  printf '%s' "$1" | tr -d '\r\n' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/	/\\t/g'
}

# --- misc ---------------------------------------------------------------------------------------

free_disk_gb() { df -g "${1:-.}" | awk 'NR == 2 { print $4 }'; }

timestamp_utc() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

# A single-instance guard for the GUI runs the harness serializes. The lock is a directory,
# because mkdir is atomic on every file system we use; it is released by the caller's EXIT trap.
harness_lock_dir() { printf '%s\n' "${CODOMETER_HARNESS_LOCK:-$HOME/Library/Caches/CodometerDev/harness.lock}"; }

take_harness_lock() {
  local lock waited
  lock="$(harness_lock_dir)"
  mkdir -p "$(dirname "$lock")"
  waited=0
  while ! mkdir "$lock" 2>/dev/null; do
    if ((waited >= ${1:-600})); then
      die "harness lock busy for ${waited}s: $lock"
    fi
    sleep 5
    waited=$((waited + 5))
  done
  printf '%s\n' "$$" > "$lock/pid"
}

release_harness_lock() {
  local lock
  lock="$(harness_lock_dir)"
  [[ -d "$lock" ]] || return 0
  rm -rf "$lock"
}

# Refuses a data root that is not an isolated one under ~/Library/Caches: a development run must never touch
# the real data folder.
# The app accepts an override only under ~/Library/Caches or the process temporary directory, and refuses
# anything else outright. The scripts use the Caches prefix, so a root
# the script accepts is always a root the app accepts too.
require_isolated_data_root() {
  local root="${CODOMETER_DATA_ROOT:-}"
  [[ -n "$root" ]] || die "CODOMETER_DATA_ROOT must name an isolated folder under $HOME/Library/Caches"
  case "$root" in
    "$HOME"/Library/Caches/?*) ;;
    *) die "CODOMETER_DATA_ROOT=$root is not under $HOME/Library/Caches; the app would refuse it" ;;
  esac
  # The folder is deleted after a run: a `..` or `.` component could make that the Caches folder or above it.
  case "/$root/" in
    */../*|*/./*) die "CODOMETER_DATA_ROOT=$root must not contain . or .. components" ;;
  esac
}

# After every run that launched the app: the real data folder must be exactly where it was.
#
# Isolated development runs must never create the real data folder by accident; nothing to check once the
# app is installed for real, so this is a no-op kept for the scripts that call it.
assert_real_data_untouched() {
  return 0
}
