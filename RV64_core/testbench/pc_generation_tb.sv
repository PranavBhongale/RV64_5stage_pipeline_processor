`timescale 1ns/1ps

module pc_generation_tb;
  parameter int XLEN = 64;

  // DUT signals
  logic clk;
  logic rst_n;
  logic fetch_ready;
  logic pc_valid;
  logic [XLEN-1:0] pc_from_execution;
  logic [XLEN-1:0] pc_from_decoding_stage;
  logic [XLEN-1:0] pc_target_exe;
  logic branch_taken;
  logic [XLEN-1:0] PC;
  logic flush;

  // DUT instantiation
  pc_generation #(.XLEN(XLEN)) dut (
    .clk(clk),
    .rst_n(rst_n),
    .fetch_ready(fetch_ready),
    .pc_valid(pc_valid),
    .pc_from_execution(pc_from_execution),
    .pc_from_decoding_stage(pc_from_decoding_stage),
    .pc_target_exe(pc_target_exe),
    .branch_taken(branch_taken),
    .pc(PC),
    .flush(flush)
  );

  // Clock generation
  initial clk = 0;
  always #5 clk = ~clk;

  // Reset task
  task automatic reset_f();
    rst_n = 0;
    fetch_ready = 0;
    pc_from_execution = 0;
    pc_from_decoding_stage = 0;
    pc_target_exe = 0;
    branch_taken = 0;
    @(posedge clk);
    @(posedge clk);
    rst_n = 1;
  endtask

  // Stimulus
  initial begin
    $dumpfile("waveforms/pc.vcd");
    $dumpvars(0, pc_generation_tb);

    // Case 0: Reset
    reset_f();
    $display("[%0t] Reset applied, PC=%0h, flush=%0b, valid=%0b",
             $time, PC, flush, pc_valid);

         fetch_ready = 1;
         repeat(3) @(posedge clk);
         branch_taken = 1;
         pc_from_execution = 64'h0000_0000_0000_0004;
         pc_from_decoding_stage = 64'h0000_0000_0000_0008;
         pc_target_exe = 64'h0000_0000_0000_0008;
         repeat(3) @(posedge clk);
          branch_taken = 1;
          pc_from_execution = 64'h0000_0000_0000_0004;
          pc_from_decoding_stage = 64'h0000_0000_0000_0004;
          pc_target_exe = 64'h0000_0000_0000_0008;
          @(posedge clk);
          fetch_ready = 0;
          @(posedge clk);
                    fetch_ready = 1;

          branch_taken = 0;
          @(posedge clk);
    #100 $finish;
  end

  // Assertions for corner cases
  always @(posedge clk) begin
    if(branch_taken && (pc_target_exe != pc_from_decoding_stage)) begin
      assert(flush == 1) else $error("Flush not asserted on misprediction!");
    end
    if(branch_taken && (pc_target_exe == pc_from_decoding_stage)) begin
      assert(flush == 0) else $error("Flush wrongly asserted on correct prediction!");
    end
  end

endmodule
