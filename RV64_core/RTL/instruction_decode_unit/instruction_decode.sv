// =============================================================================
//  instruction_decode.sv
//
//  RV64I + M-extension — PURELY COMBINATIONAL decode unit.
//
//  No registers, no clock, no reset.
//  Valid/ready are pass-through: in_ready = out_ready (no internal stall).
//  The caller (top-level pipeline) owns all registers and handshake buffering.
//
//  Ports
//  -----
//    in_valid        — upstream valid
//    in_ready        — driven by this module = out_ready (pass-through)
//    in_instruction  — 32-bit raw instruction
//    in_pc           — 64-bit PC of this instruction
//
//    out_valid       — = in_valid (pass-through)
//    out_ready       — driven by downstream; fed back to in_ready
//    out_decoded     — decoded_instr_t bundle
//    out_alu_op      — alu_op_e (separate, from alu_op_pkg)
//    out_pc          — = in_pc  (pass-through)
// =============================================================================


`timescale 1ns/1ps
import decode_pkg::*;
import alu_pkg::*;

module instruction_decode (
    // ── Upstream ──────────────────────────────────────────────────────────────
    input  logic            in_valid,
    output logic            in_ready,

    input  logic [31:0]     in_instruction,
    input  logic [63:0]     in_pc,

    // ── Downstream ────────────────────────────────────────────────────────────
    output logic            out_valid,
    input  logic            out_ready,

    output decoded_instr_t  out_decoded,
    output alu_op_t         out_alu_op,
    output logic [63:0]     out_pc
);

    // ── Valid/ready pass-through ──────────────────────────────────────────────
    assign out_valid = in_valid;
    assign in_ready  = out_ready;
    assign out_pc    = in_pc;

    // ── Internal combinational wires ──────────────────────────────────────────
    decoded_instr_t  dec;
    alu_op_t         aop;
    logic            unknown;

    assign out_decoded = dec;
    assign out_alu_op  = aop;

    // =========================================================================
    //  Field extractors
    // =========================================================================
    function automatic logic [6:0]  f_opcode (input logic [31:0] i); return i[6:0];   endfunction
    function automatic logic [4:0]  f_rd     (input logic [31:0] i); return i[11:7];  endfunction
    function automatic logic [2:0]  f_funct3 (input logic [31:0] i); return i[14:12]; endfunction
    function automatic logic [4:0]  f_rs1    (input logic [31:0] i); return i[19:15]; endfunction
    function automatic logic [4:0]  f_rs2    (input logic [31:0] i); return i[24:20]; endfunction
    function automatic logic [6:0]  f_funct7 (input logic [31:0] i); return i[31:25]; endfunction
    function automatic logic [11:0] f_csr    (input logic [31:0] i); return i[31:20]; endfunction
    function automatic logic [4:0]  f_zimm   (input logic [31:0] i); return i[19:15]; endfunction

    // =========================================================================
    //  Immediate decoders — all sign-extended to 64 bits
    // =========================================================================
    function automatic logic signed [63:0] imm_I (input logic [31:0] i);
        return {{52{i[31]}}, i[31:20]};
    endfunction

    function automatic logic signed [63:0] imm_S (input logic [31:0] i);
        return {{52{i[31]}}, i[31:25], i[11:7]};
    endfunction

    function automatic logic signed [63:0] imm_B (input logic [31:0] i);
        // imm[12|10:5|4:1|11], bit[0] = 0
        return {{51{i[31]}}, i[31], i[7], i[30:25], i[11:8], 1'b0};
    endfunction

    function automatic logic signed [63:0] imm_U (input logic [31:0] i);
        // upper-20 at [31:12], lower 12 = 0, sign-extended to 64
        return {{32{i[31]}}, i[31:12], 12'b0};
    endfunction

    function automatic logic signed [63:0] imm_J (input logic [31:0] i);
        // imm[20|10:1|11|19:12], bit[0] = 0
        return {{43{i[31]}}, i[31], i[19:12], i[20], i[30:21], 1'b0};
    endfunction

    // =========================================================================
    //  Opcode / funct7 constants
    // =========================================================================
    localparam logic [6:0] OpcR       = 7'b011_0011;
    localparam logic [6:0] OpcRW      = 7'b011_1011;
    localparam logic [6:0] OpcIAlu    = 7'b001_0011;
    localparam logic [6:0] OpcIAluW   = 7'b001_1011;
    localparam logic [6:0] OpcILoad   = 7'b000_0011;
    localparam logic [6:0] OpcIJalr   = 7'b110_0111;
    localparam logic [6:0] OpcS       = 7'b010_0011;
    localparam logic [6:0] OpcB       = 7'b110_0011;
    localparam logic [6:0] OpcULui    = 7'b011_0111;
    localparam logic [6:0] OpcUAui    = 7'b001_0111;
    localparam logic [6:0] OpcJJal    = 7'b110_1111;
    localparam logic [6:0] OpcSystem  = 7'b111_0011;
    localparam logic [6:0] OpcFence   = 7'b000_1111;

    localparam logic [6:0] Funct7M    = 7'b000_0001;  // M-extension
    localparam logic [6:0] Funct7Sub  = 7'b010_0000;  // SUB/SRA/SUBW/SRAW

    // =========================================================================
    //  Main combinational decode
    // =========================================================================
    always_comb begin

        // ── Defaults ─────────────────────────────────────────────────────────
        dec         = '0;
        aop         = ALU_ADD;
        unknown     = 1'b0;

        dec.instr_type = R_TYPE;   // overridden per opcode
        dec.mem_op     = MEM_NONE;
        dec.branch_op  = BR_NONE;
        dec.csr_op     = CSR_NONE;
        dec.sys_op     = SYS_NONE;

        // ── Opcode dispatch ───────────────────────────────────────────────────
        case (f_opcode(in_instruction))

            // -----------------------------------------------------------------
            //  R-TYPE 64-bit
            //  RV64I: ADD SUB XOR OR AND SLL SRL SRA SLT SLTU
            //  M-ext: MUL MULH MULHSU MULHU DIV DIVU REM REMU
            // -----------------------------------------------------------------
            OpcR: begin
                dec.instr_type = R_TYPE;
                dec.rs1        = f_rs1(in_instruction);
                dec.rs2        = f_rs2(in_instruction);
                dec.rd         = f_rd (in_instruction);
                dec.rs1_used   = 1'b1;
                dec.rs2_used   = 1'b1;
                dec.rd_used    = 1'b1;

                if (f_funct7(in_instruction) == Funct7M) begin
                    case (f_funct3(in_instruction))
                        3'h0: aop = ALU_MUL;
                        3'h1: aop = ALU_MULH;
                        3'h2: aop = ALU_MULHSU;
                        3'h3: aop = ALU_MULHU;
                        3'h4: aop = ALU_DIV;
                        3'h5: aop = ALU_DIVU;
                        3'h6: aop = ALU_REM;
                        3'h7: aop = ALU_REMU;
                        default: unknown = 1'b1;
                    endcase
                end else begin
                    case ({f_funct7(in_instruction), f_funct3(in_instruction)})
                        {7'h00, 3'h0}: aop = ALU_ADD;
                        {7'h20, 3'h0}: aop = ALU_SUB;
                        {7'h00, 3'h4}: aop = ALU_XOR;
                        {7'h00, 3'h6}: aop = ALU_OR;
                        {7'h00, 3'h7}: aop = ALU_AND;
                        {7'h00, 3'h1}: aop = ALU_SLL;
                        {7'h00, 3'h5}: aop = ALU_SRL;
                        {7'h20, 3'h5}: aop = ALU_SRA;
                        {7'h00, 3'h2}: aop = ALU_SLT;
                        {7'h00, 3'h3}: aop = ALU_SLTU;
                        default:        unknown = 1'b1;
                    endcase
                end
            end

            // -----------------------------------------------------------------
            //  R-TYPE *W  (RV64 word-width variants)
            //  RV64I: ADDW SUBW SLLW SRLW SRAW
            //  M-ext: MULW DIVW DIVUW REMW REMUW
            // -----------------------------------------------------------------
            OpcRW: begin
                dec.instr_type = R_TYPE;
                dec.rs1        = f_rs1(in_instruction);
                dec.rs2        = f_rs2(in_instruction);
                dec.rd         = f_rd (in_instruction);
                dec.rs1_used   = 1'b1;
                dec.rs2_used   = 1'b1;
                dec.rd_used    = 1'b1;

                if (f_funct7(in_instruction) == Funct7M) begin
                    case (f_funct3(in_instruction))
                        3'h0: aop = ALU_MULW;
                        3'h4: aop = ALU_DIVW;
                        3'h5: aop = ALU_DIVUW;
                        3'h6: aop = ALU_REMW;
                        3'h7: aop = ALU_REMUW;
                        default: unknown = 1'b1;
                    endcase
                end else begin
                    case ({f_funct7(in_instruction), f_funct3(in_instruction)})
                        {7'h00, 3'h0}: aop = ALU_ADDW;
                        {7'h20, 3'h0}: aop = ALU_SUBW;
                        {7'h00, 3'h1}: aop = ALU_SLLW;
                        {7'h00, 3'h5}: aop = ALU_SRLW;
                        {7'h20, 3'h5}: aop = ALU_SRAW;
                        default:        unknown = 1'b1;
                    endcase
                end
            end

            // -----------------------------------------------------------------
            //  I-TYPE ALU 64-bit
            //  ADDI XORI ORI ANDI SLTI SLTIU SLLI SRLI SRAI
            // -----------------------------------------------------------------
            OpcIAlu: begin
                dec.instr_type = I_TYPE;
                dec.rs1        = f_rs1(in_instruction);
                dec.rd         = f_rd (in_instruction);
                dec.imm        = imm_I(in_instruction);
                dec.rs1_used   = 1'b1;
                dec.rd_used    = 1'b1;
                dec.imm_used   = 1'b1;

                case (f_funct3(in_instruction))
                    3'h0: aop = ALU_ADD;
                    3'h4: aop = ALU_XOR;
                    3'h6: aop = ALU_OR;
                    3'h7: aop = ALU_AND;
                    3'h2: aop = ALU_SLT;
                    3'h3: aop = ALU_SLTU;
                    3'h1: begin  // SLLI — funct7 must be 0
                        if (f_funct7(in_instruction) == 7'h00) aop = ALU_SLL;
                        else                                    unknown = 1'b1;
                    end
                    3'h5: begin  // SRLI / SRAI
                        case (f_funct7(in_instruction))
                            7'h00:   aop = ALU_SRL;
                            7'h20:   aop = ALU_SRA;
                            default: unknown = 1'b1;
                        endcase
                    end
                    default: unknown = 1'b1;
                endcase
            end

            // -----------------------------------------------------------------
            //  I-TYPE ALU *W
            //  ADDIW SLLIW SRLIW SRAIW
            // -----------------------------------------------------------------
            OpcIAluW: begin
                dec.instr_type = I_TYPE;
                dec.rs1        = f_rs1(in_instruction);
                dec.rd         = f_rd (in_instruction);
                dec.imm        = imm_I(in_instruction);
                dec.rs1_used   = 1'b1;
                dec.rd_used    = 1'b1;
                dec.imm_used   = 1'b1;

                case (f_funct3(in_instruction))
                    3'h0: aop = ALU_ADDW;
                    3'h1: begin  // SLLIW
                        if (f_funct7(in_instruction) == 7'h00) aop = ALU_SLLW;
                        else                                    unknown = 1'b1;
                    end
                    3'h5: begin  // SRLIW / SRAIW
                        case (f_funct7(in_instruction))
                            7'h00:   aop = ALU_SRLW;
                            7'h20:   aop = ALU_SRAW;
                            default: unknown = 1'b1;
                        endcase
                    end
                    default: unknown = 1'b1;
                endcase
            end

            // -----------------------------------------------------------------
            //  I-TYPE Load
            //  LB LH LW LD LBU LHU LWU
            // -----------------------------------------------------------------
            OpcILoad: begin
                dec.instr_type = I_TYPE;
                dec.rs1        = f_rs1(in_instruction);
                dec.rd         = f_rd (in_instruction);
                dec.imm        = imm_I(in_instruction);
                dec.rs1_used   = 1'b1;
                dec.rd_used    = 1'b1;
                dec.imm_used   = 1'b1;
                dec.mem_read   = 1'b1;
                aop            = ALU_ADD;  // ea = rs1 + imm

                case (f_funct3(in_instruction))
                    3'h0: dec.mem_op = LOAD_BYTE;
                    3'h1: dec.mem_op = LOAD_HALF;
                    3'h2: dec.mem_op = LOAD_WORD;
                    3'h3: dec.mem_op = LOAD_DOUBLE;
                    3'h4: dec.mem_op = LOAD_BYTE_U;
                    3'h5: dec.mem_op = LOAD_HALF_U;
                    3'h6: dec.mem_op = LOAD_WORD_U;
                    default: unknown = 1'b1;
                endcase
            end

            // -----------------------------------------------------------------
            //  JALR
            // -----------------------------------------------------------------
            OpcIJalr: begin
                dec.instr_type = I_TYPE;
                dec.rs1        = f_rs1(in_instruction);
                dec.rd         = f_rd (in_instruction);
                dec.imm        = imm_I(in_instruction);
                dec.rs1_used   = 1'b1;
                dec.rd_used    = 1'b1;
                dec.imm_used   = 1'b1;
                dec.jump       = 1'b1;
                aop            = ALU_PASS_A;   // rd ← PC+4 (execute stage supplies)
                if (f_funct3(in_instruction) != 3'h0) unknown = 1'b1;
            end

            // -----------------------------------------------------------------
            //  S-TYPE
            //  SB SH SW SD
            // -----------------------------------------------------------------
            OpcS: begin
                dec.instr_type = S_TYPE;
                dec.rs1        = f_rs1(in_instruction);
                dec.rs2        = f_rs2(in_instruction);
                dec.imm        = imm_S(in_instruction);
                dec.rs1_used   = 1'b1;
                dec.rs2_used   = 1'b1;
                dec.imm_used   = 1'b1;
                dec.mem_write  = 1'b1;
                aop            = ALU_ADD;  // ea = rs1 + imm

                case (f_funct3(in_instruction))
                    3'h0: dec.mem_op = STORE_BYTE;
                    3'h1: dec.mem_op = STORE_HALF;
                    3'h2: dec.mem_op = STORE_WORD;
                    3'h3: dec.mem_op = STORE_DOUBLE;
                    default: unknown = 1'b1;
                endcase
            end

            // -----------------------------------------------------------------
            //  B-TYPE
            //  BEQ BNE BLT BGE BLTU BGEU
            // -----------------------------------------------------------------
            OpcB: begin
                dec.instr_type = B_TYPE;
                dec.rs1        = f_rs1(in_instruction);
                dec.rs2        = f_rs2(in_instruction);
                dec.imm        = imm_B(in_instruction);
                dec.rs1_used   = 1'b1;
                dec.rs2_used   = 1'b1;
                dec.imm_used   = 1'b1;
                dec.branch     = 1'b1;
                aop            = ALU_SUB;  // flags from rs1−rs2 drive branch logic

                case (f_funct3(in_instruction))
                    3'h0: dec.branch_op = BR_BEQ;
                    3'h1: dec.branch_op = BR_BNE;
                    3'h4: dec.branch_op = BR_BLT;
                    3'h5: dec.branch_op = BR_BGE;
                    3'h6: dec.branch_op = BR_BLTU;
                    3'h7: dec.branch_op = BR_BGEU;
                    default: unknown = 1'b1;
                endcase
            end

            // -----------------------------------------------------------------
            //  LUI
            // -----------------------------------------------------------------
            OpcULui: begin
                dec.instr_type = U_TYPE;
                dec.rd         = f_rd(in_instruction);
                dec.imm        = imm_U(in_instruction);
                dec.rd_used    = 1'b1;
                dec.imm_used   = 1'b1;
                aop            = ALU_LUI_PASS;
            end

            // -----------------------------------------------------------------
            //  AUIPC
            // -----------------------------------------------------------------
            OpcUAui: begin
                dec.instr_type = U_TYPE;
                dec.rd         = f_rd(in_instruction);
                dec.imm        = imm_U(in_instruction);
                dec.rd_used    = 1'b1;
                dec.imm_used   = 1'b1;
                aop            = ALU_AUIPC;
            end

            // -----------------------------------------------------------------
            //  JAL
            // -----------------------------------------------------------------
            OpcJJal: begin
                dec.instr_type = J_TYPE;
                dec.rd         = f_rd(in_instruction);
                dec.imm        = imm_J(in_instruction);
                dec.rd_used    = 1'b1;
                dec.imm_used   = 1'b1;
                dec.jump       = 1'b1;
                aop            = ALU_PASS_A;   // rd ← PC+4
            end

            // -----------------------------------------------------------------
            //  SYSTEM — CSR, ECALL, EBREAK, MRET, SRET, WFI
            // -----------------------------------------------------------------
            OpcSystem: begin
                if (f_funct3(in_instruction) != 3'h0) begin
                    // ── CSR variants ─────────────────────────────────────────
                    dec.instr_type = CSR_TYPE;
                    dec.csr_addr   = f_csr(in_instruction);
                    dec.rd         = f_rd(in_instruction);
                    dec.rd_used    = 1'b1;
                    dec.csr_access = 1'b1;

                    case (f_funct3(in_instruction))
                        3'h1: begin  // CSRRW
                            dec.csr_op   = CSR_CSRRW;
                            dec.rs1      = f_rs1(in_instruction);
                            dec.rs1_used = 1'b1;
                        end
                        3'h2: begin  // CSRRS
                            dec.csr_op   = CSR_CSRRS;
                            dec.rs1      = f_rs1(in_instruction);
                            dec.rs1_used = 1'b1;
                        end
                        3'h3: begin  // CSRRC
                            dec.csr_op   = CSR_CSRRC;
                            dec.rs1      = f_rs1(in_instruction);
                            dec.rs1_used = 1'b1;
                        end
                        3'h5: begin  // CSRRWI
                            dec.csr_op   = CSR_CSRRWI;
                            dec.zimm     = f_zimm(in_instruction);
                            dec.imm      = 64'(f_zimm(in_instruction));
                            dec.imm_used = 1'b1;
                        end
                        3'h6: begin  // CSRRSI
                            dec.csr_op   = CSR_CSRRSI;
                            dec.zimm     = f_zimm(in_instruction);
                            dec.imm      = 64'(f_zimm(in_instruction));
                            dec.imm_used = 1'b1;
                        end
                        3'h7: begin  // CSRRCI
                            dec.csr_op   = CSR_CSRRCI;
                            dec.zimm     = f_zimm(in_instruction);
                            dec.imm      = 64'(f_zimm(in_instruction));
                            dec.imm_used = 1'b1;
                        end
                        default: unknown = 1'b1;
                    endcase

                end else begin
                    // ── Privileged (funct3 = 000) ─────────────────────────────
                    dec.instr_type = SYS_TYPE;
                    dec.sys_call   = 1'b1;

                    case (in_instruction[31:20])  // f12
                        12'h000: dec.sys_op = SYS_ECALL;
                        12'h001: dec.sys_op = SYS_EBREAK;
                        12'h302: dec.sys_op = SYS_MRET;
                        12'h102: dec.sys_op = SYS_SRET;
                        12'h105: dec.sys_op = SYS_WFI;
                        default:  unknown = 1'b1;
                    endcase
                end
            end

            // -----------------------------------------------------------------
            //  FENCE / FENCE.I
            // -----------------------------------------------------------------
            OpcFence: begin
                dec.instr_type = SYS_TYPE;
                dec.sys_call   = 1'b1;
                dec.sys_op     = (f_funct3(in_instruction) == 3'h1)
                                 ? SYS_FENCE_I : SYS_FENCE;
            end

            // -----------------------------------------------------------------
            //  Illegal / unknown opcode
            // -----------------------------------------------------------------
            default: unknown = 1'b1;

        endcase

        // Mark illegal encoding — control unit raises trap.
        // instr_type left as R_TYPE (harmless default); control unit checks unknown.
        if (unknown)
            dec.instr_type = R_TYPE;

    end  // always_comb

endmodule


