#!/usr/bin/env python3
"""
c_compiler.py  —  C to RV64IM Assembly Compiler
=================================================
Compiles a subset of C into RISC-V 64-bit assembly (.asm)
compatible with rv64im_assembler.py.

Supported C subset:
  Types      : int, long, char, void  (all treated as 64-bit in registers)
  Variables  : local variables, global variables, integer literals
  Arithmetic : +  -  *  /  %  (unary -)
  Bitwise    : &  |  ^  ~  <<  >>
  Comparison : ==  !=  <  >  <=  >=
  Logical    : &&  ||  !
  Assignment : =  +=  -=  *=  /=  %=
  Control    : if / else,  while,  for,  do-while,  return,  break,  continue
  Functions  : declaration, definition, call, recursion
  Arrays     : 1-D integer arrays (local & global)
  Pointers   : basic pointer arithmetic (& and *)

ABI followed:
  - a0–a7   : function arguments (first 8); return value in a0
  - ra      : return address
  - sp      : stack pointer (grows downward, 16-byte aligned)
  - s0/fp   : frame pointer
  - Caller-saved : a0-a7, t0-t6
  - Callee-saved : s0-s11, ra, sp

Usage:
  python3 c_compiler.py input.c
  python3 c_compiler.py input.c -o output.asm
  python3 c_compiler.py input.c --dump-ast
  python3 c_compiler.py input.c --dump-ir
"""

import sys
import os
import argparse

from lexer   import Lexer
from parser  import Parser
from codegen import CodeGen


def main():
    ap = argparse.ArgumentParser(
        description="C → RV64IM assembler compiler (for rv64im_assembler.py)")
    ap.add_argument("input",            help="Input C source file (.c)")
    ap.add_argument("-o", "--output",   help="Output .asm file (default: <input>.asm)")
    ap.add_argument("--dump-ast",       action="store_true", help="Print AST and exit")
    ap.add_argument("--dump-ir",        action="store_true", help="Print IR and exit")
    args = ap.parse_args()

    src_path = args.input
    if not os.path.isfile(src_path):
        print(f"Error: file not found: {src_path}", file=sys.stderr)
        sys.exit(1)

    with open(src_path, "r", encoding="utf-8") as f:
        source = f.read()

    out_path = args.output or os.path.splitext(src_path)[0] + ".asm"

    try:
        # ── 1. Lex ────────────────────────────────────────────────
        lexer  = Lexer(source, src_path)
        tokens = lexer.tokenize()

        # ── 2. Parse ──────────────────────────────────────────────
        parser = Parser(tokens, source)
        ast    = parser.parse()

        if args.dump_ast:
            ast.dump()
            return

        # ── 3. Code-gen ───────────────────────────────────────────
        cg   = CodeGen(ast, src_path)
        asm  = cg.generate()

        if args.dump_ir:
            cg.dump_ir()
            return

        with open(out_path, "w", encoding="utf-8") as f:
            f.write(asm)

        print(f"Compiled  {src_path}  →  {out_path}")

    except (SyntaxError, TypeError, NameError) as e:
        print(f"Compiler error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
