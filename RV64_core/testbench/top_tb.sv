`timescale 1ns/1ps

module top_tb;

    parameter int XLEN = 64;
    // Clock and Reset
    logic clk;
    logic rst_n;
    // Clock Generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;      // 100 MHz clock
    end
    // Reset Generation
    initial begin
        rst_n = 0;
        #14;
        rst_n = 1;
    end
    // DUT
    TOP_MODULE #(
        .XLEN(XLEN)
    ) dut (
        .clk(clk),
        .rst_n(rst_n)
    );
    // Simulation
     final begin
    integer fd;
    integer i;
    logic [63:0] doubleword;

    fd = $fopen("memory/rtl_data_memory_result.hex", "w");

    for (i = 0; i < 2000; i = i + 8) begin

        doubleword = {
            dut.memory_writeback_stage.memory_1.u_memory_connection.u_data_memory.memory[i+7],
            dut.memory_writeback_stage.memory_1.u_memory_connection.u_data_memory.memory[i+6],
            dut.memory_writeback_stage.memory_1.u_memory_connection.u_data_memory.memory[i+5],
            dut.memory_writeback_stage.memory_1.u_memory_connection.u_data_memory.memory[i+4],
            dut.memory_writeback_stage.memory_1.u_memory_connection.u_data_memory.memory[i+3],
            dut.memory_writeback_stage.memory_1.u_memory_connection.u_data_memory.memory[i+2],
            dut.memory_writeback_stage.memory_1.u_memory_connection.u_data_memory.memory[i+1],
            dut.memory_writeback_stage.memory_1.u_memory_connection.u_data_memory.memory[i]
        };

        $fwrite(fd, "%016h\n", doubleword);
    end

    $fclose(fd);
end

initial begin 
   // waveform dump
   $dumpfile("top_tb.fst");
    $dumpvars(1, top_tb);
end
    initial begin


        $display("-------------------------------------------");
        $display("      RV64 Processor Simulation Started");
        $display("-------------------------------------------");
        $dumpfile("top.fst");
        $dumpvars(0, top_tb);
        #1000;
        $display("-------------------------------------------");
        $display("      Simulation Finished");
        $display("-------------------------------------------");
        $finish;
    end

endmodule
