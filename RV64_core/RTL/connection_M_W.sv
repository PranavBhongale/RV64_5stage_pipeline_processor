`timescale 1ns/1ps

module connection_M_W #(
   parameter int XLEN = 64
) (
    // clock signal
    input logic clk ,
    input logic rst_n ,
//    connection to execute stage
//  to write back stage

    output logic reg_write_en_in ,
    output logic [XLEN-1 : 0 ] reg_write_data_in,
    output logic [4:0] reg_write_addr_in,          // FIX: was 1-bit -> truncated rd to a single bit

    // Back-pressure to the EX stage: tells it whether the single
    // register-file write port is free this cycle for a direct
    // ALU / JAL(R) result (busy whenever a load response is landing).
    output logic writeback_ready_o,

    // Load-use hazard feedback to Decode: a load is currently in
    // flight and its destination register isn't valid yet.
    output logic       load_hazard_valid_o,
    output logic [4:0] load_hazard_rd_o,

// input from execute stage
//    write back information

    input logic write_en,
    input logic [XLEN-1 :0 ] write_data,
    input logic [4:0] write_reg,
    input logic valid_o_reg,

//  input to load store unit from execute stage

    input logic req_valid_memory,
    output logic memory_ready ,
    input logic [XLEN-1 :0 ] req_addr_o_memory,
    input  logic [XLEN-1:0]     req_wdata_memory,
    input   decode_pkg ::       mem_op_e    req_memop_out,
    input   logic [4:0]       req_rd_out,
    input   logic              req_is_load_out

);

logic [4:0]      resp_rd;
logic            response_valid;
logic            response_ready;
logic [XLEN-1:0] response_rdata;

memory_top #(
    .XLEN(XLEN)
) memory_1 (
    .clk(clk),
    .rst_n(rst_n),
    // Request from Execute stage
    .req_valid_i(req_valid_memory),
    .req_ready_o(memory_ready),
    .req_addr_i(req_addr_o_memory),
    .req_wdata_i(req_wdata_memory),
    .req_memop_i(req_memop_out),
    .req_rd_i(req_rd_out),

    // Response to Writeback
    .resp_rd_o(resp_rd),
    .responce_valid_o(response_valid),
    .responce_ready_i(response_ready),
    .responce_rdata_o(response_rdata)
);

// Always ready to accept memory response
assign response_ready = 1'b1;

// ---------------------------------------------------------------------
// Load-use hazard tracker.
//
// The memory unit only supports one outstanding request at a time (it
// simply de-asserts req_ready_o/asserts `busy` until the response is
// consumed), so there is at most one in-flight load whose destination
// register isn't valid yet. Decode must stall any instruction that
// needs that register until the response lands - forwarding alone
// can't help here since the value doesn't exist yet.
// ---------------------------------------------------------------------
logic       pending_load_valid;
logic [4:0] pending_load_rd;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pending_load_valid <= 1'b0;
        pending_load_rd    <= '0;
    end else begin
        if (req_valid_memory && memory_ready && req_is_load_out) begin
            pending_load_valid <= 1'b1;
            pending_load_rd    <= req_rd_out;
        end else if (response_valid) begin
            pending_load_valid <= 1'b0;
        end
    end
end

assign load_hazard_valid_o = pending_load_valid;
assign load_hazard_rd_o    = pending_load_rd;

// ---------------------------------------------------------------------
// Direct ALU / JAL(R) -> WB path (non-memory instructions).
// This was previously completely missing: write_en/write_data/write_reg/
// valid_o_reg came in from the Execute stage but were never connected to
// anything, so no non-memory instruction (ADD, ADDI, AND, JAL, ...) ever
// wrote its result back to the register file - only load results did.
// ---------------------------------------------------------------------
logic            alu_wb_en;
logic [XLEN-1:0] alu_wb_data;
logic [4:0]      alu_wb_addr;

writeback_unit #(
    .XLEN(XLEN)
) u_writeback_unit (
    .write_en   (write_en),
    .write_data (write_data),
    .write_reg  (write_reg),
    .valid_i    (valid_o_reg),
    .reg_write_en_o  (alu_wb_en),
    .reg_write_data_o(alu_wb_data),
    .reg_write_addr_o(alu_wb_addr)
);

// ---------------------------------------------------------------------
// Single write-port arbitration.
// A memory-load response and a direct ALU writeback can be valid in the
// same cycle (they belong to two different in-flight instructions, and
// the memory unit has variable latency). The load response is the
// older instruction in program order and is given priority; the direct
// ALU path is stalled for a cycle via writeback_ready_o, which feeds
// execution_top's existing ready_writeback handshake.
// ---------------------------------------------------------------------
assign writeback_ready_o = ~response_valid;

assign reg_write_en_in   = response_valid ? 1'b1           : (alu_wb_en & valid_o_reg);
assign reg_write_data_in = response_valid ? response_rdata : alu_wb_data;
assign reg_write_addr_in = response_valid ? resp_rd        : alu_wb_addr;

endmodule
