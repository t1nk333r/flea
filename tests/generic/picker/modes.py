#!/usr/bin/env python3
"""Exercise installed policy, harmless handoffs and reversible picker registration."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from sandbox import make
import time

repo = Path(__file__).resolve().parents[3]
sb = make('pm-')
try:
    if len(sys.argv) == 2:
        binary = Path(sys.argv[1]).resolve()
        data = binary.parent.parent/'share'
    else:
        binary = Path(os.environ.get('FLEA_BIN', repo/'target/debug/flea')).resolve()
        subprocess.run([str(repo/'packaging/flea-picker-install'), str(repo), str(sb/'stage'), str(binary), 'flea-picker'], check=True)
        binary = sb/'stage/usr/bin/flea'
        data = sb/'stage/usr/share'
    for name in ['home', 'config', 'state', 'data', 'cache', 'runtime', 'bin']:
        (sb/name).mkdir()
    (sb/'runtime').chmod(0o700)
    env = dict(os.environ, HOME=str(sb/'home'), XDG_CONFIG_HOME=str(sb/'config'),
               XDG_STATE_HOME=str(sb/'state'), XDG_DATA_HOME=str(sb/'data'),
               XDG_CACHE_HOME=str(sb/'cache'), XDG_RUNTIME_DIR=str(sb/'runtime'),
               XDG_DATA_DIRS=str(data), XDG_CURRENT_DESKTOP='sway', FLEA_UI=str(repo/'ui'),
               PATH=str(sb/'bin')+':/usr/bin', RECORD=str(sb/'record'))
    for name in ['qs', 'xdg-mime', 'systemctl', 'omarchy-update', 'gio', 'xdg-terminal-exec', 'hyprctl']:
        path = sb/'bin'/name
        path.write_text('#!/bin/sh\nprintf "%s\\n" "$0 $*" >> "$RECORD"\nexit 0\n')
        path.chmod(0o755)
    (sb/'data/applications').mkdir()
    (sb/'data/applications/com.thisisgm.flea.desktop').write_text('[Desktop Entry]\nType=Application\nName=Stale Flea\nExec=flea --gui\nMimeType=inode/directory;\n')
    (sb/'config/xdg-desktop-portal').mkdir()
    portal = sb/'config/xdg-desktop-portal/portals.conf'
    before_portal = '[preferred]\ndefault=gtk\norg.freedesktop.impl.portal.FileChooser=gtk\norg.freedesktop.impl.portal.ScreenCast=wlr\n'
    portal.write_text(before_portal)
    (sb/'config/hypr').mkdir()
    bindings = sb/'config/hypr/bindings.lua'; bindings.write_text('-- user binding\n')
    (sb/'config/mimeapps.list').write_text('[Default Applications]\ninode/directory=other.desktop\n')
    def user_files():
        return {str(p.relative_to(sb)): p.read_bytes() for name in ['home','config','state','data','cache'] for p in (sb/name).rglob('*') if p.is_file()}
    initial = user_files()
    def run(args, **kw):
        return subprocess.run([str(binary), *args], env=env, capture_output=True, text=True, timeout=10, **kw)
    for args in [[], ['/tmp'], ['--gui'], ['--select', '/tmp/file'], ['--tui'],
                 ['--default'], ['--default', 'off'], ['--youleftmeforstrata'],
                 ['--update'], ['--update', 'check'], ['shelf', 'status'],
                 ['--a-mode-upstream-adds-later'], ['--default', 'wrong']]:
        result = run(args)
        assert result.returncode == 2 and not result.stdout and len(result.stderr.splitlines()) == 1, (args, result)
        assert 'picker-only install' in result.stderr, (args, result)
        assert user_files() == initial and not (sb/'record').exists(), args
    result = run(['--gui', '--backend'], input='{"c":"quit"}\n')
    assert result.returncode == 0, result
    result = run(['--ui-state']); assert result.returncode == 0 and json.loads(result.stdout)['pickerView'] == 'list', result
    file = sb/'home/--gui'; file.write_text('fixture')
    result = run(['--open', str(file)]); assert result.returncode == 0, result
    result = run(['--select', str(file), '--print-target'])
    assert result.returncode == 0 and result.stdout.split() == [str(sb/'home'), str(file)], result
    assert run(['--open', str(sb/'home')]).returncode == 3
    assert run(['--open', str(sb/'missing')]).returncode == 2
    result = run(['--terminal', str(sb/'home')]); assert result.returncode == 0, result
    deadline = time.monotonic()+3
    while time.monotonic()<deadline and (not (sb/'record').exists() or 'xdg-terminal-exec' not in (sb/'record').read_text()):
        time.sleep(.02)
    record = (sb/'record').read_text()
    assert 'gio open ' in record and 'xdg-terminal-exec' in record, record
    result = run(['--picker']); assert result.returncode == 0, result
    assert 'org.freedesktop.impl.portal.FileChooser=flea;gtk' in portal.read_text()
    assert 'default=gtk' in portal.read_text() and 'ScreenCast=wlr' in portal.read_text()
    assert 'com.thisisgm.flea.picker' in bindings.read_text() and 'o.bind(' not in bindings.read_text()
    assert (sb/'config/mimeapps.list').read_bytes() == initial['config/mimeapps.list']
    assert not list((sb/'data').glob('dbus-1/services/*'))
    result = run(['--picker', 'off']); assert result.returncode == 0, result
    assert portal.read_text() == before_portal and bindings.read_text() == '-- user binding\n'
    print('picker modes: PASS thirteen no-side-effect refusals, helper precedence, the reveal diagnostic, handoffs and reversible FileChooser-only activation')
finally:
    shutil.rmtree(sb)
