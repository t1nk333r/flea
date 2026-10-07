#!/usr/bin/env python3
"""Call the real installed backend on a private session bus; no fake picker/helper."""
import os
from pathlib import Path
import shutil
import subprocess
import time
import gi
from sandbox import make

gi.require_version('Gio', '2.0')
from gi.repository import Gio, GLib

sb = make('pb-')
connection = Gio.bus_get_sync(Gio.BusType.SESSION, None)
name = 'org.freedesktop.impl.portal.desktop.flea'
iface = 'org.freedesktop.impl.portal.FileChooser'
object_path = '/org/freedesktop/portal/desktop'
try:
    for lane in ('withdrawn', 'fault'):
        work = sb/lane
        for part in ('home', 'config', 'state', 'data', 'cache', 'runtime', 'tmp', 'fixture'):
            (work/part).mkdir(parents=True)
        (work/'runtime').chmod(0o700)
        (work/'fixture/file.txt').write_text('fixture')
        env = dict(os.environ, HOME=str(work/'home'), XDG_CONFIG_HOME=str(work/'config'),
                   XDG_STATE_HOME=str(work/'state'), XDG_DATA_HOME=str(work/'data'),
                   XDG_CACHE_HOME=str(work/'cache'), XDG_RUNTIME_DIR=str(work/'runtime'),
                   TMPDIR=str(work/'tmp'), FLEA_BIN='/usr/bin/flea', FLEA_UI='/usr/share/flea/ui',
                   FLEA_COMMONS='compat', QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                   QSG_RHI_BACKEND='software', DISPLAY=':999' if lane == 'withdrawn' else '')
        for variable in ('WAYLAND_DISPLAY', 'QML_IMPORT_PATH', 'QML2_IMPORT_PATH', 'QT_PLUGIN_PATH'):
            env.pop(variable, None)
        with (work/'portal.log').open('w') as log:
            service = subprocess.Popen(['/usr/lib/flea/flea-portal'], env=env, stdout=log, stderr=subprocess.STDOUT)
            try:
                deadline = time.monotonic()+10
                while time.monotonic()<deadline:
                    owned = connection.call_sync('org.freedesktop.DBus', '/org/freedesktop/DBus',
                              'org.freedesktop.DBus', 'NameHasOwner', GLib.Variant('(s)', (name,)),
                              GLib.VariantType.new('(b)'), Gio.DBusCallFlags.NONE, 1000, None).unpack()[0]
                    if owned:
                        break
                    assert service.poll() is None, 'installed backend exited'
                    time.sleep(.05)
                else:
                    raise RuntimeError('installed backend never owned the bus name')
                handle = '/org/freedesktop/portal/desktop/request/gate/'+lane
                parameters = GLib.Variant('(osssa{sv})', (handle, 'org.example.PickerGate', '', 'Gate',
                    {'current_folder': GLib.Variant('ay', list(str(work/'fixture').encode())+[0])}))
                answers = []
                def answered(bus, result):
                    answers.append(bus.call_finish(result).unpack())
                connection.call(name, object_path, iface, 'OpenFile', parameters,
                                GLib.VariantType.new('(ua{sv})'), Gio.DBusCallFlags.NONE, 20000, None, answered)
                if lane == 'withdrawn':
                    while time.monotonic()<deadline:
                        ready = subprocess.run(['qs', 'ipc', '-p', '/usr/share/flea/ui/boot-compat/picker.qml',
                                                'call', 'fleapicker', 'ready'], env=env, capture_output=True, text=True)
                        if ready.returncode == 0 and ready.stdout.strip() == 'true':
                            break
                        time.sleep(.05)
                    else:
                        raise RuntimeError('installed portal did not launch its actual picker')
                    connection.call_sync(name, handle, 'org.freedesktop.impl.portal.Request', 'Close',
                                         None, None, Gio.DBusCallFlags.NONE, 5000, None)
                context = GLib.MainContext.default()
                deadline = time.monotonic()+15
                while not answers and time.monotonic()<deadline:
                    while context.pending():
                        context.iteration(False)
                    time.sleep(.02)
                assert answers == [(2, {})], answers
                print('picker portal: PASS OpenFile '+lane+' returns response 2 exactly once')
            finally:
                if service.poll() is None:
                    service.terminate()
                service.wait(timeout=10)
        deadline = time.monotonic()+3
        while time.monotonic()<deadline:
            owned = connection.call_sync('org.freedesktop.DBus', '/org/freedesktop/DBus', 'org.freedesktop.DBus',
                                         'NameHasOwner', GLib.Variant('(s)', (name,)), GLib.VariantType.new('(b)'),
                                         Gio.DBusCallFlags.NONE, 1000, None).unpack()[0]
            if not owned:
                break
            time.sleep(.02)
finally:
    shutil.rmtree(sb)
