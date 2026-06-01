#!/usr/bin/env bash
# Run BudgetTrackerTests on the iOS Simulator (Codemagic / Mac pre-ship gate).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SCHEME="${XCODE_SCHEME:-BudgetTracker}"
PROJECT="${XCODE_PROJECT:-BudgetTracker.xcodeproj}"
DESTINATION="${CM_TEST_DESTINATION:-platform=iOS Simulator,name=iPhone 16,OS=latest}"

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
