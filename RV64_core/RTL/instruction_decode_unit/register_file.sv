module register_file #(
    parameter int XLEN = 64
)(
    input  logic            clk,
    input  logic            rst_n,
    input  logic            reg_write_en,
    input  logic            reg_read_en,
    input  logic [4:0]      rs1_addr,
    input  logic [4:0]      rs2_addr,
    input  logic [4:0]      rd_addr,

    input  logic [XLEN-1:0] rd_data,

    output logic [XLEN-1:0] rs1_data,
    output logic [XLEN-1:0] rs2_data
);

    // 32 general-purpose registers
    logic [XLEN-1:0] reg_array [32];

    //--------------------------------------------------------------------------
    // Write Port
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        integer i;

        if (!rst_n) begin
            // Reset all registers to zero
            for (i = 0; i < 32; i++) begin
                reg_array[i] <= '0;
            end
        end
        else begin
            // x0 is hardwired to zero
            reg_array[0] <= '0;

            // Write to destination register
            if (reg_write_en && (rd_addr != 5'd0)) begin
                reg_array[rd_addr] <= rd_data;
            end
        end
    end

    //--------------------------------------------------------------------------
    // Read Port 1 - with same-cycle write-forwarding ("write-first" bypass).
    //
    // FORWARDING LOGIC:
    // The write port above only lands in reg_array on the *next* clock
    // edge. But in this pipeline, the write-back path (both the direct
    // ALU/JAL(R) result and the memory-load result) reaches reg_write_en/
    // rd_addr/rd_data *combinationally*, in the same cycle a dependent
    // instruction is being decoded. Without this bypass, that dependent
    // instruction would read the old, stale value out of reg_array and
    // silently compute the wrong result - a classic RAW (read-after-write)
    // hazard. This mux resolves it by forwarding rd_data directly to the
    // read output whenever the read and write addresses match in the same
    // cycle, instead of waiting a cycle for the array to update.
    //--------------------------------------------------------------------------
    always_comb begin
        if (!reg_read_en)
            rs1_data = '0;
        else if (rs1_addr == 5'd0)
            rs1_data = '0;
        else if (reg_write_en && (rd_addr == rs1_addr))
            rs1_data = rd_data;                 // forwarded value
        else
            rs1_data = reg_array[rs1_addr];
    end

    //--------------------------------------------------------------------------
    // Read Port 2 - identical forwarding logic.
    //--------------------------------------------------------------------------
    always_comb begin
        if (!reg_read_en)
            rs2_data = '0;
        else if (rs2_addr == 5'd0)
            rs2_data = '0;
        else if (reg_write_en && (rd_addr == rs2_addr))
            rs2_data = rd_data;                 // forwarded value
        else
            rs2_data = reg_array[rs2_addr];
    end

endmodule
