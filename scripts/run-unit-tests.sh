#!/usr/bin/env bash
# Run BudgetTrackerTests on the iOS Simulator (Codemagic / Mac pre-ship gate).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SCHEME="${XCODE_SCHEME:-BudgetTracker}"
PROJECT="${XCODE_PROJECT:-BudgetTracker.xcodeproj}"
if [[ -z "${CM_TEST_DESTINATION:-}" ]]; then
  CM_TEST_DESTINATION=$(
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showdestinations 2>/dev/null \
      | grep -m1 "platform:iOS Simulator" \
      | sed -n 's/.*id:\([^,}]*\).*/\1/p' \
      | tr -d ' '
  )
fi
DESTINATION="${CM_TEST_DESTINATION:-generic/platform=iOS Simulator}"
if [[ "$DESTINATION" != generic/* ]]; then
  DESTINATION="platform=iOS Simulator,id=$DESTINATION"
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
