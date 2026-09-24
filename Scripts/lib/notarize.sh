#!/usr/bin/env bash
# Notarization helpers. Sourced by release.sh.
#
# Credentials are read from the environment in a fixed order and are never printed, logged or written to a
# stage log: NOTARY_ARGS holds them in memory only, and every command that receives it runs with `set +x`.

# Set by resolve_notary_credentials.
NOTARY_ARGS=()
NOTARY_SOURCE=''
NOTARY_KEY_TEMP=''

# 0 when usable credentials exist, 1 otherwise. Never fails the script by itself: the caller decides
# whether a missing credential is a skip or, with --require-notarization, a failure.
resolve_notary_credentials() {
  set +x
  NOTARY_ARGS=()
  NOTARY_SOURCE=''

  if [[ -n "${CODOMETER_NOTARY_PROFILE:-}" ]]; then
    NOTARY_ARGS=(--keychain-profile "$CODOMETER_NOTARY_PROFILE")
    NOTARY_SOURCE="keychain profile"
    return 0
  fi

  local key_path="${CODOMETER_NOTARY_KEY_PATH:-}"
  if [[ -z "$key_path" && -n "${CODOMETER_NOTARY_KEY_P8_BASE64:-}" ]]; then
    # CI hands the key over base64-encoded. Write it with a private umask and remove it on exit.
    local previous_umask
    previous_umask="$(umask)"
    umask 077
    key_path="$(mktemp "${TMPDIR:-/tmp}/codometer-notary-XXXXXX.p8")"
    printf '%s' "$CODOMETER_NOTARY_KEY_P8_BASE64" | base64 --decode > "$key_path"
    umask "$previous_umask"
    NOTARY_KEY_TEMP="$key_path"
  fi

  if [[ -n "$key_path" && -n "${CODOMETER_NOTARY_KEY_ID:-}" && -n "${CODOMETER_NOTARY_ISSUER_ID:-}" ]]; then
    NOTARY_ARGS=(--key "$key_path" --key-id "$CODOMETER_NOTARY_KEY_ID" --issuer "$CODOMETER_NOTARY_ISSUER_ID")
    NOTARY_SOURCE="App Store Connect API key"
    return 0
  fi

  if [[ -n "${CODOMETER_NOTARY_APPLE_ID:-}" && -n "${CODOMETER_NOTARY_APP_PASSWORD:-}" && -n "${CODOMETER_NOTARY_TEAM_ID:-}" ]]; then
    NOTARY_ARGS=(--apple-id "$CODOMETER_NOTARY_APPLE_ID" --password "$CODOMETER_NOTARY_APP_PASSWORD" --team-id "$CODOMETER_NOTARY_TEAM_ID")
    NOTARY_SOURCE="Apple ID and app-specific password"
    return 0
  fi

  return 1
}

cleanup_notary_credentials() {
  if [[ -n "$NOTARY_KEY_TEMP" && -f "$NOTARY_KEY_TEMP" ]]; then
    rm -f "$NOTARY_KEY_TEMP"
  fi
  NOTARY_KEY_TEMP=''
  NOTARY_ARGS=()
}

# notarize_artifact <path-to-zip-or-dmg> <log-dir> <name>
# Returns non-zero when the submission is not Accepted, after writing the notary log next to the result.
notarize_artifact() {
  local artifact="$1" logs="$2" name="$3"
  local result="$logs/notary-$name.json"
  set +x
  if ! xcrun notarytool submit "$artifact" "${NOTARY_ARGS[@]}" --wait --timeout 30m \
        --output-format json > "$result" 2>"$logs/notary-$name.err"; then
    return 1
  fi
  local status id
  status="$(jq -r '.status // empty' < "$result" 2>/dev/null || true)"
  if [[ -z "$status" ]]; then
    status="$(plutil -extract status raw -o - -- "$result" 2>/dev/null || true)"
  fi
  id="$(jq -r '.id // empty' < "$result" 2>/dev/null || true)"
  if [[ "$status" != "Accepted" ]]; then
    if [[ -n "$id" ]]; then
      xcrun notarytool log "$id" "${NOTARY_ARGS[@]}" "$logs/notary-$name-log.json" >/dev/null 2>&1 || true
    fi
    return 1
  fi
  return 0
}

# staple_and_validate <path>
staple_and_validate() {
  xcrun stapler staple "$1" && xcrun stapler validate "$1"
}
