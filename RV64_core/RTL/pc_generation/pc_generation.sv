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
    input  logic [XLEN-1:0] pc_from_execution,
    input logic  [XLEN -1 :0 ] pc_from_decode_stage ,
    // Branch resolution from execute stage
    input  logic [XLEN-1:0] pc_target_exe,   // Resolved/correct branch target
    input  logic            branch_taken,     // EX branch/jump was actually taken
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
    logic branch_correct  ;

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
        .branch_taken (branch_correct),

        // Prediction outputs
        .predicted_pc (predicted_pc),
        .btb_hit      (btb_hit),
        .predict_taken(predict_taken_unused)
    );


    always_comb begin
       redirect_pc = 0 ; // default value;
       flush = 0 ;
       branch_correct = 0 ;
       update_enable = 0 ;
        if(branch_taken) begin
           if( pc_from_decode_stage == pc_target_exe )begin
               update_enable = branch_taken;
               branch_correct = 1'b1 ;
           end else begin
               redirect_pc   = pc_target_exe;
               flush         = branch_taken;
               update_enable = branch_taken;
               branch_correct = 1'b0 ;
           end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_pc <= '0;
            pc         <= '0;
            pc_valid   <= 1'b0;
        end else begin
            if (fetch_ready) begin
                pc_valid <= 1'b1;
                pc <= current_pc;
                if (flush) begin
                    current_pc <= redirect_pc;
                    pc <= redirect_pc ;
                end
                else begin
                    current_pc <= predicted_pc;
                    pc <= predicted_pc ;
                end
            end else  begin
             pc_valid <= 1'b0;
            end
            // else: hold pc / current_pc unchanged (implicit)
        end
    end

    // logic [XLEN -1 : 0 ] next_pc ;

    // always_ff @(posedge clk) begin
    //     if(!rst_n)begin
    //         current_pc <= 0 ;
    //     end else current_pc <= next_pc ;
    // end

    // always_comb begin
    //     pc = current_pc ;
    //     pc_valid = 1 ;
    //        if (fetch_ready) begin
    //             if (flush)
    //                 next_pc = redirect_pc;
    //             else
    //                 next_pc = predicted_pc;
    //         end else next_pc = current_pc ;
    // end

endmodule
