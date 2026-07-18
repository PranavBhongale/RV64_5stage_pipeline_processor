"""
lexer.py  —  C Lexer for the RV64IM compiler
=============================================
Produces a flat list of Token objects from a C source string.
"""

import re
from dataclasses import dataclass
from typing import List, Optional


# ─── Token kinds ──────────────────────────────────────────────────────────────

TK_INT_LIT   = "INT_LIT"
TK_CHAR_LIT  = "CHAR_LIT"
TK_STR_LIT   = "STR_LIT"
TK_IDENT     = "IDENT"
TK_KEYWORD   = "KEYWORD"
TK_OP        = "OP"
TK_PUNCT     = "PUNCT"
TK_EOF       = "EOF"

KEYWORDS = {
    "int", "long", "char", "void", "short", "unsigned", "signed",
    "return", "if", "else", "while", "for", "do",
    "break", "continue",
    "struct",               # parsed but not fully supported
    "const", "static", "extern",
    "sizeof",
}

# Operators (longest-match first)
OPERATORS = [
    "<<=", ">>=",
    "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=",
    "==", "!=", "<=", ">=", "&&", "||",
    "<<", ">>", "++", "--", "->",
    "+", "-", "*", "/", "%",
    "&", "|", "^", "~", "!",
    "<", ">", "=", "?", ":",
]

PUNCTUATION = set("(){},;[].")


@dataclass
class Token:
    kind  : str
    value : object       # str for most; int for INT_LIT
    line  : int
    col   : int

    def __repr__(self):
        return f"Token({self.kind}, {self.value!r}, L{self.line}:C{self.col})"


# ─── Lexer ────────────────────────────────────────────────────────────────────

class Lexer:
    def __init__(self, source: str, filename: str = "<stdin>"):
        self.src      = source
        self.filename = filename
        self.pos      = 0
        self.line     = 1
        self.col      = 1
        self.tokens: List[Token] = []

    # ── helpers ───────────────────────────────────────────────────

    def _here(self):
        return self.line, self.col

    def _advance(self, n=1):
        for _ in range(n):
            if self.pos < len(self.src):
                if self.src[self.pos] == "\n":
                    self.line += 1
                    self.col   = 1
                else:
                    self.col += 1
                self.pos += 1

    def _peek(self, ahead=0):
        p = self.pos + ahead
        return self.src[p] if p < len(self.src) else "\0"

    def _rest(self):
        return self.src[self.pos:]

    def _error(self, msg, line=None, col=None):
        l = line or self.line
        c = col  or self.col
        raise SyntaxError(f"{self.filename}:{l}:{c}: {msg}")

    # ── skip whitespace & comments ────────────────────────────────

    def _skip(self):
        while self.pos < len(self.src):
            ch = self._peek()
            # whitespace
            if ch in " \t\r\n":
                self._advance()
            # line comment
            elif ch == "/" and self._peek(1) == "/":
                while self.pos < len(self.src) and self._peek() != "\n":
                    self._advance()
            # block comment
            elif ch == "/" and self._peek(1) == "*":
                self._advance(2)
                while self.pos < len(self.src):
                    if self._peek() == "*" and self._peek(1) == "/":
                        self._advance(2)
                        break
                    self._advance()
            else:
                break

    # ── individual token readers ──────────────────────────────────

    def _read_int(self):
        line, col = self._here()
        start = self.pos
        # hex
        if self._peek() == "0" and self._peek(1) in "xX":
            self._advance(2)
            while re.match(r"[0-9a-fA-F]", self._peek()):
                self._advance()
            value = int(self.src[start:self.pos], 16)
        # octal
        elif self._peek() == "0" and self._peek(1).isdigit():
            while self._peek().isdigit():
                self._advance()
            value = int(self.src[start:self.pos], 8)
        # decimal
        else:
            while self._peek().isdigit():
                self._advance()
            value = int(self.src[start:self.pos])
        # optional suffix (u, l, ll, ul …)
        while self._peek().lower() in "ul":
            self._advance()
        return Token(TK_INT_LIT, value, line, col)

    def _read_char(self):
        line, col = self._here()
        self._advance()   # skip '
        ch = self._read_escape()
        if self._peek() != "'":
            self._error("unterminated char literal")
        self._advance()
        return Token(TK_INT_LIT, ord(ch) if isinstance(ch, str) else ch, line, col)

    def _read_escape(self):
        if self._peek() == "\\":
            self._advance()
            c = self._peek(); self._advance()
            return {"n":"\n","t":"\t","r":"\r","0":"\0",
                    "\\":"\\"," ":"'",'"':'"'}.get(c, c)
        c = self._peek(); self._advance()
        return c

    def _read_string(self):
        line, col = self._here()
        self._advance()   # skip "
        chars = []
        while self.pos < len(self.src) and self._peek() != '"':
            chars.append(self._read_escape())
        if self._peek() != '"':
            self._error("unterminated string literal")
        self._advance()
        return Token(TK_STR_LIT, "".join(chars), line, col)

    def _read_ident(self):
        line, col = self._here()
        start = self.pos
        while re.match(r"[A-Za-z0-9_]", self._peek()):
            self._advance()
        word = self.src[start:self.pos]
        kind = TK_KEYWORD if word in KEYWORDS else TK_IDENT
        return Token(kind, word, line, col)

    def _read_op(self):
        line, col = self._here()
        rest = self._rest()
        for op in OPERATORS:
            if rest.startswith(op):
                self._advance(len(op))
                return Token(TK_OP, op, line, col)
        self._error(f"unknown character: {self._peek()!r}")

    def _read_preproc(self):
        """Skip preprocessor directives (#include, #define simple constants)."""
        while self.pos < len(self.src) and self._peek() != "\n":
            self._advance()

    # ── main tokenize loop ────────────────────────────────────────

    def tokenize(self) -> List[Token]:
        while True:
            self._skip()
            if self.pos >= len(self.src):
                break
            ch = self._peek()

            # preprocessor — skip entirely
            if ch == "#":
                self._advance()
                self._read_preproc()
                continue

            if ch.isdigit():
                self.tokens.append(self._read_int())
            elif ch == "'" :
                self.tokens.append(self._read_char())
            elif ch == '"' :
                self.tokens.append(self._read_string())
            elif re.match(r"[A-Za-z_]", ch):
                self.tokens.append(self._read_ident())
            elif ch in PUNCTUATION:
                line, col = self._here()
                self._advance()
                self.tokens.append(Token(TK_PUNCT, ch, line, col))
            else:
                self.tokens.append(self._read_op())

        self.tokens.append(Token(TK_EOF, None, self.line, self.col))
        return self.tokens
