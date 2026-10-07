"""Registry and the deliberately bounded component URL expression grammar."""
from pathlib import Path
from urllib.parse import unquote, urlsplit
from picker.lexer import Token, error

MODULES = {'QtQuick', 'QtQuick.Layouts', 'QtQuick.Shapes', 'QtQml',
           'QtQml.Models', 'QtQml.XmlListModel', 'Quickshell', 'Quickshell.Io',
           'qs.Commons', 'qs.Ui'}
# These module types are checked by the installed engine, not resolved as UI files.
EXTERNAL_TYPES = set('''ShellRoot Singleton LazyLoader FloatingWindow PanelWindow Scope
Process SplitParser StdioCollector FileView JsonAdapter IpcHandler Timer QtObject
Item FocusScope Rectangle Text TextInput TextEdit Image MouseArea Flickable ListView GridView
Repeater Component Loader Connections Binding FrameAnimation NumberAnimation ColorAnimation
PropertyAnimation PropertyAction ScriptAction PauseAnimation SmoothedAnimation SpringAnimation SequentialAnimation ParallelAnimation Behavior Transition
State PropertyChanges AnchorChanges ParentChange Rotation Scale Translate
ShaderEffect ShaderEffectSource Canvas FontLoader TextMetrics FontMetrics
TapHandler HoverHandler WheelHandler DragHandler PointHandler PinchHandler
ScrollBar Row Column Grid Flow RowLayout ColumnLayout GridLayout Shape ShapePath
Path PathSvg PathLine PathArc PathMove PathCurve PathQuad PathCubic PathAngleArc
PathPolyline PathMultiline PathRectangle PathText Gradient GradientStop
Window XmlListModel XmlListModelRole ListModel ListElement DelegateModel
Instantiator BoundComponent'''.split())


def registry(ui, directory):
    path = directory / 'qmldir'
    records, header = [], []
    if not path.is_file():
        return header, records
    names = {}
    for line, raw in enumerate(path.read_text().splitlines(), 1):
        words = raw.split('#', 1)[0].split()
        if not words:
            continue
        token = Token(raw, '', line, 1)
        if words[0] == 'module' and len(words) == 2:
            header.append(raw)
            continue
        singleton = words[0] == 'singleton'
        record = words[1:] if singleton else words
        if len(record) not in (2, 3) or not record[-1].endswith('.qml'):
            error(path.relative_to(ui), token, 'unsupported qmldir directive')
        name, filename = record[0], record[-1]
        version = record[1] if len(record) == 3 else ''
        key = (name, version)
        if key in names and names[key] != (filename, singleton):
            error(path.relative_to(ui), token, 'conflicting qmldir declaration')
        names[key] = (filename, singleton)
        records.append((name, directory / filename, raw, token))
    return header, records


def local_path(ui, referring, raw, token):
    parsed = urlsplit(raw)
    if parsed.scheme and parsed.scheme != 'file':
        error(referring.relative_to(ui), token, 'unsupported packaged URL scheme')
    if parsed.netloc:
        error(referring.relative_to(ui), token, 'nonlocal packaged URL')
    # Relative paths may contain literal #/?; encoded file URLs use URL semantics.
    value = unquote(parsed.path if parsed.scheme else raw)
    candidate = Path(value) if value.startswith('/') else referring.parent / value
    candidate = candidate.resolve()
    if not candidate.is_relative_to(ui):
        error(referring.relative_to(ui), token, 'dependency escapes UI')
    if not candidate.exists():
        error(referring.relative_to(ui), token, f'unresolved local dependency: {raw}')
    return candidate


def static_url(expr, referring, ui):
    """Strings/concatenations, resolvedUrl, and escaped shellDir file URLs only."""
    while len(expr) >= 2 and expr[0].value == '(' and expr[-1].value == ')':
        expr = expr[1:-1]
    if not expr:
        return None
    if len(expr) == 1 and expr[0].kind == 'string':
        return expr[0].value
    if expr[0].value == 'Qt' and [t.value for t in expr[1:4]] == ['.', 'resolvedUrl', '('] and expr[-1].value == ')':
        return static_url(expr[4:-1], referring, ui)
    # A plain literal concatenation is useful for static assets too.
    if all(t.kind == 'string' if i % 2 == 0 else t.value == '+' for i, t in enumerate(expr)):
        return ''.join(t.value for t in expr[::2])
    values = [t.value for t in expr]
    prefix = ['file://', '+', 'encodeURI', '(', 'Quickshell', '.', 'shellDir', '+']
    if values[:8] == prefix and len(expr) >= 10 and expr[8].kind == 'string' and values[9] == ')':
        # Only these two URL escaping calls may follow encodeURI.
        suffix = values[10:]
        allowed = ['.', 'replace', '(', '/#/g', ',', '%23', ')',
                   '.', 'replace', '(', '/\\?/g', ',', '%3F', ')']
        if not suffix or suffix == allowed or suffix == allowed[:7]:
            root = ui / 'boot'
            return str(root) + expr[8].value
    return None


def expression(ts, start):
    """Read one QML binding/call argument with balanced delimiters."""
    out, depth = [], []
    pairs = {')': '(', ']': '[', '}': '{'}
    line = ts[start].line if start < len(ts) else 0
    for token in ts[start:]:
        value = token.value
        if not depth and (value in (';', ',', '}') or token.line > line):
            break
        if value in ('(', '[', '{'):
            depth.append(value)
        elif value in pairs:
            if not depth:
                break
            if depth[-1] != pairs[value]:
                break
            depth.pop()
        out.append(token)
    return out
