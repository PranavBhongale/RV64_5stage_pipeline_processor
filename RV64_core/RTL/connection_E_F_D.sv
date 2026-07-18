`timescale 1ns/1ps
module  connection_E_F_D #(
    parameter int XLEN = 64
) (
    input logic clk ,
    input logic rst_n,

    //  input from write back stage
    input logic reg_write_en_in ,
    input logic [XLEN -1 : 0 ] reg_write_data_in ,
    input logic [4:0] reg_write_addr_in,

    // Back-pressure from MEM/WB: the register file has a single write
    // port, so when a memory-load result is landing this cycle the
    // direct ALU/JAL(R) writeback path must stall one cycle.
    input logic writeback_ready_i,

    // Load-use hazard feedback from MEM/WB: a load is currently in
    // flight (its result hasn't landed yet). Decode must stall any
    // instruction that needs this destination register.
    input logic       load_hazard_valid_i,
    input logic [4:0] load_hazard_rd_i,

    //  output to load and store and writeback stage

     // handsheck to write back stage
     output logic write_en ,
     output logic [XLEN -1 : 0 ] write_data ,
     output logic [4:0] write_reg ,
     output logic valid_o_reg,
     //  to write load_store_unit ;

    output   logic              req_valid_memory,
    input  logic                memory_ready ,
    output  logic [XLEN-1:0]    req_addr_o_memory,
    output logic [XLEN-1:0]     req_wdata_memory,
    output  decode_pkg ::       mem_op_e    req_memop_out,
    output   logic [4:0]       req_rd_out,
    output   logic              req_is_load_out
);

//  connection of PC_generation logic
logic fetch_ready ;
logic pc_valid ;
logic  [XLEN -1 :0 ]pc_to_fetch ;
logic  [XLEN -1 :0 ] pc_target_from_execution ;
logic [XLEN-1:0] pc_for_pc_generation;
logic branch_take;
logic flush ;

 pc_generation  #(
     .XLEN(XLEN)
) u_pc_generation (
    //  clack and input logic
    .clk(clk) ,
    .rst_n(rst_n) ,
   //  hand sheak   from fetch unit
    .fetch_ready(fetch_ready) ,
    .pc_valid(pc_valid) ,
    //  signal to fetch logic  ;
    .pc(pc_to_fetch),
     //  input correct pc from execution logic  from branch and calls
    .pc_target_exe(pc_target_from_execution),
    .branch_taken(branch_take),
        // Correction input from execute stage (BTB update key)
     .pc_from_execution(pc_for_pc_generation),
    .flush(flush)
);

//  connection to fetch stage
logic [XLEN -1 :0 ]  pc_out_fetch;
logic [31:0] instruction_fetch ;
logic fetch_valid ;
logic decoder_ready ;

fetch_top #(
   .XLEN(XLEN)
) fetch_unit (
        .clk(clk),
        .rst_n(rst_n),
    // PC Generator Interface
        .pc_i(pc_to_fetch),
        .pc_valid_i(pc_valid),
        .pc_ready_o(fetch_ready),

    // Decode Stage Interface
        .pc_o(pc_out_fetch),
        .instruction_o(instruction_fetch),
        .valid_o(fetch_valid),
        .ready_i(decoder_ready)
);

// connection to decode stage
decode_pkg:: decoded_instr_t decoded_instr_wire  ;
alu_pkg:: alu_op_t          alu_op_connection ;
logic decoder_valid ;
logic ready_execution ;
logic [XLEN -1 :0 ] rs1_connection ;
logic [XLEN -1 :0 ] rs2_connection ;
logic [XLEN -1 :0 ] pc_connection ;

decoding_pipeline # (
   .XLEN(XLEN)
) instruction_decode(
        .clk(clk),
        .rst_n(rst_n),

    // From Fetch Stage
       .pc_i(pc_out_fetch),
       .instruction_i(instruction_fetch),
       .valid_i(fetch_valid),
       .ready_o(decoder_ready),

     //   input from writeback unit for register file write back
       .reg_write_en_i(reg_write_en_in),
       .reg_write_data_i(reg_write_data_in),
       .reg_write_addr_i(reg_write_addr_in),

     //   load-use hazard interlock
       .load_hazard_valid_i(load_hazard_valid_i),
       .load_hazard_rd_i(load_hazard_rd_i),

    // To Execute Stage
    .valid_o(decoder_valid),
    .ready_i(ready_execution),
    .decoded_instr(decoded_instr_wire),
    //  TO  alu
     .alu_op_o(alu_op_connection),
     .rs1_data(rs1_connection),
     .rs2_data(rs2_connection),
     .pc_out(pc_connection),
     // flush the pipeline when branch misprediction occurs
     .flush(flush)
);

// connection to execute stage

 execution_top #(
    .XLEN(XLEN)
) execution_top_M(
    // ---- Global ----
   .clk(clk),
   .rst_n(rst_n),
    // ---- Handshake from Decode stage ----
   .valid_decode(decoder_valid),
   .ready_execution_unit(ready_execution),
    // ---- Operands forwarded from Decode / Register-File stage
   .rs1_data(rs1_connection),
    .rs2_data(rs2_connection),
    // ---- Current PC (AUIPC, branch target, return address) ----
    .pc_in(pc_connection),

    // ---- Decoded instruction bundle + ALU opcode ----
    .decode_instruction(decoded_instr_wire),
    .alu_operation(alu_op_connection),

    // ---- Branch resolution -> Fetch / Branch Control Unit ----
    .branch_taken(branch_take),
    .branch_target(pc_target_from_execution),
    .pc_out(pc_for_pc_generation),
    // ---- Handshake to Memory stage (loads & stores) ----
     .valid_to_memory(req_valid_memory),
     .ready_memory(memory_ready),
     .req_addr_i(req_addr_o_memory),     // effective address (rs1 + imm)
     .req_wdata_i(req_wdata_memory),    // store write data (rs2)
     .req_memop_i(req_memop_out),
     .req_rd_i(req_rd_out),       // rd addr for load->WB path
     .req_is_load_i(req_is_load_out),

    // ---- Handshake to Write-Back stage ----
           .valid_to_writeback(valid_o_reg),
           .ready_writeback(writeback_ready_i),
           .rd(write_reg),
           .write_data(write_data)      // ALU result or PC+4 (JAL/JALR)
);

// write_en simply mirrors "this cycle carries a valid direct
// ALU / JAL(R) result destined for the register file".
// (Previously this output was left undriven - it was wired to the
//  ready_writeback *input* of execution_top instead of being assigned
//  from a real source.)
assign write_en = valid_o_reg;

endmodule
