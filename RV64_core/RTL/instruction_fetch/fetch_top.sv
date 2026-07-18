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

    // Internal signals between IFU and Instruction Memory

    // Request channel
    logic            imem_req_valid;
    logic            imem_req_ready;
    logic [XLEN-1:0] imem_addr;

    // Response channel
    logic            imem_resp_valid;
    logic            imem_resp_ready;
    logic [31:0]     imem_instruction;

    // Instruction Fetch Unit
    instruction_fetch_unit #(
        .XLEN(XLEN)
    ) u_instruction_fetch_unit (
        .clk                 (clk),
        .rst_n               (rst_n),

        //---------------- PC Generator ----------------
        .pc_i                (pc_i),
        .pc_valid_i          (pc_valid_i),
        .pc_ready_o          (pc_ready_o),

        //---------------- Decode Stage ----------------
        .pc_o                (pc_o),
        .instruction_o       (instruction_o),
        .valid_o             (valid_o),
        .ready_i             (ready_i),

        //---------------- Memory Request --------------
        .imem_req_valid_o    (imem_req_valid),
        .imem_req_ready_i    (imem_req_ready),
        .imem_addr_o         (imem_addr),

        //---------------- Memory Response -------------
        .imem_resp_valid_i   (imem_resp_valid),
        .imem_resp_ready_o   (imem_resp_ready),
        .imem_instruction_i  (imem_instruction)
    );

    // Instruction Memory

    instruction_memory #(
        .XLEN(XLEN)
    ) u_instruction_memory (
        .clk                (clk),
        .rst_n              (rst_n),

        //---------------- Request channel -------------
        .req_valid_i        (imem_req_valid),
        .req_ready_o        (imem_req_ready),
        .req_addr_i         (imem_addr),

        //---------------- Response channel ------------
        .responce_valid_o   (imem_resp_valid),
        .responce_ready_i   (imem_resp_ready),
        .responce_data_o    (imem_instruction)
    );

endmodule

