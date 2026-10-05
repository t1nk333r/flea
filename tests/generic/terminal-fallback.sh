#!/bin/bash
# The end-to-end proof of `flea --terminal` where xdg-terminal-exec is not installed: a terminal named
# by $TERMINAL, else the first known emulator on PATH, opens in the canonical directory, detached the
# way src/terminal.rs detaches every child (no inherited pipe, its own process group). This is what
# goes red when a rebase resolution drops the one-line hook in src/terminal.rs.
#   tests/generic/terminal-fallback.sh [FLEA_BIN]      FLEA_BIN defaults to target/debug/flea
set -u
cd "$(dirname "$0")/../.." || exit 1
. "$PWD/tools/flea-sandbox-guard"

bin=$(realpath -e "${1:-target/debug/flea}") || { echo "terminal-fallback: build the candidate first: ${1:-target/debug/flea}"; exit 1; }
sh_bin=$(command -v sh) && readlink_bin=$(command -v readlink) || { echo "terminal-fallback: no sh or readlink"; exit 1; }

pass=0
fail=0
check() {
    if [ "$2" = "$3" ]; then printf 'ok   %s\n' "$1"; pass=$((pass + 1))
    else printf 'FAIL %s\n     got:  %s\n     want: %s\n' "$1" "$2" "$3"; fail=$((fail + 1)); fi
}

test_root="$FIXTURE_ROOT/flea-generic-terminal-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT
dir="$test_root/a dir"
mkdir -p "$test_root/bin" "$test_root/rec" "$dir" && ln -s "$dir" "$test_root/link" || exit 1

# Sample record: "foot args=[] cwd=/…/a dir in=/dev/null out=/dev/null leader=yes". The stub is the
# process flea spawned, so a pgid equal to its own pid means it leads its own group.
stub() {
    cat > "$test_root/bin/$1" <<STUB
#!$sh_bin
read -r _ _ _ _ pgid _ < /proc/\$\$/stat
[ "\$pgid" = "\$\$" ] && leader=yes || leader=no
printf '%s args=[%s] cwd=%s in=%s out=%s leader=%s\n' "$1" "\$*" "\$(pwd -P)" "\$($readlink_bin /proc/\$\$/fd/0)" "\$($readlink_bin /proc/\$\$/fd/1)" "\$leader" >> "$test_root/rec/log"
STUB
    chmod +x "$test_root/bin/$1"
}

# Only bin/ is on PATH, so xdg-terminal-exec and every real emulator are absent. Quickshell hands
# flea --terminal a pipe and closes it, so the run does the same; the record is read once it lands.
terminal() {
    rm -f "$test_root/rec/log"
    env -i HOME="$test_root" PATH="$test_root/bin" "$@" "$bin" --terminal "$test_root/link" 2>&1 </dev/null | cat > /dev/null
    rc=${PIPESTATUS[0]}
    for _ in $(seq 1 40); do [ -s "$test_root/rec/log" ] && break; sleep 0.05; done
    printf 'rc=%s %s' "$rc" "$(cat "$test_root/rec/log" 2>/dev/null)"
}

stub foot
check "no xdg-terminal-exec: a known emulator opens in the directory, detached" \
    "$(terminal)" "rc=0 foot args=[] cwd=$dir in=/dev/null out=/dev/null leader=yes"
stub wezterm
check "\$TERMINAL names the emulator that opens" "$(terminal TERMINAL=wezterm)" \
    "rc=0 wezterm args=[] cwd=$dir in=/dev/null out=/dev/null leader=yes"
check "an empty \$TERMINAL is unset" "$(terminal TERMINAL=)" \
    "rc=0 foot args=[] cwd=$dir in=/dev/null out=/dev/null leader=yes"
check "a \$TERMINAL that is not installed still opens a known emulator" "$(terminal TERMINAL=no-such-terminal)" \
    "rc=0 foot args=[] cwd=$dir in=/dev/null out=/dev/null leader=yes"
rm -f "$test_root/bin/foot" "$test_root/bin/wezterm"
stub xterm
check "the walk reaches the last known emulator" "$(terminal)" \
    "rc=0 xterm args=[] cwd=$dir in=/dev/null out=/dev/null leader=yes"
rm -f "$test_root/bin/xterm"
check "nothing installed: the status Opener reads as a failure" "$(terminal)" "rc=2 "

printf 'terminal-fallback: %s check(s), %s failed\n' "$((pass + fail))" "$fail"
[ "$fail" -eq 0 ]
