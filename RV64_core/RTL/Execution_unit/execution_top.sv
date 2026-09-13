`timescale 1ns/1ps
import decode_pkg::*;
import alu_pkg::*;

module execution_top #(
    parameter int XLEN = 64
)(

    // Handshake from Decode stage
    input  logic                          valid_decode,
    output logic                          ready_execution_unit,

    //  Operands forwarded from Decode / Register-File stage
    input  logic [XLEN-1:0]              rs1_data,
    input  logic [XLEN-1:0]              rs2_data,

    //  Current PC (AUIPC, branch target, return address)
    input  logic [XLEN-1:0]              pc_in,

    //  Decoded instruction bundle + ALU opcode
    input  decode_pkg::decoded_instr_t   decode_instruction,
    input  alu_pkg::alu_op_t             alu_operation,

    //  Branch resolution → Fetch / Branch Control Unit
    output logic                          branch_taken,
    output logic [XLEN-1:0]              branch_target,
    output logic [XLEN -1 :0 ]           pc_out ,

    //  Handshake to Memory stage (loads & stores)
    output logic                          valid_to_memory,
    input  logic                          ready_memory,
    output logic [XLEN-1:0]              req_addr_i,     // effective address (rs1 + imm)
    output logic [XLEN-1:0]              req_wdata_i,    // store write data (rs2)
    output decode_pkg::mem_op_e          req_memop_i,
    output logic [4:0]                   req_rd_i,       // rd addr for load→WB path
    output logic                          req_is_load_i,  // 1 = this request is a load (for load-use hazard detection)

    //Handshake to Write-Back stage
    output logic                          valid_to_writeback,
    input  logic                          ready_writeback,
    output logic [4:0]                    rd,
    output logic [XLEN-1:0]              write_data      // ALU result or PC+4 (JAL/JALR)
);

    assign  pc_out = pc_in ;
    //  ALU operand selection

    logic [XLEN-1:0] alu_operand_a;
    logic [XLEN-1:0] alu_operand_b;
    logic [XLEN-1:0] alu_result;
    logic             alu_zero;
    logic             alu_negative;

    // Operand A:
    //   AUIPC    → PC
    //   LUI      → 0  (ALU_LUI_PASS just forwards operand_b = imm)
    //   default  → rs1
    always_comb begin
        unique case (alu_operation)
            alu_pkg::ALU_AUIPC    : alu_operand_a = pc_in;
            alu_pkg::ALU_LUI_PASS : alu_operand_a = '0;
            default               : alu_operand_a = rs1_data;
        endcase
    end

    // Operand B:
    //   imm_used → immediate (sign-extended by decoder)
    //   else     → rs2
    always_comb begin
        if (decode_instruction.imm_used)
            alu_operand_b = XLEN'(decode_instruction.imm);
        else
            alu_operand_b = rs2_data;
    end

    alu_module #(
        .XLEN (XLEN)
    ) u_alu (
        .operand_a     (alu_operand_a),
        .operand_b     (alu_operand_b),
        .alu_op        (alu_operation),
        .result        (alu_result),
        .zero_flag     (alu_zero),
        .negative_flag (alu_negative)
    );

    //  Branch condition evaluation
    //  Comparison is performed on raw rs1/rs2 (not ALU result) — per RV spec.
    logic branch_condition_met;

    always_comb begin
        unique case (decode_instruction.branch_op)
            decode_pkg::BR_BEQ  : branch_condition_met = (rs1_data == rs2_data);
            decode_pkg::BR_BNE  : branch_condition_met = (rs1_data != rs2_data);
            decode_pkg::BR_BLT  : branch_condition_met = ($signed(rs1_data) <  $signed(rs2_data));
            decode_pkg::BR_BGE  : branch_condition_met = ($signed(rs1_data) >= $signed(rs2_data));
            decode_pkg::BR_BLTU : branch_condition_met = (rs1_data <  rs2_data);
            decode_pkg::BR_BGEU : branch_condition_met = (rs1_data >= rs2_data);
            default             : branch_condition_met = 1'b0;
        endcase
    end

    //  Branch / Jump target
    //  JAL   (J_TYPE) : PC + imm
    //  JALR  (I_TYPE) : (rs1 + imm) & ~64'h1   ← LSB cleared per spec
    //  B-type         : PC + imm
    always_comb begin
        branch_taken  = 1'b0;
        branch_target = '0;

        if (decode_instruction.jump) begin
            branch_taken = 1'b1;
            if (decode_instruction.instr_type == decode_pkg::J_TYPE)
                branch_target = pc_in + XLEN'(decode_instruction.imm);
            else  // JALR
                branch_target = (rs1_data + XLEN'(decode_instruction.imm))
                                & {{(XLEN-1){1'b1}}, 1'b0};
        end else if (decode_instruction.branch & branch_condition_met) begin
            branch_taken  = 1'b1;
            branch_target = pc_in + XLEN'(decode_instruction.imm);
        end
    end

    //  Effective address  (rs1 + sign-extended imm)  — loads, stores, JALR
    logic [XLEN-1:0] effective_addr;
    assign effective_addr = rs1_data + XLEN'(decode_instruction.imm);


    //  Downstream routing flags
    //
    //  to_mem : any load or store
    //  to_wb  : instructions that write rd, excluding pure stores and syscalls
    //           (loads write rd via memory stage → WB path, so to_wb is false)
    logic to_mem, to_wb;

    assign to_mem = decode_instruction.mem_read | decode_instruction.mem_write;
    assign to_wb  = decode_instruction.rd_used
                  & ~decode_instruction.mem_write   // stores don't write rd
                  & ~decode_instruction.mem_read    // loads: WB via mem stage
                  & ~decode_instruction.sys_call;

    //  Ready / valid handshake
    //
    //  We only accept a new instruction when every targeted downstream stage
    //  is ready.  This keeps backpressure correct without output registers.
    logic downstream_ready;
    assign downstream_ready = (~to_mem | ready_memory)
                            & (~to_wb  | ready_writeback);

    assign ready_execution_unit = downstream_ready;

    assign valid_to_memory    = valid_decode & to_mem & ready_memory;
    assign valid_to_writeback = valid_decode & to_wb  & ready_writeback;

    //  Memory stage outputs
    assign req_addr_i  = effective_addr;
    assign req_wdata_i = rs2_data;
    assign req_memop_i = decode_instruction.mem_op;
    assign req_rd_i    = decode_instruction.rd;
    assign req_is_load_i = decode_instruction.mem_read;

    //  Write-Back stage outputs
    //
    //  JAL / JALR → return address (PC + 4)
    //  All others → ALU result
    assign rd = decode_instruction.rd;

    always_comb begin
        if (decode_instruction.jump)
            write_data = pc_in + XLEN'(4);
        else
            write_data = alu_result;
    end

endmodule
