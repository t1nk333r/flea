#!/bin/bash
# Runs the fork's pure JavaScript suites (tests/generic/js) under qml6, with no Quickshell and no window.
#   tests/generic/js.sh
set -u
cd "$(dirname "$0")/../.." || exit 1

if ! command -v qml6 >/dev/null; then
    echo "generic js.sh: qml6 is not installed, cannot run the pure JavaScript suites"
    exit 1
fi

out=$(QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 timeout 60 qml6 tests/generic/js/harness.qml 2>&1)
code=$?
echo "$out"
if [ "$code" = 124 ]; then
    echo "generic js.sh: the harness did not finish inside 60s, which a load error does"
    exit 1
fi
# qml6 exits 0 on a ReferenceError inside an imported library, so the tally proves execution.
printf '%s' "$out" | grep -qE "checks, 0 failed" || exit 1
[ "$code" = 0 ] || exit "$code"
