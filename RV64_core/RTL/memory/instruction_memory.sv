`timescale 1ns/1ps


module instruction_memory #(
    parameter int XLEN = 64,
    parameter int INSTRUCTION_MEMORY_SIZE = 1024,
    parameter int MIN_DELAY = 0,
    parameter int MAX_DELAY = 5
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
    $display("Loading instruction memory from memory/rtl_instruction_memory.hex");
end
logic  R  ;
always_ff @(posedge clk or negedge rst_n)
begin
    if (!rst_n)
    begin
        busy          <= 0;
        responce_valid_o  <= 0;
        delay_counter <= 0;
        req_ready_o   <= 1;
    end

    else
    begin

        // Accept new request

        if (req_valid_i && req_ready_o)
        begin
            busy          <= 1'b1;
            address_reg   <= req_addr_i;
             req_ready_o   <= 1'b0;
            current_delay <=
                $urandom_range(MIN_DELAY, MAX_DELAY);

            delay_counter <= 0;

            responce_valid_o <= 0;
        end


        // Memory busy
        else if (busy)
        begin

            if (delay_counter == current_delay)
            begin

                responce_data_o <=
                    instruction_memory[address_reg[$clog2(INSTRUCTION_MEMORY_SIZE)+1:2]];

                responce_valid_o <= 1'b1;

                // Response consumed
                if (responce_valid_o && responce_ready_i)
                begin
                    busy         <= 0;
                    responce_valid_o <= 1'b0;
                    req_ready_o   <= 1'b1;
                end
            end
            else
            begin
                delay_counter <= delay_counter + 1;
            end
        end
    end
end



endmodule
