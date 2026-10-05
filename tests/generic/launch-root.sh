#!/bin/bash
# The end-to-end proof that the launcher hands qs the root FORK.md promises: a stub qs first on PATH
# records the -p argument of `flea --gui` and `flea --pick`. This is what goes red when a rebase
# resolution drops the one-line hook in src/gui.rs's qs_command.
#   tests/generic/launch-root.sh [FLEA_BIN] [UI_DIR]
# FLEA_BIN defaults to target/debug/flea. With UI_DIR (an installed tree, /usr/share/flea/ui in CI)
# the launch also runs without FLEA_UI and must pick that tree's root by its own modules.
set -u
cd "$(dirname "$0")/../.." || exit 1
. "$PWD/tools/flea-sandbox-guard"

bin=$(realpath -e "${1:-target/debug/flea}") || { echo "launch-root: build the candidate first: ${1:-target/debug/flea}"; exit 1; }
installed=${2:-}

pass=0
fail=0
check() {
    if [ "$2" = "$3" ]; then printf 'ok   %s\n' "$1"; pass=$((pass + 1))
    else printf 'FAIL %s\n     got:  %s\n     want: %s\n' "$1" "$2" "$3"; fail=$((fail + 1)); fi
}

test_root="$FIXTURE_ROOT/flea-generic-launch-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT
mkdir -p "$test_root"/{bin,home,config,state,data,cache,runtime} && chmod 700 "$test_root/runtime" || exit 1

# Sample output: "ARGV -p /…/ui/boot-compat/shell.qml". exec replaces the launcher, so this is the shell's argv.
cat > "$test_root/bin/qs" <<'STUB'
#!/bin/sh
printf 'ARGV %s\n' "$*"
STUB
chmod +x "$test_root/bin/qs" || exit 1

# A ui tree with both roots; modules "dangling" links Commons and Ui at a missing Omarchy, "real" gives each a qmldir.
make_ui() {
    local ui="$test_root/$1"
    mkdir -p "$ui/boot" "$ui/boot-compat" || exit 1
    : > "$ui/boot/shell.qml"; : > "$ui/boot/picker.qml"
    ln -s ../boot/shell.qml "$ui/boot-compat/shell.qml" && ln -s ../boot/picker.qml "$ui/boot-compat/picker.qml" || exit 1
    for module in Commons Ui; do
        if [ "$2" = real ]; then
            mkdir -p "$ui/boot/$module" && printf 'module qs.%s\n' "$module" > "$ui/boot/$module/qmldir" || exit 1
        else
            ln -s "$test_root/no-omarchy/shell/$module" "$ui/boot/$module" || exit 1
        fi
    done
}
make_ui ui-bare dangling
make_ui ui-omarchy real

launch() {
    env -u FLEA_COMMONS -u FLEA_UI -u DISPLAY HOME="$test_root/home" XDG_CONFIG_HOME="$test_root/config" \
        XDG_STATE_HOME="$test_root/state" XDG_DATA_HOME="$test_root/data" XDG_CACHE_HOME="$test_root/cache" \
        XDG_RUNTIME_DIR="$test_root/runtime" WAYLAND_DISPLAY=fork-launch-root PATH="$test_root/bin:/usr/bin:/bin" \
        "$@" </dev/null 2>/dev/null | grep '^ARGV '
}
gui() { launch "$@" "$bin" --gui; }
pick() { launch FLEA_PICKER='{"stub":true}' "$@" "$bin" --pick "$test_root/reply.json"; }

bare="$test_root/ui-bare"
omarchy="$test_root/ui-omarchy"
check "no Omarchy shell: the window opens from boot-compat" "$(gui FLEA_UI="$bare")" "ARGV -p $bare/boot-compat/shell.qml"
check "no Omarchy shell: the chooser opens from boot-compat" "$(pick FLEA_UI="$bare")" "ARGV -p $bare/boot-compat/picker.qml"
check "Omarchy's modules present: the window keeps boot" "$(gui FLEA_UI="$omarchy")" "ARGV -p $omarchy/boot/shell.qml"
check "Omarchy's modules present: the chooser keeps boot" "$(pick FLEA_UI="$omarchy")" "ARGV -p $omarchy/boot/picker.qml"
check "FLEA_COMMONS=omarchy keeps boot without the modules" "$(gui FLEA_UI="$bare" FLEA_COMMONS=omarchy)" "ARGV -p $bare/boot/shell.qml"
check "FLEA_COMMONS=compat takes boot-compat beside the modules" "$(gui FLEA_UI="$omarchy" FLEA_COMMONS=compat)" "ARGV -p $omarchy/boot-compat/shell.qml"
check "an empty FLEA_COMMONS is automatic" "$(gui FLEA_UI="$bare" FLEA_COMMONS=)" "ARGV -p $bare/boot-compat/shell.qml"

if [ -n "$installed" ]; then
    ui=$(realpath -e "$installed") || { echo "FAIL no UI directory at $installed"; exit 1; }
    [ -e "$ui/boot-compat/shell.qml" ] || { echo "FAIL $ui has no boot-compat/shell.qml, so it is not a fork install"; exit 1; }
    if [ -r "$ui/boot/Commons/qmldir" ] && [ -r "$ui/boot/Ui/qmldir" ]; then want="$ui/boot/shell.qml"; else want="$ui/boot-compat/shell.qml"; fi
    check "installed tree $ui: the window opens from its own root" "$(launch "$bin" --gui)" "ARGV -p $want"
    check "installed tree $ui: FLEA_COMMONS=compat takes boot-compat" \
        "$(launch FLEA_COMMONS=compat "$bin" --gui)" "ARGV -p $ui/boot-compat/shell.qml"
fi

printf 'launch-root: %s check(s), %s failed\n' "$((pass + fail))" "$fail"
[ "$fail" -eq 0 ]
