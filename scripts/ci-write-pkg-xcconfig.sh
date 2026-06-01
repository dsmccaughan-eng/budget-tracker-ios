#!/bin/sh
# Writes repo-root pkg.xcconfig (SPM signing override + release API keys from env).
set -e

OUT="${1:-pkg.xcconfig}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

KEY_LINES="$(node --input-type=module -e "
import fs from 'fs';
const c = JSON.parse(fs.readFileSync('ios-app.config.json', 'utf8'));
for (const key of c.pkgXcconfigKeys || []) {
  const env = process.env[key] || '';
  console.log(key + ' = ' + env);
}
")"

cat > "$OUT" <<EOF
CODE_SIGNING_ALLOWED = NO
CODE_SIGNING_REQUIRED = NO
CODE_SIGN_IDENTITY =
PROVISIONING_PROFILE_SPECIFIER =
$KEY_LINES
EOF

echo "Wrote $OUT ($(wc -c < "$OUT" | tr -d ' ') bytes)"
