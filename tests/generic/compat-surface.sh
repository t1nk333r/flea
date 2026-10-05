#!/bin/bash
# The static drift guard: every Style, Color, Border and Util member ui/ reads, and every Omarchy
# qs.Ui type a ui/ file instantiates, is declared by Flea's fallback under ui/compat. Bash, grep and
# awk only, so the generic PKGBUILD's check() can run it on a box with no Quickshell at all.
#   tests/generic/compat-surface.sh
# FORK_OMARCHY_REF names an Omarchy shell/ checkout whose Ui/qmldir lists qs.Ui's types; without it
# /usr/share/omarchy/shell is read, and without that tests/generic/omarchy-ui-types.txt (v4.0.4).
set -u
cd "$(dirname "$0")/../.." || exit 1

pass=0
fail=0
ok()  { printf 'ok   %s\n' "$*"; pass=$((pass + 1)); }
bad() { printf 'FAIL %s\n' "$*"; fail=$((fail + 1)); }

if [ -n "${FORK_OMARCHY_REF:-}" ]; then
    [ -f "$FORK_OMARCHY_REF/Ui/qmldir" ] || { echo "FAIL FORK_OMARCHY_REF=$FORK_OMARCHY_REF has no Ui/qmldir"; exit 1; }
    omarchy_types=$(awk '$2 ~ /^[0-9.]+$/ { print $1 }' "$FORK_OMARCHY_REF/Ui/qmldir")
    types_from="$FORK_OMARCHY_REF/Ui/qmldir"
elif [ -f /usr/share/omarchy/shell/Ui/qmldir ]; then
    omarchy_types=$(awk '$2 ~ /^[0-9.]+$/ { print $1 }' /usr/share/omarchy/shell/Ui/qmldir)
    types_from=/usr/share/omarchy/shell/Ui/qmldir
else
    omarchy_types=$(cat tests/generic/omarchy-ui-types.txt)
    types_from=tests/generic/omarchy-ui-types.txt
fi

# Sample output line: "ui/Theme.qml:77 Style.spacing.rowPaddingX". Comments are stripped first, the
# rule (^|[[:space:]])// that keeps a file:// URL whole.
refs=$(for f in ui/*.qml ui/boot/*.qml ui/js/*.js; do
    awk -v f="$f" '{
        line = $0
        sub(/(^|[[:space:]])\/\/.*$/, "", line)
        while (match(line, /(^|[^A-Za-z0-9_.])(Style|Color|Border|Util)\.[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)?/)) {
            r = substr(line, RSTART, RLENGTH)
            sub(/^[^A-Z]/, "", r)
            print f ":" NR " " r
            line = substr(line, RSTART + RLENGTH)
        }
    }' "$f"
done)
count=$(printf '%s\n' "$refs" | grep -c .)
if [ "$count" -ge 30 ]; then
    ok "$count Style/Color/Border/Util reference sites derived from ui/"
else
    bad "only $count Style/Color/Border/Util reference sites derived from ui/, so the derivation broke"
fi

# What one compat singleton declares, sample output: "spacing" (a member), "block spacing" (a
# QtObject member), "spacing.rowGap" (a member of that block). Braces are counted per line after
# strings and comments go, so a regex like {1,3} on one line leaves the depth where it was.
declared() {
    awk '{
        line = $0
        gsub(/"[^"]*"/, "\"\"", line)
        sub(/(^|[[:space:]])\/\/.*$/, "", line)
        name = ""
        if (match(line, /^[[:space:]]*(readonly[[:space:]]+)?property[[:space:]]+[A-Za-z_.]+[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/)) {
            name = substr(line, RSTART, RLENGTH); sub(/.*[[:space:]]/, "", name)
        } else if (match(line, /^[[:space:]]*function[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/)) {
            name = substr(line, RSTART, RLENGTH); sub(/.*[[:space:]]/, "", name)
        }
        if (name != "" && depth == 1) {
            print name
            if (line ~ /:[[:space:]]*QtObject[[:space:]]*\{/) { print "block " name; block = name }
        } else if (name != "" && depth == 2 && block != "") {
            print block "." name
        }
        opened = gsub(/\{/, "{", line)
        closed = gsub(/\}/, "}", line)
        depth += opened - closed
        if (depth < 2) block = ""
    }' "$1"
}

missing=""
seen=" "
while read -r site ref; do
    [ -n "$ref" ] || continue
    case "$seen" in *" $ref "*) continue ;; esac
    seen="$seen$ref "
    head=${ref%%.*}
    rest=${ref#*.}
    member=${rest%%.*}
    sub=""
    [ "$rest" != "$member" ] && sub=${rest#*.}
    decls=$(declared "ui/compat/Commons/$head.qml" 2>/dev/null)
    if ! printf '%s\n' "$decls" | grep -qx "$member"; then
        missing="$missing $site:$head.$member"
    elif [ -n "$sub" ] && printf '%s\n' "$decls" | grep -qx "block $member" \
            && ! printf '%s\n' "$decls" | grep -qx "$member\.$sub"; then
        missing="$missing $site:$head.$member.$sub"
    fi
done <<EOF
$refs
EOF
if [ -z "$missing" ]; then
    ok "ui/compat/Commons declares every member ui/ reads"
else
    bad "ui/compat/Commons lacks members ui/ reads, first use of each:"
    printf '%s\n' $missing | sed 's/^/     /'
fi

# Sample input: "    PanelSectionHeader {" in a file that imports qs.Ui; only names Omarchy's qs.Ui exports count.
uses=$(for f in $(grep -l '^import qs\.Ui' ui/*.qml); do
    grep -nE '^[[:space:]]*[A-Z][A-Za-z0-9]*[[:space:]]*\{' "$f" | sed -E "s#^([0-9]+):[[:space:]]*([A-Za-z0-9]+).*#$f:\1 \2#"
done)
ui_missing=""
ui_count=0
seen=" "
while read -r site type; do
    [ -n "$type" ] || continue
    printf '%s\n' "$omarchy_types" | grep -qx "$type" || continue
    case "$seen" in *" $type "*) continue ;; esac
    seen="$seen$type "
    ui_count=$((ui_count + 1))
    grep -qE "^$type [0-9.]+ $type\.qml$" ui/compat/Ui/qmldir || ui_missing="$ui_missing $site:$type"
done <<EOF
$uses
EOF
if [ "$ui_count" -eq 0 ]; then
    bad "no Omarchy qs.Ui type derived from ui/ (types from $types_from), so the derivation broke"
elif [ -z "$ui_missing" ]; then
    ok "ui/compat/Ui exports all $ui_count Omarchy qs.Ui type(s) ui/ instantiates (types from $types_from)"
else
    bad "ui/compat/Ui does not export, first use of each:"
    printf '%s\n' $ui_missing | sed 's/^/     /'
fi

# Quickshell.shellDir is the root a launch took, so a file ui/ loads as shellDir + "/name.qml" (the
# tab tear-off's fleatab.qml and tabtearoff.qml) must sit in boot-compat too: a link to ui/boot's.
unlinked=""
for f in ui/boot/*.qml; do
    name=${f#ui/boot/}
    [ "$(readlink "ui/boot-compat/$name" 2>/dev/null)" = "../boot/$name" ] || unlinked="$unlinked $name"
done
if [ -z "$unlinked" ]; then
    ok "ui/boot-compat links every ui/boot entry ($(ls ui/boot/*.qml | wc -l) files)"
else
    bad "ui/boot-compat has no ../boot/ link for:$unlinked"
fi

printf 'compat-surface: %s check(s), %s failed\n' "$((pass + fail))" "$fail"
[ "$fail" -eq 0 ]
