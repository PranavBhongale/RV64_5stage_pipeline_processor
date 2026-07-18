`timescale 1ns/1ps
module data_memory #(
    parameter int XLEN          = 64,
    parameter int MEMORY_SIZE   = 4096,
    parameter int MIN_DELAY     = 1,
    parameter int MAX_DELAY     = 5
)(
    input  logic             clk,
    input  logic             rst_n,

    // Request channel
    input  logic             req_valid_i,
    output logic             req_ready_o,

    input  logic             write_en_i,
    input  logic [XLEN-1:0]  addr_i,
    input  logic [63:0]      write_data_i,
    input  data_type_t       data_type_i,

    // Response channel
    output logic             resp_valid_o,
    input  logic             resp_ready_i,
    output logic [63:0]      read_data_o,

    output logic             alignment_error_o
);


    // Memory Array
    logic [7:0] memory [MEMORY_SIZE];

    // Internal Registers
    logic             busy;

    logic             write_en_reg;
    logic [63:0]      addr_reg;
    logic [63:0]      write_data_reg;
    data_type_t       data_type_reg;

    logic [7:0]       write_mask;

    logic [63:0]      raw_data;

    integer           delay_counter;
    integer           current_delay;

    integer i;

    // Ready Signal

    assign req_ready_o = !busy;


    // Alignment Check
initial begin
    $readmemh("memory/rtl_data_memory.hex", memory);
    $display("Loading data memory from memory/rtl_data_memory.hex");
end

    always_comb begin
        alignment_error_o = 1'b0;
       unique  case(data_type_i)
            BYTE:
                alignment_error_o = 1'b0;

            HALFWORD:
                alignment_error_o = addr_i[0];

            WORD:
                alignment_error_o = |addr_i[1:0];

            DWORD:
                alignment_error_o = |addr_i[2:0];

            default:
                alignment_error_o = 1'b0;

        endcase

    end


    // Generate Write Mask
    always_comb begin

        case(data_type_reg)

            BYTE:
                write_mask = 8'b0000_0001;

            HALFWORD:
                write_mask = 8'b0000_0011;

            WORD:
                write_mask = 8'b0000_1111;

            DWORD:
                write_mask = 8'b1111_1111;

            default:
                write_mask = 8'b0;

        endcase

    end

    always_comb begin
        raw_data = {
            memory[12'(addr_reg+7)],
            memory[12'(addr_reg+6)],
            memory[12'(addr_reg+5)],
            memory[12'(addr_reg+4)],
            memory[12'(addr_reg+3)],
            memory[12'(addr_reg+2)],
            memory[12'(addr_reg+1)],
            memory[12'(addr_reg)]
        };
    end
    // Main State Machine
    always_ff @(posedge clk or negedge rst_n)
    begin

        if(!rst_n)
        begin
            busy          <= 1'b0;
            resp_valid_o  <= 1'b0;
            delay_counter <= 0;
        end

        else
        begin
            // Accept request
            if(req_valid_i && req_ready_o)
            begin

                busy           <= 1'b1;

                addr_reg       <= addr_i;
                write_en_reg   <= write_en_i;
                write_data_reg <= write_data_i;
                data_type_reg  <= data_type_i;

                delay_counter  <= 0;

                current_delay  <=
                    $urandom_range(MIN_DELAY, MAX_DELAY);

                resp_valid_o   <= 1'b0;

            end

            // Access in progress
            else if(busy)
            begin

                if(delay_counter == current_delay)
                begin

                    // STORE
                    if(write_en_reg)
                    begin

                        if(!alignment_error_o)
                        begin

                            for(i=0;i<8;i++)
                            begin

                                if(write_mask[i])
                                begin

                                    memory[12'(addr_reg+{64'(i)})]
                                    <= write_data_reg[8*i +: 8];

                                end

                            end

                        end

                        read_data_o <= '0;

                    end

                    // LOAD
                    else
                    begin

                        case(data_type_reg)

                            BYTE:
                                read_data_o <=
                                    {56'b0, raw_data[7:0]};

                            HALFWORD:
                                read_data_o <=
                                    {48'b0, raw_data[15:0]};

                            WORD:
                                read_data_o <=
                                    {32'b0, raw_data[31:0]};

                            DWORD:
                                read_data_o <= raw_data;

                            default:
                                read_data_o <= '0;

                        endcase

                    end

                    resp_valid_o <= 1'b1;

                    // Response consumed
                    if(resp_valid_o && resp_ready_i)
                    begin

                        busy         <= 1'b0;
                        resp_valid_o <= 1'b0;

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
