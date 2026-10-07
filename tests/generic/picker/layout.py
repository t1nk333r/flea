#!/usr/bin/env python3
"""Check the installed picker contract, including absent file-manager payload."""
from pathlib import Path
import os
import sys

root = Path(sys.argv[1])
ui = root / 'usr/share/flea/ui'
assert (root/'usr/share/flea/picker-only').read_bytes() == b'picker-only\n'
for path in ['usr/bin/flea', 'usr/lib/flea/flea-portal', 'usr/lib/flea/flea-gio-auth']:
    assert os.access(root/path, os.X_OK), path
service = root/'usr/share/dbus-1/services/org.freedesktop.impl.portal.desktop.flea.service'
assert 'Exec=/usr/lib/flea/flea-portal' in service.read_text()
portal = (root/'usr/share/xdg-desktop-portal/portals/flea.portal').read_text()
assert 'org.freedesktop.impl.portal.FileChooser' in portal and 'FileManager1' not in portal
for pattern in ['usr/share/applications/*flea*', 'usr/share/dbus-1/services/*FileManager1*',
                'usr/lib/flea/flea-filemanager1', 'usr/share/flea/shelf',
                'usr/share/libalpm/hooks/*flea*']:
    assert not list(root.glob(pattern)), pattern
for path in ['WindowBody.qml', 'RendererRetry.qml', 'PreviewPdf.qml', 'PreviewMedia.qml',
             'MediaSound.qml', 'boot/fleatab.qml', 'boot/tabtearoff.qml', 'boot-compat/shell.qml']:
    assert not (ui/path).exists(), path
assert (ui/'boot/shell.qml').is_file() and (ui/'boot/picker.qml').is_file()
assert (ui/'boot-compat/picker.qml').readlink() == Path('../boot/picker.qml')
for module in ['Commons', 'Ui']:
    assert (ui/f'boot-compat/{module}').readlink() == Path(f'../compat/{module}')
    for path in [ui/module, ui/'boot'/module]:
        assert path.readlink() == Path(f'/usr/share/omarchy/shell/{module}')
for line in (ui/'qmldir').read_text().splitlines():
    if not line or line.startswith('module '):
        continue
    assert (ui/line.split()[-1]).is_file(), line
for path in ui.rglob('*'):
    if path.is_symlink():
        continue
    if path.is_file() and path.suffix in ('.qml', '.js', '.mjs') and path != ui/'boot/shell.qml':
        assert 'import QtMultimedia' not in path.read_text() and 'import QtQuick.Pdf' not in path.read_text(), path
    if path.is_file():
        assert path.stat().st_mode & 0o111 == 0, path
assert (root/'usr/share/licenses/flea-picker/LICENSE').is_file()
assert (root/'usr/share/licenses/flea-picker/LICENSE.omarchy').is_file()
print('picker layout: PASS portal-only payload, pruned registry, profile and confined compat links')
