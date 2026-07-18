`timescale 1ns/1ps


module instruction_fetch_unit #(
    parameter int XLEN = 64
)
(
    // Clock and Reset
    input  logic            clk,
    input  logic            rst_n,

    // PC Generator Interface
    input  logic [XLEN-1:0] pc_i,
    input  logic            pc_valid_i,
    output logic            pc_ready_o,

    // Decode Stage Interface
    output logic [XLEN-1:0] pc_o,
    output logic [31:0]     instruction_o,
    output logic            valid_o,
    input  logic            ready_i,

    // Instruction Memory Request Channel
    output logic            imem_req_valid_o,
    input  logic            imem_req_ready_i,
    output logic [XLEN-1:0] imem_addr_o,

    // Instruction Memory Response Channel
    input  logic            imem_resp_valid_i,
    output logic            imem_resp_ready_o,
    input  logic [31:0]     imem_instruction_i
);


    // IF/ID Pipeline Register
    // (valid_o doubles as this register's own "full" bit)

    // Request side
    assign imem_req_valid_o = pc_valid_i && !valid_o;
    assign imem_addr_o      = pc_i;

    // Response side
    // FIX: was `!valid_reg || ready_i`, but `valid_reg` was declared and
    // never driven anywhere (always 0), which made this permanently `1`.
    // Also drop the anticipatory `|| ready_i`: a new response can only
    // ever arrive once a request was actually issued, which itself only
    // happens once this slot is genuinely free (see imem_req_valid_o
    // below) - so by construction a new response never arrives while
    // valid_o is still 1. Keeping the strict form here matches that and
    // avoids the same one-cycle-early-ready mismatch fixed below.
    assign imem_resp_ready_o = !valid_o;


    // Backpressure to PC Generator
    //
    // FIX: this used to be `imem_req_ready_i && (!valid_o || ready_i)`,
    // anticipating that `valid_o` would be freed this very cycle (since
    // ready_i is high) and telling pc_generation it could already move
    // on to the *next* address. But `imem_req_valid_o` below only checks
    // the current (pre-edge) `!valid_o` - it has no such anticipation.
    // So on the cycle a fetched instruction is consumed, pc_generation
    // would race ahead to a new address before the *previous* one was
    // ever actually turned into a memory request - silently dropping
    // that instruction. Require the slot to already be free instead.
    assign pc_ready_o = imem_req_ready_i && !valid_o;

    // IF/ID Pipeline Register
    always_ff @(posedge clk or negedge rst_n)
    begin

        if(!rst_n)
        begin

            pc_o          <= '0;
            instruction_o <= '0;
            valid_o       <= 1'b0;

        end

        else
        begin


            // Decode stage consumed instruction
            if(valid_o && ready_i)
            begin

                valid_o <= 1'b0;

            end


            // Memory response arrives
            if(imem_resp_valid_i && imem_resp_ready_o)
            begin

                pc_o          <= pc_i;
                instruction_o <= imem_instruction_i;
                valid_o       <= 1'b1;

            end

        end

    end

endmodule

