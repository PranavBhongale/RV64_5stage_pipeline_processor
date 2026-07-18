
`timescale 1ns/1ps

module alu_module #(
    parameter int XLEN = 64
)(
    input  logic [XLEN-1:0] operand_a,
    input  logic [XLEN-1:0] operand_b,
    input  alu_pkg::alu_op_t  alu_op,

    output logic [XLEN-1:0] result,
    output logic            zero_flag,
    output logic            negative_flag
);

    import alu_pkg::*;

    logic signed [XLEN-1:0] a_signed, b_signed;

    assign a_signed = operand_a;
    assign b_signed = operand_b;



    // FIX: was `always_latch`. The case statement below (with a default
    // arm) already covers every alu_op value, so this is a fully
    // combinational block - it must not synthesize as a latch, or the
    // ALU result (and therefore every downstream forwarded value) can
    // glitch/hold stale data instead of tracking operand_a/operand_b
    // immediately.

    logic signed [31:0] result_1;
    logic signed [31:0] result_2;
    logic signed [31:0] result_3;
    logic signed [31:0] result_4;
    logic signed [31:0] result_5;
    logic [127:0]result_7;
    logic [127:0]result_8;
    logic [127:0]result_9;
    logic   [127:0]result_10;
    logic [63:0] result_11 ;
    logic [127:0 ]a_ext;
    logic [127:0] b_ext ;
    logic signed [63:0] dividend_1 , divisor_1 , quetiont_1 ;
    logic signed [31:0] dividend_2 , divisor_2 , quetiont_2 ;
    logic  [31:0]devide_3;

    always_comb begin
        result = '0;
        result_1 = '0;
        result_2 = '0;
        result_3 = '0;
        result_4 = '0;
        result_5 = '0;
        result_7 = '0;
        result_8 = '0;
        result_9 = '0;
        result_10 = '0;
        result_11 = '0;
        a_ext  = '0;
        b_ext  = '0;
        dividend_1 = '0;
        divisor_1 = '0;
        quetiont_1 = '0;
        dividend_2 = '0;
        divisor_2 = '0;
        quetiont_2 = '0;
        devide_3 = '0;
        case (alu_op)

            ALU_ADD : result = operand_a + operand_b;

            ALU_SUB : result = operand_a - operand_b;

            ALU_AND : result = operand_a & operand_b;

            ALU_OR  : result = operand_a | operand_b;

            ALU_XOR : result = operand_a ^ operand_b;

            ALU_SLL : result = operand_a << operand_b[5:0];

            ALU_SRL : result = operand_a >> operand_b[5:0];

            ALU_SRA : result = a_signed >>> operand_b[5:0];

            ALU_SLT : result = 64'(a_signed < b_signed);

            ALU_SLTU: result = 64'(operand_a < operand_b);

            ALU_ADDW: begin
                 result_1  = operand_a[31:0]+operand_b[31:0] ;
                 result = {{32{(result_1[31])}},
                           (operand_a[31:0]+operand_b[31:0])};
            end

            ALU_SUBW: begin
                result_2 =  operand_a[31:0]-operand_b[31:0] ;
                     result = {{32{(result_2[31])}},
                           (operand_a[31:0]-operand_b[31:0])};

            end

            ALU_SLLW: begin
                      result_3 = operand_a[31:0] << operand_b[31:0] ;
                     result = {{32{(result_3[31])}},
                           (operand_a[31:0] << operand_b[4:0])};
            end


            ALU_SRLW: begin
                     result_4  = operand_a[31:0] >> operand_b[31:0] ;
                    result = {{32{(result_4[31])}},
                           (operand_a[31:0] >> operand_b[4:0])};

            end

            ALU_SRAW: begin
               result_5 = $signed(operand_a[31:0]) >>> operand_b[4:0];
                result = {{32{(result_5[31])}},
                           ($signed(operand_a[31:0]) >>> operand_b[4:0])};
            end

            ALU_LUI_PASS :
                result = operand_b;

            ALU_AUIPC :
                result = operand_a + operand_b;

            ALU_MUL :  begin
                result_7 = a_signed * b_signed;
                result = result_7[63:0];  // Example: take lower 64 bits
            end
             ALU_MULH :  begin
                result_8 = a_signed * b_signed;
                result = result_8[127:64] ;
            end

              ALU_MULHU :  begin
                result_9 = operand_a * operand_b;
                result = result_9[127:64];  // Example: take lower 64 bits
            end

             ALU_MULHSU :  begin
                a_ext = {{64{operand_a[63]}} , operand_a};
                 b_ext = {64'b0 , operand_b} ;
                result_10 =  $signed(a_ext * b_ext);
                result = result_10[127:64] ;
            end

            ALU_MULW : begin
              result_11 = ((a_signed * b_signed)) ;
              result = {{ 32{result_11[31]} }, result_11[31:0]} ;

            end



            ALU_DIV :begin
              dividend_1 = operand_a ;
              divisor_1 = operand_b ;
              if(divisor_1 == 0 )
                result = -1 ;

              else if ((dividend_1 == 64'h8000000000000000) && (divisor_1 == -1))
                result = 64'h8000000000000000;
              else begin
                quetiont_1 = dividend_1 / divisor_1 ;
                result = quetiont_1;
              end
          end
            ALU_DIVU :
                result = (operand_b == 0)
                       ? {XLEN{1'b1}}
                       : operand_a / operand_b;


          ALU_DIVW : begin
              dividend_2 = operand_a[31:0] ;
              divisor_2 = operand_b[31:0] ;
              if(divisor_2 == 0 )
                result = -1 ;

              else if ((dividend_2 == 32'h80000000) && (divisor_2 == -1))
                result = 64'hFFFFFFFF80000000;
              else begin
                quetiont_2 = dividend_2 / divisor_2 ;
                result = {{32{quetiont_2[31]}}, quetiont_2};
              end
          end


          ALU_DIVUW : begin
              devide_3  = ( (operand_a[31:0]) / (operand_b[31:0]));
              result = (operand_b == 0 ) ?  -1  : ( {{32{devide_3[31]}} , devide_3} );
          end
           ALU_REMU : begin
           result = (operand_b == 0 ) ?   (operand_a)
                : (64'((operand_a) % (operand_b)))  ;
           end

            ALU_REM :
                result = (operand_b == 0)
                       ? a_signed
                       : a_signed % b_signed;

            ALU_REMW :
                result = (operand_b == 0)
                       ?{{32{operand_a[31]}}, (operand_a[31:0])}
                       : $signed(64'($signed(operand_a[31:0]) % $signed(operand_b[31:0])));


            ALU_REMUW : begin 
                result = (operand_b == 0 ) ?  {{32{operand_a[31]}}, (operand_a[31:0])}
                : $signed(64'((operand_a[31:0]) % (operand_b[31:0])))  ;
            end
            ALU_PASS_A :
                result = operand_a;
            default :
                result = '0;

        endcase
    end

    assign zero_flag     = (result == 0);
    assign negative_flag = result[XLEN-1];

endmodule


