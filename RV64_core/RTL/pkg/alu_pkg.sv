`timescale 1ns/1ps
package alu_pkg;

typedef enum logic [4:0] {
    ALU_ADD      = 5'h00,
    ALU_SUB      = 5'h01,
    ALU_AND      = 5'h02,
    ALU_OR       = 5'h03,
    ALU_XOR      = 5'h04,
    ALU_SLL      = 5'h05,
    ALU_SRL      = 5'h06,
    ALU_SRA      = 5'h07,
    ALU_SLT      = 5'h08,
    ALU_SLTU     = 5'h09,
    ALU_ADDW     = 5'h0A,
    ALU_SUBW     = 5'h0B,
    ALU_SLLW     = 5'h0C,
    ALU_SRLW     = 5'h0D,
    ALU_SRAW     = 5'h0E,
    ALU_LUI_PASS = 5'h0F,
    ALU_AUIPC    = 5'h10,
    ALU_MUL      = 5'h11,
    ALU_MULH     = 5'h12,
    ALU_MULHU    = 5'h13,
    ALU_MULHSU   = 5'h14,
    ALU_DIV      = 5'h15,
    ALU_DIVU     = 5'h16,
    ALU_REM      = 5'h17,
    ALU_REMU     = 5'h18,
    ALU_MULW     = 5'h19,
    ALU_DIVW     = 5'h1A,
    ALU_DIVUW    = 5'h1B,
    ALU_REMW     = 5'h1C,
    ALU_REMUW    = 5'h1D,
    ALU_PASS_A   = 5'h1E,
    NONE         = 5'h1F
}  alu_op_t;

endpackage


