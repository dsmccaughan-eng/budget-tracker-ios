#!/bin/sh
# Fail fast before archive/export if CI signing inputs are wrong.
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MIN_PROFILES="$(node --input-type=module -e "
import fs from 'fs';
const c = JSON.parse(fs.readFileSync('$ROOT/ios-app.config.json', 'utf8'));
console.log(c.profiles.length);
")"
PROFILE_NAMES="$(node --input-type=module -e "
import fs from 'fs';
const c = JSON.parse(fs.readFileSync('$ROOT/ios-app.config.json', 'utf8'));
for (const p of c.profiles) console.log(p.ascName);
")"

echo "=== Code signing identities (expect Apple Distribution) ==="
IDENT_LINE="$(security find-identity -v -p codesigning | grep -i "Apple Distribution" | head -1 || true)"
if [ -z "$IDENT_LINE" ]; then
  echo "ERROR: No distribution identity in keychain."
  exit 1
fi
echo "$IDENT_LINE"

KEYCHAIN_HASH="$(echo "$IDENT_LINE" | sed -n 's/^[[:space:]]*[0-9]*[)] \([A-F0-9]*\) ".*/\1/p')"
if [ -z "$KEYCHAIN_HASH" ]; then
  echo "ERROR: Could not parse distribution identity fingerprint."
  exit 1
fi

PROFILE_DIR="${HOME}/Library/MobileDevice/Provisioning Profiles"
echo "=== Provisioning profiles in ${PROFILE_DIR} ==="
count="$(find "$PROFILE_DIR" -maxdepth 1 -name '*.mobileprovision' 2>/dev/null | wc -l | tr -d ' ')"
echo "Found ${count} profile file(s)"
if [ "$count" -lt "$MIN_PROFILES" ]; then
  echo "ERROR: Expected at least ${MIN_PROFILES} .mobileprovision files."
  exit 1
fi

find_profile_by_name() {
  name="$1"
  for f in "$PROFILE_DIR"/*.mobileprovision; do
    [ -f "$f" ] || continue
    tmp="$(mktemp)"
    if security cms -D -i "$f" -o "$tmp" 2>/dev/null; then
      actual="$(plutil -extract Name raw "$tmp" 2>/dev/null || true)"
      rm -f "$tmp"
      if [ "$actual" = "$name" ]; then
        echo "$f"
        return 0
      fi
    fi
    rm -f "$tmp"
  done
  return 1
}

verify_profile_includes_keychain_cert() {
  profile_path="$1"
  profile_name="$2"
  python3 - "$profile_path" "$profile_name" "$KEYCHAIN_HASH" <<'PY'
import plistlib, subprocess, sys, tempfile, os

profile_path, label, keychain_hash = sys.argv[1], sys.argv[2], sys.argv[3].upper()
plist_bytes = subprocess.check_output(["security", "cms", "-D", "-i", profile_path])
plist = plistlib.loads(plist_bytes)
certs = plist.get("DeveloperCertificates") or []
if not certs:
    print(f"ERROR: {label} has no embedded certificates")
    sys.exit(1)
for i, der in enumerate(certs):
    with tempfile.NamedTemporaryFile(suffix=".cer", delete=False) as tmp:
        tmp.write(der)
        path = tmp.name
    try:
        out = subprocess.check_output(
            ["openssl", "x509", "-inform", "DER", "-in", path, "-noout", "-fingerprint", "-sha1"],
            text=True,
        )
    finally:
        os.unlink(path)
    fp = out.split("=", 1)[1].strip().replace(":", "").upper()
    if fp == keychain_hash:
        print(f"OK: {label} includes distribution certificate ({fp})")
        sys.exit(0)
print(
    f"ERROR: {label} does not include the keychain distribution cert ({keychain_hash}). "
    "Regenerate profiles for this certificate or update DISTRIBUTION_P12_BASE64."
)
sys.exit(1)
PY
}

echo "$PROFILE_NAMES" | while IFS= read -r name; do
  [ -n "$name" ] || continue
  path="$(find_profile_by_name "$name")" || {
    echo "ERROR: Profile not found: $name"
    exit 1
  }
  verify_profile_includes_keychain_cert "$path" "$name"
done

echo "=== Signing check passed ==="
