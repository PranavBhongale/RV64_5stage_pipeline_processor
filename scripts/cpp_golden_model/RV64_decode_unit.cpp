#include <iostream>
#include <cstdint>
using namespace std;

// ─────────────────────────────────────────────
//  Instruction types
// ─────────────────────────────────────────────
enum class InstrType {
    R_TYPE, I_TYPE, S_TYPE, B_TYPE, U_TYPE, J_TYPE,
    CSR_TYPE, SYS_TYPE,
    UNKNOWN
};

// ─────────────────────────────────────────────
//  ALU operation codes  (RV64I + M extension)
// ─────────────────────────────────────────────
#include "alu_op.h"

enum class MemOp {
    NONE,
    // Loads (signed)
    LOAD_BYTE,       // LB   — 8-bit  sign-extend
    LOAD_HALF,       // LH   — 16-bit sign-extend
    LOAD_WORD,       // LW   — 32-bit sign-extend
    LOAD_DOUBLE,     // LD   — 64-bit (RV64 only)
    // Loads (unsigned / zero-extend)
    LOAD_BYTE_U,     // LBU
    LOAD_HALF_U,     // LHU
    LOAD_WORD_U,     // LWU  (RV64 only — 32-bit zero-extend)
    // Stores
    STORE_BYTE,      // SB
    STORE_HALF,      // SH
    STORE_WORD,      // SW
    STORE_DOUBLE     // SD   (RV64 only)
};

enum class BranchOp {
    NONE, BEQ, BNE, BLT, BGE, BLTU, BGEU
};

// ─────────────────────────────────────────────
//  CSR operation codes
// ─────────────────────────────────────────────
enum class CsrOp {
    NONE,
    CSRRW,   // read/write
    CSRRS,   // read/set bits
    CSRRC,   // read/clear bits
    CSRRWI,  // immediate read/write
    CSRRSI,  // immediate read/set
    CSRRCI   // immediate read/clear
};

// ─────────────────────────────────────────────
//  System operation codes
// ─────────────────────────────────────────────
enum class SysOp {
    NONE,
    ECALL,
    EBREAK,
    FENCE,
    FENCE_I,
    MRET,
    SRET,
    WFI
};

// ─────────────────────────────────────────────
//  Decoded instruction bundle → control logic
// ─────────────────────────────────────────────
struct DecodedInstruction {
    // classification
    InstrType instr_type  = InstrType::UNKNOWN;
    ALU_OP    alu_op      = ALU_OP::ALU_ADD;        // default to ADD (safe/NOP-like)
    MemOp     mem_op      = MemOp::NONE;
    BranchOp  branch_op   = BranchOp::NONE;
    CsrOp     csr_op      = CsrOp::NONE;
    SysOp     sys_op      = SysOp::NONE;

    // register addresses
    uint8_t  rs1     = 0;
    uint8_t  rs2     = 0;
    uint8_t  rd      = 0;

    // immediate (sign-extended 64-bit)
    int64_t  imm     = 0;

    // CSR address (12-bit)
    uint16_t csr_addr = 0;

    // zimm field (5-bit unsigned, CSR immediate variants)
    uint8_t  zimm    = 0;

    // control flags
    bool rs1_used    = false;
    bool rs2_used    = false;
    bool rd_used     = false;
    bool imm_used    = false;
    bool mem_read    = false;
    bool mem_write   = false;
    bool branch      = false;
    bool jump        = false;
    bool csr_access  = false;
    bool sys_call    = false;
    bool valid       = false;
};

// ─────────────────────────────────────────────────────────────────────────────
//  Instruction Decode Unit — RV64I + M extension
// ─────────────────────────────────────────────────────────────────────────────
class instruction_decode_unit {
public:

    // ──── INPUTS ────
    uint32_t in_instruction = 0;
    uint64_t in_pc          = 0;
    bool     in_valid       = false;

    // ──── OUTPUT (to control logic) ────
    DecodedInstruction decoded;

    // ──── HANDSHAKE ────
    bool out_ready = true;

private:

    // ── Opcode constants ─────────────────────────────────────────────────────
    static constexpr uint8_t OPC_R       = 0b0110011;  // R-type 64-bit (RV64I + M)
    static constexpr uint8_t OPC_R_W     = 0b0111011;  // R-type *W (ADDW/SUBW/... + MULW/DIVW/...)
    static constexpr uint8_t OPC_I_ALU   = 0b0010011;  // I-type ALU 64-bit (ADDI, XORI, SLLI...)
    static constexpr uint8_t OPC_I_ALU_W = 0b0011011;  // I-type ALU *W (ADDIW, SLLIW, SRLIW, SRAIW)
    static constexpr uint8_t OPC_I_LOAD  = 0b0000011;  // I-type Load (LB/LH/LW/LD/LBU/LHU/LWU)
    static constexpr uint8_t OPC_I_JALR  = 0b1100111;  // JALR
    static constexpr uint8_t OPC_S       = 0b0100011;  // S-type Store (SB/SH/SW/SD)
    static constexpr uint8_t OPC_B       = 0b1100011;  // B-type Branch
    static constexpr uint8_t OPC_U_LUI   = 0b0110111;  // LUI
    static constexpr uint8_t OPC_U_AUI   = 0b0010111;  // AUIPC
    static constexpr uint8_t OPC_J_JAL   = 0b1101111;  // JAL
    static constexpr uint8_t OPC_SYSTEM  = 0b1110011;  // SYSTEM (CSR + ECALL/EBREAK/MRET/WFI)
    static constexpr uint8_t OPC_FENCE   = 0b0001111;  // FENCE / FENCE.I

    // M-extension funct7
    static constexpr uint8_t FUNCT7_M    = 0b0000001;
    // RV64I *W arithmetic funct7
    static constexpr uint8_t FUNCT7_SUB  = 0b0100000;  // SUB/SUBW, SRA/SRAW, SRAIW

    // ── Field extractors ─────────────────────────────────────────────────────
    uint8_t  opcode  (uint32_t i) { return  i & 0x7F; }
    uint8_t  rd_f    (uint32_t i) { return (i >>  7) & 0x1F; }
    uint8_t  funct3  (uint32_t i) { return (i >> 12) & 0x07; }
    uint8_t  rs1_f   (uint32_t i) { return (i >> 15) & 0x1F; }
    uint8_t  rs2_f   (uint32_t i) { return (i >> 20) & 0x1F; }
    uint8_t  funct7  (uint32_t i) { return (i >> 25) & 0x7F; }
    uint16_t csr_f   (uint32_t i) { return (i >> 20) & 0xFFF; }
    uint8_t  zimm_f  (uint32_t i) { return (i >> 15) & 0x1F; }

    // ── Immediate decoders (all sign-extend to 64-bit) ────────────────────────
    int64_t imm_I(uint32_t i) {
        // bits [31:20] sign-extended
        return (int64_t)((int32_t)i >> 20);
    }
    int64_t imm_S(uint32_t i) {
        int32_t raw = ((int32_t)(i & 0xFE000000) >> 20) | ((i >> 7) & 0x1F);
        return (int64_t)raw;
    }
  int64_t imm_B(uint32_t instr)
{
    int32_t imm =
          (((instr >> 31) & 0x1) << 12)
        | (((instr >> 7)  & 0x1) << 11)
        | (((instr >> 25) & 0x3F) << 5)
        | (((instr >> 8)  & 0xF) << 1);

    // Sign extend 13-bit immediate
    imm = (imm << 19) >> 19;

    return (int64_t)imm;
}
    int64_t imm_U(uint32_t i) {
        // sign-extended 32-bit value with lower 12 bits zero
        return (int64_t)((int32_t)(i & 0xFFFFF000));
    }
    int64_t imm_J(uint32_t i) {
        int32_t raw = ((int32_t)(i & 0x80000000) >> 11)
                    | (i & 0x000FF000)
                    | ((i & 0x00100000) >> 9)
                    | ((i >> 20) & 0x7FE);
        return (int64_t)raw;
    }

    // ── R-TYPE 64-bit  (OPC_R = 0b0110011) ───────────────────────────────────
    // Covers: ADD SUB AND OR XOR SLL SRL SRA SLT SLTU  (RV64I)
    //         MUL MULH MULHU MULHSU DIV DIVU REM REMU  (RV64M)
    void decode_R(uint32_t instr, DecodedInstruction& d) {
        d.instr_type = InstrType::R_TYPE;
        d.rs1        = rs1_f(instr);
        d.rs2        = rs2_f(instr);
        d.rd         = rd_f (instr);
        d.rs1_used   = true;
        d.rs2_used   = true;
        d.rd_used    = true;

        uint8_t f3 = funct3(instr);
        uint8_t f7 = funct7(instr);

        // M-extension: funct7 = 0000001
        if (f7 == FUNCT7_M) {
            switch (f3) {
                case 0x0: d.alu_op = ALU_OP::ALU_MUL;    break;  // MUL
                case 0x1: d.alu_op = ALU_OP::ALU_MULH;   break;  // MULH
                case 0x2: d.alu_op = ALU_OP::ALU_MULHSU; break;  // MULHSU
                case 0x3: d.alu_op = ALU_OP::ALU_MULHU;  break;  // MULHU
                case 0x4: d.alu_op = ALU_OP::ALU_DIV;    break;  // DIV
                case 0x5: d.alu_op = ALU_OP::ALU_DIVU;   break;  // DIVU
                case 0x6: d.alu_op = ALU_OP::ALU_REM;    break;  // REM
                case 0x7: d.alu_op = ALU_OP::ALU_REMU;   break;  // REMU
                default:  d.instr_type = InstrType::UNKNOWN; break;
            }
            return;
        }

        // RV64I base R-type
        if      (f3 == 0x0 && f7 == 0x00) d.alu_op = ALU_OP::ALU_ADD;
        else if (f3 == 0x0 && f7 == 0x20) d.alu_op = ALU_OP::ALU_SUB;
        else if (f3 == 0x4 && f7 == 0x00) d.alu_op = ALU_OP::ALU_XOR;
        else if (f3 == 0x6 && f7 == 0x00) d.alu_op = ALU_OP::ALU_OR;
        else if (f3 == 0x7 && f7 == 0x00) d.alu_op = ALU_OP::ALU_AND;
        else if (f3 == 0x1 && f7 == 0x00) d.alu_op = ALU_OP::ALU_SLL;
        else if (f3 == 0x5 && f7 == 0x00) d.alu_op = ALU_OP::ALU_SRL;
        else if (f3 == 0x5 && f7 == 0x20) d.alu_op = ALU_OP::ALU_SRA;
        else if (f3 == 0x2 && f7 == 0x00) d.alu_op = ALU_OP::ALU_SLT;
        else if (f3 == 0x3 && f7 == 0x00) d.alu_op = ALU_OP::ALU_SLTU;
        else                               d.instr_type = InstrType::UNKNOWN;
    }

    // ── R-TYPE *W  (OPC_R_W = 0b0111011) ────────────────────────────────────
    // Covers: ADDW SUBW SLLW SRLW SRAW  (RV64I)
    //         MULW DIVW DIVUW REMW REMUW (RV64M)
    // *W ops operate on lower 32 bits, result sign-extended to 64 bits.
    void decode_R_W(uint32_t instr, DecodedInstruction& d) {
        d.instr_type = InstrType::R_TYPE;
        d.rs1        = rs1_f(instr);
        d.rs2        = rs2_f(instr);
        d.rd         = rd_f (instr);
        d.rs1_used   = true;
        d.rs2_used   = true;
        d.rd_used    = true;

        uint8_t f3 = funct3(instr);
        uint8_t f7 = funct7(instr);

        // M *W extension
        if (f7 == FUNCT7_M) {
            switch (f3) {
                case 0x0: d.alu_op = ALU_OP::ALU_MULW;  break;  // MULW
                case 0x4: d.alu_op = ALU_OP::ALU_DIVW;  break;  // DIVW
                case 0x5: d.alu_op = ALU_OP::ALU_DIVUW; break;  // DIVUW
                case 0x6: d.alu_op = ALU_OP::ALU_REMW;  break;  // REMW
                case 0x7: d.alu_op = ALU_OP::ALU_REMUW; break;  // REMUW
                default:  d.instr_type = InstrType::UNKNOWN; break;
            }
            return;
        }

        // RV64I *W base
        if      (f3 == 0x0 && f7 == 0x00) d.alu_op = ALU_OP::ALU_ADDW;
        else if (f3 == 0x0 && f7 == 0x20) d.alu_op = ALU_OP::ALU_SUBW;
        else if (f3 == 0x1 && f7 == 0x00) d.alu_op = ALU_OP::ALU_SLLW;
        else if (f3 == 0x5 && f7 == 0x00) d.alu_op = ALU_OP::ALU_SRLW;
        else if (f3 == 0x5 && f7 == 0x20) d.alu_op = ALU_OP::ALU_SRAW;
        else                               d.instr_type = InstrType::UNKNOWN;
    }

    // ── I-TYPE ALU 64-bit  (OPC_I_ALU = 0b0010011) ───────────────────────────
    // ADDI XORI ORI ANDI SLTI SLTIU SLLI SRLI SRAI
    // Note: for shifts, shamt is bits [25:20] (6 bits for RV64).
    //       funct6 = bits[31:26]; we reuse funct7 field and mask as needed.
    //       SRLI: funct7 upper 6 bits = 000000 (funct7 = 0x00)
    //       SRAI: funct7 upper 6 bits = 010000 (funct7 = 0x20)
    //       SLLI: funct7 = 0x00
    void decode_I_ALU(uint32_t instr, DecodedInstruction& d) {
        d.instr_type = InstrType::I_TYPE;
        d.rs1        = rs1_f(instr);
        d.rd         = rd_f (instr);
        d.imm        = imm_I(instr);   // for shifts: lower 6 bits of imm = shamt
        d.rs1_used   = true;
        d.rd_used    = true;
        d.imm_used   = true;

        uint8_t f3 = funct3(instr);
        uint8_t f7 = funct7(instr);   // bit[30] distinguishes SRAI from SRLI

        if      (f3 == 0x0)                d.alu_op = ALU_OP::ALU_ADD;   // ADDI
        else if (f3 == 0x4)                d.alu_op = ALU_OP::ALU_XOR;   // XORI
        else if (f3 == 0x6)                d.alu_op = ALU_OP::ALU_OR;    // ORI
        else if (f3 == 0x7)                d.alu_op = ALU_OP::ALU_AND;   // ANDI
        else if (f3 == 0x2)                d.alu_op = ALU_OP::ALU_SLT;   // SLTI
        else if (f3 == 0x3)                d.alu_op = ALU_OP::ALU_SLTU;  // SLTIU
        else if (f3 == 0x1 && f7 == 0x00) d.alu_op = ALU_OP::ALU_SLL;   // SLLI (shamt[5:0])
        else if (f3 == 0x5 && f7 == 0x00) d.alu_op = ALU_OP::ALU_SRL;   // SRLI
        else if (f3 == 0x5 && f7 == 0x20) d.alu_op = ALU_OP::ALU_SRA;   // SRAI
        else                               d.instr_type = InstrType::UNKNOWN;
    }

    // ── I-TYPE ALU *W  (OPC_I_ALU_W = 0b0011011) ────────────────────────────
    // ADDIW SLLIW SRLIW SRAIW
    // Operates on lower 32 bits of rs1, result sign-extended to 64 bits.
    // shamt is 5-bit (bits [24:20]); funct7 distinguishes SRLIW/SRAIW.
    void decode_I_ALU_W(uint32_t instr, DecodedInstruction& d) {
        d.instr_type = InstrType::I_TYPE;
        d.rs1        = rs1_f(instr);
        d.rd         = rd_f (instr);
        d.imm        = imm_I(instr);   // for shifts: lower 5 bits = shamt
        d.rs1_used   = true;
        d.rd_used    = true;
        d.imm_used   = true;

        uint8_t f3 = funct3(instr);
        uint8_t f7 = funct7(instr);

        if      (f3 == 0x0)                d.alu_op = ALU_OP::ALU_ADDW;  // ADDIW
        else if (f3 == 0x1 && f7 == 0x00) d.alu_op = ALU_OP::ALU_SLLW;  // SLLIW
        else if (f3 == 0x5 && f7 == 0x00) d.alu_op = ALU_OP::ALU_SRLW;  // SRLIW
        else if (f3 == 0x5 && f7 == 0x20) d.alu_op = ALU_OP::ALU_SRAW;  // SRAIW
        else                               d.instr_type = InstrType::UNKNOWN;
    }

    // ── I-TYPE Load  (OPC_I_LOAD = 0b0000011) ────────────────────────────────
    // LB LH LW LD LBU LHU LWU
    // Effective address = rs1 + imm  (ALU_ADD)
    void decode_I_LOAD(uint32_t instr, DecodedInstruction& d) {
        d.instr_type = InstrType::I_TYPE;
        d.rs1        = rs1_f(instr);
        d.rd         = rd_f (instr);
        d.imm        = imm_I(instr);
        d.rs1_used   = true;
        d.rd_used    = true;
        d.imm_used   = true;
        d.mem_read   = true;
        d.alu_op     = ALU_OP::ALU_ADD;        // address = rs1 + imm

        switch (funct3(instr)) {
            case 0x0: d.mem_op = MemOp::LOAD_BYTE;   break;  // LB
            case 0x1: d.mem_op = MemOp::LOAD_HALF;   break;  // LH
            case 0x2: d.mem_op = MemOp::LOAD_WORD;   break;  // LW  (sign-extend to 64)
            case 0x3: d.mem_op = MemOp::LOAD_DOUBLE; break;  // LD  (RV64 new)
            case 0x4: d.mem_op = MemOp::LOAD_BYTE_U; break;  // LBU
            case 0x5: d.mem_op = MemOp::LOAD_HALF_U; break;  // LHU
            case 0x6: d.mem_op = MemOp::LOAD_WORD_U; break;  // LWU (RV64 new, zero-extend)
            default:  d.instr_type = InstrType::UNKNOWN; break;
        }
    }

    // ── I-TYPE JALR  (OPC_I_JALR = 0b1100111) ────────────────────────────────
    // JALR: rd = PC+4;  PC = (rs1 + imm) & ~1
    // ALU computes rs1+imm for branch target; PC+4 is written to rd via ALU_PASS_A
    // (the execute stage is expected to pass the pre-calculated PC+4 through as 'a').
    void decode_I_JALR(uint32_t instr, DecodedInstruction& d) {
        d.instr_type = InstrType::I_TYPE;
        d.rs1        = rs1_f(instr);
        d.rd         = rd_f (instr);
        d.imm        = imm_I(instr);
        d.rs1_used   = true;
        d.rd_used    = true;
        d.imm_used   = true;
        d.jump       = true;
        // ALU_PASS_A: rd gets PC+4 (the execute/WB stage supplies PC+4 as operand A)
        d.alu_op     = ALU_OP::ALU_PASS_A;
    }

    // ── S-TYPE  (OPC_S = 0b0100011) ──────────────────────────────────────────
    // SB SH SW SD
    // Effective address = rs1 + imm  (ALU_ADD)
    void decode_S(uint32_t instr, DecodedInstruction& d) {
        d.instr_type = InstrType::S_TYPE;
        d.rs1        = rs1_f(instr);
        d.rs2        = rs2_f(instr);
        d.imm        = imm_S(instr);
        d.rs1_used   = true;
        d.rs2_used   = true;
        d.imm_used   = true;
        d.mem_write  = true;
        d.alu_op     = ALU_OP::ALU_ADD;

        switch (funct3(instr)) {
            case 0x0: d.mem_op = MemOp::STORE_BYTE;   break;  // SB
            case 0x1: d.mem_op = MemOp::STORE_HALF;   break;  // SH
            case 0x2: d.mem_op = MemOp::STORE_WORD;   break;  // SW
            case 0x3: d.mem_op = MemOp::STORE_DOUBLE; break;  // SD  (RV64 new)
            default:  d.instr_type = InstrType::UNKNOWN; break;
        }
    }

    // ── B-TYPE  (OPC_B = 0b1100011) ──────────────────────────────────────────
    // BEQ BNE BLT BGE BLTU BGEU
    void decode_B(uint32_t instr, DecodedInstruction& d) {
        d.instr_type = InstrType::B_TYPE;
        d.rs1        = rs1_f(instr);
        d.rs2        = rs2_f(instr);
        d.imm        = imm_B(instr);
        d.rs1_used   = true;
        d.rs2_used   = true;
        d.imm_used   = true;
        d.branch     = true;
        d.alu_op     = ALU_OP::ALU_SUB;  // rs1-rs2: zero/neg/overflow flags drive branch

        switch (funct3(instr)) {
            case 0x0: d.branch_op = BranchOp::BEQ;  break;
            case 0x1: d.branch_op = BranchOp::BNE;  break;
            case 0x4: d.branch_op = BranchOp::BLT;  break;
            case 0x5: d.branch_op = BranchOp::BGE;  break;
            case 0x6: d.branch_op = BranchOp::BLTU; break;
            case 0x7: d.branch_op = BranchOp::BGEU; break;
            default:  d.instr_type = InstrType::UNKNOWN; break;
        }
    }

    // ── U-TYPE  (LUI / AUIPC) ────────────────────────────────────────────────
    // LUI:   rd = imm_U  (sign-extended 32-bit upper immediate, lower 12 = 0)
    // AUIPC: rd = PC + imm_U
    void decode_U(uint32_t instr, uint8_t opc, DecodedInstruction& d) {
        d.instr_type = InstrType::U_TYPE;
        d.rd         = rd_f(instr);
        d.imm        = imm_U(instr);
        d.rd_used    = true;
        d.imm_used   = true;
        d.alu_op     = (opc == OPC_U_LUI) ? ALU_OP::ALU_LUI_PASS : ALU_OP::ALU_AUIPC;
    }

    // ── J-TYPE  (JAL) ────────────────────────────────────────────────────────
    // JAL: rd = PC+4;  PC = PC + imm_J
    // ALU_PASS_A: rd gets PC+4 (execute stage supplies PC+4 as operand A)
    void decode_J(uint32_t instr, DecodedInstruction& d) {
        d.instr_type = InstrType::J_TYPE;
        d.rd         = rd_f(instr);
        d.imm        = imm_J(instr);
        d.rd_used    = true;
        d.imm_used   = true;
        d.jump       = true;
        d.alu_op     = ALU_OP::ALU_PASS_A;     // rd = PC+4 (pass through)
    }

    // ── SYSTEM opcode  (CSR + ECALL + EBREAK + MRET + WFI) ──────────────────
    void decode_SYSTEM(uint32_t instr, DecodedInstruction& d) {
        uint8_t  f3  = funct3(instr);
        uint32_t f12 = (instr >> 20) & 0xFFF;

        // CSR instructions: funct3 != 000
        if (f3 != 0x0) {
            d.instr_type = InstrType::CSR_TYPE;
            d.csr_addr   = csr_f(instr);
            d.rd         = rd_f(instr);
            d.rd_used    = true;
            d.csr_access = true;

            switch (f3) {
                case 0x1:                           // CSRRW
                    d.csr_op   = CsrOp::CSRRW;
                    d.rs1      = rs1_f(instr);
                    d.rs1_used = true;
                    break;
                case 0x2:                           // CSRRS
                    d.csr_op   = CsrOp::CSRRS;
                    d.rs1      = rs1_f(instr);
                    d.rs1_used = true;
                    break;
                case 0x3:                           // CSRRC
                    d.csr_op   = CsrOp::CSRRC;
                    d.rs1      = rs1_f(instr);
                    d.rs1_used = true;
                    break;
                case 0x5:                           // CSRRWI
                    d.csr_op   = CsrOp::CSRRWI;
                    d.zimm     = zimm_f(instr);
                    d.imm      = (int64_t)d.zimm;
                    d.imm_used = true;
                    break;
                case 0x6:                           // CSRRSI
                    d.csr_op   = CsrOp::CSRRSI;
                    d.zimm     = zimm_f(instr);
                    d.imm      = (int64_t)d.zimm;
                    d.imm_used = true;
                    break;
                case 0x7:                           // CSRRCI
                    d.csr_op   = CsrOp::CSRRCI;
                    d.zimm     = zimm_f(instr);
                    d.imm      = (int64_t)d.zimm;
                    d.imm_used = true;
                    break;
                default:
                    d.instr_type = InstrType::UNKNOWN;
                    break;
            }
            return;
        }

        // funct3 == 000: privileged / system instructions
        d.instr_type = InstrType::SYS_TYPE;
        d.sys_call   = true;

        switch (f12) {
            case 0x000: d.sys_op = SysOp::ECALL;  break;  // ECALL
            case 0x001: d.sys_op = SysOp::EBREAK; break;  // EBREAK
            case 0x302: d.sys_op = SysOp::MRET;   break;  // MRET
            case 0x102: d.sys_op = SysOp::SRET;   break;  // SRET
            case 0x105: d.sys_op = SysOp::WFI;    break;  // WFI
            default:    d.instr_type = InstrType::UNKNOWN; break;
        }
    }

    // ── FENCE / FENCE.I  (OPC_FENCE = 0b0001111) ─────────────────────────────
    void decode_FENCE(uint32_t instr, DecodedInstruction& d) {
        d.instr_type = InstrType::SYS_TYPE;
        d.sys_call   = true;
        d.sys_op     = (funct3(instr) == 0x1) ? SysOp::FENCE_I : SysOp::FENCE;
    }

public:

    // tick() : called every clock cycle
    void tick() {
        decoded       = DecodedInstruction{};
        decoded.valid = false;
        out_ready     = true;

        if (!in_valid) return;

        uint32_t instr = in_instruction;
        uint8_t  opc   = opcode(instr);

        switch (opc) {
            case OPC_R:       decode_R        (instr,      decoded); break;
            case OPC_R_W:     decode_R_W      (instr,      decoded); break;  // RV64 *W R-type
            case OPC_I_ALU:   decode_I_ALU    (instr,      decoded); break;
            case OPC_I_ALU_W: decode_I_ALU_W  (instr,      decoded); break;  // RV64 *W I-type
            case OPC_I_LOAD:  decode_I_LOAD   (instr,      decoded); break;
            case OPC_I_JALR:  decode_I_JALR   (instr,      decoded); break;
            case OPC_S:       decode_S        (instr,      decoded); break;
            case OPC_B:       decode_B        (instr,      decoded); break;
            case OPC_U_LUI:   decode_U        (instr, opc, decoded); break;
            case OPC_U_AUI:   decode_U        (instr, opc, decoded); break;
            case OPC_J_JAL:   decode_J        (instr,      decoded); break;
            case OPC_SYSTEM:  decode_SYSTEM   (instr,      decoded); break;
            case OPC_FENCE:   decode_FENCE    (instr,      decoded); break;
            default:
                decoded.instr_type = InstrType::UNKNOWN;
                break;
        }

        decoded.valid = true;
    }
};



