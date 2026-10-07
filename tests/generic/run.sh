#!/usr/bin/env bash
# Runs the fork's own suites, the ones tests/run-all.sh never sees (its audit globs tests/*.sh only).
# Each suite's OWN exit code is read, the tests/run-all.sh rule. Builds nothing: launch-root,
# shellload-compat and terminal-fallback need target/debug/flea (or FLEA_BIN), so build first.
#   tests/generic/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1

suites="compat-surface compat-parity shellload-compat launch-root js clipboard-x11 terminal-fallback picker-closure"
failed=0
ran=0
skipped=0
for name in $suites; do
    suite="tests/generic/$name.sh"
    [ -x "$suite" ] || { printf '  %-17s FAIL   no executable at %s\n' "$name" "$suite"; failed=$((failed + 1)); continue; }
    out=$("./$suite" 2>&1)
    rc=$?
    ran=$((ran + 1))
    last=$(printf '%s\n' "$out" | grep -v '^[[:space:]]*$' | tail -1)
    # A suite that skipped all or part of its proof says so on a SKIP or skip line; that is not an ok.
    skip=$(printf '%s\n' "$out" | grep -m1 -E '(^|: )(SKIP|skip) ')
    if [ "$rc" -eq 0 ] && [ -n "$skip" ]; then
        printf '  %-17s SKIP   %s\n' "$name" "$skip"
        skipped=$((skipped + 1))
    elif [ "$rc" -eq 0 ]; then
        printf '  %-17s ok     %s\n' "$name" "$last"
    else
        printf '  %-17s FAIL   rc=%s\n' "$name" "$rc"
        printf '%s\n' "$out" | sed 's/^/      /'
        failed=$((failed + 1))
    fi
done

# A suite in tests/generic that the list above does not name is run by nothing, so it fails here.
orphans=""
for suite in tests/generic/*.sh; do
    name=${suite#tests/generic/}
    name=${name%.sh}
    [ "$name" = run ] && continue
    case " $suites " in *" $name "*) continue ;; esac
    orphans="$orphans $name"
done
if [ -n "$orphans" ]; then
    printf '\ngeneric run: FAIL suite(s) no list runs:%s\n' "$orphans"
    failed=$((failed + 1))
fi

printf '\ngeneric run: %d suite(s) run, %d skipped, %d failed\n' "$ran" "$skipped" "$failed"
exit "$failed"
