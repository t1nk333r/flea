"""Use the shared shell guard before allocating a Python fixture directory."""
from pathlib import Path
import subprocess
import tempfile


def make(prefix):
    repo = Path(__file__).resolve().parents[3]
    result = subprocess.run(['bash', '-c',
                             'source "$1/tools/flea-sandbox-guard"; sandbox_root_ok; printf "%s" "$SANDBOX_ROOT"',
                             'fixture', str(repo)], check=True, capture_output=True, text=True)
    directory = Path(tempfile.mkdtemp(prefix=prefix, dir=result.stdout))
    subprocess.run(['bash', '-c', 'source "$1/tools/flea-sandbox-guard"; sandbox_require "$2"',
                    'fixture', str(repo), str(directory)], check=True)
    return directory
