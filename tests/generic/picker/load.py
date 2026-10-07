#!/usr/bin/env python3
"""Real installed picker listings and all deferred QML compiled offscreen."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from sandbox import make
import time
from probe import generate

repo = Path(__file__).resolve().parents[3]
sb = make('pl-')
FAILED = re.compile(r'is not a type|Cannot open|No such file or directory|(?:Type|Script) .* unavailable|'
                    r'module .* is not installed|import (?:error|.*not found)|'
                    r'Failed to load configuration|(?:Loader|component).*error|PICKER_PROBE_FAILED', re.I)
ANSI = re.compile(r'\x1b\[[0-9;]*[A-Za-z]')


def environment(lane, ui, binary):
    w = sb / lane
    for p in ['h', 'c', 's', 'd', 'k', 'r', 't']:
        (w/p).mkdir(parents=True)
    (w/'r').chmod(0o700)
    env = {k: v for k, v in os.environ.items() if k not in
           ('QML_IMPORT_PATH', 'QML2_IMPORT_PATH', 'QT_PLUGIN_PATH', 'QML_DISK_CACHE_PATH',
            'WAYLAND_DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE', 'FLEA_SELECT', 'FLEA_PATH')}
    env.update(HOME=str(w/'h'), XDG_CONFIG_HOME=str(w/'c'), XDG_STATE_HOME=str(w/'s'),
               XDG_DATA_HOME=str(w/'d'), XDG_CACHE_HOME=str(w/'k'), XDG_RUNTIME_DIR=str(w/'r'),
               TMPDIR=str(w/'t'), FLEA_UI=str(ui), FLEA_BIN=str(binary), FLEA_COMMONS='compat',
               QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', QSG_RHI_BACKEND='software',
               QT_FORCE_STDERR_LOGGING='1', DISPLAY=':999')
    return w, env


def ipc(entry, target, method, env):
    return subprocess.run(['qs', 'ipc', '-p', str(entry), 'call', target, method],
                          env=env, capture_output=True, text=True, timeout=3)


def exercise(command, entry, env, logfile, predicate):
    with logfile.open('w') as log:
        process = subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 25
            while time.monotonic() < deadline:
                if process.poll() is not None:
                    raise RuntimeError(f'picker process exited {process.returncode}')
                if predicate():
                    break
                time.sleep(.1)
            else:
                raise RuntimeError('installed picker did not meet its runtime predicate')
        finally:
            if process.poll() is None:
                process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
    text = ANSI.sub('', logfile.read_text())
    if FAILED.search(text):
        raise RuntimeError('installed load diagnostics: '+text)


success = False
try:
    if len(sys.argv) == 3:
        ui = Path(sys.argv[1]).resolve()
        binary = Path(sys.argv[2]).resolve()
    elif len(sys.argv) == 1:
        binary = Path(os.environ.get('FLEA_BIN', repo/'target/debug/flea')).resolve()
        subprocess.run([str(repo/'packaging/flea-picker-install'), str(repo), str(sb/'stage'),
                        str(binary), 'flea-picker'], check=True)
        ui = sb/'stage/usr/share/flea/ui'
        binary = sb/'stage/usr/bin/flea'
    else:
        raise RuntimeError('usage: picker-load.sh [UI_DIR FLEA_BIN]')
    if not shutil.which('qs') or not binary.is_file() or not (ui/'boot-compat/picker.qml').is_file():
        raise RuntimeError('installed picker prerequisites are missing')
    fixture = sb/'fixture'
    fixture.mkdir()
    (fixture/'alpha.txt').write_text('alpha')
    (fixture/'beta.txt').write_text('beta')
    (fixture/'folder').mkdir()
    for lane, request, view, expected in [
        ('o', {'mode': 'open', 'multiple': True}, 'list', {'alpha.txt', 'beta.txt', 'folder'}),
        ('g', {'mode': 'open'}, 'grid', {'alpha.txt', 'beta.txt', 'folder'}),
        ('s', {'mode': 'save', 'name': 'suggested.txt'}, 'list', {'alpha.txt', 'beta.txt', 'folder'}),
        ('f', {'mode': 'open', 'directory': True}, 'list', {'alpha.txt', 'beta.txt', 'folder'}),
        ('m', {'mode': 'savefiles', 'files': ['one.txt', 'two.txt']}, 'list', {'alpha.txt', 'beta.txt', 'folder'}),
    ]:
        w, env = environment(lane, ui, binary)
        (w/'s/flea').mkdir()
        (w/'s/flea/ui.json').write_text(json.dumps({'pickerView': view})+'\n')
        env['FLEA_PICKER'] = json.dumps(dict(request, folder=str(fixture), app='org.example.PickerGate'))
        entry = ui/'boot-compat/picker.qml'
        def listed():
            ready = ipc(entry, 'fleapicker', 'ready', env)
            if ready.returncode or ready.stdout.strip() != 'true':
                return False
            result = ipc(entry, 'fleapicker', 'snapshot', env)
            if result.returncode:
                return False
            snap = json.loads(result.stdout)
            if snap['state'] != 'ready':
                return False
            assert snap['path'] == str(fixture) and snap['view'] == view, snap
            assert {row['n'] for row in snap['rows']} == expected and snap['total'] == len(expected), snap
            assert not snap['backendUnavailable'] and not snap['listingFailed'], snap
            if request['mode'] == 'save':
                assert snap['saveName'] == 'suggested.txt', snap
            if request.get('directory') or request['mode'] == 'savefiles':
                accept = ipc(entry, 'fleapicker', 'accept', env)
                assert accept.returncode == 0 and accept.stdout.strip() == 'Choose folder', accept
            return True
        exercise([str(binary), '--pick', str(w/'reply')], entry, env, sb/(lane+'.log'), listed)
        print(f'picker load: PASS {lane} exact rows and {view} view')
    w, env = environment('p', ui, binary)
    directory = sb/'probe'; directory.mkdir()
    components, singletons = generate(ui, directory)
    entry = directory/'probe.qml'
    def compiled():
        result = ipc(entry, 'pickerprobe', 'ready', env)
        return result.returncode == 0 and result.stdout.strip() == 'true'
    exercise(['qs', '-p', str(entry)], entry, env, sb/'probe.log', compiled)
    print(f'picker load: PASS {components} compiled components and {singletons} singleton accesses')
    success = True
except Exception as error:
    print(f'picker load: FAIL {error}; retained evidence: {sb}', file=sys.stderr)
    for log in sb.glob('*.log'):
        print(log.name+'\n'+log.read_text(), file=sys.stderr)
    sys.exit(1)
finally:
    if success:
        shutil.rmtree(sb)
