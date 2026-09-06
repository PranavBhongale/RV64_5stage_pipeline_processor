`timescale 1ns/1ps
import decode_pkg::*;
import alu_pkg::*;

module execution_pipeline #(
    parameter int XLEN = 64
)(
    // Global
    input  logic clk,
    input  logic rst_n,
    // Decode → Execute

    input  logic                        valid_decode,
    output logic                        ready_execution_unit,

    input  logic [XLEN-1:0]             rs1_data,
    input  logic [XLEN-1:0]             rs2_data,
    input  logic [XLEN-1:0]             pc_in,

    input  decoded_instr_t              decode_instruction,
    input  alu_op_t                     alu_operation,


    // Execute → Fetch
    output logic                        branch_taken,
    output logic [XLEN-1:0]             branch_target,
    output logic [XLEN-1:0]             pc_out,


    // Execute → Memory

    output logic                        valid_to_memory,
    input  logic                        ready_memory,

    output logic [XLEN-1:0]             req_addr_i,
    output logic [XLEN-1:0]             req_wdata_i,
    output mem_op_e                     req_memop_i,
    output logic [4:0]                  req_rd_i,
    output logic                        req_is_load_i,

    // Execute → Writeback
    output logic                        valid_to_writeback,
    input  logic                        ready_writeback,

    output logic [4:0]                  rd,
    output logic [XLEN-1:0]             write_data
);


    // Execute Pipeline Registers


    logic                valid_r;

    logic [XLEN-1:0]     rs1_r;
    logic [XLEN-1:0]     rs2_r;
    logic [XLEN-1:0]     pc_r;

    decoded_instr_t      decode_r;
    alu_op_t             alu_op_r;

    // Pipeline Register


    always_ff @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            valid_r <= 1'b0;
            rs1_r   <= '0;
            rs2_r   <= '0;
            pc_r    <= '0;

            decode_r <= '0;
            alu_op_r <= ALU_ADD;

        end
        else if (ready_execution_unit&&valid_decode) begin

            valid_r <= valid_decode;
            rs1_r   <= rs1_data;
            rs2_r   <= rs2_data;
            pc_r    <= pc_in;

            decode_r <= decode_instruction;
            alu_op_r <= alu_operation;

        end

    end


    // Execution Stage

    execution_top #(
        .XLEN(XLEN)
    ) u_execution (

        // Pipeline Register Outputs

        .valid_decode(valid_r),
        .ready_execution_unit(ready_execution_unit),

        .rs1_data(rs1_r),
        .rs2_data(rs2_r),
        .pc_in(pc_r),

        .decode_instruction(decode_r),
        .alu_operation(alu_op_r),

        // Branch
        .branch_taken(branch_taken),
        .branch_target(branch_target),
        .pc_out(pc_out),

        // Memory

        .valid_to_memory(valid_to_memory),
        .ready_memory(ready_memory),

        .req_addr_i(req_addr_i),
        .req_wdata_i(req_wdata_i),
        .req_memop_i(req_memop_i),
        .req_rd_i(req_rd_i),
        .req_is_load_i(req_is_load_i),

        // Writeback

        .valid_to_writeback(valid_to_writeback),
        .ready_writeback(ready_writeback),

        .rd(rd),
        .write_data(write_data)

    );

endmodule
