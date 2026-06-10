#!/usr/bin/env bash
# Run BudgetTrackerTests on the iOS Simulator (Codemagic / Mac pre-ship gate).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SCHEME="${XCODE_SCHEME:-BudgetTracker}"
PROJECT="${XCODE_PROJECT:-BudgetTracker.xcodeproj}"
if [[ -z "${CM_TEST_DESTINATION:-}" ]]; then
  CM_TEST_DESTINATION=$(
    set +o pipefail
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showdestinations 2>/dev/null \
      | grep "platform:iOS Simulator" \
      | grep -v "placeholder" \
      | head -1 \
      | sed -n 's/.*id:\([^,}]*\).*/\1/p' \
      | tr -d ' '
  )
fi

if [[ -n "${CM_TEST_DESTINATION:-}" ]]; then
  if [[ "$CM_TEST_DESTINATION" == platform=* ]]; then
    DESTINATION="$CM_TEST_DESTINATION"
  else
    DESTINATION="platform=iOS Simulator,id=$CM_TEST_DESTINATION"
  fi
else
  DESTINATION="platform=iOS Simulator,name=iPhone 17"
fi

echo "Running unit tests: scheme=$SCHEME destination=$DESTINATION"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -only-testing:BudgetTrackerTests \
  -resultBundlePath /tmp/BudgetTrackerTestResults.xcresult \
  test \
  CODE_SIGNING_ALLOWED=NO

echo "Unit tests passed."
