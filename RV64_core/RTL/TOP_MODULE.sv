`timescale 1ns/1ps

module TOP_MODULE #(
    parameter int XLEN = 64
)(
    input logic clk,
    input logic rst_n
);

    // Internal signals between Execute and Memory stage

    logic                    write_en;
    logic [XLEN-1:0]         write_data;
    logic [4:0]              write_reg;
    logic                    valid_o_reg;

    logic                    req_valid_memory;
    logic                    memory_ready;
    logic [XLEN-1:0]         req_addr_o_memory;
    logic [XLEN-1:0]         req_wdata_memory;
    decode_pkg::mem_op_e     req_memop_out;
    logic [4:0]              req_rd_out;
    logic                    req_is_load_out;

    // Internal signals between Memory and Writeback stage

    logic                    reg_write_en_in;
    logic [XLEN-1:0]         reg_write_data_in;
    logic [4:0]              reg_write_addr_in;

    // Single-write-port back-pressure from MEM/WB stage to EX stage
    logic                    writeback_ready;

    // Load-use hazard feedback from MEM/WB stage to Decode stage
    logic                    load_hazard_valid;
    logic [4:0]              load_hazard_rd;

    // Fetch + Decode + Execute Stage

    connection_E_F_D #(
        .XLEN(XLEN)
    ) execute_stage (

        .clk(clk),
        .rst_n(rst_n),

        // Writeback -> Execute
        .reg_write_en_in(reg_write_en_in),
        .reg_write_data_in(reg_write_data_in),
        .reg_write_addr_in(reg_write_addr_in),

        // Memory/Writeback -> Execute (single write-port arbitration)
        .writeback_ready_i(writeback_ready),

        // Memory/Writeback -> Decode (load-use hazard interlock)
        .load_hazard_valid_i(load_hazard_valid),
        .load_hazard_rd_i(load_hazard_rd),

        // Execute -> Memory
        .write_en(write_en),
        .write_data(write_data),
        .write_reg(write_reg),
        .valid_o_reg(valid_o_reg),

        .req_valid_memory(req_valid_memory),
        .memory_ready(memory_ready),
        .req_addr_o_memory(req_addr_o_memory),
        .req_wdata_memory(req_wdata_memory),
        .req_memop_out(req_memop_out),
        .req_rd_out(req_rd_out),
        .req_is_load_out(req_is_load_out)
    );



    // Memory + Writeback Stage

    connection_M_W #(
        .XLEN(XLEN)
    ) memory_writeback_stage (

        .clk(clk),
        .rst_n(rst_n),

        // Memory -> Execute (Writeback)
        .reg_write_en_in(reg_write_en_in),
        .reg_write_data_in(reg_write_data_in),
        .reg_write_addr_in(reg_write_addr_in),

        // Memory/Writeback -> Execute (single write-port arbitration)
        .writeback_ready_o(writeback_ready),

        // Memory/Writeback -> Decode (load-use hazard interlock)
        .load_hazard_valid_o(load_hazard_valid),
        .load_hazard_rd_o(load_hazard_rd),

        // Execute -> Memory
        .write_en(write_en),
        .write_data(write_data),
        .write_reg(write_reg),
        .valid_o_reg(valid_o_reg),

        .req_valid_memory(req_valid_memory),
        .memory_ready(memory_ready),
        .req_addr_o_memory(req_addr_o_memory),
        .req_wdata_memory(req_wdata_memory),
        .req_memop_out(req_memop_out),
        .req_rd_out(req_rd_out),
        .req_is_load_out(req_is_load_out)
    );

endmodule
