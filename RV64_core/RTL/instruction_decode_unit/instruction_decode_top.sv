
module instruction_decode_top #(
    parameter  int XLEN  =  64
) (
    input  logic             clk,
    input  logic             rst_n,

    // From Fetch Stage
    input  logic [XLEN-1:0]  pc_i,
    input  logic [31:0]      instruction_i,
    input  logic             valid_i,
    output logic             ready_o,

     //   input from writeback unit for register file write back
        input logic              reg_write_en_i,
        input logic [XLEN-1:0]  reg_write_data_i,
        input logic [4:0]       reg_write_addr_i,



    // To Execute Stage
     output logic             valid_o,
     input  logic             ready_i,
      output decode_pkg:: decoded_instr_t decoded_instr ,
    //  TO  alu
    output alu_pkg::alu_op_t    alu_op_o,
    output logic [XLEN-1:0]     rs1_data,
    output logic [XLEN-1:0]     rs2_data ,
    output logic [XLEN -1 :0]   pc_out

);

instruction_decode u_instruction_decode (
    .in_valid       (valid_i),
    .in_ready       (ready_o),
    .in_instruction (instruction_i),
    .in_pc          (pc_i),

    .out_valid      (valid_o), //  valid to   execute stage
    .out_ready      (ready_i), //  ready from execute stage
    .out_decoded    (decoded_instr),
    .out_alu_op     (alu_op_o),
    .out_pc         (pc_out)

);




register_file #(
    .XLEN(XLEN)
) u_register_file (
    .clk           (clk),
    .rst_n         (rst_n),
    .reg_write_en  (reg_write_en_i),
    .reg_read_en   (decoded_instr.rs1_used||decoded_instr.rs2_used),
    .rs1_addr      (decoded_instr.rs1),
    .rs2_addr      (decoded_instr.rs2),
    .rd_addr       (reg_write_addr_i),
    .rd_data       (reg_write_data_i),
    .rs1_data      (rs1_data),
    .rs2_data      (rs2_data)
);



endmodule
