"""Compute the picker graph; installation exceptions are recorded, not traversed."""
import json
from pathlib import Path
from picker.lexer import tokens, error, Token
from picker.resolver import (MODULES, EXTERNAL_TYPES, registry, local_path,
                             static_url, expression)


class Closure:
    def __init__(self, repo):
        self.ui = (Path(repo) / 'ui').resolve()
        self.files = set()
        self.reasons = {}
        self.modules = set()
        self.registries = {}

    def records(self, directory):
        if directory not in self.registries:
            self.registries[directory] = registry(self.ui, directory)
        return self.registries[directory][1]

    def add(self, path, source, token, kind, traverse=True):
        path = path.resolve()
        if not path.is_relative_to(self.ui):
            error(source.relative_to(self.ui), token, 'dependency escapes UI')
        relative = str(path.relative_to(self.ui))
        reason = {'source': str(source.relative_to(self.ui)), 'line': token.line,
                  'column': token.column, 'kind': kind}
        if reason not in self.reasons.setdefault(relative, []):
            self.reasons[relative].append(reason)
        if not path.is_file():
            error(source.relative_to(self.ui), token, f'unresolved local dependency: {relative}')
        if relative in self.files:
            return
        self.files.add(relative)
        if traverse and path.suffix in ('.qml', '.js', '.mjs'):
            self.walk(path)

    def resolve(self, path, raw, token, kind):
        self.add(local_path(self.ui, path, raw, token), path, token, kind)

    def external(self, path, name, token):
        if name not in MODULES:
            error(path.relative_to(self.ui), token, f'review dependency mapping for external module {name}')
        self.modules.add(name)
        if name in ('qs.Commons', 'qs.Ui'):
            directory = self.ui / 'compat' / name.split('.')[1]
            for support in sorted(directory.iterdir()):
                self.add(support, path, token, 'complete compat module')

    def walk(self, path):
        ts = tokens(path.read_text(), path.relative_to(self.ui))
        qml = path.suffix == '.qml'
        directories = {'': path.parent} if qml else {}
        external_aliases = set()
        ignored = set()
        # Imports end at a newline or semicolon. Static JS imports/reexports
        # may span lines, ending at their source string and optional semicolon.
        for i, token in enumerate(ts):
            if token.value not in ('import', 'export'):
                continue
            if i and ts[i-1].value == '.' and (i < 2 or ts[i-2].line == token.line):
                # QML JS .import is the only supported dotted import statement.
                if not (i == 1 or ts[i-2].line < token.line):
                    error(path.relative_to(self.ui), token, 'unsupported dynamic import')
            end = i + 1
            if not qml and not (i and ts[i-1].value == '.'):
                while end < len(ts) and ts[end].value not in (';', 'import', 'export'):
                    if ts[end].kind == 'string' and (end == i+1 or ts[end-1].value == 'from'):
                        end += 1
                        break
                    end += 1
                if token.value == 'export' and not any(t.value == 'from' for t in ts[i+1:end]):
                    continue
            else:
                while end < len(ts) and ts[end].line == token.line and ts[end].value != ';':
                    end += 1
            body = ts[i+1:end]
            ignored.update(range(i, end))
            if not body:
                error(path.relative_to(self.ui), token, 'unsupported import syntax')
            if body[0].value == '(':
                error(path.relative_to(self.ui), token, 'unsupported dynamic import')
            if qml or (i and ts[i-1].value == '.'):
                target = body[0]
                alias = None
                for n, item in enumerate(body[:-1]):
                    if item.value == 'as':
                        alias = body[n+1].value
                if target.kind == 'string':
                    local = local_path(self.ui, path, target.value, target)
                    if local.is_dir():
                        directories[alias or ''] = local
                        self.records(local)
                    else:
                        self.add(local, path, target, 'script import')
                else:
                    name = ''
                    for item in body:
                        if item.kind == 'number' or item.value == 'as':
                            break
                        name += item.value
                    self.external(path, name, target)
                    if alias:
                        external_aliases.add(alias)
            else:
                # import "x"; import ... from "x"; export ... from "x".
                strings = [t for t in body if t.kind == 'string']
                if not strings:
                    # Multiline named imports have exactly one source after from.
                    j = end
                    while j < len(ts) and ts[j].value not in (';', 'import', 'export'):
                        if ts[j].value == 'from' and j + 1 < len(ts):
                            strings = [ts[j+1]]
                            break
                        j += 1
                if len(strings) != 1 or strings[0].kind != 'string':
                    error(path.relative_to(self.ui), token, 'unsupported ES module dependency')
                self.resolve(path, strings[0].value, strings[0], 'ES module import')
        if qml:
            self.types(path, ts, directories, external_aliases, ignored)
        self.resources(path, ts, qml)

    def types(self, path, ts, directories, external_aliases, ignored):
        inline = {ts[i+1].value for i, t in enumerate(ts[:-1]) if t.value == 'component'}
        for i, token in enumerate(ts):
            if i in ignored or token.kind != 'identifier':
                continue
            qualifier = ts[i-2].value if i >= 2 and ts[i-1].value == '.' else ''
            directory = directories.get(qualifier)
            found = False
            if directory is not None:
                for name, target, raw, where in self.records(directory):
                    if token.value == name:
                        self.add(target, path, token, 'registered type')
                        found = True
            # Unknown uppercase object constructors must not become implicit lookup.
            if not found and i+1 < len(ts) and ts[i+1].value == '{' and token.value[:1].isupper():
                if qualifier in external_aliases or token.value in EXTERNAL_TYPES or token.value in inline:
                    continue
                # Compat module types are resolved by the declared module registry.
                compat = any(token.value == rec[0] for name in ('Commons', 'Ui')
                             for rec in self.records(self.ui / 'compat' / name))
                if not compat:
                    error(path.relative_to(self.ui), token, f'unregistered local object type {token.value}')

    def resources(self, path, ts, qml):
        # Track each QML object's type through braces to distinguish component
        # Loader sources from dynamic Image/FileView user inputs.
        stack = []
        loader_ids = set()
        scan_stack = []
        for i, token in enumerate(ts):
            if token.value == '{':
                scan_stack.append(ts[i-1].value if i else '')
            elif token.value == '}' and scan_stack:
                scan_stack.pop()
            elif token.value == 'id' and i+2 < len(ts) and ts[i+1].value == ':':
                if scan_stack and scan_stack[-1] in ('Loader', 'LazyLoader'):
                    loader_ids.add(ts[i+2].value)
        for i, token in enumerate(ts):
            value = token.value
            if value == '{':
                previous = ts[i-1].value if i else ''
                stack.append(previous if previous[:1].isupper() else None)
            elif value == '}':
                if stack:
                    stack.pop()
            component_source = value == 'source' and i+1 < len(ts) and ts[i+1].value in (':', '=')
            owner = next((name for name in reversed(stack) if name), '')
            call = value in ('setSource', 'resolvedUrl', 'createComponent') and i+1 < len(ts) and ts[i+1].value == '('
            if call or component_source:
                expr = expression(ts, i+2)
                raw = static_url(expr, path, self.ui)
                assigned_loader = i >= 2 and ts[i-1].value == '.' and ts[i-2].value in loader_ids
                required = call or owner in ('Loader', 'LazyLoader') or assigned_loader
                if raw:
                    if required or raw.endswith(('.qml', '.js', '.mjs', '.svg', '.png', '.jpg', '.webp', '.ttf', '.otf')):
                        self.resolve(path, raw, token, 'component load' if required else 'static asset')
                elif raw is None and required:
                    # Assignment through a Loader id is also handled by the
                    # resolvedUrl call; a dynamic source binding is never accepted.
                    error(path.relative_to(self.ui), token, 'unsupported dependency-bearing component expression')
            # Literal packaged resources outside source bindings (e.g. icon URL).
            if token.kind == 'string' and token.value.endswith(('.svg', '.png', '.jpg', '.webp', '.ttf', '.otf')):
                if not token.value.startswith(('http:', 'https:', 'data:', 'image:')):
                    self.resolve(path, token.value, token, 'static asset')

    def generate(self, output):
        root = self.ui / 'boot/picker.qml'
        self.add(root, root, Token('', '', 1, 1), 'picker entry')
        support = Token('', '', 1, 1)
        # Both alternatives must exist even if this particular graph imports only Commons.
        for name in ('qs.Commons', 'qs.Ui'):
            self.external(root, name, support)
        self.add(self.ui / 'compat/LICENSE.omarchy', root, support, 'compat license', False)
        self.add(self.ui / 'boot/shell.qml', root, support, 'discovery sentinel; not traversed', False)
        header, records = registry(self.ui, self.ui)
        retained = [raw for name, target, raw, token in records if str(target.relative_to(self.ui)) in self.files]
        self.reasons['qmldir'] = [{'kind': 'generated pruned registry'}]
        self.reasons['boot-compat/picker.qml'] = [{'kind': 'compat entry link'}]
        self.reasons['picker-only'] = [{'kind': 'installed profile marker outside UI'}]
        self.reasons['@package/usr/share/licenses/flea-picker/LICENSE'] = [
            {'source': 'LICENSE', 'kind': 'explicit package license outside UI'}]
        for notice in sorted((self.ui / 'vendor/LICENSES').glob('*')):
            self.reasons[str(notice.relative_to(self.ui))] = [
                {'source': str(notice.relative_to(self.ui)), 'kind': 'explicit vendor legal notice'}]
        output = Path(output)
        output.mkdir(parents=True, exist_ok=True)
        (output / 'ui-files.txt').write_text(''.join(p+'\n' for p in sorted(self.files)))
        (output / 'qmldir').write_text('\n'.join(header + retained)+'\n')
        (output / 'modules.txt').write_text(''.join(m+'\n' for m in sorted(self.modules)))
        (output / 'reasons.json').write_text(json.dumps(self.reasons, sort_keys=True, indent=2)+'\n')
