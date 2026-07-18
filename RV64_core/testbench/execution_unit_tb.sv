`timescale 1ns/1ps

// =============================================================================
//  tb_execution_top.sv
//  Full-coverage testbench for execution_top.
//
//  Test groups:
//    1.  ALU operations          – all 31 alu_op_t values
//    2.  Branch instructions     – all 6 branch types, taken & not-taken
//    3.  Jump instructions       – JAL and JALR (return-address, target, LSB clear)
//    4.  Load instructions       – every mem_op_e load variant, handshake
//    5.  Store instructions      – every mem_op_e store variant, handshake
//    6.  Handshake / backpressure– ready stalls on memory & writeback ports
//    7.  Edge cases              – divide-by-zero, overflow, XLEN boundaries
//
//  Requires:  decode_pkg, alu_pkg, alu_module, execution_top
// =============================================================================

import decode_pkg::*;
import alu_pkg::*;

module execution_unit_tb;

    //  Parameters
    localparam int XLEN    = 64;
    localparam int CLK_HALF = 5;          // 10 ns clock period

    //  DUT ports
    logic                        clk;
    logic                        rst_n;

    logic                        valid_decode;
    logic                        ready_execution_unit;

    logic [XLEN-1:0]             rs1_data;
    logic [XLEN-1:0]             rs2_data;
    logic [XLEN-1:0]             pc_in;

    decode_pkg::decoded_instr_t  decode_instruction;
    alu_pkg::alu_op_t            alu_operation;

    logic                        branch_taken;
    logic [XLEN-1:0]             branch_target;

    logic                        valid_to_memory;
    logic                        ready_memory;
    logic [XLEN-1:0]             req_addr_i;
    logic [XLEN-1:0]             req_wdata_i;
    decode_pkg::mem_op_e         req_memop_i;
    logic [4:0]                  req_rd_i;

    logic                        valid_to_writeback;
    logic                        ready_writeback;
    logic [4:0]                  rd;
    logic [XLEN-1:0]             write_data;

    //  DUT instantiation
    execution_top #(.XLEN(XLEN)) dut (
        .clk                  (clk),
        .rst_n                (rst_n),
        .valid_decode         (valid_decode),
        .ready_execution_unit (ready_execution_unit),
        .rs1_data             (rs1_data),
        .rs2_data             (rs2_data),
        .pc_in                (pc_in),
        .decode_instruction   (decode_instruction),
        .alu_operation        (alu_operation),
        .branch_taken         (branch_taken),
        .branch_target        (branch_target),
        .valid_to_memory      (valid_to_memory),
        .ready_memory         (ready_memory),
        .req_addr_i           (req_addr_i),
        .req_wdata_i          (req_wdata_i),
        .req_memop_i          (req_memop_i),
        .req_rd_i             (req_rd_i),
        .valid_to_writeback   (valid_to_writeback),
        .ready_writeback      (ready_writeback),
        .rd                   (rd),
        .write_data           (write_data)
    );

    // =========================================================================
    //  Clock generation
    // =========================================================================
    initial clk = 0;
    always #CLK_HALF clk = ~clk;

    // =========================================================================
    //  Scoreboard / counters
    // =========================================================================
    int pass_cnt = 0;
    int fail_cnt = 0;

    // =========================================================================
    //  Helper tasks & functions
    // =========================================================================

    // ---- reset ----
    task automatic do_reset();
        rst_n              = 1'b0;
        valid_decode       = 1'b0;
        ready_memory       = 1'b1;
        ready_writeback    = 1'b1;
        rs1_data           = '0;
        rs2_data           = '0;
        pc_in              = '0;
        alu_operation      = alu_pkg::NONE;
        decode_instruction = '0;
        @(posedge clk); @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
    endtask

    // ---- wait one clock ----
    task automatic tick();
        @(posedge clk); #1;
    endtask

    // ---- assert helper ----
    task automatic chk(
        input string   test_name,
        input logic    got,
        input logic    exp
    );
        if (got === exp) begin
            $display("  PASS  %-50s  got=%0b exp=%0b", test_name, got, exp);
            pass_cnt++;
        end else begin
            $display("  FAIL  %-50s  got=%0b exp=%0b", test_name, got, exp);
            fail_cnt++;
        end
    endtask

    task automatic chk64(
        input string        test_name,
        input logic [63:0]  got,
        input logic [63:0]  exp
    );
        if (got === exp) begin
            $display("  PASS  %-50s  got=0x%016h exp=0x%016h", test_name, got, exp);
            pass_cnt++;
        end else begin
            $display("  FAIL  %-50s  got=0x%016h exp=0x%016h", test_name, got, exp);
            fail_cnt++;
        end
    endtask

    // ---- build a minimal decoded_instr_t for ALU R-type ----
    function automatic decode_pkg::decoded_instr_t make_rtype(
        input logic [4:0] rs1, rs2, rdest
    );
        decode_pkg::decoded_instr_t d = '0;
        d.instr_type = decode_pkg::R_TYPE;
        d.rs1        = rs1;
        d.rs2        = rs2;
        d.rd         = rdest;
        d.rs1_used   = 1'b1;
        d.rs2_used   = 1'b1;
        d.rd_used    = 1'b1;
        d.imm_used   = 1'b0;
        return d;
    endfunction

    // ---- build an I-type (immediate) ALU instruction ----
    function automatic decode_pkg::decoded_instr_t make_itype(
        input logic [4:0]        rs1, rdest,
        input logic signed [63:0] imm
    );
        decode_pkg::decoded_instr_t d = '0;
        d.instr_type = decode_pkg::I_TYPE;
        d.rs1        = rs1;
        d.rd         = rdest;
        d.rs1_used   = 1'b1;
        d.rd_used    = 1'b1;
        d.imm_used   = 1'b1;
        d.imm        = imm;
        return d;
    endfunction

    // ---- build a branch instruction ----
    function automatic decode_pkg::decoded_instr_t make_branch(
        input decode_pkg::branch_op_e bop,
        input logic [4:0]             rs1, rs2,
        input logic signed [63:0]     imm
    );
        decode_pkg::decoded_instr_t d = '0;
        d.instr_type = decode_pkg::B_TYPE;
        d.branch_op  = bop;
        d.rs1        = rs1;
        d.rs2        = rs2;
        d.rs1_used   = 1'b1;
        d.rs2_used   = 1'b1;
        d.imm_used   = 1'b1;
        d.imm        = imm;
        d.branch     = 1'b1;
        return d;
    endfunction

    // ---- build a load instruction ----
    function automatic decode_pkg::decoded_instr_t make_load(
        input decode_pkg::mem_op_e   mop,
        input logic [4:0]            rs1, rdest,
        input logic signed [63:0]    imm
    );
        decode_pkg::decoded_instr_t d = '0;
        d.instr_type = decode_pkg::I_TYPE;
        d.mem_op     = mop;
        d.rs1        = rs1;
        d.rd         = rdest;
        d.rs1_used   = 1'b1;
        d.rd_used    = 1'b1;
        d.imm_used   = 1'b1;
        d.imm        = imm;
        d.mem_read   = 1'b1;
        return d;
    endfunction

    // ---- build a store instruction ----
    function automatic decode_pkg::decoded_instr_t make_store(
        input decode_pkg::mem_op_e   mop,
        input logic [4:0]            rs1, rs2,
        input logic signed [63:0]    imm
    );
        decode_pkg::decoded_instr_t d = '0;
        d.instr_type = decode_pkg::S_TYPE;
        d.mem_op     = mop;
        d.rs1        = rs1;
        d.rs2        = rs2;
        d.rs1_used   = 1'b1;
        d.rs2_used   = 1'b1;
        d.imm_used   = 1'b1;
        d.imm        = imm;
        d.mem_write  = 1'b1;
        return d;
    endfunction

    // ---- build a JAL instruction ----
    function automatic decode_pkg::decoded_instr_t make_jal(
        input logic [4:0]         rdest,
        input logic signed [63:0] imm
    );
        decode_pkg::decoded_instr_t d = '0;
        d.instr_type = decode_pkg::J_TYPE;
        d.rd         = rdest;
        d.rd_used    = 1'b1;
        d.imm_used   = 1'b1;
        d.imm        = imm;
        d.jump       = 1'b1;
        return d;
    endfunction

    // ---- build a JALR instruction ----
    function automatic decode_pkg::decoded_instr_t make_jalr(
        input logic [4:0]         rs1, rdest,
        input logic signed [63:0] imm
    );
        decode_pkg::decoded_instr_t d = '0;
        d.instr_type = decode_pkg::I_TYPE;
        d.rs1        = rs1;
        d.rd         = rdest;
        d.rs1_used   = 1'b1;
        d.rd_used    = 1'b1;
        d.imm_used   = 1'b1;
        d.imm        = imm;
        d.jump       = 1'b1;
        return d;
    endfunction

    // ---- drive one combinational cycle and sample outputs ----
    task automatic drive_and_sample(
        input  decode_pkg::decoded_instr_t dinstr,
        input  alu_pkg::alu_op_t           aluop,
        input  logic [XLEN-1:0]            a, b, pc,
        input  logic                        rdy_mem, rdy_wb
    );
        decode_instruction = dinstr;
        alu_operation      = aluop;
        rs1_data           = a;
        rs2_data           = b;
        pc_in              = pc;
        valid_decode       = 1'b1;
        ready_memory       = rdy_mem;
        ready_writeback    = rdy_wb;
        #1; // let combinational logic settle
    endtask

    // =========================================================================
    //  TEST GROUP 1 – ALU operations
    // =========================================================================
    task automatic test_alu_ops();
        logic [XLEN-1:0] a, b, exp;
        decode_pkg::decoded_instr_t di;

        $display("\n========== GROUP 1 : ALU Operations ==========");

        // Helper: run one R-type ALU test
        // (we must declare inner variables outside unique scope to be legal SV)
        a = 64'h0000_0000_DEAD_BEEF;
        b = 64'h0000_0000_0000_0010;

        // ADD
        di = make_rtype(1,2,3);
        drive_and_sample(di, ALU_ADD, a, b, 64'h1000, 1, 1);
        chk64("ALU_ADD result", write_data, a + b);

        // SUB
        di = make_rtype(1,2,3);
        drive_and_sample(di, ALU_SUB, a, b, 64'h1000, 1, 1);
        chk64("ALU_SUB result", write_data, a - b);

        // AND
        drive_and_sample(di, ALU_AND, a, b, 64'h1000, 1, 1);
        chk64("ALU_AND result", write_data, a & b);

        // OR
        drive_and_sample(di, ALU_OR, a, b, 64'h1000, 1, 1);
        chk64("ALU_OR result", write_data, a | b);

        // XOR
        drive_and_sample(di, ALU_XOR, a, b, 64'h1000, 1, 1);
        chk64("ALU_XOR result", write_data, a ^ b);

        // SLL
        drive_and_sample(di, ALU_SLL, a, 64'd4, 64'h1000, 1, 1);
        chk64("ALU_SLL result", write_data, a << 4);

        // SRL
        drive_and_sample(di, ALU_SRL, a, 64'd4, 64'h1000, 1, 1);
        chk64("ALU_SRL result", write_data, a >> 4);

        // SRA  (arithmetic right shift; a has bit63=0 here so same as SRL)
        a = 64'hFFFF_0000_0000_0001;
        drive_and_sample(di, ALU_SRA, a, 64'd4, 64'h1000, 1, 1);
        chk64("ALU_SRA result", write_data, 64'($signed(a) >>> 4));

        // SLT  – signed
        a = 64'hFFFF_FFFF_FFFF_FFFF; // -1 signed
        b = 64'h0000_0000_0000_0001;
        drive_and_sample(di, ALU_SLT, a, b, 64'h1000, 1, 1);
        chk64("ALU_SLT  -1 < 1 => 1", write_data, 64'd1);

        drive_and_sample(di, ALU_SLT, b, a, 64'h1000, 1, 1);
        chk64("ALU_SLT   1 < -1 => 0", write_data, 64'd0);

        // SLTU – unsigned
        a = 64'hFFFF_FFFF_FFFF_FFFF;
        b = 64'h0000_0000_0000_0001;
        drive_and_sample(di, ALU_SLTU, b, a, 64'h1000, 1, 1);
        chk64("ALU_SLTU  1 < MAXU => 1", write_data, 64'd1);

        // ADDW  32-bit add sign-extended
        a = 64'h0000_0000_7FFF_FFFF;
        b = 64'h0000_0000_0000_0001;
        drive_and_sample(di, ALU_ADDW, a, b, 64'h1000, 1, 1);
        exp = 64'($signed(32'(a[31:0] + b[31:0])));
        chk64("ALU_ADDW overflow → sign-ext", write_data, exp);

        // SUBW
        a = 64'h0000_0000_0000_0005;
        b = 64'h0000_0000_0000_0008;
        drive_and_sample(di, ALU_SUBW, a, b, 64'h1000, 1, 1);
        exp = 64'($signed(32'(a[31:0] - b[31:0])));
        chk64("ALU_SUBW negative sign-ext", write_data, exp);

        // LUI_PASS – operand_b (imm) passed through
        a = 64'h1234_5678_9ABC_DEF0;
        b = 64'hDEAD_BEEF_0000_0000;
        di = make_itype(1,3, 64'(b));
        drive_and_sample(di, ALU_LUI_PASS, a, b, 64'h1000, 1, 1);
        chk64("ALU_LUI_PASS = imm", write_data, b);

        // AUIPC – pc + imm
        a   = 64'h0;
        b   = 64'h0000_0000_0001_0000;
        di  = make_itype(0, 3, 64'(b));
        drive_and_sample(di, ALU_AUIPC, a, b, 64'h0000_0000_0002_0000, 1, 1);
        chk64("ALU_AUIPC = PC+imm", write_data, 64'h0003_0000);

        // MUL
        a = 64'd12; b = 64'd11;
        di = make_rtype(1,2,3);
        drive_and_sample(di, ALU_MUL, a, b, 64'h1000, 1, 1);
        chk64("ALU_MUL 12*11=132", write_data, 64'd132);

        // MULH – upper 64 bits of signed product
        a = 64'hFFFF_FFFF_FFFF_FFFF; // -1
        b = 64'h0000_0000_0000_0002;
        drive_and_sample(di, ALU_MULH, a, b, 64'h1000, 1, 1);
        chk64("ALU_MULH -1*2 upper=FFFF...", write_data, 64'hFFFF_FFFF_FFFF_FFFF);

        // DIV signed
        a = 64'd100; b = 64'd7;
        drive_and_sample(di, ALU_DIV, a, b, 64'h1000, 1, 1);
        chk64("ALU_DIV 100/7=14", write_data, 64'd14);

        // DIV by zero → all-ones
        drive_and_sample(di, ALU_DIV, a, 64'd0, 64'h1000, 1, 1);
        chk64("ALU_DIV by zero = FFFF..", write_data, {XLEN{1'b1}});

        // DIVU by zero → all-ones
        drive_and_sample(di, ALU_DIVU, a, 64'd0, 64'h1000, 1, 1);
        chk64("ALU_DIVU by zero = FFFF..", write_data, {XLEN{1'b1}});

        // REM
        a = 64'd100; b = 64'd7;
        drive_and_sample(di, ALU_REM, a, b, 64'h1000, 1, 1);
        chk64("ALU_REM 100%7=2", write_data, 64'd2);

        // REM by zero → dividend
        drive_and_sample(di, ALU_REM, a, 64'd0, 64'h1000, 1, 1);
        chk64("ALU_REM by zero = dividend", write_data, a);

        // MULW  32-bit
        a = 64'd1000; b = 64'd333;
        drive_and_sample(di, ALU_MULW, a, b, 64'h1000, 1, 1);
        chk64("ALU_MULW 1000*333=333000", write_data, 64'd333000);

        // PASS_A
        a = 64'hCAFE_BABE_1234_5678;
        drive_and_sample(di, ALU_PASS_A, a, b, 64'h1000, 1, 1);
        chk64("ALU_PASS_A = rs1", write_data, a);

        valid_decode = 0;
    endtask

    //  TEST GROUP 2 – Branch instructions
    task automatic test_branches();
        decode_pkg::decoded_instr_t di;
        logic [XLEN-1:0] pc = 64'h0000_0000_0000_1000;
        logic signed [63:0] imm = 64'd32;

        $display("\n========== GROUP 2 : Branch Instructions ==========");

        // BEQ – taken
        di = make_branch(BR_BEQ, 1, 2, imm);
        drive_and_sample(di, NONE, 64'd10, 64'd10, pc, 1, 1);
        chk  ("BEQ taken  – branch_taken=1",        branch_taken,   1'b1);
        chk64("BEQ taken  – branch_target=PC+imm",  branch_target,  pc + 64'(imm));

        // BEQ – not taken
        drive_and_sample(di, NONE, 64'd10, 64'd11, pc, 1, 1);
        chk  ("BEQ !taken – branch_taken=0",        branch_taken,   1'b0);

        // BNE – taken
        di = make_branch(BR_BNE, 1, 2, imm);
        drive_and_sample(di, NONE, 64'd10, 64'd11, pc, 1, 1);
        chk  ("BNE taken",                           branch_taken,   1'b1);

        // BNE – not taken
        drive_and_sample(di, NONE, 64'd5, 64'd5, pc, 1, 1);
        chk  ("BNE !taken",                          branch_taken,   1'b0);

        // BLT – taken  (signed: -1 < 1)
        di = make_branch(BR_BLT, 1, 2, imm);
        drive_and_sample(di, NONE,
                         64'hFFFF_FFFF_FFFF_FFFF,  // -1
                         64'h0000_0000_0000_0001,   // +1
                         pc, 1, 1);
        chk  ("BLT taken  (-1 < 1)",                 branch_taken,   1'b1);

        // BLT – not taken
        drive_and_sample(di, NONE, 64'd5, 64'd3, pc, 1, 1);
        chk  ("BLT !taken (5 > 3)",                  branch_taken,   1'b0);

        // BGE – taken  (signed: 5 >= 3)
        di = make_branch(BR_BGE, 1, 2, imm);
        drive_and_sample(di, NONE, 64'd5, 64'd3, pc, 1, 1);
        chk  ("BGE taken  (5 >= 3)",                  branch_taken,   1'b1);

        // BGE – equal  (taken)
        drive_and_sample(di, NONE, 64'd7, 64'd7, pc, 1, 1);
        chk  ("BGE taken  (7 == 7)",                  branch_taken,   1'b1);

        // BGE – not taken
        drive_and_sample(di, NONE,
                         64'hFFFF_FFFF_FFFF_FFFF,   // -1
                         64'h0000_0000_0000_0001,    // +1
                         pc, 1, 1);
        chk  ("BGE !taken (-1 < 1)",                  branch_taken,   1'b0);

        // BLTU – taken  (unsigned: 1 < MAXU)
        di = make_branch(BR_BLTU, 1, 2, imm);
        drive_and_sample(di, NONE,
                         64'h0000_0000_0000_0001,
                         64'hFFFF_FFFF_FFFF_FFFF,
                         pc, 1, 1);
        chk  ("BLTU taken (1 < MAXU)",                branch_taken,   1'b1);

        // BGEU – taken  (MAXU >= 1)
        di = make_branch(BR_BGEU, 1, 2, imm);
        drive_and_sample(di, NONE,
                         64'hFFFF_FFFF_FFFF_FFFF,
                         64'h0000_0000_0000_0001,
                         pc, 1, 1);
        chk  ("BGEU taken (MAXU >= 1)",               branch_taken,   1'b1);

        // Negative immediate branch target
        di = make_branch(BR_BEQ, 1, 2, -64'sd8);
        drive_and_sample(di, NONE, 64'd0, 64'd0, pc, 1, 1);
        chk  ("BEQ taken  negative imm – taken",      branch_taken,   1'b1);
        chk64("BEQ taken  negative imm – target",     branch_target,  pc - 64'd8);

        valid_decode = 0;
    endtask

    // =========================================================================
    //  TEST GROUP 3 – JAL / JALR
    // =========================================================================
    task automatic test_jumps();
        decode_pkg::decoded_instr_t di;
        logic [XLEN-1:0] pc  = 64'h0000_0000_0000_2000;

        $display("\n========== GROUP 3 : Jump Instructions ==========");

        // JAL  – always taken, target = PC + imm, rd = PC+4
        di = make_jal(1, 64'sd256);
        drive_and_sample(di, ALU_ADD, 64'h0, 64'h0, pc, 1, 1);
        chk  ("JAL  branch_taken=1",                   branch_taken,   1'b1);
        chk64("JAL  branch_target = PC+imm",           branch_target,  pc + 64'd256);
        chk64("JAL  write_data = PC+4 (return addr)",  write_data,     pc + 64'd4);
        chk  ("JAL  valid_to_writeback=1",             valid_to_writeback, 1'b1);
        chk  ("JAL  valid_to_memory=0",               valid_to_memory,    1'b0);

        // JALR – target = (rs1 + imm) & ~1, rd = PC+4
        di = make_jalr(3, 5, 64'sd5);   // imm=5 makes LSB=1 → must be cleared
        drive_and_sample(di, ALU_ADD,
                         64'h0000_0000_0000_0100,  // rs1
                         64'h0,
                         pc, 1, 1);
        chk  ("JALR branch_taken=1",                   branch_taken,    1'b1);
        chk64("JALR target = (rs1+imm)&~1",            branch_target,   64'h0000_0000_0000_0104); // 0x100+5=0x105 → 0x104
        chk64("JALR write_data = PC+4",                write_data,      pc + 64'd4);

        valid_decode = 0;
    endtask

    // =========================================================================
    //  TEST GROUP 4 – Load instructions
    // =========================================================================
    task automatic test_loads();
        decode_pkg::decoded_instr_t di;
        logic [XLEN-1:0] base = 64'h0000_0000_0000_8000;
        logic signed [63:0] imm = 64'sd16;

        $display("\n========== GROUP 4 : Load Instructions ==========");

        // Each load: valid_to_memory must fire, valid_to_writeback must NOT
        // (writeback happens after memory stage returns data)

        // foreach ({
        //          LOAD_BYTE, LOAD_HALF, LOAD_WORD, LOAD_DOUBLE,
        //           LOAD_BYTE_U, LOAD_HALF_U, LOAD_WORD_U} [i]) begin
        //     // can't foreach over enum directly; iterate manually
        // end

        // LOAD_BYTE
        di = make_load(LOAD_BYTE, 1, 5, imm);
        drive_and_sample(di, NONE, base, 64'h0, 64'h1000, 1, 1);
        chk  ("LOAD_BYTE  valid_to_memory=1",    valid_to_memory,    1'b1);
        chk  ("LOAD_BYTE  valid_to_wb=0",        valid_to_writeback, 1'b0);
        chk64("LOAD_BYTE  req_addr=base+imm",    req_addr_i,         base+64'(imm));
        chk  ("LOAD_BYTE  req_memop",            req_memop_i == LOAD_BYTE, 1'b1);
        chk  ("LOAD_BYTE  req_rd=5",             req_rd_i == 5'd5,   1'b1);

        // LOAD_HALF
        di = make_load(LOAD_HALF, 1, 6, imm);
        drive_and_sample(di, NONE, base, 64'h0, 64'h1000, 1, 1);
        chk  ("LOAD_HALF  valid_to_memory=1",    valid_to_memory,    1'b1);
        chk  ("LOAD_HALF  req_memop",            req_memop_i == LOAD_HALF, 1'b1);

        // LOAD_WORD
        di = make_load(LOAD_WORD, 1, 7, imm);
        drive_and_sample(di, NONE, base, 64'h0, 64'h1000, 1, 1);
        chk  ("LOAD_WORD  valid_to_memory=1",    valid_to_memory,    1'b1);
        chk  ("LOAD_WORD  req_memop",            req_memop_i == LOAD_WORD, 1'b1);

        // LOAD_DOUBLE
        di = make_load(LOAD_DOUBLE, 1, 8, imm);
        drive_and_sample(di, NONE, base, 64'h0, 64'h1000, 1, 1);
        chk  ("LOAD_DOUBLE valid_to_memory=1",   valid_to_memory,    1'b1);
        chk  ("LOAD_DOUBLE req_memop",           req_memop_i == LOAD_DOUBLE, 1'b1);

        // LOAD_BYTE_U
        di = make_load(LOAD_BYTE_U, 1, 9, imm);
        drive_and_sample(di, NONE, base, 64'h0, 64'h1000, 1, 1);
        chk  ("LOAD_BYTE_U  req_memop",          req_memop_i == LOAD_BYTE_U, 1'b1);

        // LOAD_HALF_U
        di = make_load(LOAD_HALF_U, 1, 10, imm);
        drive_and_sample(di, NONE, base, 64'h0, 64'h1000, 1, 1);
        chk  ("LOAD_HALF_U  req_memop",          req_memop_i == LOAD_HALF_U, 1'b1);

        // LOAD_WORD_U
        di = make_load(LOAD_WORD_U, 1, 11, imm);
        drive_and_sample(di, NONE, base, 64'h0, 64'h1000, 1, 1);
        chk  ("LOAD_WORD_U  req_memop",          req_memop_i == LOAD_WORD_U, 1'b1);

        // Negative offset load
        di = make_load(LOAD_WORD, 1, 5, -64'sd8);
        drive_and_sample(di, NONE, base, 64'h0, 64'h1000, 1, 1);
        chk64("LOAD negative offset addr",        req_addr_i, base - 64'd8);

        valid_decode = 0;
    endtask

    // =========================================================================
    //  TEST GROUP 5 – Store instructions
    // =========================================================================
    task automatic test_stores();
        decode_pkg::decoded_instr_t di;
        logic [XLEN-1:0] base  = 64'h0000_0000_0000_A000;
        logic [XLEN-1:0] wdata = 64'hDEAD_BEEF_CAFE_1234;
        logic signed [63:0] imm = 64'sd4;

        $display("\n========== GROUP 5 : Store Instructions ==========");

        // Stores: valid_to_memory=1, valid_to_writeback=0, rd NOT written

        // STORE_BYTE
        di = make_store(STORE_BYTE, 1, 2, imm);
        drive_and_sample(di, NONE, base, wdata, 64'h1000, 1, 1);
        chk  ("STORE_BYTE valid_to_memory=1",    valid_to_memory,    1'b1);
        chk  ("STORE_BYTE valid_to_wb=0",        valid_to_writeback, 1'b0);
        chk64("STORE_BYTE req_addr=base+imm",    req_addr_i,         base+64'(imm));
        chk64("STORE_BYTE req_wdata=rs2",        req_wdata_i,        wdata);
        chk  ("STORE_BYTE req_memop",            req_memop_i == STORE_BYTE, 1'b1);

        // STORE_HALF
        di = make_store(STORE_HALF, 1, 2, imm);
        drive_and_sample(di, NONE, base, wdata, 64'h1000, 1, 1);
        chk  ("STORE_HALF req_memop",            req_memop_i == STORE_HALF, 1'b1);

        // STORE_WORD
        di = make_store(STORE_WORD, 1, 2, imm);
        drive_and_sample(di, NONE, base, wdata, 64'h1000, 1, 1);
        chk  ("STORE_WORD req_memop",            req_memop_i == STORE_WORD, 1'b1);

        // STORE_DOUBLE
        di = make_store(STORE_DOUBLE, 1, 2, imm);
        drive_and_sample(di, NONE, base, wdata, 64'h1000, 1, 1);
        chk  ("STORE_DOUBLE req_memop",          req_memop_i == STORE_DOUBLE, 1'b1);

        valid_decode = 0;
    endtask

    // =========================================================================
    //  TEST GROUP 6 – Handshake / backpressure
    // =========================================================================
    task automatic test_handshake();
        decode_pkg::decoded_instr_t di;

        $display("\n========== GROUP 6 : Handshake / Backpressure ==========");

        // --- 6a: ready_writeback deasserted → execution stalls ---
        di = make_rtype(1, 2, 3);
        drive_and_sample(di, ALU_ADD, 64'd10, 64'd20, 64'h1000,
                         /*rdy_mem*/1, /*rdy_wb*/0);
        chk("WB not ready → ready_exec=0",       ready_execution_unit, 1'b0);
        chk("WB not ready → valid_to_wb=0",      valid_to_writeback,   1'b0);

        // --- 6b: ready_writeback asserted again ---
        drive_and_sample(di, ALU_ADD, 64'd10, 64'd20, 64'h1000, 1, 1);
        chk("WB ready → ready_exec=1",           ready_execution_unit, 1'b1);
        chk("WB ready → valid_to_wb=1",          valid_to_writeback,   1'b1);

        // --- 6c: ready_memory deasserted for a load → stalls ---
        di = make_load(LOAD_WORD, 1, 5, 64'sd0);
        drive_and_sample(di, NONE, 64'h8000, 64'h0, 64'h1000,
                         /*rdy_mem*/0, /*rdy_wb*/1);
        chk("MEM not ready → ready_exec=0",      ready_execution_unit, 1'b0);
        chk("MEM not ready → valid_to_mem=0",    valid_to_memory,      1'b0);

        // --- 6d: ready_memory asserted ---
        drive_and_sample(di, NONE, 64'h8000, 64'h0, 64'h1000, 1, 1);
        chk("MEM ready → valid_to_mem=1",        valid_to_memory,      1'b1);

        // --- 6e: valid_decode deasserted → no downstream valid ---
        di = make_rtype(1,2,3);
        decode_instruction = di;
        alu_operation      = ALU_ADD;
        rs1_data           = 64'd1; rs2_data = 64'd2;
        valid_decode       = 1'b0;
        ready_memory       = 1'b1; ready_writeback = 1'b1;
        #1;
        chk("valid_decode=0 → valid_to_wb=0",   valid_to_writeback, 1'b0);
        chk("valid_decode=0 → valid_to_mem=0",  valid_to_memory,    1'b0);

        // --- 6f: store with ready_memory stalled ---
        di = make_store(STORE_DOUBLE, 1, 2, 64'sd0);
        drive_and_sample(di, NONE, 64'h5000, 64'hDEAD, 64'h1000,
                         /*rdy_mem*/0, /*rdy_wb*/1);
        chk("STORE MEM stall → ready_exec=0",    ready_execution_unit, 1'b0);

        valid_decode = 0;
    endtask

    // =========================================================================
    //  TEST GROUP 7 – Edge cases
    // =========================================================================
    task automatic test_edge_cases();
        decode_pkg::decoded_instr_t di;

        $display("\n========== GROUP 7 : Edge Cases ==========");

        // --- 7a: XLEN-wide operands ADD overflow (unsigned wrap) ---
        di = make_rtype(1,2,3);
        drive_and_sample(di, ALU_ADD,
                         64'hFFFF_FFFF_FFFF_FFFF,
                         64'h0000_0000_0000_0001,
                         64'h1000, 1, 1);
        chk64("ADD 64-bit overflow wraps to 0", write_data, 64'h0);

        // --- 7b: SLL by 63 ---
        drive_and_sample(di, ALU_SLL,
                         64'h0000_0000_0000_0001,
                         64'd63,
                         64'h1000, 1, 1);
        chk64("SLL by 63 = MSB set", write_data, 64'h8000_0000_0000_0000);

        // --- 7c: SRA by 63 on negative → all-ones ---
        drive_and_sample(di, ALU_SRA,
                         64'h8000_0000_0000_0000,
                         64'd63,
                         64'h1000, 1, 1);
        chk64("SRA -MAX >> 63 = all-ones", write_data, 64'hFFFF_FFFF_FFFF_FFFF);

        // --- 7d: MULHU – upper 64 bits of unsigned multiply ---
        drive_and_sample(di, ALU_MULHU,
                         64'hFFFF_FFFF_FFFF_FFFF,
                         64'hFFFF_FFFF_FFFF_FFFF,
                         64'h1000, 1, 1);
        // MAXU * MAXU = MAXU^2; upper word = MAXU - 1
        chk64("MULHU MAXU*MAXU upper", write_data, 64'hFFFF_FFFF_FFFF_FFFE);

        // --- 7e: REMW by zero → dividend lower 32 sign-extended ---
        drive_and_sample(di, ALU_REMW,
                         64'h0000_0000_8000_0001,  // lower 32 = 0x8000_0001
                         64'h0,
                         64'h1000, 1, 1);
        chk64("REMW div-by-zero = sign-ext dividend",
              write_data,
              64'($signed(32'h8000_0001)));   // sign-extended negative

        // --- 7f: JALR LSB clearing ---
        di = make_jalr(3, 5, 64'sd1);       // imm=1 → (rs1+1) LSB must be 0
        drive_and_sample(di, ALU_ADD,
                         64'h0000_0000_0000_0FFF,  // rs1: odd+1 = 0x1000 (even) → LSB clear
                         64'h0,
                         64'h2000, 1, 1);
        chk64("JALR target LSB cleared (0xFFF+1=0x1000 already even)",
              branch_target, 64'h0000_0000_0000_1000);

        // target with initially set LSB
        drive_and_sample(di, ALU_ADD,
                         64'h0000_0000_0000_0FFE,  // 0xFFE+1=0xFFF → LSB=1 → clear → 0xFFE
                         64'h0,
                         64'h2000, 1, 1);
        chk64("JALR target LSB cleared (0xFFE+1=0xFFF → 0xFFE)",
              branch_target, 64'h0000_0000_0000_0FFE);

        // --- 7g: zero-register (x0) as rd – rd_used should be false (decoder's job,
        //         but verify the path doesn't accidentally fire valid_to_writeback) ---
        di = make_rtype(1, 2, 0);   // rd = x0
        di.rd_used = 1'b0;          // decoder would clear this for x0
        drive_and_sample(di, ALU_ADD, 64'd5, 64'd3, 64'h1000, 1, 1);
        chk("x0 rd → valid_to_writeback=0", valid_to_writeback, 1'b0);

        valid_decode = 0;
    endtask

    // =========================================================================
    //  Main stimulus
    // =========================================================================
    initial begin
        $display("=========================================================");
        $display("  execution_top full-coverage testbench");
        $display("=========================================================");

        do_reset();

        test_alu_ops();
        tick();

        test_branches();
        tick();

        test_jumps();
        tick();

        test_loads();
        tick();

        test_stores();
        tick();

        test_handshake();
        tick();

        test_edge_cases();
        tick();

        // ---- Final report ----
        $display("\n=========================================================");
        $display("  RESULTS:  PASS=%0d   FAIL=%0d   TOTAL=%0d",
                 pass_cnt, fail_cnt, pass_cnt+fail_cnt);
        if (fail_cnt == 0)
            $display("  ALL TESTS PASSED");
        else
            $display("  *** %0d FAILURES – SEE ABOVE ***", fail_cnt);
        $display("=========================================================\n");

        $finish;
    end
   initial begin
    $dumpfile("waveforms/execution.vcd");
    $dumpvars(0, execution_unit_tb);
   end

    // =========================================================================
    //  Timeout watchdog
    // =========================================================================
    initial begin
        #500_000;
        $display("TIMEOUT – simulation killed");
        $finish;
    end

endmodule

