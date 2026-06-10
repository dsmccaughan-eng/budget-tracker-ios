#!/bin/sh
# Hard wall-clock limit for Codemagic steps (saves macOS minutes when a step hangs).
# Usage: ci-step-timeout.sh <seconds> <step-name> <command> [args...]
set -e

LIMIT="${1:?usage: ci-step-timeout.sh <seconds> <step-name> <cmd> [args...]}"
STEP="${2:?}"
shift 2

echo "=== ${STEP} (max ${LIMIT}s) ==="

if command -v timeout >/dev/null 2>&1; then
  timeout -k 5 "$LIMIT" "$@"
  exit $?
fi

"$@" &
child=$!
(
  sleep "$LIMIT"
  if kill -0 "$child" 2>/dev/null; then
    echo "ERROR: Step '${STEP}' exceeded ${LIMIT}s — failing build"
    kill -9 "$child" 2>/dev/null
  fi
) &
watcher=$!
wait "$child"
status=$?
kill "$watcher" 2>/dev/null || true
wait "$watcher" 2>/dev/null || true

case "$status" in
  124|137|143)
    echo "ERROR: Step '${STEP}' timed out after ${LIMIT}s"
    exit 124
    ;;
esac
exit "$status"
