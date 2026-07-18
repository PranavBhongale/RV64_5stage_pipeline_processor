module branch_target_buffer #(
    parameter int XLEN = 64,
    parameter int BTB_ENTRIES = 16
)(
    input  logic            clk,
    input  logic            rst_n,

    // Update interface
    input  logic            update_en,
    input  logic [XLEN-1:0] update_pc,
    input  logic [XLEN-1:0] update_target,
    input  logic            update_taken,

    // Query interface
    input  logic [XLEN-1:0] query_pc,

    // Outputs
    output logic            hit,
    output logic [XLEN-1:0] target,
    output logic            taken
);

    localparam int INDEX_W = $clog2(BTB_ENTRIES);

    typedef struct packed {
        logic valid;
        logic [XLEN-1:0] pc;
        logic [XLEN-1:0] target;
        logic [1:0] counter;     // 2-bit saturating predictor
    } btb_entry_t;

    btb_entry_t btb_array[BTB_ENTRIES];

    //-------------------------------------------------------------
    // Update logic
    //-------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        integer i;
        logic [INDEX_W-1:0] index;

        if (!rst_n) begin
            for (i = 0; i < BTB_ENTRIES; i++) begin
                btb_array[i].valid   <= 1'b0;
                btb_array[i].pc      <= '0;
                btb_array[i].target  <= '0;
                btb_array[i].counter <= 2'b01;   // weakly not taken
            end
        end
        else if (update_en) begin

            index = update_pc[INDEX_W:1];

            // New entry
            if (!btb_array[index].valid ||
                btb_array[index].pc != update_pc) begin

                btb_array[index].valid  <= 1'b1;
                btb_array[index].pc     <= update_pc;
                btb_array[index].target <= update_target;

                if (update_taken)
                    btb_array[index].counter <= 2'b10;
                else
                    btb_array[index].counter <= 2'b01;
            end

            else begin

                // Preserve previous target if branch not taken
                if (update_taken)
                    btb_array[index].target <= update_target;

                // Saturating counter update
                if (update_taken) begin
                    if (btb_array[index].counter != 2'b11)
                        btb_array[index].counter <=
                            btb_array[index].counter + 1'b1;
                end
                else begin
                    if (btb_array[index].counter != 2'b00)
                        btb_array[index].counter <=
                            btb_array[index].counter - 1'b1;
                end
            end
        end
    end

    //-------------------------------------------------------------
    // Query logic
    //-------------------------------------------------------------
    always_comb begin
        logic [INDEX_W-1:0] index;

        index = query_pc[INDEX_W:1];

        hit    = 1'b0;
        target = '0;
        taken  = 1'b0;

        if (btb_array[index].valid &&
            (btb_array[index].pc == query_pc)) begin

            hit    = 1'b1;
            target = btb_array[index].target;
            taken  = btb_array[index].counter[1];
        end
    end

endmodule
