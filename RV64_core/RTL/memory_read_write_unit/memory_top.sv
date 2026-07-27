`timescale 1ns/1ps
import decode_pkg ::*;
module memory_top #(
    parameter int XLEN = 64
)
(
    input  logic             clk,
    input  logic             rst_n,

    // Request channel from Execute Unit
    input  logic             req_valid_i,
    output logic             req_ready_o,
    input  logic [XLEN-1:0]  req_addr_i,
    input  logic [XLEN-1:0]  req_wdata_i,
    input decode_pkg ::  mem_op_e          req_memop_i,
    input  logic [4:0]       req_rd_i, // destination register address for load instructions




    // address to write back unit  for storing load data
    output logic [4:0]       resp_rd_o,

    // Response channel to Writeback Unit
    output logic             responce_valid_o,
    input  logic             responce_ready_i,
    output logic [XLEN-1:0]  responce_rdata_o
);

    //  Decode mem_op_e
    data_type_t dtype;
    logic       isLoad, isStore;
    logic [4:0] rd_addr;

     always_ff@(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_addr <= '0;
        end else if (req_valid_i && req_ready_o) begin
            rd_addr <= req_rd_i; // Capture rd address for load instructions
        end

    end

    always_comb begin
        isLoad  = 0;
        isStore = 0;
        dtype   = WORD; // default

        case (req_memop_i)
            LOAD_BYTE, LOAD_BYTE_U: begin isLoad=1;
                 dtype=BYTE; end
            LOAD_HALF, LOAD_HALF_U: begin isLoad=1;
                 dtype=HALFWORD; end
            LOAD_WORD, LOAD_WORD_U: begin isLoad=1;
                 dtype=WORD; end
            LOAD_DOUBLE:            begin isLoad=1;
                 dtype=DWORD; end

            STORE_BYTE:  begin isStore=1;
                 dtype=BYTE; end
            STORE_HALF:  begin isStore=1;
                 dtype=HALFWORD; end
            STORE_WORD:  begin isStore=1;
                 dtype=WORD; end
            STORE_DOUBLE:begin isStore=1;
                 dtype=DWORD; end
            default: begin
                isLoad  = 0;
                isStore = 0;
                dtype   = WORD; // default
            end
        endcase
    end

    //  Process Write Data
    logic [XLEN-1:0] processed_wdata;
    logic            mem_read_en, mem_write_en;

    always_comb begin
        processed_wdata = '0;
        mem_read_en     = isLoad;
        mem_write_en    = isStore;

        if (isStore) begin
            unique case (dtype)
                BYTE:     processed_wdata = 64'(req_wdata_i[7:0]);
                HALFWORD: processed_wdata = 64'(req_wdata_i[15:0]);
                WORD:     processed_wdata = 64'(req_wdata_i[31:0]);
                DWORD:    processed_wdata = 64'(req_wdata_i[63:0]);
                default:   processed_wdata = req_wdata_i; // default case
            endcase
        end
    end

    // Connect to memory_connection
    memory_connection #(
        .XLEN(XLEN)
    ) u_memory_connection (
        .clk                  (clk),
        .rst_n                (rst_n),

        // Handshake from Execute Unit
        .exec_valid_i         (req_valid_i),
        .exec_ready_o         (req_ready_o),

        // Memory access signals
        .mem_write_en_i       (mem_write_en),
        .mem_addr_i           (req_addr_i),
        .mem_write_data_i     (processed_wdata),
        .mem_data_type_i      (dtype),

        // Handshake to Writeback Unit
        .mem_data_valid_o     (responce_valid_o),
        .write_back_unit_ready(responce_ready_i),

        // Read data
        .mem_read_data_o      (responce_rdata_o)
    );
/* verilator lint_off LATCH */
  always_comb begin
  if(responce_valid_o&&responce_ready_i) begin
        resp_rd_o = rd_addr; // Update rd address when response is valid
    end
    end
/* verilator lint_on LATCH */

endmodule
