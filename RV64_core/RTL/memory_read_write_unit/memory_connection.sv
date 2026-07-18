


import decode_pkg ::*;

module memory_connection #(
    parameter int XLEN = 64
)(
    input  logic             clk,
    input  logic             rst_n,

    // Handshake from Execute Unit
    input  logic             exec_valid_i,
    output logic             exec_ready_o,

    // Memory access signals
    input  logic             mem_write_en_i,
    input  logic [XLEN-1:0]  mem_addr_i,
    input  logic [XLEN-1:0]  mem_write_data_i,
    input  data_type_t       mem_data_type_i,

    // Handshake to Writeback Unit
    output logic             mem_data_valid_o,
    input  logic             write_back_unit_ready,

    // Read data
    output logic [XLEN-1:0]  mem_read_data_o
);

logic alignment_error;

data_memory #(
    .XLEN(XLEN)
) u_data_memory (
    .clk               (clk),
    .rst_n             (rst_n),

    // Request channel
    .req_valid_i       (exec_valid_i),
    .req_ready_o       (exec_ready_o),

    .write_en_i        (mem_write_en_i),
    .addr_i            (mem_addr_i),
    .write_data_i      (mem_write_data_i),
    .data_type_i       (mem_data_type_i),

    // Response channel
    .resp_valid_o      (mem_data_valid_o),
    .resp_ready_i      (write_back_unit_ready),
    .read_data_o       (mem_read_data_o),

    // Error signal
    .alignment_error_o (alignment_error)
);

endmodule
