#!/bin/bash
# Runs the argv ui/js/X11Copy.js hands Quickshell's Process on X11 (Copy Path and the Dropbox share
# link) against stub xclip and xsel, and checks what a paste would get: the exact bytes, on the
# CLIPBOARD selection, through xsel when xclip is absent or fails, a failure status when neither can
# copy (ui/ShareLink.qml turns it into its error line), and an exit while the tool's selection owner
# lingers, since a Process held open by that owner never runs a second copy.
#   tests/generic/clipboard-x11.sh
set -u
cd "$(dirname "$0")/../.." || exit 1
. "$PWD/tools/flea-sandbox-guard"
command -v qml6 >/dev/null || { echo "clipboard-x11: qml6 is not installed, cannot build the argv"; exit 1; }
sh_bin=$(command -v sh) || { echo "clipboard-x11: no sh"; exit 1; }
timeout_bin=$(command -v timeout) || { echo "clipboard-x11: no timeout"; exit 1; }

pass=0
fail=0
check() {
    if [ "$2" = "$3" ]; then printf 'ok   %s\n' "$1"; pass=$((pass + 1))
    else printf 'FAIL %s\n     got:  %s\n     want: %s\n' "$1" "$2" "$3"; fail=$((fail + 1)); fi
}

test_root="$FIXTURE_ROOT/flea-generic-clipboard-$$"
sandbox_make "$test_root"
cleanup() {
    # A stub's lingering owner is a sleep in its own process group; nothing else is ever killed.
    [ -f "$test_root/owner.pid" ] && kill "$(cat "$test_root/owner.pid")" 2>/dev/null
    sandbox_remove "$test_root"
}
trap cleanup EXIT
mkdir -p "$test_root/bin" "$test_root/rec" "$test_root/cwd" || exit 1

# Every text the copy must carry byte for byte: printf's own flags and conversions, shell syntax a
# spliced script would run, a line break, a trailing newline and a backslash escape.
texts=("-n" "-e x\\ty" "--" "a'b\"c \$(touch PWNED) \`touch PWNED2\` ;|&<>" $'one\ntwo\n' "%s %d %% \\n \\\\" "/home/u/dir with space")

# qml6 builds each argv from the real library and prints it URI-encoded, one element per field.
cat > "$test_root/argv.qml" <<'QML'
import QtQuick
import "CLIPBOARD_JS" as X11Copy
Item {
    Component.onCompleted: {
        var args = Qt.application.arguments;
        var texts = args.slice(args.indexOf("--") + 1);
        for (var i = 0; i < texts.length; i++)
            console.log("ARGV " + X11Copy.x11Argv(texts[i]).map(encodeURIComponent).join(" "));
        Qt.exit(0);
    }
}
QML
sed -i "s#CLIPBOARD_JS#$PWD/ui/js/X11Copy.js#" "$test_root/argv.qml" || exit 1
mapfile -t lines < <(QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 timeout 30 qml6 "$test_root/argv.qml" -- "${texts[@]}" 2>&1 | sed -n 's/^qml: ARGV //p')
if [ "${#lines[@]}" -ne "${#texts[@]}" ]; then
    echo "FAIL qml6 printed ${#lines[@]} argv line(s) for ${#texts[@]} text(s), so ui/js/X11Copy.js did not load"
    exit 1
fi

# The tools the script may reach; a stub writes its stdin to rec/<tool> and its arguments beside it.
# STUB_xclip and STUB_xsel: ok, fail (exit 1, as with no X display), or linger (fork an owner that
# keeps the inherited stdout and stderr, which is what a real xclip or xsel selection owner does).
stub() {
    cat > "$test_root/bin/$1" <<STUB
#!$sh_bin
printf '%s\n' "\$*" > "$test_root/rec/$1.args"
cat > "$test_root/rec/$1"
case "\${STUB_$1:-ok}" in
    fail) exit 1 ;;
    linger) sleep 30 & echo \$! > "$test_root/owner.pid" ;;
esac
exit 0
STUB
    chmod +x "$test_root/bin/$1"
}
for tool in cat sleep; do ln -sf "$(command -v "$tool")" "$test_root/bin/$tool" || exit 1; done

# Runs one argv with only bin/ on PATH and both pipes captured, the way Quickshell's Process holds
# them; the script's own exit status is the status Process reports.
run_argv() {
    local -a argv=()
    local field value
    for field in $1; do printf -v value '%b' "${field//%/\\x}"; argv+=("$value"); done
    argv[0]=$sh_bin
    rm -f "$test_root/rec/"*
    (cd "$test_root/cwd" && PATH="$test_root/bin" "$timeout_bin" 10 "${argv[@]}" 2>&1 | cat > "$test_root/rec/pipe"; exit "${PIPESTATUS[0]}")
    echo "$?"
}
same_bytes() { printf '%s' "$2" > "$test_root/want"; cmp -s "$test_root/want" "$1" && echo same || echo "differs: $(od -c "$1" 2>&1 | head -3 | tr '\n' ' ')"; }

stub xclip
stub xsel
for i in "${!texts[@]}"; do
    label=$(printf '%q' "${texts[$i]}")
    status=$(run_argv "${lines[$i]}")
    check "xclip copies $label exactly" "$status $(same_bytes "$test_root/rec/xclip" "${texts[$i]}")" "0 same"
done
check "nothing in a copied text ran" "$(ls "$test_root/cwd")" ""
args=$(cat "$test_root/rec/xclip.args")
case " $args " in *" -selection c"*|*" -sel c"*) sel=clipboard ;; *) sel="other: $args" ;; esac
check "xclip writes the CLIPBOARD selection, the one Ctrl+V pastes" "$sel" clipboard
check "xsel is not started when xclip copied" "$([ -e "$test_root/rec/xsel" ] && echo started || echo idle)" idle

argv_line=${lines[3]}
check "a failing xclip falls back to xsel" "$(STUB_xclip=fail run_argv "$argv_line") $(same_bytes "$test_root/rec/xsel" "${texts[3]}")" "0 same"
rm -f "$test_root/bin/xclip"
check "no xclip: xsel copies the text exactly" "$(run_argv "$argv_line") $(same_bytes "$test_root/rec/xsel" "${texts[3]}")" "0 same"
args=$(cat "$test_root/rec/xsel.args")
case " $args " in *" --clipboard "*|*" -b "*) sel=clipboard ;; *) sel="other: $args" ;; esac
check "xsel writes the CLIPBOARD selection" "$sel" clipboard
rm -f "$test_root/bin/xsel"
status=$(run_argv "$argv_line")
check "neither tool: the copy reports a failure" "$([ "$status" -ne 0 ] && echo failed || echo "exit 0")" failed

# A real owner outlives the copy; the script must still exit at once and close both pipes.
for tool in xclip xsel; do
    stub "$tool"
    [ "$tool" = xsel ] && rm -f "$test_root/bin/xclip"
    start=$(date +%s)
    status=$(STUB_xclip=linger STUB_xsel=linger run_argv "$argv_line")
    took=$(( $(date +%s) - start ))
    check "$tool leaves an owner running: the copy still finishes" "$status $([ "$took" -lt 5 ] && echo prompt || echo "took ${took}s")" "0 prompt"
    [ -f "$test_root/owner.pid" ] && kill "$(cat "$test_root/owner.pid")" 2>/dev/null
    rm -f "$test_root/owner.pid"
done

printf 'clipboard-x11: %s check(s), %s failed\n' "$((pass + fail))" "$fail"
[ "$fail" -eq 0 ]
