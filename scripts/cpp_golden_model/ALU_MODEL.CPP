


#include<iostream>
#include <cstdint>
#include <cstdio>
#include <cassert>
using namespace std;
// ============================================================
//  RV64 ALU — Black Box Model
//  ─────────────────────────────────────────────────────────
//  Covers every arithmetic/logic operation needed by the
//  RV64I + RV64M instruction set.
//
//  Pipeline position :  EX stage
//  Latency           :  1 cycle (combinational inside tick)
//  Control source    :  ALU Control Unit → alu_op_i
//
//  Port diagram
//  ┌──────────────────────────────────────────────────────┐
//  │                      ALU                             │
//  │                                                      │
//  │  a_i      [63:0] ──►                                 │
//  │  b_i      [63:0] ──►  ┌──────────┐                   │
//  │  alu_op_i  [5:0] ──►  │  Execute │──► result_o       │
//  │  valid_i         ──►  │          │──► zero_o         │
//  │                       │          │──► neg_o          │
//  │  ◄── ready_o          │          │──► overflow_o     │
//  │  ◄── valid_o          └──────────┘──► carry_o        │
//  │  ready_i         ──►                                 │
//  └──────────────────────────────────────────────────────┘
//
//  ALU opcodes (alu_op_i) — driven by ALU Control Unit
//  ─────────────────────────────────────────────────────────
//  The ALU control unit maps {funct7, funct3, opcode_type}
//  to one of these ALU_OP codes.
//
//  ┌────┬──────────────┬─────────────────────────────────┐
//  │ Op │  Mnemonic    │  Operation                      │
//  ├────┼──────────────┼─────────────────────────────────┤
//  │ 00 │  ADD         │  a + b                          │
//  │ 01 │  SUB         │  a - b                          │
//  │ 02 │  AND         │  a & b                          │
//  │ 03 │  OR          │  a | b                          │
//  │ 04 │  XOR         │  a ^ b                          │
//  │ 05 │  SLL         │  a << b[5:0]                    │
//  │ 06 │  SRL         │  a >> b[5:0]  (logical)         │
//  │ 07 │  SRA         │  a >> b[5:0]  (arithmetic)      │
//  │ 08 │  SLT         │  (int64)a < (int64)b ? 1 : 0    │
//  │ 09 │  SLTU        │  (uint64)a < (uint64)b ? 1 : 0  │
//  │ 0A │  ADDW        │  sext32(a[31:0] + b[31:0])      │
//  │ 0B │  SUBW        │  sext32(a[31:0] - b[31:0])      │
//  │ 0C │  SLLW        │  sext32(a[31:0] << b[4:0])      │
//  │ 0D │  SRLW        │  sext32(a[31:0] >> b[4:0])      │
//  │ 0E │  SRAW        │  sext32((int32)a >> b[4:0])     │
//  │ 0F │  LUI_PASS    │  b  (pass b = upper-imm)        │
//  │ 10 │  AUIPC_ADD   │  a + b  (PC + upper-imm)        │
//  │ 11 │  MUL         │  (a * b)[63:0]                  │
//  │ 12 │  MULH        │  (int128)(a*b)[127:64]          │
//  │ 13 │  MULHU       │  (uint128)(a*b)[127:64]         │
//  │ 14 │  MULHSU      │  (signed×unsigned)[127:64]      │
//  │ 15 │  DIV         │  (int64)a / (int64)b            │
//  │ 16 │  DIVU        │  (uint64)a / (uint64)b          │
//  │ 17 │  REM         │  (int64)a % (int64)b            │
//  │ 18 │  REMU        │  (uint64)a % (uint64)b          │
//  │ 19 │  MULW        │  sext32(a[31:0] * b[31:0])      │
//  │ 1A │  DIVW        │  sext32((int32)a / (int32)b)    │
//  │ 1B │  DIVUW       │  sext32((uint32)a / (uint32)b)  │
//  │ 1C │  REMW        │  sext32((int32)a % (int32)b)    │
//  │ 1D │  REMUW       │  sext32((uint32)a % (uint32)b)  │
//  │ 1E │  PASS_A      │  a  (used by JAL/JALR: PC+4)    │
//  └────┴──────────────┴─────────────────────────────────┘
// ============================================================

// ── ALU opcode enum ──────────────────────────────────────────
#include "alu_op.h"

// ── helper: sign-extend 32-bit result to 64 bits ────────────
static inline uint64_t sext32(uint32_t v) {
    return static_cast<uint64_t>(static_cast<int64_t>(static_cast<int32_t>(v)));
}

// ── helper: 128-bit signed multiply ─────────────────────────
// GCC/Clang support __int128 natively
static inline uint64_t mulh_signed(int64_t a, int64_t b) {
    __int128 res = static_cast<__int128>(a) * static_cast<__int128>(b);
    return static_cast<uint64_t>(static_cast<unsigned __int128>(res) >> 64);
}
static inline uint64_t mulh_unsigned(uint64_t a, uint64_t b) {
    unsigned __int128 res = static_cast<unsigned __int128>(a) *
                            static_cast<unsigned __int128>(b);
    return static_cast<uint64_t>(res >> 64);
}
static inline uint64_t mulh_su(int64_t a, uint64_t b) {
    // signed × unsigned upper half
    __int128 res = static_cast<__int128>(a) *
                   static_cast<__int128>(static_cast<unsigned __int128>(b));
    return static_cast<uint64_t>(static_cast<unsigned __int128>(res) >> 64);
}


class ALU {


//  PUBLIC INTERFACE
public:

    // ── Input channel (driven by EX stage / forwarding mux) ──
    bool     valid_i  = false;   // upstream says inputs are valid
    bool     ready_i  = false;   // downstream (MEM/WB) can accept

    uint64_t a_i      = 0;       // operand A  (rs1 or PC)
    uint64_t b_i      = 0;       // operand B  (rs2 or immediate)
    ALU_OP   alu_op_i = ALU_OP::ALU_ADD; // operation select from ALU ctrl

    // ── Output channel ────────────────────────────────────────
    bool     valid_o    = false; // result is valid this cycle
    bool     ready_o    = false; // ALU can accept new inputs

    uint64_t result_o   = 0;     // primary result
    bool     zero_o     = false; // result == 0  (branch comparator)
    bool     neg_o      = false; // result[63]   (sign bit)
    bool     carry_o    = false; // unsigned carry out (ADD/SUB)
    bool     overflow_o = false; // signed overflow    (ADD/SUB)

    // ── Exception flags ───────────────────────────────────────
    bool     div_by_zero_o = false;  // DIV/REM by zero
    bool     div_overflow_o= false;  // MIN_INT / -1

    // ── Constructor ───────────────────────────────────────────
    ALU() { reset(); }

    void reset() {
        valid_i = false; ready_i = false;
        a_i = 0; b_i = 0; alu_op_i = ALU_OP::ALU_ADD;
        valid_o = false; ready_o = false;
        result_o = 0;
        zero_o = false; neg_o = false;
        carry_o = false; overflow_o = false;
        div_by_zero_o = false; div_overflow_o = false;
    }

    // ─────────────────────────────────────────────────────────
    //  tick()
    //  ──────
    //  Called once per clock cycle by the pipeline.
    //  Fully combinational inside — result is available
    //  in the same cycle (single-cycle EX stage).
    //
    //  Handshake:
    //    upstream  → valid_i  (I have valid operands)
    //    ALU       → ready_o  (I can compute this cycle)
    //    ALU       → valid_o  (result is valid)
    //    downstream→ ready_i  (I can accept result)
    //
    //  Transaction fires when valid_i & ready_o both high.
    //  Result consumed  when valid_o & ready_i both high.
    // ─────────────────────────────────────────────────────────
    void tick() {

        // ALU is always ready to accept (single cycle, no buffer)
        ready_o = true;

        // Default outputs
        valid_o      = false;
        result_o     = 0;
        zero_o       = false;
        neg_o        = false;
        carry_o      = false;
        overflow_o   = false;
        div_by_zero_o  = false;
        div_overflow_o = false;

        // ── Input handshake ──────────────────────────────────
        if (!valid_i || !ready_o) return;

        // ── Execute ──────────────────────────────────────────
        result_o = compute(a_i, b_i, alu_op_i);

        // ── Flag generation ───────────────────────────────────
        zero_o     = (result_o == 0);
        neg_o      = (result_o >> 63) & 1;

        // Carry & overflow only meaningful for ADD/SUB family
        if (alu_op_i == ALU_OP::ALU_ADD || alu_op_i == ALU_OP::ALU_AUIPC || alu_op_i == ALU_OP::ALU_ADDW) {
            // unsigned carry: check if 65-bit result overflowed
            unsigned __int128 ua = static_cast<unsigned __int128>(a_i) +
                                   static_cast<unsigned __int128>(b_i);
            carry_o    = (ua >> 64) & 1;
            // signed overflow: same sign inputs, different sign output
            int64_t sa = static_cast<int64_t>(a_i);
            int64_t sb = static_cast<int64_t>(b_i);
            int64_t sr = static_cast<int64_t>(result_o);
            overflow_o = ((sa > 0 && sb > 0 && sr < 0) ||
                          (sa < 0 && sb < 0 && sr > 0));
        }
        else if (alu_op_i == ALU_OP::ALU_SUB || alu_op_i == ALU_OP::ALU_SUBW) {
            unsigned __int128 ua = static_cast<unsigned __int128>(a_i) -
                                   static_cast<unsigned __int128>(b_i);
            carry_o    = (ua >> 64) & 1;   // borrow
            int64_t sa = static_cast<int64_t>(a_i);
            int64_t sb = static_cast<int64_t>(b_i);
            int64_t sr = static_cast<int64_t>(result_o);
            overflow_o = ((sa > 0 && sb < 0 && sr < 0) ||
                          (sa < 0 && sb > 0 && sr > 0));
        }

        // ── Output handshake ─────────────────────────────────
        valid_o = true;
        // Note: result is held until downstream asserts ready_i.
        // In a simple in-order pipeline this is always 1 cycle.
    }

    // ─────────────────────────────────────────────────────────
    //  Debug dump
    // ─────────────────────────────────────────────────────────
    void dump() const {
        static const char* op_names[] = {
            "ADD","SUB","AND","OR","XOR","SLL","SRL","SRA",
            "SLT","SLTU","ADDW","SUBW","SLLW","SRLW","SRAW",
            "LUI","AUIPC","MUL","MULH","MULHU","MULHSU",
            "DIV","DIVU","REM","REMU",
            "MULW","DIVW","DIVUW","REMW","REMUW","PASS_A"
        };
        printf("\n||===== ALU State ============================||\n");
        printf("║  op      = %-10s                              ||\n",
               (static_cast<uint8_t>(alu_op_i) < 0x1F) ? op_names[static_cast<uint8_t>(alu_op_i)] : "???");
        printf("||  a_i     = 0x%016llX                    ||\n", a_i);
        printf("||  b_i     = 0x%016llX                   ||\n", b_i);
        printf("||  result  = 0x%016llX                    ||\n", result_o);
        printf("||  flags   zero=%-1d  neg=%-1d  carry=%-1d  overflow=%-1d      ||\n",
               zero_o, neg_o, carry_o, overflow_o);
        printf("||  div_by_zero=%-1d  div_overflow=%-1d                    ||\n",
               div_by_zero_o, div_overflow_o);
        printf("||  valid_i=%-1d  ready_o=%-1d  valid_o=%-1d  ready_i=%-1d       ||\n",
               valid_i, ready_o, valid_o, ready_i);
        printf("==================================================================\n");
    }

// ──────────────────────────────────────────────────────────────
//  PRIVATE — execution core (invisible to pipeline)
// ──────────────────────────────────────────────────────────────
private:

    uint64_t compute(uint64_t a, uint64_t b, ALU_OP op) {

        // typed aliases — used heavily below
        const int64_t  sa  = static_cast<int64_t>(a);
        const int64_t  sb  = static_cast<int64_t>(b);
        const uint32_t wa  = static_cast<uint32_t>(a);
        const uint32_t wb  = static_cast<uint32_t>(b);
        const int32_t  swa = static_cast<int32_t>(wa);
        const int32_t  swb = static_cast<int32_t>(wb);

        // Shift amounts (RV64 ISA §2.6)
        const uint8_t  shamt6 = b & 0x3F;   // 64-bit shifts: [5:0]
        const uint8_t  shamt5 = b & 0x1F;   // 32-bit shifts: [4:0]

        switch (op) {

            // ── Base integer ──────────────────────────────────
            case ALU_OP::ALU_ADD:      return a + b;
            case ALU_OP::ALU_SUB:      return a - b;
            case ALU_OP::ALU_AND:      return a & b;
            case ALU_OP::ALU_OR:       return a | b;
            case ALU_OP::ALU_XOR:      return a ^ b;
            case ALU_OP::ALU_SLL:      return a << shamt6;
            case ALU_OP::ALU_SRL:      return a >> shamt6;
            case ALU_OP::ALU_SRA:      return static_cast<uint64_t>(sa >> shamt6);
            case ALU_OP::ALU_SLT:      return (sa < sb) ? 1ULL : 0ULL;
            case ALU_OP::ALU_SLTU:     return (a  < b ) ? 1ULL : 0ULL;

            // ── Word (*W) — operate on [31:0], sign-extend ────
            case ALU_OP::ALU_ADDW:     return sext32(wa + wb);
            case ALU_OP::ALU_SUBW:     return sext32(wa - wb);
            case ALU_OP::ALU_SLLW:     return sext32(wa << shamt5);
            case ALU_OP::ALU_SRLW:     return sext32(wa >> shamt5);
            case ALU_OP::ALU_SRAW:     return sext32(static_cast<uint32_t>(swa >> shamt5));

            // ── Upper immediate / PC ops ───────────────────────
            case ALU_OP::ALU_LUI_PASS: return b;           // LUI: pass upper imm
            case ALU_OP::ALU_AUIPC:    return a + b;        // AUIPC: PC + upper imm

            // ── M-extension: multiply ─────────────────────────
            case ALU_OP::ALU_MUL:      return a * b;        // lower 64 bits
            case ALU_OP::ALU_MULH:     return mulh_signed(sa, sb);
            case ALU_OP::ALU_MULHU:    return mulh_unsigned(a, b);
            case ALU_OP::ALU_MULHSU:   return mulh_su(sa, b);

            // ── M-extension: divide (with RV64 exception rules) ─
            case ALU_OP::ALU_DIV: {
                if (b == 0) { div_by_zero_o = true; return UINT64_MAX; } // -1
                // signed overflow: MIN_INT64 / -1
                if (a == 0x8000000000000000ULL && sb == -1) {
                    div_overflow_o = true;
                    return 0x8000000000000000ULL; // MIN_INT
                }
                return static_cast<uint64_t>(sa / sb);
            }
            case ALU_OP::ALU_DIVU: {
                if (b == 0) { div_by_zero_o = true; return UINT64_MAX; }
                return a / b;
            }
            case ALU_OP::ALU_REM: {
                if (b == 0) { div_by_zero_o = true; return a; }
                if (a == 0x8000000000000000ULL && sb == -1) {
                    div_overflow_o = true; return 0;
                }
                return static_cast<uint64_t>(sa % sb);
            }
            case ALU_OP::ALU_REMU: {
                if (b == 0) { div_by_zero_o = true; return a; }
                return a % b;
            }

            // ── M-extension: word variants ────────────────────
            case ALU_OP::ALU_MULW: {
                return sext32(wa * wb);
            }
            case ALU_OP::ALU_DIVW: {
                if (wb == 0) { div_by_zero_o = true; return UINT64_MAX; }
                if (swa == INT32_MIN && swb == -1) {
                    div_overflow_o = true;
                    return sext32(static_cast<uint32_t>(INT32_MIN));
                }
                return sext32(static_cast<uint32_t>(swa / swb));
            }
            case ALU_OP::ALU_DIVUW: {
                if (wb == 0) { div_by_zero_o = true; return UINT64_MAX; }
                return sext32(wa / wb);
            }
            case ALU_OP::ALU_REMW: {
                if (wb == 0) { div_by_zero_o = true; return sext32(wa); }
                if (swa == INT32_MIN && swb == -1) {
                    div_overflow_o = true; return 0;
                }
                return sext32(static_cast<uint32_t>(swa % swb));
            }
            case ALU_OP::ALU_REMUW: {
                if (wb == 0) { div_by_zero_o = true; return sext32(wa); }
                return sext32(wa % wb);
            }

            // ── Passthrough (JAL/JALR: a = PC+4) ─────────────
            case ALU_OP::ALU_PASS_A:   return a;

            default:           return 0;
        }
    }
};

