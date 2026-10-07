"""Generate a test-only compile probe from the same closure graph implementation."""
from pathlib import Path
import json
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from picker.closure import Closure
from picker.lexer import Token
from picker.resolver import registry


def generate(ui, directory):
    graph = Closure(ui.parent)
    root = ui / 'boot/picker.qml'
    token = Token('', '', 1, 1)
    graph.add(root, root, token, 'picker entry')
    for name in ('qs.Commons', 'qs.Ui'):
        graph.external(root, name, token)
    # The runtime graph is the generator's output, not a second component list.
    files = sorted(p for p in graph.files if p.endswith('.qml'))
    lines = ['import Quickshell', 'import Quickshell.Io', 'import QtQuick']
    for alias, path in [('Flea', ui), ('Commons', ui/'compat/Commons'), ('Ui', ui/'compat/Ui')]:
        lines.append('import '+json.dumps(path.as_uri())+' as '+alias)
    lines += ['ShellRoot {', '    id: root', '    property bool done: false']
    count = 0
    for alias, path in [('Flea', ui), ('Commons', ui/'compat/Commons'), ('Ui', ui/'compat/Ui')]:
        _, records = registry(ui, path)
        for name, target, raw, token in records:
            if raw.startswith('singleton ') and str(target.relative_to(ui)) in graph.files:
                lines.append(f'    property var singleton{count}: {alias}.{name}')
                count += 1
    lines += ['    Component.onCompleted: {', '        var files = '+json.dumps([(ui/p).as_uri() for p in files])]
    lines += ['        for (var i = 0; i < files.length; i++) {',
              '            var component = Qt.createComponent(files[i], Component.PreferSynchronous)',
              '            if (component.status !== Component.Ready) {',
              '                console.error("PICKER_PROBE_FAILED " + files[i] + " " + component.errorString())',
              '                return', '            }', '        }',
              f'        console.log("PICKER_PROBE_READY {len(files)} components {count} singletons")',
              '        root.done = true', '    }',
              '    IpcHandler { target: "pickerprobe"; function ready(): bool { return root.done } }', '}']
    (directory/'probe.qml').write_text('\n'.join(lines)+'\n')
    for module in ['Commons', 'Ui']:
        (directory/module).symlink_to(ui/'compat'/module, target_is_directory=True)
    return len(files), count
