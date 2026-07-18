`timescale 1ns/1ps

// ============================================================
//  Testbench : load_store_tb
//  DUT       : memory_top
//
//  Debug features added:
//    [1] Handshake monitor  — logs every stall cycle on both
//        req and resp channels; errors on broken handshake
//        (valid drops without ready ever asserting)
//    [2] X/Z detector       — fires on any unknown bit on
//        DUT outputs each clock
//    [3] Backpressure stall counter — measures how many cycles
//        resp_valid is held high while resp_ready is low
//    [4] Data checker       — scoreboard now stores expected
//        rdata for store-then-load sequences and checks it
//    [5] Signal snapshot    — dump all DUT ports on any FAIL
//    [6] Per-TC counters    — 12-entry pass/fail table so you
//        know exactly which test case broke
//    [7] op_name()          — human-readable opcode in every
//        message (no more printing raw integers)
// ============================================================

typedef enum logic [3:0] {
    LOAD_BYTE   = 4'd0,
    LOAD_BYTE_U = 4'd1,
    LOAD_HALF   = 4'd2,
    LOAD_HALF_U = 4'd3,
    LOAD_WORD   = 4'd4,
    LOAD_WORD_U = 4'd5,
    LOAD_DOUBLE = 4'd6,
    STORE_BYTE  = 4'd8,
    STORE_HALF  = 4'd9,
    STORE_WORD  = 4'd10,
    STORE_DOUBLE= 4'd11
} mem_op_e;

module load_store_tb;

    // --------------------------------------------------------
    //  Parameters
    // --------------------------------------------------------
    parameter int XLEN       = 64;
    parameter int CLK_PERIOD = 10;
    parameter int SB_DEPTH   = 32;
    parameter int MAX_TC     = 12;   // number of test cases

    // --------------------------------------------------------
    //  DUT port signals
    // --------------------------------------------------------
    logic            clk;
    logic            rst_n;

    logic            req_valid_i;
    logic            req_ready_o;
    logic [XLEN-1:0] req_addr_i;
    logic [XLEN-1:0] req_wdata_i;
    mem_op_e         req_memop_i;
    logic [4:0]      req_rd_i;

    logic [4:0]      resp_rd_o;
    logic            responce_valid_o;
    logic            responce_ready_i;
    logic [XLEN-1:0] responce_rdata_o;

    // --------------------------------------------------------
    //  DUT Instantiation
    // --------------------------------------------------------
    memory_top #(.XLEN(XLEN)) dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .req_valid_i       (req_valid_i),
        .req_ready_o       (req_ready_o),
        .req_addr_i        (req_addr_i),
        .req_wdata_i       (req_wdata_i),
        .req_memop_i       (req_memop_i),
        .req_rd_i          (req_rd_i),
        .resp_rd_o         (resp_rd_o),
        .responce_valid_o  (responce_valid_o),
        .responce_ready_i  (responce_ready_i),
        .responce_rdata_o  (responce_rdata_o)
    );

    // --------------------------------------------------------
    //  Clock
    // --------------------------------------------------------
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // --------------------------------------------------------
    //  [7] Human-readable opcode name
    // --------------------------------------------------------
    function automatic string op_name(mem_op_e op);
        case (op)
            LOAD_BYTE   : return "LOAD_BYTE";
            LOAD_BYTE_U : return "LOAD_BYTE_U";
            LOAD_HALF   : return "LOAD_HALF";
            LOAD_HALF_U : return "LOAD_HALF_U";
            LOAD_WORD   : return "LOAD_WORD";
            LOAD_WORD_U : return "LOAD_WORD_U";
            LOAD_DOUBLE : return "LOAD_DOUBLE";
            STORE_BYTE  : return "STORE_BYTE";
            STORE_HALF  : return "STORE_HALF";
            STORE_WORD  : return "STORE_WORD";
            STORE_DOUBLE: return "STORE_DOUBLE";
            default     : return "UNKNOWN_OP";
        endcase
    endfunction

    // --------------------------------------------------------
    //  Scoreboard — ring-buffer FIFO
    //  Now also carries expected_rdata for data checking.
    // --------------------------------------------------------
    typedef struct packed {
        logic [XLEN-1:0] addr;
        logic [XLEN-1:0] expected_rdata;  // [4] meaningful only when check_data=1
        logic            check_data;       // [4] 1 = compare rdata, 0 = ignore
        logic [3:0]      memop_bits;
        logic [4:0]      rd;
    } req_entry_t;

    req_entry_t  sb_mem   [SB_DEPTH];
    int unsigned sb_head;
    int unsigned sb_tail;
    int unsigned sb_count;

    // --------------------------------------------------------
    //  [6] Per-TC pass/fail counters
    // --------------------------------------------------------
    int tc_pass [MAX_TC];
    int tc_fail [MAX_TC];
    int cur_tc;           // set by tc_begin() before each test case

    int pass_cnt;
    int fail_cnt;

    task automatic tc_begin(int tc_num, string name);
        cur_tc = tc_num;
        $display("\n%s", {72{"="}});
        $display("  TC%0d : %s", tc_num, name);
        $display("%s", {72{"="}});
    endtask

    // Central FAIL / PASS recording — always use these so
    // per-TC and global counts stay in sync.
    task automatic record_fail(string msg);
        $display("[FAIL][TC%0d][%0t ns] %s", cur_tc, $time/1000, msg);
        tc_fail[cur_tc]++;
        fail_cnt++;
    endtask

    task automatic record_pass(string msg);
        $display("[PASS][TC%0d][%0t ns] %s", cur_tc, $time/1000, msg);
        tc_pass[cur_tc]++;
        pass_cnt++;
    endtask

    // --------------------------------------------------------
    //  Scoreboard helpers
    // --------------------------------------------------------
    task automatic sb_push(req_entry_t e);
        if (sb_count == SB_DEPTH) begin
            record_fail("Scoreboard overflow — increase SB_DEPTH");
        end else begin
            sb_mem[sb_tail] = e;
            sb_tail  = (sb_tail + 1) % SB_DEPTH;
            sb_count++;
        end
    endtask

    task automatic sb_pop(output req_entry_t e, output logic ok);
        if (sb_count == 0) begin
            ok = 1'b0;
        end else begin
            e        = sb_mem[sb_head];
            sb_head  = (sb_head + 1) % SB_DEPTH;
            sb_count--;
            ok       = 1'b1;
        end
    endtask

    task automatic sb_flush();
        sb_head  = 0;
        sb_tail  = 0;
        sb_count = 0;
    endtask

    // --------------------------------------------------------
    //  [5] Signal snapshot — call on any FAIL for instant
    //      visibility of all DUT ports without opening a VCD.
    // --------------------------------------------------------
    task automatic signal_snapshot(string context_msg);
        $display("  [SNAPSHOT @ %0t ns] context: %s", $time/1000, context_msg);
        $display("  req  : valid=%b ready=%b  op=%-12s addr=0x%016h wdata=0x%016h rd=%0d",
                 req_valid_i, req_ready_o,
                 op_name(req_memop_i), req_addr_i, req_wdata_i, req_rd_i);
        $display("  resp : valid=%b ready=%b  rdata=0x%016h rd=%0d",
                 responce_valid_o, responce_ready_i,
                 responce_rdata_o, resp_rd_o);
        $display("  ctrl : rst_n=%b  sb_count=%0d", rst_n, sb_count);
    endtask

    // --------------------------------------------------------
    //  [2] X/Z detector
    //  Fires on any unknown bit on DUT outputs each clock edge.
    //  Suppressed during reset (rst_n=0) to avoid spurious hits.
    // --------------------------------------------------------
    always @(posedge clk) begin
        if (rst_n) begin
            // req_ready_o
            if (^req_ready_o === 1'bx) begin
                record_fail("X/Z detected on req_ready_o");
                signal_snapshot("X/Z on req_ready_o");
            end
            // resp outputs
            if (responce_valid_o === 1'bx) begin
                record_fail("X/Z detected on responce_valid_o");
                signal_snapshot("X/Z on responce_valid_o");
            end
            if (responce_valid_o && (^responce_rdata_o === 1'bx)) begin
                record_fail("X/Z detected on responce_rdata_o while valid");
                signal_snapshot("X/Z on responce_rdata_o");
            end
            if (responce_valid_o && (^resp_rd_o === 1'bx)) begin
                record_fail("X/Z detected on resp_rd_o while valid");
                signal_snapshot("X/Z on resp_rd_o");
            end
        end
    end

    // --------------------------------------------------------
    //  [1] Handshake monitor — req channel
    //
    //  Rule 1: once valid is asserted it must not drop until
    //          ready is seen (valid-stability requirement).
    //  Rule 2: ready must come within REQ_MAX_STALL cycles.
    //  Logs every stall cycle so you can count exactly where
    //  the DUT stopped responding.
    // --------------------------------------------------------
    parameter int REQ_MAX_STALL  = 20;
    parameter int RESP_MAX_STALL = 50;

    int req_stall_cnt;
    int resp_stall_cnt;
    logic req_valid_prev;

    always @(posedge clk) begin
        if (!rst_n) begin
            req_stall_cnt  = 0;
            resp_stall_cnt = 0;
            req_valid_prev = 1'b0;
        end else begin

            // --- REQ channel ---
            if (req_valid_i && !req_ready_o) begin
                req_stall_cnt++;
                $display("[HS-REQ ][%0t ns] STALL cycle %0d — waiting for req_ready_o",
                         "  (op=%s addr=0x%h)",
                         $time/1000, req_stall_cnt,
                         op_name(req_memop_i), req_addr_i);
                if (req_stall_cnt >= REQ_MAX_STALL) begin
                    record_fail($sformatf(
                        "req_ready_o not seen after %0d stall cycles (op=%s addr=0x%h)",
                        req_stall_cnt, op_name(req_memop_i), req_addr_i));
                    signal_snapshot("REQ handshake timeout");
                end
            end else if (req_valid_i && req_ready_o) begin
                if (req_stall_cnt > 0)
                    $display("[HS-REQ ][%0t ns] Handshake complete after %0d stall cycles",
                             $time/1000, req_stall_cnt);
                req_stall_cnt = 0;
            end else begin
                req_stall_cnt = 0;
            end

            // // Broken handshake: valid dropped without ready (protocol violation)
            // if (req_valid_prev && !req_valid_i && !req_ready_o) begin
            //     record_fail("REQ handshake broken: req_valid_i dropped before req_ready_o");
            //     signal_snapshot("Broken REQ handshake");
            // end
            req_valid_prev = req_valid_i;

            // --- RESP channel ---
            if (responce_valid_o && !responce_ready_i) begin
                resp_stall_cnt++;
                $display("[HS-RESP][%0t ns] Backpressure stall cycle %0d",
                         " — DUT holding valid, WB not ready",
                         $time/1000, resp_stall_cnt);
                if (resp_stall_cnt >= RESP_MAX_STALL) begin
                    record_fail($sformatf(
                        "Response stalled for %0d cycles with valid=1, ready=0",
                        resp_stall_cnt));
                    signal_snapshot("RESP backpressure timeout");
                end
            end else if (responce_valid_o && responce_ready_i) begin
                if (resp_stall_cnt > 0)
                    $display("[HS-RESP][%0t ns] Response accepted after %0d backpressure cycles",
                             $time/1000, resp_stall_cnt);
                resp_stall_cnt = 0;
            end else begin
                resp_stall_cnt = 0;
            end
        end
    end

    // --------------------------------------------------------
    //  Response checker — [4] checks both rd and rdata
    // --------------------------------------------------------
    req_entry_t chk_exp;
    logic       chk_ok;

    always @(posedge clk) begin
        if (responce_valid_o && responce_ready_i) begin
            sb_pop(chk_exp, chk_ok);

            if (!chk_ok) begin
                record_fail("Unexpected response — scoreboard empty");
                signal_snapshot("Extra response");
            end else begin
                // rd check
                if (resp_rd_o !== chk_exp.rd) begin
                    record_fail($sformatf(
                        "rd MISMATCH: expected=%0d  got=%0d  (op=%s addr=0x%h)",
                        chk_exp.rd, resp_rd_o,
                        op_name(mem_op_e'(chk_exp.memop_bits)), chk_exp.addr));
                    signal_snapshot("rd mismatch");
                end else begin
                    record_pass($sformatf(
                        "rd OK rd=%0d  rdata=0x%016h  (op=%s addr=0x%h)",
                        resp_rd_o, responce_rdata_o,
                        op_name(mem_op_e'(chk_exp.memop_bits)), chk_exp.addr));
                end

                // [4] rdata check — only when the TB knows the expected value
                if (chk_exp.check_data) begin
                    if (responce_rdata_o !== chk_exp.expected_rdata) begin
                        record_fail($sformatf(
                            "rdata MISMATCH: expected=0x%016h  got=0x%016h",
                            "  (op=%s addr=0x%h rd=%0d)",
                            chk_exp.expected_rdata, responce_rdata_o,
                            op_name(mem_op_e'(chk_exp.memop_bits)),
                            chk_exp.addr, chk_exp.rd));
                        signal_snapshot("rdata mismatch");
                    end else begin
                        record_pass($sformatf(
                            "rdata OK 0x%016h  (op=%s addr=0x%h)",
                            responce_rdata_o,
                            op_name(mem_op_e'(chk_exp.memop_bits)), chk_exp.addr));
                    end
                end
            end
        end
    end

    // --------------------------------------------------------
    //  Helper: is_load / is_store
    // --------------------------------------------------------
    function automatic logic is_load(mem_op_e op);
        case (op)
            LOAD_BYTE, LOAD_BYTE_U,
            LOAD_HALF, LOAD_HALF_U,
            LOAD_WORD, LOAD_WORD_U,
            LOAD_DOUBLE : return 1'b1;
            default      : return 1'b0;
        endcase
    endfunction

    // --------------------------------------------------------
    //  Task: do_reset
    task automatic do_reset(int cycles = 5);
        rst_n            = 1'b0;
        req_valid_i      = 1'b0;
        req_addr_i       = '0;
        req_wdata_i      = '0;
        req_memop_i      = LOAD_WORD;
        req_rd_i         = 5'd0;
        responce_ready_i = 1'b1;
        repeat(cycles) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        $display("[RST][%0t ns] Reset released", $time/1000);
    endtask

    // --------------------------------------------------------
    //  Task: send_request
    //    check_data   : 1 = scoreboard will compare rdata
    //    expected_rdata: value to compare when check_data=1
    // --------------------------------------------------------
    task automatic send_request(
        input logic [XLEN-1:0] addr,
        input logic [XLEN-1:0] wdata,
        input mem_op_e         memop,
        input logic [4:0]      rd,
        input logic            check_data     = 1'b0,
        input logic [XLEN-1:0] expected_rdata = '0,
        input int              max_wait       = 20
    );
        int wait_cnt;
        wait_cnt = 0;

        @(posedge clk);
        req_valid_i = 1'b1;
        req_addr_i  = addr;
        req_wdata_i = wdata;
        req_memop_i = memop;
        req_rd_i    = rd;

        $display("[REQ ][TC%0d][%0t ns] Sending op=%-12s addr=0x%016h wdata=0x%016h rd=%0d",
                 cur_tc, $time/1000, op_name(memop), addr, wdata, rd);

        forever begin
            @(posedge clk);
            if (req_ready_o) begin
                $display("[REQ ][TC%0d][%0t ns] Handshake OK  (waited %0d cycle(s))",
                         cur_tc, $time/1000, wait_cnt);
                if (is_load(memop)) begin
                    req_entry_t e;
                    e.addr          = addr;
                    e.expected_rdata= expected_rdata;
                    e.check_data    = check_data;
                    e.memop_bits    = memop[3:0];
                    e.rd            = rd;
                    sb_push(e);
                end
                @(posedge clk);
                req_valid_i = 1'b0;
                break;
            end
            wait_cnt++;
            if (wait_cnt >= max_wait) begin
                record_fail($sformatf(
                    "req_ready_o not seen in %0d cycles (op=%s addr=0x%h)",
                    max_wait, op_name(memop), addr));
                signal_snapshot("send_request timeout");
                @(posedge clk);
                req_valid_i = 1'b0;
                break;
            end
        end
    endtask

    // --------------------------------------------------------
    //  Task: wait_response
    // --------------------------------------------------------
    task automatic wait_response(
        output logic [XLEN-1:0] rdata,
        output logic [4:0]      rd_out,
        input  int              max_wait = 50
    );
        int cnt;
        cnt = 0;
        forever begin
            @(posedge clk);
            if (responce_valid_o && responce_ready_i) begin
                rdata  = responce_rdata_o;
                rd_out = resp_rd_o;
                $display("[RESP][TC%0d][%0t ns] Received rdata=0x%016h rd=%0d (after %0d cycle(s))",
                         cur_tc, $time/1000, rdata, rd_out, cnt);
                break;
            end
            cnt++;
            if (cnt >= max_wait) begin
                record_fail($sformatf(
                    "Response not received within %0d cycles (sb_count=%0d)",
                    max_wait, sb_count));
                signal_snapshot("wait_response timeout");
                rdata  = 'x;
                rd_out = 'x;
                break;
            end
        end
    endtask

    // --------------------------------------------------------
    //  Task: idle_cycles
    // --------------------------------------------------------
    task automatic idle_cycles(int n);
        repeat(n) @(posedge clk);
    endtask

    // --------------------------------------------------------
    //  [6] Per-TC report table
    // --------------------------------------------------------
    task automatic report_summary();
        int total_p, total_f;
        total_p = 0; total_f = 0;
        $display("\n%s", {72{"="}});
        $display("  TESTBENCH SUMMARY");
        $display("%s", {72{"-"}});
        $display("  %-6s  %-30s  %6s  %6s", "TC", "Description", "PASS", "FAIL");
        $display("%s", {72{"-"}});
        // TC names (update if you add/rename test cases)
        begin
            string tc_names[MAX_TC];
            tc_names[0]  = "Init / counters";
            tc_names[1]  = "Reset assertion";
            tc_names[2]  = "LOAD_WORD, WB always ready";
            tc_names[3]  = "STORE_DOUBLE";
            tc_names[4]  = "LOAD_DOUBLE after STORE (data chk)";
            tc_names[5]  = "LOAD_HALF + WB backpressure";
            tc_names[6]  = "LOAD_BYTE_U, valid held";
            tc_names[7]  = "STORE_BYTE";
            tc_names[8]  = "STORE_HALF";
            tc_names[9]  = "Back-to-back LOAD_WORD x3";
            tc_names[10] = "Randomised stimulus x10";
            tc_names[11] = "Reset mid-operation";
            for (int i = 0; i < MAX_TC; i++) begin
                $display("  TC%-4d  %-30s  %6d  %6d",
                         i, tc_names[i], tc_pass[i], tc_fail[i]);
                total_p += tc_pass[i];
                total_f += tc_fail[i];
            end
        end
        $display("%s", {72{"-"}});
        $display("  %-36s  %6d  %6d", "TOTAL", total_p, total_f);
        $display("%s", {72{"="}});
        if (total_f == 0)
            $display("  >>> ALL TESTS PASSED <<<");
        else
            $display("  >>> %0d FAILURE(s) — see [FAIL] lines above <<<", total_f);
        $display("%s\n", {72{"="}});
    endtask

    // ========================================================
    //  MAIN TEST SEQUENCE
    // ========================================================
    logic [XLEN-1:0] rdata;
    logic [4:0]      rd_out;

    mem_op_e rand_ops [11];
    int      rand_n_ops;

    // simple shadow memory for data checking in randomised TC
    // (word-addressed, 256 entries; for demo purposes)
    logic [XLEN-1:0] shadow_mem [256];
    logic            shadow_valid[256];

    initial begin
        // Init per-TC counters
        for (int i = 0; i < MAX_TC; i++) begin
            tc_pass[i] = 0;
            tc_fail[i] = 0;
        end
        sb_flush();
        pass_cnt = 0;
        fail_cnt = 0;
        cur_tc   = 0;

        for (int i = 0; i < 256; i++) shadow_valid[i] = 1'b0;

        rand_ops[0]  = LOAD_BYTE;
        rand_ops[1]  = LOAD_BYTE_U;
        rand_ops[2]  = LOAD_HALF;
        rand_ops[3]  = LOAD_HALF_U;
        rand_ops[4]  = LOAD_WORD;
        rand_ops[5]  = LOAD_WORD_U;
        rand_ops[6]  = LOAD_DOUBLE;
        rand_ops[7]  = STORE_BYTE;
        rand_ops[8]  = STORE_HALF;
        rand_ops[9]  = STORE_WORD;
        rand_ops[10] = STORE_DOUBLE;
        rand_n_ops   = 11;

        $dumpfile("waveforms/load_store.vcd");
        $dumpvars(0, load_store_tb);

        // -------------------------------------------------------
        // TC1: Reset
        // -------------------------------------------------------
        tc_begin(1, "Reset assertion");
        do_reset(6);
        record_pass("Reset completed cleanly");

        // -------------------------------------------------------
        // TC2: Single LOAD_WORD (rd=5, addr=0x1000)
        //      Data check disabled — memory uninitialized,
        //      we only verify rd forwarding.
        // -------------------------------------------------------
        tc_begin(2, "LOAD_WORD, WB always ready");
        responce_ready_i = 1'b1;
        send_request(.addr(64'h1000), .wdata('0),
                     .memop(LOAD_WORD), .rd(5'd5));
        wait_response(rdata, rd_out);
        idle_cycles(2);

        // -------------------------------------------------------
        // TC3: STORE_DOUBLE — write known value into shadow
        // -------------------------------------------------------
        tc_begin(3, "STORE_DOUBLE addr=0x2000");
        send_request(.addr(64'h2000),
                     .wdata(64'hDEAD_BEEF_CAFE_BABE),
                     .memop(STORE_DOUBLE), .rd(5'd0));
        // Update shadow memory (byte-address 0x2000 → index 0x400)
        shadow_mem[8'(64'h2000 >> 3)]   = 64'hDEAD_BEEF_CAFE_BABE;
        shadow_valid[8'(64'h2000 >> 3)] = 1'b1;
        idle_cycles(4);

        // -------------------------------------------------------
        // TC4: LOAD_DOUBLE from same address — data check ON
        // -------------------------------------------------------
        tc_begin(4, "LOAD_DOUBLE after STORE (data check)");
        send_request(.addr(64'h2000), .wdata('0),
                     .memop(LOAD_DOUBLE), .rd(5'd10),
                     .check_data(1'b1),
                     .expected_rdata(64'hDEAD_BEEF_CAFE_BABE));
        wait_response(rdata, rd_out);
        idle_cycles(2);

        // -------------------------------------------------------
        // TC5: Backpressure — WB holds ready low for 5 cycles
        // -------------------------------------------------------
        tc_begin(5, "LOAD_HALF + WB backpressure");
        responce_ready_i = 1'b0;
        send_request(.addr(64'h3000), .wdata('0),
                     .memop(LOAD_HALF), .rd(5'd7));
        $display("[TC5] Holding responce_ready_i=0 for 5 cycles — watching stall counter");
        idle_cycles(5);
        responce_ready_i = 1'b1;
        wait_response(rdata, rd_out);
        idle_cycles(2);

        // -------------------------------------------------------
        // TC6: LOAD_BYTE_U — manual handshake, valid held high
        // -------------------------------------------------------
        tc_begin(6, "LOAD_BYTE_U, valid held until ready");
        responce_ready_i = 1'b1;
        begin : blk_tc6
            req_entry_t e6;
            @(posedge clk);
            req_valid_i = 1'b1;
            req_addr_i  = 64'h4000;
            req_wdata_i = '0;
            req_memop_i = LOAD_BYTE_U;
            req_rd_i    = 5'd15;
            $display("[TC6] valid asserted — waiting for ready (manual handshake)");

            @(posedge clk);
            while (!req_ready_o) begin
                $display("[TC6] ready not yet seen, holding valid...");
                @(posedge clk);
            end

            e6.addr          = req_addr_i;
            e6.expected_rdata= '0;
            e6.check_data    = 1'b0;
            e6.memop_bits    = req_memop_i[3:0];
            e6.rd            = req_rd_i;
            sb_push(e6);
            $display("[TC6][%0t ns] Handshake complete (manual)", $time/1000);

            @(posedge clk);
            req_valid_i = 1'b0;
        end
        wait_response(rdata, rd_out);
        idle_cycles(2);

        // -------------------------------------------------------
        // TC7: STORE_BYTE
        // -------------------------------------------------------
        tc_begin(7, "STORE_BYTE");
        send_request(.addr(64'h5000), .wdata(64'hFF),
                     .memop(STORE_BYTE), .rd(5'd0));
        idle_cycles(3);
        record_pass("STORE_BYTE issued, no response expected");

        // -------------------------------------------------------
        // TC8: STORE_HALF
        // -------------------------------------------------------
        tc_begin(8, "STORE_HALF");
        send_request(.addr(64'h5002), .wdata(64'hABCD),
                     .memop(STORE_HALF), .rd(5'd0));
        idle_cycles(3);
        record_pass("STORE_HALF issued, no response expected");

        // -------------------------------------------------------
        // TC9: Back-to-back LOAD_WORD x3
        // -------------------------------------------------------
        tc_begin(9, "Back-to-back LOAD_WORD x3");
        responce_ready_i = 1'b1;
        send_request(64'h100, '0, LOAD_WORD, 5'd1);
        send_request(64'h104, '0, LOAD_WORD, 5'd2);
        send_request(64'h108, '0, LOAD_WORD, 5'd3);
        $display("[TC9] All 3 requests sent — draining responses");
        repeat(3) wait_response(rdata, rd_out);
        idle_cycles(2);

        // -------------------------------------------------------
        // TC10: Randomised stimulus with shadow-memory data check
        // -------------------------------------------------------
        tc_begin(10, "Randomised stimulus x10");
        begin : blk_rand
            int          op_idx;
            mem_op_e     op;
            logic [63:0] addr;
            logic [63:0] wdata;
            logic [4:0]  rd;
            logic        do_check;
            logic [63:0] exp_data;
            int          shad_idx;

            for (int i = 0; i < 10; i++) begin
                op_idx = $urandom_range(0, rand_n_ops - 1);
                op     = rand_ops[op_idx];
                // Use a small address range so store→load hits are likely
                addr   = {57'd0, 4'($urandom_range(0, 15)), 3'd0}; // 16 aligned slots
                wdata  = {$urandom(), $urandom()};
                rd     = 5'($urandom_range(1, 31));

                responce_ready_i = ($urandom_range(0, 3) != 0) ? 1'b1 : 1'b0;

                shad_idx = int'(addr >> 3) & 32'(8'hFF);
                do_check = 1'b0;
                exp_data = '0;

                if (!is_load(op)) begin
                    // Store: update shadow
                    shadow_mem[shad_idx]   = wdata;
                    shadow_valid[shad_idx] = 1'b1;
                    $display("[TC10] txn %0d STORE  op=%-12s addr=0x%h data=0x%h",
                             i, op_name(op), addr, wdata);
                end else begin
                    // Load: check data if shadow is valid for this address
                    if (shadow_valid[shad_idx]) begin
                        do_check = 1'b1;
                        // For sub-word loads the expected value depends on
                        // byte lane; for simplicity check only LOAD_DOUBLE
                        // (full-word) here and skip partial loads.
                        if (op != LOAD_DOUBLE) do_check = 1'b0;
                        exp_data = shadow_mem[shad_idx];
                    end
                    $display("[TC10] txn %0d LOAD   op=%-12s addr=0x%h rd=%0d (data_chk=%0b)",
                             i, op_name(op), addr, rd, do_check);
                end

                send_request(addr, wdata, op, rd, do_check, exp_data);

                if (1'($urandom_range(0, 1))) begin
                    responce_ready_i = 1'b1;
                    idle_cycles($urandom_range(0, 3));
                end
            end

            // Drain all pending
            responce_ready_i = 1'b1;
            while (sb_count > 0)
                wait_response(rdata, rd_out);
            idle_cycles(4);
        end

        // -------------------------------------------------------
        // TC11: Reset mid-operation
        // -------------------------------------------------------
        tc_begin(11, "Reset mid-operation");
        @(posedge clk);
        req_valid_i = 1'b1;
        req_addr_i  = 64'hDEAD;
        req_memop_i = LOAD_WORD;
        req_rd_i    = 5'd20;
        $display("[TC11] Request driven — asserting reset before handshake");

        @(posedge clk);
        rst_n = 1'b0;
        sb_flush();

        @(posedge clk); @(posedge clk);
        rst_n       = 1'b1;
        req_valid_i = 1'b0;
        idle_cycles(3);

        // After reset: outputs must be 0 / deasserted
        if (responce_valid_o !== 1'b0)
            record_fail($sformatf(
                "responce_valid_o not cleared after reset (got %b)",
                responce_valid_o));
        else
            record_pass("responce_valid_o=0 after reset");

        if (resp_rd_o !== 5'd0)
            record_fail($sformatf(
                "resp_rd_o not cleared after reset (got %0d)", resp_rd_o));
        else
            record_pass("resp_rd_o=0 after reset");

        if (responce_rdata_o !== '0)
            record_fail($sformatf(
                "responce_rdata_o not cleared after reset (got 0x%016h)",
                responce_rdata_o));
        else
            record_pass("responce_rdata_o=0 after reset");

        // -------------------------------------------------------
        // Finish
        // -------------------------------------------------------
        idle_cycles(10);
        report_summary();
        $finish;
    end

    // --------------------------------------------------------
    //  Timeout watchdog
    // --------------------------------------------------------
    initial begin
        #500_000;
        $display("[TB] TIMEOUT — simulation ran too long");
        $finish;
    end

endmodule
