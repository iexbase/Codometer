#!/usr/bin/env bash
# Assembles Codometer.app from the Swift package: the app binary, the embedded widget extension, the
# version numbers, the app icon and an ad-hoc signature.
#
# Usage:
#   Scripts/build-app.sh [debug|release] [options]     (default: release)
#
#   --output <dir>    assemble into <dir>/Codometer.app instead of build/Codometer.app.
#                     With --output nothing in build/ is touched and no process is stopped: this is the
#                     mode the release gate uses, and the mode to use from a scratch workspace.
#   --version <X.Y.Z> override Packaging/VERSION (the release gate passes the version it resolved)
#   --build <n>       override the build number
#   --no-sign         leave the bundle unsigned; the caller signs it with the mode it resolved
#   --allow-missing-icon   continue when Scripts/build-icon.sh is absent, even in release
#
# Bundle identifiers come from Packaging/identity.env. Set CODOMETER_REGISTER=1 to register the built app
# (and its widget) with LaunchServices afterwards; that also unregisters every other copy of the app, which
# would otherwise compete for the widget's bundle identifier
# from before the rename. Registration is a debug-only convenience: a release build never registers,
# never stops a process and never writes outside its output folder.
#
# Why the bundle is assembled in a staging folder, the running extension is stopped and the bundle swapped
# in with renames, and why every build gets a new CFBundleVersion: chronod (WidgetKit) launches the
# extension on its own schedule and keeps it alive between requests. A bundle that is half deleted or half
# copied, a registered copy that no longer exists, or an extension process still running from the replaced
# bundle ("Bundle version did not match") make chronod's requests fail; after a burst of failures chronod
# logs "Disallowing reloads due to extensive failures" and refuses the widget's placeholder reloads for
# 24 hours. A new build number tells chronod that the extension changed, so it drops archives rendered by
# an older build.
set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck source=lib/common.sh
source Scripts/lib/common.sh
resolve_developer_dir

configuration="release"
output_dir=""
version_override=""
build_override=""
do_sign=1
allow_missing_icon=0

if (($# > 0)); then
  case "$1" in
    debug|release) configuration="$1"; shift ;;
    -*) ;;
    *) die "usage: $0 [debug|release] [--output <dir>] [--version X.Y.Z] [--build <n>] [--no-sign]" 64 ;;
  esac
fi

while (($# > 0)); do
  case "$1" in
    --output) output_dir="${2:-}"; shift 2 ;;
    --version) version_override="${2:-}"; shift 2 ;;
    --build) build_override="${2:-}"; shift 2 ;;
    --no-sign) do_sign=0; shift ;;
    --allow-missing-icon) allow_missing_icon=1; shift ;;
    *) die "unknown option: $1" 64 ;;
  esac
done

# shellcheck source=../Packaging/identity.env
source Packaging/identity.env
bundle_id_pattern='^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$'
if [[ ! "${CODOMETER_BUNDLE_ID:-}" =~ $bundle_id_pattern ]]; then
  die "Packaging/identity.env: CODOMETER_BUNDLE_ID is missing or not a reverse-DNS identifier" 65
fi
if [[ ! "${CODOMETER_WIDGETS_BUNDLE_ID:-}" =~ $bundle_id_pattern || "$CODOMETER_WIDGETS_BUNDLE_ID" != "$CODOMETER_BUNDLE_ID".* ]]; then
  die "Packaging/identity.env: CODOMETER_WIDGETS_BUNDLE_ID must start with CODOMETER_BUNDLE_ID followed by a dot" 65
fi
version="${version_override:-$(read_version "$(pwd)")}"
is_semver "$version" || die "--version: \"$version\" is not X.Y.Z"
build_number="${build_override:-$(resolve_build_number "$(pwd)")}"
[[ "$build_number" =~ ^[0-9]+$ ]] || die "--build: \"$build_number\" is not a number"

swift build -c "$configuration" --product Codometer
swift build -c "$configuration" --product CodometerWidgets
bin_dir="$(swift build -c "$configuration" --show-bin-path)"

if [[ -n "$output_dir" ]]; then
  mkdir -p "$output_dir"
  staging_root="$(cd "$output_dir" && pwd)/.staging"
  app="$(cd "$output_dir" && pwd)/Codometer.app"
  in_place=0
else
  staging_root="build/.staging"
  app="build/Codometer.app"
  in_place=1
fi
stage="$staging_root/Codometer.app"

rm -rf "$staging_root"
mkdir -p "$stage/Contents/MacOS" "$stage/Contents/Resources"
# ditto --norsrc --noextattr everywhere: a resource fork or an extended attribute picked up on the way in
# becomes "unsealed contents" at signing time.
ditto --norsrc --noextattr "$bin_dir/Codometer" "$stage/Contents/MacOS/Codometer"
ditto --norsrc --noextattr Packaging/Info.plist "$stage/Contents/Info.plist"
plist_set_string "$stage/Contents/Info.plist" CFBundleIdentifier "$CODOMETER_BUNDLE_ID"
plist_set_string "$stage/Contents/Info.plist" CFBundleShortVersionString "$version"
plist_set_string "$stage/Contents/Info.plist" CFBundleVersion "$build_number"

# The repository URL is packaging knowledge, not runtime knowledge: the app reads this Info.plist key and
# never Packaging/identity.env, and shows the link only after validating it.
if [[ -n "${CODOMETER_REPOSITORY:-}" ]]; then
  if [[ ! "$CODOMETER_REPOSITORY" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
    die "Packaging/identity.env: CODOMETER_REPOSITORY must be \"<owner>/<repo>\" or empty" 65
  fi
  plist_set_string "$stage/Contents/Info.plist" CodometerRepositoryURL "https://github.com/$CODOMETER_REPOSITORY"
fi
# The licence name, when one has been chosen: the first non-empty line of LICENSE.
if [[ -f LICENSE ]]; then
  license_name="$(grep -m1 -vE '^[[:space:]]*$' LICENSE | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | cut -c1-60)"
  [[ -n "$license_name" ]] && plist_set_string "$stage/Contents/Info.plist" CodometerLicenseName "$license_name"
fi
plutil -lint "$stage/Contents/Info.plist" >/dev/null

# --- app icon -------------------------------------------------------------------------------------
#
# Scripts/build-icon.sh compiles Packaging/AppIcon.icon. The contract is: `--out <dir>` exits 0 and writes
# exactly Assets.car, AppIcon.icns and partial.plist there. There is no .iconset to fall back to, so a
# release build without an icon is a failure: the Dock, Finder, the DMG and every notification would show
# the generic placeholder.
icon_source="none"
icon_work="$staging_root/icon"
if [[ -x Scripts/build-icon.sh ]]; then
  mkdir -p "$icon_work"
  if Scripts/build-icon.sh --out "$icon_work"; then
    for required in Assets.car AppIcon.icns partial.plist; do
      [[ -f "$icon_work/$required" ]] || die "Scripts/build-icon.sh did not write $required"
    done
    ditto --norsrc --noextattr "$icon_work/Assets.car" "$stage/Contents/Resources/Assets.car"
    ditto --norsrc --noextattr "$icon_work/AppIcon.icns" "$stage/Contents/Resources/AppIcon.icns"
    for key in CFBundleIconFile CFBundleIconName; do
      value="$(plist_get "$icon_work/partial.plist" "$key" || true)"
      [[ -n "$value" ]] || die "Scripts/build-icon.sh partial.plist has no $key"
      plist_set_string "$stage/Contents/Info.plist" "$key" "$value"
    done
    icon_source="build-icon.sh"
  else
    die "Scripts/build-icon.sh failed"
  fi
elif [[ "$configuration" == "debug" || "$allow_missing_icon" == "1" ]]; then
  printf 'warning: Scripts/build-icon.sh is missing; building without an app icon\n' >&2
  icon_source="missing"
else
  die "Scripts/build-icon.sh is missing: a release build needs the app icon. Pass --allow-missing-icon to build without one." 66
fi

# --- widget extension -----------------------------------------------------------------------------
# Codometer.app/Contents/PlugIns/CodometerWidgets.appex, versioned exactly like the host app.
appex="$stage/Contents/PlugIns/CodometerWidgets.appex"
mkdir -p "$appex/Contents/MacOS"
ditto --norsrc --noextattr "$bin_dir/CodometerWidgets" "$appex/Contents/MacOS/CodometerWidgets"
ditto --norsrc --noextattr Packaging/Widgets-Info.plist "$appex/Contents/Info.plist"
plist_set_string "$appex/Contents/Info.plist" CFBundleIdentifier "$CODOMETER_WIDGETS_BUNDLE_ID"
plist_set_string "$appex/Contents/Info.plist" CFBundleShortVersionString "$version"
plist_set_string "$appex/Contents/Info.plist" CFBundleVersion "$build_number"
plutil -lint "$appex/Contents/Info.plist" Packaging/Widgets.entitlements >/dev/null

if [[ "$configuration" == "release" ]]; then
  strip -x "$stage/Contents/MacOS/Codometer" "$appex/Contents/MacOS/CodometerWidgets"
fi

xattr -cr "$stage"

if ((do_sign == 1)); then
  # Ad-hoc signatures with the hardened runtime, inside out: the sandboxed extension first, then the app.
  codesign --force --sign - --options runtime --timestamp=none --entitlements Packaging/Widgets.entitlements "$appex"
  codesign --force --sign - --options runtime --timestamp=none "$stage"
  codesign --verify --strict --deep "$stage"
fi

# --- install the bundle ---------------------------------------------------------------------------

# The extension process of this bundle, if chronod is keeping one alive. Only this path, never other copies.
stop_extension() {
  local executable="$app/Contents/PlugIns/CodometerWidgets.appex/Contents/MacOS/CodometerWidgets"
  pkill -f "^$executable" 2>/dev/null || true
}

if ((in_place == 1)) && [[ "$configuration" == "debug" ]]; then
  # Swap the finished bundle in: two renames instead of seconds of deleting, copying and signing in place.
  # The old extension is stopped first and again right after, in case chronod launched it in between.
  previous="$staging_root/Codometer.previous.app"
  stop_extension
  if [[ -e "$app" ]]; then mv "$app" "$previous"; fi
  mv "$stage" "$app"
  stop_extension
else
  # Release, or an explicit --output: replace the target without touching any running process.
  rm -rf "$app"
  mkdir -p "$(dirname "$app")"
  mv "$stage" "$app"
fi
rm -rf "$staging_root"

if [[ "${CODOMETER_REGISTER:-0}" == "1" ]]; then
  if [[ "$configuration" == "release" ]]; then
    # Registering a release build is a shipping step, never something a build does on its own.
    die "CODOMETER_REGISTER is only honoured for debug builds; register a release build deliberately with Scripts/dev-register.sh" 65
  fi
  lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
  app_path="$(cd "$(dirname "$app")" && pwd)/$(basename "$app")"
  appex_path="$app_path/Contents/PlugIns/CodometerWidgets.appex"

  # Other registered copies (moved, copied or already deleted bundles) share the bundle identifiers; copies
  # under the former name would show a second, stale widget gallery entry.
  while IFS= read -r stale; do
    [[ -z "$stale" || "$stale" == "$app_path" || "$stale" == "$appex_path" ]] && continue
    echo "Unregistering other copy: $stale"
    if [[ "$stale" == *.appex ]]; then
      pluginkit -r "$stale" 2>/dev/null || true
    fi
    "$lsregister" -u "$stale" 2>/dev/null || true
  done < <(
    {
      "$lsregister" -dump 2>/dev/null | awk \
        -v app="$CODOMETER_BUNDLE_ID" -v widgets="$CODOMETER_WIDGETS_BUNDLE_ID" \
        '
        /^path:/ { sub(/^path:[ \t]+/, ""); sub(/ \(0x[0-9a-f]+\)$/, ""); path = $0 }
        /^identifier:/ && ($2 == app || $2 == widgets) { print path }
      '
      for widgets_id in "$CODOMETER_WIDGETS_BUNDLE_ID"; do
        pluginkit -m -A -D -v -i "$widgets_id" 2>/dev/null | awk -F '\t' 'NF >= 4 { print $4 }'
      done
    } | LC_ALL=C sort -u
  )

  "$lsregister" -f -R -trusted "$app_path"
  stop_extension
  echo "Registered $app with LaunchServices (build $build_number)"
fi

echo "Built $app ($configuration, $version build $build_number, icon: $icon_source)"
