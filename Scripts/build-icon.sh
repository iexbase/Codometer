#!/usr/bin/env bash
# Compiles Packaging/AppIcon.icon (an Icon Composer document) into the three files an app bundle
# needs, and optionally exports the six Liquid Glass renditions for review.
#
# Usage:
#   Scripts/build-icon.sh --out <dir>            compile into <dir> (build contract, see below)
#   Scripts/build-icon.sh --previews <dir>       also export Default/Dark/Clear*/Tinted* at 1024
#   Scripts/build-icon.sh --render [<dir>]       re-draw the layer PNGs (designer step, writes into
#                                                Packaging/AppIcon.icon/Assets by default)
#   Scripts/build-icon.sh --docs [<dir>]         write docs/images/icon-{light,dark}.png
#   Scripts/build-icon.sh --check                run the script's own checks (see CHECKS below)
#
# Build contract (Scripts/build-app.sh and Scripts/release.sh depend on it):
#   * `--out <dir>` exits 0 and writes exactly <dir>/Assets.car, <dir>/AppIcon.icns and
#     <dir>/partial.plist — the partial Info.plist carrying CFBundleIconFile and CFBundleIconName,
#     both "AppIcon". The caller merges those two keys into the bundle's Info.plist.
#   * Nothing outside <dir> is written. <dir> is created if missing; existing files at those three
#     paths are replaced. A relative <dir> is the caller's: it resolves against the directory the
#     script was run from, not against the repository root the script works in.
#   * <dir> must hold nothing but those three files, so a caller can copy it wholesale; point it at a
#     work directory of its own rather than at Contents/Resources.
#   * Exit 2 means the asset compiler (`xcrun actool`) is unavailable — the caller decides whether
#     that is a warning (debug build) or an error (release build).
#   * Exit 64 is a usage error, 65 a broken icon document, 1 any other failure.
#   * `--previews <dir>` additionally renders the six renditions with the Icon Composer command line
#     tool. It lives inside Icon Composer.app next to the developer directory and is not on CI
#     images; when it is missing the export is skipped with a note and the exit code stays 0.
#     `xcrun ictool` is a different tool and cannot export — do not substitute it.
#   * Assets.car is NOT byte reproducible: actool stamps a compile time and a fresh UUID into each
#     flattened rendition name, so two compiles of the same document differ in about 300 bytes. The
#     pixels are reproducible — AppIcon.icns and partial.plist hash the same every time. A build
#     manifest that has to match across machines should compare AppIcon.icns, not Assets.car.
#
# The layer PNGs under Packaging/AppIcon.icon/Assets are committed, so an ordinary build never
# redraws them and never needs Swift. `--render` regenerates them from Scripts/icon/RenderIconLayers.swift.
set -euo pipefail

# The directory the caller ran this from, and this script's own absolute path — both captured before
# the `cd`, because afterwards neither a relative argument nor `$0` would still resolve.
readonly invocation_directory="$PWD"
script_path="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
readonly script_path

cd "$(dirname "$script_path")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || echo /Applications/Xcode.app/Contents/Developer)}"

readonly icon_document="Packaging/AppIcon.icon"
readonly icon_name="AppIcon"
readonly assets_directory="$icon_document/Assets"
readonly renderer="Scripts/icon/RenderIconLayers.swift"
readonly deployment_target="26.0"
# Every rendition the system can show, in the order they are reviewed.
readonly renditions=(Default Dark ClearLight ClearDark TintedLight TintedDark)
# The layers icon.json composes; the check refuses any other file under Assets/.
readonly layers=(ring-track.png ring-arc.png island.png droplet.png)
# Documentation images: README shows the icon at about 190 pt, so 384 px covers Retina. ictool
# exports 16-bit Display P3, which is far over the 200 KB budget; they are re-encoded to 8-bit sRGB.
readonly docs_directory="docs/images"
readonly docs_side=384
readonly docs_budget=200000
readonly srgb_profile="/System/Library/ColorSync/Profiles/sRGB Profile.icc"

readonly exit_usage=64
readonly exit_document=65
readonly exit_no_actool=2

say() { printf '%s\n' "$*" >&2; }
die() { say "build-icon: error: $1"; exit "${2:-1}"; }

# actool hands the work to `ibtoold`, a long-lived service that does not share this script's working
# directory: a relative path reaches it as one resolved against whatever directory started the
# service. Every path given to it is made absolute first.
absolute() {
  local path="$1"
  case "$path" in
    /*) printf '%s' "$path" ;;
    *) printf '%s' "$PWD/$path" ;;
  esac
}

# A directory the caller named is the caller's, so a relative one resolves against the directory they
# ran the script from. Resolving it against the repository root instead would quietly write the icon
# into the source tree — including into build/ — while the caller found its own directory empty.
caller_path() {
  local path="$1"
  case "$path" in
    /*) printf '%s' "$path" ;;
    *) printf '%s' "$invocation_directory/$path" ;;
  esac
}

usage() {
  say "usage: Scripts/build-icon.sh [--out <dir>] [--previews <dir>] [--render [<dir>]] [--docs [<dir>]] [--check]"
  exit "$exit_usage"
}

# MARK: - The icon document

# Parses icon.json, which is JSON and therefore not something `plutil -lint` accepts; `plutil
# -convert` does read it, and rejects malformed input the same way.
lint_document() {
  [[ -d "$icon_document" ]] || die "$icon_document is missing" "$exit_document"
  [[ -f "$icon_document/icon.json" ]] || die "$icon_document/icon.json is missing" "$exit_document"
  plutil -convert xml1 -o /dev/null "$icon_document/icon.json" \
    || die "$icon_document/icon.json is not valid JSON" "$exit_document"

  local expected actual
  expected="$(printf '%s\n' "${layers[@]}" | sort)"
  actual="$(cd "$assets_directory" 2>/dev/null && ls -1 | sort || true)"
  [[ "$expected" == "$actual" ]] || die "$assets_directory must hold exactly: ${layers[*]}" "$exit_document"

  local layer
  for layer in "${layers[@]}"; do
    grep -q "\"$layer\"" "$icon_document/icon.json" \
      || die "icon.json does not reference $layer" "$exit_document"
    [[ -s "$assets_directory/$layer" ]] || die "$assets_directory/$layer is empty" "$exit_document"
  done
  say "build-icon: icon.json parses, ${#layers[@]} layers present"
}

# MARK: - Compiling

compile_icon() {
  local out="$1"
  command -v xcrun >/dev/null 2>&1 || die "xcrun not found; install the Xcode command line tools" "$exit_no_actool"
  xcrun --find actool >/dev/null 2>&1 \
    || die "actool not found in $DEVELOPER_DIR; install Xcode 26 or select it with xcode-select" "$exit_no_actool"

  mkdir -p "$out"
  rm -f "$out/Assets.car" "$out/$icon_name.icns" "$out/partial.plist"

  # actool prints its results as a plist on stdout; failures land in the log it writes to stderr.
  local log
  if ! log="$(xcrun actool "$(absolute "$icon_document")" \
      --compile "$(absolute "$out")" \
      --platform macosx \
      --minimum-deployment-target "$deployment_target" \
      --app-icon "$icon_name" \
      --output-partial-info-plist "$(absolute "$out")/partial.plist" \
      --errors --warnings \
      --output-format human-readable-text 2>&1)"; then
    say "$log"
    die "actool failed"
  fi
  if printf '%s' "$log" | grep -q ': error:'; then
    say "$log"
    die "actool reported errors"
  fi

  local file
  for file in Assets.car "$icon_name.icns" partial.plist; do
    [[ -s "$out/$file" ]] || { say "$log"; die "actool did not write $out/$file"; }
  done
  # The contract says "exactly" these three files: a caller copies the directory wholesale.
  local extra
  extra="$(cd "$out" && ls -1 | grep -vx -e 'Assets.car' -e "$icon_name.icns" -e 'partial.plist' || true)"
  [[ -z "$extra" ]] || die "$out holds unexpected files: ${extra//$'\n'/, }"

  plutil -lint "$out/partial.plist" >/dev/null || die "$out/partial.plist is not a valid plist"
  local key value
  for key in CFBundleIconFile CFBundleIconName; do
    value="$(plutil -extract "$key" raw -o - "$out/partial.plist" 2>/dev/null || true)"
    [[ "$value" == "$icon_name" ]] || die "partial.plist $key is \"$value\", expected \"$icon_name\""
  done

  say "build-icon: compiled $icon_document → $out ($(du -h "$out/Assets.car" | cut -f1) Assets.car)"
}

# MARK: - Previews

# The exporting ictool lives inside Icon Composer.app, which ships beside the developer directory.
# `xcrun ictool` resolves to a different tool that rejects --export-image.
icon_composer_tool() {
  printf '%s' "$DEVELOPER_DIR/../Applications/Icon Composer.app/Contents/Executables/ictool"
}

export_previews() {
  local out="$1" tool
  tool="$(icon_composer_tool)"
  if [[ ! -x "$tool" ]]; then
    say "build-icon: note: Icon Composer is not installed here, skipping previews"
    say "build-icon: note: looked for $tool"
    return 0
  fi
  mkdir -p "$out"
  local rendition
  for rendition in "${renditions[@]}"; do
    "$tool" "$(absolute "$icon_document")" \
      --export-image \
      --output-file "$out/$icon_name-$rendition.png" \
      --platform macOS \
      --rendition "$rendition" \
      --width 1024 --height 1024 --scale 1 >/dev/null \
      || die "ictool could not export the $rendition rendition"
    [[ -s "$out/$icon_name-$rendition.png" ]] || die "ictool wrote no $rendition image"
  done
  say "build-icon: exported ${#renditions[@]} renditions at 1024 → $out"
}

# MARK: - Documentation images

# One 1024 rendition, resampled and re-encoded to an 8-bit sRGB PNG that fits the 200 KB budget.
export_docs() {
  local out="${1:-$docs_directory}" tool
  tool="$(icon_composer_tool)"
  [[ -x "$tool" ]] || die "Icon Composer is not installed here, so the documentation images cannot be exported"
  [[ -f "$srgb_profile" ]] || die "$srgb_profile is missing"
  mkdir -p "$out"
  local pair rendition name full
  for pair in "Default:light" "Dark:dark"; do
    rendition="${pair%%:*}"
    name="${pair##*:}"
    full="$out/.icon-$name-full.png"
    "$tool" "$(absolute "$icon_document")" \
      --export-image --output-file "$full" --platform macOS --rendition "$rendition" \
      --width 1024 --height 1024 --scale 1 >/dev/null \
      || { rm -f "$full"; die "ictool could not export the $rendition rendition"; }
    sips -Z "$docs_side" --matchTo "$srgb_profile" -s format png "$full" \
      --out "$out/icon-$name.png" >/dev/null 2>&1 \
      || { rm -f "$full"; die "sips could not resample icon-$name.png"; }
    rm -f "$full"
    local size
    size="$(stat -f %z "$out/icon-$name.png")"
    (( size <= docs_budget )) || die "$out/icon-$name.png is $size B, over the 200 KB budget"
    say "build-icon: wrote $out/icon-$name.png (${docs_side}px, $size B)"
  done
}

# MARK: - Rendering the layers

render_layers() {
  local out="${1:-$assets_directory}"
  [[ -f "$renderer" ]] || die "$renderer is missing"
  command -v swift >/dev/null 2>&1 || die "swift not found; the layers can only be redrawn with a toolchain"
  mkdir -p "$out"
  swift "$renderer" "$out" || die "the layer renderer failed"
}

# MARK: - Checks
#
# CHECKS: the icon is data, so its tests are script checks rather than Swift tests.
#   1. `bash -n` on this script.
#   2. icon.json parses and references exactly the committed layers.
#   3. The renderer is deterministic: two runs into different directories are byte identical.
#   4. A scratch compile produces the three contract files, and `assetutil --info` lists the
#      AppIcon renditions for the light, dark and tinted appearances.
#   5. A relative `--out` lands in the caller's directory and writes nothing into the repository.
#   6. Exit codes: usage error 64, missing document 65, missing actool 2, and a relative invocation
#      from another directory still reports them.
#   7. The documentation images exist and stay inside their 200 KB budget.

check_failures=0

expect() {
  local label="$1" expected="$2"
  shift 2
  local status=0
  "$@" >/dev/null 2>&1 || status=$?
  if [[ "$status" == "$expected" ]]; then
    say "  ok    $label (exit $status)"
  else
    say "  FAIL  $label (exit $status, expected $expected)"
    check_failures=$((check_failures + 1))
  fi
}

report() {
  local label="$1" ok="$2"
  if [[ "$ok" == "yes" ]]; then
    say "  ok    $label"
  else
    say "  FAIL  $label"
    check_failures=$((check_failures + 1))
  fi
}

# Runs a command in another working directory, so the checks can exercise how the script behaves for a
# caller that did not start in the repository root.
run_from() {
  local directory="$1"
  shift
  ( cd "$directory" && "$@" )
}

run_checks() {
  local scratch
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/build-icon-check.XXXXXX")"
  # shellcheck disable=SC2064
  trap "rm -rf '$scratch'" EXIT

  say "build-icon: checks"

  bash -n "$script_path" && report "bash -n Scripts/build-icon.sh" yes || report "bash -n Scripts/build-icon.sh" no

  local status=0
  plutil -convert xml1 -o /dev/null "$icon_document/icon.json" || status=$?
  [[ "$status" == 0 ]] && report "icon.json parses" yes || report "icon.json parses" no
  lint_document >/dev/null 2>&1 && report "icon.json references exactly the committed layers" yes \
    || report "icon.json references exactly the committed layers" no

  render_layers "$scratch/a" >/dev/null 2>&1 || true
  render_layers "$scratch/b" >/dev/null 2>&1 || true
  local deterministic=yes layer
  for layer in "${layers[@]}"; do
    cmp -s "$scratch/a/$layer" "$scratch/b/$layer" || deterministic=no
    cmp -s "$scratch/a/$layer" "$assets_directory/$layer" || deterministic=no
  done
  report "renderer is deterministic and matches the committed layers" "$deterministic"

  if xcrun --find actool >/dev/null 2>&1; then
    compile_icon "$scratch/out" >/dev/null 2>&1 && report "compiles into the three contract files" yes \
      || report "compiles into the three contract files" no
    local info appearance
    info="$(xcrun assetutil --info "$scratch/out/Assets.car" 2>/dev/null || true)"
    printf '%s' "$info" | grep -q "\"Name\" : \"$icon_name\"" \
      && report "Assets.car lists the $icon_name icon" yes || report "Assets.car lists the $icon_name icon" no
    for appearance in NSAppearanceNameAqua NSAppearanceNameDarkAqua ISAppearanceTintable; do
      printf '%s' "$info" | grep -q "$appearance" \
        && report "Assets.car has $appearance renditions" yes \
        || report "Assets.car has $appearance renditions" no
    done

    # The build contract's "never writes outside <dir>": a relative <dir> belongs to the caller, so
    # the three files land there and nothing appears in the repository root.
    local relative_ok=yes stray="$PWD/build-icon-relative-check"
    rm -rf "$stray" "$scratch/elsewhere"
    mkdir -p "$scratch/elsewhere"
    run_from "$scratch/elsewhere" "$script_path" --out build-icon-relative-check >/dev/null 2>&1 \
      || relative_ok=no
    local file
    for file in Assets.car "$icon_name.icns" partial.plist; do
      [[ -s "$scratch/elsewhere/build-icon-relative-check/$file" ]] || relative_ok=no
    done
    [[ ! -e "$stray" ]] || relative_ok=no
    rm -rf "$stray"
    report "a relative --out lands in the caller's directory, not in the repository" "$relative_ok"
  else
    say "  skip  compile checks (actool unavailable)"
  fi

  expect "usage error" "$exit_usage" "$script_path" --nonsense
  expect "usage error without a value" "$exit_usage" "$script_path" --out
  # Invoked by a relative path from another directory, the script must still behave: it works out its
  # own location before changing into the repository root.
  expect "relative invocation from another directory" "$exit_usage" \
    run_from "$(dirname "$script_path")" ./build-icon.sh --nonsense
  (
    # A copy of the tree with the document removed must report a broken document, not a crash.
    mkdir -p "$scratch/empty/Scripts/icon" "$scratch/empty/Packaging"
    cp "$script_path" "$scratch/empty/Scripts/build-icon.sh"
    cp "$renderer" "$scratch/empty/Scripts/icon/"
    chmod +x "$scratch/empty/Scripts/build-icon.sh"
  )
  expect "missing icon document" "$exit_document" "$scratch/empty/Scripts/build-icon.sh" --out "$scratch/none"
  (
    # An empty developer directory has no actool: the contract asks for exit 2 there.
    mkdir -p "$scratch/fakexcode/usr/bin"
  )
  local saved_developer_dir="$DEVELOPER_DIR"
  export DEVELOPER_DIR="$scratch/fakexcode"
  expect "missing actool" "$exit_no_actool" "$script_path" --out "$scratch/out2"
  export DEVELOPER_DIR="$saved_developer_dir"

  local image
  for image in "$docs_directory/icon-light.png" "$docs_directory/icon-dark.png"; do
    if [[ -s "$image" ]]; then
      local size
      size="$(stat -f %z "$image")"
      if (( size <= docs_budget )); then
        report "$image is ${size} B (≤ 200 KB)" yes
      else
        report "$image is ${size} B (> 200 KB)" no
      fi
    else
      report "$image exists" no
    fi
  done

  if (( check_failures == 0 )); then
    say "build-icon: all checks passed"
  else
    die "$check_failures check(s) failed"
  fi
}

# MARK: - Arguments

out_directory=""
previews_directory=""
render_directory=""
docs_out=""
do_render=0
do_docs=0
do_check=0

while (( $# > 0 )); do
  case "$1" in
    --out)
      [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || usage
      out_directory="$(caller_path "$2")"; shift 2 ;;
    --previews)
      [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || usage
      previews_directory="$(caller_path "$2")"; shift 2 ;;
    --render)
      do_render=1
      if [[ $# -ge 2 && -n "$2" && "$2" != --* ]]; then render_directory="$(caller_path "$2")"; shift 2; else shift; fi ;;
    --docs)
      do_docs=1
      if [[ $# -ge 2 && -n "$2" && "$2" != --* ]]; then docs_out="$(caller_path "$2")"; shift 2; else shift; fi ;;
    --check)
      do_check=1; shift ;;
    -h|--help)
      usage ;;
    *)
      say "build-icon: error: unknown option $1"
      usage ;;
  esac
done

if (( do_check )); then
  [[ -z "$out_directory$previews_directory$render_directory$docs_out" && "$do_render" -eq 0 && "$do_docs" -eq 0 ]] || usage
  run_checks
  exit 0
fi

if (( do_render )); then
  render_layers "$render_directory"
fi

if (( do_render == 0 && do_docs == 0 )) && [[ -z "$out_directory" && -z "$previews_directory" ]]; then
  usage
fi

lint_document

if [[ -n "$out_directory" ]]; then
  compile_icon "$out_directory"
fi

if [[ -n "$previews_directory" ]]; then
  export_previews "$previews_directory"
fi

if (( do_docs )); then
  export_docs "$docs_out"
fi
