"""A second, regex-only reading of the closure, independent of the generator's tokenizer."""
from pathlib import Path
import re

BLOCK = re.compile(r'/\*.*?\*/', re.S)
LINE = re.compile(r'(^|[^:])//.*$', re.M)
# A quoted name with a script or component suffix, optionally under a directory.
LITERAL = re.compile(r'''(["'`])((?:[^"'`\n]*/)?[^"'`\n/.][^"'`\n/]*\.(?:qml|m?js))\1''')
# Loader sources and component loads; only path-shaped arguments name a file.
LOAD = re.compile(r'''(?:\bsource\s*[:=]|\bsetSource\s*\(|\bcreateComponent\s*\()\s*(["'`])([^"'`\n]*\.\w+)\1''')


def strip(text):
    text = BLOCK.sub(lambda m: '\n' * m.group(0).count('\n'), text)
    return LINE.sub(r'\1', text)


def unlisted(ui, files):
    """Each reference in a listed file must resolve to a listed file; returns the ones that do not."""
    ui = Path(ui).resolve()
    problems = []
    for relative in sorted(files):
        # boot/shell.qml ships as a discovery sentinel and is never loaded by the picker.
        if not relative.endswith(('.qml', '.js', '.mjs')) or relative == 'boot/shell.qml':
            continue
        path = ui / relative
        for number, line in enumerate(strip(path.read_text()).splitlines(), 1):
            for pattern in (LITERAL, LOAD):
                for match in pattern.finditer(line):
                    raw = match.group(2)
                    if '://' in raw:
                        continue
                    # Relative to the file, the UI root, or a shellDir-prefixed boot entry.
                    found = {str(c.relative_to(ui)) for c in
                             ((base / ('.' + raw if raw.startswith('/') else raw)).resolve()
                              for base in (path.parent, ui, ui / 'boot'))
                             if c.is_relative_to(ui) and c.is_file()}
                    problem = f'{relative}:{number}: {raw} resolves to no closure file ({sorted(found)})'
                    if not found & files and problem not in problems:
                        problems.append(problem)
    return problems
