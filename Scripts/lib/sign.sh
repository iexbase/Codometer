#!/usr/bin/env bash
# Code-signing mode resolution and signing for Codometer. Sourced by release.sh and build-app.sh.
#
# Three modes, resolved from the keychain and the environment, never guessed silently:
#   adhoc                      no signing identity at all       → `--sign -`, no timestamp, no notarization
#   developer-id               an identity and notary credentials
#   developer-id-unnotarized   an identity but no notary credentials
#
# An explicitly requested identity that is not in the keychain is an error, not a fallback to ad hoc: it
# almost always means a misconfigured machine, and silently shipping an unsigned build would be worse.

# Set by resolve_sign_mode.
SIGN_MODE=''
SIGN_IDENTITY=''
SIGN_MODE_REASON=''
SIGN_ERROR=''

# Prints every "Developer ID Application" identity in the default keychain search list, one per line.
developer_id_identities() {
  security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p'
}

identity_exists() {
  security find-identity -v -p codesigning 2>/dev/null | stream_has "$1"
}

# resolve_sign_mode <have-notary-credentials: 0|1>
resolve_sign_mode() {
  local have_notary="${1:-0}"
  local requested="${CODOMETER_SIGN_IDENTITY:-}"
  SIGN_ERROR=''

  if [[ -n "$requested" ]]; then
    if ! identity_exists "$requested"; then
      SIGN_ERROR="CODOMETER_SIGN_IDENTITY=\"$requested\" is not in the keychain. Refusing to fall back to an ad-hoc signature, because an explicit identity means someone intended a signed build."
      return 1
    fi
    SIGN_IDENTITY="$requested"
    SIGN_MODE_REASON="CODOMETER_SIGN_IDENTITY"
  else
    local found count
    found="$(developer_id_identities)"
    count="$(printf '%s' "$found" | grep -c . || true)"
    if [[ "$count" == "1" ]]; then
      SIGN_IDENTITY="$(printf '%s' "$found" | sed -n '1p')"
      SIGN_MODE_REASON="the single Developer ID Application identity in the keychain"
    elif [[ "${count:-0}" -gt 1 ]]; then
      SIGN_ERROR="$count Developer ID Application identities are in the keychain; set CODOMETER_SIGN_IDENTITY to pick one"
      return 1
    else
      SIGN_MODE='adhoc'
      SIGN_IDENTITY='-'
      SIGN_MODE_REASON="no Developer ID Application identity in the keychain"
      return 0
    fi
  fi

  if [[ "$have_notary" == "1" ]]; then
    SIGN_MODE='developer-id'
  else
    SIGN_MODE='developer-id-unnotarized'
  fi
}

# sign_bundle <path> [entitlements]
#
# Inside out, never `--deep`: `--deep` re-signs nested code with the outer bundle's options and silently
# drops the extension's entitlements. `--deep` is fine for verification only.
sign_bundle() {
  local target="$1" entitlements="${2:-}"
  local args
  args=(--force --sign "$SIGN_IDENTITY" --options runtime)
  if [[ "$SIGN_MODE" == "adhoc" ]]; then
    args+=(--timestamp=none)
  else
    args+=(--timestamp)
  fi
  if [[ -n "$entitlements" ]]; then
    args+=(--entitlements "$entitlements")
  fi
  codesign "${args[@]}" "$target"
}

# sign_app <app> <entitlements-for-the-appex>
sign_app() {
  local app="$1" widget_entitlements="$2" appex
  # Strip extended attributes and resource forks the staging copy may have picked up; codesign refuses
  # to seal them and Finder adds them behind your back.
  xattr -cr "$app"
  for appex in "$app"/Contents/PlugIns/*.appex; do
    [[ -d "$appex" ]] || continue
    sign_bundle "$appex" "$widget_entitlements"
  done
  sign_bundle "$app"
  codesign --verify --strict --deep --verbose=2 "$app" 2>&1 | sed 's/^/    /'
}

# sign_file <path> — a flat file such as the DMG (no entitlements, no hardened runtime flag needed).
sign_file() {
  local target="$1"
  if [[ "$SIGN_MODE" == "adhoc" ]]; then
    codesign --force --sign - --timestamp=none "$target"
  else
    codesign --force --sign "$SIGN_IDENTITY" --timestamp "$target"
  fi
}
