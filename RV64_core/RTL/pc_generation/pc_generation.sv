`timescale 1ns/1ps
module pc_generation #(
    parameter int XLEN = 64
) (
    // Clock and reset
    input  logic            clk,
    input  logic            rst_n,
    // Handshake with fetch unit
    input  logic            fetch_ready,
    output logic            pc_valid,
    // Correction inputs from pipeline stages
    input  logic [XLEN-1:0] pc_from_execution,       // PC of the branch/jump instr in EX (BTB update key)
    // Branch resolution from execute stage
    input  logic [XLEN-1:0] pc_target_exe,   // Resolved/correct branch target
    input  logic            branch_taken,     // EX: branch/jump was actually taken
    // PC output to fetch unit
    output logic [XLEN-1:0] pc,
    // Pipeline flush output (one-cycle pulse)
    output logic            flush
);

    // PC state
    logic [XLEN-1:0] current_pc;   // PC currently being fetched (drives BTB query)

    // BTB / branch-predictor outputs
    logic [XLEN-1:0] predicted_pc; // BTB prediction: target_pc or PC+4
    logic            btb_hit;
    logic            predict_taken_unused; // exposed by sub-module; unused here

    // Redirect target (combinational)
    logic [XLEN-1:0] redirect_pc;

    // BTB update (combinational one-cycle pulse)
    logic            update_enable;

    branch_logic_top #(
        .XLEN       (XLEN),
        .BTB_ENTRIES(16)
    ) u_branch_logic (
        .clk          (clk),
        .rst_n        (rst_n),

        // Query: current PC being fetched
        .pc           (current_pc),

        // Update: EX-stage branch resolution
        .update_en    (update_enable),
        .update_pc    (pc_from_execution),  // PC of the branch instruction in EX
        .target_pc    (pc_target_exe),      // Resolved (correct) target
        .branch_taken (branch_taken),       // Actual outcome from EX

        // Prediction outputs
        .predicted_pc (predicted_pc),
        .btb_hit      (btb_hit),
        .predict_taken(predict_taken_unused)
    );

    // -----------------------------------------------------------------
    // Redirect / flush decision
    // -----------------------------------------------------------------
    // NOTE (design simplification): correctly *skipping* the flush when
    // the BTB already predicted this branch/jump right requires tagging
    // the predicted target onto the instruction and carrying it, in
    // lock-step, all the way through Decode and Execute so it can be
    // compared against pc_target_exe in the very same cycle the branch
    // resolves. That tag does not exist anywhere else in this RTL, and
    // the previous code tried to fake it by comparing pc_target_exe
    // against whatever instruction happened to be sitting in Decode at
    // that moment (completely unrelated to the branch resolving in EX,
    // and off by two pipeline stages) - a latent correctness bug, since
    // a coincidental match could suppress a flush that was actually
    // required.
    //
    // Until the predicted-target tag is threaded through the pipeline,
    // we conservatively flush + redirect on every resolved taken
    // branch/jump. This is always correct (never executes down a wrong
    // path unrecovered); we still train the BTB on every resolution so
    // that once this exact branch is fetched again, `predicted_pc`
    // above already points at the right place.
    always_comb begin
        update_enable = branch_taken;
        redirect_pc   = pc_target_exe;
        flush         = branch_taken;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_pc <= '0;
            pc         <= '0;
            pc_valid   <= 1'b0;
        end else begin
            // FIX: pc_valid used to pulse for exactly one cycle per new
            // address and the stall branch re-copied the (already
            // advanced) current_pc into pc. Together that meant a PC
            // value could be silently replaced by the *next* one before
            // fetch ever got a chance to accept it (e.g. while fetch's
            // request was sitting in instruction memory's multi-cycle
            // latency) - instructions were dropped mid-fetch. There is
            // always a next address to offer once out of reset, so
            // pc_valid simply stays high; `pc` (and `current_pc`) only
            // change on cycles where `fetch_ready` says the previously
            // offered address was actually accepted - otherwise they
            // hold their value exactly as a valid/ready producer must.
            pc_valid <= 1'b1;
            if (fetch_ready) begin
                pc <= current_pc;
                if (flush)
                    current_pc <= redirect_pc;
                else
                    current_pc <= predicted_pc;
            end
            // else: hold pc / current_pc unchanged (implicit)
        end
    end
endmodule

