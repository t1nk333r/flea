#!/usr/bin/env python3
"""Consumer-visible graph regressions in isolated miniature UI trees."""
import json
from pathlib import Path
import re
import shutil
import subprocess
from oracle import unlisted
from sandbox import make

REPO = Path(__file__).resolve().parents[3]
TOOL = REPO / 'tools/flea-picker-closure'
ROOT = make('picker-closure-')


def fixture(name):
    repo = ROOT / name
    ui = repo / 'ui'
    (ui / 'boot').mkdir(parents=True)
    (ui / 'boot/picker.qml').write_text('import QtQuick\nimport ".." as Flea\nItem { Flea.Root {} }\n')
    (ui / 'boot/shell.qml').write_text('import ForbiddenSentinel\n')
    (ui / 'qmldir').write_text('module flea\nRoot 1.0 Root.qml\nsingleton Theme 1.0 Theme.qml\nChild 1.0 Child.qml\nChild 2.0 Child.qml\nUnused 1.0 Unused.qml\n')
    (ui / 'Root.qml').write_text('''import QtQuick
import "."
import "js/a.js" as A
Item {
    property color tint: Theme.color
    Child {}
    Loader { active: false; source: "Deferred.qml" }
    Component.onCompleted: Qt.createComponent("Extra" + ".qml")
    // PreviewPdf {} Loader { source: "Absent.qml" }
    property string comment: "Unused {} and \\\"escaped\\\""
    property string template: `Unused {}`
}
''')
    for name in ['Theme', 'Child', 'Deferred', 'Extra']:
        (ui / (name+'.qml')).write_text('import QtQuick\nItem {}\n')
    (ui / 'Deferred.qml').write_text('import QtQuick\nItem { Image { source: "assets/picture.svg" } }\n')
    (ui / 'assets').mkdir()
    (ui / 'assets/picture.svg').write_text('<svg/>')
    (ui / 'js').mkdir()
    (ui / 'js/a.js').write_text('.import "b.js" as B\nvar text = `PreviewPdf {}`;\n')
    (ui / 'js/b.js').write_text('.import "a.js" as A\n.import "c.mjs" as C\n')
    (ui / 'js/c.mjs').write_text('import {\n x\n} from "d.mjs"\nexport {\n y\n} from "e.mjs"\n')
    (ui / 'js/d.mjs').write_text('export const x = 1;\n')
    (ui / 'js/e.mjs').write_text('export const y = 2;\n')
    for module in ['Commons', 'Ui']:
        directory = ui / 'compat' / module
        directory.mkdir(parents=True)
        (directory / 'qmldir').write_text('module qs.'+module+'\nSupport 1.0 Support.qml\n')
        (directory / 'Support.qml').write_text('import QtQuick\nItem {}\n')
    (ui / 'compat/LICENSE.omarchy').write_text('license fixture\n')
    return repo


def generate(repo, success=True):
    out = repo / 'out'
    result = subprocess.run([str(TOOL), '--repo', str(repo), '--output', str(out)], capture_output=True, text=True)
    if success:
        assert result.returncode == 0, result.stderr
    else:
        assert result.returncode != 0, 'invalid dependency was packaged'
        assert not (out / 'ui-files.txt').exists(), 'partial success manifest'
        assert re.search(r'[^ ]+:\d+:\d+:', result.stderr), result.stderr
    return out, result


try:
    repo = fixture('positive')
    out, _ = generate(repo)
    expected = {'boot/picker.qml', 'boot/shell.qml', 'Root.qml', 'Theme.qml', 'Child.qml',
                'Deferred.qml', 'Extra.qml', 'assets/picture.svg', 'js/a.js', 'js/b.js',
                'js/c.mjs', 'js/d.mjs', 'js/e.mjs', 'compat/LICENSE.omarchy'}
    for module in ['Commons', 'Ui']:
        expected.update({'compat/'+module+'/qmldir', 'compat/'+module+'/Support.qml'})
    assert set((out / 'ui-files.txt').read_text().splitlines()) == expected
    registry = (out / 'qmldir').read_text()
    assert 'Unused' not in registry and 'Child 2.0 Child.qml' in registry
    assert 'component load' in {r['kind'] for r in json.loads((out / 'reasons.json').read_text())['Deferred.qml']}
    first = {p.name: p.read_bytes() for p in out.iterdir()}
    generate(repo)
    assert first == {p.name: p.read_bytes() for p in out.iterdir()}
    # An imported helper follows the graph without any recipe edit.
    (repo / 'ui/js/e.mjs').write_text('import "new.mjs";\nexport const y = 2;\n')
    (repo / 'ui/js/new.mjs').write_text('export const z = 3;\n')
    generate(repo)
    assert 'js/new.mjs' in (out / 'ui-files.txt').read_text().splitlines()
    for name, mutate, needle in [
        ('missing-js', lambda ui: (ui/'js/b.js').unlink(), 'b.js'),
        ('missing-type', lambda ui: (ui/'Child.qml').unlink(), 'Child.qml'),
        ('dynamic', lambda ui: (ui/'Root.qml').write_text('import QtQuick\nItem { Loader { source: choose() } }'), 'unsupported'),
        ('dynamic-assignment', lambda ui: (ui/'Root.qml').write_text('import QtQuick\nItem { Loader { id: lazy; source: "" } Component.onCompleted: lazy.source = choose() }'), 'unsupported'),
        ('escape', lambda ui: (ui/'Root.qml').write_text('import QtQuick\nItem { Loader { source: "../escape.qml" } }'), 'escapes'),
        ('module', lambda ui: (ui/'Root.qml').write_text('import QtMultimedia\nItem {}'), 'QtMultimedia'),
        ('unregistered', lambda ui: (ui/'Root.qml').write_text('import QtQuick\nItem { Mystery {} }'), 'unregistered'),
        ('directive', lambda ui: (ui/'qmldir').write_text('module flea\nplugin hostile\n'), 'qmldir'),
        ('dynamic-import', lambda ui: (ui/'js/a.js').write_text('import(getName());'), 'dynamic'),
    ]:
        repo = fixture(name)
        (repo/'escape.qml').write_text('Item {}')
        mutate(repo/'ui')
        _, result = generate(repo, False)
        assert needle in result.stderr, result.stderr
    # The real UI, read a second way that shares nothing with the generator's tokenizer: every
    # script or component a listed file names must itself be listed, so a file the generator
    # silently drops fails here, and dropping one listed component must be noticed.
    subprocess.run([str(TOOL), '--repo', str(REPO), '--output', str(ROOT/'real')], check=True)
    listed = set((ROOT/'real/ui-files.txt').read_text().splitlines())
    assert not unlisted(REPO/'ui', listed), unlisted(REPO/'ui', listed)
    assert not unlisted(ROOT/'positive/ui', set((ROOT/'positive/out/ui-files.txt').read_text().splitlines()))
    for dropped in ['ShareBrowser.qml', 'PowerSectorsReader.qml', 'js/AnchorHold.js']:
        assert any(dropped in p for p in unlisted(REPO/'ui', listed - {dropped})), dropped
    print('picker closure: PASS graph, cycles, versions, deferred loads, assets, nine fail-closed cases and the regex oracle')
finally:
    shutil.rmtree(ROOT)
