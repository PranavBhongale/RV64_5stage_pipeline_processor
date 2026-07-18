#!/usr/bin/env python3
"""
rv64im_assembler.py  —  RV64IM Assembler
=========================================
Reads a .asm file, produces two output files:
  imem.hex   — instruction memory  (one 32-bit word per line, hex)
  dmem.hex   — data memory         (one 8-bit byte per line, hex)

Supported ISA:
  Base RV64I:
    R-type  : ADD SUB AND OR XOR SLL SRL SRA SLT SLTU
              ADDW SUBW SLLW SRLW SRAW                   (RV64I *W variants)
    I-type  : ADDI ANDI ORI XORI SLTI SLTIU
              SLLI SRLI SRAI                              (64-bit shifts, shamt[5:0])
              ADDIW SLLIW SRLIW SRAIW                    (RV64I *W imm variants)
    Load    : LB LH LW LBU LHU  LD LWU                  (LD/LWU = RV64I)
    Store   : SB SH SW  SD                               (SD = RV64I)
    Branch  : BEQ BNE BLT BGE BLTU BGEU
    U-type  : LUI AUIPC
    Jump    : JAL JALR
    System  : ECALL EBREAK

  RV64M extension (multiply / divide):
    MUL MULH MULHU MULHSU DIV DIVU REM REMU
    MULW DIVW DIVUW REMW REMUW                           (RV64M *W variants)

  Pseudo-instructions (compiler-friendly):
    NOP  LI  MV  NEG  NEGW  NOT
    SEQZ SNEZ SLTZ SGTZ
    BEQZ BNEZ BLEZ BGEZ BLTZ BGTZ
    J    JR   RET  CALL  TAIL
    LA   (generates AUIPC + ADDI pair)

Directives:
  .text   .data   .bss
  .byte   .half   .word   .dword
  .ascii  .asciz  .string
  .align  .balign .zero
  .global .globl  .extern  .equ  .set

Compiler compatibility:
  — Section-aware layout (text / data / bss separated)
  — Symbol table exported to  symbols.txt
  — Relocation-friendly: LA expands to AUIPC+ADDI pair
  — .equ / .set constant folding
  — Expression parser for immediates: supports +, -, *, /, %, <<, >>, ()

Usage:
  python3 rv64im_assembler.py program.asm
      → imem.hex, dmem.hex, symbols.txt

  python3 rv64im_assembler.py program.asm --dis
      → disassembly listing to stdout

  python3 rv64im_assembler.py program.asm --imem custom_imem.hex --dmem custom_dmem.hex
      → custom output filenames
"""

import sys
import re
import os
import struct
import operator
from typing import Optional, List, Dict, Tuple

# ═══════════════════════════════════════════════════════════════════════════════
# CONSTANTS
# ═══════════════════════════════════════════════════════════════════════════════

IMEM_PAD_WORDS   = 256     # pad instruction memory to this many words (NOP fill)
DMEM_PAD_BYTES   = 256     # pad data memory to this many bytes (zero fill)

TEXT_BASE        = 0x0000_0000   # instruction memory base address
DATA_BASE        = 0x0001_0000   # data memory base address  (64 KiB above text)

NOP_WORD         = 0x0000_0013   # ADDI x0, x0, 0

# ═══════════════════════════════════════════════════════════════════════════════
# EXCEPTION
# ═══════════════════════════════════════════════════════════════════════════════

class AssemblerError(Exception):
    def __init__(self, message: str, line_num: int = None, line_text: str = None):
        self.message   = message
        self.line_num  = line_num
        self.line_text = line_text
        super().__init__(self._format())

    def _format(self) -> str:
        parts = []
        if self.line_num is not None:
            parts.append(f"Line {self.line_num}")
        if self.line_text is not None:
            parts.append(f"  >> {self.line_text.rstrip()}")
        parts.append(f"  ERROR: {self.message}")
        return "\n".join(parts)


# ═══════════════════════════════════════════════════════════════════════════════
# REGISTER TABLE
# ═══════════════════════════════════════════════════════════════════════════════

REGISTERS: Dict[str, int] = {
    **{f'x{i}': i for i in range(32)},
    'zero': 0,
    'ra':   1,  'sp':   2,  'gp':   3,  'tp':   4,
    't0':   5,  't1':   6,  't2':   7,
    's0':   8,  'fp':   8,  's1':   9,
    'a0':  10,  'a1':  11,  'a2':  12,  'a3':  13,
    'a4':  14,  'a5':  15,  'a6':  16,  'a7':  17,
    's2':  18,  's3':  19,  's4':  20,  's5':  21,
    's6':  22,  's7':  23,  's8':  24,  's9':  25,
    's10': 26,  's11': 27,
    't3':  28,  't4':  29,  't5':  30,  't6':  31,
}

REG_NAMES = [
    'zero','ra','sp','gp','tp',
    't0','t1','t2','s0','s1',
    'a0','a1','a2','a3','a4','a5','a6','a7',
    's2','s3','s4','s5','s6','s7','s8','s9','s10','s11',
    't3','t4','t5','t6',
]

# ═══════════════════════════════════════════════════════════════════════════════
# ALL SUPPORTED MNEMONICS  (used for error hints)
# ═══════════════════════════════════════════════════════════════════════════════

ALL_MNEMONICS = {
    # RV64I R-type
    'ADD','SUB','AND','OR','XOR','SLL','SRL','SRA','SLT','SLTU',
    'ADDW','SUBW','SLLW','SRLW','SRAW',
    # RV64I I-type ALU
    'ADDI','ANDI','ORI','XORI','SLTI','SLTIU',
    'SLLI','SRLI','SRAI',
    'ADDIW','SLLIW','SRLIW','SRAIW',
    # RV64I Loads
    'LB','LH','LW','LBU','LHU','LD','LWU',
    # RV64I Stores
    'SB','SH','SW','SD',
    # RV64I Branches
    'BEQ','BNE','BLT','BGE','BLTU','BGEU',
    # RV64I U / J
    'LUI','AUIPC','JAL','JALR',
    # RV64I System
    'ECALL','EBREAK',
    # RV64M
    'MUL','MULH','MULHU','MULHSU','DIV','DIVU','REM','REMU',
    'MULW','DIVW','DIVUW','REMW','REMUW',
    # Pseudo
    'NOP','LI','MV','NEG','NEGW','NOT',
    'SEQZ','SNEZ','SLTZ','SGTZ',
    'BEQZ','BNEZ','BLEZ','BGEZ','BLTZ','BGTZ',
    'J','JR','RET','CALL','TAIL','LA',
}


# ═══════════════════════════════════════════════════════════════════════════════
# SIMPLE EXPRESSION EVALUATOR  (for .equ and immediate expressions)
# ═══════════════════════════════════════════════════════════════════════════════

def eval_expr(expr: str, constants: Dict[str, int],
              line_num: int = None, line_text: str = None) -> int:
    """
    Evaluate a constant integer expression.
    Supports: decimal, 0x hex, 0b binary, +, -, *, /, %, <<, >>, (), unary -.
    Also resolves names from `constants` dict.
    """
    expr = expr.strip()
    if not expr:
        raise AssemblerError("Empty expression.", line_num, line_text)

    # Replace known constant names with their values (longest first to avoid partial subs)
    for name in sorted(constants.keys(), key=len, reverse=True):
        # word-boundary replacement
        expr = re.sub(r'\b' + re.escape(name) + r'\b', str(constants[name]), expr)

    # Allow only safe characters
    if not re.match(r'^[\d\s\+\-\*\/\%\<\>\(\)\|&\^~xXbBoO]+$', expr):
        raise AssemblerError(
            f"Invalid characters in expression: '{expr}'",
            line_num, line_text)
    try:
        # Use Python's eval with restricted builtins
        result = eval(expr, {"__builtins__": {}})  # noqa
        return int(result)
    except Exception as e:
        raise AssemblerError(
            f"Cannot evaluate expression '{expr}': {e}",
            line_num, line_text)


# ═══════════════════════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

def parse_reg(name: str, line_num=None, line_text=None) -> int:
    name = name.strip().lower()
    if not name:
        raise AssemblerError("Expected a register name but got empty string.",
                             line_num, line_text)
    if name not in REGISTERS:
        hint = ""
        if name.startswith("r") and name[1:].isdigit():
            hint = f" (use 'x{name[1:]}' — RISC-V uses x-prefix)"
        elif name in ("eax","ebx","ecx","edx","rax","rbx","rcx","rdx"):
            hint = " (x86 registers — RISC-V uses x0-x31 / ABI names)"
        raise AssemblerError(
            f"Unknown register: '{name}'{hint}\n"
            f"  Valid: x0-x31, zero, ra, sp, gp, tp, t0-t6, s0-s11, a0-a7, fp",
            line_num, line_text)
    return REGISTERS[name]


def parse_imm(token: str, labels: Dict[str, int], constants: Dict[str, int],
              current_pc: int = None, line_num=None, line_text=None) -> int:
    """
    Parse an immediate / label reference.
    For branch/jump labels: returns byte offset from current_pc.
    For data labels used in LA: returns absolute address.
    """
    token = token.strip()
    if not token:
        raise AssemblerError("Expected an immediate but got empty string.",
                             line_num, line_text)

    # Label reference
    if token in labels:
        addr = labels[token]
        if current_pc is not None:
            return addr - current_pc
        return addr

    # Looks like identifier → undefined label / constant
    if re.match(r'^[A-Za-z_][A-Za-z0-9_]*$', token):
        if token in constants:
            return constants[token]
        defined = list(labels.keys()) + list(constants.keys())
        raise AssemblerError(
            f"Undefined symbol: '{token}'\n"
            f"  Defined symbols: {defined if defined else '(none)'}",
            line_num, line_text)

    # Expression (may include +/- etc.)
    return eval_expr(token, constants, line_num, line_text)


def to_signed(value: int, bits: int) -> int:
    """Mask to `bits` bits then sign-extend."""
    value = value & ((1 << bits) - 1)
    if value >= (1 << (bits - 1)):
        value -= (1 << bits)
    return value


def check_range(value: int, bits: int, signed: bool, mnemonic: str,
                line_num=None, line_text=None):
    if signed:
        lo = -(1 << (bits - 1))
        hi =  (1 << (bits - 1)) - 1
    else:
        lo, hi = 0, (1 << bits) - 1
    if not (lo <= value <= hi):
        raise AssemblerError(
            f"Immediate {value} (0x{value & 0xFFFF_FFFF_FFFF_FFFF:X}) out of range "
            f"for {mnemonic}.\n"
            f"  {'Signed' if signed else 'Unsigned'} {bits}-bit range: [{lo}, {hi}].",
            line_num, line_text)


def split_operands(raw: str, line_num=None, line_text=None) -> List[str]:
    """
    Split operands string.
    Handles:
      "x1, x2, x3"        → ['x1','x2','x3']
      "x1, 4(x2)"         → ['x2','x1','4']      (load/store form)
      "x1, label"          → ['x1','label']
    """
    raw = raw.strip()
    # Detect offset(base) pattern at the end
    m = re.search(r'([-+]?[0-9A-Za-z_+\-\*\/\%\<\>\(\)]*)\((\w+)\)\s*$', raw)
    if m:
        offset   = m.group(1).strip() or '0'
        base_reg = m.group(2).strip()
        before   = raw[:m.start()].strip().rstrip(',')
        parts    = [p.strip() for p in before.split(',') if p.strip()]
        # order: [base, rd_or_rs, offset]
        return [base_reg] + parts + [offset]
    return [p.strip() for p in raw.split(',') if p.strip()]


def expect_ops(ops, count, mnemonic, syntax, line_num=None, line_text=None):
    if len(ops) != count:
        raise AssemblerError(
            f"'{mnemonic}' needs {count} operand(s), got {len(ops)}.\n"
            f"  Syntax: {mnemonic} {syntax}",
            line_num, line_text)


# ═══════════════════════════════════════════════════════════════════════════════
# INSTRUCTION ENCODERS
# ═══════════════════════════════════════════════════════════════════════════════

def enc_r(funct7, rs2, rs1, funct3, rd, opcode) -> int:
    return (((funct7 & 0x7F) << 25) | ((rs2 & 0x1F) << 20) |
            ((rs1   & 0x1F) << 15) | ((funct3 & 0x7) << 12) |
            ((rd    & 0x1F) <<  7) |  (opcode & 0x7F))

def enc_i(imm12, rs1, funct3, rd, opcode) -> int:
    return (((imm12  & 0xFFF) << 20) | ((rs1 & 0x1F) << 15) |
            ((funct3 & 0x7)   << 12) | ((rd  & 0x1F) <<  7) |
             (opcode & 0x7F))

def enc_s(imm12, rs2, rs1, funct3, opcode) -> int:
    return ((((imm12 >> 5) & 0x7F) << 25) | ((rs2 & 0x1F) << 20) |
            ((rs1 & 0x1F) << 15)           | ((funct3 & 0x7) << 12) |
            ((imm12 & 0x1F) << 7)          |  (opcode & 0x7F))

def enc_b(imm13, rs2, rs1, funct3, opcode) -> int:
    b12   = (imm13 >> 12) & 0x1
    b11   = (imm13 >> 11) & 0x1
    b10_5 = (imm13 >>  5) & 0x3F
    b4_1  = (imm13 >>  1) & 0xF
    return ((b12 << 31) | (b10_5 << 25) | ((rs2 & 0x1F) << 20) |
            ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) |
            (b4_1 << 8) | (b11 << 7) | (opcode & 0x7F))

def enc_u(imm20, rd, opcode) -> int:
    return (((imm20 & 0xFFFFF) << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F))

def enc_j(imm21, rd, opcode) -> int:
    b20    = (imm21 >> 20) & 0x1
    b19_12 = (imm21 >> 12) & 0xFF
    b11    = (imm21 >> 11) & 0x1
    b10_1  = (imm21 >>  1) & 0x3FF
    return ((b20 << 31) | (b10_1 << 21) | (b11 << 20) |
            (b19_12 << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F))


# ═══════════════════════════════════════════════════════════════════════════════
# SINGLE-INSTRUCTION ASSEMBLER
# Returns list of 32-bit ints (most instructions = 1, LA = 2)
# ═══════════════════════════════════════════════════════════════════════════════

def assemble_one(mnemonic: str, ops: List[str], pc: int,
                 labels: Dict[str, int], constants: Dict[str, int],
                 line_num=None, line_text=None) -> List[int]:
    """
    Encode one mnemonic + operand list.
    Returns a list of 32-bit words (usually 1, pseudo-instructions may return 2).
    """
    LN, LT = line_num, line_text

    # ── helpers that bind context ────────────────────────────────────────────
    def R(i) -> int:
        if i >= len(ops):
            raise AssemblerError(f"'{mnemonic}' missing operand #{i+1}.", LN, LT)
        return parse_reg(ops[i], LN, LT)

    def I(i, bits=12, signed=True, pc_rel=True) -> int:
        if i >= len(ops):
            raise AssemblerError(f"'{mnemonic}' missing operand #{i+1}.", LN, LT)
        v = parse_imm(ops[i], labels, constants,
                      pc if pc_rel else None, LN, LT)
        check_range(v, bits, signed, mnemonic, LN, LT)
        return to_signed(v, bits) if signed else (v & ((1 << bits) - 1))

    def SHAMT(i, bits=6) -> int:
        """Parse shift amount (unsigned, 0..63 for RV64, 0..31 for *W)."""
        if i >= len(ops):
            raise AssemblerError(f"'{mnemonic}' missing operand #{i+1}.", LN, LT)
        v = parse_imm(ops[i], labels, constants, None, LN, LT)
        hi = (1 << bits) - 1
        if not (0 <= v <= hi):
            raise AssemblerError(
                f"Shift amount {v} out of range [0, {hi}] for {mnemonic}.", LN, LT)
        return v & hi

    def BRANCH_OFF(i) -> int:
        if i >= len(ops):
            raise AssemblerError(f"'{mnemonic}' missing operand #{i+1}.", LN, LT)
        off = parse_imm(ops[i], labels, constants, pc, LN, LT)
        if off % 2 != 0:
            raise AssemblerError(
                f"Branch offset {off} is not 2-byte aligned.", LN, LT)
        check_range(off, 13, True, mnemonic, LN, LT)
        return off & 0x1FFF

    def JUMP_OFF(i, bits=21) -> int:
        if i >= len(ops):
            raise AssemblerError(f"'{mnemonic}' missing operand #{i+1}.", LN, LT)
        off = parse_imm(ops[i], labels, constants, pc, LN, LT)
        if off % 2 != 0:
            raise AssemblerError(
                f"Jump offset {off} is not 2-byte aligned.", LN, LT)
        check_range(off, bits, True, mnemonic, LN, LT)
        return off & ((1 << bits) - 1)

    def U_IMM(i) -> int:
        if i >= len(ops):
            raise AssemblerError(f"'{mnemonic}' missing operand #{i+1}.", LN, LT)
        raw = parse_imm(ops[i], labels, constants, None, LN, LT)
        # Accept either a full 32-bit address or a 20-bit upper immediate
        upper = (raw >> 12) & 0xFFFFF
        return upper

    # ────────────────────────────────────────────────────────────────────────
    # RV64I  R-type  (opcode 0110011 = 0x33)
    # ────────────────────────────────────────────────────────────────────────
    if mnemonic == 'ADD':
        expect_ops(ops, 3, mnemonic, "rd, rs1, rs2", LN, LT)
        return [enc_r(0x00, R(2), R(1), 0x0, R(0), 0x33)]
    if mnemonic == 'SUB':
        expect_ops(ops, 3, mnemonic, "rd, rs1, rs2", LN, LT)
        return [enc_r(0x20, R(2), R(1), 0x0, R(0), 0x33)]
    if mnemonic == 'SLL':
        expect_ops(ops, 3, mnemonic, "rd, rs1, rs2", LN, LT)
        return [enc_r(0x00, R(2), R(1), 0x1, R(0), 0x33)]
    if mnemonic == 'SLT':
        expect_ops(ops, 3, mnemonic, "rd, rs1, rs2", LN, LT)
        return [enc_r(0x00, R(2), R(1), 0x2, R(0), 0x33)]
    if mnemonic == 'SLTU':
        expect_ops(ops, 3, mnemonic, "rd, rs1, rs2", LN, LT)
        return [enc_r(0x00, R(2), R(1), 0x3, R(0), 0x33)]
    if mnemonic == 'XOR':
        expect_ops(ops, 3, mnemonic, "rd, rs1, rs2", LN, LT)
        return [enc_r(0x00, R(2), R(1), 0x4, R(0), 0x33)]
    if mnemonic == 'SRL':
        expect_ops(ops, 3, mnemonic, "rd, rs1, rs2", LN, LT)
        return [enc_r(0x00, R(2), R(1), 0x5, R(0), 0x33)]
    if mnemonic == 'SRA':
        expect_ops(ops, 3, mnemonic, "rd, rs1, rs2", LN, LT)
        return [enc_r(0x20, R(2), R(1), 0x5, R(0), 0x33)]
    if mnemonic == 'OR':
        expect_ops(ops, 3, mnemonic, "rd, rs1, rs2", LN, LT)
        return [enc_r(0x00, R(2), R(1), 0x6, R(0), 0x33)]
    if mnemonic == 'AND':
        expect_ops(ops, 3, mnemonic, "rd, rs1, rs2", LN, LT)
        return [enc_r(0x00, R(2), R(1), 0x7, R(0), 0x33)]

    # ── RV64I *W R-type  (opcode 0111011 = 0x3B) ────────────────────────────
    if mnemonic == 'ADDW':
        expect_ops(ops, 3, mnemonic, "rd, rs1, rs2", LN, LT)
        return [enc_r(0x00, R(2), R(1), 0x0, R(0), 0x3B)]
    if mnemonic == 'SUBW':
        expect_ops(ops, 3, mnemonic, "rd, rs1, rs2", LN, LT)
        return [enc_r(0x20, R(2), R(1), 0x0, R(0), 0x3B)]
    if mnemonic == 'SLLW':
        expect_ops(ops, 3, mnemonic, "rd, rs1, rs2", LN, LT)
        return [enc_r(0x00, R(2), R(1), 0x1, R(0), 0x3B)]
    if mnemonic == 'SRLW':
        expect_ops(ops, 3, mnemonic, "rd, rs1, rs2", LN, LT)
        return [enc_r(0x00, R(2), R(1), 0x5, R(0), 0x3B)]
    if mnemonic == 'SRAW':
        expect_ops(ops, 3, mnemonic, "rd, rs1, rs2", LN, LT)
        return [enc_r(0x20, R(2), R(1), 0x5, R(0), 0x3B)]

    # ── RV64M R-type  (opcode 0110011, funct7 = 0000001 = 0x01) ────────────
    if mnemonic == 'MUL':
        expect_ops(ops, 3, mnemonic, "rd, rs1, rs2", LN, LT)
        return [enc_r(0x01, R(2), R(1), 0x0, R(0), 0x33)]
    if mnemonic == 'MULH':
        expect_ops(ops, 3, mnemonic, "rd, rs1, rs2", LN, LT)
        return [enc_r(0x01, R(2), R(1), 0x1, R(0), 0x33)]
    if mnemonic == 'MULHSU':
        expect_ops(ops, 3, mnemonic, "rd, rs1, rs2", LN, LT)
        return [enc_r(0x01, R(2), R(1), 0x2, R(0), 0x33)]
    if mnemonic == 'MULHU':
        expect_ops(ops, 3, mnemonic, "rd, rs1, rs2", LN, LT)
        return [enc_r(0x01, R(2), R(1), 0x3, R(0), 0x33)]
    if mnemonic == 'DIV':
        expect_ops(ops, 3, mnemonic, "rd, rs1, rs2", LN, LT)
        return [enc_r(0x01, R(2), R(1), 0x4, R(0), 0x33)]
    if mnemonic == 'DIVU':
        expect_ops(ops, 3, mnemonic, "rd, rs1, rs2", LN, LT)
        return [enc_r(0x01, R(2), R(1), 0x5, R(0), 0x33)]
    if mnemonic == 'REM':
        expect_ops(ops, 3, mnemonic, "rd, rs1, rs2", LN, LT)
        return [enc_r(0x01, R(2), R(1), 0x6, R(0), 0x33)]
    if mnemonic == 'REMU':
        expect_ops(ops, 3, mnemonic, "rd, rs1, rs2", LN, LT)
        return [enc_r(0x01, R(2), R(1), 0x7, R(0), 0x33)]

    # ── RV64M *W R-type  (opcode 0111011 = 0x3B, funct7 = 0x01) ────────────
    if mnemonic == 'MULW':
        expect_ops(ops, 3, mnemonic, "rd, rs1, rs2", LN, LT)
        return [enc_r(0x01, R(2), R(1), 0x0, R(0), 0x3B)]
    if mnemonic == 'DIVW':
        expect_ops(ops, 3, mnemonic, "rd, rs1, rs2", LN, LT)
        return [enc_r(0x01, R(2), R(1), 0x4, R(0), 0x3B)]
    if mnemonic == 'DIVUW':
        expect_ops(ops, 3, mnemonic, "rd, rs1, rs2", LN, LT)
        return [enc_r(0x01, R(2), R(1), 0x5, R(0), 0x3B)]
    if mnemonic == 'REMW':
        expect_ops(ops, 3, mnemonic, "rd, rs1, rs2", LN, LT)
        return [enc_r(0x01, R(2), R(1), 0x6, R(0), 0x3B)]
    if mnemonic == 'REMUW':
        expect_ops(ops, 3, mnemonic, "rd, rs1, rs2", LN, LT)
        return [enc_r(0x01, R(2), R(1), 0x7, R(0), 0x3B)]

    # ────────────────────────────────────────────────────────────────────────
    # RV64I  I-type ALU  (opcode 0010011 = 0x13)
    # ────────────────────────────────────────────────────────────────────────
    if mnemonic == 'ADDI':
        expect_ops(ops, 3, mnemonic, "rd, rs1, imm12", LN, LT)
        return [enc_i(I(2) & 0xFFF, R(1), 0x0, R(0), 0x13)]
    if mnemonic == 'SLTI':
        expect_ops(ops, 3, mnemonic, "rd, rs1, imm12", LN, LT)
        return [enc_i(I(2) & 0xFFF, R(1), 0x2, R(0), 0x13)]
    if mnemonic == 'SLTIU':
        expect_ops(ops, 3, mnemonic, "rd, rs1, imm12", LN, LT)
        return [enc_i(I(2) & 0xFFF, R(1), 0x3, R(0), 0x13)]
    if mnemonic == 'XORI':
        expect_ops(ops, 3, mnemonic, "rd, rs1, imm12", LN, LT)
        return [enc_i(I(2) & 0xFFF, R(1), 0x4, R(0), 0x13)]
    if mnemonic == 'ORI':
        expect_ops(ops, 3, mnemonic, "rd, rs1, imm12", LN, LT)
        return [enc_i(I(2) & 0xFFF, R(1), 0x6, R(0), 0x13)]
    if mnemonic == 'ANDI':
        expect_ops(ops, 3, mnemonic, "rd, rs1, imm12", LN, LT)
        return [enc_i(I(2) & 0xFFF, R(1), 0x7, R(0), 0x13)]

    # ── RV64I 64-bit shifts  (shamt[5:0], funct7[6:1] selects op) ───────────
    if mnemonic == 'SLLI':
        expect_ops(ops, 3, mnemonic, "rd, rs1, shamt[0..63]", LN, LT)
        sh = SHAMT(2, 6)
        return [enc_i((0b000000 << 6) | sh, R(1), 0x1, R(0), 0x13)]
    if mnemonic == 'SRLI':
        expect_ops(ops, 3, mnemonic, "rd, rs1, shamt[0..63]", LN, LT)
        sh = SHAMT(2, 6)
        return [enc_i((0b000000 << 6) | sh, R(1), 0x5, R(0), 0x13)]
    if mnemonic == 'SRAI':
        expect_ops(ops, 3, mnemonic, "rd, rs1, shamt[0..63]", LN, LT)
        sh = SHAMT(2, 6)
        return [enc_i((0b010000 << 6) | sh, R(1), 0x5, R(0), 0x13)]

    # ── RV64I *W I-type  (opcode 0011011 = 0x1B) ────────────────────────────
    if mnemonic == 'ADDIW':
        expect_ops(ops, 3, mnemonic, "rd, rs1, imm12", LN, LT)
        return [enc_i(I(2) & 0xFFF, R(1), 0x0, R(0), 0x1B)]
    if mnemonic == 'SLLIW':
        expect_ops(ops, 3, mnemonic, "rd, rs1, shamt[0..31]", LN, LT)
        sh = SHAMT(2, 5)
        return [enc_i((0b0000000 << 5) | sh, R(1), 0x1, R(0), 0x1B)]
    if mnemonic == 'SRLIW':
        expect_ops(ops, 3, mnemonic, "rd, rs1, shamt[0..31]", LN, LT)
        sh = SHAMT(2, 5)
        return [enc_i((0b0000000 << 5) | sh, R(1), 0x5, R(0), 0x1B)]
    if mnemonic == 'SRAIW':
        expect_ops(ops, 3, mnemonic, "rd, rs1, shamt[0..31]", LN, LT)
        sh = SHAMT(2, 5)
        return [enc_i((0b0100000 << 5) | sh, R(1), 0x5, R(0), 0x1B)]

    # ────────────────────────────────────────────────────────────────────────
    # RV64I  Loads  (opcode 0000011 = 0x03)
    # split_operands returns [base, rd, offset]
    # ────────────────────────────────────────────────────────────────────────
    LOAD_F3 = {'LB':0x0,'LH':0x1,'LW':0x2,'LD':0x3,'LBU':0x4,'LHU':0x5,'LWU':0x6}
    if mnemonic in LOAD_F3:
        expect_ops(ops, 3, mnemonic, "rd, offset(rs1)", LN, LT)
        return [enc_i(I(2) & 0xFFF, R(0), LOAD_F3[mnemonic], R(1), 0x03)]

    # ────────────────────────────────────────────────────────────────────────
    # RV64I  Stores  (opcode 0100011 = 0x23)
    # split_operands returns [base, rs2, offset]
    # ────────────────────────────────────────────────────────────────────────
    STORE_F3 = {'SB':0x0,'SH':0x1,'SW':0x2,'SD':0x3}
    if mnemonic in STORE_F3:
        expect_ops(ops, 3, mnemonic, "rs2, offset(rs1)", LN, LT)
        return [enc_s(I(2) & 0xFFF, R(1), R(0), STORE_F3[mnemonic], 0x23)]

    # ────────────────────────────────────────────────────────────────────────
    # RV64I  Branches  (opcode 1100011 = 0x63)
    # ────────────────────────────────────────────────────────────────────────
    BRANCH_F3 = {'BEQ':0x0,'BNE':0x1,'BLT':0x4,'BGE':0x5,'BLTU':0x6,'BGEU':0x7}
    if mnemonic in BRANCH_F3:
        expect_ops(ops, 3, mnemonic, "rs1, rs2, label", LN, LT)
        return [enc_b(BRANCH_OFF(2), R(1), R(0), BRANCH_F3[mnemonic], 0x63)]

    # ────────────────────────────────────────────────────────────────────────
    # RV64I  U-type
    # ────────────────────────────────────────────────────────────────────────
    if mnemonic == 'LUI':
        expect_ops(ops, 2, mnemonic, "rd, imm20", LN, LT)
        return [enc_u(U_IMM(1), R(0), 0x37)]
    if mnemonic == 'AUIPC':
        expect_ops(ops, 2, mnemonic, "rd, imm20", LN, LT)
        return [enc_u(U_IMM(1), R(0), 0x17)]

    # ────────────────────────────────────────────────────────────────────────
    # RV64I  J-type / JALR
    # ────────────────────────────────────────────────────────────────────────
    if mnemonic == 'JAL':
        expect_ops(ops, 2, mnemonic, "rd, label", LN, LT)
        return [enc_j(JUMP_OFF(1, 21), R(0), 0x6F)]
    if mnemonic == 'JALR':
        expect_ops(ops, 3, mnemonic, "rd, rs1, imm12  or  rd, imm12(rs1)", LN, LT)
        return [enc_i(I(2) & 0xFFF, R(1), 0x0, R(0), 0x67)]

    # ────────────────────────────────────────────────────────────────────────
    # RV64I  System
    # ────────────────────────────────────────────────────────────────────────
    if mnemonic == 'ECALL':
        return [enc_i(0x000, 0, 0x0, 0, 0x73)]
    if mnemonic == 'EBREAK':
        return [enc_i(0x001, 0, 0x0, 0, 0x73)]

    # ────────────────────────────────────────────────────────────────────────
    # PSEUDO-INSTRUCTIONS
    # ────────────────────────────────────────────────────────────────────────

    # NOP → ADDI x0, x0, 0
    if mnemonic == 'NOP':
        return [enc_i(0, 0, 0x0, 0, 0x13)]

    # MV rd, rs → ADDI rd, rs, 0
    if mnemonic == 'MV':
        expect_ops(ops, 2, mnemonic, "rd, rs", LN, LT)
        return [enc_i(0, R(1), 0x0, R(0), 0x13)]

    # NEG rd, rs → SUB rd, x0, rs
    if mnemonic == 'NEG':
        expect_ops(ops, 2, mnemonic, "rd, rs", LN, LT)
        return [enc_r(0x20, R(1), 0, 0x0, R(0), 0x33)]

    # NEGW rd, rs → SUBW rd, x0, rs
    if mnemonic == 'NEGW':
        expect_ops(ops, 2, mnemonic, "rd, rs", LN, LT)
        return [enc_r(0x20, R(1), 0, 0x0, R(0), 0x3B)]

    # NOT rd, rs → XORI rd, rs, -1
    if mnemonic == 'NOT':
        expect_ops(ops, 2, mnemonic, "rd, rs", LN, LT)
        return [enc_i(0xFFF, R(1), 0x4, R(0), 0x13)]   # -1 in 12-bit = 0xFFF

    # SEQZ rd, rs → SLTIU rd, rs, 1
    if mnemonic == 'SEQZ':
        expect_ops(ops, 2, mnemonic, "rd, rs", LN, LT)
        return [enc_i(1, R(1), 0x3, R(0), 0x13)]

    # SNEZ rd, rs → SLTU rd, x0, rs
    if mnemonic == 'SNEZ':
        expect_ops(ops, 2, mnemonic, "rd, rs", LN, LT)
        return [enc_r(0x00, R(1), 0, 0x3, R(0), 0x33)]

    # SLTZ rd, rs → SLT rd, rs, x0
    if mnemonic == 'SLTZ':
        expect_ops(ops, 2, mnemonic, "rd, rs", LN, LT)
        return [enc_r(0x00, 0, R(1), 0x2, R(0), 0x33)]

    # SGTZ rd, rs → SLT rd, x0, rs
    if mnemonic == 'SGTZ':
        expect_ops(ops, 2, mnemonic, "rd, rs", LN, LT)
        return [enc_r(0x00, R(1), 0, 0x2, R(0), 0x33)]

    # LI rd, imm  — accepts any 32-bit immediate (expands to LUI+ADDI if needed)
    if mnemonic == 'LI':
        expect_ops(ops, 2, mnemonic, "rd, imm", LN, LT)
        v = parse_imm(ops[1], labels, constants, None, LN, LT)
        rd_n = R(0)
        lo12 = to_signed(v & 0xFFF, 12)   # sign-extended low 12
        hi20 = ((v - lo12) >> 12) & 0xFFFFF
        if hi20 == 0:
            # Fits in 12-bit signed immediate → single ADDI
            return [enc_i(v & 0xFFF, 0, 0x0, rd_n, 0x13)]
        else:
            # LUI rd, hi20 ; ADDI rd, rd, lo12
            lui  = enc_u(hi20, rd_n, 0x37)
            addi = enc_i(lo12 & 0xFFF, rd_n, 0x0, rd_n, 0x13)
            return [lui, addi]

    # LA rd, symbol  → AUIPC rd, %hi(sym) ; ADDI rd, rd, %lo(sym)
    if mnemonic == 'LA':
        expect_ops(ops, 2, mnemonic, "rd, symbol", LN, LT)
        rd_n = R(0)
        sym  = ops[1].strip()
        # Resolve symbol absolute address (no pc-rel for label lookup here)
        if sym in labels:
            addr = labels[sym]
        elif sym in constants:
            addr = constants[sym]
        else:
            raise AssemblerError(f"Undefined symbol for LA: '{sym}'", LN, LT)
        offset = addr - pc           # pc-relative offset
        lo12   = to_signed(offset & 0xFFF, 12)
        hi20   = ((offset - lo12) >> 12) & 0xFFFFF
        auipc  = enc_u(hi20, rd_n, 0x17)
        addi   = enc_i(lo12 & 0xFFF, rd_n, 0x0, rd_n, 0x13)
        return [auipc, addi]

    # ── One-register branches (pseudo) ───────────────────────────────────────

    # BEQZ rs, label → BEQ rs, x0, label
    if mnemonic == 'BEQZ':
        expect_ops(ops, 2, mnemonic, "rs, label", LN, LT)
        return [enc_b(BRANCH_OFF(1), 0, R(0), 0x0, 0x63)]

    # BNEZ rs, label → BNE rs, x0, label
    if mnemonic == 'BNEZ':
        expect_ops(ops, 2, mnemonic, "rs, label", LN, LT)
        return [enc_b(BRANCH_OFF(1), 0, R(0), 0x1, 0x63)]

    # BLEZ rs, label → BGE x0, rs, label
    if mnemonic == 'BLEZ':
        expect_ops(ops, 2, mnemonic, "rs, label", LN, LT)
        return [enc_b(BRANCH_OFF(1), R(0), 0, 0x5, 0x63)]

    # BGEZ rs, label → BGE rs, x0, label
    if mnemonic == 'BGEZ':
        expect_ops(ops, 2, mnemonic, "rs, label", LN, LT)
        return [enc_b(BRANCH_OFF(1), 0, R(0), 0x5, 0x63)]

    # BLTZ rs, label → BLT rs, x0, label
    if mnemonic == 'BLTZ':
        expect_ops(ops, 2, mnemonic, "rs, label", LN, LT)
        return [enc_b(BRANCH_OFF(1), 0, R(0), 0x4, 0x63)]

    # BGTZ rs, label → BLT x0, rs, label
    if mnemonic == 'BGTZ':
        expect_ops(ops, 2, mnemonic, "rs, label", LN, LT)
        return [enc_b(BRANCH_OFF(1), R(0), 0, 0x4, 0x63)]

    # J label → JAL x0, label
    if mnemonic == 'J':
        expect_ops(ops, 1, mnemonic, "label", LN, LT)
        return [enc_j(JUMP_OFF(0, 21), 0, 0x6F)]

    # JR rs → JALR x0, rs, 0
    if mnemonic == 'JR':
        expect_ops(ops, 1, mnemonic, "rs", LN, LT)
        return [enc_i(0, R(0), 0x0, 0, 0x67)]

    # RET → JALR x0, ra, 0
    if mnemonic == 'RET':
        return [enc_i(0, 1, 0x0, 0, 0x67)]

    # CALL label → JAL ra, label   (near call — fits in 21-bit)
    if mnemonic == 'CALL':
        expect_ops(ops, 1, mnemonic, "label", LN, LT)
        return [enc_j(JUMP_OFF(0, 21), 1, 0x6F)]

    # TAIL label → JAL x0, label   (tail call — no return)
    if mnemonic == 'TAIL':
        expect_ops(ops, 1, mnemonic, "label", LN, LT)
        return [enc_j(JUMP_OFF(0, 21), 0, 0x6F)]

    # ────────────────────────────────────────────────────────────────────────
    # Unknown mnemonic
    # ────────────────────────────────────────────────────────────────────────
    suggestions = sorted(
        m for m in ALL_MNEMONICS
        if mnemonic[:3] in m or m.startswith(mnemonic[:3])
    )
    hint = f"\n  Did you mean: {', '.join(suggestions[:6])}?" if suggestions else ""
    raise AssemblerError(
        f"Unknown mnemonic: '{mnemonic}'{hint}\n"
        f"  Supported: {', '.join(sorted(ALL_MNEMONICS))}",
        LN, LT)


# ═══════════════════════════════════════════════════════════════════════════════
# DIRECTIVE HANDLER  —  processes .byte / .word / .ascii etc. into data bytes
# ═══════════════════════════════════════════════════════════════════════════════

def handle_directive(directive: str, args: str,
                     data_bytes: bytearray, constants: Dict[str, int],
                     line_num=None, line_text=None):
    """
    Handle data-section directives.
    Appends emitted bytes to `data_bytes`.
    Returns number of bytes emitted (for PC tracking — 0 for non-data directives).
    """
    d = directive.lower()

    if d in ('.byte',):
        tokens = [t.strip() for t in args.split(',') if t.strip()]
        for tok in tokens:
            v = eval_expr(tok, constants, line_num, line_text) & 0xFF
            data_bytes.append(v)
        return len(tokens)

    if d in ('.half', '.2byte'):
        tokens = [t.strip() for t in args.split(',') if t.strip()]
        for tok in tokens:
            v = eval_expr(tok, constants, line_num, line_text) & 0xFFFF
            data_bytes += struct.pack('<H', v)
        return len(tokens) * 2

    if d in ('.word', '.4byte'):
        tokens = [t.strip() for t in args.split(',') if t.strip()]
        for tok in tokens:
            v = eval_expr(tok, constants, line_num, line_text) & 0xFFFF_FFFF
            data_bytes += struct.pack('<I', v)
        return len(tokens) * 4

    if d in ('.dword', '.8byte', '.quad'):
        tokens = [t.strip() for t in args.split(',') if t.strip()]
        for tok in tokens:
            v = eval_expr(tok, constants, line_num, line_text) & 0xFFFF_FFFF_FFFF_FFFF
            data_bytes += struct.pack('<Q', v)
        return len(tokens) * 8

    if d in ('.ascii',):
        s = _parse_string(args, line_num, line_text)
        enc = s.encode('utf-8')
        data_bytes += enc
        return len(enc)

    if d in ('.asciz', '.string'):
        s = _parse_string(args, line_num, line_text)
        enc = s.encode('utf-8') + b'\x00'
        data_bytes += enc
        return len(enc)

    if d in ('.zero', '.space'):
        n = eval_expr(args.strip(), constants, line_num, line_text)
        if n < 0:
            raise AssemblerError(f".zero count cannot be negative: {n}", line_num, line_text)
        data_bytes += b'\x00' * n
        return n

    if d in ('.align', '.balign'):
        # .align N → align current position to 2^N boundary  (GNU .align semantics)
        n = eval_expr(args.strip(), constants, line_num, line_text)
        alignment = (1 << n) if d == '.align' else n
        cur = len(data_bytes)
        pad = (-cur) % alignment if alignment > 0 else 0
        data_bytes += b'\x00' * pad
        return pad

    # Ignored directives (no bytes emitted)
    if d in ('.text', '.data', '.bss', '.global', '.globl', '.extern',
             '.section', '.file', '.type', '.size', '.ident', '.option',
             '.attribute'):
        return 0

    # Unknown directive — warn but don't fatal
    print(f"[WARN] Line {line_num}: unknown directive '{directive}' ignored.",
          file=sys.stderr)
    return 0


def _parse_string(raw: str, line_num=None, line_text=None) -> str:
    """Extract the string between the outermost quotes, handling escape sequences."""
    raw = raw.strip()
    m = re.match(r'^"(.*)"$', raw, re.DOTALL)
    if not m:
        raise AssemblerError(
            f"Malformed string literal: {raw!r}\n  Must be enclosed in double quotes.",
            line_num, line_text)
    s = m.group(1)
    # Unescape common sequences
    escape_map = {
        'n': '\n', 't': '\t', 'r': '\r', '\\': '\\',
        '"': '"',  "'": "'",  '0': '\0',  'a': '\a',
        'b': '\b', 'f': '\f', 'v': '\v',
    }
    result = []
    i = 0
    while i < len(s):
        if s[i] == '\\' and i + 1 < len(s):
            ch = s[i + 1]
            if ch in escape_map:
                result.append(escape_map[ch])
                i += 2
            elif ch == 'x' and i + 3 < len(s):
                hex_val = s[i+2:i+4]
                try:
                    result.append(chr(int(hex_val, 16)))
                    i += 4
                except ValueError:
                    result.append('\\' + ch)
                    i += 2
            else:
                result.append('\\' + ch)
                i += 2
        else:
            result.append(s[i])
            i += 1
    return ''.join(result)


# ═══════════════════════════════════════════════════════════════════════════════
# TWO-PASS ASSEMBLER
# ═══════════════════════════════════════════════════════════════════════════════

class Section:
    TEXT = 'text'
    DATA = 'data'
    BSS  = 'bss'


def assemble(source_text: str) -> Tuple[List[int], bytes, Dict[str, int]]:
    """
    Full two-pass assembly.

    Returns:
        (words, data_bytes, symbols)
        words      — list of 32-bit instruction words
        data_bytes — raw data section content
        symbols    — label → address dict
    """
    lines   = source_text.splitlines()
    errors  = []

    # ── shared state ─────────────────────────────────────────────────────────
    labels    : Dict[str, int]  = {}   # symbol → byte address
    constants : Dict[str, int]  = {}   # .equ / .set symbols
    globals_  : set             = set()

    # We track two separate program counters:
    text_pc = TEXT_BASE
    data_pc = DATA_BASE

    current_section = Section.TEXT
    data_bytes       = bytearray()

    # ── line cleaner ─────────────────────────────────────────────────────────
    def clean(raw: str) -> str:
        line = raw.split('#')[0].split(';')[0]
        return line.strip()

    # ── shared line parser (yields section, mnemonic_or_directive, ops, ...) ─
    def parse_line(line: str, line_num: int, raw: str):
        """
        Returns (label_name_or_None, directive_or_None, mnemonic_or_None, raw_ops).
        """
        label = None
        # Inline label  →  "label: instruction"
        if ':' in line:
            lbl_part, rest = line.split(':', 1)
            lbl_part = lbl_part.strip()
            if re.match(r'^[A-Za-z_\.][A-Za-z0-9_\.]*$', lbl_part):
                label = lbl_part
                line  = rest.strip()
            # else: colon might be inside an expression; ignore

        if not line:
            return label, None, None, ''

        parts     = line.split(None, 1)
        token     = parts[0]
        rest_args = parts[1].strip() if len(parts) > 1 else ''

        if token.startswith('.'):
            return label, token, None, rest_args   # directive
        return label, None, token.upper(), rest_args  # instruction

    # ─────────────────────────────────────────────────────────────────────────
    # PASS 1  —  collect labels, .equ constants, section layout
    # ─────────────────────────────────────────────────────────────────────────
    current_section = Section.TEXT
    text_pc = TEXT_BASE
    data_pc = DATA_BASE

    for line_num, raw in enumerate(lines, 1):
        line = clean(raw)
        if not line:
            continue

        label, directive, mnemonic, args = parse_line(line, line_num, raw)

        # Register label
        if label:
            addr = text_pc if current_section == Section.TEXT else data_pc
            if label in labels:
                errors.append(AssemblerError(
                    f"Duplicate label: '{label}' (previously at 0x{labels[label]:08X})",
                    line_num, raw))
            else:
                labels[label] = addr

        if directive:
            d = directive.lower()

            # Section switches
            if d == '.text':
                current_section = Section.TEXT; continue
            if d in ('.data', '.rodata'):
                current_section = Section.DATA; continue
            if d == '.bss':
                current_section = Section.BSS; continue

            # .equ / .set
            if d in ('.equ', '.set'):
                m = re.match(r'(\w+)\s*,\s*(.+)', args)
                if not m:
                    errors.append(AssemblerError(
                        f"Bad .equ syntax: expected 'name, value'", line_num, raw))
                    continue
                cname  = m.group(1).strip()
                cval   = eval_expr(m.group(2).strip(), constants, line_num, raw)
                constants[cname] = cval
                labels[cname]    = cval    # also exportable
                continue

            # .global / .globl
            if d in ('.global', '.globl'):
                for sym in args.split(','):
                    globals_.add(sym.strip())
                continue

            # Data directives — advance data_pc
            if current_section in (Section.DATA, Section.BSS):
                tmp = bytearray()
                nb  = handle_directive(directive, args, tmp, constants, line_num, raw)
                data_pc += nb
            continue   # directives don't advance text_pc

        if mnemonic:
            if current_section == Section.TEXT:
                # Count words this instruction will produce
                # LA expands to 2, most are 1
                n = 2 if mnemonic == 'LA' or (mnemonic == 'LI') else 1
                # For LI we need to check the immediate — default 1, may expand to 2
                # We'll over-count to 2 for LI if the immediate can't be evaluated yet
                # Safe bet: always assume 1 for LI in pass1 (may fail for forward refs)
                if mnemonic == 'LI':
                    # Try to evaluate; if forward ref, assume 1 word
                    ops_p1 = split_operands(args, line_num, raw)
                    if len(ops_p1) >= 2:
                        try:
                            v = parse_imm(ops_p1[1], labels, constants,
                                          None, line_num, raw)
                            lo12 = to_signed(v & 0xFFF, 12)
                            hi20 = ((v - lo12) >> 12) & 0xFFFFF
                            n = 2 if hi20 != 0 else 1
                        except Exception:
                            n = 2  # be conservative
                    else:
                        n = 1
                elif mnemonic == 'LA':
                    n = 2  # always 2 words (AUIPC + ADDI)
                else:
                    n = 1
                text_pc += 4 * n

    # ─────────────────────────────────────────────────────────────────────────
    # PASS 2  —  encode instructions & collect data bytes
    # ─────────────────────────────────────────────────────────────────────────
    words: List[int]  = []
    data_bytes         = bytearray()
    current_section    = Section.TEXT
    text_pc            = TEXT_BASE
    data_pc            = DATA_BASE

    for line_num, raw in enumerate(lines, 1):
        line = clean(raw)
        if not line:
            continue

        label, directive, mnemonic, args = parse_line(line, line_num, raw)

        if directive:
            d = directive.lower()
            if d == '.text':
                current_section = Section.TEXT; continue
            if d in ('.data', '.rodata'):
                current_section = Section.DATA; continue
            if d == '.bss':
                current_section = Section.BSS; continue
            if d in ('.equ', '.set', '.global', '.globl', '.extern'):
                continue

            if current_section in (Section.DATA, Section.BSS):
                handle_directive(directive, args, data_bytes, constants, line_num, raw)
            continue

        if mnemonic:
            try:
                ops  = split_operands(args, line_num, raw)
                inst = assemble_one(mnemonic, ops, text_pc,
                                    labels, constants, line_num, raw)
                for w in inst:
                    words.append(w & 0xFFFF_FFFF)
                text_pc += 4 * len(inst)
            except AssemblerError as e:
                errors.append(e)
                words.append(NOP_WORD)  # placeholder
                text_pc += 4

    # ── Report errors ─────────────────────────────────────────────────────────
    if errors:
        sep = '=' * 64
        print(f"\n{sep}", file=sys.stderr)
        print(f"  Assembler found {len(errors)} error(s):", file=sys.stderr)
        print(sep, file=sys.stderr)
        for i, err in enumerate(errors, 1):
            print(f"\n[Error {i}]", file=sys.stderr)
            print(str(err), file=sys.stderr)
        print(f"\n{sep}", file=sys.stderr)
        print("  Assembly FAILED.  No output written.", file=sys.stderr)
        print(f"{sep}\n", file=sys.stderr)
        sys.exit(1)

    # Merge labels + constants into unified symbol table
    all_symbols = dict(constants)
    all_symbols.update(labels)

    return words, bytes(data_bytes), all_symbols


# ═══════════════════════════════════════════════════════════════════════════════
# OUTPUT WRITERS
# ═══════════════════════════════════════════════════════════════════════════════

def write_imem(words: List[int], path: str, pad_to: int = IMEM_PAD_WORDS):
    """Write instruction memory hex file — one 32-bit word (8 hex digits) per line."""
    lines = []
    for i in range(pad_to):
        w = words[i] if i < len(words) else NOP_WORD
        lines.append(f'{w:08x}')
    with open(path, 'w') as f:
        f.write('\n'.join(lines) + '\n')
    print(f"[imem] Wrote {len(words)} instruction(s) → '{path}'  "
          f"(padded to {pad_to} words)")


def write_dmem(data: bytes, path: str, pad_to: int = DMEM_PAD_BYTES):
    """Write data memory hex file — one byte (2 hex digits) per line."""
    lines = []
    for i in range(pad_to):
        b = data[i] if i < len(data) else 0
        lines.append(f'{b:02x}')
    with open(path, 'w') as f:
        f.write('\n'.join(lines) + '\n')
    print(f"[dmem] Wrote {len(data)} data byte(s)    → '{path}'  "
          f"(padded to {pad_to} bytes)")


def write_symbols(symbols: Dict[str, int], path: str):
    """Write symbol table for linker / debugger use."""
    with open(path, 'w') as f:
        f.write(f"# RV64IM Symbol Table\n")
        f.write(f"# {'Symbol':<30} {'Hex':>12}  {'Decimal':>12}\n")
        f.write(f"# {'-'*30} {'-'*12}  {'-'*12}\n")
        for name, addr in sorted(symbols.items(), key=lambda kv: kv[1]):
            f.write(f"  {name:<30} 0x{addr:016x}  {addr:>20}\n")
    print(f"[syms] Wrote {len(symbols)} symbol(s)     → '{path}'")


# ═══════════════════════════════════════════════════════════════════════════════
# DISASSEMBLER
# ═══════════════════════════════════════════════════════════════════════════════

def disassemble(words: List[int], base: int = TEXT_BASE):
    """Pretty-print disassembly of instruction words."""

    def r(n):
        return REG_NAMES[n & 0x1F]

    def sext12(v):
        return v - 0x1000 if v & 0x800 else v

    def sext13(v):
        return v - 0x2000 if v & 0x1000 else v

    def sext21(v):
        return v - 0x200000 if v & 0x100000 else v

    print(f"\n{'addr':>10}  {'hex':>10}  {'disassembly'}")
    print('-' * 60)

    for i, w in enumerate(words):
        addr   = base + i * 4
        opcode = w & 0x7F
        rd     = (w >>  7) & 0x1F
        f3     = (w >> 12) & 0x07
        rs1    = (w >> 15) & 0x1F
        rs2    = (w >> 20) & 0x1F
        f7     = (w >> 25) & 0x7F
        imm_i  = sext12((w >> 20) & 0xFFF)
        imm_u  = (w >> 12) & 0xFFFFF

        asm = '???'

        if opcode == 0x33:   # R-type (base + M)
            if f7 == 0x01:   # M extension
                op = {0:'mul',1:'mulh',2:'mulhsu',3:'mulhu',
                      4:'div',5:'divu',6:'rem',7:'remu'}.get(f3, '?m')
            else:
                op = {(0,0x00):'add',(0,0x20):'sub',(1,0x00):'sll',
                      (2,0x00):'slt',(3,0x00):'sltu',(4,0x00):'xor',
                      (5,0x00):'srl',(5,0x20):'sra',
                      (6,0x00):'or',(7,0x00):'and'}.get((f3,f7),'?r')
            asm = f'{op} {r(rd)}, {r(rs1)}, {r(rs2)}'

        elif opcode == 0x3B: # RV64 *W R-type (base + M)
            if f7 == 0x01:   # M *W
                op = {0:'mulw',4:'divw',5:'divuw',6:'remw',7:'remuw'}.get(f3,'?mw')
            else:
                op = {(0,0x00):'addw',(0,0x20):'subw',(1,0x00):'sllw',
                      (5,0x00):'srlw',(5,0x20):'sraw'}.get((f3,f7),'?rw')
            asm = f'{op} {r(rd)}, {r(rs1)}, {r(rs2)}'

        elif opcode == 0x13: # I-type ALU
            if f3 == 0x1:
                asm = f'slli {r(rd)}, {r(rs1)}, {rs2}'
            elif f3 == 0x5:
                op  = 'srai' if f7 & 0x20 else 'srli'
                asm = f'{op} {r(rd)}, {r(rs1)}, {rs2}'
            else:
                op  = {0:'addi',2:'slti',3:'sltiu',4:'xori',6:'ori',7:'andi'}.get(f3,'?i')
                asm = f'{op} {r(rd)}, {r(rs1)}, {imm_i}'

        elif opcode == 0x1B: # RV64 *W I-type
            if f3 == 0x1:
                asm = f'slliw {r(rd)}, {r(rs1)}, {rs2}'
            elif f3 == 0x5:
                op  = 'sraiw' if f7 & 0x20 else 'srliw'
                asm = f'{op} {r(rd)}, {r(rs1)}, {rs2}'
            elif f3 == 0x0:
                asm = f'addiw {r(rd)}, {r(rs1)}, {imm_i}'
            else:
                asm = '?iw'

        elif opcode == 0x03: # Loads
            op  = {0:'lb',1:'lh',2:'lw',3:'ld',4:'lbu',5:'lhu',6:'lwu'}.get(f3,'?l')
            asm = f'{op} {r(rd)}, {imm_i}({r(rs1)})'

        elif opcode == 0x23: # Stores
            imm_s = sext12(((w >> 25) << 5) | ((w >> 7) & 0x1F))
            op    = {0:'sb',1:'sh',2:'sw',3:'sd'}.get(f3,'?s')
            asm   = f'{op} {r(rs2)}, {imm_s}({r(rs1)})'

        elif opcode == 0x63: # Branches
            imm_b = sext13(((w>>31)<<12)|((w>>7&1)<<11)|
                           ((w>>25&0x3F)<<5)|((w>>8&0xF)<<1))
            op    = {0:'beq',1:'bne',4:'blt',5:'bge',6:'bltu',7:'bgeu'}.get(f3,'?b')
            asm   = f'{op} {r(rs1)}, {r(rs2)}, {imm_b:+d}'

        elif opcode == 0x37:
            asm = f'lui {r(rd)}, 0x{imm_u:05x}'

        elif opcode == 0x17:
            asm = f'auipc {r(rd)}, 0x{imm_u:05x}'

        elif opcode == 0x6F: # JAL
            imm_j = sext21(((w>>31)<<20)|((w>>12&0xFF)<<12)|
                           ((w>>20&1)<<11)|((w>>21&0x3FF)<<1))
            asm   = f'jal {r(rd)}, {imm_j:+d}'

        elif opcode == 0x67: # JALR
            asm = f'jalr {r(rd)}, {r(rs1)}, {imm_i}'

        elif opcode == 0x73: # System
            if w == 0x00000073: asm = 'ecall'
            elif w == 0x00100073: asm = 'ebreak'
            else: asm = f'csr? 0x{w:08x}'

        elif w == 0x00000013:
            asm = 'nop'

        print(f'0x{addr:08x}  0x{w:08x}  {asm}')


# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

def main():
    import argparse

    parser = argparse.ArgumentParser(
        description='RV64IM Assembler — produces imem.hex and dmem.hex',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 rv64im_assembler.py prog.asm
  python3 rv64im_assembler.py prog.asm --dis
  python3 rv64im_assembler.py prog.asm --imem my_imem.hex --dmem my_dmem.hex
        """)

    parser.add_argument('asm_file',
                        default='scripts\\test_env\\program.asm',
                        help='Input assembly source file (.asm)')
    parser.add_argument('--imem', default='memory\golden_instruction_memory.hex',
                        help='Instruction memory output file (default: imem.hex)')
    parser.add_argument('--dmem', default='memory\golden_data_memory.hex',
                        help='Data memory output file (default: dmem.hex)')
    parser.add_argument('--syms', default='symbols.txt',
                        help='Symbol table output file (default: symbols.txt)')
    parser.add_argument('--dis', action='store_true',
                        help='Print disassembly to stdout instead of writing files')
    parser.add_argument('--imem-size', type=int, default=IMEM_PAD_WORDS,
                        metavar='N',
                        help=f'Pad imem to N words (default: {IMEM_PAD_WORDS})')
    parser.add_argument('--dmem-size', type=int, default=DMEM_PAD_BYTES,
                        metavar='N',
                        help=f'Pad dmem to N bytes (default: {DMEM_PAD_BYTES})')

    args = parser.parse_args()

    # ── Read source ───────────────────────────────────────────────────────────
    try:
        with open(args.asm_file, 'r') as f:
            source = f.read()
    except FileNotFoundError:
        print(f"\nERROR: File not found: '{args.asm_file}'", file=sys.stderr)
        sys.exit(1)
    except PermissionError:
        print(f"\nERROR: Permission denied: '{args.asm_file}'", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"\nERROR reading '{args.asm_file}': {e}", file=sys.stderr)
        sys.exit(1)

    if not source.strip():
        print(f"\nERROR: '{args.asm_file}' is empty.", file=sys.stderr)
        sys.exit(1)

    # ── Assemble ──────────────────────────────────────────────────────────────
    words, data_bytes, symbols = assemble(source)

    # ── Output ────────────────────────────────────────────────────────────────
    if args.dis:
        print(f"\n=== Disassembly of '{args.asm_file}' ===")
        disassemble(words)
        if data_bytes:
            print(f"\n=== Data Section ({len(data_bytes)} bytes) ===")
            for i in range(0, len(data_bytes), 16):
                chunk = data_bytes[i:i+16]
                hex_s = ' '.join(f'{b:02x}' for b in chunk)
                asc_s = ''.join(chr(b) if 32 <= b < 127 else '.' for b in chunk)
                print(f'  0x{DATA_BASE+i:08x}  {hex_s:<48}  {asc_s}')
        if symbols:
            print(f"\n=== Symbol Table ===")
            for name, addr in sorted(symbols.items(), key=lambda kv: kv[1]):
                print(f"  {name:<30} 0x{addr:016x}")
    else:
        try:
            write_imem(words,    args.imem, args.imem_size)
            write_dmem(data_bytes, args.dmem, args.dmem_size)
            write_symbols(symbols, args.syms)
            print(f"\nAssembly successful.")
        except PermissionError as e:
            print(f"\nERROR: Permission denied writing output: {e}", file=sys.stderr)
            sys.exit(1)
        except Exception as e:
            print(f"\nERROR writing output: {e}", file=sys.stderr)
            sys.exit(1)


if __name__ == '__main__':
    main()
