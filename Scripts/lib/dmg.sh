#!/usr/bin/env bash
# Disk-image creation and verification. Sourced by release.sh.
#
# The image holds the app and a symlink to /Applications, nothing else: no background art, no volume icon,
# no Finder window scripting (all of it is flaky on a headless runner and buys the user nothing).
# The `Applications` symlink is part of the package, not of the data the app reads, so the "never follow a
# symlink" rule does not apply to it.

# make_dmg <app> <work-dir> <out-dmg> <volume-name>
make_dmg() {
  local app="$1" work="$2" out="$3" volume="$4"
  local root="$work/dmg"
  rm -rf "$root"
  mkdir -p "$root"
  # --norsrc --noextattr: the same copy mode the bundle was staged with, so nothing unsealed appears.
  ditto --norsrc --noextattr "$app" "$root/$(basename "$app")"
  ln -s /Applications "$root/Applications"
  rm -f "$out"
  # APFS + ULFO (LZFSE): smallest of the formats that macOS 26 mounts read-only without a helper.
  hdiutil create -volname "$volume" -srcfolder "$root" -fs APFS -format ULFO -ov "$out" >/dev/null
  rm -rf "$root"
}

# mount_dmg <dmg> <work-dir> — prints the mount point on stdout.
#
# The attach plist is walked with plutil alone, entity by entity: an APFS image has several system entities
# and only one of them carries a mount point. Reading it without jq keeps the one step that leaves a disk
# image attached on the machine free of a dependency that may be missing, and lets the failure path detach
# the image it just attached instead of leaving it mounted for the rest of the session.
mount_dmg() {
  local dmg="$1" work="$2" plist point device index
  plist="$work/attach.plist"
  # -mountrandom keeps the mount out of /Volumes/<name>, so a second copy of the app never shadows the
  # installed one in LaunchServices; -nobrowse -noautoopen keep Finder out of it entirely.
  hdiutil attach "$dmg" -readonly -nobrowse -noautoopen -mountrandom "$work" -plist > "$plist"
  index=0
  while plutil -extract "system-entities.$index.dev-entry" raw -o - "$plist" >/dev/null 2>&1; do
    point="$(plutil -extract "system-entities.$index.mount-point" raw -o - "$plist" 2>/dev/null || true)"
    if [[ -n "$point" ]]; then
      printf '%s\n' "$point"
      return 0
    fi
    index=$((index + 1))
  done
  device="$(plutil -extract 'system-entities.0.dev-entry' raw -o - "$plist" 2>/dev/null || true)"
  if [[ -n "$device" ]]; then
    hdiutil detach "$device" -force -quiet 2>/dev/null || true
  fi
  return 1
}

# detach_dmg <mount-point>
detach_dmg() {
  local point="$1" tries=0
  [[ -n "$point" && -d "$point" ]] || return 0
  while ! hdiutil detach "$point" -quiet 2>/dev/null; do
    tries=$((tries + 1))
    if ((tries >= 5)); then
      hdiutil detach "$point" -force -quiet 2>/dev/null || true
      return 0
    fi
    sleep 1
  done
  return 0
}
