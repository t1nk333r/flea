#!/usr/bin/env python3
"""Reject privilege-bearing archives and missing mandatory trusted results."""
import io
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
from sandbox import make

repo = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(repo/'tools'))
from picker.archive import validate, DEPENDENCIES, CONFLICTS, EXECUTABLES, DATA, LINKS, UI, LICENSE

sb = make('pv-')
try:
    info = 'pkgname = flea-picker\npkgbase = flea-picker\npkgver = 1-1\narch = x86_64\nprovides = flea-picker-portal\nmakedepend = cargo\n'
    info += ''.join('depend = '+d+'\n' for d in sorted(DEPENDENCIES))
    info += ''.join('conflict = '+d+'\n' for d in sorted(CONFLICTS))
    def package(extra=None, replacement=None, attributes=None, tail=b''):
        path = sb/'fixture.pkg.tar.zst'
        raw = io.BytesIO()
        with tarfile.open(fileobj=raw, mode='w') as archive:
            for name in sorted(EXECUTABLES | DATA | {'.PKGINFO', UI+'qmldir', UI+'boot/picker.qml', UI+'boot/shell.qml', LICENSE+'LICENSE', LICENSE+'LICENSE.omarchy'}):
                content = b'fixture'
                if name == '.PKGINFO':
                    content = (replacement or info).encode()
                if name == 'usr/share/flea/picker-only':
                    content = b'picker-only\n'
                member = tarfile.TarInfo(name)
                member.mode = 0o755 if name in EXECUTABLES else 0o644
                member.size = len(content)
                for attribute, value in (attributes or {}).get(name, {}).items():
                    setattr(member, attribute, value)
                archive.addfile(member, io.BytesIO(content))
            for name, target in LINKS.items():
                member = tarfile.TarInfo(name); member.type = tarfile.SYMTYPE; member.linkname = target; member.mode = 0o777
                archive.addfile(member)
            if extra is not None:
                archive.addfile(extra, io.BytesIO(b'x'*extra.size))
            archive.fileobj.write(tail)
            archive.offset += len(tail)
        path.write_bytes(subprocess.run(['zstd', '-q', '-c'], input=raw.getvalue(), capture_output=True, check=True).stdout)
        return path
    assert set(validate(package())) == DEPENDENCIES
    for name, kind, mode, link in [
        ('.INSTALL', tarfile.REGTYPE, 0o644, ''),
        ('usr/share/libalpm/hooks/evil.hook', tarfile.REGTYPE, 0o644, ''),
        ('usr/bin/evil', tarfile.REGTYPE, 0o4755, ''),
        ('../../etc/evil', tarfile.REGTYPE, 0o644, ''),
        ('/etc/evil', tarfile.REGTYPE, 0o644, ''),
        (UI+'bad.qml', tarfile.LNKTYPE, 0o644, 'usr/bin/flea'),
        (UI+'bad.qml', tarfile.SYMTYPE, 0o777, '/etc/passwd'),
        (UI+'Commons/evil', tarfile.REGTYPE, 0o644, ''),
        (UI+'bad.qml', tarfile.REGTYPE, 0o755, ''),
        ('usr/bin/flea', tarfile.REGTYPE, 0o755, ''),
        (UI+'bad.qml', tarfile.REGTYPE, 0o2644, ''),
    ]:
        member = tarfile.TarInfo(name); member.type = kind; member.mode = mode; member.linkname = link
        if kind == tarfile.REGTYPE:
            member.size = 1
        try:
            validate(package(member))
        except ValueError:
            pass
        else:
            raise AssertionError('unsafe package accepted: '+name)
    # Build-only requirements are inherited from upstream and may change without a verifier update.
    assert set(validate(package(replacement=info+'makedepend = git\n'))) == DEPENDENCIES
    for replacement in [info+'depend = qt6-webengine\n', info.replace('flea-picker-portal', 'flea'), info+'install = evil\n',
                        info+'makedepend = $(evil)\n']:
        try:
            validate(package(replacement=replacement))
        except ValueError:
            pass
        else:
            raise AssertionError('unsafe metadata accepted')
    for attributes in [
        {'usr/bin/flea': {'pax_headers': {'LIBARCHIVE.xattr.security.capability': 'AQAAAoAAAAAAAAAAAAAAAAAAAAA='}}},
        {'usr/lib/flea/flea-portal': {'uname': 'build'}},
    ]:
        try:
            validate(package(attributes=attributes))
        except ValueError:
            pass
        else:
            raise AssertionError('privilege-bearing extension or owner accepted')
    # A header with a broken checksum ends Python's iteration but not libarchive's, which retries
    # past it; the scriptlet behind it must still be seen. An empty segment aliases a listed path.
    broken = bytearray(tarfile.TarInfo('broken').tobuf())
    broken[148:156] = b'0000000\0'
    script = tarfile.TarInfo('.INSTALL'); script.size = 4
    alias = tarfile.TarInfo(UI+'/boot/picker.qml'); alias.size = 1
    for case, build in [('hidden scriptlet', lambda: package(tail=bytes(broken)+script.tobuf()+b'evil'.ljust(512, b'\0'))),
                        ('empty path segment', lambda: package(alias))]:
        try:
            validate(build())
        except ValueError:
            pass
        else:
            raise AssertionError(case+' accepted')
    baseline, candidate = sb/'baseline', sb/'candidate'
    baseline.mkdir(); candidate.mkdir()
    for gate in ['generic', 'picker-build', 'picker-install']:
        (candidate/(gate+'.rc')).write_text('0\n')
        (candidate/(gate+'.log')).write_text('fixture\n')
        (candidate/(gate+'.failures')).write_text('')
    command = [str(repo/'tools/fork-verify'), 'compare', '--baseline', str(baseline), '--candidate', str(candidate)]
    assert subprocess.run(command, capture_output=True).returncode == 0
    for gate in ['picker-build', 'picker-install']:
        (candidate/(gate+'.rc')).unlink()
        result = subprocess.run(command, capture_output=True, text=True)
        assert result.returncode != 0 and gate in result.stdout, result.stdout
        (candidate/(gate+'.rc')).write_text('1\n')
        (baseline/(gate+'.rc')).write_text('1\n')
        result = subprocess.run(command, capture_output=True, text=True)
        assert result.returncode != 0, 'picker failure compared away against baseline'
        (candidate/(gate+'.rc')).write_text('0\n')
    print('picker verify: PASS unsafe archive/metadata cases, missing results and unconditional picker failures')
finally:
    shutil.rmtree(sb)
