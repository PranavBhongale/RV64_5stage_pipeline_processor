"""
codegen.py  —  RV64IM Assembly Code Generator
==============================================
Walks the AST and emits assembly compatible with rv64im_assembler.py.

Register allocation strategy:
  - Simple stack-based: ALL locals live on the stack (fp-relative)
  - Temporaries: t0-t6  (caller-saved, freely clobbered)
  - Function args passed/returned: a0-a7
  - Callee-saved: s0 (fp), s1-s11, ra, sp
  - We only preserve ra, fp, and the s-regs we use

Stack frame layout (grows downward):
  [high address]
  old ra         <- fp + 0   (saved by prologue)
  old fp         <- fp - 8
  local var N    <- fp - 16
  local var N-1  <- fp - 24
  ...
  [low address / sp]
"""

from ast_nodes import *
from typing import List, Dict, Optional, Tuple
import os


# ─── Register file constants ──────────────────────────────────────────────────

ARG_REGS  = ["a0","a1","a2","a3","a4","a5","a6","a7"]
TMP_REGS  = ["t0","t1","t2","t3","t4","t5","t6"]
RET_REG   = "a0"


# ─── Symbol / scope information ───────────────────────────────────────────────

class VarInfo:
    def __init__(self, name, ctype, fp_offset=None, is_global=False, label=None):
        self.name      = name
        self.ctype     = ctype
        self.fp_offset = fp_offset    # signed int, relative to fp (locals)
        self.is_global = is_global
        self.label     = label        # asm label (globals)


class FuncInfo:
    def __init__(self, name, ret_type, params):
        self.name     = name
        self.ret_type = ret_type
        self.params   = params        # List[Param]


# ─── Code generator ───────────────────────────────────────────────────────────

class CodeGen:
    def __init__(self, ast: TranslationUnit, filename: str = ""):
        self.ast          = ast
        self.filename     = filename

        # output lines
        self._text_lines : List[str] = []
        self._data_lines : List[str] = []

        # global symbol table: name → VarInfo / FuncInfo
        self._globals : Dict[str, VarInfo]  = {}
        self._funcs   : Dict[str, FuncInfo] = {}

        # per-function state
        self._locals      : List[Dict[str, VarInfo]] = []   # scope stack
        self._frame_size  : int  = 0
        self._next_offset : int  = 0    # next fp-relative offset (negative, grows down)
        self._label_cnt   : int  = 0
        self._cur_func    : Optional[str] = None
        self._break_label    : Optional[str] = None
        self._continue_label : Optional[str] = None

        # string literals: value → label
        self._strings : Dict[str, str] = {}

    # ── label factory ─────────────────────────────────────────────

    def _new_label(self, prefix=".L") -> str:
        n = self._label_cnt
        self._label_cnt += 1
        return f"{prefix}{n}"

    # ── emit helpers ──────────────────────────────────────────────

    def _emit(self, line: str):
        self._text_lines.append(line)

    def _emit_data(self, line: str):
        self._data_lines.append(line)

    def _ins(self, mnemonic: str, *args):
        operands = ", ".join(str(a) for a in args)
        self._emit(f"    {mnemonic:<8} {operands}")

    def _label(self, name: str, global_=False):
        if global_:
            self._emit(f"    .global {name}")
        self._emit(f"{name}:")

    def _comment(self, txt: str):
        self._emit(f"    # {txt}")

    # ── scope / variable management ───────────────────────────────

    def _push_scope(self):
        self._locals.append({})

    def _pop_scope(self):
        self._locals.pop()

    def _declare_local(self, name: str, ctype: CType, size_override=None) -> VarInfo:
        """Allocate space on the stack for a local variable."""
        sz = size_override or _type_size(ctype)
        sz = _align_up(sz, 8)           # always 8-byte aligned for simplicity
        self._next_offset -= sz
        info = VarInfo(name, ctype, fp_offset=self._next_offset)
        if self._locals:
            self._locals[-1][name] = info
        return info

    def _lookup(self, name: str) -> Optional[VarInfo]:
        for scope in reversed(self._locals):
            if name in scope:
                return scope[name]
        return self._globals.get(name)

    # ── address / load / store ────────────────────────────────────

    def _load_addr_into(self, info: VarInfo, reg: str):
        """Put the ADDRESS of variable into reg."""
        if info.is_global:
            self._ins("LA", reg, info.label)
        else:
            if -2048 <= info.fp_offset <= 2047:
                self._ins("ADDI", reg, "s0", info.fp_offset)
            else:
                self._ins("LI",   reg, info.fp_offset)
                self._ins("ADD",  reg, "s0", reg)

    def _load_var_into(self, info: VarInfo, reg: str):
        """Load the VALUE of a scalar variable into reg."""
        if info.ctype.is_array:
            # loading an array decays to address
            self._load_addr_into(info, reg)
            return
        if info.is_global:
            # two-instruction load for globals
            tmp = "t6"
            self._ins("LA",  tmp, info.label)
            self._emit_load(info.ctype, reg, tmp, 0)
        else:
            self._emit_load(info.ctype, reg, "s0", info.fp_offset)

    def _emit_load(self, ctype: CType, dst: str, base: str, offset: int):
        """Choose correct load instruction for the type."""
        if ctype.is_ptr():
            op = "LD"
        else:
            op = {"char":"LB", "short":"LH", "int":"LW", "long":"LD",
                  "void":"LD"}.get(ctype.base, "LD")
        self._ins(op, dst, f"{offset}({base})")

    def _emit_store(self, ctype: CType, src: str, base: str, offset: int):
        """Choose correct store instruction for the type."""
        if ctype.is_ptr():
            op = "SD"
        else:
            op = {"char":"SB", "short":"SH", "int":"SW", "long":"SD",
                  "void":"SD"}.get(ctype.base, "SD")
        self._ins(op, src, f"{offset}({base})")

    def _store_to_info(self, info: VarInfo, src_reg: str):
        """Store src_reg → variable."""
        if info.is_global:
            tmp = "t6"
            self._ins("LA", tmp, info.label)
            self._emit_store(info.ctype, src_reg, tmp, 0)
        else:
            self._emit_store(info.ctype, src_reg, "s0", info.fp_offset)

    # ── expression evaluation → result in dst_reg ─────────────────

    def _eval_expr(self, expr, dst: str = "a0") -> str:
        """
        Evaluate expression, put result in dst.
        Returns the register that actually holds the result (usually dst).
        Uses t0-t5 as scratch (never t6 – reserved for global address temp).
        """

        if isinstance(expr, IntLit):
            self._ins("LI", dst, expr.value)
            return dst

        if isinstance(expr, StrLit):
            label = self._intern_string(expr.value)
            self._ins("LA", dst, label)
            return dst

        if isinstance(expr, Ident):
            info = self._lookup(expr.name)
            if info is None:
                raise NameError(f"line {expr.line}: undefined variable '{expr.name}'")
            self._load_var_into(info, dst)
            return dst

        if isinstance(expr, SizeOf):
            if isinstance(expr.of_type, CType):
                sz = _type_size(expr.of_type)
            else:
                sz = 8   # conservative: sizeof expression → 8
            self._ins("LI", dst, sz)
            return dst

        if isinstance(expr, AddressOf):
            operand = expr.expr
            if isinstance(operand, Ident):
                info = self._lookup(operand.name)
                if info is None:
                    raise NameError(f"undefined: {operand.name}")
                self._load_addr_into(info, dst)
            elif isinstance(operand, Subscript):
                self._eval_subscript_addr(operand, dst)
            else:
                raise TypeError(f"cannot take address of {type(operand).__name__}")
            return dst

        if isinstance(expr, Deref):
            self._eval_expr(expr.expr, dst)
            # Load from that address (assume pointer-to-int for now → LD)
            self._ins("LD", dst, f"0({dst})")
            return dst

        if isinstance(expr, Subscript):
            self._eval_subscript_addr(expr, "t0")
            # detect element size for proper load
            arr_expr = expr.array
            if isinstance(arr_expr, Ident):
                info = self._lookup(arr_expr.name)
                if info:
                    elem = CType(info.ctype.base, info.ctype.ptr_depth)
                    self._emit_load(elem, dst, "t0", 0)
                    return dst
            # fallback: LD
            self._ins("LD", dst, "0(t0)")
            return dst

        if isinstance(expr, Cast):
            self._eval_expr(expr.expr, dst)
            # sign/zero extension casts (simplified)
            return dst

        if isinstance(expr, UnaryOp):
            return self._eval_unary(expr, dst)

        if isinstance(expr, BinOp):
            return self._eval_binop(expr, dst)

        if isinstance(expr, Assign):
            return self._eval_assign(expr, dst)

        if isinstance(expr, Call):
            return self._eval_call(expr, dst)

        if isinstance(expr, Ternary):
            return self._eval_ternary(expr, dst)

        raise TypeError(f"unknown expression type: {type(expr).__name__}")

    # ── address of array element ──────────────────────────────────

    def _eval_subscript_addr(self, expr: Subscript, dst: str):
        """Compute address of expr.array[expr.index] into dst."""
        arr = expr.array

        # get element size
        elem_sz = 8
        if isinstance(arr, Ident):
            info = self._lookup(arr.name)
            if info:
                elem_sz = _type_size(CType(info.ctype.base, info.ctype.ptr_depth))

        self._eval_expr(arr, dst)        # base address
        self._eval_expr(expr.index, "t1")
        if elem_sz != 1:
            self._ins("LI",  "t2", elem_sz)
            self._ins("MUL", "t1", "t1", "t2")
        self._ins("ADD", dst, dst, "t1")

    # ── unary expressions ─────────────────────────────────────────

    def _eval_unary(self, expr: UnaryOp, dst: str) -> str:
        op = expr.op

        if op == "-":
            self._eval_expr(expr.operand, dst)
            self._ins("NEG", dst, dst)
            return dst

        if op == "~":
            self._eval_expr(expr.operand, dst)
            self._ins("NOT", dst, dst)
            return dst

        if op == "!":
            self._eval_expr(expr.operand, dst)
            self._ins("SEQZ", dst, dst)
            return dst

        if op in ("pre++", "pre--"):
            arith = "ADDI" ; delta = 1 if op == "pre++" else -1
            self._eval_lval_addr(expr.operand, "t0")
            self._ins("LD",   dst,  "0(t0)")
            self._ins("ADDI", dst,  dst, delta)
            self._ins("SD",   dst,  "0(t0)")
            return dst

        if op in ("post++", "post--"):
            delta = 1 if op == "post++" else -1
            self._eval_lval_addr(expr.operand, "t0")
            self._ins("LD",   dst,  "0(t0)")
            self._ins("ADDI", "t1", dst, delta)
            self._ins("SD",   "t1", "0(t0)")
            return dst   # returns OLD value

        raise TypeError(f"unknown unary op: {op}")

    # ── lvalue address ────────────────────────────────────────────

    def _eval_lval_addr(self, expr, dst: str):
        if isinstance(expr, Ident):
            info = self._lookup(expr.name)
            if info is None:
                raise NameError(f"undefined: {expr.name}")
            self._load_addr_into(info, dst)
        elif isinstance(expr, Deref):
            self._eval_expr(expr.expr, dst)
        elif isinstance(expr, Subscript):
            self._eval_subscript_addr(expr, dst)
        else:
            raise TypeError(f"not an lvalue: {type(expr).__name__}")

    # ── binary expressions ────────────────────────────────────────

    # Mapping of C operator → RV64IM instruction (reg, reg)
    _BINOP_INS = {
        "+":  "ADD",  "-": "SUB",  "*": "MUL",
        "/":  "DIV",  "%": "REM",
        "&":  "AND",  "|": "OR",   "^": "XOR",
        "<<": "SLL",  ">>":"SRA",
    }

    def _eval_binop(self, expr: BinOp, dst: str) -> str:
        op = expr.op

        # short-circuit logical
        if op == "&&":
            return self._eval_logand(expr, dst)
        if op == "||":
            return self._eval_logor(expr, dst)

        # comparison
        if op in ("==","!=","<",">","<=",">="):
            return self._eval_compare(expr, dst)

        # arithmetic / bitwise
        if op in self._BINOP_INS:
            self._eval_expr(expr.left, dst)
            self._ins("ADDI", "sp", "sp", -8)
            self._ins("SD",   dst,  "0(sp)")          # push left
            self._eval_expr(expr.right, "t0")
            self._ins("LD",   dst,  "0(sp)")          # pop left
            self._ins("ADDI", "sp", "sp", 8)
            ins = self._BINOP_INS[op]
            self._ins(ins, dst, dst, "t0")
            return dst

        raise TypeError(f"unsupported binary op: {op}")

    def _eval_compare(self, expr: BinOp, dst: str) -> str:
        """
        Evaluate comparison.  Left -> t1, Right -> t0, result -> dst.
        Using t1 for left avoids the SLT dst, t0, dst aliasing hazard.
        """
        op = expr.op
        self._eval_expr(expr.left, "t1")
        self._ins("ADDI", "sp", "sp", -8)
        self._ins("SD",   "t1", "0(sp)")
        self._eval_expr(expr.right, "t0")
        self._ins("LD",   "t1", "0(sp)")
        self._ins("ADDI", "sp", "sp", 8)

        if op == "==":
            self._ins("XOR",  dst, "t1", "t0")
            self._ins("SEQZ", dst, dst)
        elif op == "!=":
            self._ins("XOR",  dst, "t1", "t0")
            self._ins("SNEZ", dst, dst)
        elif op == "<":
            self._ins("SLT",  dst, "t1", "t0")
        elif op == ">":
            self._ins("SLT",  dst, "t0", "t1")
        elif op == "<=":
            self._ins("SLT",  dst, "t0", "t1")
            self._ins("XORI", dst, dst,  1)
        elif op == ">=":
            self._ins("SLT",  dst, "t1", "t0")
            self._ins("XORI", dst, dst,  1)
        return dst

    def _eval_logand(self, expr: BinOp, dst: str) -> str:
        false_lbl = self._new_label(".Lfalse")
        end_lbl   = self._new_label(".Lend")
        self._eval_expr(expr.left, dst)
        self._ins("BEQ", dst, "zero", false_lbl)
        self._eval_expr(expr.right, dst)
        self._ins("BEQ", dst, "zero", false_lbl)
        self._ins("LI",  dst, 1)
        self._ins("JAL", "zero", end_lbl)
        self._label(false_lbl)
        self._ins("LI",  dst, 0)
        self._label(end_lbl)
        return dst

    def _eval_logor(self, expr: BinOp, dst: str) -> str:
        true_lbl = self._new_label(".Ltrue")
        end_lbl  = self._new_label(".Lend")
        self._eval_expr(expr.left, dst)
        self._ins("BNE", dst, "zero", true_lbl)
        self._eval_expr(expr.right, dst)
        self._ins("BNE", dst, "zero", true_lbl)
        self._ins("LI",  dst, 0)
        self._ins("JAL", "zero", end_lbl)
        self._label(true_lbl)
        self._ins("LI",  dst, 1)
        self._label(end_lbl)
        return dst

    # ── assignment ────────────────────────────────────────────────

    def _eval_assign(self, expr: Assign, dst: str) -> str:
        op = expr.op

        # Get address of LHS
        self._eval_lval_addr(expr.target, "t5")

        # Compound assignment: read, modify, store
        if op != "=":
            simple_op = op[:-1]   # "+=" → "+"
            # load old value
            self._ins("LD", "t4", "0(t5)")
            self._ins("ADDI", "sp", "sp", -8)
            self._ins("SD",   "t5", "0(sp)")        # save address
            # eval RHS
            self._eval_expr(expr.value, dst)
            self._ins("LD",  "t5", "0(sp)")          # restore address
            self._ins("ADDI","sp", "sp", 8)
            if simple_op in self._BINOP_INS:
                self._ins(self._BINOP_INS[simple_op], dst, "t4", dst)
            else:
                raise TypeError(f"unsupported compound assign: {op}")
        else:
            # Save address
            self._ins("ADDI", "sp", "sp", -8)
            self._ins("SD",   "t5", "0(sp)")
            # Eval RHS
            self._eval_expr(expr.value, dst)
            self._ins("LD",  "t5", "0(sp)")
            self._ins("ADDI","sp", "sp", 8)

        self._ins("SD", dst, "0(t5)")
        return dst

    # ── function call ─────────────────────────────────────────────

    def _eval_call(self, expr: Call, dst: str) -> str:
        # Caller-save: we already use a0-a7 for args, t0-t5 as scratch.
        # Push caller-saved temporaries we depend on (t0-t4 + a0-a7) onto stack
        # Simple approach: save a0-a7 we'll overwrite for args, restore after
        n_args = len(expr.args)

        # Evaluate all args, push them on stack in reverse order first
        # then load into a0-a7 just before the call
        arg_temps = []
        for i, arg in enumerate(expr.args):
            self._eval_expr(arg, "t0")
            self._ins("ADDI", "sp", "sp", -8)
            self._ins("SD",   "t0", "0(sp)")
            arg_temps.append(i)

        # Pop args into a0, a1, ... in correct order
        for i in range(n_args - 1, -1, -1):
            reg = ARG_REGS[i] if i < len(ARG_REGS) else None
            if reg:
                self._ins("LD",   reg, "0(sp)")
                self._ins("ADDI", "sp", "sp", 8)
            else:
                # Extra args stay on stack (ABI: pass on stack)
                pass

        self._ins("CALL", expr.func)

        if dst != RET_REG:
            self._ins("MV", dst, RET_REG)
        return dst

    # ── ternary ───────────────────────────────────────────────────

    def _eval_ternary(self, expr: Ternary, dst: str) -> str:
        else_lbl = self._new_label(".Lelse")
        end_lbl  = self._new_label(".Lend")
        self._eval_expr(expr.cond, dst)
        self._ins("BEQ", dst, "zero", else_lbl)
        self._eval_expr(expr.then, dst)
        self._ins("JAL", "zero", end_lbl)
        self._label(else_lbl)
        self._eval_expr(expr.else_, dst)
        self._label(end_lbl)
        return dst

    # ── statement code-gen ────────────────────────────────────────

    def _gen_stmt(self, stmt):
        if isinstance(stmt, Block):
            self._push_scope()
            for s in stmt.stmts:
                self._gen_stmt(s)
            self._pop_scope()

        elif isinstance(stmt, ExprStmt):
            self._eval_expr(stmt.expr, "a0")

        elif isinstance(stmt, VarDecl):
            self._gen_var_decl(stmt)

        elif isinstance(stmt, IfStmt):
            self._gen_if(stmt)

        elif isinstance(stmt, WhileStmt):
            self._gen_while(stmt)

        elif isinstance(stmt, DoWhileStmt):
            self._gen_do_while(stmt)

        elif isinstance(stmt, ForStmt):
            self._gen_for(stmt)

        elif isinstance(stmt, ReturnStmt):
            self._gen_return(stmt)

        elif isinstance(stmt, BreakStmt):
            if self._break_label is None:
                raise SyntaxError("break outside loop")
            self._ins("JAL", "zero", self._break_label)

        elif isinstance(stmt, ContinueStmt):
            if self._continue_label is None:
                raise SyntaxError("continue outside loop")
            self._ins("JAL", "zero", self._continue_label)

        else:
            pass   # ignore unknown (e.g. empty Block)

    def _gen_var_decl(self, stmt: VarDecl):
        ctype = stmt.ctype

        if ctype.is_array:
            n    = ctype.arr_size or 1
            esz  = _type_size(CType(ctype.base, ctype.ptr_depth))
            total = _align_up(n * esz, 8)
            info = self._declare_local(stmt.name, ctype, size_override=total)
            # zero-initialize
            self._load_addr_into(info, "t0")
            for i in range(n):
                self._ins("SW", "zero", f"{i*esz}(t0)")
            # initializer list
            if stmt.init and isinstance(stmt.init, list):
                for i, val in enumerate(stmt.init):
                    self._eval_expr(val, "t1")
                    self._ins("SW", "t1", f"{i*esz}(t0)")
        else:
            info = self._declare_local(stmt.name, ctype)
            if stmt.init:
                self._eval_expr(stmt.init, "t0")
                self._store_to_info(info, "t0")
            else:
                # zero-initialize
                self._store_to_info(info, "zero")

    def _gen_if(self, stmt: IfStmt):
        else_lbl = self._new_label(".Lelse")
        end_lbl  = self._new_label(".Lend")
        self._comment(f"if (line {stmt.line})")
        self._eval_expr(stmt.cond, "t0")
        self._ins("BEQ", "t0", "zero", else_lbl)
        self._gen_stmt(stmt.then)
        if stmt.else_:
            self._ins("JAL", "zero", end_lbl)
        self._label(else_lbl)
        if stmt.else_:
            self._gen_stmt(stmt.else_)
            self._label(end_lbl)

    def _gen_while(self, stmt: WhileStmt):
        cond_lbl  = self._new_label(".Lwhile_cond")
        end_lbl   = self._new_label(".Lwhile_end")
        old_break = self._break_label
        old_cont  = self._continue_label
        self._break_label    = end_lbl
        self._continue_label = cond_lbl
        self._comment(f"while (line {stmt.line})")
        self._label(cond_lbl)
        self._eval_expr(stmt.cond, "t0")
        self._ins("BEQ", "t0", "zero", end_lbl)
        self._gen_stmt(stmt.body)
        self._ins("JAL", "zero", cond_lbl)
        self._label(end_lbl)
        self._break_label    = old_break
        self._continue_label = old_cont

    def _gen_do_while(self, stmt: DoWhileStmt):
        body_lbl = self._new_label(".Ldo_body")
        end_lbl  = self._new_label(".Ldo_end")
        cond_lbl = self._new_label(".Ldo_cond")
        old_break = self._break_label
        old_cont  = self._continue_label
        self._break_label    = end_lbl
        self._continue_label = cond_lbl
        self._label(body_lbl)
        self._gen_stmt(stmt.body)
        self._label(cond_lbl)
        self._eval_expr(stmt.cond, "t0")
        self._ins("BNE", "t0", "zero", body_lbl)
        self._label(end_lbl)
        self._break_label    = old_break
        self._continue_label = old_cont

    def _gen_for(self, stmt: ForStmt):
        cond_lbl = self._new_label(".Lfor_cond")
        step_lbl = self._new_label(".Lfor_step")
        end_lbl  = self._new_label(".Lfor_end")
        old_break = self._break_label
        old_cont  = self._continue_label
        self._break_label    = end_lbl
        self._continue_label = step_lbl
        self._push_scope()
        self._comment(f"for (line {stmt.line})")
        if stmt.init:
            self._gen_stmt(stmt.init)
        self._label(cond_lbl)
        if stmt.cond:
            self._eval_expr(stmt.cond, "t0")
            self._ins("BEQ", "t0", "zero", end_lbl)
        self._gen_stmt(stmt.body)
        self._label(step_lbl)
        if stmt.step:
            self._eval_expr(stmt.step, "t0")
        self._ins("JAL", "zero", cond_lbl)
        self._label(end_lbl)
        self._pop_scope()
        self._break_label    = old_break
        self._continue_label = old_cont

    def _gen_return(self, stmt: ReturnStmt):
        if stmt.value:
            self._eval_expr(stmt.value, RET_REG)
        func_end = f".L{self._cur_func}_end"
        self._ins("JAL", "zero", func_end)

    # ── function prologue / epilogue ──────────────────────────────

    def _gen_function(self, decl: FuncDecl):
        if decl.body is None:
            return   # forward declaration

        self._cur_func    = decl.name
        self._next_offset = 0
        self._locals      = []
        self._label_cnt   = 0   # reset per-function for cleaner labels

        # First pass: scan body to know how many locals we need
        # We do a two-pass approach: generate into a temp buffer, then prepend prologue.
        saved_text = self._text_lines
        self._text_lines = []

        # open a fresh scope for parameters + body
        self._push_scope()

        # Bind parameters → stack slots  (ABI: args arrive in a0-a7)
        param_setup = []
        for i, param in enumerate(decl.params):
            info = self._declare_local(param.name, param.ctype)
            if i < len(ARG_REGS):
                param_setup.append((ARG_REGS[i], info))
            # else: on stack already (we don't handle >8 args fully)

        # Generate body instructions (into self._text_lines buffer)
        body_buf : List[str] = []
        self._text_lines = body_buf

        # Store parameters to their stack slots AFTER frame is built
        # We'll inject the stores right after the prologue.
        param_store_buf : List[str] = []
        for reg, info in param_setup:
            if -2048 <= info.fp_offset <= 2047:
                param_store_buf.append(f"    SD       {reg}, {info.fp_offset}(s0)")
            else:
                param_store_buf.append(f"    LI       t6, {info.fp_offset}")
                param_store_buf.append(f"    ADD      t6, s0, t6")
                param_store_buf.append(f"    SD       {reg}, 0(t6)")

        self._gen_stmt(decl.body)
        self._pop_scope()

        end_label = f".L{self._cur_func}_end"
        self._label(end_label)

        # Build prologue & epilogue now that we know frame size
        frame = _align_up(-self._next_offset + 16, 16)   # +16 for ra+fp

        prologue : List[str] = []
        def P(s): prologue.append(s)

        P(f"")
        P(f"    .global {decl.name}")
        P(f"{decl.name}:")
        P(f"    # ── prologue ─────────────────────────────")
        P(f"    ADDI     sp, sp, -{frame}")
        P(f"    SD       ra, {frame-8}(sp)")
        P(f"    SD       s0, {frame-16}(sp)")
        P(f"    ADDI     s0, sp, {frame}")
        # param stores
        prologue.extend(param_store_buf)
        P(f"    # ── body ────────────────────────────────")

        epilogue : List[str] = []
        def E(s): epilogue.append(s)
        E(f"    # ── epilogue ────────────────────────────")
        E(f"    LD       ra, {frame-8}(sp)")
        E(f"    LD       s0, {frame-16}(sp)")
        E(f"    ADDI     sp, sp, {frame}")
        E(f"    JALR     zero, ra, 0")

        # Combine: restore saved_text, append function
        self._text_lines = saved_text
        self._text_lines.extend(prologue)
        self._text_lines.extend(body_buf)
        self._text_lines.extend(epilogue)

    # ── global variable layout ────────────────────────────────────

    def _gen_global_var(self, decl: GlobalVarDecl):
        label = decl.name
        ctype = decl.ctype
        info  = VarInfo(decl.name, ctype, is_global=True, label=label)
        self._globals[decl.name] = info

        self._emit_data(f"")
        self._emit_data(f"    .global {label}")
        self._emit_data(f"{label}:")

        if ctype.is_array:
            n   = ctype.arr_size or 1
            esz = _type_size(CType(ctype.base, ctype.ptr_depth))
            if decl.init and isinstance(decl.init, list):
                for item in decl.init:
                    if isinstance(item, IntLit):
                        v = item.value
                    else:
                        v = 0
                    dir_ = _dtype_directive(ctype.base)
                    self._emit_data(f"    {dir_}    {v}")
                # pad remainder
                for _ in range(n - len(decl.init)):
                    dir_ = _dtype_directive(ctype.base)
                    self._emit_data(f"    {dir_}    0")
            else:
                self._emit_data(f"    .zero   {n * esz}")
        else:
            dir_ = _dtype_directive(ctype.base)
            if decl.init:
                if isinstance(decl.init, IntLit):
                    self._emit_data(f"    {dir_}    {decl.init.value}")
                elif isinstance(decl.init, StrLit):
                    self._emit_data(f'    .asciz  "{decl.init.value}"')
                else:
                    self._emit_data(f"    {dir_}    0   # non-const init (patched at load)")
            else:
                self._emit_data(f"    {dir_}    0")

    # ── string literal interning ──────────────────────────────────

    def _intern_string(self, value: str) -> str:
        if value not in self._strings:
            label = f".Lstr{len(self._strings)}"
            self._strings[value] = label
            self._emit_data(f"")
            self._emit_data(f"{label}:")
            escaped = value.replace("\\","\\\\").replace('"','\\"') \
                           .replace("\n","\\n").replace("\t","\\t")
            self._emit_data(f'    .asciz  "{escaped}"')
        return self._strings[value]

    # ── top-level generate ────────────────────────────────────────

    def generate(self) -> str:
        # First pass: collect function signatures for forward refs
        for decl in self.ast.decls:
            if isinstance(decl, FuncDecl):
                self._funcs[decl.name] = FuncInfo(decl.name, decl.ret_type, decl.params)

        # Emit section headers
        self._text_lines.append("    .text")
        self._data_lines.append("")
        self._data_lines.append("    .data")

        # Process all top-level declarations
        for decl in self.ast.decls:
            if isinstance(decl, GlobalVarDecl):
                self._gen_global_var(decl)
            elif isinstance(decl, FuncDecl):
                self._gen_function(decl)
            elif isinstance(decl, Block) and not decl.stmts:
                pass   # empty (from skipped semicolons)

        # Build final assembly string
        lines = []
        src = os.path.basename(self.filename)
        lines.append(f"# Generated by c_compiler.py  (source: {src})")
        lines.append(f"# Compatible with rv64im_assembler.py")
        lines.append("")
        lines.extend(self._text_lines)
        lines.append("")
        lines.extend(self._data_lines)
        lines.append("")

        return "\n".join(lines) + "\n"

    def dump_ir(self):
        """Print a pseudo-IR listing (just the raw text lines)."""
        for line in self._text_lines:
            print(line)


# ─── Utility functions ────────────────────────────────────────────────────────

def _type_size(ctype: CType) -> int:
    if ctype.is_ptr():
        return 8
    return {"char":1,"short":2,"int":4,"long":8,"void":0}.get(ctype.base, 8)

def _align_up(n: int, align: int) -> int:
    return (n + align - 1) // align * align

def _dtype_directive(base: str) -> str:
    return {
        "char":  ".byte",
        "short": ".half",
        "int":   ".word",
        "long":  ".dword",
        "void":  ".dword",
    }.get(base, ".dword")
