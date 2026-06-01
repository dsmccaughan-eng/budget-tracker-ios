#!/bin/sh
# Decode a base64 provisioning profile and install it using its UUID filename.
set -e

if [ -z "${1:-}" ]; then
  echo "Usage: install-mobileprovision.sh <base64-profile>" >&2
  exit 1
fi

PROFILE_DIR="${HOME}/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$PROFILE_DIR"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

printf '%s' "$1" | base64 --decode > "$TMP"
UUID="$(security cms -D -i "$TMP" 2>/dev/null | plutil -extract UUID raw -)"

if [ -z "$UUID" ]; then
  echo "Could not read provisioning profile UUID" >&2
  exit 1
fi

cp "$TMP" "$PROFILE_DIR/$UUID.mobileprovision"
echo "Installed provisioning profile $UUID"
