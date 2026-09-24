#!/usr/bin/env bash
# The policy gate. Runs on plain grep/awk so every agent and every runner can run it without installing
# anything, and wraps the Swift-side localization lints so one command covers both halves.
#
#   Scripts/lint.sh                 policy rules + CodometerSourceLintTests
#   Scripts/lint.sh --skip-tests    policy rules only (fast; the release gate still runs the Swift tests)
#   Scripts/lint.sh --advisory      also print the `privacy: .public` inventory (never fails)
#   Scripts/lint.sh --rules         list the rule ids used in Scripts/lint-allow.txt
#
# Exceptions live in Scripts/lint-allow.txt, never in this file, so an exception is always visible in a diff.
#
# Comments are stripped before the rules run (an `// URLSession` in prose is not a network call), but string
# literals are kept, because a forbidden identifier hidden in a string is exactly what these rules look for.
set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck source=lib/common.sh
source Scripts/lib/common.sh

ALLOW_FILE="Scripts/lint-allow.txt"
RUN_TESTS=1
ADVISORY=0

while (($# > 0)); do
  case "$1" in
    --skip-tests) RUN_TESTS=0 ;;
    --advisory) ADVISORY=1 ;;
    --rules)
      cat <<'EOF'
try-bang            `try!`
fatal-error         `fatalError(` outside an unavailable init(coder:)
print               `print(` (use AppLog)
timeline-animation  `TimelineView(.animation` (per-frame SwiftUI loop)
repeat-forever      `.repeatForever` (endless SwiftUI animation)
symbol-effect       a repeating `.symbolEffect(`
bundle-module       `Bundle.module` (cannot ship inside a hand-assembled .app)
ru-locale           `Locale(identifier: "ru_RU")`
locale-region       `Locale(identifier:` with a fixed region outside CodometerL10n/Localizer.swift
network             `URLSession` / `NWConnection` outside Platform/Network/StatusFeedClient.swift
user-defaults       `UserDefaults` / `CFPreferences` outside the language shim
defaults-key        a defaults key other than AppleLanguages or NSApplicationCrashOnExceptions
window-autosave     a window frame autosave name
process             `posix_spawn` / `Process(` outside Platform/Process
debug-guard         a Debug source whose first line of code is not `#if DEBUG`
l10n-pending        a leftover `l10n: pending` marker
doc-images          a README image link that does not resolve
shell-empty-array   `"${name[@]}"` on an array that can be empty (bash 3.2 + set -u)
shell-find-maxdepth a file search that sets its depth limit twice
EOF
      exit 0
      ;;
    -h|--help) print_header_help "$0"; exit 0 ;;
    *) die "unknown option: $1" 64 ;;
  esac
  shift
done

WORK="$(mktemp -d "${TMPDIR:-/tmp}/codometer-lint-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# --- the code stream ------------------------------------------------------------------------------
#
# "path:line:code" for every Swift source, with `//` comments removed. A `//` only starts a comment when
# the quotes before it on the line are balanced, so `let s = "http://x"` keeps its literal.

strip_comments() {
  awk -v path="$1" '
    {
      line = $0
      out = ""
      quotes = 0
      i = 1
      n = length(line)
      while (i <= n) {
        c = substr(line, i, 1)
        if (c == "\\" && quotes % 2 == 1) { out = out substr(line, i, 2); i += 2; continue }
        if (c == "\"") { quotes++ }
        if (c == "/" && substr(line, i + 1, 1) == "/" && quotes % 2 == 0) { break }
        out = out c
        i++
      }
      print path ":" NR ":" out
    }
  ' "$1"
}

build_stream() {
  local target="$1" f
  : > "$target"
  while IFS= read -r f; do
    strip_comments "$f" >> "$target"
  done < <(find Sources -name '*.swift' -type f | LC_ALL=C sort)
}

STREAM="$WORK/code.txt"
build_stream "$STREAM"
SOURCE_FILES="$(grep -c . < <(find Sources -name '*.swift' -type f) || true)"

# --- the allow list -------------------------------------------------------------------------------

# allowed <rule> <path> <code> → 0 when an entry in Scripts/lint-allow.txt covers this hit.
allowed() {
  local rule="$1" path="$2" code="$3"
  [[ -f "$ALLOW_FILE" ]] || return 1
  local line entry_rule entry_glob entry_sub
  while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    entry_rule="${line%%|*}"; entry_rule="$(printf '%s' "$entry_rule" | sed 's/[[:space:]]*$//')"
    [[ "$entry_rule" == "$rule" ]] || continue
    local rest="${line#*|}"
    entry_glob="${rest%%|*}"
    entry_sub="${rest#*|}"
    entry_glob="$(printf '%s' "$entry_glob" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    entry_sub="$(printf '%s' "$entry_sub" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    # shellcheck disable=SC2254
    case "$path" in
      $entry_glob) ;;
      *) continue ;;
    esac
    if [[ "$entry_sub" == "*" || "$code" == *"$entry_sub"* ]]; then
      return 0
    fi
  done < "$ALLOW_FILE"
  return 1
}

FAILURES=0
RULES_RUN=0

# report <rule> <message> <hits>   (hits: newline-separated "path:line:code", may be empty)
#
# Called directly, never through a pipe: a pipeline would run this in a subshell and the failure count
# would be thrown away with it.
report() {
  local rule="$1" message="$2" hits="$3"
  RULES_RUN=$((RULES_RUN + 1))
  local hit path lineno code rest shown=0
  local saved_ifs="$IFS"
  IFS=$'\n'
  for hit in $hits; do
    [[ -n "$hit" ]] || continue
    path="${hit%%:*}"
    rest="${hit#*:}"
    lineno="${rest%%:*}"
    code="${rest#*:}"
    if allowed "$rule" "$path" "$code"; then continue; fi
    if ((shown == 0)); then
      printf '  %sFAIL%s  %s — %s\n' "$C_RED" "$C_RESET" "$rule" "$message" >&2
      shown=1
    fi
    printf '          %s:%s: %s\n' "$path" "$lineno" "$(printf '%s' "$code" | sed 's/^[[:space:]]*//')" >&2
  done
  IFS="$saved_ifs"
  if ((shown == 1)); then
    FAILURES=$((FAILURES + 1))
    return 0
  fi
  printf '  %sPASS%s  %s\n' "$C_GREEN" "$C_RESET" "$rule"
}

# grep_rule <rule> <message> <extended-regex> [path-exclude-regex]
grep_rule() {
  local rule="$1" message="$2" pattern="$3" exclude="${4:-}"
  local hits
  if [[ -n "$exclude" ]]; then
    hits="$(grep -E "$pattern" "$STREAM" | grep -Ev "^($exclude):" || true)"
  else
    hits="$(grep -E "$pattern" "$STREAM" || true)"
  fi
  report "$rule" "$message" "$hits"
}

heading "Policy lint ($SOURCE_FILES Swift sources)"

grep_rule try-bang "force try hides a failure the app could report" 'try!'

# fatalError is allowed in the unavailable init(coder:) every AppKit subclass must declare. The check looks
# back a few lines for that initialiser rather than parsing Swift.
fatal_hits=''
while IFS= read -r hit; do
  [[ -n "$hit" ]] || continue
  path="${hit%%:*}"; rest="${hit#*:}"; lineno="${rest%%:*}"
  start=$((lineno - 6)); ((start < 1)) && start=1
  if sed -n "${start},${lineno}p" "$path" | stream_has_re 'init[?]?\(coder'; then continue; fi
  fatal_hits="${fatal_hits}${hit}"$'\n'
done < <(grep -E 'fatalError\(' "$STREAM" || true)
report fatal-error "fatalError outside an unavailable init(coder:)" "$fatal_hits"

grep_rule print "print() bypasses the unified log and leaks into release output" '(^|[^A-Za-z0-9_.])print\('
grep_rule timeline-animation "TimelineView(.animation) redraws every frame forever" 'TimelineView\(\.animation'
grep_rule repeat-forever "an endless SwiftUI animation keeps the CPU awake; use a CA layer" '\.repeatForever'
# `.symbolEffect` is fine for a one-shot. Only a repeating one keeps the CPU awake, and it always says so:
# `.contentTransition(.symbolEffect(.replace))` and `options: .nonRepeating` are one-shots.
symbol_hits="$(grep -E '\.symbolEffect\(' "$STREAM" | grep -Ei '(repeat|indefinite|periodic)' | grep -v 'nonRepeating' || true)"
report symbol-effect "a repeating symbolEffect keeps the CPU awake" "$symbol_hits"
grep_rule bundle-module "Bundle.module cannot be loaded from a hand-assembled .app" 'Bundle\.module'
grep_rule ru-locale "a hard-coded ru_RU locale ignores the language setting" 'Locale\(identifier: *"ru_RU"'
grep_rule locale-region "a fixed locale belongs in CodometerL10n, not in a feature" \
  'Locale\(identifier: *"' 'Sources/CodometerL10n/Localizer\.swift'
grep_rule network "the only place allowed to open a connection is StatusFeedClient" \
  '(URLSession|NWConnection)' 'Sources/CodometerPlatform/Network/StatusFeedClient\.swift'
grep_rule user-defaults "settings live in settings.json; defaults are only for the language shim" \
  '(UserDefaults|CFPreferences)'
grep_rule window-autosave "a new autosave name writes a new defaults key" '[Ff]rameAutosaveName'
grep_rule process "spawning belongs in Platform/Process (signature-verified vendor binaries only)" \
  '(posix_spawn|[^A-Za-z0-9_.]Process\()' 'Sources/CodometerPlatform/Process/[A-Za-z]+\.swift'

# In a file that touches the defaults system, a quoted literal next to a key-shaped expression is a
# defaults key. Only two keys are allowed: the language override and the crash-on-exception switch.
defaults_files="$(grep -E '(UserDefaults|CFPreferences)' "$STREAM" | cut -d: -f1 | LC_ALL=C sort -u || true)"
key_hits=''
if [[ -n "$defaults_files" ]]; then
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    while IFS= read -r hit; do
      [[ -n "$hit" ]] || continue
      code="${hit#*:}"; code="${code#*:}"
      for key in $(printf '%s' "$code" | grep -oE '"[A-Za-z][A-Za-z0-9 ._-]*"' || true); do
        case "$key" in
          '"AppleLanguages"'|'"NSApplicationCrashOnExceptions"') ;;
          *) key_hits="${key_hits}${hit}"$'\n' ;;
        esac
      done
    done < <(grep -E "^$f:" "$STREAM" | grep -E '(forKey:|forName:|register\(defaults:|CFPreferences|[Kk]ey[[:space:]]*[:=])' | grep '"' || true)
  done < <(printf '%s\n' "$defaults_files")
fi
report defaults-key "an unexpected UserDefaults key" "$key_hits"

# Debug sources must compile away in release. The first line that is neither blank nor a comment is #if DEBUG.
debug_hits=''
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  first="$(grep -nvE '^[[:space:]]*(//.*)?$' "$f" | sed -n '1p')"
  lineno="${first%%:*}"
  code="${first#*:}"
  if [[ "$(printf '%s' "$code" | sed 's/[[:space:]]*$//')" != "#if DEBUG" ]]; then
    debug_hits="${debug_hits}${f}:${lineno}:${code}"$'\n'
  fi
done < <(find Sources -type f \( -path 'Sources/*/Debug/*.swift' -o -name 'Debug*.swift' \) | LC_ALL=C sort)
report debug-guard "a Debug source that does not start with #if DEBUG" "$debug_hits"

# --- the release scripts themselves -----------------------------------------------------------------
#
# The scripts are the release gate, and a gate that silently stops working is worse than no gate. These two
# rules cover the mistakes that shell makes easy and that this project has already made once each:
#
#   · macOS ships bash 3.2, where expanding an EMPTY array as "${name[@]}" under `set -u` is an "unbound
#     variable" error, not an empty expansion. An array filled in only on one branch therefore works right
#     up to the first run that takes the other branch.
#   · a search that names two depths ("… 1 -name A -o … 2 -path B") reads like two scopes and is one:
#     the depth option is global, the last one wins, and the clause written for the other depth silently
#     stops matching — a check that then passes because it is looking nowhere.
#
# `bash -n` (release stage 2) catches neither: both are valid shell. Comments are blanked out first — the
# comment that explains a rule is the one place the forbidden shape is written on purpose — while the line
# numbering stays intact, so a hit still points at the real line.

empty_array_hits=''
maxdepth_hits=''
while IFS= read -r script; do
  [[ -n "$script" ]] || continue
  stripped="$WORK/shell-$(printf '%s' "$script" | tr '/' '-')"
  sed 's/#.*$//' "$script" > "$stripped"

  for name in $(grep -oE '(^|[[:space:]])(local[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*=\(\)' "$stripped" \
                  | sed -E 's/.*[[:space:]]//; s/=\(\)//' | LC_ALL=C sort -u); do
    while IFS= read -r hit; do
      [[ -n "$hit" ]] || continue
      empty_array_hits="${empty_array_hits}${script}:${hit}"$'\n'
    done < <(grep -nF "\${$name[@]}" "$stripped" || true)
  done

  while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    maxdepth_hits="${maxdepth_hits}${script}:${hit}"$'\n'
  done < <(grep -nE 'find[^|]*-maxdepth[^|]*-maxdepth' "$stripped" || true)
done < <(find Scripts -name '*.sh' -type f | LC_ALL=C sort)

report shell-empty-array \
  'an array that can be empty, expanded as "${name[@]}": in bash 3.2 with set -u that is an error, not an empty list' \
  "$empty_array_hits"
report shell-find-maxdepth \
  "a file search that sets its depth limit twice: only the last limit applies and the other clause never matches" \
  "$maxdepth_hits"

# --- localization markers -------------------------------------------------------------------------

pending="$(grep -rn 'l10n: pending' Sources || true)"
RULES_RUN=$((RULES_RUN + 1))
if [[ -n "$pending" ]]; then
  printf '  %sFAIL%s  l10n-pending — untranslated text left in the sources\n' "$C_RED" "$C_RESET" >&2
  printf '%s\n' "$pending" | sed 's/^/          /' >&2
  FAILURES=$((FAILURES + 1))
else
  printf '  %sPASS%s  l10n-pending\n' "$C_GREEN" "$C_RESET"
fi

# --- documentation images -------------------------------------------------------------------------
#
# Every image the READMEs link must exist. Without a docs/images folder there is nothing to resolve, so the
# rule reports a skip rather than inventing a failure.

RULES_RUN=$((RULES_RUN + 1))
if [[ -d docs/images ]]; then
  missing=''
  for doc in README.md README.ru.md; do
    [[ -f "$doc" ]] || continue
    while IFS= read -r link; do
      [[ -n "$link" ]] || continue
      case "$link" in http*|'') continue ;; esac
      [[ -e "$link" ]] || missing="${missing}${doc}: ${link}"$'\n'
    done < <(grep -oE '!\[[^]]*\]\([^)]+\)' "$doc" | sed -E 's/.*\(([^)]*)\).*/\1/' | sed 's/ .*//' || true)
  done
  if [[ -n "$missing" ]]; then
    printf '  %sFAIL%s  doc-images — a README image link does not resolve\n' "$C_RED" "$C_RESET" >&2
    printf '%s' "$missing" | sed 's/^/          /' >&2
    FAILURES=$((FAILURES + 1))
  else
    printf '  %sPASS%s  doc-images\n' "$C_GREEN" "$C_RESET"
  fi
else
  printf '  %sSKIP%s  doc-images — there is no docs/images folder\n' "$C_BLUE" "$C_RESET"
fi

# --- advisory -------------------------------------------------------------------------------------

if ((ADVISORY == 1)); then
  heading "Advisory (never fails the gate)"
  public_logs="$(grep -c 'privacy: \.public' "$STREAM" || true)"
  note "$public_logs log interpolations marked privacy: .public — check each one for paths, labels and e-mail"
  grep -n 'privacy: \.public' "$STREAM" | sed 's/^/    /' || true
fi

# --- the Swift half -------------------------------------------------------------------------------

if ((RUN_TESTS == 1)); then
  heading "CodometerSourceLintTests"
  resolve_developer_dir
  if swift test --filter CodometerSourceLintTests 2>&1 | tail -20; then
    printf '  %sPASS%s  swift test --filter CodometerSourceLintTests\n' "$C_GREEN" "$C_RESET"
  else
    printf '  %sFAIL%s  swift test --filter CodometerSourceLintTests\n' "$C_RED" "$C_RESET" >&2
    FAILURES=$((FAILURES + 1))
  fi
else
  heading "CodometerSourceLintTests"
  printf '  %sSKIP%s  --skip-tests\n' "$C_BLUE" "$C_RESET"
fi

heading "Lint summary"
if ((FAILURES > 0)); then
  printf '  %s%d of %d rules failed%s\n' "$C_RED" "$FAILURES" "$RULES_RUN" "$C_RESET" >&2
  exit 1
fi
printf '  %sall %d rules pass%s\n' "$C_GREEN" "$RULES_RUN" "$C_RESET"
