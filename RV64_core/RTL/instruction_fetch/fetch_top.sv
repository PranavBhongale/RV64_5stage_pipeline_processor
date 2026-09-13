`timescale 1ns/1ps

module fetch_top #(
    parameter int XLEN = 64
)
(
    // Clock and Reset
    input  logic            clk,
    input  logic            rst_n,

    // PC Generator Interface
    input  logic [XLEN-1:0] pc_i,
    input  logic            pc_valid_i,
    output logic            pc_ready_o,

    // Decode Stage Interface
    output logic [XLEN-1:0] pc_o,
    output logic [31:0]     instruction_o,
    output logic            valid_o,
    input  logic            ready_i
);

  logic pc_ready ;
  assign pc_o = pc_i ;
  assign pc_ready_o = pc_ready && !pc_valid_i ;
    // Instruction Memory
    instruction_memory #(
        .XLEN(XLEN)
    ) u_instruction_memory (
        .clk                (clk),
        .rst_n              (rst_n),

        // Request channel
        .req_valid_i        (pc_valid_i),
        .req_ready_o        (pc_ready),
        .req_addr_i         (pc_i),

        // Response channel
        .responce_valid_o   (valid_o),
        .responce_ready_i   (ready_i),
        .responce_data_o    (instruction_o)
    );

endmodule
