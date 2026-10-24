#!/usr/bin/env bash
# Build the app, then drive it like a person would and check what appears.
#
# The self-tests (`PortScope --selftest`) cover logic. This covers the parts
# they cannot see: whether the window opens, whether the menu bar panel shows
# the same rows as the window, whether "Open PortScope" actually reopens it,
# and which language a fresh install starts in.
#
# Usage:
#   scripts/validate.sh            # build, launch a scratch copy, check, quit
#   scripts/validate.sh --keep     # leave it running for a look
#   scripts/validate.sh --no-build # use the existing dist/PortScope.app
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="$ROOT/dist/PortScope.app"
OUT="$ROOT/.build/validate"
BIN="$OUT/validate"

KEEP=""
if [[ "${1:-}" != "--no-build" ]]; then
    echo "==> Building"
    "$ROOT/scripts/build.sh" >/dev/null
fi

echo "==> Compiling the UI harness"
mkdir -p "$OUT"
swiftc -O -parse-as-library "$ROOT/Support/Validation/Validation.swift" -o "$BIN"

echo "==> Driving the app"
# A harness crash must still report, not hang: the app it launched is a child of
# this shell only by convention, so it is killed explicitly on the way out.
trap 'pkill -f "portscope-validation-$$" 2>/dev/null || true' EXIT

set +e
"$BIN" "$BUNDLE" "$@"
STATUS=$?
set -e

if [[ $STATUS -eq 0 ]]; then
    echo "==> UI validation passed"
else
    echo "==> UI validation failed (exit $STATUS)" >&2
fi
exit $STATUS
