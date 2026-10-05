#!/bin/bash
# The value drift guard: Flea's fallback computes what Omarchy's own Commons and Ui compute, for an
# empty theme, a stock one (nord, rendered template shell.toml), a hostile one, and the stock one under
# a ~/.config/omarchy/shell.toml override. One probe config root runs twice, Commons and Ui linked to
# Omarchy's and then to ui/compat; the line sets must match.
#   tests/generic/compat-parity.sh
# Omarchy is FORK_OMARCHY_REF (a shell/ checkout) or /usr/share/omarchy/shell; with neither this
# prints SKIP, and a FORK_OMARCHY_REF that names nothing usable is a failure, never a skip.
set -u
cd "$(dirname "$0")/../.." || exit 1
. "$PWD/tools/flea-sandbox-guard"

if [ -n "${FORK_OMARCHY_REF:-}" ]; then
    ref=$FORK_OMARCHY_REF
    [ -f "$ref/Commons/qmldir" ] && [ -f "$ref/Ui/qmldir" ] \
        || { echo "FAIL FORK_OMARCHY_REF=$ref has no Commons/qmldir and Ui/qmldir"; exit 1; }
elif [ -f /usr/share/omarchy/shell/Commons/qmldir ] && [ -f /usr/share/omarchy/shell/Ui/qmldir ]; then
    ref=/usr/share/omarchy/shell
else
    echo "compat-parity: SKIP no Omarchy reference (set FORK_OMARCHY_REF to a basecamp/omarchy shell/ checkout)"
    exit 0
fi
qs_bin=$(command -v qs) || { echo "compat-parity: qs is not installed, cannot run the probe"; exit 1; }

test_root="$FIXTURE_ROOT/flea-generic-parity-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/fixtures" "$test_root/home/.config/omarchy" "$test_root/state" "$test_root/config" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
cp -r tests/generic/parity/stock tests/generic/parity/hostile "$test_root/fixtures/" || exit 1
cp tests/generic/parity/user/shell.toml "$test_root/home/.config/omarchy/shell.toml" || exit 1

# Sample output line: "parity hostile Style.spacing.rowGap=5". PATH holds nothing, so neither side
# reaches hyprctl or fc-match, and HYPRLAND_INSTANCE_SIGNATURE is unset for the same reason.
probe() {
    local name=$1 modules=$2 dir="$test_root/$1"
    mkdir -p "$dir" || return 1
    cp tests/generic/compat-parity.qml "$dir/shell.qml" || return 1
    ln -s "$modules/Commons" "$dir/Commons" && ln -s "$modules/Ui" "$dir/Ui" && ln -s ../fixtures "$dir/fixtures" || return 1
    timeout 30 env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE PATH=/nonexistent-fork-parity \
        HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CONFIG_HOME="$test_root/config" \
        XDG_RUNTIME_DIR="$test_root/runtime" QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
        "$qs_bin" -p "$dir" > "$test_root/$name.log" 2>&1
}
probe omarchy "$(realpath "$ref")" &
probe compat "$PWD/ui/compat" &
wait

fail=0
for side in omarchy compat; do
    if ! grep -aq 'parity done' "$test_root/$side.log"; then
        echo "FAIL the $side probe never finished; the end of its log:"
        tail -n 12 "$test_root/$side.log" | sed 's/^/     /'
        fail=1
    fi
    grep -ao 'parity [a-z]* .*' "$test_root/$side.log" | sort > "$test_root/$side.lines"
done
[ "$fail" -eq 0 ] || exit 1

lines=$(grep -c . "$test_root/compat.lines")
if [ "$lines" -lt 150 ]; then
    echo "FAIL only $lines parity line(s), so the probe lost its keys"
    exit 1
fi
# Equal sets would also come from two sides that both ignore the override, so it must have landed.
for want in 'parity user Style.font.baseSize=15' 'parity stock Style.font.baseSize=12'; do
    grep -qxF "$want" "$test_root/compat.lines" || { echo "FAIL the user override did not layer: no '$want'"; exit 1; }
done
if diff -u "$test_root/omarchy.lines" "$test_root/compat.lines" > "$test_root/diff"; then
    echo "ok   ui/compat matches Omarchy at $ref on all $lines value(s) across 5 fixtures (startup values first)"
    exit 0
fi
echo "FAIL ui/compat differs from Omarchy at $ref (- Omarchy, + compat):"
grep -E '^[-+]parity' "$test_root/diff" | head -40 | sed 's/^/     /'
exit 1
