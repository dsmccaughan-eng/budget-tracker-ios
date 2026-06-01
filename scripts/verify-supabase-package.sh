#!/usr/bin/env bash
# Fail CI if supabase-swift resolves below 2.44.0 (iOS 26 launch crash fix).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MIN_VERSION="2.44.0"
RESOLVED="${ROOT}/BudgetTracker.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

if [[ ! -f "$RESOLVED" ]]; then
  echo "Package.resolved missing — run: xcodebuild -resolvePackageDependencies"
  exit 1
fi

python3 - "$RESOLVED" "$MIN_VERSION" <<'PY'
import json, sys
path, minimum = sys.argv[1], sys.argv[2]

def parse(v):
    parts = []
    for p in v.split("."):
        num = ""
        for ch in p:
            if ch.isdigit():
                num += ch
            else:
                break
        parts.append(int(num or 0))
    while len(parts) < 3:
        parts.append(0)
    return tuple(parts[:3])

with open(path, encoding="utf-8") as f:
    data = json.load(f)

pins = data.get("pins", [])
found = None
for pin in pins:
    identity = pin.get("identity") or pin.get("package", "")
    if "supabase" in identity.lower():
        found = pin.get("state", {}).get("version") or pin.get("version")
        break

if not found:
    print("::error::supabase-swift pin not found in Package.resolved")
    sys.exit(1)

if parse(found) < parse(minimum):
    print(f"::error::supabase-swift {found} < required {minimum} (iOS 26 launch crash)")
    sys.exit(1)

print(f"supabase-swift {found} >= {minimum}")
PY
