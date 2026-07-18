`timescale 1ns/1ps
// =============================================================================
//  tb_alu_m_ext.sv
//  M-extension verification through execution_top DUT ports.
//
//  Covers (RV64M):
//    64-bit : MUL  MULH  MULHU  MULHSU  DIV  DIVU  REM  REMU
//    32-bit : MULW DIVW  DIVUW  REMW    REMUW
//
//  Each operation is tested for:
//    - Normal case
//    - Corner values (0, 1, -1, INT_MIN, INT_MAX, MAXU)
//    - Divide / remainder by zero  (spec-mandated return values)
//    - MULW/DIVW/REMW sign-extension to 64 bits
// =============================================================================
module tb_for_m_extention;
    import decode_pkg::*;
    import alu_pkg::*;

    // -------------------------------------------------------------------------
    localparam int XLEN     = 64;
    localparam int CLK_HALF = 5;

    // Useful constants (avoids repetitive literals)
    localparam logic [63:0] ZERO    = 64'h0000_0000_0000_0000;
    localparam logic [63:0] ONE     = 64'h0000_0000_0000_0001;
    localparam logic [63:0] NEG1    = 64'hFFFF_FFFF_FFFF_FFFF;  // -1 signed
    localparam logic [63:0] INT_MIN = 64'h8000_0000_0000_0000;  // most-negative signed
    localparam logic [63:0] INT_MAX = 64'h7FFF_FFFF_FFFF_FFFF;  // most-positive signed
    localparam logic [63:0] MAXU    = 64'hFFFF_FFFF_FFFF_FFFF;  // unsigned max

    localparam logic [31:0] INT_MIN32 = 32'h8000_0000;
    localparam logic [31:0] INT_MAX32 = 32'h7FFF_FFFF;
    localparam logic [31:0] MAXU32    = 32'hFFFF_FFFF;

    // -------------------------------------------------------------------------
    //  DUT ports
    // -------------------------------------------------------------------------
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

    // -------------------------------------------------------------------------
    //  DUT
    // -------------------------------------------------------------------------
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

    //  Clock
    initial clk = 1'b0;
    always #CLK_HALF clk = ~clk;

    // -------------------------------------------------------------------------
    //  Scoreboard
    // -------------------------------------------------------------------------
    int pass_cnt;
    int fail_cnt;
    initial begin
        pass_cnt = 0;
        fail_cnt = 0;
    end

    // -------------------------------------------------------------------------
    //  Helpers
    // -------------------------------------------------------------------------
    task automatic chk64(
        input string       name,
        input logic [63:0] got,
        input logic [63:0] exp
    );
        if (got === exp) begin
            $display("  PASS  %-60s  got=0x%016h", name, got);
            pass_cnt++;
        end else begin
            $display("  FAIL  %-60s  got=0x%016h  exp=0x%016h", name, got, exp);
            fail_cnt++;
        end
    endtask

    // Build a minimal R-type decoded bundle for M-extension ops
    // (no immediate, no memory, rd_used=1)
    function automatic decode_pkg::decoded_instr_t m_instr(
        input logic [4:0] rdest
    );
        decode_pkg::decoded_instr_t d;
        d            = '0;
        d.instr_type = decode_pkg::R_TYPE;
        d.rs1        = 5'd1;
        d.rs2        = 5'd2;
        d.rd         = rdest;
        d.rs1_used   = 1'b1;
        d.rs2_used   = 1'b1;
        d.rd_used    = 1'b1;
        d.imm_used   = 1'b0;
        return d;
    endfunction

    // Drive inputs and wait for combinational settle
    task automatic run(
        input alu_pkg::alu_op_t op,
        input logic [63:0]      a,
        input logic [63:0]      b
    );
        decode_instruction = m_instr(5'd3);
        alu_operation      = op;
        rs1_data           = a;
        rs2_data           = b;
        valid_decode       = 1'b1;
        ready_writeback    = 1'b1;
        ready_memory       = 1'b1;
        pc_in              = 64'h1000;
        #1;
    endtask

    // Sign-extend 32-bit value to 64 bits  (Verilator-safe, no cast syntax)
    function automatic logic [63:0] sext32(input logic [31:0] v);
        sext32 = {{32{v[31]}}, v};
    endfunction

    // -------------------------------------------------------------------------
    //  Reset
    // -------------------------------------------------------------------------
    task automatic do_reset();
        rst_n              = 1'b0;
        valid_decode       = 1'b0;
        ready_memory       = 1'b1;
        ready_writeback    = 1'b1;
        rs1_data           = 64'h0;
        rs2_data           = 64'h0;
        pc_in              = 64'h0;
        alu_operation      = alu_pkg::NONE;
        decode_instruction = '0;
        @(posedge clk);
        @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
    endtask

    // =========================================================================
    //  MUL  –  lower 64 bits of signed(rs1) * signed(rs2)
    // =========================================================================
    task automatic test_MUL();
        $display("\n--- MUL ---");

        // normal
        run(ALU_MUL, 64'd6, 64'd7);
        chk64("MUL  6*7=42",              write_data, 64'd42);

        run(ALU_MUL, NEG1, 64'd3);
        chk64("MUL  -1*3=-3",             write_data, NEG1 - 64'd2);  // 0xFFFF..FD

        run(ALU_MUL, NEG1, NEG1);
        chk64("MUL  -1*-1=1",             write_data, ONE);

        // zero
        run(ALU_MUL, 64'd999, ZERO);
        chk64("MUL  n*0=0",               write_data, ZERO);

        // INT_MIN * 1
        run(ALU_MUL, INT_MIN, ONE);
        chk64("MUL  INT_MIN*1=INT_MIN",   write_data, INT_MIN);

        // INT_MIN * -1  →  lower 64 = INT_MIN  (overflow wraps)
        run(ALU_MUL, INT_MIN, NEG1);
        chk64("MUL  INT_MIN*-1 lower=INT_MIN", write_data, INT_MIN);

        // large positive
        run(ALU_MUL, 64'd1_000_000, 64'd1_000_000);
        chk64("MUL  1e6*1e6=1e12",        write_data, 64'd1_000_000_000_000);
    endtask

    // =========================================================================
    //  MULH  –  upper 64 bits of signed*signed (128-bit product)
    // =========================================================================
    task automatic test_MULH();
        $display("\n--- MULH ---");

        // small positives → upper word = 0
        run(ALU_MULH, 64'd100, 64'd200);
        chk64("MULH  100*200 upper=0",    write_data, ZERO);

        // -1 * 1 → upper = -1 (all ones, sign-fill)
        run(ALU_MULH, NEG1, ONE);
        chk64("MULH  -1*1 upper=NEG1",    write_data, NEG1);

        // -1 * -1 = +1 → 128-bit = 0x0000..0001 → upper = 0
        run(ALU_MULH, NEG1, NEG1);
        chk64("MULH  -1*-1 upper=0",      write_data, ZERO);

        // INT_MIN * INT_MIN  upper = INT_MIN/2  (0x2000..0000)
        // 0x8000..0 * 0x8000..0 = 0x4000..0 << 64  → upper=0x4000_0000_0000_0000
        run(ALU_MULH, INT_MIN, INT_MIN);
        chk64("MULH  INT_MIN*INT_MIN upper=0x4000..", write_data,
              64'h4000_0000_0000_0000);

        // INT_MAX * INT_MAX upper = 0x3FFF_FFFF_FFFF_FFFF - 1 + rounding
        // exact: (2^63-1)^2 = 2^126 - 2^64 + 1 → upper = 2^62 - 1 = 0x3FFF_FFFF_FFFF_FFFF
        run(ALU_MULH, INT_MAX, INT_MAX);
        chk64("MULH  INT_MAX*INT_MAX upper", write_data,
              64'h3FFF_FFFF_FFFF_FFFF);

        // -1 * 2 upper = -1
        run(ALU_MULH, NEG1, 64'd2);
        chk64("MULH  -1*2 upper=NEG1",    write_data, NEG1);
    endtask

    // =========================================================================
    //  MULHU  –  upper 64 bits of unsigned*unsigned
    // =========================================================================
    task automatic test_MULHU();
        $display("\n--- MULHU ---");

        // small
        run(ALU_MULHU, 64'd10, 64'd10);
        chk64("MULHU 10*10 upper=0",      write_data, ZERO);

        // MAXU * MAXU = (2^64-1)^2 → upper = 2^64-2
        run(ALU_MULHU, MAXU, MAXU);
        chk64("MULHU MAXU*MAXU upper=MAXU-1", write_data,
              64'hFFFF_FFFF_FFFF_FFFE);

        // MAXU * 1 → upper = 0
        run(ALU_MULHU, MAXU, ONE);
        chk64("MULHU MAXU*1 upper=0",     write_data, ZERO);

        // MAXU * 2 → upper = 1
        run(ALU_MULHU, MAXU, 64'd2);
        chk64("MULHU MAXU*2 upper=1",     write_data, ONE);

        // zero
        run(ALU_MULHU, MAXU, ZERO);
        chk64("MULHU MAXU*0 upper=0",     write_data, ZERO);
    endtask

    // =========================================================================
    //  MULHSU  –  upper 64 bits of signed(rs1) * unsigned(rs2)
    // =========================================================================
    task automatic test_MULHSU();
        $display("\n--- MULHSU ---");

        // positive * positive → same as MULHU for small values
        run(ALU_MULHSU, 64'd3, 64'd4);
        chk64("MULHSU 3*4 upper=0",       write_data, ZERO);

        // -1 (signed) * MAXU (unsigned)
        // = 0xFFFF..FFFF * 0xFFFF..FFFF as signed*unsigned
        // signed -1 = -(1), unsigned MAXU = 2^64-1
        // product = -(2^64-1) = -2^64+1
        // 128-bit two's complement: 0xFFFF..FFFF_0000..0001
        // upper 64 = 0xFFFF_FFFF_FFFF_FFFF
        run(ALU_MULHSU, NEG1, MAXU);
        chk64("MULHSU -1*MAXU upper=NEG1", write_data, NEG1);

        // -1 * 1 → product = -1 → upper = NEG1
        run(ALU_MULHSU, NEG1, ONE);
        chk64("MULHSU -1*1 upper=NEG1",   write_data, NEG1);

        // 1 * MAXU → product = MAXU → upper = 0
        run(ALU_MULHSU, ONE, MAXU);
        chk64("MULHSU 1*MAXU upper=0",    write_data, ZERO);

        // zero product
        run(ALU_MULHSU, ZERO, MAXU);
        chk64("MULHSU 0*MAXU upper=0",    write_data, ZERO);
    endtask

    // =========================================================================
    //  DIV  –  signed division, truncate toward zero
    // =========================================================================
    task automatic test_DIV();
        $display("\n--- DIV ---");

        run(ALU_DIV, 64'd20, 64'd3);
        chk64("DIV  20/3=6",              write_data, 64'd6);

        run(ALU_DIV, 64'd20, NEG1 - 64'd2);   // 20 / -3 = -6
        chk64("DIV  20/-3=-6",            write_data, NEG1 - 64'd5);  // 0xFFFF..FFFA

        run(ALU_DIV, NEG1 - 64'd19, 64'd4);   // -20 / 4 = -5
        chk64("DIV  -20/4=-5",            write_data, NEG1 - 64'd4);

        run(ALU_DIV, NEG1 - 64'd19, NEG1 - 64'd3); // -20 / -4 = 5
        chk64("DIV  -20/-4=5",            write_data, 64'd5);

        // divide by 1
        run(ALU_DIV, 64'd12345, ONE);
        chk64("DIV  n/1=n",               write_data, 64'd12345);

        // divide by -1 (non-overflow)
        run(ALU_DIV, 64'd100, NEG1);
        chk64("DIV  100/-1=-100",         write_data, NEG1 - 64'd99);

        // INT_MIN / -1  →  overflow: spec says result = INT_MIN
        run(ALU_DIV, INT_MIN, NEG1);
        chk64("DIV  INT_MIN/-1=INT_MIN (overflow)", write_data, INT_MIN);

        // divide by zero → all-ones (-1 signed)
        run(ALU_DIV, 64'd42, ZERO);
        chk64("DIV  n/0=MAXU",            write_data, MAXU);

        run(ALU_DIV, ZERO, ZERO);
        chk64("DIV  0/0=MAXU",            write_data, MAXU);
    endtask

    // =========================================================================
    //  DIVU  –  unsigned division
    // =========================================================================
    task automatic test_DIVU();
        $display("\n--- DIVU ---");

        run(ALU_DIVU, 64'd100, 64'd7);
        chk64("DIVU 100/7=14",            write_data, 64'd14);

        run(ALU_DIVU, MAXU, ONE);
        chk64("DIVU MAXU/1=MAXU",         write_data, MAXU);

        run(ALU_DIVU, MAXU, MAXU);
        chk64("DIVU MAXU/MAXU=1",         write_data, ONE);

        run(ALU_DIVU, ONE, MAXU);
        chk64("DIVU 1/MAXU=0",            write_data, ZERO);

        // divide by zero → all-ones
        run(ALU_DIVU, 64'd55, ZERO);
        chk64("DIVU n/0=MAXU",            write_data, MAXU);

        run(ALU_DIVU, ZERO, ZERO);
        chk64("DIVU 0/0=MAXU",            write_data, MAXU);
    endtask

    // =========================================================================
    //  REM  –  signed remainder  (sign follows dividend)
    // =========================================================================
    task automatic test_REM();
        $display("\n--- REM ---");

        run(ALU_REM, 64'd20, 64'd3);
        chk64("REM  20%3=2",              write_data, 64'd2);

        // -20 % 3 = -2  (sign of dividend)
        run(ALU_REM, NEG1 - 64'd19, 64'd3);
        chk64("REM  -20%3=-2",            write_data, NEG1 - 64'd1);  // 0xFFFF..FFFE

        // 20 % -3 = 2  (sign of dividend, positive)
        run(ALU_REM, 64'd20, NEG1 - 64'd2);
        chk64("REM  20%-3=2",             write_data, 64'd2);

        // -20 % -3 = -2
        run(ALU_REM, NEG1 - 64'd19, NEG1 - 64'd2);
        chk64("REM  -20%-3=-2",           write_data, NEG1 - 64'd1);

        // zero remainder
        run(ALU_REM, 64'd21, 64'd3);
        chk64("REM  21%3=0",              write_data, ZERO);

        // n % 1 = 0
        run(ALU_REM, 64'd9999, ONE);
        chk64("REM  n%1=0",               write_data, ZERO);

        // INT_MIN % -1 → 0  (overflow case, spec mandates 0)
        run(ALU_REM, INT_MIN, NEG1);
        chk64("REM  INT_MIN%-1=0",        write_data, ZERO);

        // divide by zero → dividend
        run(ALU_REM, 64'd42, ZERO);
        chk64("REM  n%0=n",               write_data, 64'd42);

        run(ALU_REM, NEG1, ZERO);
        chk64("REM  -1%0=-1",             write_data, NEG1);
    endtask

    // =========================================================================
    //  REMU  –  unsigned remainder
    // =========================================================================
    task automatic test_REMU();
        $display("\n--- REMU ---");

        run(ALU_REMU, 64'd100, 64'd7);
        chk64("REMU 100%7=2",             write_data, 64'd2);

        run(ALU_REMU, MAXU, 64'd3);
        chk64("REMU MAXU%3=0",            write_data, ZERO);   // MAXU = 3*k, remainder 0

        // Note: MAXU = 0xFFFF_FFFF_FFFF_FFFF = 3 * 0x5555_5555_5555_5555, so rem=0
        run(ALU_REMU, MAXU, ONE);
        chk64("REMU MAXU%1=0",            write_data, ZERO);

        run(ALU_REMU, ONE, MAXU);
        chk64("REMU 1%MAXU=1",            write_data, ONE);

        // divide by zero → dividend
        run(ALU_REMU, 64'd77, ZERO);
        chk64("REMU n%0=n",               write_data, 64'd77);

        run(ALU_REMU, MAXU, ZERO);
        chk64("REMU MAXU%0=MAXU",         write_data, MAXU);
    endtask

    // =========================================================================
    //  MULW  –  lower 32 of rs1*rs2, sign-extended to 64
    // =========================================================================
    task automatic test_MULW();
        logic [63:0] exp;
        $display("\n--- MULW ---");

        // 100 * 200 = 20000
        exp = sext32(32'd20000);
        run(ALU_MULW, 64'd100, 64'd200);
        chk64("MULW 100*200=20000 sext", write_data, exp);

        // overflow: 0x7FFF_FFFF * 2 lower 32 wraps
        exp = sext32(32'hFFFF_FFFE);
        run(ALU_MULW, {32'h0, INT_MAX32}, 64'd2);
        chk64("MULW INT_MAX32*2 wrap sext", write_data, exp);

        // -1 * -1 lower32 = 1  sign-ext = 0x0000..0001
        exp = sext32(32'h0000_0001);
        run(ALU_MULW, NEG1, NEG1);
        chk64("MULW -1*-1 lower=1 sext", write_data, exp);

        // INT_MIN32 * 1
        exp = sext32(INT_MIN32);
        run(ALU_MULW, sext32(INT_MIN32), ONE);
        chk64("MULW INT_MIN32*1 sext", write_data, exp);

        // zero
        exp = sext32(32'h0);
        run(ALU_MULW, 64'd999, ZERO);
        chk64("MULW n*0=0 sext",          write_data, exp);

        // upper 32 of rs1 should be ignored
        // 0xDEAD_BEEF_0000_0005 * 3 → lower32 = 5*3=15
        exp = sext32(32'd15);
        run(ALU_MULW, 64'hDEAD_BEEF_0000_0005, 64'd3);
        chk64("MULW upper32 ignored, 5*3=15", write_data, exp);
    endtask

    // =========================================================================
    //  DIVW  –  signed 32-bit divide, sign-extended result
    // =========================================================================
    task automatic test_DIVW();
        logic [63:0] exp;
        $display("\n--- DIVW ---");

        exp = sext32(32'd6);
        run(ALU_DIVW, 64'd20, 64'd3);
        chk64("DIVW 20/3=6 sext",         write_data, exp);

        // negative result
        exp = sext32(32'hFFFF_FFFC);  // -4
        run(ALU_DIVW, 64'd20, NEG1 - 64'd4);  // 20 / -5 = -4
        chk64("DIVW 20/-5=-4 sext",       write_data, exp);

        // INT_MIN32 / -1 → overflow → INT_MIN32 sign-extended
        exp = sext32(INT_MIN32);
        run(ALU_DIVW, sext32(INT_MIN32), NEG1);
        chk64("DIVW INT_MIN32/-1 overflow sext", write_data, exp);

        // n / 1
        exp = sext32(32'd12345);
        run(ALU_DIVW, 64'd12345, ONE);
        chk64("DIVW n/1=n sext",          write_data, exp);

        // divide by zero → sign-extended all-ones (MAXU32 sign-ext = NEG1)
        run(ALU_DIVW, 64'd7, ZERO);
        chk64("DIVW n/0=NEG1 sext",       write_data, NEG1);

        // upper 32 of inputs ignored: 0xDEAD_BEEF_0000_0064 / 7 = 100/7=14
        exp = sext32(32'd14);
        run(ALU_DIVW, 64'hDEAD_BEEF_0000_0064, 64'd7);
        chk64("DIVW upper32 ignored, 100/7=14", write_data, exp);
    endtask

    // =========================================================================
    //  DIVUW  –  unsigned 32-bit divide, sign-extended result
    // =========================================================================
    task automatic test_DIVUW();
        logic [63:0] exp;
        $display("\n--- DIVUW ---");

        exp = sext32(32'd14);
        run(ALU_DIVUW, 64'd100, 64'd7);
        chk64("DIVUW 100/7=14 sext",      write_data, exp);

        exp = sext32(32'd1);
        run(ALU_DIVUW, {32'h0, MAXU32}, {32'h0, MAXU32});
        chk64("DIVUW MAXU32/MAXU32=1 sext", write_data, exp);

        // MAXU32 / 1
        exp = sext32(MAXU32);
        run(ALU_DIVUW, {32'h0, MAXU32}, ONE);
        chk64("DIVUW MAXU32/1=MAXU32 sext", write_data, exp);

        // divide by zero → MAXU32 sign-extended = NEG1
        run(ALU_DIVUW, 64'd55, ZERO);
        chk64("DIVUW n/0=NEG1 sext",      write_data, NEG1);

        // upper 32 of rs2 should not affect result
        exp = sext32(32'd50);
        run(ALU_DIVUW, 64'hDEAD_BEEF_0000_0064,  // lower32=100
                       64'hCAFE_BABE_0000_0002);  // lower32=2
        chk64("DIVUW upper32 ignored 100/2=50", write_data, exp);
    endtask

    // =========================================================================
    //  REMW  –  signed 32-bit remainder, sign-extended result
    // =========================================================================
    task automatic test_REMW();
        logic [63:0] exp;
        $display("\n--- REMW ---");

        exp = sext32(32'd2);
        run(ALU_REMW, 64'd20, 64'd3);
        chk64("REMW 20%3=2 sext",         write_data, exp);

        // -20 % 3 = -2  (sign follows dividend)
        exp = sext32(32'hFFFF_FFFE);  // -2
        run(ALU_REMW, NEG1 - 64'd19, 64'd3);
        chk64("REMW -20%3=-2 sext",       write_data, exp);

        // INT_MIN32 % -1 = 0
        exp = sext32(32'd0);
        run(ALU_REMW, sext32(INT_MIN32), NEG1);
        chk64("REMW INT_MIN32%-1=0 sext", write_data, exp);

        // n % 1 = 0
        exp = sext32(32'd0);
        run(ALU_REMW, 64'd12345, ONE);
        chk64("REMW n%1=0 sext",          write_data, exp);

        // divide by zero → dividend sign-extended
        // dividend lower32 = 0x8000_0001 → sext = 0xFFFF_FFFF_8000_0001
        exp = sext32(32'h8000_0001);
        run(ALU_REMW, 64'h0000_0000_8000_0001, ZERO);
        chk64("REMW n%0=n sext",          write_data, exp);

        // upper 32 of rs1 ignored
        exp = sext32(32'd1);
        run(ALU_REMW, 64'hDEAD_BEEF_0000_0007,  // lower32=7
                      64'd3);                     // 7%3=1
        chk64("REMW upper32 ignored 7%3=1", write_data, exp);
    endtask

    // =========================================================================
    //  REMUW  –  unsigned 32-bit remainder, sign-extended result
    // =========================================================================
    task automatic test_REMUW();
        logic [63:0] exp;
        $display("\n--- REMUW ---");

        exp = sext32(32'd2);
        run(ALU_REMUW, 64'd20, 64'd3);
        chk64("REMUW 20%3=2 sext",        write_data, exp);

        exp = sext32(32'd0);
        run(ALU_REMUW, {32'h0, MAXU32}, ONE);
        chk64("REMUW MAXU32%1=0 sext",    write_data, exp);

        exp = sext32(32'd1);
        run(ALU_REMUW, ONE, {32'h0, MAXU32});
        chk64("REMUW 1%MAXU32=1 sext",    write_data, exp);

        // divide by zero → dividend lower32 sign-extended
        exp = sext32(32'd77);
        run(ALU_REMUW, 64'd77, ZERO);
        chk64("REMUW n%0=n sext",         write_data, exp);

        // MAXU32 % 0 → MAXU32 sign-extended = NEG1
        exp = sext32(MAXU32);
        run(ALU_REMUW, {32'h0, MAXU32}, ZERO);
        chk64("REMUW MAXU32%0=MAXU32 sext", write_data, exp);

        // upper 32 of rs1 ignored
        exp = sext32(32'd1);
        run(ALU_REMUW, 64'hDEAD_BEEF_0000_0007, 64'd3);
        chk64("REMUW upper32 ignored 7%3=1", write_data, exp);
    endtask

    // =========================================================================
    //  Main
    // =========================================================================
    initial begin
        $display("=============================================================");
        $display("  M-Extension verification  (through execution_top)");
        $display("=============================================================");

        do_reset();

        test_MUL();
        test_MULH();
        test_MULHU();
        test_MULHSU();

        test_DIV();
        test_DIVU();
        test_REM();
        test_REMU();
        test_MULW();
        test_DIVW();
        test_DIVUW();
        test_REMW();
        test_REMUW();

        valid_decode = 1'b0;
        @(posedge clk);

        $display("\n=============================================================");
        $display("  RESULTS : PASS=%0d  FAIL=%0d  TOTAL=%0d",
                 pass_cnt, fail_cnt, pass_cnt + fail_cnt);
        if (fail_cnt == 0)
            $display("  ALL M-EXTENSION TESTS PASSED");
        else
            $display("  *** %0d FAILURE(S) – SEE ABOVE ***", fail_cnt);
        $display("=============================================================\n");

        $finish;
    end

   initial begin 
       $dumpfile("waveforms/m.vcd");
       $dumpvars(0, tb_for_m_extention);
   end


    //watch dog

    initial begin
        #1_000_000;
        $display("TIMEOUT");
        $finish;
    end

endmodule

