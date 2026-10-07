"""Validate an immutable candidate archive before pacman may install it as root."""
from pathlib import PurePosixPath
import re
import subprocess
import tarfile

DEPENDENCIES = {'bash', 'bubblewrap', 'coreutils', 'dbus', 'fontconfig', 'gcc-libs',
                'glib2', 'glibc', 'gvfs', 'python', 'python-gobject', 'qt6-declarative',
                'quickshell>=0.3.1', 'shared-mime-info', 'util-linux', 'xdg-desktop-portal'}
CONFLICTS = {'flea', 'flea-bin', 'flea-git', 'flea-generic'}
OPTIONAL = {'gvfs-afc', 'gvfs-dnssd', 'gvfs-gphoto2', 'gvfs-mtp', 'gvfs-nfs', 'gvfs-smb',
            'kimageformats', 'libheif', 'ffmpegthumbnailer', 'xdg-terminal-exec', 'xdg-desktop-portal-gtk'}
EXECUTABLES = {'usr/bin/flea', 'usr/lib/flea/flea-portal', 'usr/lib/flea/flea-gio-auth'}
DATA = {'usr/share/flea/picker-only', 'usr/share/xdg-desktop-portal/portals/flea.portal',
        'usr/share/dbus-1/services/org.freedesktop.impl.portal.desktop.flea.service'}
METADATA = {'.PKGINFO', '.BUILDINFO', '.MTREE'}
UI = 'usr/share/flea/ui/'
LICENSE = 'usr/share/licenses/flea-picker/'
LINKS = {UI+'boot-compat/picker.qml': '../boot/picker.qml',
         UI+'boot-compat/Commons': '../compat/Commons', UI+'boot-compat/Ui': '../compat/Ui'}
for module in ('Commons', 'Ui'):
    for prefix in ('', 'boot/'):
        LINKS[UI+prefix+module] = '/usr/share/omarchy/shell/'+module
DIRECTORIES = set()
for path in EXECUTABLES | DATA | {UI+'x', LICENSE+'x'}:
    DIRECTORIES.update(str(p) for p in PurePosixPath(path).parents if str(p) != '.')


def forbidden(name):
    return name == 'omarchy' or name.startswith(('omarchy-', 'qt6-multimedia', 'qt6-webengine')) or name in CONFLICTS


def metadata(text):
    fields = {}
    allowed = {'pkgname', 'pkgbase', 'xdata', 'pkgver', 'pkgdesc', 'url', 'builddate', 'packager',
               'size', 'arch', 'license', 'conflict', 'provides', 'depend', 'optdepend', 'makedepend'}
    for line in text.splitlines():
        if not line or line.startswith('#'):
            continue
        key, separator, value = line.partition(' = ')
        if not separator or key not in allowed:
            raise ValueError('unapproved package metadata field: '+key)
        fields.setdefault(key, []).append(value)
    for key in ('pkgname', 'pkgbase'):
        if fields.get(key) != ['flea-picker']:
            raise ValueError('archive must name flea-picker')
    if fields.get('provides') != ['flea-picker-portal']:
        raise ValueError('unapproved package capabilities')
    # Build-only metadata is inherited from upstream and never reaches the installing system.
    if not all(re.fullmatch(r'[a-z0-9@._+-]+(?:[<>=]+[A-Za-z0-9._:+~-]+)?', d) for d in fields.get('makedepend', [])):
        raise ValueError('malformed build requirement')
    deps = fields.get('depend', [])
    if len(deps) != len(DEPENDENCIES) or set(deps) != DEPENDENCIES:
        raise ValueError('unapproved runtime dependency set')
    if len(fields.get('conflict', [])) != len(CONFLICTS) or set(fields.get('conflict', [])) != CONFLICTS:
        raise ValueError('incorrect package conflicts')
    if not all(value.split(': ', 1)[0] in OPTIONAL for value in fields.get('optdepend', [])):
        raise ValueError('unapproved optional dependency')
    if fields.get('arch') not in (['x86_64'], ['aarch64']):
        raise ValueError('unsupported package architecture')
    if len(fields.get('pkgver', [])) != 1 or not re.fullmatch(r'[A-Za-z0-9._+:-]+', fields['pkgver'][0]):
        raise ValueError('invalid package version')
    return sorted(DEPENDENCIES)


def validate(archive):
    if archive.stat().st_size > 64*1024*1024:
        raise ValueError('candidate archive exceeds the picker size bound')
    process = subprocess.Popen(['zstd', '-dc', '--', str(archive)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    seen, info, total = set(), None, 0
    try:
        # Read past a damaged header the way libarchive does, so nothing after it goes unchecked.
        with tarfile.open(fileobj=process.stdout, mode='r|', ignore_zeros=True) as stream:
            for entry in stream:
                raw = entry.name
                name = raw.removeprefix('./').rstrip('/')
                if any(str(parent) in LINKS for parent in PurePosixPath(name).parents):
                    raise ValueError('archive path traverses a module symlink: '+name)
                if not name or raw.startswith('/') or any(p in ('', '.', '..') for p in name.split('/')) or name in seen:
                    raise ValueError('duplicate or escaping archive path: '+raw)
                seen.add(name)
                total += entry.size
                if len(seen) > 4096 or total > 128*1024*1024:
                    raise ValueError('archive exceeds the picker payload bound')
                if entry.pax_headers.keys() - {'path', 'linkpath', 'size', 'mtime', 'atime', 'ctime'}:
                    raise ValueError('unapproved archive extension metadata: '+name)
                if (entry.uid != 0 or entry.gid != 0 or entry.uname not in ('', 'root') or
                    entry.gname not in ('', 'root') or entry.mode & 0o7000 or
                    (not entry.issym() and entry.mode & 0o022)):
                    raise ValueError('unsafe archive ownership or permissions: '+name)
                if entry.islnk() or not (entry.isdir() or entry.isfile() or entry.issym()):
                    raise ValueError('unsafe archive member kind: '+name)
                if entry.issym():
                    if LINKS.get(name) != entry.linkname:
                        raise ValueError('unapproved archive symlink: '+name)
                    continue
                if name in LINKS:
                    raise ValueError('required symlink is not a symlink: '+name)
                if entry.isdir():
                    if name not in DIRECTORIES and not name.startswith((UI, LICENSE)):
                        raise ValueError('unexpected archive directory: '+name)
                    continue
                if name not in EXECUTABLES | DATA | METADATA and not name.startswith((UI, LICENSE)):
                    raise ValueError('unexpected archive destination: '+name)
                if name not in EXECUTABLES and entry.mode & 0o111:
                    raise ValueError('executable UI/data archive member: '+name)
                if name in EXECUTABLES and entry.mode & 0o111 != 0o111:
                    raise ValueError('nonexecutable helper: '+name)
                if name == '.PKGINFO':
                    if entry.size > 65536:
                        raise ValueError('oversized package metadata')
                    info = stream.extractfile(entry).read().decode('utf-8')
                if name == 'usr/share/flea/picker-only':
                    if entry.size != 12 or stream.extractfile(entry).read() != b'picker-only\n':
                        raise ValueError('invalid picker profile')
        process.stdout.close()
        stderr = process.stderr.read()
        if process.wait() != 0:
            raise ValueError('invalid compressed archive: '+stderr.decode(errors='replace'))
    finally:
        if process.poll() is None:
            process.kill()
        process.wait()
        process.stdout.close()
        process.stderr.close()
    required = EXECUTABLES | DATA | set(LINKS) | {'.PKGINFO', UI+'qmldir', UI+'boot/picker.qml', UI+'boot/shell.qml', LICENSE+'LICENSE', LICENSE+'LICENSE.omarchy'}
    if not required <= seen or info is None:
        raise ValueError('incomplete picker archive layout')
    return metadata(info)
