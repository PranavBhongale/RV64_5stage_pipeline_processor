`timescale 1ns/1ps


module instruction_fetch_unit #(
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
    input  logic            ready_i,

    // Instruction Memory Request Channel
    output logic            imem_req_valid_o,
    input  logic            imem_req_ready_i,
    output logic [XLEN-1:0] imem_addr_o,

    // Instruction Memory Response Channel
    input  logic            imem_resp_valid_i,
    output logic            imem_resp_ready_o,
    input  logic [31:0]     imem_instruction_i
);

    // IF/ID Pipeline Register
    // (valid_o doubles as this register's own "full" bit)

    // Request side
    assign imem_req_valid_o = pc_valid_i && !valid_o;
    assign imem_addr_o      = pc_i;

    assign imem_resp_ready_o = !valid_o;


    assign pc_ready_o = imem_req_ready_i&&!pc_valid_i;

    // IF/ID Pipeline Register
    always_ff @(posedge clk or negedge rst_n)
    begin
        if(!rst_n)
        begin
            pc_o          <= '0;
            instruction_o <= '0;
            valid_o       <= 1'b0;
        end
        else
        begin
           // Decode stage consumed instruction
            if(valid_o && ready_i)
            begin
                valid_o <= 1'b0;
            end
            // Memory response arrives
            if(imem_resp_ready_o && imem_resp_valid_i)
            begin
                pc_o          <= pc_i;
                instruction_o <= imem_instruction_i;
                valid_o       <= 1'b1;
            end
        end
    end
endmodule
