"""
parser.py  —  Recursive-descent C parser
==========================================
Parses the token stream from lexer.py into an AST (ast_nodes.py).
"""

from lexer import (Token, TK_INT_LIT, TK_CHAR_LIT, TK_STR_LIT,
                   TK_IDENT, TK_KEYWORD, TK_OP, TK_PUNCT, TK_EOF)
from ast_nodes import *
from typing import List, Optional


class Parser:
    def __init__(self, tokens: List[Token], source: str = ""):
        self.tokens  = tokens
        self.pos     = 0
        self.source  = source

    # ── token utilities ───────────────────────────────────────────

    def _cur(self) -> Token:
        return self.tokens[self.pos]

    def _peek(self, ahead=1) -> Token:
        p = self.pos + ahead
        return self.tokens[p] if p < len(self.tokens) else self.tokens[-1]

    def _advance(self) -> Token:
        tok = self.tokens[self.pos]
        if self.pos < len(self.tokens) - 1:
            self.pos += 1
        return tok

    def _expect_punct(self, ch):
        tok = self._cur()
        if tok.kind != TK_PUNCT or tok.value != ch:
            self._error(f"expected '{ch}', got {tok.value!r}", tok)
        return self._advance()

    def _expect_op(self, op):
        tok = self._cur()
        if tok.kind != TK_OP or tok.value != op:
            self._error(f"expected operator '{op}', got {tok.value!r}", tok)
        return self._advance()

    def _match_punct(self, *chs) -> bool:
        return self._cur().kind == TK_PUNCT and self._cur().value in chs

    def _match_op(self, *ops) -> bool:
        return self._cur().kind == TK_OP and self._cur().value in ops

    def _match_keyword(self, *kws) -> bool:
        return self._cur().kind == TK_KEYWORD and self._cur().value in kws

    def _match_ident(self) -> bool:
        return self._cur().kind == TK_IDENT

    def _error(self, msg, tok=None):
        t = tok or self._cur()
        raise SyntaxError(f"line {t.line}: {msg} (got {t.value!r})")

    # ── type parsing ──────────────────────────────────────────────

    TYPE_BASES = {"int", "long", "char", "void", "short",
                  "unsigned", "signed"}

    def _is_type_start(self) -> bool:
        t = self._cur()
        return (t.kind == TK_KEYWORD and t.value in self.TYPE_BASES) or \
               (t.kind == TK_KEYWORD and t.value in ("const", "static", "extern"))

    def _parse_base_type(self) -> str:
        """Consume type qualifiers/specifiers, return canonical base."""
        parts = []
        while self._cur().kind == TK_KEYWORD and \
              self._cur().value in (*self.TYPE_BASES, "const", "static", "extern"):
            parts.append(self._advance().value)
        # Map combinations → canonical
        clean = [p for p in parts if p not in ("const", "static", "extern")]
        if "void" in clean:           return "void"
        if "char" in clean:           return "char"
        if "short" in clean:          return "short"
        if "long" in clean:           return "long"
        return "int"

    def _parse_type(self) -> CType:
        """Parse a full type, including pointer stars."""
        base  = self._parse_base_type()
        depth = 0
        while self._match_op("*"):
            self._advance()
            depth += 1
        return CType(base, depth)

    def _parse_declarator(self, base_type: CType):
        """
        Parse:   [*] name [array-dims]
        Returns: (CType, name)
        """
        depth = 0
        while self._match_op("*"):
            self._advance()
            depth += 1

        if self._cur().kind not in (TK_IDENT, TK_KEYWORD):
            self._error("expected identifier in declarator")
        name = self._advance().value

        ctype = CType(base_type.base, base_type.ptr_depth + depth)

        # array dimensions
        while self._match_punct("["):
            self._advance()
            if self._match_punct("]"):
                size = None
                self._advance()
            else:
                size = self._parse_expr()
                if isinstance(size, IntLit):
                    size = size.value
                else:
                    size = None        # dynamic – treat as pointer
                self._expect_punct("]")
            ctype = CType(ctype.base, ctype.ptr_depth, is_array=True, arr_size=size)

        return ctype, name

    # ── top-level parsing ─────────────────────────────────────────

    def parse(self) -> TranslationUnit:
        decls = []
        while self._cur().kind != TK_EOF:
            decls.append(self._parse_top_level())
        return TranslationUnit(decls)

    def _parse_top_level(self):
        line = self._cur().line

        # Skip lone semicolons
        if self._match_punct(";"):
            self._advance()
            return Block([])

        if not self._is_type_start():
            self._error("expected type at top level")

        base = self._parse_base_type()
        # collect leading pointer stars into base_type
        stars = 0
        while self._match_op("*"):
            self._advance(); stars += 1
        base_type = CType(base, stars)

        name = self._cur().value
        self._advance()

        # array declarator?
        arr_type = base_type
        while self._match_punct("["):
            self._advance()
            if self._match_punct("]"):
                size = None; self._advance()
            else:
                sz_expr = self._parse_expr()
                size = sz_expr.value if isinstance(sz_expr, IntLit) else None
                self._expect_punct("]")
            arr_type = CType(arr_type.base, arr_type.ptr_depth,
                             is_array=True, arr_size=size)

        # function declaration / definition
        if self._match_punct("("):
            params = self._parse_param_list()
            if self._match_punct(";"):
                self._advance()
                body = None
            else:
                body = self._parse_block()
            return FuncDecl(base_type, name, params, body, line)

        # global variable
        init = None
        if self._match_op("="):
            self._advance()
            if self._match_punct("{"):
                init = self._parse_init_list()
            else:
                init = self._parse_assign_expr()

        self._expect_punct(";")
        return GlobalVarDecl(arr_type, name, init, line)

    def _parse_param_list(self) -> List[Param]:
        self._expect_punct("(")
        params = []
        if self._match_punct(")"):
            self._advance()
            return params
        # (void) means no params
        if self._match_keyword("void") and self._peek().value == ")":
            self._advance(); self._advance()
            return params
        while True:
            if not self._is_type_start():
                self._error("expected type in parameter list")
            base_type = self._parse_type()
            ctype, pname = self._parse_declarator(base_type)
            params.append(Param(ctype, pname))
            if self._match_punct(","):
                self._advance()
            else:
                break
        self._expect_punct(")")
        return params

    # ── statement parsing ─────────────────────────────────────────

    def _parse_block(self) -> Block:
        self._expect_punct("{")
        stmts = []
        while not self._match_punct("}"):
            if self._cur().kind == TK_EOF:
                self._error("unexpected EOF in block")
            stmts.append(self._parse_stmt())
        self._advance()   # consume '}'
        return Block(stmts)

    def _parse_stmt(self):
        tok = self._cur()

        # ── block ──
        if tok.kind == TK_PUNCT and tok.value == "{":
            return self._parse_block()

        # ── if ──
        if tok.kind == TK_KEYWORD and tok.value == "if":
            return self._parse_if()

        # ── while ──
        if tok.kind == TK_KEYWORD and tok.value == "while":
            return self._parse_while()

        # ── do-while ──
        if tok.kind == TK_KEYWORD and tok.value == "do":
            return self._parse_do_while()

        # ── for ──
        if tok.kind == TK_KEYWORD and tok.value == "for":
            return self._parse_for()

        # ── return ──
        if tok.kind == TK_KEYWORD and tok.value == "return":
            return self._parse_return()

        # ── break / continue ──
        if tok.kind == TK_KEYWORD and tok.value == "break":
            self._advance(); self._expect_punct(";")
            return BreakStmt(tok.line)
        if tok.kind == TK_KEYWORD and tok.value == "continue":
            self._advance(); self._expect_punct(";")
            return ContinueStmt(tok.line)

        # ── local variable declaration ──
        if self._is_type_start():
            return self._parse_local_decl()

        # ── expression statement ──
        if self._match_punct(";"):
            self._advance()
            return Block([])        # empty statement
        expr = self._parse_expr()
        self._expect_punct(";")
        return ExprStmt(expr)

    def _parse_if(self) -> IfStmt:
        line = self._cur().line
        self._advance()   # 'if'
        self._expect_punct("(")
        cond = self._parse_expr()
        self._expect_punct(")")
        then = self._parse_stmt()
        else_ = None
        if self._match_keyword("else"):
            self._advance()
            else_ = self._parse_stmt()
        return IfStmt(cond, then, else_, line)

    def _parse_while(self) -> WhileStmt:
        line = self._cur().line
        self._advance()   # 'while'
        self._expect_punct("(")
        cond = self._parse_expr()
        self._expect_punct(")")
        body = self._parse_stmt()
        return WhileStmt(cond, body, line)

    def _parse_do_while(self) -> DoWhileStmt:
        line = self._cur().line
        self._advance()   # 'do'
        body = self._parse_stmt()
        self._expect_punct  # 'while' keyword consumed below
        if not (self._cur().kind == TK_KEYWORD and self._cur().value == "while"):
            self._error("expected 'while' after do body")
        self._advance()
        self._expect_punct("(")
        cond = self._parse_expr()
        self._expect_punct(")")
        self._expect_punct(";")
        return DoWhileStmt(body, cond, line)

    def _parse_for(self) -> ForStmt:
        line = self._cur().line
        self._advance()   # 'for'
        self._expect_punct("(")

        # init
        if self._match_punct(";"):
            init = None; self._advance()
        elif self._is_type_start():
            init = self._parse_local_decl()   # consumes its own ';'
        else:
            init = ExprStmt(self._parse_expr())
            self._expect_punct(";")

        # condition
        if self._match_punct(";"):
            cond = None; self._advance()
        else:
            cond = self._parse_expr()
            self._expect_punct(";")

        # step
        if self._match_punct(")"):
            step = None
        else:
            step = self._parse_expr()

        self._expect_punct(")")
        body = self._parse_stmt()
        return ForStmt(init, cond, step, body, line)

    def _parse_return(self) -> ReturnStmt:
        line = self._cur().line
        self._advance()   # 'return'
        if self._match_punct(";"):
            self._advance()
            return ReturnStmt(None, line)
        val = self._parse_expr()
        self._expect_punct(";")
        return ReturnStmt(val, line)

    def _parse_local_decl(self) -> VarDecl:
        line = self._cur().line
        base_type = self._parse_type()
        ctype, name = self._parse_declarator(base_type)
        init = None
        if self._match_op("="):
            self._advance()
            if self._match_punct("{"):
                init = self._parse_init_list()
            else:
                init = self._parse_assign_expr()
        self._expect_punct(";")
        return VarDecl(ctype, name, init, line)

    def _parse_init_list(self):
        """{ expr, expr, ... }"""
        self._expect_punct("{")
        items = []
        while not self._match_punct("}"):
            items.append(self._parse_assign_expr())
            if self._match_punct(","):
                self._advance()
        self._advance()  # '}'
        return items

    # ── expression parsing (precedence climbing) ──────────────────
    # Priority table (highest number = tightest binding)

    ASSIGN_OPS = {"=", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "<<=", ">>="}

    def _parse_expr(self):
        """Full expression including comma (we skip comma-expr for simplicity)."""
        return self._parse_assign_expr()

    def _parse_assign_expr(self):
        left = self._parse_ternary()
        if self._cur().kind == TK_OP and self._cur().value in self.ASSIGN_OPS:
            op   = self._advance().value
            right = self._parse_assign_expr()   # right-associative
            return Assign(op, left, right, left.line if hasattr(left,"line") else 0)
        return left

    def _parse_ternary(self):
        cond = self._parse_logor()
        if self._match_op("?"):
            self._advance()
            then = self._parse_expr()
            self._expect_op(":")
            else_ = self._parse_ternary()
            return Ternary(cond, then, else_,
                           cond.line if hasattr(cond,"line") else 0)
        return cond

    def _parse_logor(self):
        left = self._parse_logand()
        while self._match_op("||"):
            op = self._advance().value
            right = self._parse_logand()
            left = BinOp(op, left, right)
        return left

    def _parse_logand(self):
        left = self._parse_bitor()
        while self._match_op("&&"):
            op = self._advance().value
            right = self._parse_bitor()
            left = BinOp(op, left, right)
        return left

    def _parse_bitor(self):
        left = self._parse_bitxor()
        while self._match_op("|"):
            op = self._advance().value
            right = self._parse_bitxor()
            left = BinOp(op, left, right)
        return left

    def _parse_bitxor(self):
        left = self._parse_bitand()
        while self._match_op("^"):
            op = self._advance().value
            right = self._parse_bitand()
            left = BinOp(op, left, right)
        return left

    def _parse_bitand(self):
        left = self._parse_equality()
        while self._match_op("&"):
            # distinguish from unary &: binary & only inside expression
            op = self._advance().value
            right = self._parse_equality()
            left = BinOp(op, left, right)
        return left

    def _parse_equality(self):
        left = self._parse_relational()
        while self._match_op("==", "!="):
            op = self._advance().value
            right = self._parse_relational()
            left = BinOp(op, left, right)
        return left

    def _parse_relational(self):
        left = self._parse_shift()
        while self._match_op("<", ">", "<=", ">="):
            op = self._advance().value
            right = self._parse_shift()
            left = BinOp(op, left, right)
        return left

    def _parse_shift(self):
        left = self._parse_additive()
        while self._match_op("<<", ">>"):
            op = self._advance().value
            right = self._parse_additive()
            left = BinOp(op, left, right)
        return left

    def _parse_additive(self):
        left = self._parse_multiplicative()
        while self._match_op("+", "-"):
            op = self._advance().value
            right = self._parse_multiplicative()
            left = BinOp(op, left, right)
        return left

    def _parse_multiplicative(self):
        left = self._parse_unary()
        while self._match_op("*", "/", "%"):
            op = self._advance().value
            right = self._parse_unary()
            left = BinOp(op, left, right)
        return left

    def _parse_unary(self):
        tok = self._cur()
        # unary -
        if tok.kind == TK_OP and tok.value == "-":
            self._advance()
            return UnaryOp("-", self._parse_unary(), tok.line)
        # unary +
        if tok.kind == TK_OP and tok.value == "+":
            self._advance()
            return self._parse_unary()
        # logical not
        if tok.kind == TK_OP and tok.value == "!":
            self._advance()
            return UnaryOp("!", self._parse_unary(), tok.line)
        # bitwise not
        if tok.kind == TK_OP and tok.value == "~":
            self._advance()
            return UnaryOp("~", self._parse_unary(), tok.line)
        # dereference *
        if tok.kind == TK_OP and tok.value == "*":
            self._advance()
            return Deref(self._parse_unary(), tok.line)
        # address-of &
        if tok.kind == TK_OP and tok.value == "&":
            self._advance()
            return AddressOf(self._parse_unary(), tok.line)
        # prefix ++ / --
        if tok.kind == TK_OP and tok.value in ("++", "--"):
            op = self._advance().value
            operand = self._parse_unary()
            return UnaryOp("pre" + op, operand, tok.line)
        # sizeof
        if tok.kind == TK_KEYWORD and tok.value == "sizeof":
            return self._parse_sizeof()
        # cast: (type) expr
        if tok.kind == TK_PUNCT and tok.value == "(" and self._is_type_start_at(1):
            return self._parse_cast()
        return self._parse_postfix()

    def _is_type_start_at(self, offset) -> bool:
        t = self._peek(offset)
        return t.kind == TK_KEYWORD and t.value in self.TYPE_BASES

    def _parse_cast(self):
        line = self._cur().line
        self._expect_punct("(")
        ctype = self._parse_type()
        # consume optional pointer stars already parsed into ctype
        self._expect_punct(")")
        expr = self._parse_unary()
        return Cast(ctype, expr, line)

    def _parse_sizeof(self):
        line = self._cur().line
        self._advance()   # 'sizeof'
        if self._match_punct("("):
            self._advance()
            if self._is_type_start():
                t = self._parse_type()
                self._expect_punct(")")
                return SizeOf(t, line)
            expr = self._parse_expr()
            self._expect_punct(")")
            return SizeOf(expr, line)
        return SizeOf(self._parse_unary(), line)

    def _parse_postfix(self):
        expr = self._parse_primary()
        while True:
            tok = self._cur()
            # array subscript
            if tok.kind == TK_PUNCT and tok.value == "[":
                self._advance()
                idx = self._parse_expr()
                self._expect_punct("]")
                expr = Subscript(expr, idx, tok.line)
            # function call
            elif tok.kind == TK_PUNCT and tok.value == "(" and isinstance(expr, Ident):
                args = self._parse_arg_list()
                expr = Call(expr.name, args, tok.line)
            # postfix ++ / --
            elif tok.kind == TK_OP and tok.value in ("++", "--"):
                op = self._advance().value
                expr = UnaryOp("post" + op, expr, tok.line)
            # struct member access (stubbed — not fully supported)
            elif tok.kind == TK_PUNCT and tok.value == ".":
                self._advance()
                member = self._advance().value
                expr = BinOp(".", expr, Ident(member, tok.line), tok.line)
            elif tok.kind == TK_OP and tok.value == "->":
                self._advance()
                member = self._advance().value
                expr = BinOp("->", Deref(expr, tok.line),
                             Ident(member, tok.line), tok.line)
            else:
                break
        return expr

    def _parse_arg_list(self) -> List:
        self._expect_punct("(")
        args = []
        if self._match_punct(")"):
            self._advance()
            return args
        while True:
            args.append(self._parse_assign_expr())
            if self._match_punct(","):
                self._advance()
            else:
                break
        self._expect_punct(")")
        return args

    def _parse_primary(self):
        tok = self._cur()

        if tok.kind == TK_INT_LIT:
            self._advance()
            return IntLit(tok.value, tok.line)

        if tok.kind == TK_STR_LIT:
            self._advance()
            return StrLit(tok.value, tok.line)

        if tok.kind in (TK_IDENT, TK_KEYWORD):
            self._advance()
            return Ident(tok.value, tok.line)

        if tok.kind == TK_PUNCT and tok.value == "(":
            self._advance()
            expr = self._parse_expr()
            self._expect_punct(")")
            return expr

        self._error(f"unexpected token in expression: {tok.value!r}", tok)
