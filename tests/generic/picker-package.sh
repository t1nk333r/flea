#!/usr/bin/env bash
set -euo pipefail
repo=$(realpath "$(dirname "$0")/../..")
if [ "$#" -eq 1 ]; then
    exec python "$repo/tests/generic/picker/layout.py" "$1"
fi
source "$repo/tools/flea-sandbox-guard"
sandbox_root_ok
sb=$(mktemp -d "$SANDBOX_ROOT/picker-package-XXXXXX")
sandbox_require "$sb"
touch "$sb/$SANDBOX_MARKER"
trap 'sandbox_require "$sb"; rm -rf -- "$sb"' EXIT
binary=${FLEA_BIN:-$repo/target/debug/flea}
"$repo/packaging/flea-picker-install" "$repo" "$sb/stage" "$binary" flea-picker
python "$repo/tests/generic/picker/layout.py" "$sb/stage"
export HOME="$sb/home" XDG_CONFIG_HOME="$sb/config" XDG_STATE_HOME="$sb/state"
export XDG_CACHE_HOME="$sb/cache" XDG_DATA_HOME="$sb/data" XDG_RUNTIME_DIR="$sb/runtime"
mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
printf '{"c":"quit"}\n' | "$sb/stage/usr/bin/flea" --backend
# Refusals are picker-modes.sh's; without a session they would exit 2 with or without the guard.
printf 'picker package: PASS staged layout and backend\n'
