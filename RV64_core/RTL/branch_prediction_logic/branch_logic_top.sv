`timescale 1ns/1ps

module branch_logic_top #(
    parameter int XLEN         = 64,
    parameter int BTB_ENTRIES  = 16
)(
    input  logic             clk,
    input  logic             rst_n,

    // Current PC from fetch stage

    input  logic [XLEN-1:0] pc,

    // Update interface from execute stage
    input  logic             update_en,
    input  logic [XLEN-1:0] update_pc,
    input  logic [XLEN-1:0] target_pc,
    input  logic             branch_taken,

    // Predicted next PC
    output logic [XLEN-1:0] predicted_pc,

    // BTB status outputs (optional)
    output logic             btb_hit,
    output logic             predict_taken
);

    // Internal BTB outputs
    logic [XLEN-1:0] btb_target;

    // Branch Target Buffer
    branch_target_buffer #(
        .XLEN(XLEN),
        .BTB_ENTRIES(BTB_ENTRIES)
    ) btb_inst (
        .clk           (clk),
        .rst_n         (rst_n),

        // Update interface
        .update_en     (update_en),
        .update_pc     (update_pc),
        .update_target (target_pc),
        .update_taken  (branch_taken),

        // Query interface
        .query_pc      (pc),

        // Outputs
        .hit           (btb_hit),
        .target        (btb_target),
        .taken         (predict_taken)
    );


    // Next PC prediction

    always_comb begin
        if (btb_hit && predict_taken)
            predicted_pc = btb_target;
        else
            predicted_pc = pc + 64'd4;
    end

endmodule

