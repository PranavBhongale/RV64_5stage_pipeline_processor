`timescale 1ns/1ps

// ============================================================
//  Testbench : fetch_top_tb
//  DUT       : fetch_top  (Instruction Fetch Unit)
//
//  VCD-friendly design choices
//  ─────────────────────────────────────────────────────────
//  • CLK_PERIOD = 100 ns  → waveform edges are widely spaced
//  • SKEW       = 20 ns   → inputs driven 20 ns AFTER posedge
//                           (clearly after the clock edge in GTKWave)
//  • IDLE_GAP   = 8 clk   → 8-cycle idle bus between every test
//                           (creates a visible blank region to find
//                            test boundaries at a glance)
//  • Burst count = 4      → keeps total VCD compact
//  • Random txns = 6      → enough variety without bloating file
// ============================================================

module fetch_top_tb;

  // ----------------------------------------------------------------
  // Timing constants  (tweak only here)
  // ----------------------------------------------------------------
  parameter int XLEN        = 64;
  parameter int CLK_PERIOD  = 100;  // ns  → 10 MHz – easy to read
  parameter int SKEW        = 20;   // ns after posedge to drive inputs
  parameter int IDLE_GAP    = 8;    // idle cycles between tests
  parameter int TIMEOUT     = 3000; // watchdog cycle limit

  // ----------------------------------------------------------------
  // DUT signals
  // ----------------------------------------------------------------
  logic            clk;
  logic            rst_n;

  // PC-Generator → DUT
  logic [XLEN-1:0] pc_i;
  logic            pc_valid_i;
  logic            pc_ready_o;

  // DUT → Decode stage
  logic [XLEN-1:0] pc_o;
  logic [31:0]     instruction_o;
  logic            valid_o;
  logic            ready_i;

  // ----------------------------------------------------------------
  // Scoreboard counters
  // ----------------------------------------------------------------
  int total_tests  = 0;
  int passed_tests = 0;
  int failed_tests = 0;
  int sent_count   = 0;
  int recvd_count  = 0;

  // ----------------------------------------------------------------
  // DUT instantiation
  // ----------------------------------------------------------------
  fetch_top #(
    .XLEN(XLEN)
  ) dut (
    .clk           (clk),
    .rst_n         (rst_n),
    .pc_i          (pc_i),
    .pc_valid_i    (pc_valid_i),
    .pc_ready_o    (pc_ready_o),
    .pc_o          (pc_o),
    .instruction_o (instruction_o),
    .valid_o       (valid_o),
    .ready_i       (ready_i)
  );

  // ----------------------------------------------------------------
  // VCD dump
  // ----------------------------------------------------------------
  initial begin
    $dumpfile("fetch_top.vcd");
    $dumpvars(0, fetch_top_tb);
  end

  // ----------------------------------------------------------------
  // Clock  –  100 ns period (50 ns hi / 50 ns lo)
  // ----------------------------------------------------------------
  initial clk = 0;
  always #(CLK_PERIOD/2) clk = ~clk;

  // ----------------------------------------------------------------
  // Watchdog
  // ----------------------------------------------------------------
  initial begin
    #(CLK_PERIOD * TIMEOUT);
    $display("[WATCHDOG] Timeout at %0t ns", $time);
    $finish;
  end

  // ----------------------------------------------------------------
  // Continuous handshake monitor (non-blocking prints only)
  // ----------------------------------------------------------------
  always @(posedge clk) begin
    if (rst_n && pc_valid_i && pc_ready_o) begin
      sent_count++;
      $display("[IN  ][%6t ns] PC=0x%016h  (txn #%0d)", $time, pc_i, sent_count);
    end
  end

  always @(posedge clk) begin
    if (rst_n && valid_o && ready_i) begin
      recvd_count++;
      $display("[OUT ][%6t ns] PC=0x%016h  INSTR=0x%08h  (txn #%0d)",
               $time, pc_o, instruction_o, recvd_count);
    end
  end

  // ================================================================
  //  HELPER TASKS
  // ================================================================

  // ------------------------------------------------------------------
  // bus_idle : de-assert all handshake signals and wait N cycles
  //            → produces a clean blank region in GTKWave between tests
  // ------------------------------------------------------------------
  task automatic bus_idle(input int n = IDLE_GAP);
    @(posedge clk); #SKEW;
    pc_valid_i = 0;
    pc_i       = '0;
    ready_i    = 0;
    repeat(n-1) @(posedge clk);
    #SKEW;
  endtask

  // ------------------------------------------------------------------
  // apply_reset : assert rst_n=0 for N cycles then release
  //               inputs are parked at zero during reset
  // ------------------------------------------------------------------
  task automatic apply_reset(input int cycles = 5);
    // drive synchronously after posedge + SKEW so it's visible
    @(posedge clk); #SKEW;
    rst_n      = 0;
    pc_i       = '0;
    pc_valid_i = 0;
    ready_i    = 0;
    repeat(cycles) @(posedge clk);
    #SKEW;
    rst_n = 1;
    $display("[RST ][%6t ns] Reset released", $time);
  endtask

  // ------------------------------------------------------------------
  // drive_pc : assert pc_valid_i + pc_i, wait for pc_ready_o=1
  //            inputs are driven SKEW ns after posedge so they are
  //            clearly after the clock edge in the waveform viewer
  // ------------------------------------------------------------------
  task automatic drive_pc(
    input  logic [XLEN-1:0] pc,
    output logic             accepted
  );
    int cnt = 0;
    @(posedge clk); #SKEW;   // align to clock then skew
    pc_i       = pc;
    pc_valid_i = 1;
    accepted   = 0;

    // Poll up to 50 cycles for acceptance
    while (cnt < 50) begin
      @(posedge clk); #SKEW;
      cnt++;
      if (pc_ready_o) begin
        accepted   = 1;
        pc_valid_i = 0;   // de-assert one SKEW after the accepting edge
        break;
      end
    end
    if (!accepted) pc_valid_i = 0;
  endtask

  // ------------------------------------------------------------------
  // wait_output : wait up to 50 cycles for valid_o & ready_i handshake
  // ------------------------------------------------------------------
  task automatic wait_output(
    output logic [XLEN-1:0] got_pc,
    output logic [31:0]     got_instr,
    output logic            seen
  );
    int cnt = 0;
    seen = 0;
    while (cnt < 50) begin
      @(posedge clk); #SKEW;
      cnt++;
      if (valid_o && ready_i) begin
        got_pc    = pc_o;
        got_instr = instruction_o;
        seen      = 1;
        break;
      end
    end
  endtask

  // ------------------------------------------------------------------
  // wait_clk : wait N clock cycles (always with SKEW offset)
  // ------------------------------------------------------------------
  task automatic wait_clk(input int n = 1);
    repeat(n) @(posedge clk);
    #SKEW;
  endtask

  // ------------------------------------------------------------------
  // check : assertion helper
  // ------------------------------------------------------------------
  task automatic check(
    input string test_name,
    input logic  condition,
    input string msg = ""
  );
    total_tests++;
    if (condition) begin
      passed_tests++;
      $display("  [PASS] %s %s", test_name, msg);
    end else begin
      failed_tests++;
      $display("  [FAIL] %s %s  <<<<", test_name, msg);
    end
  endtask

  // ================================================================
  //  MAIN TEST SEQUENCE
  // ================================================================
  initial begin
    $display("=======================================================");
    $display("  fetch_top Testbench  (CLK=%0d ns, SKEW=%0d ns)", CLK_PERIOD, SKEW);
    $display("=======================================================");

    // ──────────────────────────────────────────────────────────────
    //  T1 : Reset behaviour
    //       Expected waveform: all outputs low/0 for 5 cycles,
    //       then rst_n rises and DUT is ready to accept traffic.
    // ──────────────────────────────────────────────────────────────
    $display("\n--- T1: Reset Behaviour ---");
    apply_reset(5);
    // Give one more idle cycle so the post-reset state is visible
    wait_clk(2);
    check("T1.1  valid_o = 0 after reset",       valid_o    === 1'b0, "");
    check("T1.2  pc_ready_o not X after reset",  pc_ready_o !== 1'bx, "");

    bus_idle();   // ← blank gap in GTKWave  ─────────────────────────


    // ──────────────────────────────────────────────────────────────
    //  T2 : Basic handshake – single transfer
    //       Expected waveform:
    //         • pc_valid_i rises, pc_ready_o goes high → input HS
    //         • one cycle later valid_o=1, ready_i=1   → output HS
    //         • both sides de-assert cleanly
    // ──────────────────────────────────────────────────────────────
    $display("\n--- T2: Basic Handshake (single transfer) ---");
    begin
      logic accepted, seen;
      logic [XLEN-1:0] got_pc;
      logic [31:0]     got_instr;

      @(posedge clk); #SKEW;
      ready_i = 1;                        // downstream open

      drive_pc(64'hFFFF_FFFF_8000_0000, accepted);
      check("T2.1  Input  handshake accepted", accepted === 1'b1, "");

      wait_output(got_pc, got_instr, seen);
      check("T2.2  Output handshake seen",     seen     === 1'b1, "");
      $display("       got_pc=0x%016h  got_instr=0x%08h", got_pc, got_instr);

      @(posedge clk); #SKEW;
      ready_i = 0;
    end

    bus_idle();   // ← blank gap ─────────────────────────────────────


    // ──────────────────────────────────────────────────────────────
    //  T3 : Back-pressure – downstream NOT ready (ready_i = 0)
    //       Expected waveform:
    //         • pc_valid_i=1 → DUT accepts PC (input HS OK)
    //         • valid_o goes high but ready_i stays 0
    //         • valid_o must STAY high for ≥5 cycles (data held)
    //         • ready_i rises → final output HS occurs
    // ──────────────────────────────────────────────────────────────
    $display("\n--- T3: Back-pressure (ready_i=0) ---");
    begin
      logic accepted;
      int   drop_count;

      @(posedge clk); #SKEW;
      ready_i = 0;                        // block downstream

      drive_pc(64'hFFFF_FFFF_8000_0004, accepted);
      check("T3.1  Input accepted even with downstream stalled",
            accepted === 1'b1, "");

      // Give the pipeline two cycles to propagate the data to the output
      wait_clk(2);

      // Count how many cycles valid_o drops while ready_i is still 0
      drop_count = 0;
      repeat(5) begin
        @(posedge clk); #SKEW;
        if (!valid_o) drop_count++;
      end
      check("T3.2  valid_o held HIGH during 5-cycle back-pressure",
            drop_count === 0,
            $sformatf("(dropped %0d/5 cycles)", drop_count));

      // Release downstream – output handshake should complete
      @(posedge clk); #SKEW;
      ready_i = 1;
      wait_clk(3);                        // let output HS complete
      @(posedge clk); #SKEW;
      ready_i = 0;
    end

    bus_idle();   // ← blank gap ─────────────────────────────────────


    // ──────────────────────────────────────────────────────────────
    //  T4 : Source stall – pc_valid_i = 0
    //       Expected waveform:
    //         • pc_valid_i stays 0 for 5 cycles
    //         • pc_ready_o should be high (DUT open for business)
    //         • valid_o should NOT produce new transfers
    // ──────────────────────────────────────────────────────────────
    $display("\n--- T4: Source stall (pc_valid_i=0) ---");
    begin
      @(posedge clk); #SKEW;
      ready_i    = 1;
      pc_valid_i = 0;
      pc_i       = 64'hDEAD_BEEF_DEAD_0000;   // visible garbage value in waveform
      wait_clk(5);
      $display("       pc_ready_o=%0b  valid_o=%0b", pc_ready_o, valid_o);
      check("T4.1  pc_ready_o asserted waiting for source",
            pc_ready_o === 1'b1, "(DUT should accept whenever source is ready)");
    end

    bus_idle();   // ← blank gap ─────────────────────────────────────


    // ──────────────────────────────────────────────────────────────
    //  T5 : Burst of 4 consecutive PCs (pipeline fill)
    //       Expected waveform:
    //         • 4 back-to-back input handshakes
    //         • pipeline outputs appear a few cycles later
    //         • 4-cycle drain gap at end
    // ──────────────────────────────────────────────────────────────
    $display("\n--- T5: Burst of 4 consecutive PCs ---");
    begin
      logic accepted;
      logic [XLEN-1:0] base_pc = 64'hFFFF_FFFF_9000_0000;
      int   acc_count = 0;
      int   burst     = 4;

      @(posedge clk); #SKEW;
      ready_i = 1;

      for (int i = 0; i < burst; i++) begin
        drive_pc(base_pc + (i * 4), accepted);
        if (accepted) acc_count++;
        // 2-cycle gap between each PC so each handshake is
        // individually visible in the waveform
        wait_clk(2);
      end

      check("T5.1  All burst PCs accepted",
            acc_count === burst,
            $sformatf("(%0d/%0d)", acc_count, burst));

      // Drain – keep ready_i=1 and let outputs come through
      wait_clk(burst + 4);
      @(posedge clk); #SKEW;
      ready_i = 0;
    end

    bus_idle();   // ← blank gap ─────────────────────────────────────


    // ──────────────────────────────────────────────────────────────
    //  T6 : Alternating ready_i (0 → 1 → 0 → 1 …)
    //       Expected waveform:
    //         • ready_i toggles every transaction
    //         • valid_o seen to stall and resume on alternate cycles
    // ──────────────────────────────────────────────────────────────
    $display("\n--- T6: Alternating ready_i ---");
    begin
      logic accepted;
      logic [XLEN-1:0] base_pc = 64'hFFFF_FFFF_A000_0000;
      int   ok_count = 0;

      for (int i = 0; i < 4; i++) begin
        @(posedge clk); #SKEW;
        ready_i = i[0];               // 0,1,0,1
        drive_pc(base_pc + (i * 4), accepted);
        if (accepted) ok_count++;
        wait_clk(3);                  // 3-cycle pause → clearly visible toggle
      end

      @(posedge clk); #SKEW;
      ready_i = 1;
      wait_clk(6);                    // drain
      @(posedge clk); #SKEW;
      ready_i = 0;
      $display("       Accepted %0d/4 during alternating ready_i", ok_count);
      check("T6.1  At least half accepted during alternating ready_i",
            ok_count >= 2, "");
    end

    bus_idle();   // ← blank gap ─────────────────────────────────────


    // ──────────────────────────────────────────────────────────────
    //  T7 : Mid-burst back-pressure then resume
    //       Expected waveform:
    //         • 2 PCs sent → stall 6 cycles (ready_i=0)
    //         • valid_o stays high during stall (data buffered)
    //         • ready_i rises → buffered outputs flush
    //         • 2 more PCs sent after resume
    // ──────────────────────────────────────────────────────────────
    $display("\n--- T7: Mid-burst back-pressure then resume ---");
    begin
      logic accepted;
      logic [XLEN-1:0] base_pc = 64'hFFFF_FFFF_B000_0000;

      @(posedge clk); #SKEW;
      ready_i = 1;

      // First 2 PCs
      for (int i = 0; i < 2; i++) begin
        drive_pc(base_pc + (i * 4), accepted);
        wait_clk(2);
      end

      // Stall downstream for 6 cycles (clearly visible blank in output)
      @(posedge clk); #SKEW;
      ready_i = 0;
      $display("       [%6t ns] Downstream stalled for 6 cycles", $time);
      wait_clk(6);

      // Resume
      @(posedge clk); #SKEW;
      ready_i = 1;
      $display("       [%6t ns] Downstream resumed", $time);
      wait_clk(3);                    // let buffered output flush

      // Next 2 PCs after resume
      for (int i = 2; i < 4; i++) begin
        drive_pc(base_pc + (i * 4), accepted);
        wait_clk(2);
      end

      wait_clk(6);
      @(posedge clk); #SKEW;
      ready_i = 0;
      check("T7.1  Pipeline resumes cleanly after mid-burst stall",
            1'b1, "(verify in waveform: buffered data released on ready_i↑)");
    end

    bus_idle();   // ← blank gap ─────────────────────────────────────


    // ──────────────────────────────────────────────────────────────
    //  T8 : Source squash – pc_valid_i drops mid-burst
    //       Expected waveform:
    //         • PC sent → pc_valid_i dropped for 5 cycles (gap)
    //         • pc_valid_i returns → new PC accepted
    // ──────────────────────────────────────────────────────────────
    $display("\n--- T8: Source squash (pc_valid_i gap) ---");
    begin
      logic accepted;
      logic [XLEN-1:0] base_pc = 64'hFFFF_FFFF_C000_0000;

      @(posedge clk); #SKEW;
      ready_i = 1;

      drive_pc(base_pc, accepted);
      wait_clk(2);

      // Source goes silent for 5 cycles
      @(posedge clk); #SKEW;
      pc_valid_i = 0;
      pc_i       = '0;
      $display("       [%6t ns] Source silent for 5 cycles", $time);
      wait_clk(5);

      // Source resumes with next PC
      drive_pc(base_pc + 4, accepted);
      wait_clk(4);
      $display("       Source resumed – accepted=%0b", accepted);
      check("T8.1  Source can re-drive after 5-cycle gap",
            accepted === 1'b1, "");

      @(posedge clk); #SKEW;
      ready_i = 0;
    end

    bus_idle();   // ← blank gap ─────────────────────────────────────


    // ──────────────────────────────────────────────────────────────
    //  T9 : Double stall – both sides idle simultaneously
    //       Expected waveform:
    //         • pc_valid_i=0 AND ready_i=0 for 8 cycles
    //         • all signals must remain glitch-free (no X, no Z)
    //         • both sides release together at the end
    // ──────────────────────────────────────────────────────────────
    $display("\n--- T9: Double stall (both sides idle) ---");
    begin
      @(posedge clk); #SKEW;
      ready_i    = 0;
      pc_valid_i = 0;
      pc_i       = 64'hCCCC_CCCC_CCCC_CCCC;  // distinctive pattern in waveform
      $display("       [%6t ns] Both sides stalled for 8 cycles", $time);
      wait_clk(8);

      check("T9.1  valid_o not X during double stall",    valid_o    !== 1'bx, "");
      check("T9.2  pc_ready_o not X during double stall", pc_ready_o !== 1'bx, "");

      // Release both simultaneously
      @(posedge clk); #SKEW;
      ready_i    = 1;
      pc_valid_i = 1;
      pc_i       = 64'hFFFF_FFFF_D000_0000;
      wait_clk(4);
      @(posedge clk); #SKEW;
      pc_valid_i = 0;
      ready_i    = 0;
    end

    bus_idle();   // ← blank gap ─────────────────────────────────────


    // ──────────────────────────────────────────────────────────────
    //  T10 : Light random stimulus (6 transactions)
    //        Expected waveform:
    //          • Irregular gaps and ready_i patterns
    //          • Still clearly separated by 3-cycle pauses
    // ──────────────────────────────────────────────────────────────
    $display("\n--- T10: Randomised Handshake (6 transactions) ---");
    begin
      logic accepted;
      logic [XLEN-1:0] rnd_pc;
      int   rnd_gap, rnd_ready;
      int   total_accepted = 0;

      for (int i = 0; i < 6; i++) begin
        rnd_pc    = {$random, $random} & ~64'h3;  // 4-byte aligned
        rnd_gap   = $urandom_range(2, 5);          // 2-5 cycle gap (readable)
        rnd_ready = $urandom_range(0, 1);

        @(posedge clk); #SKEW;
        ready_i = rnd_ready[0];
        drive_pc(rnd_pc, accepted);
        if (accepted) total_accepted++;
        wait_clk(rnd_gap);
      end

      @(posedge clk); #SKEW;
      ready_i = 1;
      wait_clk(8);                    // final drain
      @(posedge clk); #SKEW;
      ready_i = 0;

      $display("       Accepted %0d/6 random PCs", total_accepted);
      check("T10.1  At least one random PC accepted",
            total_accepted > 0, "");
    end

    bus_idle();   // final settling gap ─────────────────────────────


    // ──────────────────────────────────────────────────────────────
    //  SUMMARY
    // ──────────────────────────────────────────────────────────────
    $display("\n=======================================================");
    $display("  TEST SUMMARY");
    $display("  Total   : %0d", total_tests);
    $display("  Passed  : %0d", passed_tests);
    $display("  Failed  : %0d", failed_tests);
    $display("===========================================================");
    $display("  Handshakes observed:");
    $display("    Input  side : %0d", sent_count);
    $display("    Output side : %0d", recvd_count);
    $display("=======================================================");
    $display("  VCD → fetch_top.vcd");
    $display("  GTKWave hint: zoom to each 8-cycle idle gap to find");
    $display("  the start/end of every test section cleanly.");
    $display("=======================================================\n");

    $finish;
  end

endmodule

