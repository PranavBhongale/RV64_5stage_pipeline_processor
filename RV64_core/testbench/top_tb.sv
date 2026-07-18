`timescale 1ns/1ps

module top_tb;

    parameter int XLEN = 64;
    //---------------------------------------
    // Clock and Reset
    //---------------------------------------
    logic clk;
    logic rst_n;
    //---------------------------------------
    // Clock Generation
    //---------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;      // 100 MHz clock
    end
    //---------------------------------------
    // Reset Generation
    //---------------------------------------
    initial begin
        rst_n = 0;
        #20;
        rst_n = 1;
    end
    //---------------------------------------
    // DUT
    //---------------------------------------
    TOP_MODULE #(
        .XLEN(XLEN)
    ) dut (
        .clk(clk),
        .rst_n(rst_n)
    );
    //---------------------------------------
    // Simulation
    //---------------------------------------
     final begin
    $writememh("memory/rtl_data_memory_result.hex",
               dut.memory_writeback_stage.memory_1.u_memory_connection.u_data_memory.memory);
         end

initial begin 
   // waveform dump
   $dumpfile("top_tb.vcd");
    $dumpvars(1, top_tb);
end
    initial begin


        $display("-------------------------------------------");
        $display("      RV64 Processor Simulation Started");
        $display("-------------------------------------------");
        $dumpfile("top.vcd");
        $dumpvars(0, top_tb);
        #5000;
        $display("-------------------------------------------");
        $display("      Simulation Finished");
        $display("-------------------------------------------");
        $finish;
    end

endmodule
