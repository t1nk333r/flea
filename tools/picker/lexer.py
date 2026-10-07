"""Small dependency lexer, not a QML compiler. Comments never create edges."""
from dataclasses import dataclass
import re


@dataclass(frozen=True)
class Token:
    value: str
    kind: str
    line: int
    column: int


def error(path, token, message):
    raise ValueError(f'{path}:{token.line}:{token.column}: {message}')


def tokens(text, path):
    result = []
    i, line, column = 0, 1, 1
    def advance(s):
        nonlocal line, column
        if '\n' in s:
            line += s.count('\n')
            column = len(s.rsplit('\n', 1)[1]) + 1
        else:
            column += len(s)
    while i < len(text):
        start, ln, col = i, line, column
        ch = text[i]
        if ch.isspace():
            i += 1
        elif text.startswith('//', i):
            end = text.find('\n', i)
            i = len(text) if end < 0 else end
        elif text.startswith('/*', i):
            end = text.find('*/', i + 2)
            if end < 0:
                error(path, Token('', '', ln, col), 'unterminated comment')
            i = end + 2
        elif ch == '/' and (not result or result[-1].value in ('(', '=', ':', ',', '[', '!', '?', '|', '&', ';', '{', 'return')):
            i += 1
            bracket = False
            while i < len(text):
                if text[i] == '\\':
                    i += 2
                    continue
                if text[i] == '[':
                    bracket = True
                elif text[i] == ']':
                    bracket = False
                elif text[i] == '/' and not bracket:
                    i += 1
                    break
                i += 1
            else:
                error(path, Token('', '', ln, col), 'unterminated regular expression')
            while i < len(text) and text[i].isalpha():
                i += 1
            result.append(Token(text[start:i], 'regex', ln, col))
        elif ch in '\"\'`':
            quote = ch
            i += 1
            value = ''
            while i < len(text) and text[i] != quote:
                if text[i] == '\\':
                    i += 1
                    if i >= len(text):
                        break
                    if text[i] in 'xu':
                        count = 2 if text[i] == 'x' else 4
                        raw = text[i + 1:i + 1 + count]
                        try:
                            value += chr(int(raw, 16))
                        except ValueError:
                            error(path, Token('', '', ln, col), 'invalid string escape')
                        i += count + 1
                        continue
                    value += {'n': '\n', 'r': '\r', 't': '\t', '\n': ''}.get(text[i], text[i])
                else:
                    value += text[i]
                i += 1
            if i >= len(text):
                error(path, Token('', '', ln, col), 'unterminated string')
            i += 1
            kind = 'template' if quote == '`' and '${' in value else 'string'
            result.append(Token(value, kind, ln, col))
        elif ch.isalpha() or ch in '_$':
            i += 1
            while i < len(text) and (text[i].isalnum() or text[i] in '_$'):
                i += 1
            result.append(Token(text[start:i], 'identifier', ln, col))
        elif ch.isdigit():
            match = re.match(r'\d+(?:\.\d+)?', text[i:])
            i += len(match[0])
            result.append(Token(match[0], 'number', ln, col))
        else:
            i += 1
            result.append(Token(ch, 'punct', ln, col))
        advance(text[start:i])
    return result
