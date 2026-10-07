#!/usr/bin/env python3
"""Manifest transitions preserve unowned data and installation confinement."""
import os
from pathlib import Path
import shutil
import subprocess
from sandbox import make

trusted = Path(__file__).resolve().parents[3]
repo = Path(os.environ.get('FLEA_INSTALL_REPO', trusted)).resolve()
root = make('picker-install-')
env = dict(os.environ)
# The installer always uses release/flea; accept the same built binary seam as other suites.
binary = Path(env.get('FLEA_BIN', repo/'target/debug/flea')).resolve()
(root/'target/release').mkdir(parents=True)
shutil.copy2(binary, root/'target/release/flea')
env['CARGO_TARGET_DIR'] = str(root/'target')
env['TMPDIR'] = str(root)


def install(destination, *args, success=True):
    result = subprocess.run([str(repo/'tools/flea-install'), '--destdir', str(destination), *args],
                            env=env, capture_output=True, text=True)
    assert (result.returncode == 0) == success, result.stdout + result.stderr
    return result


def inventory(stage):
    result = {}
    for p in stage.rglob('*'):
        key = str(p.relative_to(stage))
        if key == 'usr/share/flea/install-manifest' or p.is_dir() and not p.is_symlink():
            continue
        result[key] = ('link', str(p.readlink())) if p.is_symlink() else ('file', p.stat().st_mode & 0o777, p.read_bytes())
    return result


try:
    stage = root/'stage'
    install(stage)
    assert (stage/'usr/share/applications/com.thisisgm.flea.desktop').is_file()
    user = stage/'usr/share/flea/user-owned.txt'
    user.write_text('untouched')
    install(stage, '--picker')
    subprocess.run(['python', str(trusted/'tests/generic/picker/layout.py'), str(stage)], check=True)
    assert not (stage/'usr/share/licenses/flea').exists()
    assert user.read_text() == 'untouched'
    manifest = (stage/'usr/share/flea/install-manifest').read_text()
    assert 'picker-only' in manifest and 'com.thisisgm.flea.desktop' not in manifest
    direct = root/'direct'
    subprocess.run([str(repo/'packaging/flea-picker-install'), str(repo), str(direct), str(binary), 'flea-picker'], check=True)
    actual = inventory(stage)
    del actual['usr/share/flea/user-owned.txt']
    assert actual == inventory(direct), 'plain install differs from package payload'
    install(stage)
    assert not (stage/'usr/share/flea/picker-only').exists()
    assert not (stage/'usr/share/licenses/flea-picker').exists()
    assert (stage/'usr/share/flea/shelf/manifest.json').is_file()
    assert (stage/'usr/lib/flea/flea-filemanager1').is_file()
    assert user.read_text() == 'untouched'
    install(stage, '--picker')
    install(stage, '--picker', '--uninstall', success=False)
    assert (stage/'usr/bin/flea').is_file()
    result = install(stage, '--uninstall')
    assert '--default' not in result.stdout
    assert not (stage/'usr/bin/flea').exists() and user.read_text() == 'untouched'
    assert not (stage/'usr/share/licenses/flea-picker').exists()
    foreign = root/'foreign'
    (foreign/'usr/bin').mkdir(parents=True)
    (foreign/'usr/bin/flea').write_text('foreign')
    install(foreign, '--picker', success=False)
    assert (foreign/'usr/bin/flea').read_text() == 'foreign'
    install(foreign, '--picker', '--force')
    install(foreign, '--uninstall')
    linked = root/'linked'
    (linked/'usr/share').mkdir(parents=True)
    elsewhere = root/'elsewhere'; elsewhere.mkdir()
    (linked/'usr/share/flea').symlink_to(elsewhere, target_is_directory=True)
    install(linked, '--picker', success=False)
    assert not list(elsewhere.iterdir())
    writable = root/'writable'; writable.mkdir(); writable.chmod(0o777)
    install(writable, '--picker', success=False)
    assert not list(writable.iterdir())
    print('picker install: PASS full/picker/full transitions, manifest pruning, payload equality and confinement')
finally:
    shutil.rmtree(root)
