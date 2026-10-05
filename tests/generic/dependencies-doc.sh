#!/usr/bin/env bash
# Package dependencies are part of the installation contract, not a copied list.
set -euo pipefail
repo=$(realpath "$(dirname "$0")/../..")
mapfile -t dependencies < <(startdir="$repo" bash -c 'source "$startdir/PKGBUILD"; printf "%s\n" "${depends[@]}"')
python - "$repo/docs/install-linux.md" "${dependencies[@]}" <<'PY'
from pathlib import Path
import re
import sys

def missing(names, text):
    documented = set()
    for line in text.splitlines():
        if line.startswith('|'):
            column = re.sub(r'\([^)]*\)', '', line.split('|')[1])
            documented.update(re.findall(r'\b[a-z][a-z0-9+.-]*', column))
    return sorted(set(re.split(r'[<>=]', name, maxsplit=1)[0] for name in names)-documented)

text = Path(sys.argv[1]).read_text()
absent = missing(sys.argv[2:], text)
if absent:
    raise SystemExit('dependency documentation missing Arch package(s): '+', '.join(absent))
assert missing(['new-runtime-dependency'], text) == ['new-runtime-dependency']
print('dependency documentation: PASS every package requirement has a distro mapping row')
PY
