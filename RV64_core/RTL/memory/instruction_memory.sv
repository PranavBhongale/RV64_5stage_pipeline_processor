`timescale 1ns/1ps


module instruction_memory #(
    parameter int XLEN = 64,
    parameter int INSTRUCTION_MEMORY_SIZE = 1024,
    parameter int MIN_DELAY = 0,
    parameter int MAX_DELAY = 0
)(
    input  logic             clk,
    input  logic             rst_n,

    // Request channel
    input  logic             req_valid_i,
    output logic             req_ready_o,
    input  logic [XLEN-1:0]  req_addr_i,

    // Response channel
    output logic             responce_valid_o,
    input  logic             responce_ready_i,
    output logic [31:0]      responce_data_o
);

logic [31:0] instruction_memory [INSTRUCTION_MEMORY_SIZE];

logic busy;

logic [XLEN-1:0] address_reg;

int unsigned delay_counter;
int unsigned current_delay;

initial begin
    $readmemh(
        "memory/golden_instruction_memory.hex",
        instruction_memory
    );
    $display("Loading instruction memory from memory/golden_instruction_memory.hex");
end


    always_comb begin
        req_ready_o = !busy && !responce_valid_o ;
    end

always_ff @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            busy              <= 1'b0;
            address_reg      <= '0;

            delay_counter    <= 0;
            current_delay    <= 0;

            responce_valid_o <= 1'b0;
            responce_data_o  <= 32'b0;

        end
        else begin

            if (req_valid_i && req_ready_o) begin

                address_reg <= req_addr_i;

                busy <= 1'b1;

                // Select delay
                if (MAX_DELAY > MIN_DELAY) begin
                    current_delay <= MIN_DELAY +
                                     $urandom_range(
                                         MAX_DELAY - MIN_DELAY
                                     );
                end
                else begin
                    current_delay <= MIN_DELAY;
                end

                delay_counter <= 0;
            end

            if (busy && !responce_valid_o) begin

                if (delay_counter >= current_delay) begin

                    if (32'(address_reg >> 2) < INSTRUCTION_MEMORY_SIZE) begin

                        responce_data_o <=
                            instruction_memory[address_reg[11:2]];

                    end
                    else begin

                        responce_data_o <= 32'h00000013; // RISC-V NOP
                    end
                    responce_valid_o <= 1'b1;
                end
                else begin
                    delay_counter <= delay_counter + 1;
                end
            end

            // Response handshake
            if (responce_valid_o && responce_ready_i) begin

                responce_valid_o <= 1'b0;
                busy             <= 1'b0;

            end
        end
    end

endmodule

