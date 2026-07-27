module decoding_pipeline#(
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

     //   load-use hazard interlock: a load is in flight and its
     //   destination register isn't valid yet
    input logic              load_hazard_valid_i,
    input logic [4:0]        load_hazard_rd_i,

    // To Execute Stage
     output logic             valid_o,
     input  logic             ready_i,
     output decode_pkg:: decoded_instr_t decoded_instr ,
    //  TO  alu
    output alu_pkg::alu_op_t    alu_op_o,
    output logic [XLEN-1:0]     rs1_data,
    output logic [XLEN-1:0]     rs2_data ,
    output logic [XLEN -1 :0]   pc_out,
   //  flush the pipeline when branch misprediction occurs
    input logic flush
);

     decode_pkg:: decoded_instr_t decoded_instr_reg ;
     alu_pkg :: alu_op_t          alu_op_reg ;
     logic valid_reg ;
     logic [XLEN -1 :0 ] rs1_reg ;
     logic [XLEN-1 :0 ] rs2_reg ;
     logic [XLEN-1 :0 ] pc_reg ;
     logic              inner_ready_o_unused;

instruction_decode_top#(
     .XLEN(XLEN)
) instruction_decode (
        .clk(clk),
        .rst_n(rst_n),

    // From Fetch Stage
     .pc_i(pc_i),
     .instruction_i(instruction_i),
     .valid_i(valid_i),
     .ready_o(inner_ready_o_unused),

     //   input from writeback unit for register file write back
     .reg_write_en_i(reg_write_en_i),
     .reg_write_data_i(reg_write_data_i),
     .reg_write_addr_i(reg_write_addr_i),


    // To Execute Stage
     .valid_o(valid_reg),
     .ready_i(ready_i),
     .decoded_instr(decoded_instr_reg),
    //  TO  alu
     .alu_op_o(alu_op_reg),
     .rs1_data(rs1_reg),
     .rs2_data(rs2_reg),
     .pc_out(pc_reg)

);

logic load_use_hazard;
assign load_use_hazard = load_hazard_valid_i && (load_hazard_rd_i != 5'd0) &&
                      ( (decoded_instr_reg.rs1_used && decoded_instr_reg.rs1 == load_hazard_rd_i) ||
                      (decoded_instr_reg.rs2_used && decoded_instr_reg.rs2 == load_hazard_rd_i) );

assign ready_o = ready_i && !load_use_hazard;

//  this is the ID/EX pipeline register
always_ff @(posedge clk or negedge rst_n) begin

    if(!rst_n||flush) begin
      decoded_instr <= '0;
      valid_o <= '0 ;
      alu_op_o <= alu_pkg::ALU_ADD;
      rs1_data <= '0;
      rs2_data <= '0;
      pc_out <= '0;
    end else if (load_use_hazard) begin
      valid_o <= 1'b0;
    end else begin
      decoded_instr <= decoded_instr_reg;
      valid_o <= valid_reg;
      alu_op_o <= alu_op_reg;
      rs1_data <= rs1_reg;
      rs2_data <= rs2_reg;
      pc_out <= pc_reg ;
    end
end
endmodule
