#pragma once
#include <cstdint>

// ── Shared ALU opcode enum (used by ALU_MODEL and RV64_decode_unit) ──────────
enum class ALU_OP : uint8_t {
    ALU_ADD      = 0x00,
    ALU_SUB      = 0x01,
    ALU_AND      = 0x02,
    ALU_OR       = 0x03,
    ALU_XOR      = 0x04,
    ALU_SLL      = 0x05,
    ALU_SRL      = 0x06,
    ALU_SRA      = 0x07,
    ALU_SLT      = 0x08,
    ALU_SLTU     = 0x09,
    ALU_ADDW     = 0x0A,
    ALU_SUBW     = 0x0B,
    ALU_SLLW     = 0x0C,
    ALU_SRLW     = 0x0D,
    ALU_SRAW     = 0x0E,
    ALU_LUI_PASS = 0x0F,
    ALU_AUIPC    = 0x10,
    ALU_MUL      = 0x11,
    ALU_MULH     = 0x12,
    ALU_MULHU    = 0x13,
    ALU_MULHSU   = 0x14,
    ALU_DIV      = 0x15,
    ALU_DIVU     = 0x16,
    ALU_REM      = 0x17,
    ALU_REMU     = 0x18,
    ALU_MULW     = 0x19,
    ALU_DIVW     = 0x1A,
    ALU_DIVUW    = 0x1B,
    ALU_REMW     = 0x1C,
    ALU_REMUW    = 0x1D,
    ALU_PASS_A   = 0x1E,
    NONE         = 0x1F
};
