#!/bin/bash
# Loads the real shell from ui/boot-compat, the root a launch without Omarchy takes, the way
# tests/shellload.sh loads ui/boot. When an Omarchy reference exists the same tree is also loaded
# from boot-ref (entries linked to boot/, Commons and Ui linked to Omarchy's), and any warning the
# compat load prints that the reference load does not is a failure: a member the fallback declares
# but gets wrong shows up there (Unable to assign [undefined], TypeError, ReferenceError).
#   tests/generic/shellload-compat.sh [UI_DIR]      UI_DIR defaults to ./ui; CI also passes /usr/share/flea/ui
# The backend is FLEA_BIN, else target/debug/flea, else flea on PATH.
set -u
cd "$(dirname "$0")/../.." || exit 1
. "$PWD/tools/flea-sandbox-guard"

ui_src=$(realpath -e "${1:-ui}") || { echo "shellload-compat: no UI directory at ${1:-ui}"; exit 1; }
[ -e "$ui_src/boot-compat/shell.qml" ] || { echo "FAIL $ui_src has no boot-compat/shell.qml"; exit 1; }
command -v qs >/dev/null || { echo "shellload-compat: qs is not installed, cannot load the shell"; exit 1; }
bin=${FLEA_BIN:-}
[ -n "$bin" ] || { [ -x target/debug/flea ] && bin=$PWD/target/debug/flea; }
[ -n "$bin" ] || bin=$(command -v flea) || { echo "shellload-compat: no flea binary; build target/debug/flea or set FLEA_BIN"; exit 1; }

if [ -n "${FORK_OMARCHY_REF:-}" ]; then
    ref=$FORK_OMARCHY_REF
    [ -f "$ref/Commons/qmldir" ] || { echo "FAIL FORK_OMARCHY_REF=$ref has no Commons/qmldir"; exit 1; }
elif [ -f /usr/share/omarchy/shell/Commons/qmldir ]; then
    ref=/usr/share/omarchy/shell
else
    ref=""
fi

pass=0
fail=0
ok()  { printf 'ok   %s\n' "$*"; pass=$((pass + 1)); }
bad() { printf 'FAIL %s\n' "$*"; fail=$((fail + 1)); }

test_root="$FIXTURE_ROOT/flea-generic-shellload-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

# A copy, so Quickshell's config watcher sees no edit from another lane and boot-ref can be added to
# an installed tree; cp -a keeps boot-compat's relative links pointing inside the copy.
cp -a "$ui_src" "$test_root/ui" || exit 1
roots="boot-compat"
if [ -n "$ref" ]; then
    mkdir -p "$test_root/ui/boot-ref" || exit 1
    ln -s ../boot/shell.qml "$test_root/ui/boot-ref/shell.qml" && ln -s ../boot/picker.qml "$test_root/ui/boot-ref/picker.qml" \
        && ln -s "$(realpath "$ref")/Commons" "$test_root/ui/boot-ref/Commons" && ln -s "$(realpath "$ref")/Ui" "$test_root/ui/boot-ref/Ui" || exit 1
    roots="$roots boot-ref"
fi

# Offscreen with no compositor; a shell never exits on its own, so the timeout (124) is the success path.
load() {
    # One letter, so the IPC socket under runtime/quickshell/by-id/ stays inside sun_path's 108 bytes.
    local root=$1 w="$test_root/${1:5:1}"
    mkdir -p "$w"/{home,config,state,data,cache,runtime,tmp,fixture} && chmod 700 "$w/runtime" || return 1
    env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u FLEA_SELECT -u FLEA_COMMONS \
        HOME="$w/home" XDG_CONFIG_HOME="$w/config" XDG_STATE_HOME="$w/state" XDG_DATA_HOME="$w/data" \
        XDG_CACHE_HOME="$w/cache" XDG_RUNTIME_DIR="$w/runtime" TMPDIR="$w/tmp" \
        FLEA_PATH="$w/fixture" FLEA_BIN="$bin" QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
        timeout 25 qs -p "$test_root/ui/$root/shell.qml" > "$test_root/$root.log" 2>&1
    echo $? > "$test_root/$root.status"
}
for root in $roots; do load "$root" & done
wait

log="$test_root/boot-compat.log"
status=$(cat "$test_root/boot-compat.status")
if [ "$status" -eq 124 ]; then
    ok "the compat shell stayed alive until the timeout"
else
    bad "qs exited before the load window completed (exit $status)"
fi
if grep -aq 'Configuration Loaded' "$log"; then
    ok "the compat shell loads: qs reported Configuration Loaded"
else
    bad "qs never reported Configuration Loaded from boot-compat"
fi
# Sample input, upstream main without Omarchy: 'caused by @WindowBody.qml[3:1]: module "qs.Commons" is not installed'.
hard='Failed to load configuration|Cannot assign to non-existent|is not installed|is not a type'
if ! grep -aqE "$hard" "$log"; then
    ok "no load failure, missing module, missing type or assignment to a missing property"
else
    bad "the compat load logged:"
    grep -aE "$hard" "$log" | head -5 | sed 's/^/     /'
fi

# Sample input: '  WARN: @file:///…/ui/boot-compat/../Header.qml[12:5]: TypeError: …'. Colour codes,
# timestamps and the root's own name are normalised away, so only the message is compared. The
# compat Commons and Ui are rewrites, so a position inside them never matches Omarchy's own file.
normalise() {
    sed -E 's/\x1b\[[0-9;]*m//g' "$1" | grep -aE 'WARN|ERROR' \
        | sed -E -e 's#boot-(compat|ref)#ROOT#g' -e 's/^[^A-Z]*(WARN|ERROR)/\1/' -e 's/0x[0-9a-f]+/0xX/g' \
              -e 's#/by-id/[^/]+/#/by-id/ID/#g' -e 's#(@(Commons|Ui)/[A-Za-z0-9_/]+\.qml)\[-?[0-9]+:-?[0-9]+\]#\1[L:C]#g' | sort -u
}
if [ -n "$ref" ]; then
    if grep -aq 'Configuration Loaded' "$test_root/boot-ref.log"; then
        extra=$(comm -23 <(normalise "$log") <(normalise "$test_root/boot-ref.log"))
        if [ -z "$extra" ]; then
            ok "no warning the Omarchy reference load ($ref) does not also print"
        else
            bad "warnings only the compat load prints (reference $ref):"
            printf '%s\n' "$extra" | head -10 | sed 's/^/     /'
        fi
    else
        bad "the Omarchy reference load ($ref) did not load, so nothing could be compared"
    fi
else
    echo "skip no Omarchy reference, so the differential check did not run (set FORK_OMARCHY_REF)"
fi

printf 'shellload-compat: %s check(s), %s failed\n' "$((pass + fail))" "$fail"
[ "$fail" -eq 0 ]
