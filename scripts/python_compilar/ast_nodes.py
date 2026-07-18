"""
ast_nodes.py  —  AST node definitions
======================================
All nodes are plain Python dataclasses / classes.
"""

from dataclasses import dataclass, field
from typing import List, Optional, Any


# ──────────────────────────────────────────────────────────────────────────────
#  Type representation
# ──────────────────────────────────────────────────────────────────────────────

@dataclass
class CType:
    base     : str           # "int" | "long" | "char" | "void" | "ptr"
    ptr_depth: int = 0       # number of pointer indirections
    is_array : bool = False
    arr_size : Optional[int] = None

    def is_ptr(self):
        return self.ptr_depth > 0 or self.is_array

    def deref(self):
        """Return the type one pointer level deeper."""
        if self.ptr_depth > 0:
            return CType(self.base, self.ptr_depth - 1)
        if self.is_array:
            return CType(self.base, 0)
        raise TypeError("cannot deref non-pointer type")

    def size(self):
        """Size in bytes (used for pointer arithmetic & .data layout)."""
        if self.is_ptr():
            return 8        # 64-bit pointer
        return {"char": 1, "short": 2, "int": 4,
                "long": 8, "void": 0}.get(self.base, 8)

    def __str__(self):
        s = self.base + ("*" * self.ptr_depth)
        if self.is_array:
            s += f"[{self.arr_size}]"
        return s


# ──────────────────────────────────────────────────────────────────────────────
#  Expressions
# ──────────────────────────────────────────────────────────────────────────────

@dataclass
class IntLit:
    value : int
    line  : int = 0
    def dump(self, ind=""): print(f"{ind}IntLit({self.value})")

@dataclass
class StrLit:
    value : str
    line  : int = 0
    def dump(self, ind=""): print(f'{ind}StrLit("{self.value}")')

@dataclass
class Ident:
    name : str
    line : int = 0
    def dump(self, ind=""): print(f"{ind}Ident({self.name})")

@dataclass
class BinOp:
    op    : str
    left  : Any
    right : Any
    line  : int = 0
    def dump(self, ind=""):
        print(f"{ind}BinOp({self.op})")
        self.left.dump(ind + "  ")
        self.right.dump(ind + "  ")

@dataclass
class UnaryOp:
    op      : str
    operand : Any
    line    : int = 0
    def dump(self, ind=""):
        print(f"{ind}UnaryOp({self.op})")
        self.operand.dump(ind + "  ")

@dataclass
class Assign:
    op     : str          # "=" | "+=" | "-=" | etc.
    target : Any
    value  : Any
    line   : int = 0
    def dump(self, ind=""):
        print(f"{ind}Assign({self.op})")
        self.target.dump(ind + "  ")
        self.value.dump(ind + "  ")

@dataclass
class Call:
    func  : str
    args  : List[Any]
    line  : int = 0
    def dump(self, ind=""):
        print(f"{ind}Call({self.func})")
        for a in self.args:
            a.dump(ind + "  ")

@dataclass
class Subscript:
    array : Any
    index : Any
    line  : int = 0
    def dump(self, ind=""):
        print(f"{ind}Subscript")
        self.array.dump(ind + "  ")
        self.index.dump(ind + "  ")

@dataclass
class Deref:
    expr : Any
    line : int = 0
    def dump(self, ind=""):
        print(f"{ind}Deref")
        self.expr.dump(ind + "  ")

@dataclass
class AddressOf:
    expr : Any
    line : int = 0
    def dump(self, ind=""):
        print(f"{ind}AddressOf")
        self.expr.dump(ind + "  ")

@dataclass
class Cast:
    to_type : CType
    expr    : Any
    line    : int = 0
    def dump(self, ind=""):
        print(f"{ind}Cast({self.to_type})")
        self.expr.dump(ind + "  ")

@dataclass
class SizeOf:
    of_type : Any          # CType or expression
    line    : int = 0
    def dump(self, ind=""): print(f"{ind}SizeOf({self.of_type})")

@dataclass
class Ternary:
    cond  : Any
    then  : Any
    else_ : Any
    line  : int = 0
    def dump(self, ind=""):
        print(f"{ind}Ternary")
        self.cond.dump(ind + "  ")
        self.then.dump(ind + "  ")
        self.else_.dump(ind + "  ")

# ──────────────────────────────────────────────────────────────────────────────
#  Statements
# ──────────────────────────────────────────────────────────────────────────────

@dataclass
class Block:
    stmts : List[Any]
    def dump(self, ind=""):
        print(f"{ind}Block")
        for s in self.stmts:
            s.dump(ind + "  ")

@dataclass
class ExprStmt:
    expr : Any
    def dump(self, ind=""):
        print(f"{ind}ExprStmt")
        self.expr.dump(ind + "  ")

@dataclass
class VarDecl:
    ctype   : CType
    name    : str
    init    : Optional[Any] = None   # expression or list (for arrays)
    line    : int = 0
    def dump(self, ind=""):
        print(f"{ind}VarDecl({self.ctype} {self.name})")
        if self.init:
            if isinstance(self.init, list):
                for x in self.init: x.dump(ind + "  ")
            else:
                self.init.dump(ind + "  ")

@dataclass
class IfStmt:
    cond    : Any
    then    : Any
    else_   : Optional[Any] = None
    line    : int = 0
    def dump(self, ind=""):
        print(f"{ind}If")
        self.cond.dump(ind + "  ")
        self.then.dump(ind + "  ")
        if self.else_:
            print(f"{ind}Else")
            self.else_.dump(ind + "  ")

@dataclass
class WhileStmt:
    cond  : Any
    body  : Any
    line  : int = 0
    def dump(self, ind=""):
        print(f"{ind}While")
        self.cond.dump(ind + "  ")
        self.body.dump(ind + "  ")

@dataclass
class DoWhileStmt:
    body  : Any
    cond  : Any
    line  : int = 0
    def dump(self, ind=""):
        print(f"{ind}DoWhile")
        self.body.dump(ind + "  ")
        self.cond.dump(ind + "  ")

@dataclass
class ForStmt:
    init  : Optional[Any]
    cond  : Optional[Any]
    step  : Optional[Any]
    body  : Any
    line  : int = 0
    def dump(self, ind=""):
        print(f"{ind}For")
        if self.init: self.init.dump(ind + "  ")
        if self.cond: self.cond.dump(ind + "  ")
        if self.step: self.step.dump(ind + "  ")
        self.body.dump(ind + "  ")

@dataclass
class ReturnStmt:
    value : Optional[Any]
    line  : int = 0
    def dump(self, ind=""):
        print(f"{ind}Return")
        if self.value: self.value.dump(ind + "  ")

@dataclass
class BreakStmt:
    line : int = 0
    def dump(self, ind=""): print(f"{ind}Break")

@dataclass
class ContinueStmt:
    line : int = 0
    def dump(self, ind=""): print(f"{ind}Continue")

# ──────────────────────────────────────────────────────────────────────────────
#  Top-level declarations
# ──────────────────────────────────────────────────────────────────────────────

@dataclass
class Param:
    ctype : CType
    name  : str

@dataclass
class FuncDecl:
    ret_type : CType
    name     : str
    params   : List[Param]
    body     : Optional[Block]   # None = forward declaration
    line     : int = 0
    def dump(self, ind=""):
        args = ", ".join(f"{p.ctype} {p.name}" for p in self.params)
        print(f"{ind}FuncDecl {self.ret_type} {self.name}({args})")
        if self.body:
            self.body.dump(ind + "  ")

@dataclass
class GlobalVarDecl:
    ctype : CType
    name  : str
    init  : Optional[Any] = None
    line  : int = 0
    def dump(self, ind=""):
        print(f"{ind}GlobalVar({self.ctype} {self.name})")
        if self.init:
            if isinstance(self.init, list):
                for x in self.init: x.dump(ind + "  ")
            else:
                self.init.dump(ind + "  ")

@dataclass
class TranslationUnit:
    decls : List[Any]
    def dump(self, ind=""):
        print(f"{ind}TranslationUnit")
        for d in self.decls:
            d.dump(ind + "  ")



