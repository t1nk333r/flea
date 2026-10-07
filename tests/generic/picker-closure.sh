#!/usr/bin/env bash
set -euo pipefail
repo=$(realpath "$(dirname "$0")/../..")
exec python "$repo/tests/generic/picker/closure.py"
