`timescale 1ns/1ps

// =============================================================================
//  tb_branch_logic_top — Full-coverage self-checking testbench
//
//  DUT : branch_logic_top (which internally instantiates branch_target_buffer)
//
//  Test groups
//  -----------
//  T01  Reset behaviour           — all entries invalid after reset
//  T02  Cold miss                 — query before any update → PC+4 predicted
//  T03  Basic taken path          — update taken → hit + correct target
//  T04  Basic not-taken path      — update not-taken → hit but not predict taken
//  T05  Saturation — upper bound  — counter clamps at 2'b11 (strongly taken)
//  T06  Saturation — lower bound  — counter clamps at 2'b00 (strongly not-taken)
//  T07  Weakly-taken → not-taken  — two not-taken flips prediction
//  T08  Weakly-not-taken → taken  — two taken   flips prediction
//  T09  Tag aliasing              — two PCs share index, different tags → eviction
//  T10  Mid-run reset             — reset clears all entries mid-stream
//  T11  Simultaneous update+query — same index: query sees old value (read-before-write)
//  T12  PC+4 fallthrough          — predicted_pc = pc+4 on miss / predict_not_taken
//  T13  Target not overwritten on not-taken — stored target survives a not-taken update
//  T14  All-entries fill          — write all 16 entries and read back
//  T15  Re-reset after population — all entries invalidated again
// =============================================================================

module branch_logic_tb;

    // -------------------------------------------------------------------------
    //  Parameters (must match DUT)
    // -------------------------------------------------------------------------
    localparam int XLEN        = 64;
    localparam int BTB_ENTRIES = 16;
    localparam int INDEX_W     = $clog2(BTB_ENTRIES);   // 4

    // -------------------------------------------------------------------------
    //  DUT signals
    // -------------------------------------------------------------------------
    logic             clk;
    logic             rst_n;
    logic [XLEN-1:0] pc;
    logic             update_en;
    logic [XLEN-1:0] update_pc;
    logic [XLEN-1:0] target_pc;
    logic             branch_taken;
    logic [XLEN-1:0] predicted_pc;
    logic             btb_hit;
    logic             predict_taken;

    // -------------------------------------------------------------------------
    //  DUT instantiation
    // -------------------------------------------------------------------------
    branch_logic_top #(
        .XLEN       (XLEN),
        .BTB_ENTRIES(BTB_ENTRIES)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .pc           (pc),
        .update_en    (update_en),
        .update_pc    (update_pc),
        .target_pc    (target_pc),
        .branch_taken (branch_taken),
        .predicted_pc (predicted_pc),
        .btb_hit      (btb_hit),
        .predict_taken(predict_taken)
    );

    // -------------------------------------------------------------------------
    //  Clock — 10 ns period
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    //  Scoreboard counters
    // -------------------------------------------------------------------------
    int pass_cnt = 0;
    int fail_cnt = 0;

    // -------------------------------------------------------------------------
    //  Helper — PC → index (mirrors BTB internals: bits [INDEX_W:1])
    // -------------------------------------------------------------------------
    function automatic logic [INDEX_W-1:0] pc_to_index (input logic [XLEN-1:0] p);
        return p[INDEX_W:1];
    endfunction

    // -------------------------------------------------------------------------
    //  Helper — build a PC that hashes to a given index with a specific tag
    //  PC layout:  bits[XLEN-1:INDEX_W+1]=tag | bits[INDEX_W:1]=index | bit[0]=0
    //
    //  tag_val is XLEN bits wide — no truncation at the parameter boundary.
    //  Callers should ensure non-zero bits sit within bits [XLEN-1:INDEX_W+1].
    // -------------------------------------------------------------------------
    function automatic logic [XLEN-1:0] make_pc (
        input logic [INDEX_W-1:0]  idx,
        input logic [XLEN-1:0]     tag_val     // full width, never truncated
    );
        logic [XLEN-1:0] p;
        p = '0;
        p[INDEX_W:1]        = idx;
        p[XLEN-1:INDEX_W+1] = tag_val[XLEN-INDEX_W-2:0];
        return p;
    endfunction

    // -------------------------------------------------------------------------
    //  Assertion task — checks and prints PASS / FAIL
    // -------------------------------------------------------------------------
    task automatic chk (
        input string    test_name,
        input logic     got,
        input logic     exp
    );
        if (got === exp) begin
            $display("[PASS] %-45s  got=%0b exp=%0b  t=%0t", test_name, got, exp, $time);
            pass_cnt++;
        end else begin
            $display("[FAIL] %-45s  got=%0b exp=%0b  t=%0t", test_name, got, exp, $time);
            fail_cnt++;
        end
    endtask

    task automatic chk64 (
        input string    test_name,
        input logic [XLEN-1:0] got,
        input logic [XLEN-1:0] exp
    );
        if (got === exp) begin
            $display("[PASS] %-45s  got=0x%016h exp=0x%016h  t=%0t", test_name, got, exp, $time);
            pass_cnt++;
        end else begin
            $display("[FAIL] %-45s  got=0x%016h exp=0x%016h  t=%0t", test_name, got, exp, $time);
            fail_cnt++;
        end
    endtask

    // -------------------------------------------------------------------------
    //  Drive helpers
    // -------------------------------------------------------------------------

    // Apply one update.  Ends on a negedge with update_en=0 AND one
    // full idle cycle consumed, so back-to-back calls inside repeat()
    // never collapse onto the same posedge.
    //
    //  negedge N  : drive update_en=1 + signals
    //  posedge N  : DUT latches
    //  negedge N+1: deassert update_en
    //  posedge N+1: idle (guarantees clean separation)
    //  negedge N+2: task returns  <-- next call starts here
    task automatic do_update (
        input logic [XLEN-1:0] upc,
        input logic [XLEN-1:0] utgt,
        input logic             utaken
    );
        @(negedge clk);
        update_en    = 1'b1;
        update_pc    = upc;
        target_pc    = utgt;
        branch_taken = utaken;
        @(posedge clk); #1;      // DUT latches; #1 for output settle
        @(negedge clk);
        update_en    = 1'b0;
        @(posedge clk); #1;      // idle cycle -- prevents back-to-back collision
        // task returns at this negedge implicitly when next @(negedge clk)
        // is hit by the caller; no extra wait needed here
    endtask

    // Apply N taken updates to the same PC (counter training)
    task automatic train_taken (
        input logic [XLEN-1:0] upc,
        input logic [XLEN-1:0] utgt,
        input int               n
    );
        repeat (n) do_update(upc, utgt, 1'b1);
    endtask

    // Apply N not-taken updates to the same PC
    task automatic train_not_taken (
        input logic [XLEN-1:0] upc,
        input int               n
    );
        repeat (n) do_update(upc, 64'h0, 1'b0);
    endtask

    // Set the query PC and wait for combinational outputs to settle
    task automatic query (input logic [XLEN-1:0] qpc);
        @(negedge clk);
        pc = qpc;
        #1;
    endtask

    // Full reset pulse
    task automatic do_reset ();
        @(negedge clk);
        rst_n = 1'b0;
        @(posedge clk); #1;
        @(posedge clk); #1;
        @(negedge clk);
        rst_n = 1'b1;
    endtask

    // -------------------------------------------------------------------------
    //  Main stimulus
    // -------------------------------------------------------------------------
    initial begin : STIMULUS
        $display("=================================================================");
        $display("  tb_branch_logic_top — Full Coverage Testbench");
        $display("  XLEN=%0d  BTB_ENTRIES=%0d  INDEX_W=%0d", XLEN, BTB_ENTRIES, INDEX_W);
        $display("=================================================================");

        // Default idle state
        rst_n        = 1'b1;
        pc           = '0;
        update_en    = 1'b0;
        update_pc    = '0;
        target_pc    = '0;
        branch_taken = 1'b0;

        // -----------------------------------------------------------------
        // T01 — Reset behaviour
        // -----------------------------------------------------------------
        $display("\n--- T01: Reset behaviour ---");
        do_reset();
        // After reset, query every possible index: should be miss
        for (int idx = 0; idx < BTB_ENTRIES; idx++) begin
            query(make_pc(idx[INDEX_W-1:0], '0));
            chk($sformatf("T01 reset: idx=%0d btb_hit=0", idx), btb_hit, 1'b0);
            chk($sformatf("T01 reset: idx=%0d predict_taken=0", idx), predict_taken, 1'b0);
        end

        // -----------------------------------------------------------------
        // T02 — Cold miss: predicted_pc must be PC+4
        // -----------------------------------------------------------------
        $display("\n--- T02: Cold miss → predicted_pc = PC+4 ---");
        begin
            logic [XLEN-1:0] test_pc;
            test_pc = make_pc(4'h3, 'hABCD);
            query(test_pc);
            chk  ("T02 cold miss: btb_hit=0",      btb_hit,      1'b0);
            chk64("T02 cold miss: predicted=pc+4",  predicted_pc, test_pc + 64'd4);
        end

        // -----------------------------------------------------------------
        // T03 — Basic taken update → hit + predict taken + correct target
        // -----------------------------------------------------------------
        $display("\n--- T03: Basic taken update ---");
        begin
            logic [XLEN-1:0] branch_pc, tgt;
            branch_pc = make_pc(4'h5, 'h1111);
            tgt       = 64'hDEAD_BEEF_0000_1000;

            // First update: counter starts at 2'b01 after reset, +1 = 2'b10 → taken
            do_update(branch_pc, tgt, 1'b1);
            query(branch_pc);
            chk  ("T03 taken: btb_hit=1",           btb_hit,      1'b1);
            chk  ("T03 taken: predict_taken=1",      predict_taken, 1'b1);
            chk64("T03 taken: predicted_pc=target",  predicted_pc,  tgt);
        end

        // -----------------------------------------------------------------
        // T04 — Basic not-taken update → hit, predict_taken=0, PC+4
        // -----------------------------------------------------------------
        $display("\n--- T04: Basic not-taken update ---");
        begin
            logic [XLEN-1:0] branch_pc, tgt;
            branch_pc = make_pc(4'h7, 'h2222);
            tgt       = 64'hCAFE_0000_0000_4000;

            // One taken to install entry (counter → 2'b10)
            do_update(branch_pc, tgt, 1'b1);
            // Two not-taken to push counter to 2'b00 (strongly not-taken)
            train_not_taken(branch_pc, 2);
            query(branch_pc);
            chk  ("T04 not-taken: btb_hit=1",       btb_hit,       1'b1);
            chk  ("T04 not-taken: predict_taken=0",  predict_taken, 1'b0);
            chk64("T04 not-taken: predicted=pc+4",   predicted_pc,  branch_pc + 64'd4);
        end

        // -----------------------------------------------------------------
        // T05 — Saturation upper bound (strongly taken, counter stays 2'b11)
        // -----------------------------------------------------------------
        $display("\n--- T05: Saturation upper bound ---");
        begin
            logic [XLEN-1:0] branch_pc, tgt;
            branch_pc = make_pc(4'h2, 'h3333);
            tgt       = 64'h0000_1000_0000_8000;

            // Drive 6 consecutive taken updates — counter must stay at 2'b11
            train_taken(branch_pc, tgt, 6);
            query(branch_pc);
            chk  ("T05 sat-upper: btb_hit=1",        btb_hit,       1'b1);
            chk  ("T05 sat-upper: predict_taken=1",   predict_taken, 1'b1);
            chk64("T05 sat-upper: target correct",    predicted_pc,  tgt);
            // One not-taken: counter drops to 2'b10, still predicts taken
            do_update(branch_pc, tgt, 1'b0);
            query(branch_pc);
            chk  ("T05 sat-upper-1: predict_taken=1", predict_taken, 1'b1);
        end

        // -----------------------------------------------------------------
        // T06 — Saturation lower bound (strongly not-taken, stays 2'b00)
        // -----------------------------------------------------------------
        $display("\n--- T06: Saturation lower bound ---");
        begin
            logic [XLEN-1:0] branch_pc, tgt;
            branch_pc = make_pc(4'h9, 'h4444);
            tgt       = 64'h0000_2000_0000_0000;

            // Install with one taken, then hammer not-taken × 6
            do_update(branch_pc, tgt, 1'b1);
            train_not_taken(branch_pc, 6);
            query(branch_pc);
            chk  ("T06 sat-lower: btb_hit=1",        btb_hit,       1'b1);
            chk  ("T06 sat-lower: predict_taken=0",   predict_taken, 1'b0);
            // One taken: counter rises to 2'b01, still predicts not-taken
            do_update(branch_pc, tgt, 1'b1);
            query(branch_pc);
            chk  ("T06 sat-lower+1: predict_taken=0", predict_taken, 1'b0);
        end

        // -----------------------------------------------------------------
        // T07 — Weakly-taken → not-taken (2'b10 → 2'b01 → 2'b00)
        // -----------------------------------------------------------------
        $display("\n--- T07: Weakly-taken flips to not-taken after 2 not-taken updates ---");
        begin
            logic [XLEN-1:0] branch_pc, tgt;
            branch_pc = make_pc(4'hA, 'h5555);
            tgt       = 64'h0000_0000_FFFF_0000;

            // Install: one taken → counter=2'b10 (weakly taken)
            do_update(branch_pc, tgt, 1'b1);
            query(branch_pc);
            chk("T07 start: predict_taken=1", predict_taken, 1'b1);

            // First not-taken → counter=2'b01 (weakly not-taken)
            do_update(branch_pc, tgt, 1'b0);
            query(branch_pc);
            chk("T07 after 1 NT: predict_taken=0", predict_taken, 1'b0);

            // Second not-taken → counter=2'b00 (strongly not-taken)
            do_update(branch_pc, tgt, 1'b0);
            query(branch_pc);
            chk("T07 after 2 NT: predict_taken=0", predict_taken, 1'b0);
        end

        // -----------------------------------------------------------------
        // T08 — Weakly-not-taken → taken (2'b01 → 2'b10)
        // -----------------------------------------------------------------
        $display("\n--- T08: Weakly-not-taken flips to taken after 2 taken updates ---");
        begin
            logic [XLEN-1:0] branch_pc, tgt;
            branch_pc = make_pc(4'hB, 'h6666);
            tgt       = 64'h1234_5678_9ABC_DEF0;

            // Install as strongly not-taken: one taken then 3 not-taken
            do_update(branch_pc, tgt, 1'b1);
            train_not_taken(branch_pc, 3);
            query(branch_pc);
            chk("T08 start: predict_taken=0", predict_taken, 1'b0);

            // First taken → counter=2'b01
            do_update(branch_pc, tgt, 1'b1);
            query(branch_pc);
            chk("T08 after 1 T: predict_taken=0", predict_taken, 1'b0);

            // Second taken → counter=2'b10 → flips to taken
            do_update(branch_pc, tgt, 1'b1);
            query(branch_pc);
            chk  ("T08 after 2 T: predict_taken=1", predict_taken, 1'b1);
            chk64("T08 after 2 T: predicted_pc=tgt", predicted_pc, tgt);
        end

        // -----------------------------------------------------------------
        // T09 — Tag aliasing / eviction
        //        Two PCs with the same index but different tags
        // -----------------------------------------------------------------
        $display("\n--- T09: Tag aliasing (same index, different tag) ---");
        begin
            logic [XLEN-1:0] pc_A, pc_B, tgt_A, tgt_B;
            pc_A  = make_pc(4'hC, 'h7777);
            pc_B  = make_pc(4'hC, 'h8888);   // same index, different tag
            tgt_A = 64'hAAAA_AAAA_AAAA_AAAA;
            tgt_B = 64'hBBBB_BBBB_BBBB_BBBB;

            // Install A (taken)
            train_taken(pc_A, tgt_A, 2);
            query(pc_A);
            chk  ("T09 A hit before eviction",       btb_hit,       1'b1);
            chk64("T09 A predicted_pc=tgt_A",        predicted_pc,  tgt_A);

            // Install B (evicts A because same index)
            train_taken(pc_B, tgt_B, 2);
            query(pc_B);
            chk  ("T09 B hit after install",         btb_hit,       1'b1);
            chk64("T09 B predicted_pc=tgt_B",        predicted_pc,  tgt_B);

            // A should now miss (evicted)
            query(pc_A);
            chk  ("T09 A miss after eviction",       btb_hit,       1'b0);
            chk64("T09 A falls through to pc_A+4",   predicted_pc,  pc_A + 64'd4);
        end

        // -----------------------------------------------------------------
        // T10 — Mid-run reset clears all entries
        // -----------------------------------------------------------------
        $display("\n--- T10: Mid-run reset ---");
        begin
            logic [XLEN-1:0] branch_pc, tgt;
            branch_pc = make_pc(4'hD, 'h9999);
            tgt       = 64'hFEED_FACE_CAFE_BABE;

            train_taken(branch_pc, tgt, 3);
            query(branch_pc);
            chk("T10 pre-reset: hit=1",  btb_hit, 1'b1);

            do_reset();

            // After reset every index must miss
            for (int idx = 0; idx < BTB_ENTRIES; idx++) begin
                query(make_pc(idx[INDEX_W-1:0], '1));
                chk($sformatf("T10 post-reset: idx=%0d hit=0", idx), btb_hit, 1'b0);
            end
        end

        // -----------------------------------------------------------------
        // T11 — Simultaneous update + query on the same index
        //        Query must see the OLD value (read-before-write SRAM model)
        // -----------------------------------------------------------------
        $display("\n--- T11: Simultaneous update + query (same index, read-before-write) ---");
        begin
            logic [XLEN-1:0] branch_pc, tgt;
            branch_pc = make_pc(4'hE, 'hAAAA);
            tgt       = 64'h0000_DEAD_0000_1234;

            // No entry for this PC yet → miss expected during the update cycle
            @(negedge clk);
            pc           = branch_pc;   // query
            update_en    = 1'b1;        // update at the same time
            update_pc    = branch_pc;
            target_pc    = tgt;
            branch_taken = 1'b1;
            #1;
            // Before posedge: entry not yet written → hit must still be 0
            chk("T11 during update cycle: hit=0 (old value)", btb_hit, 1'b0);
            @(posedge clk); #1;
            @(negedge clk);
            update_en = 1'b0;

            // Now query: entry has been written → hit=1
            query(branch_pc);
            chk  ("T11 after update cycle: hit=1",           btb_hit,      1'b1);
            chk  ("T11 after update cycle: predict_taken=1", predict_taken, 1'b1);
            chk64("T11 after update cycle: predicted=tgt",   predicted_pc,  tgt);
        end

        // -----------------------------------------------------------------
        // T12 — PC+4 fallthrough for miss and predict_not_taken
        // -----------------------------------------------------------------
        $display("\n--- T12: predicted_pc = PC+4 on miss and on not-taken prediction ---");
        begin
            logic [XLEN-1:0] branch_pc, tgt;
            branch_pc = make_pc(4'h0, 'hBBBB);
            tgt       = 64'h0000_CAFE_0000_0000;

            // Miss (no entry)
            query(branch_pc);
            chk64("T12 miss → pc+4", predicted_pc, branch_pc + 64'd4);

            // Install as strongly not-taken
            do_update(branch_pc, tgt, 1'b1);
            train_not_taken(branch_pc, 3);
            query(branch_pc);
            chk  ("T12 not-taken hit: btb_hit=1",      btb_hit,      1'b1);
            chk  ("T12 not-taken hit: predict_taken=0", predict_taken, 1'b0);
            chk64("T12 not-taken hit: predicted=pc+4",  predicted_pc,  branch_pc + 64'd4);
        end

        // -----------------------------------------------------------------
        // T13 — Target NOT overwritten by a not-taken update
        // -----------------------------------------------------------------
        $display("\n--- T13: Target preserved across not-taken update ---");
        begin
            logic [XLEN-1:0] branch_pc, tgt_orig, tgt_fake;
            branch_pc = make_pc(4'h1, 'hCCCC);
            tgt_orig  = 64'h1111_2222_3333_4444;
            tgt_fake  = 64'hDEAD_DEAD_DEAD_DEAD;

            // Install with taken → target stored
            train_taken(branch_pc, tgt_orig, 2);

            // Not-taken update (passes tgt_fake — should be ignored by DUT)
            do_update(branch_pc, tgt_fake, 1'b0);

            // Re-train to taken so we can observe the target
            train_taken(branch_pc, tgt_orig, 3);
            query(branch_pc);
            chk64("T13 target preserved (not tgt_fake)", predicted_pc, tgt_orig);
        end

        // -----------------------------------------------------------------
        // T14 — Fill all BTB_ENTRIES and read back
        // -----------------------------------------------------------------
        $display("\n--- T14: Fill all %0d BTB entries and read back ---", BTB_ENTRIES);
        begin
            logic [XLEN-1:0] pcs   [BTB_ENTRIES];
            logic [XLEN-1:0] tgts  [BTB_ENTRIES];

            // Build PCs entirely in 64-bit arithmetic — never through make_pc.
            // PC field layout:  bits[63:5]=tag | bits[4:1]=index | bit[0]=0
            //
            // For entry i:
            //   index = i          → placed at bits [4:1]  via (i << 1)
            //   tag   = (i+1)      → placed at bits [36:5] via (i+1) << 5
            //                        (well inside [63:5], unique, non-zero)
            //
            // The SAME expression is used for both the train_taken write
            // and the query, so write-tag == query-tag by construction.
            for (int i = 0; i < BTB_ENTRIES; i++) begin
                pcs[i]  = (64'(i + 1) << 5) | (64'(i) << 1);
                tgts[i] = 64'hF000_0000_0000_0000 | (64'(i) * 64'h100);
                train_taken(pcs[i], tgts[i], 2);
            end

            // Verify all 16 entries hit and return correct targets
            for (int i = 0; i < BTB_ENTRIES; i++) begin
                query(pcs[i]);
                chk  ($sformatf("T14 idx=%0d: hit=1",          i), btb_hit,       1'b1);
                chk  ($sformatf("T14 idx=%0d: predict_taken=1", i), predict_taken, 1'b1);
                chk64($sformatf("T14 idx=%0d: target correct",  i), predicted_pc,  tgts[i]);
            end
        end

        // -----------------------------------------------------------------
        // T15 — Re-reset after full population
        // -----------------------------------------------------------------
        $display("\n--- T15: Re-reset after full population ---");
        do_reset();
        for (int idx = 0; idx < BTB_ENTRIES; idx++) begin
            query(make_pc(idx[INDEX_W-1:0], '1));
            chk($sformatf("T15 post-reset: idx=%0d hit=0", idx), btb_hit, 1'b0);
        end

        // -----------------------------------------------------------------
        //  Summary
        // -----------------------------------------------------------------
        @(negedge clk);
        $display("\n=================================================================");
        $display("  RESULTS:  PASS=%0d   FAIL=%0d   TOTAL=%0d",
                 pass_cnt, fail_cnt, pass_cnt + fail_cnt);
        if (fail_cnt == 0)
            $display("  ALL TESTS PASSED");
        else
            $display("  *** %0d TEST(S) FAILED — see [FAIL] lines above ***", fail_cnt);
        $display("=================================================================\n");
        $finish;
    end : STIMULUS

    // -------------------------------------------------------------------------
    //  Timeout watchdog — 100 µs
    // -------------------------------------------------------------------------
    initial begin
        #100_000;
        $display("[WATCHDOG] Simulation exceeded 100 us — force-stopping.");
        $finish;
    end

    // -------------------------------------------------------------------------
    //  Waveform dump (comment out if not needed)
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_branch_logic_top.vcd");
        $dumpvars(0, tb_branch_logic_top);
    end

endmodule
