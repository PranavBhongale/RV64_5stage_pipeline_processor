module writeback_unit #(
    parameter int XLEN = 64
) (
    input  logic            write_en,
    input  logic [XLEN-1:0] write_data,
    input  logic [4:0]      write_reg,
    input logic             valid_i ,


    //  output  to  register file 

    output logic           reg_write_en_o,
    output logic [XLEN-1:0] reg_write_data_o,
    output logic [4:0]     reg_write_addr_o

);




assign reg_write_en_o   = write_en & valid_i;
assign reg_write_data_o = write_data;
assign reg_write_addr_o = write_reg;

endmodule

