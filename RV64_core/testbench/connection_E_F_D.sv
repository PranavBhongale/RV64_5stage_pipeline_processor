`timescale 1ns/1ps

module connection_E_F_D;

parameter XLEN = 64;

//====================================================
// Clock & Reset
//====================================================

logic clk;
logic rst_n;

//====================================================
// Writeback Inputs
//====================================================

logic              reg_write_en_in;
logic [XLEN-1:0]   reg_write_data_in;
logic [4:0]        reg_write_addr_in;

//====================================================
// Outputs
//====================================================

logic              write_en;
logic [XLEN-1:0]   write_data;
logic [4:0]        write_reg;
logic              valid_o_reg;

//====================================================
// Memory Interface
//====================================================

logic              req_valid_memory;
logic              memory_ready;
logic [XLEN-1:0]   req_addr_o_memory;
logic [XLEN-1:0]   req_wdata_memory;
decode_pkg::mem_op_e req_memop_out;
logic [4:0]        req_rd_out;

//====================================================
// DUT
//====================================================

connection_E_F_D #(
    .XLEN(XLEN)
)
dut
(
    .clk(clk),
    .rst_n(rst_n),

    .reg_write_en_in(reg_write_en_in),
    .reg_write_data_in(reg_write_data_in),
    .reg_write_addr_in(reg_write_addr_in),

    .write_en(write_en),
    .write_data(write_data),
    .write_reg(write_reg),
    .valid_o_reg(valid_o_reg),

    .req_valid_memory(req_valid_memory),
    .memory_ready(memory_ready),
    .req_addr_o_memory(req_addr_o_memory),
    .req_wdata_memory(req_wdata_memory),
    .req_memop_out(req_memop_out),
    .req_rd_out(req_rd_out)
);

//====================================================
// Clock
//====================================================

initial
    clk = 0;

always #5 clk = ~clk;

//====================================================
// Reset
//====================================================

task automatic reset_dut;

begin

    rst_n = 0;

    reg_write_en_in   = 0;
    reg_write_data_in = 0;
    reg_write_addr_in = 0;

    memory_ready = 0;

    repeat(5) @(posedge clk);

    rst_n = 1;

    $display("-----------------------------------");
    $display("RESET RELEASED");
    $display("-----------------------------------");

end

endtask

//====================================================
// Simulate Writeback
//====================================================

task automatic register_write;

input [4:0] rd;
input [63:0] data;

begin

    @(posedge clk);

    reg_write_en_in   = 1;
    reg_write_addr_in = rd;
    reg_write_data_in = data;

    @(posedge clk);

    reg_write_en_in = 0;

end

endtask

//====================================================
// Memory Ready Pulse
//====================================================

task automatic memory_accept;

begin

    memory_ready = 1;

    repeat(20)
        @(posedge clk);

    memory_ready = 0;

end

endtask

//====================================================
// Waveform
//====================================================

initial
begin

    $dumpfile("waveforms/pipeline.vcd");
    $dumpvars(0,connection_E_F_D_tb);

end

//====================================================
// Simulation
//====================================================

initial
begin

    reset_dut();

    //------------------------------------------------
    // Allow pipeline to fill
    //------------------------------------------------

    repeat(20)
        @(posedge clk);

    //------------------------------------------------
    // Register Write
    //------------------------------------------------

    register_write(5'd5,64'h123456789ABCDEF0);

    repeat(20)
        @(posedge clk);

    //------------------------------------------------
    // Another Register Write
    //------------------------------------------------

    register_write(5'd10,64'hAAAAAAAA55555555);

    repeat(20)
        @(posedge clk);

    //------------------------------------------------
    // Memory Ready
    //------------------------------------------------

    memory_accept();

    repeat(100)
        @(posedge clk);

    $finish();

end

//====================================================
// Monitor
//====================================================

always @(posedge clk)
begin

    $display("------------------------------------------------");

    $display("TIME = %0t",$time);

    $display("WB_EN      = %b",write_en);

    $display("WB_RD      = %d",write_reg);

    $display("WB_DATA    = %h",write_data);

    $display("MEM_VALID  = %b",req_valid_memory);

    $display("MEM_READY  = %b",memory_ready);

    $display("MEM_ADDR   = %h",req_addr_o_memory);

    $display("MEM_DATA   = %h",req_wdata_memory);

    $display("MEM_RD     = %d",req_rd_out);

end

endmodule

